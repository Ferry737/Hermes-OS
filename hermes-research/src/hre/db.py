"""Database connections. Every connection is autocommit; multi-statement work uses conn.transaction()."""
from __future__ import annotations

import os

import psycopg
from psycopg.rows import dict_row


def dsn() -> str:
    if os.environ.get("HRE_DSN"):
        return os.environ["HRE_DSN"]
    password = os.environ.get("HRE_DB_PASSWORD") or os.environ.get("POSTGRES_PASSWORD", "")
    return psycopg.conninfo.make_conninfo(
        host=os.environ.get("HRE_DB_HOST", "localhost"),
        port=os.environ.get("HRE_DB_PORT", "5432"),
        dbname=os.environ.get("HRE_DB_NAME", "hermes"),
        user=os.environ.get("HRE_DB_USER", "hre"),
        password=password,
        application_name=os.environ.get("HRE_APP_NAME", "hre"),
    )


def connect(conninfo: str | None = None) -> psycopg.Connection:
    return psycopg.connect(conninfo or dsn(), autocommit=True, row_factory=dict_row)
