"""Postgres task queue: idempotent enqueue, SKIP LOCKED leasing, heartbeats, fenced completion, reaping.

Correctness rule: a result only counts if it is committed in the same transaction that flips the task
to 'succeeded', and that UPDATE matches only while we still hold the lease (owner + attempt number).
A worker whose lease expired and was re-leased elsewhere therefore commits nothing.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Iterable

import psycopg
from psycopg.types.json import Jsonb

from .errors import LeaseLost


@dataclass(frozen=True)
class Task:
    id: int
    role: str
    kind: str
    payload: dict
    attempts: int
    max_attempts: int
    concept_id: int | None
    run_id: int | None
    idempotency_key: str

    @classmethod
    def from_row(cls, r: dict) -> "Task":
        return cls(r["id"], r["role"], r["kind"], r["payload"], r["attempts"], r["max_attempts"],
                   r["concept_id"], r["run_id"], r["idempotency_key"])


def enqueue(conn: psycopg.Connection, role: str, kind: str, key: str, payload: dict | None = None,
            *, priority: int = 0, concept_id: int | None = None, run_id: int | None = None,
            max_attempts: int = 4, delay_s: float = 0) -> int | None:
    """Insert a task; returns its id, or None if a task with this idempotency key already exists."""
    row = conn.execute(
        """INSERT INTO tasks (role, kind, idempotency_key, payload, priority, concept_id, run_id,
                              max_attempts, not_before)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, now() + make_interval(secs => %s))
           ON CONFLICT (idempotency_key) DO NOTHING RETURNING id""",
        (role, kind, key, Jsonb(payload or {}), priority, concept_id, run_id, max_attempts, delay_s),
    ).fetchone()
    return row["id"] if row else None


LEASE_SQL = """
UPDATE tasks t
   SET status = 'leased', lease_owner = %(owner)s,
       lease_expires_at = now() + make_interval(secs => %(lease_s)s),
       attempts = t.attempts + 1, updated_at = now()
 WHERE t.id = (
         SELECT id FROM tasks
          WHERE status = 'queued'
            AND (role || '.' || kind) = ANY(%(kinds)s)
            AND not_before <= now()
          ORDER BY priority DESC, created_at, id
          FOR UPDATE SKIP LOCKED
          LIMIT 1)
RETURNING t.*"""


def lease(conn: psycopg.Connection, owner: str, kinds: Iterable[str], lease_s: float) -> Task | None:
    """Lease the next ready task whose 'role.kind' this worker can handle."""
    row = conn.execute(LEASE_SQL, {"owner": owner, "kinds": list(kinds), "lease_s": lease_s}).fetchone()
    return Task.from_row(row) if row else None


def heartbeat(conn: psycopg.Connection, task: Task, owner: str, lease_s: float) -> bool:
    """Extend our lease. False means we no longer own the task."""
    cur = conn.execute(
        """UPDATE tasks SET lease_expires_at = now() + make_interval(secs => %s), updated_at = now()
            WHERE id = %s AND status = 'leased' AND lease_owner = %s AND attempts = %s""",
        (lease_s, task.id, owner, task.attempts))
    return cur.rowcount == 1


def complete(conn: psycopg.Connection, task: Task, owner: str, result: dict | None = None,
             persist: Callable[[psycopg.Connection], Any] | None = None) -> None:
    """Persist side effects and mark succeeded atomically, fenced by the lease. Raises LeaseLost."""
    with conn.transaction():
        if persist is not None:
            persist(conn)
        cur = conn.execute(
            """UPDATE tasks SET status = 'succeeded', result = %s, lease_owner = NULL,
                      lease_expires_at = NULL, last_error = NULL, updated_at = now()
                WHERE id = %s AND status = 'leased' AND lease_owner = %s AND attempts = %s""",
            (Jsonb(result or {}), task.id, owner, task.attempts))
        if cur.rowcount != 1:
            raise LeaseLost(f"task {task.id} attempt {task.attempts} no longer leased by {owner}")


def fail(conn: psycopg.Connection, task: Task, owner: str, error: str, *, retryable: bool,
         delay_s: float = 0) -> str | None:
    """Record a failure. Retryable failures requeue until max_attempts, then go dead.
    Returns the new status, or None if we had already lost the lease."""
    row = conn.execute(
        """UPDATE tasks
              SET status = CASE WHEN %(retryable)s AND attempts < max_attempts THEN 'queued' ELSE 'dead' END,
                  not_before = now() + make_interval(secs => %(delay)s),
                  lease_owner = NULL, lease_expires_at = NULL, last_error = %(error)s, updated_at = now()
            WHERE id = %(id)s AND status = 'leased' AND lease_owner = %(owner)s AND attempts = %(attempt)s
        RETURNING status""",
        {"retryable": retryable, "delay": delay_s, "error": error[:4000], "id": task.id,
         "owner": owner, "attempt": task.attempts}).fetchone()
    return row["status"] if row else None


def reap(conn: psycopg.Connection) -> dict[str, int]:
    """Reclaim leases whose holder died. Returns counts of tasks requeued and killed."""
    rows = conn.execute(
        """UPDATE tasks
              SET status = CASE WHEN attempts >= max_attempts THEN 'dead' ELSE 'queued' END,
                  lease_owner = NULL, lease_expires_at = NULL,
                  last_error = coalesce(last_error, 'lease expired'),
                  not_before = now() + interval '1 minute', updated_at = now()
            WHERE status = 'leased' AND lease_expires_at < now()
        RETURNING status""").fetchall()
    return {"requeued": sum(r["status"] == "queued" for r in rows),
            "dead": sum(r["status"] == "dead" for r in rows)}


def dead(conn: psycopg.Connection, limit: int = 50) -> list[dict]:
    return conn.execute(
        """SELECT id, role, kind, idempotency_key, attempts, last_error, updated_at
             FROM tasks WHERE status = 'dead' ORDER BY updated_at DESC LIMIT %s""", (limit,)).fetchall()


def retry_dead(conn: psycopg.Connection, task_id: int | None = None, error_like: str | None = None) -> int:
    """Operator action: give dead tasks a fresh set of attempts."""
    if task_id is None and error_like is None:
        raise ValueError("pass a task id or an error pattern")
    cur = conn.execute(
        """UPDATE tasks SET status = 'queued', attempts = 0, not_before = now(), updated_at = now()
            WHERE status = 'dead' AND (%(id)s::bigint IS NULL OR id = %(id)s)
              AND (%(pat)s::text IS NULL OR last_error LIKE %(pat)s)""",
        {"id": task_id, "pat": error_like})
    return cur.rowcount


def backoff_seconds(attempt: int, base: float, cap: float) -> float:
    return min(cap, base * 2 ** max(0, attempt - 1))
