---
title: 05 - Testing FastAPI
description: "FastAPI is tested with `TestClient` (sync) or `AsyncClient` from `httpx` (async)  -  they send real HTTP requests to the app without a running server; `dependency_overrides` replaces dependencies (auth, DB) in tests; test the full request-response cycle including validation and status codes."
tags: [fastapi, testing, TestClient, AsyncClient, httpx, dependency_overrides, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Testing FastAPI

> FastAPI is tested with `TestClient` (sync) or `AsyncClient` from `httpx` (async)  -  they send real HTTP requests to the app without a running server; `dependency_overrides` replaces dependencies (auth, DB) in tests; test the full request-response cycle including validation and status codes.

---

## Quick Reference

**Core idea:**
- `TestClient(app)`  -  sync HTTP client for testing; from `starlette.testclient` or `fastapi.testclient`
- `AsyncClient(app=app, base_url="http://test")`  -  async HTTP client from `httpx`; required for lifespan events
- `app.dependency_overrides[real_dep] = fake_dep`  -  replace a dependency for all tests
- `client.get("/path")` -> `Response`; check `.status_code`, `.json()`, `.headers`
- `TestClient` as context manager  -  triggers lifespan events (`startup`/`shutdown`)

**Tricky points:**
- `TestClient` does NOT trigger lifespan events by default  -  use `with TestClient(app) as client:` to trigger startup/shutdown
- `AsyncClient` requires `pytest-asyncio` and the app's lifespan runs within `async with AsyncClient(...):`
- `dependency_overrides` is global on the `app` object  -  always clean up: `app.dependency_overrides = {}` in a fixture teardown; otherwise leaks between tests
- The `TestClient` makes requests using Starlette's test transport  -  no real network, no real port, but full ASGI stack runs (middleware, routing, validation)
- Testing files: use `client.post("/upload", files={"file": ("test.txt", b"content", "text/plain")})`

---

## What It Is

Testing FastAPI means testing the full stack  -  routing, dependency injection, Pydantic validation, middleware  -  without running a real server. `TestClient` wraps the app in a test transport, allowing you to make `client.get("/users")` calls that go through the complete ASGI pipeline and return a real `Response` object.

`dependency_overrides` is the key tool for integration testing: replace the real database session with a test session, replace the real auth with a fake that returns a specific user, and test the handler's behavior in isolation from external services.

---

## How It Actually Works

Basic test:
```python
from fastapi.testclient import TestClient
from myapp.main import app

client = TestClient(app)

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_create_user():
    response = client.post(
        "/users",
        json={"email": "alice@example.com", "name": "Alice"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "alice@example.com"
    assert "id" in data

def test_invalid_user_returns_422():
    response = client.post("/users", json={"email": "notanemail"})
    assert response.status_code == 422
```

`dependency_overrides` for testing with a fake DB:
```python
import pytest
from fastapi.testclient import TestClient
from myapp.main import app
from myapp.dependencies import get_db

@pytest.fixture
def db_session():
    # In-memory SQLite for tests
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session
        session.rollback()

@pytest.fixture
def client(db_session):
    def override_get_db():
        yield db_session
    
    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides = {}  # cleanup

def test_list_users(client, db_session):
    db_session.add(User(email="alice@example.com", name="Alice"))
    db_session.flush()
    
    response = client.get("/users")
    assert response.status_code == 200
    assert len(response.json()) == 1
```

Authenticated routes:
```python
from myapp.dependencies import get_current_user

@pytest.fixture
def auth_client(client):
    fake_user = User(id=1, email="admin@example.com", role="admin")
    app.dependency_overrides[get_current_user] = lambda: fake_user
    yield client
    app.dependency_overrides.pop(get_current_user, None)

def test_delete_user_requires_admin(client):
    response = client.delete("/users/1")
    assert response.status_code == 401

def test_admin_can_delete_user(auth_client):
    response = auth_client.delete("/users/1")
    assert response.status_code in (200, 204)
```

---

## How It Connects

`dependency_overrides` replaces FastAPI dependencies  -  understanding `Depends()` is required to use overrides effectively.
[[fastapi-dependencies|FastAPI Dependencies]]

The database session in tests uses a rollback-per-test pattern  -  combines pytest fixtures with SQLAlchemy sessions.
[[database-sessions|Database Sessions in FastAPI]]

---

## Common Misconceptions

Misconception 1: "`TestClient` tests the API the same as a real client."
Reality: `TestClient` runs the full ASGI stack (routing, validation, middleware, dependencies) but skips network I/O. It doesn't test DNS, TLS, or actual HTTP parsing. For testing those layers, use a real running server.

Misconception 2: "`dependency_overrides` only applies to the next test."
Reality: `dependency_overrides` modifications persist until explicitly cleared. Always reset in fixture teardown: `app.dependency_overrides = {}` or `app.dependency_overrides.pop(dep, None)`. Forgetting to clean up causes tests to interfere with each other.

---

## Why It Matters in Practice

Complete test pattern for a CRUD endpoint:
```python
def test_crud_lifecycle(client, db_session):
    # Create
    r = client.post("/items", json={"name": "Widget", "price": 9.99})
    assert r.status_code == 201
    item_id = r.json()["id"]
    
    # Read
    r = client.get(f"/items/{item_id}")
    assert r.status_code == 200
    assert r.json()["name"] == "Widget"
    
    # Update
    r = client.patch(f"/items/{item_id}", json={"price": 12.99})
    assert r.status_code == 200
    
    # Delete
    r = client.delete(f"/items/{item_id}")
    assert r.status_code == 204
    
    # Verify deleted
    r = client.get(f"/items/{item_id}")
    assert r.status_code == 404
```

---

## Interview Angle

Common question forms:
- "How do you test a FastAPI endpoint?"
- "How do you mock authentication in FastAPI tests?"

Answer frame: `TestClient(app)`  -  makes real HTTP requests to the app's ASGI stack. Check `response.status_code` and `response.json()`. `dependency_overrides[get_db] = lambda: test_session`  -  replace DB dependency with test session. `dependency_overrides[get_current_user] = lambda: fake_user`  -  bypass auth. Always reset overrides in fixture teardown. `with TestClient(app)` triggers lifespan events.

---

## Related Notes

- [[pytest|Pytest]]
- [[fixtures|Fixtures]]
- [[fastapi-dependencies|FastAPI Dependencies]]
- [[async-testing|Async Testing]]
