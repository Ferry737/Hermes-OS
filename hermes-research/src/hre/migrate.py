"""Forward-only SQL migrations, applied in filename order and recorded in schema_migrations."""
from __future__ import annotations

from pathlib import Path

import psycopg

from .config import ROOT

MIGRATIONS = ROOT / "migrations"


def migrate(conn: psycopg.Connection, directory: Path = MIGRATIONS) -> list[str]:
    conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations "
                 "(name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())")
    applied = []
    with conn.transaction():
        conn.execute("SELECT pg_advisory_xact_lock(4241)")   # one migrator at a time
        done = {r["name"] for r in conn.execute("SELECT name FROM schema_migrations")}
        for path in sorted(directory.glob("*.sql")):
            if path.name in done:
                continue
            conn.execute(path.read_text())
            conn.execute("INSERT INTO schema_migrations (name) VALUES (%s)", (path.name,))
            applied.append(path.name)
    return applied
