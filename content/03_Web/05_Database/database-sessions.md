---
title: 05 - Database Sessions
description: "In FastAPI, a database session is opened per request via a `yield` dependency — `async with AsyncSession(engine) as session: yield session` provides a fresh session, auto-commits on success, and rolls back on exceptions; the session is closed when the request ends."
tags: [fastapi, database-session, AsyncSession, yield-dependency, transaction, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Database Sessions in FastAPI

> In FastAPI, a database session is opened per request via a `yield` dependency — `async with AsyncSession(engine) as session: yield session` provides a fresh session, auto-commits on success, and rolls back on exceptions; the session is closed when the request ends.

---

## Quick Reference

**Core idea:**
- One session per request — opens at the start of request handling, closes after the response is sent
- `yield` dependency: code before `yield` = setup (open session), code after = teardown (close/rollback)
- `await session.commit()` — commit after successful handler execution
- `await session.rollback()` — rollback on exception; prevents partial writes
- `expire_on_commit=False` — response model can access session attributes after commit (prevents lazy-load errors after commit)

**Tricky points:**
- Without `expire_on_commit=False`, accessing an ORM object's attributes after `commit()` triggers a re-fetch — but the session is already closed in a `yield` dependency; this raises `DetachedInstanceError`
- Nested transactions (`session.begin_nested()`) create savepoints — rollback to savepoint without rolling back the outer transaction; useful for nested operations that may fail
- Session isolation level: by default, SQLAlchemy uses the database's default (usually `READ COMMITTED`) — multiple reads in the same session may see different snapshots if another transaction commits between them
- Do NOT share a single session across requests — SQLAlchemy sessions are not thread-safe and not designed for concurrent use
- `session.flush()` vs `session.commit()`: `flush()` sends SQL to DB (assigns auto-increment IDs) but stays in the transaction; `commit()` finalizes and makes changes visible to other transactions

---

## What It Is

A database session is the unit of work for database interactions. It tracks changes (new objects, modifications, deletions) and sends them to the database in a coordinated transaction. In a web application, a request typically maps to one transaction: all DB operations in the handler either succeed together or roll back together.

FastAPI's `yield` dependency is the idiomatic way to manage this lifecycle — setup before the handler, teardown after, with exception handling built in.

---

## How It Actually Works

Standard async session dependency:
```python
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from typing import AsyncGenerator

engine = create_async_engine(DATABASE_URL, pool_pre_ping=True)
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,  # prevent DetachedInstanceError after commit
)

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

Handler using the session:
```python
@app.post("/users", status_code=201, response_model=UserResponse)
async def create_user(
    data: UserCreate,
    db: AsyncSession = Depends(get_db),
):
    user = User(email=data.email, name=data.name)
    db.add(user)
    await db.flush()      # generate the user.id before returning
    await db.refresh(user)  # ensure all defaults are loaded
    return user
    # After return: get_db's finally block runs → session.commit() → session.close()
```

Multiple operations in one transaction:
```python
@app.post("/transfer")
async def transfer_funds(
    transfer: TransferRequest,
    db: AsyncSession = Depends(get_db),
):
    sender = await db.get(Account, transfer.from_account_id)
    receiver = await db.get(Account, transfer.to_account_id)
    
    if sender.balance < transfer.amount:
        raise HTTPException(400, "Insufficient funds")
    
    sender.balance -= transfer.amount
    receiver.balance += transfer.amount
    # Both changes committed atomically — or both rolled back on exception
    # get_db handles commit in its finally block
```

Testing with session override:
```python
async def get_test_db():
    async with TestAsyncSession() as session:
        yield session
        await session.rollback()  # always rollback in tests; never persist

app.dependency_overrides[get_db] = get_test_db
```

---

## How It Connects

`get_db()` uses SQLAlchemy's `AsyncSession` — understanding async SQLAlchemy explains why `await` is needed on all operations.
[[sqlalchemy-async|SQLAlchemy Async]]

`yield` dependencies are a FastAPI pattern where teardown runs after the response — the same pattern applies to any resource that needs setup/teardown.
[[fastapi-dependencies|FastAPI Dependencies]]

---

## Common Misconceptions

Misconception 1: "You can access ORM attributes after the session closes."
Reality: By default (`expire_on_commit=True`), all attribute accesses after commit trigger a new SELECT. If the session is closed, this raises `DetachedInstanceError`. Solution: `expire_on_commit=False` — attributes are cached from the last load and remain accessible after commit.

Misconception 2: "A single global `session` object works for concurrent requests."
Reality: SQLAlchemy sessions are NOT thread-safe and NOT designed for concurrent coroutines. Each request must have its own session — which is exactly what the `yield` dependency provides.

---

## Why It Matters in Practice

The request-session-transaction equivalence:
```
HTTP Request → dependency creates session → handler runs queries → 
   success: commit → close session → send response
   exception: rollback → close session → send error response
```

This ensures atomicity: a handler that raises an exception after partially modifying the database leaves no partial changes. The rollback in the `except` block guarantees a clean state.

---

## Interview Angle

Common question forms:
- "How do you manage database sessions in FastAPI?"
- "How do you ensure a transaction is rolled back on error?"

Answer frame: `yield` dependency — `async with AsyncSession(engine) as session: yield session`. Before `yield`: open session. After `yield` (in `finally` / `except`): commit on success, rollback on exception. One session per request. `expire_on_commit=False` prevents `DetachedInstanceError`. `dependency_overrides` replaces in tests for rollback after each test.

---

## Related Notes

- [[sqlalchemy-async|SQLAlchemy Async]]
- [[fastapi-dependencies|FastAPI Dependencies]]
- [[orm-basics|ORM Basics]]
- [[alembic|Alembic Migrations]]
