---
title: 08 - Path and Query Parameters
description: "FastAPI extracts path parameters from URL segments (`/users/{id}`) and query parameters from the query string (`/users?page=2`) — both are automatically type-coerced and validated from the function signature; `Path()` and `Query()` add constraints and metadata."
tags: [fastapi, path-parameters, query-parameters, Path, Query, type-coercion, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# Path and Query Parameters

> FastAPI extracts path parameters from URL segments (`/users/{id}`) and query parameters from the query string (`/users?page=2`) — both are automatically type-coerced and validated from the function signature; `Path()` and `Query()` add constraints and metadata.

---

## Quick Reference

**Core idea:**
- **Path parameter**: `@app.get("/users/{user_id}")` + `user_id: int` in function signature → automatically extracted from URL and cast to `int`
- **Query parameter**: any function parameter NOT in the path template → extracted from query string (`?key=value`)
- `Query(default=None)` — makes the query parameter optional with a default
- `Path(ge=1)` — adds constraints to a path parameter
- Multiple path/query params declared as function parameters are resolved in parallel

**Tricky points:**
- Path parameters are always required (they're part of the URL path); query parameters can be optional via `= None` or `Query(default=...)`
- Type coercion happens automatically: `user_id: int` will reject non-integer paths with a 422 error
- `Optional[str] = None` vs `str = Query(default=None)` — functionally equivalent for query params; `Query()` adds OpenAPI metadata
- `list[str]` as a query parameter allows `?tags=a&tags=b` (repeated key) → `["a", "b"]`
- Declaring `request: Request` in the signature gives access to the raw request without any FastAPI magic

---

## What It Is

FastAPI's parameter system is an extension of Python function signatures — the function parameters describe what the endpoint expects, and FastAPI handles extraction, coercion, and validation automatically. This eliminates the `request.query_params.get("page", "1")` + `int(page_str)` boilerplate common in other frameworks.

The type annotation drives validation: `page: int` means FastAPI will reject non-integer query strings with a 422. `user_id: UUID` means FastAPI validates UUID format. The function receives already-validated, typed Python objects.

---

## How It Actually Works

Path and query parameters:
```python
from fastapi import FastAPI, Path, Query
from typing import Annotated

app = FastAPI()

@app.get("/users/{user_id}")
async def get_user(
    user_id: Annotated[int, Path(ge=1, description="User ID")],
    include_deleted: bool = False,
):
    return {"user_id": user_id, "include_deleted": include_deleted}

# GET /users/42            → user_id=42, include_deleted=False
# GET /users/42?include_deleted=true → user_id=42, include_deleted=True
# GET /users/abc           → 422 (not an integer)
# GET /users/0             → 422 (not >= 1)
```

Query parameters with constraints:
```python
@app.get("/users")
async def list_users(
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    search: str | None = None,
    tags: list[str] = Query(default=[]),
):
    return {"page": page, "page_size": page_size, "search": search, "tags": tags}

# GET /users?page=2&search=alice&tags=admin&tags=user
# → page=2, page_size=20, search="alice", tags=["admin", "user"]
```

Multiple path parameters:
```python
@app.get("/users/{user_id}/posts/{post_id}")
async def get_post(user_id: int, post_id: int):
    return {"user_id": user_id, "post_id": post_id}
```

---

## How It Connects

Path and query parameters are part of FastAPI's declarative request parsing — the same mechanism handles request bodies (Pydantic models) and headers.
[[fastapi|FastAPI]]

`Path()` and `Query()` use Pydantic's `Field()` under the hood for constraints — understanding Pydantic helps explain why the same `ge`, `le`, `min_length` constraints work.
[[pydantic|Pydantic]]

---

## Common Misconceptions

Misconception 1: "Query parameters with `list[str]` accept comma-separated values."
Reality: By default, FastAPI expects repeated query string keys: `?tags=a&tags=b`. For comma-separated `?tags=a,b`, you need to parse manually or use a custom validator.

Misconception 2: "Optional path parameters can have defaults."
Reality: Path parameters are part of the URL structure — there is no such thing as an optional path segment in FastAPI. If `user_id` is in the path template `{user_id}`, it must be present in the URL. Use query parameters for optional values.

---

## Why It Matters in Practice

```python
@app.get("/products")
async def search_products(
    q: str | None = Query(None, min_length=1, description="Search query"),
    category: str | None = None,
    min_price: float | None = Query(None, ge=0),
    max_price: float | None = Query(None, ge=0),
    sort_by: Literal["price", "rating", "name"] = "rating",
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
):
    # All inputs are validated, typed, and documented in Swagger UI automatically
    ...
```

This single function declaration generates complete OpenAPI documentation — parameter names, types, constraints, descriptions — all from type annotations.

---

## Interview Angle

Common question forms:
- "How do you get path parameters in FastAPI?"
- "How do you make a query parameter optional?"

Answer frame: Path param: declared in route template `{id}` and as function parameter `user_id: int` — automatically extracted and validated. Query param: any function parameter not in the path template; optional via `= None`. `Path()` and `Query()` add constraints (`ge`, `le`, `min_length`) and OpenAPI metadata. Type annotation drives validation — wrong type → 422 Unprocessable Entity.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[request-body|Request Body]]
- [[pydantic|Pydantic]]
- [[http-basics|HTTP Basics]]
