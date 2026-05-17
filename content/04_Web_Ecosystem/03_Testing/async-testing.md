---
title: 06 - Async Testing
description: "`pytest-asyncio` enables async test functions — `async def test_something()` runs in an event loop; `@pytest.mark.asyncio` marks a test async (or use `asyncio_mode = 'auto'`); `AsyncClient` from `httpx` tests FastAPI async endpoints with async syntax."
tags: [pytest-asyncio, async-testing, AsyncClient, httpx, asyncio_mode, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Async Testing

> `pytest-asyncio` enables async test functions — `async def test_something()` runs in an event loop; `@pytest.mark.asyncio` marks a test async (or use `asyncio_mode = 'auto'`); `AsyncClient` from `httpx` tests FastAPI async endpoints with async syntax.

---

## Quick Reference

**Core idea:**
- `pip install pytest-asyncio httpx` — required packages for async FastAPI testing
- `asyncio_mode = "auto"` in `pytest.ini` — auto-detect async test functions; no per-test decorator needed
- `async def test_example():` — async test function
- `AsyncClient(app=app, base_url="http://test")` — async HTTP client; use as `async with AsyncClient(...) as client:`
- Async fixtures: `@pytest.fixture` on `async def` function (requires `asyncio_mode = "auto"` or explicit `@pytest_asyncio.fixture`)

**Tricky points:**
- `asyncio_mode = "auto"` (pytest.ini option) is the recommended configuration — without it, every async test needs `@pytest.mark.asyncio`
- Event loop scope: by default, each test gets a new event loop — session-scoped async fixtures require `loop_scope="session"` in newer pytest-asyncio
- `AsyncClient` triggers FastAPI's lifespan events — `async with AsyncClient(app=app, ...)` is the preferred way to test with lifespan (DB pool init, Redis connect)
- `TestClient` (sync) wraps the async app in a synchronous interface — fine for most tests; `AsyncClient` is needed when the test itself needs to be async (e.g., async fixtures, await in test body)
- Mixing sync and async fixtures: sync fixtures can be used in async tests; async fixtures cannot be used in sync tests

---

## What It Is

When your FastAPI handlers are `async def`, your integration tests may also need to be async — especially when they share async fixtures (like an `AsyncSession`) or use `AsyncClient`. `pytest-asyncio` is the plugin that enables this: it wraps async test functions in an event loop, making `await` work in test bodies.

The typical setup: `asyncio_mode = "auto"` in `pyproject.toml` so all `async def test_*` functions run automatically, and `AsyncClient` as the HTTP client in a module-scoped or session-scoped async fixture.

---

## How It Actually Works

`pyproject.toml` configuration:
```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

Async test with `AsyncClient`:
```python
import pytest
from httpx import AsyncClient
from myapp.main import app

@pytest.fixture
async def async_client():
    async with AsyncClient(app=app, base_url="http://test") as client:
        yield client
        # lifespan shutdown runs when context manager exits

async def test_create_user(async_client):
    response = await async_client.post(
        "/users",
        json={"email": "alice@example.com", "name": "Alice"},
    )
    assert response.status_code == 201
    assert response.json()["email"] == "alice@example.com"
```

Async test with async DB session:
```python
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from myapp.dependencies import get_db

@pytest.fixture(scope="session")
def engine():
    return create_async_engine("sqlite+aiosqlite:///:memory:")

@pytest.fixture
async def db_session(engine):
    async with AsyncSession(engine) as session:
        yield session
        await session.rollback()

@pytest.fixture
async def client(db_session):
    async def override_db():
        yield db_session
    
    app.dependency_overrides[get_db] = override_db
    async with AsyncClient(app=app, base_url="http://test") as c:
        yield c
    app.dependency_overrides = {}

async def test_list_empty_users(client):
    response = await client.get("/users")
    assert response.status_code == 200
    assert response.json() == []
```

Testing async utility functions directly:
```python
from myapp.services import fetch_user_data

async def test_fetch_user_data():
    result = await fetch_user_data(user_id=1)
    assert result["name"] == "Alice"
```

---

## How It Connects

`pytest-asyncio` builds on pytest fixtures — async fixtures are used the same way as sync ones.
[[fixtures|Fixtures]]

`AsyncClient` is the async equivalent of `TestClient` — both test the FastAPI ASGI stack without a real server.
[[testing-fastapi|Testing FastAPI]]

---

## Common Misconceptions

Misconception 1: "You need `@pytest.mark.asyncio` on every async test."
Reality: With `asyncio_mode = "auto"` in pytest configuration, all `async def test_*` functions run automatically. The decorator is only needed without this setting or when using `asyncio_mode = "strict"`.

Misconception 2: "`TestClient` can't test async FastAPI handlers."
Reality: `TestClient` runs the async ASGI app in a synchronous wrapper — it creates an event loop internally. Most async FastAPI tests work fine with `TestClient`. `AsyncClient` is specifically needed when the test itself needs to `await` or when async lifespan events must run (like async DB pool initialization).

---

## Why It Matters in Practice

When to use `AsyncClient` over `TestClient`:
- App uses lifespan events that initialize async resources (DB pool, Redis) — `async with AsyncClient` triggers them
- Tests share async fixtures (async DB sessions, async cache)
- Testing streaming/WebSocket responses (requires async iteration)
- Test code itself needs `await` (e.g., pre-seeding data via async ORM before the request)

For simple endpoint tests with no async fixtures: `TestClient` is simpler and works fine.

---

## Interview Angle

Common question forms:
- "How do you write async tests for FastAPI?"
- "What is `pytest-asyncio`?"

Answer frame: `pytest-asyncio` runs `async def test_*` functions in an event loop. Set `asyncio_mode = "auto"` in `pyproject.toml` — no per-test decorator needed. Use `AsyncClient(app=app, base_url="http://test")` as async context manager for HTTP testing. Async fixtures work the same as sync ones. `AsyncClient` triggers lifespan events; `TestClient` does only inside `with TestClient(app)`.

---

## Related Notes

- [[testing-fastapi|Testing FastAPI]]
- [[pytest|Pytest]]
- [[fixtures|Fixtures]]
- [[asyncio|Asyncio]]
