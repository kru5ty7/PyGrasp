---
title: 04 - HTTP Headers
description: "HTTP headers are key-value metadata sent with requests and responses  -  they control caching (`Cache-Control`), content negotiation (`Content-Type`, `Accept`), authentication (`Authorization`), CORS (`Access-Control-*`), and connection behavior (`Connection`, `Keep-Alive`)."
tags: [http, headers, Content-Type, Authorization, Cache-Control, CORS, Accept, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# HTTP Headers

> HTTP headers are key-value metadata sent with requests and responses  -  they control caching (`Cache-Control`), content negotiation (`Content-Type`, `Accept`), authentication (`Authorization`), CORS (`Access-Control-*`), and connection behavior (`Connection`, `Keep-Alive`).

---

## Quick Reference

**Core idea:**
- `Content-Type`  -  describes the body format (`application/json`, `text/html`, `multipart/form-data`)
- `Accept`  -  tells the server what formats the client accepts (`application/json`, `*/*`)
- `Authorization`  -  carries credentials (`Bearer <token>`, `Basic <base64>`)
- `Cache-Control`  -  controls caching behavior (`no-cache`, `max-age=3600`, `no-store`)
- `Content-Length`  -  size of the body in bytes; required by some servers for POST/PUT
- `Location`  -  URI of newly created resource (in 201 responses) or redirect target (301/302)
- `X-Request-ID` / custom `X-*` headers  -  non-standard headers by convention use `X-` prefix (deprecated by RFC 6648, but still common)

**Tricky points:**
- Header names are case-insensitive (`content-type` and `Content-Type` are the same)
- `Content-Type: application/json` without `charset=utf-8` is technically ambiguous  -  most frameworks default to UTF-8 anyway
- `Authorization: Bearer <token>`  -  the token is NOT encrypted by the header; HTTPS encrypts it in transit
- `Cache-Control: no-cache` does NOT mean "don't cache"  -  it means "revalidate before using the cache"; `no-store` means "never store"
- CORS headers (`Access-Control-Allow-Origin`) are set by the server, not the client  -  clients cannot grant themselves permission

---

## What It Is

HTTP headers are the envelope metadata for HTTP messages. The body carries the content; the headers tell endpoints what the content is, who is sending it, what formats are acceptable, and how to handle the message. They are the primary mechanism for protocol negotiation  -  clients and servers use headers to agree on format, encoding, caching, and authentication without baking these concerns into the URL or body.

Request headers describe the client's request context. Response headers describe the server's response and instructions for the client. Some headers appear in both (e.g., `Content-Type`).

---

## How It Actually Works

Common request headers:
```http
GET /api/users HTTP/1.1
Host: api.example.com
Authorization: Bearer eyJhbGci...
Accept: application/json
Accept-Encoding: gzip, deflate, br
User-Agent: Mozilla/5.0 ...
```

Common response headers:
```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Content-Length: 342
Cache-Control: max-age=60, must-revalidate
ETag: "abc123"
X-Request-ID: f4e2-9a1b
```

Setting headers in FastAPI:
```python
from fastapi import FastAPI, Response
from fastapi.responses import JSONResponse

app = FastAPI()

@app.get("/data")
async def get_data(response: Response):
    response.headers["X-Custom-Header"] = "value"
    return {"data": "..."}

@app.get("/cached")
async def get_cached():
    return JSONResponse(
        content={"data": "..."},
        headers={"Cache-Control": "max-age=3600"}
    )
```

Reading request headers in FastAPI:
```python
from fastapi import Header

@app.get("/auth")
async def auth_endpoint(authorization: str = Header(...)):
    # Header() automatically converts 'authorization' -> 'Authorization'
    token = authorization.removeprefix("Bearer ")
    ...
```

---

## How It Connects

Headers are part of the HTTP protocol  -  understanding the request-response cycle shows how headers flow between client and server.
[[http-basics|HTTP Basics]]

CORS is controlled entirely through HTTP headers  -  the `Access-Control-*` family allows or blocks cross-origin requests.
[[cors|CORS]]

---

## Common Misconceptions

Misconception 1: "`Cache-Control: no-cache` disables caching."
Reality: `no-cache` instructs caches to revalidate before serving a cached response. The response may still be stored and returned if the server confirms it hasn't changed (304 Not Modified). `no-store` is the directive that completely prevents caching.

Misconception 2: "The `Authorization` header is secure without HTTPS."
Reality: HTTP headers are transmitted as plaintext without HTTPS. Anyone on the network path can read the token. HTTPS encrypts the entire HTTP message, including headers. Always use HTTPS for bearer tokens.

---

## Why It Matters in Practice

Authentication flow:
```
Client -> POST /login -> Server
Server -> 200 {"token": "eyJ..."} -> Client
Client -> GET /api/data (Authorization: Bearer eyJ...) -> Server
Server -> validates token -> 200 {"data": "..."} -> Client
```

Caching strategy via headers:
- `Cache-Control: max-age=3600`  -  cache for 1 hour, no revalidation needed
- `Cache-Control: no-cache` + `ETag: "abc"`  -  cache but revalidate; server returns 304 if unchanged
- `Cache-Control: no-store`  -  never cache (sensitive data: financial transactions, personal info)

---

## Interview Angle

Common question forms:
- "What HTTP header carries the auth token?"
- "What is the difference between `no-cache` and `no-store`?"

Answer frame: Auth token in `Authorization: Bearer <token>` header. **`no-cache`**: store but revalidate before serving  -  can still return cached response with 304. **`no-store`**: never store. `Content-Type` describes the body format; `Accept` describes what the client accepts. Header names are case-insensitive. CORS headers are server-set; they cannot be self-granted by clients.

---

## Related Notes

- [[http-basics|HTTP Basics]]
- [[cors|CORS]]
- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[http-status-codes|HTTP Status Codes]]
