---
title: 06 - Session-Based Authentication
description: "Session-based authentication stores user state on the server and identifies users via a session ID cookie, making it stateful and revocable unlike JWT-based authentication."
tags: [sessions, authentication, cookies, csrf, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Session-Based Authentication

> Session-based authentication is the original web identity model  -  the server holds the truth about who is logged in, the browser holds only a reference key, and revoking access is as simple as deleting the server-side record.

---

## Quick Reference

**Core idea:**
- On login: server creates a session record (user ID, expiry, metadata), stores it, and sends `Set-Cookie: session_id=<opaque_id>` to the browser
- On each request: browser automatically sends `Cookie: session_id=<opaque_id>`; server looks up the session to identify the user
- Session stores: in-memory (single-process dev), database (durable), Redis (fast + durable + shared across instances)
- `HttpOnly` prevents JavaScript from reading the cookie; `Secure` restricts it to HTTPS; `SameSite=Strict` blocks cross-site requests
- Stateful: sessions can be revoked instantly by deleting the server-side record

**Tricky points:**
- In-memory session storage breaks immediately in multi-process or multi-server deployments  -  session created by worker A is not visible to worker B
- `SameSite=Lax` (the default in modern browsers) blocks cross-origin POST requests but allows cross-origin GET navigation  -  a significant CSRF mitigation, but not complete protection
- Session fixation attack: attacker sets a known session ID before login; server must regenerate the session ID on successful authentication
- Session expiry must be enforced server-side  -  a cookie's `Max-Age` is advisory and can be ignored by the client
- `Secure` flag has no effect on `http://` connections  -  if the application runs on HTTP in development, the cookie still transmits, but this is a development-only concern

---

## What It Is

When you log in to a website and your browser remembers who you are across page loads, that persistence comes from one of two mechanisms: a session cookie or a token. Session-based authentication uses the cookie to carry a random identifier  -  the session ID  -  that the server maps to your identity in a lookup table. The identifier itself contains no information; it is an opaque pointer to the real session data stored on the server.

Think of it as a coat check ticket. When you arrive (log in), the server takes your coat (identity) and gives you a numbered ticket (session ID). When you return (make a request), you hand over the ticket and the server retrieves your coat. The ticket is worthless on its own  -  it only has meaning because the server maintains the coatroom. If you lose the ticket (session ID is stolen), someone else can use it to claim your coat. If the coatroom closes (server deletes the session), all tickets become invalid instantly.

This stateful design has several important properties. Revocation is immediate  -  deleting the session record from Redis or the database makes the session ID invalid on the very next request, regardless of any cookie TTL. This is the primary advantage over JWT, where the token contains its own expiry and cannot be invalidated before that time without a blocklist. Sessions are also naturally bounded  -  the server controls how much data they hold and can scan them for anomalies. The trade-off is the shared state requirement: every server instance must be able to look up any session, which means session storage must be external (Redis, database) in any distributed deployment.

---

## How It Actually Works

Flask and Django have built-in session support. FastAPI does not ship with sessions natively  -  the `starlette-sessions` or `fastapi-sessions` libraries add this capability, backed by Redis or database storage.

A typical Redis-backed session flow in a Python web application:

```python
# Pseudo-code representing the session lifecycle  -  actual API varies by framework

# Login handler
async def login(request, credentials):
    user = await authenticate(credentials.username, credentials.password)
    if not user:
        raise HTTPException(status_code=401)

    session_id = generate_secure_random_id()  # e.g., secrets.token_urlsafe(32)
    session_data = {"user_id": user.id, "email": user.email}
    await redis.setex(f"session:{session_id}", 3600, json.dumps(session_data))

    response = RedirectResponse(url="/dashboard")
    response.set_cookie(
        key="session_id",
        value=session_id,
        httponly=True,      # no JavaScript access
        secure=True,        # HTTPS only
        samesite="lax",     # CSRF mitigation
        max_age=3600,       # browser discards after 1 hour
    )
    return response

# Request authentication middleware
async def get_current_user(request: Request):
    session_id = request.cookies.get("session_id")
    if not session_id:
        raise HTTPException(status_code=401)

    session_data = await redis.get(f"session:{session_id}")
    if not session_data:
        raise HTTPException(status_code=401)

    return json.loads(session_data)

# Logout handler
async def logout(request, session_id=Cookie(None)):
    await redis.delete(f"session:{session_id}")
    response = RedirectResponse(url="/login")
    response.delete_cookie("session_id")
    return response
```

Cookie security attributes deserve deliberate attention. `HttpOnly` prevents `document.cookie` access from JavaScript, blocking XSS-based session theft. `Secure` restricts transmission to HTTPS connections. `SameSite=Strict` prevents the browser from sending the cookie on any cross-site request, including navigations  -  this blocks CSRF entirely but also breaks OAuth flows and login links from emails. `SameSite=Lax` allows cross-site GET navigations (links, redirects) but blocks cross-site POST  -  a reasonable default for most applications.

---

## How It Connects

Session-based auth and JWT represent the two main stateful vs stateless auth models  -  understanding both clarifies when to choose which.

[[jwt|JSON Web Tokens (JWT)]]

CSRF attacks specifically target cookie-based authentication  -  understanding how CSRF protection works is a natural complement to understanding sessions.

[[csrf-protection|CSRF Protection]]

---

## Common Misconceptions

Misconception 1: "Session cookies are more secure than JWT because they don't contain user data."
Reality: Session cookies are more easily revocable, not inherently more secure. If a session ID is stolen (via XSS or network sniffing), an attacker can impersonate the user just as they could with a stolen JWT. The security difference lies in revocation: a stolen session ID can be invalidated immediately; a stolen JWT cannot be invalidated before its expiry without a blocklist.

Misconception 2: "Setting a cookie's `Max-Age` ensures the session expires after that time."
Reality: `Max-Age` tells the browser when to discard the cookie, but a server-side session must also have its own expiry enforced. A client could modify or ignore the cookie expiry. Server-side session stores (Redis with TTL, database with `expires_at` column) enforce expiry independently of what the browser does.

---

## Why It Matters in Practice

Session-based auth is the standard model for server-rendered web applications and is still common in Python frameworks (Django's `SessionMiddleware`, Flask-Login). Understanding the session lifecycle, the required cookie attributes, the storage backend options, and the comparison to JWT gives the knowledge needed to implement authentication correctly and choose the right model for a given application type. APIs serving JavaScript front-ends typically lean toward JWT; traditional server-rendered apps lean toward sessions.

---

## Interview Angle

Common question forms:
- "How does session-based authentication work?"
- "What is the difference between session-based auth and JWT?"
- "What cookie attributes should a session cookie have?"

Answer frame:
Session auth: server stores session data, client holds only an opaque session ID in a cookie. Each request the server looks up the session ID. Stateful  -  immediate revocation by deleting the server record. JWT is stateless  -  the token carries claims and cannot be revoked without a blocklist. Cookie attributes: `HttpOnly` (no JS access), `Secure` (HTTPS only), `SameSite=Lax` (CSRF mitigation). Redis is the standard production session store for multi-instance deployments.

---

## Related Notes

- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[jwt|JSON Web Tokens (JWT)]]
- [[csrf-protection|CSRF Protection]]
- [[redis-python|Redis with Python]]
- [[hashing-and-passwords|Hashing and Passwords]]
