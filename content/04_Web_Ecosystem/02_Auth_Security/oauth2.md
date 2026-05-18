---
title: 04 - OAuth2
description: "OAuth2 is an authorization framework for delegated access  -  a user grants a third-party application access to their resources without sharing their password; FastAPI's `OAuth2PasswordBearer` extracts bearer tokens; the Authorization Code flow is the standard for web apps."
tags: [oauth2, bearer-token, authorization-code, OAuth2PasswordBearer, scopes, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# OAuth2

> OAuth2 is an authorization framework for delegated access  -  a user grants a third-party application access to their resources without sharing their password; FastAPI's `OAuth2PasswordBearer` extracts bearer tokens; the Authorization Code flow is the standard for web apps.

---

## Quick Reference

**Core idea:**
- **OAuth2** is about delegation: "I, the user, authorize this app to act on my behalf, with these permissions (scopes)"
- **Bearer token**: a token that grants access  -  "whoever holds this token is authorized"; sent as `Authorization: Bearer <token>`
- `OAuth2PasswordBearer(tokenUrl="/auth/token")`  -  FastAPI dependency that extracts the Bearer token from the `Authorization` header
- **Scopes**: limited permissions (`read:users`, `write:posts`) granted to an access token
- **Flows**: Password (testing/internal), Authorization Code (web apps), Client Credentials (server-to-server), Implicit (deprecated)

**Tricky points:**
- OAuth2 Password flow sends username+password directly to the API  -  only appropriate for first-party apps (your own frontend); never for third-party apps
- `OAuth2PasswordBearer` only extracts the token  -  it does not validate it; validation is done in your `get_current_user` dependency
- The `tokenUrl` in `OAuth2PasswordBearer` is metadata for Swagger UI  -  it tells Swagger where to get a token for the "Authorize" button; it doesn't affect runtime behavior
- Scopes in OAuth2 are advisory  -  the auth server issues tokens with scopes; resource servers check scopes; FastAPI has `SecurityScopes` for this
- Access tokens + refresh tokens: access tokens are short-lived (minutes); refresh tokens are long-lived (days/weeks) and used to obtain new access tokens

---

## What It Is

OAuth2 solves "how does a user authorize App B to access their data at Service A without giving App B their Service A password?" Think of logging in to a third-party website with your Google account  -  you authorize Google to share your profile with the site without the site knowing your Google password.

In the FastAPI context, OAuth2 is commonly used in a simplified form: the Password flow (where the client sends username+password to get a token) is used for first-party apps. The Authorization Code flow (redirect to auth server, user approves, get code, exchange for token) is used for third-party integration (Google, GitHub, etc.).

---

## How It Actually Works

FastAPI with OAuth2 Password flow:
```python
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

@app.post("/auth/token")
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):
    user = authenticate_user(db, form_data.username, form_data.password)
    if not user:
        raise HTTPException(status_code=401, detail="Incorrect username or password",
                           headers={"WWW-Authenticate": "Bearer"})
    
    access_token = create_access_token(user.id)
    return {"access_token": access_token, "token_type": "bearer"}

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    payload = decode_access_token(token)  # verifies signature and expiry
    user = db.query(User).get(int(payload["sub"]))
    if not user:
        raise HTTPException(status_code=401)
    return user

@app.get("/me")
async def read_me(user: User = Depends(get_current_user)):
    return user
```

Scopes with `Security` and `SecurityScopes`:
```python
from fastapi.security import SecurityScopes
from fastapi import Security

async def get_current_user(
    security_scopes: SecurityScopes,
    token: str = Depends(oauth2_scheme),
) -> User:
    payload = decode_access_token(token)
    token_scopes = payload.get("scopes", [])
    for scope in security_scopes.scopes:
        if scope not in token_scopes:
            raise HTTPException(403, f"Insufficient scope: {scope}")
    return get_user(payload["sub"])

@app.get("/admin/users")
async def admin_list(user: User = Security(get_current_user, scopes=["admin"])):
    ...
```

---

## How It Connects

OAuth2 access tokens are typically JWTs  -  JWT is the format; OAuth2 is the framework that issues and uses the tokens.
[[jwt|JWT]]

FastAPI's `Security()` (used with scopes) extends `Depends()` with OAuth2 scope information for Swagger UI.
[[fastapi-security|Security in FastAPI]]

---

## Common Misconceptions

Misconception 1: "OAuth2 is an authentication protocol."
Reality: OAuth2 is an authorization framework  -  it delegates access, not identity. For authentication (who is the user?), OpenID Connect (OIDC) extends OAuth2. OIDC adds an ID token (JWT with user identity claims) to the OAuth2 access token.

Misconception 2: "OAuth2 Password flow is the standard for web apps."
Reality: Password flow is for first-party apps where the frontend is fully trusted with the user's credentials. For third-party apps (OAuth2 "Sign in with Google"), the Authorization Code flow is standard  -  the user is redirected to the identity provider, logs in there, and the app receives only an authorization code.

---

## Why It Matters in Practice

FastAPI + OAuth2 is the standard pattern for API authentication:
1. Frontend calls `POST /auth/token` with `username` + `password` (OAuth2 Password flow)
2. Server validates credentials, returns JWT access token
3. Frontend stores token (memory preferred; localStorage is XSS-vulnerable)
4. All subsequent requests include `Authorization: Bearer <token>`
5. Token expiry: frontend detects 401, calls `POST /auth/refresh` with refresh token

For third-party auth (Google, GitHub): use a library like `authlib` or `fastapi-users`  -  implementing the Authorization Code flow manually is complex and error-prone.

---

## Interview Angle

Common question forms:
- "How do you implement authentication in FastAPI?"
- "What is OAuth2?"

Answer frame: OAuth2 = delegated authorization framework. FastAPI: `OAuth2PasswordBearer(tokenUrl="/auth/token")` extracts bearer token; `get_current_user` dependency decodes/validates it. Login endpoint issues JWT. For production: access token (short-lived) + refresh token (long-lived). OAuth2 Password flow for first-party apps; Authorization Code for third-party. `Security()` for scope-based authorization in Swagger UI.

---

## Related Notes

- [[jwt|JWT]]
- [[fastapi-security|Security in FastAPI]]
- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[hashing-and-passwords|Hashing and Passwords]]
