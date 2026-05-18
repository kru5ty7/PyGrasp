---
title: 08 - asyncpg
description: "asyncpg is a pure-async PostgreSQL driver written in Python and Cython — it is the fastest Python-to-PostgreSQL driver and is used as the backend for SQLAlchemy's async engine."
tags: [asyncpg, postgresql, async, driver, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# asyncpg

> asyncpg is Python's fastest PostgreSQL driver — it speaks the PostgreSQL wire protocol directly using asyncio, bypassing the DBAPI-2 interface entirely, and gives you binary-encoded results with no string parsing overhead.

---

## Quick Reference

**Core idea:**
- `asyncpg.connect()` opens a single async connection; `asyncpg.create_pool()` manages a connection pool
- `conn.fetch()` returns a list of `Record` objects; `conn.fetchrow()` returns one; `conn.fetchval()` returns a scalar
- `conn.execute()` runs a statement returning only a status string (INSERT, UPDATE, DELETE)
- Prepared statements are compiled and cached automatically per connection on first use
- Types are encoded and decoded in binary by asyncpg — no string parsing means better performance and accurate Python type mapping

**Tricky points:**
- asyncpg is not DBAPI-2 compliant — it does not use `.cursor()`, `.fetchmany()`, or `connection.commit()` in the traditional sense; transactions are explicit context managers
- `$1`, `$2` positional parameters replace the `%s` or `?` placeholders used in psycopg2 / SQLite
- `asyncpg.Record` behaves like a read-only dict-and-tuple hybrid — `row['column']` and `row[0]` both work
- Transactions require explicit management: `async with conn.transaction():` — there is no autocommit exception to be aware of from psycopg2
- Cannot be used directly in sync code — it requires a running asyncio event loop; use `psycopg2` for synchronous applications

---

## What It Is

Most Python database drivers are built on top of the DBAPI-2 specification (PEP 249), a standard interface that defines `.connect()`, `.cursor()`, `.execute()`, and `.fetchall()`. DBAPI-2 was designed in an era of synchronous code — every call blocks the thread until the database responds. psycopg2, the long-standing standard PostgreSQL driver, follows this model and cannot participate in an asyncio event loop without being wrapped in a thread pool executor.

asyncpg takes a different approach. It implements the PostgreSQL frontend/backend wire protocol directly in asyncio, with performance-critical parts written in Cython. There is no DBAPI-2 layer, no cursor object, and no string-encoded SQL values. Queries are sent as binary messages; results come back as binary-encoded data that asyncpg decodes directly into Python types — integers become Python `int`, timestamps become `datetime`, JSON columns become Python dicts. This binary encoding eliminates an entire parsing step that DBAPI-2 drivers pay on every row.

The driver was created by the EdgeDB team and was first released in 2016. It remains the reference implementation for how to write a high-performance async database driver in Python. Benchmarks consistently show asyncpg running 3–5 times faster than psycopg2 on equivalent query workloads, with the gap widening as result set sizes increase.

---

## How It Actually Works

Direct asyncpg usage covers both single connections and pool-managed connections. For production applications a pool is always preferable because it manages connection health, limits concurrency, and handles reconnection automatically.

```python
import asyncpg

async def main():
    # Single connection
    conn = await asyncpg.connect("postgresql://user:pass@localhost/mydb")
    rows = await conn.fetch("SELECT id, email FROM users WHERE active = $1", True)
    for row in rows:
        print(row["id"], row["email"])
    await conn.close()

    # Pool (preferred for applications)
    pool = await asyncpg.create_pool(
        "postgresql://user:pass@localhost/mydb",
        min_size=5,
        max_size=20,
    )
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM users WHERE id = $1", 42)
    await pool.close()
```

Transactions are managed as async context managers. If an exception is raised inside the block, the transaction rolls back automatically.

```python
async with conn.transaction():
    await conn.execute("INSERT INTO accounts(id, balance) VALUES($1, $2)", 1, 1000)
    await conn.execute("UPDATE accounts SET balance = balance - $1 WHERE id = $2", 100, 1)
```

When asyncpg is used as the driver behind SQLAlchemy's async engine, the connection URL scheme changes and the ORM handles all direct asyncpg calls internally — the application code sees only `AsyncSession`.

```python
from sqlalchemy.ext.asyncio import create_async_engine

engine = create_async_engine("postgresql+asyncpg://user:pass@localhost/mydb")
```

Prepared statements in asyncpg are cached per connection automatically. The first time a query string is sent, PostgreSQL parses and plans it and returns a statement handle. Subsequent calls with the same query string skip the parse step. This makes parameterized queries with varying values (but the same structure) significantly faster than ad-hoc string building.

---

## How It Connects

SQLAlchemy's async engine delegates all actual database communication to asyncpg under the `postgresql+asyncpg://` URL scheme, so understanding asyncpg helps when debugging low-level connection errors.

[[sqlalchemy-async|SQLAlchemy Async]]

Connection pooling concepts — `min_size`, `max_size`, pool health checks — apply to asyncpg's `create_pool()` as well as SQLAlchemy's pool configuration.

[[connection-pooling|Database Connection Pooling]]

---

## Common Misconceptions

Misconception 1: "I can use psycopg2 in an async FastAPI application without issues."
Reality: psycopg2 is a synchronous, blocking driver. Using it inside an async endpoint blocks the entire event loop thread for the duration of the database call, defeating the purpose of async and serializing all database operations. The correct choice is asyncpg (directly or via SQLAlchemy async), or psycopg3 which has native async support.

Misconception 2: "asyncpg's non-DBAPI-2 design makes it incompatible with SQLAlchemy."
Reality: SQLAlchemy's async dialect abstracts over the driver interface. The `postgresql+asyncpg` dialect translates between SQLAlchemy's internal query representation and asyncpg's API. Application code using SQLAlchemy ORM or Core is fully insulated from asyncpg's non-standard interface.

---

## Why It Matters in Practice

In async Python web applications backed by PostgreSQL, asyncpg is the standard driver choice — either used directly for maximum control or through SQLAlchemy's async engine. Understanding its connection and pool semantics, transaction management, and the `$1` positional parameter syntax prevents confusion when reading stack traces, debugging connection errors, or tuning pool parameters for high-throughput services.

---

## Interview Angle

Common question forms:
- "Why can't you use psycopg2 in an asyncio application?"
- "What driver does SQLAlchemy use for async PostgreSQL connections?"

Answer frame:
psycopg2 is synchronous and blocking — each call occupies the thread until the database responds, stalling the entire asyncio event loop. asyncpg implements the PostgreSQL wire protocol natively in asyncio with binary encoding, making it both async-safe and significantly faster. SQLAlchemy's async engine uses asyncpg via the `postgresql+asyncpg://` connection URL, so the ORM stays async-safe throughout.

---

## Related Notes

- [[sqlalchemy-async|SQLAlchemy Async]]
- [[sqlalchemy-orm|SQLAlchemy ORM]]
- [[connection-pooling|Database Connection Pooling]]
- [[async-await|Async/Await]]
- [[asyncio|asyncio]]
