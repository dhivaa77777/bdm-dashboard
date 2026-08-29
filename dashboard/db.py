"""Database connection and query execution for the Olist dashboard.

This module replaces the simple ``query()`` function in the original dashboard
with a cleaner separation of concerns.  All connections acquire
``SUPABASE_DATABASE_URL`` from the environment (via ``python-dotenv``).

The design keeps responsibilities separated so that the UI layer never
constructs SQL strings directly — that work is delegated to ``queries.py``.
"""

import os
from contextlib import contextmanager
from dotenv import load_dotenv
import psycopg2
from psycopg2.extras import RealDictCursor

load_dotenv()

_DATABASE_URL = os.environ.get("SUPABASE_DATABASE_URL")
if not _DATABASE_URL:
    raise RuntimeError("SUPABASE_DATABASE_URL is not set (see .env.example).")


@contextmanager
def get_connection():
    """Yield a psycopg2 connection with RealDictCursor."""
    conn = psycopg2.connect(_DATABASE_URL, cursor_factory=RealDictCursor)
    try:
        yield conn
    finally:
        conn.close()


def run_query(sql: str, params: tuple = None):
    """Execute a SELECT query and return list of dicts."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            return cur.fetchall()


def run_scalar(sql: str, params: tuple = None):
    """Execute a query returning a single scalar value."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            row = cur.fetchone()
            return row[0] if row else None