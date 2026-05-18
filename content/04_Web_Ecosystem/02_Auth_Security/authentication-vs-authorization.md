---
title: 01 - Authentication vs Authorization
description: "Authentication verifies identity ('who are you?')  -  the client proves it is who it claims to be via credentials; Authorization verifies permissions ('what can you do?')  -  the server decides what an authenticated identity is allowed to access; these are separate concerns with different mechanisms."
tags: [authentication, authorization, authn, authz, identity, permissions, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# Authentication vs Authorization

> Authentication verifies identity ('who are you?')  -  the client proves it is who it claims to be via credentials; Authorization verifies permissions ('what can you do?')  -  the server decides what an authenticated identity is allowed to access; these are separate concerns with different mechanisms.

---

## Quick Reference

**Core idea:**
- **Authentication (AuthN)**: "prove who you are"  -  username+password, token, certificate, biometric
- **Authorization (AuthZ)**: "check what you're allowed to do"  -  role-based (RBAC), attribute-based (ABAC), policy-based
- HTTP `401 Unauthorized`  -  not authenticated (confusingly named)
- HTTP `403 Forbidden`  -  authenticated but not authorized
- Common auth mechanisms: session cookies, JWT tokens, API keys, OAuth2

**Tricky points:**
- The HTTP status codes are confusingly named: `401 Unauthorized` means "not authenticated"; `403 Forbidden` means "not authorized"
- Authentication precedes authorization  -  you must know who someone is before deciding what they can do
- Stateless authentication (JWT): the server doesn't store sessions; the token carries all claims; the server only verifies the token signature
- Stateful authentication (session cookies): the server stores session data; the cookie is just an opaque session ID
- "Anonymous access" is still authorization  -  the server authorizes the anonymous identity to access public resources

---

## What It Is

Authentication and authorization are two separate security gates. Authentication at the door: "show your ID." Authorization inside: "your ID says you're a guest, so you can access the lobby but not the executive suite."

Mixing them causes security bugs. A common mistake: checking `if user.id == resource.owner_id` (authorization) before verifying the JWT signature (authentication). If the token is forged, you never knew who the user actually was.

The order must always be: authenticate first (verify who they are) -> authorize second (check what they can do).

---

## How It Actually Works

FastAPI authentication flow:
```python
# 1. Authentication dependency  -  extracts and verifies identity
async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    
    user = db.query(User).get(user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user

# 2. Authorization dependency  -  checks what the identity can do
def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    return current_user

# 3. Route that requires both:
@app.delete("/users/{id}")
async def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),  # chains: authn -> authz
):
    ...
```

RBAC (Role-Based Access Control) example:
```python
class Permission(str, Enum):
    READ = "read"
    WRITE = "write"
    DELETE = "delete"

def require_permission(permission: Permission):
    def check(user: User = Depends(get_current_user)):
        if permission not in user.permissions:
            raise HTTPException(403, f"Requires {permission} permission")
        return user
    return check

@app.delete("/posts/{id}")
async def delete_post(
    post_id: int,
    _: User = Depends(require_permission(Permission.DELETE)),
):
    ...
```

---

## How It Connects

JWT is the most common stateless authentication token format  -  it carries identity claims that authorization checks use.
[[jwt|JWT]]

FastAPI `Depends()` chains authentication and authorization naturally  -  `require_admin` depends on `get_current_user`.
[[fastapi-dependencies|FastAPI Dependencies]]

---

## Common Misconceptions

Misconception 1: "Authentication and authorization can be handled in a single check."
Reality: They can be in the same code, but they are conceptually separate. Authentication validates the credential (is this token valid?). Authorization checks the permission (does this user have access?). Conflating them makes code harder to test and audit.

Misconception 2: "HTTPS provides authentication."
Reality: HTTPS (TLS) authenticates the server to the client (via certificate), not the user to the server. User authentication requires credentials (password, token) separate from TLS.

---

## Why It Matters in Practice

Typical multi-tenant API:
```
Request: DELETE /users/42
1. Authentication: decode JWT -> user_id=99 (verified: user 99 is requesting)
2. Authorization check 1: user 99 has role "admin"? -> No
3. Authorization check 2: resource /users/42 belongs to user 99? -> No
4. Result: 403 Forbidden
```

Security audit questions:
- "Where in the code is authentication performed?"  -  should be one place (auth middleware or `get_current_user` dependency)
- "Where is authorization performed?"  -  should be per-resource, per-action
- "Can an unauthenticated request reach sensitive data?"  -  trace the dependency chain

---

## Interview Angle

Common question forms:
- "What is the difference between authentication and authorization?"
- "What HTTP status code do you return when a user isn't logged in?"

Answer frame: **AuthN** = verify identity (who are you?); **AuthZ** = verify permission (what can you do?). AuthN first, then AuthZ. **401** = not authenticated; **403** = authenticated but not authorized. JWT is stateless auth  -  server verifies signature; no session stored. FastAPI: `get_current_user` dependency for AuthN, role/permission checks for AuthZ, chained with `Depends()`.

---

## Related Notes

- [[jwt|JWT]]
- [[oauth2|OAuth2]]
- [[fastapi-security|Security in FastAPI]]
- [[fastapi-dependencies|FastAPI Dependencies]]
