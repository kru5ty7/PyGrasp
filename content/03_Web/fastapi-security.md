---
title: Security in FastAPI
description: "FastAPI provides security utilities for OAuth2, API key, and HTTP Basic authentication — `OAuth2PasswordBearer`, `APIKeyHeader`, `HTTPBasic` extract credentials from requests; used as `Depends()` parameters; `Security()` extends `Depends()` with OAuth2 scope support for Swagger UI."
tags: [fastapi, security, OAuth2PasswordBearer, APIKeyHeader, HTTPBasic, Security, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Security in FastAPI

> FastAPI provides security utilities for OAuth2, API key, and HTTP Basic authentication — `OAuth2PasswordBearer`, `APIKeyHeader`, `HTTPBasic` extract credentials from requests; used as `Depends()` parameters; `Security()` extends `Depends()` with OAuth2 scope support for Swagger UI.

---

## Quick Reference

**Core idea:**
- `OAuth2PasswordBearer(tokenUrl="/token")` — extracts `Authorization: Bearer <token>` from headers
- `APIKeyHeader(name="X-API-Key")` — extracts a custom header value
- `APIKeyQuery(name="api_key")` — extracts an API key from query params
- `HTTPBasic()` — prompts browser for username/password (Base64 encoded in `Authorization` header)
- `Security(get_current_user, scopes=["read"])` — like `Depends()` but adds OAuth2 scope metadata for Swagger UI

**Tricky points:**
- These utilities only extract credentials — they do NOT validate; validation is your `get_current_user` dependency's job
- `OAuth2PasswordBearer(auto_error=False)` — returns `None` if no token is present instead of raising 401; use for optional auth
- `APIKeyHeader(auto_error=False)` — same pattern for optional API key
- `Security()` affects Swagger UI's "Authorize" dialog — declares the required scopes; runtime scope enforcement is still done manually in the dependency
- Combining auth methods (JWT + API key): use `Optional` deps with `auto_error=False` and check both in `get_current_user`

---

## What It Is

FastAPI's security utilities are specialized `Depends()` callables that standardize how credentials are extracted from different locations (headers, query params, cookies) and communicate their presence to OpenAPI documentation. They're the bridge between the HTTP transport layer and your validation logic.

The separation is intentional: extraction (where the credential comes from) is separate from validation (whether it's valid). `OAuth2PasswordBearer` handles extraction; your `decode_jwt()` + database lookup handles validation.

---

## How It Actually Works

JWT Bearer authentication (complete example):
```python
from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    credentials_exception = HTTPException(
        status_code=401,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    
    user = db.query(User).get(int(user_id))
    if user is None:
        raise credentials_exception
    return user
```

API key authentication:
```python
from fastapi.security import APIKeyHeader

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

async def get_api_key(api_key: str | None = Depends(api_key_header)) -> str:
    if api_key is None or api_key != VALID_API_KEY:
        raise HTTPException(status_code=403, detail="Invalid or missing API key")
    return api_key

@app.get("/data", dependencies=[Depends(get_api_key)])
async def get_data():
    ...
```

Optional authentication (public + auth'd access):
```python
oauth2_scheme_optional = OAuth2PasswordBearer(tokenUrl="/token", auto_error=False)

async def get_current_user_optional(
    token: str | None = Depends(oauth2_scheme_optional),
) -> User | None:
    if token is None:
        return None
    return decode_and_get_user(token)

@app.get("/posts")
async def list_posts(current_user: User | None = Depends(get_current_user_optional)):
    if current_user:
        return db.query(Post).all()  # show all posts to authenticated users
    return db.query(Post).filter(Post.public == True).all()
```

---

## How It Connects

FastAPI security builds on `Depends()` — the security utilities are specialized dependencies.
[[fastapi-dependencies|FastAPI Dependencies]]

OAuth2 and JWT are the protocols that back the authentication — security utilities in FastAPI implement their extraction layer.
[[oauth2|OAuth2]]
[[jwt|JWT]]

---

## Common Misconceptions

Misconception 1: "`OAuth2PasswordBearer` validates the JWT."
Reality: `OAuth2PasswordBearer` only extracts the bearer token from the `Authorization` header. It raises 401 if no token is present (and `auto_error=True`). The JWT signature verification and user lookup happen in your custom `get_current_user` dependency.

Misconception 2: "`Security()` enforces scopes at runtime."
Reality: `Security(get_current_user, scopes=["read"])` passes the requested scopes to the dependency function via `SecurityScopes`. The dependency must explicitly check `security_scopes.scopes` against the token's scopes — FastAPI does not automatically enforce them.

---

## Why It Matters in Practice

Layered security example:
```python
# Layer 1: Extract token (OAuth2PasswordBearer)
# Layer 2: Validate token, load user (get_current_user)  
# Layer 3: Check role/scope (require_admin)
# Layer 4: Check resource ownership (current_user.id == resource.owner_id)

@app.put("/users/{id}/profile")
async def update_profile(
    user_id: int,
    update: ProfileUpdate,
    current_user: User = Depends(get_current_user),
):
    if current_user.id != user_id and current_user.role != "admin":
        raise HTTPException(403, "Cannot update another user's profile")
    ...
```

Each layer has a single responsibility — makes each layer independently testable.

---

## Interview Angle

Common question forms:
- "How do you add JWT authentication to a FastAPI app?"
- "What is `OAuth2PasswordBearer`?"

Answer frame: `OAuth2PasswordBearer(tokenUrl="/token")` extracts the bearer token from the `Authorization` header. Use it as `Depends(oauth2_scheme)` in `get_current_user` — which then decodes and validates the JWT. `APIKeyHeader` for API key extraction. `Security()` for scope-aware OAuth2 in Swagger. Separation: security utilities extract, custom dependencies validate.

---

## Related Notes

- [[oauth2|OAuth2]]
- [[jwt|JWT]]
- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[fastapi-dependencies|FastAPI Dependencies]]
