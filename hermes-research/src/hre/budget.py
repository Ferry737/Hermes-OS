"""LLM spend control: reserve before a call, settle with real usage after, release on failure.

Reservations are serialized with a transaction-scoped advisory lock, so concurrent workers can never
jointly overshoot a cap. Caps apply per day, per calendar month, and per concept (lifetime).
"""
from __future__ import annotations

from dataclasses import dataclass

import psycopg

from .errors import BudgetExceeded

LOCK_KEY = 4242
COUNTED = "status IN ('reserved', 'settled')"
AMOUNT = "coalesce(cost_usd, est_cost_usd)"


@dataclass(frozen=True)
class Caps:
    daily_usd: float
    monthly_usd: float
    per_concept_usd: float

    @classmethod
    def from_config(cls, cfg: dict) -> "Caps":
        b = cfg["llm"]["budget"]
        return cls(float(b["daily_usd"]), float(b["monthly_usd"]), float(b["per_concept_usd"]))


def cost_usd(pricing: dict, model: str, *, input_tokens: int = 0, output_tokens: int = 0,
             cache_read_tokens: int = 0, cache_write_tokens: int = 0,
             cache_multipliers: dict | None = None, batch: bool = False, batch_discount: float = 0.5) -> float:
    """Dollar cost of one call. input_tokens excludes cached tokens, matching the API's usage fields."""
    if model not in pricing:
        raise KeyError(f"no pricing for model {model!r}; add it to llm.pricing_usd_per_mtok")
    p = pricing[model]
    m = cache_multipliers or {"read": 0.10, "write": 1.25}
    total = (input_tokens * p["input"] + cache_read_tokens * p["input"] * m["read"]
             + cache_write_tokens * p["input"] * m["write"] + output_tokens * p["output"]) / 1_000_000
    return total * (1 - batch_discount) if batch else total


def spent(conn: psycopg.Connection) -> dict[str, float]:
    row = conn.execute(
        f"""SELECT coalesce(sum({AMOUNT}) FILTER (WHERE created_at >= date_trunc('day', now())), 0) AS today,
                   coalesce(sum({AMOUNT}) FILTER (WHERE created_at >= date_trunc('month', now())), 0) AS month
              FROM llm_calls WHERE {COUNTED}""").fetchone()
    return {"today": float(row["today"]), "month": float(row["month"])}


def reserve(conn: psycopg.Connection, caps: Caps, *, agent: str, model: str, prompt_version: str,
            est_cost: float, task_id: int | None = None, concept_id: int | None = None,
            batch: bool = False) -> int:
    """Reserve est_cost against every cap or raise BudgetExceeded. Returns the llm_calls row id."""
    with conn.transaction():
        conn.execute("SELECT pg_advisory_xact_lock(%s)", (LOCK_KEY,))
        s = spent(conn)
        if s["today"] + est_cost > caps.daily_usd:
            raise BudgetExceeded(f"daily cap ${caps.daily_usd:.2f} (spent ${s['today']:.2f})")
        if s["month"] + est_cost > caps.monthly_usd:
            raise BudgetExceeded(f"monthly cap ${caps.monthly_usd:.2f} (spent ${s['month']:.2f})")
        if concept_id is not None:
            c = conn.execute(f"SELECT coalesce(sum({AMOUNT}), 0) AS v FROM llm_calls "
                             f"WHERE {COUNTED} AND concept_id = %s", (concept_id,)).fetchone()["v"]
            if float(c) + est_cost > caps.per_concept_usd:
                raise BudgetExceeded(f"per-concept cap ${caps.per_concept_usd:.2f} (spent ${float(c):.2f})")
        return conn.execute(
            """INSERT INTO llm_calls (task_id, concept_id, agent, model, prompt_version, est_cost_usd, batch)
               VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id""",
            (task_id, concept_id, agent, model, prompt_version, est_cost, batch)).fetchone()["id"]


def settle(conn: psycopg.Connection, call_id: int, *, cost: float, input_tokens: int, output_tokens: int,
           cache_read_tokens: int = 0, cache_write_tokens: int = 0, stop_reason: str | None = None,
           latency_ms: int | None = None) -> None:
    conn.execute(
        """UPDATE llm_calls SET status = 'settled', cost_usd = %s, input_tokens = %s, output_tokens = %s,
                  cache_read_tokens = %s, cache_write_tokens = %s, stop_reason = %s, latency_ms = %s
            WHERE id = %s""",
        (cost, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, stop_reason, latency_ms,
         call_id))


def release(conn: psycopg.Connection, call_id: int) -> None:
    """The call never billed (connection error, 5xx before output): stop counting the reservation."""
    conn.execute("UPDATE llm_calls SET status = 'released' WHERE id = %s AND status = 'reserved'", (call_id,))
