---
title: 13 - CORS
description: "CORS (Cross-Origin Resource Sharing) is a browser security mechanism — browsers block cross-origin requests unless the server explicitly allows them via `Access-Control-*` response headers; FastAPI adds `CORSMiddleware` to set these headers; preflight OPTIONS requests check permissions before actual requests."
tags: [cors, cross-origin, Access-Control-Allow-Origin, preflight, CORSMiddleware, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# CORS

> CORS (Cross-Origin Resource Sharing) is a browser security mechanism — browsers block cross-origin requests unless the server explicitly allows them via `Access-Control-*` response headers; FastAPI adds `CORSMiddleware` to set these headers; preflight OPTIONS requests check permissions before actual requests.

---

## Quick Reference

**Core idea:**
- **Origin** = scheme + host + port (`https://app.example.com:443`)
- A "cross-origin" request: JavaScript at `app.example.com` calling `api.example.com` (different subdomain = different origin)
- Browsers send a preflight `OPTIONS` request for "non-simple" requests (custom headers, non-GET/POST, `Content-Type: application/json`)
- `Access-Control-Allow-Origin: https://app.example.com` — server says this origin is allowed
- `Access-Control-Allow-Credentials: true` — cookies and auth headers are allowed in cross-origin requests

**Tricky points:**
- CORS is enforced by browsers, NOT servers — the server always receives the request; CORS headers tell the browser whether to expose the response
- `allow_origins=["*"]` and `allow_credentials=True` are incompatible — credentials with wildcard origin is blocked by browsers as a security rule; must list specific origins
- Preflight `OPTIONS` request must return 200 (not 204) for some browsers
- `allow_origins` must include the exact origin including scheme and port — `http://localhost:3000` ≠ `http://localhost` ≠ `https://localhost:3000`
- CORS headers are NOT a server-side security mechanism — they only control browser behavior; server-side auth (JWT, sessions) is still required

---

## What It Is

CORS is the browser's enforcement of the same-origin policy. JavaScript code running on `https://app.example.com` cannot read the response of a `fetch()` call to `https://api.example.com` unless the API server explicitly opts in by setting `Access-Control-Allow-Origin`.

This prevents malicious websites from using a victim's browser to make authenticated requests to other sites and read the responses. It's a browser-enforced rule; Curl and server-to-server calls are not subject to CORS.

---

## How It Actually Works

CORS flow:
```
Browser JS at app.example.com:
→ OPTIONS https://api.example.com/users  (preflight)
   Origin: https://app.example.com
   Access-Control-Request-Method: POST
   Access-Control-Request-Headers: Content-Type, Authorization

← 200 OK
   Access-Control-Allow-Origin: https://app.example.com
   Access-Control-Allow-Methods: POST, GET, DELETE
   Access-Control-Allow-Headers: Content-Type, Authorization
   Access-Control-Max-Age: 600

→ POST https://api.example.com/users  (actual request)
   Origin: https://app.example.com
   Content-Type: application/json

← 200 OK
   Access-Control-Allow-Origin: https://app.example.com
   {"id": 1, "name": "Alice"}
```

FastAPI `CORSMiddleware`:
```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://app.example.com",
        "http://localhost:3000",   # development
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    allow_headers=["Content-Type", "Authorization"],
    max_age=600,  # preflight cache duration in seconds
)
```

For local development with any origin:
```python
# Development only — never in production:
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,  # must be False with wildcard
    allow_methods=["*"],
    allow_headers=["*"],
)
```

---

## How It Connects

CORS is implemented as FastAPI middleware — it adds response headers to every request and handles preflight `OPTIONS` requests.
[[fastapi-middleware|Middleware in FastAPI]]

The `Access-Control-Allow-Origin` header is an HTTP response header — understanding HTTP headers gives the full picture.
[[http-headers|HTTP Headers]]

---

## Common Misconceptions

Misconception 1: "Configuring CORS on the server prevents unauthorized API access."
Reality: CORS only controls what browsers do with responses. A server configured with CORS is still accessible via Curl, Postman, or server-to-server calls — those tools don't enforce CORS. Actual access control requires authentication (JWT, API keys, sessions).

Misconception 2: "Setting `allow_origins=["*"]` allows all authenticated requests."
Reality: `allow_origins=["*"]` with `allow_credentials=True` is rejected by browsers — the browser requires a specific origin when credentials are included (cookies, Authorization headers). List explicit allowed origins instead.

---

## Why It Matters in Practice

Common scenario: React frontend (`localhost:3000` in dev, `https://app.example.com` in prod) calls FastAPI backend (`localhost:8000` in dev, `https://api.example.com` in prod).

Checklist for CORS configuration:
1. List all frontend origins in `allow_origins`
2. If using cookies or `Authorization` headers: `allow_credentials=True` + no wildcard in origins
3. List only necessary methods and headers — minimal surface
4. Include dev origins (localhost) in development but not production builds
5. `max_age=600` to reduce preflight request frequency

---

## Interview Angle

Common question forms:
- "What is CORS and how do you configure it?"
- "What is a preflight request?"

Answer frame: CORS = browser policy preventing cross-origin reads unless server opts in. Preflight = browser sends OPTIONS first for "non-simple" requests to check permissions. Server responds with `Access-Control-Allow-Origin`, `Allow-Methods`, `Allow-Headers`. In FastAPI: `app.add_middleware(CORSMiddleware, allow_origins=[...])`. Credentials require specific origins (not `*`). CORS is browser-only — not a server security mechanism.

---

## Related Notes

- [[fastapi-middleware|Middleware in FastAPI]]
- [[http-headers|HTTP Headers]]
- [[fastapi|FastAPI]]
- [[authentication-vs-authorization|Authentication vs Authorization]]
