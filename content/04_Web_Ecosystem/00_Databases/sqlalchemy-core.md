---
title: 02 - SQLAlchemy Core
description: "SQLAlchemy Core is the SQL expression language layer  -  constructs SQL as Python objects (`select()`, `insert()`, `update()`, `delete()`); works with `Engine` and `Connection`; more explicit than ORM but less than raw SQL strings; used when you need full control over queries."
tags: [sqlalchemy, core, engine, connection, select, insert, expression-language, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# SQLAlchemy Core

> SQLAlchemy Core is the SQL expression language layer  -  constructs SQL as Python objects (`select()`, `insert()`, `update()`, `delete()`); works with `Engine` and `Connection`; more explicit than ORM but less than raw SQL strings; used when you need full control over queries.

---

## Quick Reference

**Core idea:**
- `engine = create_engine("postgresql+psycopg2://user:pass@host/db")`  -  connection factory; manages pool
- `with engine.connect() as conn:`  -  get a connection from the pool
- `conn.execute(select(users_table))`  -  run a query; returns `Result`
- `Table("users", metadata, Column("id", Integer, primary_key=True), ...)`  -  explicit table definition
- `select(User).where(User.age > 18)`  -  ORM-level Core (using mapped class attributes)

**Tricky points:**
- `engine.connect()` begins a transaction implicitly in SQLAlchemy 2.0  -  commit with `conn.commit()` or use `engine.begin()` context manager (auto-commits on exit, rolls back on exception)
- `create_engine()` does NOT connect immediately  -  the pool is lazy; first connection is made on first query
- `pool_size`, `max_overflow`, `pool_timeout`  -  pool settings that must be tuned for production; default pool_size=5 may be too small under load
- `text("SELECT * FROM users WHERE id = :id")` + `{"id": 42}`  -  raw SQL with bound parameters; still safe from SQL injection
- Connection pool is per `Engine` instance  -  create one `Engine` for the application lifetime; don't create per request

---

## What It Is

SQLAlchemy has two layers: Core (SQL expression language) and ORM (object mapping). Core is the foundation  -  it provides a Pythonic way to build SQL queries without using raw strings, while remaining close to SQL semantics. The ORM builds on Core.

Core is appropriate when: you're working with large datasets that don't fit the ORM's row-by-row model, writing complex queries (CTEs, window functions), doing bulk inserts, or interacting with tables that don't have ORM models.

---

## How It Actually Works

Engine setup and connection:
```python
from sqlalchemy import create_engine, text

# Connection URL format: dialect+driver://user:pass@host:port/dbname
engine = create_engine(
    "postgresql+psycopg2://user:pass@localhost/mydb",
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,  # test connections before use (handles stale connections)
    echo=False,          # log SQL to stdout if True (development only)
)

# Connection as context manager (auto-rollback on exception):
with engine.connect() as conn:
    result = conn.execute(text("SELECT version()"))
    print(result.fetchone())
    conn.commit()

# Or engine.begin() for automatic commit:
with engine.begin() as conn:
    conn.execute(text("INSERT INTO logs (msg) VALUES (:msg)"), {"msg": "hello"})
    # commits automatically on successful exit
```

Core table definition and queries:
```python
from sqlalchemy import Table, Column, Integer, String, MetaData, select, insert, update, delete

metadata = MetaData()
users = Table("users", metadata,
    Column("id", Integer, primary_key=True),
    Column("email", String(255), unique=True),
    Column("name", String(100)),
)

with engine.begin() as conn:
    # Insert
    conn.execute(insert(users).values(email="alice@example.com", name="Alice"))
    
    # Select
    stmt = select(users).where(users.c.email == "alice@example.com")
    row = conn.execute(stmt).fetchone()
    print(row.email, row.name)
    
    # Update
    conn.execute(update(users).where(users.c.id == 1).values(name="Alice Smith"))
    
    # Delete
    conn.execute(delete(users).where(users.c.id == 1))
```

Bulk insert (much faster than per-row ORM adds):
```python
with engine.begin() as conn:
    conn.execute(
        insert(users),
        [{"email": f"user{i}@example.com", "name": f"User {i}"} for i in range(1000)]
    )
```

---

## How It Connects

SQLAlchemy Core is the foundation that the ORM builds on  -  ORM models emit Core-level SQL expressions under the hood.
[[orm-basics|ORM Basics]]

For async applications (FastAPI), use `create_async_engine` from `sqlalchemy.ext.asyncio` instead of the sync `create_engine`.
[[sqlalchemy-async|SQLAlchemy Async]]

---

## Common Misconceptions

Misconception 1: "`create_engine` opens a database connection."
Reality: `create_engine` creates a connection pool factory  -  no connection is made until the first query. The `pool_size` defines the maximum idle connections kept in the pool; actual connections are checked out on demand.

Misconception 2: "You must choose either Core or ORM."
Reality: Core and ORM are used together. ORM models for domain logic and simple queries; Core expressions for bulk operations, complex queries, or performance-sensitive code paths. You can mix them in the same application.

---

## Why It Matters in Practice

Performance-critical bulk operations use Core instead of ORM:
```python
# ORM way: slow for large datasets (one object created per row)
users = session.scalars(select(User)).all()

# Core way: fast (no Python objects created, raw tuples)
with engine.connect() as conn:
    result = conn.execute(select(users_table))
    for row in result:  # streams results, doesn't load all into memory
        process(row)
```

For 100k+ row exports, Core streaming is orders of magnitude faster than loading all ORM objects.

---

## Interview Angle

Common question forms:
- "What is the difference between SQLAlchemy Core and ORM?"
- "How do you connect to a database with SQLAlchemy?"

Answer frame: **Core** = SQL expression language (build queries as Python objects); **ORM** = maps Python classes to tables. `create_engine(url)` creates the connection pool (lazy  -  no immediate connection). `engine.begin()` for auto-committing transactions. Core is faster for bulk operations; ORM is better for domain object modeling. `pool_pre_ping=True` for stale connection handling in production.

---

## Related Notes

- [[orm-basics|ORM Basics]]
- [[sqlalchemy-async|SQLAlchemy Async]]
- [[alembic|Alembic Migrations]]
- [[database-sessions|Database Sessions in FastAPI]]
