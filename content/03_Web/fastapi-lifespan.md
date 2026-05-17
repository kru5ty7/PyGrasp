---
title: Lifespan Events
description: "FastAPI lifespan events run code at application startup and shutdown — the `@asynccontextmanager`-based `lifespan` parameter replaces the deprecated `on_event` handlers; used for initializing database connection pools, loading ML models, and connecting to Redis."
tags: [fastapi, lifespan, startup, shutdown, asynccontextmanager, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Lifespan Events

> FastAPI lifespan events run code at application startup and shutdown — the `@asynccontextmanager`-based `lifespan` parameter replaces the deprecated `on_event` handlers; used for initializing database connection pools, loading ML models, and connecting to Redis.

---

## Quick Reference

**Core idea:**
- `lifespan` parameter on `FastAPI()`: takes an async context manager that yields once
- Code before `yield` runs at startup; code after `yield` runs at shutdown
- `state` object: store shared resources on `app.state` during lifespan; access in handlers via `request.app.state`
- Old pattern (deprecated): `@app.on_event("startup")` / `@app.on_event("shutdown")` — still works but avoid in new code
- Lifespan runs once per process — not per request

**Tricky points:**
- If startup code raises, the server does not start — fail fast on initialization errors (can't connect to DB, can't load model)
- Shutdown code runs when the server receives `SIGTERM` — guaranteed to run for graceful shutdown; not guaranteed on `SIGKILL`
- Resources created in lifespan are shared across all requests — they must be thread-safe or async-safe
- SQLAlchemy `engine` / `sessionmaker` are created once in lifespan; individual sessions are per-request (via `Depends(get_db)`)
- For tests: use `TestClient` as an async context manager — it triggers lifespan events; or use `lifespan_manager` from `asgi-lifespan`

---

## What It Is

Lifespan events solve the "how do I initialize shared resources once when the server starts" problem. Database connection pools, Redis clients, ML model weights — these should be created once at startup and shared across all request handlers, then cleaned up gracefully at shutdown.

Without lifespan, you'd either initialize these in module-level globals (hard to test, non-async) or recreate them per request (wasteful). Lifespan provides a clean async context for initialization with guaranteed cleanup.

---

## How It Actually Works

Modern lifespan pattern:
```python
from contextlib import asynccontextmanager
from fastapi import FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    app.state.db_pool = await create_db_pool(DATABASE_URL)
    app.state.redis = await aioredis.from_url(REDIS_URL)
    print("Server started")
    
    yield  # Server is running; handle requests here
    
    # Shutdown
    await app.state.db_pool.close()
    await app.state.redis.close()
    print("Server shutting down")

app = FastAPI(lifespan=lifespan)

# Access in handlers:
@app.get("/health")
async def health(request: Request):
    await request.app.state.redis.ping()
    return {"status": "ok"}
```

ML model loading:
```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Load model once at startup (expensive)
    loop = asyncio.get_event_loop()
    app.state.model = await loop.run_in_executor(None, load_large_model, MODEL_PATH)
    
    yield
    
    # Cleanup not needed for in-memory model
    del app.state.model

app = FastAPI(lifespan=lifespan)

@app.post("/predict")
async def predict(data: InputData, request: Request):
    model = request.app.state.model
    result = model.predict(data.features)
    return {"prediction": result}
```

Accessing state via dependency:
```python
def get_db_pool(request: Request) -> AsyncConnectionPool:
    return request.app.state.db_pool

@app.get("/users")
async def list_users(pool: AsyncConnectionPool = Depends(get_db_pool)):
    async with pool.connection() as conn:
        return await conn.execute("SELECT * FROM users").fetchall()
```

---

## How It Connects

Lifespan uses `@asynccontextmanager` — the same pattern used by `@asynccontextmanager` in `contextlib` for `async with` blocks.
[[async-context-managers|Async Context Managers]]

Database sessions are per-request (via `Depends`) but the connection pool is created once in lifespan — understanding the difference is key.
[[database-sessions|Database Sessions in FastAPI]]

---

## Common Misconceptions

Misconception 1: "`@app.on_event('startup')` is equivalent to lifespan."
Reality: `@app.on_event` is deprecated and split into separate startup/shutdown handlers — there's no shared context between them. `lifespan` uses a single context manager where you can share state via local variables (not just `app.state`). Use `lifespan` in all new code.

Misconception 2: "Lifespan events run per request."
Reality: Lifespan events run once per process lifecycle — startup at boot, shutdown at graceful stop. Resources initialized in lifespan persist for the entire lifetime of the process and are shared across all requests.

---

## Why It Matters in Practice

The lifespan pattern is essential for any production FastAPI application:
- Database connection pool (one pool, many connections checked out per request)
- Redis client (one client, used for caching/pub-sub)
- HTTP client session (one `aiohttp.ClientSession` for outgoing requests)
- ML models (load once into memory)
- Background workers (start async worker tasks on startup, cancel on shutdown)

---

## Interview Angle

Common question forms:
- "How do you initialize a database connection pool in FastAPI?"
- "What are startup events in FastAPI?"

Answer frame: Use `lifespan` context manager — code before `yield` is startup, after is shutdown. Store shared resources on `app.state`. Access in handlers via `request.app.state` or a `Depends()` wrapper. Old `@app.on_event` is deprecated. Fails at startup = server doesn't start (fail-fast). Lifespan runs once per process.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[async-context-managers|Async Context Managers]]
- [[database-sessions|Database Sessions in FastAPI]]
- [[fastapi-dependencies|FastAPI Dependencies]]
