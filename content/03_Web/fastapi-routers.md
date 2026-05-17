---
title: Routers in FastAPI
description: "`APIRouter` splits a FastAPI application into modular route groups — each router has its own prefix, tags, and dependencies; routers are included in the main app with `app.include_router()`; used to organize routes by domain (users, orders, products) without one massive file."
tags: [fastapi, APIRouter, include_router, prefix, tags, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# Routers in FastAPI

> `APIRouter` splits a FastAPI application into modular route groups — each router has its own prefix, tags, and dependencies; routers are included in the main app with `app.include_router()`; used to organize routes by domain (users, orders, products) without one massive file.

---

## Quick Reference

**Core idea:**
- `router = APIRouter(prefix="/users", tags=["users"])` — creates a sub-router with shared prefix and OpenAPI tags
- `@router.get("/")` → maps to `GET /users/`
- `app.include_router(router)` — registers the router's routes on the main app
- `include_router(router, prefix="/api/v1", dependencies=[Depends(auth)])` — add prefix and dependencies at include time
- Routers can include other routers (nested)

**Tricky points:**
- `prefix` does NOT get a trailing slash automatically — `prefix="/users"` + `@router.get("/{id}")` → `/users/{id}`; `@router.get("/")` → `/users/`
- Tags on `APIRouter` are combined with tags on `app.include_router()` in OpenAPI docs
- Dependencies on the router apply to all routes in that router — `APIRouter(dependencies=[Depends(require_auth)])` requires auth for every route
- Route ordering matters: routes are matched in the order they are registered; a catch-all route (`/{anything}`) should be last
- `app.include_router(router)` adds routes at the time of the call — routers must be included before the server starts

---

## What It Is

A FastAPI application with 50+ routes in a single file becomes unmaintainable. `APIRouter` solves this by letting you define routes in separate modules and combine them in the main app. Each router acts like a mini-app — same `@router.get`/`@router.post` decorators, same dependencies, same response models.

The pattern: one `main.py` that creates `app` and includes routers, and multiple `routers/` modules each defining routes for a specific domain.

---

## How It Actually Works

Router module (`routers/users.py`):
```python
from fastapi import APIRouter, Depends, HTTPException

router = APIRouter(
    prefix="/users",
    tags=["users"],
    dependencies=[Depends(require_auth)],
    responses={404: {"description": "Not found"}},
)

@router.get("/", response_model=list[UserResponse])
async def list_users(db: Session = Depends(get_db)):
    return db.query(User).all()

@router.get("/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).get(user_id)
    if not user:
        raise HTTPException(404)
    return user
```

Main app (`main.py`):
```python
from fastapi import FastAPI
from routers import users, orders, products

app = FastAPI()

app.include_router(users.router)
app.include_router(orders.router)
app.include_router(products.router)

# Or with version prefix:
app.include_router(users.router, prefix="/api/v1")
```

Nested routers:
```python
# api_router collects all domain routers
api_router = APIRouter(prefix="/api/v1")
api_router.include_router(users.router)
api_router.include_router(orders.router)

app.include_router(api_router)
# Results: /api/v1/users/..., /api/v1/orders/...
```

---

## How It Connects

Routers organize routes but otherwise use the same FastAPI mechanism — path params, dependencies, response models all work the same way on router routes.
[[fastapi|FastAPI]]

Router-level dependencies (`APIRouter(dependencies=[Depends(auth)])`) apply to all routes without repeating `Depends(auth)` on each handler.
[[fastapi-dependencies|FastAPI Dependencies]]

---

## Common Misconceptions

Misconception 1: "Router routes are independent from the main app."
Reality: `app.include_router(router)` copies all routes from the router into the app. After inclusion, there is no distinction — the routes become part of the app's route table. The router object is just a container used during setup.

Misconception 2: "Routers can be included multiple times with different prefixes."
Reality: Including the same router twice with different prefixes does work and creates duplicate routes with both prefixes — but this is uncommon and can create confusion. If you need the same routes at two prefixes, create separate routers or use route-level parameters.

---

## Why It Matters in Practice

Recommended project structure:
```
app/
  main.py           ← creates FastAPI app, includes routers
  routers/
    users.py        ← APIRouter(prefix="/users")
    orders.py       ← APIRouter(prefix="/orders")
    auth.py         ← APIRouter(prefix="/auth")
  models/
    user.py
    order.py
  dependencies.py   ← shared Depends() functions
  database.py       ← DB session setup
```

This structure scales to 100+ routes without any single file becoming unwieldy.

---

## Interview Angle

Common question forms:
- "How do you organize routes in a large FastAPI application?"
- "What is `APIRouter`?"

Answer frame: `APIRouter` groups related routes with a shared prefix, tags, and dependencies. Define routes on the router with `@router.get/post` — same as on the app. Register with `app.include_router(router)`. Pattern: one router per domain (`/users`, `/orders`), all included in `main.py`. Router-level `dependencies=[Depends(auth)]` requires auth for all routes in that router without per-route repetition.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[fastapi-dependencies|FastAPI Dependencies]]
- [[fastapi-middleware|Middleware in FastAPI]]
