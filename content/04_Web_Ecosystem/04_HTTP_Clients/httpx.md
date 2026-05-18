---
title: 02 - httpx
description: "httpx is a modern Python HTTP client that supports both synchronous and asynchronous requests with an API compatible with requests, adding HTTP/2 support and native asyncio integration."
tags: [httpx, http-client, async, http2, fastapi, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# httpx

> httpx is requests for the modern Python ecosystem  -  it adds async support, HTTP/2, and type annotations while keeping an API familiar to anyone who already knows requests.

---

## Quick Reference

**Core idea:**
- Sync: `httpx.get(url, ...)` and `httpx.Client()`  -  drop-in requests replacement
- Async: `await client.get(url, ...)` inside `async with httpx.AsyncClient() as client:`
- HTTP/2 support: `httpx.AsyncClient(http2=True)`  -  requires `pip install httpx[http2]`
- Both clients support: `auth=`, `headers=`, `cookies=`, `timeout=`, `follow_redirects=`, `params=`, `json=`
- FastAPI's `TestClient` is built on httpx  -  knowing httpx's API means knowing how TestClient works

**Tricky points:**
- `follow_redirects=False` is the default in httpx (unlike requests where it is `True`)  -  must set `follow_redirects=True` explicitly when redirects are expected
- `httpx.AsyncClient` should be created once and reused, not created per request  -  it maintains a connection pool
- Timeouts in httpx have more granularity: `httpx.Timeout(connect=5, read=30, write=5, pool=1)`  -  or a single float for all
- `raise_for_status()` raises `httpx.HTTPStatusError` (not `requests.HTTPError`)  -  the exception class names differ
- `httpx.URL` and `httpx.Headers` are immutable  -  they differ from requests' mutable headers dict behavior

---

## What It Is

When asyncio became a mainstream Python pattern and FastAPI emerged as a leading async web framework, the requests library became a friction point. requests is synchronous and blocking  -  every call halts the calling thread until the response arrives. Using requests inside a FastAPI route handler blocks the event loop, preventing other requests from being handled concurrently. The correct replacement is an async HTTP client, but aiohttp's API differs significantly from requests, requiring developers to relearn common operations.

httpx was designed to solve this problem. It provides a synchronous client (`httpx.Client`) that is a near-drop-in replacement for requests and an asynchronous client (`httpx.AsyncClient`) that uses asyncio natively. Both clients share the same parameter names, the same response object attributes, and the same exception hierarchy. A developer familiar with requests can switch to httpx with minimal friction  -  and in async contexts, simply add `await` and switch to `AsyncClient`.

Beyond API compatibility, httpx adds capabilities that requests lacks. HTTP/2 support (with the optional `h2` dependency) allows multiplexing multiple requests over a single connection, reducing latency for APIs that support it. Type annotations throughout the library make IDE integration significantly better than requests. The `httpx.MockTransport` enables testing without network calls. And httpx is the transport layer that FastAPI's `TestClient` is built on, which means understanding httpx's API directly improves the ability to work with FastAPI tests.

---

## How It Actually Works

The synchronous client mirrors requests closely enough that the transition is mostly syntax-compatible. The main behavioral difference is `follow_redirects=False` by default.

```python
import httpx

# Synchronous  -  same API as requests, with follow_redirects flag
response = httpx.get(
    "https://api.example.com/users",
    params={"page": 1},
    headers={"Authorization": "Bearer token"},
    follow_redirects=True,     # must opt-in; requests follows by default
    timeout=10.0,
)
response.raise_for_status()   # raises httpx.HTTPStatusError
data = response.json()

# Sync client with connection reuse (preferred for multiple requests)
with httpx.Client(headers={"Authorization": "Bearer token"}, timeout=10) as client:
    r1 = client.get("https://api.example.com/users")
    r2 = client.get("https://api.example.com/posts")
```

The async client is identical in API but all methods are coroutines.

```python
import httpx
import asyncio

async def fetch_user(user_id: int) -> dict:
    async with httpx.AsyncClient(
        base_url="https://api.example.com",
        headers={"Authorization": "Bearer token"},
        timeout=httpx.Timeout(connect=5.0, read=30.0),
    ) as client:
        response = await client.get(f"/users/{user_id}")
        response.raise_for_status()
        return response.json()

# Concurrent requests
async def fetch_all_users(user_ids: list[int]) -> list[dict]:
    async with httpx.AsyncClient(base_url="https://api.example.com") as client:
        tasks = [client.get(f"/users/{uid}") for uid in user_ids]
        responses = await asyncio.gather(*tasks)
        return [r.json() for r in responses]
```

For a FastAPI application, the `AsyncClient` should live for the application's lifetime  -  created at startup and closed at shutdown  -  rather than created per request.

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
import httpx

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http_client = httpx.AsyncClient(timeout=10.0)
    yield
    await app.state.http_client.aclose()

app = FastAPI(lifespan=lifespan)

@app.get("/proxy")
async def proxy_endpoint(request: Request):
    client: httpx.AsyncClient = request.app.state.http_client
    response = await client.get("https://upstream.service.com/data")
    return response.json()
```

HTTP/2 support provides connection multiplexing  -  multiple concurrent requests share one TCP connection, reducing overhead for APIs that accept parallel calls.

```python
async with httpx.AsyncClient(http2=True) as client:
    # These requests multiplex over one TCP connection (if server supports HTTP/2)
    responses = await asyncio.gather(
        client.get("https://api.example.com/resource/1"),
        client.get("https://api.example.com/resource/2"),
        client.get("https://api.example.com/resource/3"),
    )
```

---

## How It Connects

requests is httpx's predecessor and synchronous alternative  -  understanding requests first makes httpx's API immediately familiar.

[[requests-library|requests Library]]

FastAPI's TestClient is an httpx synchronous client pointed at an ASGI application  -  using TestClient correctly requires understanding httpx's request options.

[[testing-fastapi|Testing FastAPI]]

---

## Common Misconceptions

Misconception 1: "httpx.AsyncClient can be used as a drop-in replacement for requests.Session in synchronous code."
Reality: `AsyncClient` is async-only  -  it requires an active asyncio event loop and must be awaited. For synchronous code, `httpx.Client` is the correct replacement for `requests.Session`. The distinction between `httpx.Client` and `httpx.AsyncClient` is the sync/async divide, not a performance difference.

Misconception 2: "Creating a new AsyncClient per request is fine because it is lightweight."
Reality: Each `AsyncClient` creates a new connection pool. Creating one per request means no connection reuse across requests  -  the main performance benefit of a client is lost. The correct pattern is one `AsyncClient` per application (or service dependency), created at startup and reused for the application's lifetime.

---

## Why It Matters in Practice

httpx has become the standard Python HTTP client for async applications and for FastAPI specifically. Its presence in FastAPI's test infrastructure means Python web developers encounter it regardless of whether they explicitly choose it. Understanding the async client lifecycle, the `follow_redirects` default difference from requests, and the connection pool reuse pattern prevents common performance mistakes in FastAPI applications that call external services.

---

## Interview Angle

Common question forms:
- "How do you make async HTTP requests in a FastAPI application?"
- "What is the difference between httpx and requests?"
- "How do you test a FastAPI endpoint that calls an external API?"

Answer frame:
httpx has both sync (`httpx.Client`) and async (`httpx.AsyncClient`) interfaces with requests-compatible API. For FastAPI: create one `AsyncClient` at application startup, inject it as a dependency, await calls inside route handlers. Key difference from requests: `follow_redirects=False` by default. For testing external API calls: `httpx.MockTransport` or patching with `unittest.mock` to avoid real network calls.

---

## Related Notes

- [[requests-library|requests Library]]
- [[aiohttp-client|aiohttp Client]]
- [[testing-fastapi|Testing FastAPI]]
- [[async-await|Async/Await]]
- [[http-basics|HTTP Basics]]
