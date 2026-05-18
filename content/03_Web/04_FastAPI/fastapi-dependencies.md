---
title: 11 - FastAPI Dependencies
description: "FastAPI's `Depends()` system injects shared logic into route handlers  -  database sessions, authentication, pagination, and settings are common dependencies; dependencies can depend on other dependencies (chaining), and can have cleanup logic via `yield`."
tags: [fastapi, Depends, dependency-injection, yield-dependency, db-session, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# FastAPI Dependencies

> FastAPI's `Depends()` system injects shared logic into route handlers  -  database sessions, authentication, pagination, and settings are common dependencies; dependencies can depend on other dependencies (chaining), and can have cleanup logic via `yield`.

---

## Quick Reference

**Core idea:**
- `Depends(callable)`  -  declares a dependency; FastAPI calls the callable and injects the result
- Dependencies run before the handler; if they raise `HTTPException`, the handler does not run
- `yield` dependencies: code before `yield` is setup, `yield` value is injected, code after `yield` is teardown (runs after response is sent)
- `Depends(func, use_cache=True)`  -  default; same dependency called multiple times in one request returns the same instance
- `Security(callable)`  -  like `Depends()` but marks the dependency as a security scheme in OpenAPI docs

**Tricky points:**
- Dependencies are resolved per-request, not at startup  -  a `yield` database session opens and closes for each request
- `use_cache=True` (default): if the same dependency function appears multiple times in a request (via chaining), it's called once and the result is shared; `use_cache=False` forces a fresh call each time
- A `yield` dependency's teardown code runs even if the handler raises an exception  -  like a `finally` block
- `yield` dependencies can raise `HTTPException` after `yield` to change the response  -  unusual but supported
- Class-based dependencies: `class Paginator` with `__call__` method  -  useful for parameterized dependencies

---

## What It Is

Dependency injection in FastAPI is a declarative way to share logic across multiple endpoints without repeating it. Instead of opening a database connection in every handler, you write one `get_db()` dependency, and FastAPI calls it before each handler that declares `db: Session = Depends(get_db)`.

Dependencies form a tree  -  a handler depends on `get_current_user`, which depends on `get_db` and `get_settings`. FastAPI resolves the entire tree, calling each dependency in the correct order and passing results down.

---

## How It Actually Works

Simple dependency:
```python
from fastapi import FastAPI, Depends, HTTPException

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/users/{id}")
async def get_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).get(user_id)
    if not user:
        raise HTTPException(status_code=404)
    return user
```

Authentication dependency chain:
```python
def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    payload = decode_jwt(token)
    user = db.query(User).get(payload["sub"])
    if not user:
        raise HTTPException(status_code=401)
    return user

def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != "admin":
        raise HTTPException(status_code=403)
    return user

@app.delete("/users/{id}")
async def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),  # _ because we don't use the value
):
    ...
```

Class-based dependency for pagination:
```python
class Pagination:
    def __init__(self, page: int = 1, size: int = Query(20, le=100)):
        self.offset = (page - 1) * size
        self.limit = size

@app.get("/items")
async def list_items(pagination: Pagination = Depends()):
    return db.query(Item).offset(pagination.offset).limit(pagination.limit).all()
```

Router-level dependency (applies to all routes in the router):
```python
router = APIRouter(dependencies=[Depends(require_auth)])
```

---

## How It Connects

`Depends()` is the practical realization of the dependency injection pattern  -  abstracting shared concerns into reusable callables.
[[dependency-injection|Dependency Injection]]

Database sessions are the most common `yield` dependency  -  every handler that touches the database gets a fresh, auto-closing session.
[[database-sessions|Database Sessions in FastAPI]]

---

## Common Misconceptions

Misconception 1: "Dependencies are shared across requests."
Reality: Dependencies are per-request by default. Each request gets a fresh instance. The `use_cache=True` behavior shares the instance within a single request (if the same dependency is needed at multiple points in the dependency tree), not across requests.

Misconception 2: "You must use `Depends` for everything."
Reality: `Depends` is for shared logic that spans multiple endpoints. Simple parameters unique to one endpoint (path params, query params, specific body fields) don't need `Depends`. Use it when the same setup/teardown pattern repeats across endpoints.

---

## Why It Matters in Practice

`Depends` enables the clean FastAPI pattern where business logic is tested in isolation:
```python
# Test the handler with a fake dependency:
def get_test_db():
    db = create_test_db()
    try:
        yield db
    finally:
        db.rollback()
        db.close()

app.dependency_overrides[get_db] = get_test_db
```

`dependency_overrides` replaces any dependency for testing  -  no mocking frameworks needed.

---

## Interview Angle

Common question forms:
- "How does dependency injection work in FastAPI?"
- "How do you share a database session across dependencies?"

Answer frame: `Depends(callable)`  -  FastAPI calls the callable and injects the result into the handler. `yield` dependencies: setup before `yield`, teardown after (used for DB sessions  -  `yield db; finally: db.close()`). Dependencies can chain  -  `require_admin` depends on `get_current_user` which depends on `get_db`. `dependency_overrides` replaces dependencies in tests.

---

## Related Notes

- [[dependency-injection|Dependency Injection]]
- [[fastapi|FastAPI]]
- [[database-sessions|Database Sessions in FastAPI]]
- [[fastapi-security|Security in FastAPI]]
