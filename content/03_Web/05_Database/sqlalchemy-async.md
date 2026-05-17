---
title: 03 - SQLAlchemy Async
description: "`sqlalchemy.ext.asyncio` provides async versions of Engine, Session, and Connection — `create_async_engine()`, `AsyncSession`, and `async_sessionmaker`; required for FastAPI async handlers that query the database without blocking the event loop; uses `await` for all database operations."
tags: [sqlalchemy, async, AsyncSession, create_async_engine, asyncpg, aiosqlite, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# SQLAlchemy Async

> `sqlalchemy.ext.asyncio` provides async versions of Engine, Session, and Connection — `create_async_engine()`, `AsyncSession`, and `async_sessionmaker`; required for FastAPI async handlers that query the database without blocking the event loop; uses `await` for all database operations.

---

## Quick Reference

**Core idea:**
- `create_async_engine("postgresql+asyncpg://...")` — async engine using an async driver (`asyncpg` for PostgreSQL, `aiosqlite` for SQLite)
- `AsyncSession` — async version of `Session`; all query methods are `await`-able
- `async_sessionmaker(engine, class_=AsyncSession)` — factory for creating `AsyncSession` instances
- `async with AsyncSession(engine) as session:` — session lifecycle as async context manager
- All query execution methods are awaited: `await session.execute(stmt)`, `await session.commit()`

**Tricky points:**
- The driver must also be async — `asyncpg` (not `psycopg2`) for PostgreSQL; `aiosqlite` for SQLite; the sync drivers block the event loop
- `AsyncSession` does NOT support lazy loading — accessing a relationship (`user.posts`) after the session is closed raises `MissingGreenlet`; use `selectinload` or `joinedload` to eager-load before closing the session
- `await session.refresh(obj)` — reload object attributes from DB after commit (replaces `session.refresh()`)
- `scalars()` returns a `ScalarResult` that is not yet awaited — `result = await session.execute(stmt); items = result.scalars().all()` — note `.scalars()` is sync, `.execute()` is async
- Connection pool for async: `NullPool` is recommended for serverless/short-lived processes; default pool is fine for long-running servers

---

## What It Is

SQLAlchemy's synchronous `Session.execute()` blocks the OS thread while waiting for the database — this freezes the event loop in an async FastAPI handler. `AsyncSession` wraps the same SQLAlchemy logic but uses an async driver underneath, making database I/O awaitable.

The async API is nearly identical to the sync API — the main differences are: `await` on all I/O operations, no lazy loading (must eager-load relationships), and using `asyncpg`/`aiosqlite` drivers instead of `psycopg2`/`sqlite3`.

---

## How It Actually Works

Setup:
```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

DATABASE_URL = "postgresql+asyncpg://user:pass@localhost/mydb"

engine = create_async_engine(
    DATABASE_URL,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
)

AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
```

FastAPI dependency:
```python
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

Async queries:
```python
from sqlalchemy import select
from sqlalchemy.orm import selectinload

@app.get("/users/{id}")
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(User)
        .options(selectinload(User.posts))  # eager-load; no lazy loading in async
        .where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(404)
    return user

@app.post("/users", status_code=201)
async def create_user(data: UserCreate, db: AsyncSession = Depends(get_db)):
    user = User(email=data.email, name=data.name)
    db.add(user)
    await db.flush()     # sends INSERT to DB, generates id
    await db.refresh(user)  # loads generated id and defaults
    return user
```

---

## How It Connects

Async SQLAlchemy requires the same ORM model definitions as the sync version — only the session and engine differ.
[[orm-basics|ORM Basics]]

`get_db()` is the standard FastAPI `yield` dependency that provides a per-request `AsyncSession`.
[[database-sessions|Database Sessions in FastAPI]]

---

## Common Misconceptions

Misconception 1: "Using `async def` handler with sync `Session` is fine."
Reality: A sync `Session.execute()` call blocks the thread running the event loop — all other coroutines freeze until the DB query returns. This defeats async concurrency. You must use `AsyncSession` with an async driver in async FastAPI handlers.

Misconception 2: "`AsyncSession` supports lazy loading."
Reality: Lazy loading requires executing a new query when a relationship is accessed. In async context, this would require implicit `await` inside attribute access — Python doesn't support this. Any attempt to lazy-load raises `MissingGreenlet`. Always use `selectinload(Model.relationship)` in the query options.

---

## Why It Matters in Practice

Under concurrent load, async SQLAlchemy allows many requests to have in-flight database queries simultaneously. With sync SQLAlchemy in an async app:

```
Request 1: await route_handler() → session.execute() → BLOCKS event loop
                                                         ↑ all other requests wait here
```

With async SQLAlchemy:
```
Request 1: await route_handler() → await session.execute() → yields to event loop
Request 2: runs while Request 1 waits for DB
Request 3: runs while Request 1 waits for DB
```

---

## Interview Angle

Common question forms:
- "How do you use SQLAlchemy with FastAPI?"
- "Why can't you use psycopg2 with async FastAPI?"

Answer frame: `psycopg2` is synchronous — blocks the event loop. Use `asyncpg` driver + `create_async_engine` + `AsyncSession`. All execute/commit calls are awaited. No lazy loading in async — use `selectinload`/`joinedload` in the query. `get_db()` yield dependency provides per-request `AsyncSession` with auto-commit/rollback.

---

## Related Notes

- [[orm-basics|ORM Basics]]
- [[sqlalchemy-core|SQLAlchemy Core]]
- [[database-sessions|Database Sessions in FastAPI]]
- [[fastapi-dependencies|FastAPI Dependencies]]
