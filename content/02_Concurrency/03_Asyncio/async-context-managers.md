---
title: 12 - Async Context Managers
description: "Async context managers implement `__aenter__` and `__aexit__` coroutine methods — used with `async with`; they allow awaiting during setup and teardown (database connections, locks, HTTP sessions); `@asynccontextmanager` from `contextlib` converts an async generator to a context manager."
tags: [async-context-managers, __aenter__, __aexit__, async-with, asynccontextmanager, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Async Context Managers

> Async context managers implement `__aenter__` and `__aexit__` coroutine methods — used with `async with`; they allow awaiting during setup and teardown (database connections, locks, HTTP sessions); `@asynccontextmanager` from `contextlib` converts an async generator to a context manager.

---

## Quick Reference

**Core idea:**
- `async with cm as value:` — calls `await cm.__aenter__()` on entry, `await cm.__aexit__(...)` on exit
- `__aenter__(self)` — coroutine; its return value is bound to `as value`
- `__aexit__(self, exc_type, exc_val, exc_tb)` — coroutine; return `True` to suppress the exception
- `@contextlib.asynccontextmanager` — decorate an async generator function; `yield` is the entry point
- Common uses: database sessions (`async with db.session() as session:`), HTTP clients (`async with aiohttp.ClientSession() as session:`), asyncio locks (`async with lock:`)

**Tricky points:**
- `async with` requires an async context; it cannot be used in a synchronous function — use regular `with` there
- `asyncio.Lock`, `asyncio.Semaphore` support `async with` — they must be awaited; `threading.Lock` does not support `async with`
- `@asynccontextmanager` wraps an `async def` generator function — the generator must have exactly one `yield` and must be defined with `async def`
- Nesting async context managers: `async with A() as a, B() as b:` is syntactic sugar for nested `async with` blocks; they are entered left-to-right and exited right-to-left
- An async context manager created outside an event loop (at module level) may not work correctly if the event loop has not started yet

---

## What It Is

Think of the difference between renting a car (synchronous) and renting a private jet (async). Renting a car: walk in, sign, get keys, done — no waiting. Renting a private jet: request, wait for availability confirmation, wait for preparation, then fly; on return, wait for post-flight check, then sign off. The setup and teardown involve waiting. An async context manager is for the jet rental scenario: `async with jet_rental() as jet:` awaits the availability check on entry, and awaits the post-flight inspection on exit.

The need arises with database connections, network sessions, and locks. Opening a database connection involves an async I/O operation (network handshake). Closing it involves flushing pending writes. These operations must be awaitable; a regular context manager's `__enter__`/`__exit__` cannot await. `__aenter__`/`__aexit__` are coroutines, so `async with` can await them properly.

---

## How It Actually Works

`async with expr as val:` desugars to:

```python
_ctx = expr
val = await _ctx.__aenter__()
try:
    body
except:
    if not await _ctx.__aexit__(*sys.exc_info()):
        raise
else:
    await _ctx.__aexit__(None, None, None)
```

A minimal async context manager:

```python
class AsyncDBConnection:
    async def __aenter__(self):
        self.conn = await open_db_connection()
        return self.conn
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.conn.close()
        return False  # do not suppress exceptions
```

`@asynccontextmanager`:

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def managed_session(db_url):
    session = await create_session(db_url)
    try:
        yield session
    finally:
        await session.close()

async def main():
    async with managed_session(DB_URL) as session:
        await session.execute(...)
```

`asyncio.Lock` as an async context manager:
```python
lock = asyncio.Lock()

async def critical_section():
    async with lock:
        # Only one coroutine at a time
        await shared_resource_operation()
```

---

## How It Connects

Async context managers are the async counterpart to regular context managers — they use `__aenter__`/`__aexit__` instead of `__enter__`/`__exit__`.
[[context-managers|Context Managers]]

`asyncio.Lock` and `asyncio.Semaphore` implement the async context manager protocol — they are the primary synchronization primitives for coroutines.
[[asyncio-locks|Asyncio Locks]]

---

## Common Misconceptions

Misconception 1: "Regular context managers can be used with `async with`."
Reality: `async with` requires `__aenter__` and `__aexit__` — a regular context manager with `__enter__`/`__exit__` cannot be used directly with `async with`. Use `contextlib.asynccontextmanager` to wrap synchronous context managers for use in async code, or just use regular `with` for synchronous resources.

Misconception 2: "`@asynccontextmanager` works with regular (non-async) generator functions."
Reality: `@asynccontextmanager` requires an `async def` generator function (one that uses both `async def` and `yield`). A regular generator function decorated with `@asynccontextmanager` raises `AttributeError` or `TypeError` because it lacks the async generator protocol.

---

## Why It Matters in Practice

The aiohttp client session is the canonical example:
```python
async with aiohttp.ClientSession() as session:
    async with session.get(url) as response:
        data = await response.json()
```

Both levels are async context managers — the session (awaiting connection setup/teardown) and the response (awaiting the response headers).

Database transactions:
```python
async with db.transaction():
    await db.execute("INSERT ...")
    await db.execute("UPDATE ...")
# Transaction committed on exit, rolled back on exception
```

The `__aexit__` method decides whether to commit or rollback based on whether an exception occurred.

---

## Interview Angle

Common question forms:
- "What is an async context manager?"
- "How do you create one without writing a full class?"

Answer frame: Async context managers implement `__aenter__` (coroutine returning the resource) and `__aexit__` (coroutine for cleanup). Used with `async with`. Required when setup/teardown involves async operations (network connections, async locks). Create without a class using `@contextlib.asynccontextmanager` on an `async def` generator — code before `yield` is `__aenter__`, code after is `__aexit__`. `asyncio.Lock` and `asyncio.Semaphore` support `async with`.

---

## Related Notes

- [[context-managers|Context Managers]]
- [[contextlib|contextlib]]
- [[asyncio-locks|Asyncio Locks]]
- [[async-await|Async and Await]]
