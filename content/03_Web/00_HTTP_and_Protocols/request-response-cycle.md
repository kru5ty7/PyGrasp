---
title: 05 - Request-Response Cycle
description: "The HTTP request-response cycle: client sends a request (method + URL + headers + optional body), server processes and returns a response (status code + headers + optional body); for a web API, the cycle involves DNS resolution, TCP connection, TLS handshake, HTTP exchange, and connection teardown."
tags: [http, request-response, TCP, TLS, DNS, keep-alive, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# Request Response Cycle

> The HTTP request-response cycle: client sends a request (method + URL + headers + optional body), server processes and returns a response (status code + headers + optional body); for a web API, the cycle involves DNS resolution, TCP connection, TLS handshake, HTTP exchange, and connection teardown.

---

## Quick Reference

**Core idea:**
- **Request**: `METHOD /path HTTP/version\r\n` + headers + blank line + optional body
- **Response**: `HTTP/version STATUS_CODE reason\r\n` + headers + blank line + optional body
- Full cycle: DNS → TCP 3-way handshake → TLS handshake (HTTPS) → HTTP request → HTTP response
- `Connection: keep-alive` — reuses the TCP connection for multiple requests (default in HTTP/1.1)
- HTTP/2: multiplexes multiple requests over a single TCP connection (binary framing, no head-of-line blocking per stream)

**Tricky points:**
- DNS resolution adds latency on the first request to a host — result is cached (TTL-based); CDN edge nodes reduce DNS + TCP RTT
- TLS handshake adds 1-2 RTTs before the first byte of HTTP data is sent (mitigated by TLS session resumption and 0-RTT in TLS 1.3)
- HTTP/1.1 `keep-alive` reuses TCP but requests are still sequential on that connection; HTTP/2 multiplexing allows parallel requests on one connection
- `Content-Length` mismatch (server sends fewer bytes than declared): client hangs waiting for the rest; more bytes: client truncates or errors
- `Transfer-Encoding: chunked` — body is sent in pieces; used when `Content-Length` is unknown (streaming responses)

---

## What It Is

The request-response cycle is the fundamental unit of web communication. Every web interaction — loading a page, calling an API, submitting a form — is one or more request-response cycles. Understanding it is essential because performance problems, security vulnerabilities, and bugs in web applications typically manifest at a specific point in this cycle.

The steps before HTTP even starts (DNS, TCP, TLS) add latency that dwarfs the actual HTTP exchange time in fast networks. Optimizations like HTTP/2, CDNs, and keep-alive connections target these pre-HTTP costs.

---

## How It Actually Works

Raw HTTP/1.1 request over a TCP connection:
```
→ TCP SYN
← TCP SYN-ACK
→ TCP ACK
(TLS handshake for HTTPS)
→ GET /api/users HTTP/1.1\r\n
   Host: api.example.com\r\n
   Authorization: Bearer eyJ...\r\n
   Accept: application/json\r\n
   \r\n
← HTTP/1.1 200 OK\r\n
   Content-Type: application/json\r\n
   Content-Length: 98\r\n
   \r\n
   {"users": [...]}
```

In ASGI/FastAPI, the cycle maps to:
```
1. Uvicorn accepts TCP connection
2. Uvicorn reads HTTP request → parses into scope dict (method, path, headers, query)
3. ASGI app (Starlette/FastAPI) receives scope + receive callable
4. Route matching → dependency injection → handler coroutine
5. Handler returns Response → send callable writes status + headers + body
6. Uvicorn sends bytes to client
```

`Transfer-Encoding: chunked` streaming response in FastAPI:
```python
from fastapi.responses import StreamingResponse

async def event_stream():
    for i in range(10):
        yield f"data: {i}\n\n"
        await asyncio.sleep(0.5)

@app.get("/stream")
async def stream():
    return StreamingResponse(event_stream(), media_type="text/event-stream")
```

No `Content-Length` — server sends chunks as they become available; client receives incrementally.

---

## How It Connects

The request-response cycle is the basis for WSGI and ASGI — both interfaces define how a Python web framework receives the request and sends the response.
[[wsgi|WSGI]]
[[asgi|ASGI]]

HTTP headers carry the metadata that controls each step of the cycle — content type, caching, authentication, connection behavior.
[[http-headers|HTTP Headers]]

---

## Common Misconceptions

Misconception 1: "HTTPS adds a separate round trip for every request."
Reality: TLS session resumption (and 0-RTT in TLS 1.3) allows subsequent connections to skip most of the handshake. For a reused connection (`keep-alive`), there is no additional TLS overhead after the initial handshake.

Misconception 2: "HTTP/2 just compresses headers."
Reality: HTTP/2 does compress headers (HPACK), but the bigger gains come from **multiplexing** — multiple request-response pairs travel concurrently over a single TCP connection, eliminating HTTP/1.1's head-of-line blocking where a slow response blocks all subsequent requests on that connection.

---

## Why It Matters in Practice

Latency breakdown for a typical HTTPS API call:
```
DNS lookup:         10-50ms (cached: ~0ms)
TCP handshake:      20-100ms (1 RTT)
TLS handshake:      20-100ms (1-2 RTTs, 0 with TLS 1.3 0-RTT)
Server processing:  5-200ms (your code)
Data transfer:      varies (size / bandwidth)
```

Optimizations targeting each phase:
- DNS: long TTL, DNS prefetch, CDN
- TCP/TLS: HTTP/2, connection reuse, TLS session resumption
- Server: caching, async, DB query optimization
- Transfer: compression, pagination, streaming

---

## Interview Angle

Common question forms:
- "What happens between typing a URL and seeing the page?"
- "What does keep-alive do?"

Answer frame: DNS lookup → TCP 3-way handshake → TLS handshake (HTTPS) → HTTP request → server processes → HTTP response → browser renders. **Keep-alive** reuses the TCP connection for multiple requests, saving handshake RTTs. **HTTP/2** multiplexes multiple requests over one connection. Performance bottlenecks: DNS (cache it), TCP+TLS (reuse connections), server (async, caching).

---

## Related Notes

- [[http-basics|HTTP Basics]]
- [[http-headers|HTTP Headers]]
- [[wsgi|WSGI]]
- [[asgi|ASGI]]
