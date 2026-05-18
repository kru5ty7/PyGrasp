---
title: 03 - aiohttp Client
description: "aiohttp's ClientSession is a battle-tested async HTTP client that manages connection pools, supports streaming responses, and has been the standard async HTTP client in Python since before httpx existed."
tags: [aiohttp, http-client, async, websockets, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# aiohttp Client

> aiohttp's `ClientSession` is the original async HTTP client for Python  -  it must be created inside a running event loop, shared across requests for connection pooling, and closed when no longer needed.

---

## Quick Reference

**Core idea:**
- `aiohttp.ClientSession` is the async HTTP client  -  always use as an async context manager or manage lifecycle explicitly
- `async with session.get(url) as response: data = await response.json()`  -  note the double `async with`
- `ClientSession` maintains a connection pool internally  -  create once per application, not per request
- `aiohttp.TCPConnector(limit=100, limit_per_host=30)`  -  controls total and per-host connection limits
- Comparison to httpx: aiohttp is async-only, lower-level, older, more battle-tested for high-throughput async work

**Tricky points:**
- The response context manager (`async with session.get(url) as response`) must be used  -  accessing `response` after the `with` block has exited closes the connection and reading the body raises an error
- `await response.json()` assumes UTF-8 encoding and `Content-Type: application/json`  -  for non-standard APIs, pass `content_type=None` to skip the content-type check
- `ClientSession` must be created inside an event loop  -  creating it at module import time (before the loop starts) raises a `DeprecationWarning` in recent versions and will eventually be an error
- `aiohttp.ClientSession` does not follow redirects by default in some configurations  -  verify `allow_redirects=True` for use cases that need it
- Timeout is configured via `aiohttp.ClientTimeout(total=30, connect=5)` object, not a simple float

---

## What It Is

aiohttp is one of the oldest async Python frameworks. It was created in 2014, when asyncio itself was new and the ecosystem of async tools was sparse. It provides both a web server (similar to FastAPI/Starlette) and an HTTP client (`ClientSession`). The client side of aiohttp was, for several years, the only serious option for making async HTTP calls in Python  -  predating httpx by several years.

The `ClientSession` manages a connection pool, handles cookie persistence across requests, supports streaming for large response bodies, and provides WebSocket client capabilities. Its architecture is lower-level than requests or httpx  -  the response body is not read automatically; you must explicitly call `await response.read()`, `await response.json()`, or `await response.text()` to consume it. This explicitness is a feature for streaming use cases but adds ceremony for simple JSON API calls.

The library is particularly well-suited for high-throughput async work. Its connection pool implementation is mature, well-tested at scale, and provides fine-grained control through `TCPConnector`. Many production systems running millions of requests per day use aiohttp as their HTTP client layer. For new projects, httpx is often the simpler choice; for projects already using aiohttp or requiring its specific features (WebSocket client, streaming, the server component alongside the client), aiohttp remains the standard.

---

## How It Actually Works

The double async-with pattern is the defining syntax of aiohttp client code. The outer `with` manages the session lifecycle; the inner `with` manages the response connection.

```python
import aiohttp
import asyncio

async def fetch_users() -> list[dict]:
    async with aiohttp.ClientSession() as session:
        async with session.get("https://api.example.com/users") as response:
            response.raise_for_status()
            return await response.json()

# Multiple requests with one session
async def fetch_many(urls: list[str]) -> list[dict]:
    async with aiohttp.ClientSession(
        headers={"Authorization": "Bearer token"},
        timeout=aiohttp.ClientTimeout(total=30, connect=5),
    ) as session:
        results = []
        for url in urls:
            async with session.get(url) as response:
                results.append(await response.json())
        return results

# Concurrent requests
async def fetch_concurrent(urls: list[str]) -> list[dict]:
    async with aiohttp.ClientSession() as session:
        tasks = [session.get(url) for url in urls]
        responses = await asyncio.gather(*tasks, return_exceptions=True)
        results = []
        for response in responses:
            if isinstance(response, Exception):
                results.append({"error": str(response)})
            else:
                async with response:
                    results.append(await response.json())
        return results
```

For applications that maintain a long-lived session (the recommended pattern for FastAPI/asyncio services), the session is created at startup and closed at shutdown.

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
import aiohttp

@asynccontextmanager
async def lifespan(app: FastAPI):
    connector = aiohttp.TCPConnector(limit=100, limit_per_host=30)
    app.state.http_session = aiohttp.ClientSession(
        connector=connector,
        timeout=aiohttp.ClientTimeout(total=30),
    )
    yield
    await app.state.http_session.close()

app = FastAPI(lifespan=lifespan)
```

Streaming large responses avoids loading the full body into memory:

```python
async with session.get("https://files.example.com/large_file.zip") as response:
    with open("large_file.zip", "wb") as f:
        async for chunk in response.content.iter_chunked(1024 * 64):  # 64KB chunks
            f.write(chunk)
```

---

## How It Connects

httpx is the modern alternative to aiohttp for async HTTP  -  both are valid choices for a FastAPI application that needs to call external services.

[[httpx|httpx]]

aiohttp also provides WebSocket client support via `session.ws_connect()`  -  the WebSocket client note covers this in the context of the `websockets` library.

[[websocket-clients|WebSocket Clients]]

---

## Common Misconceptions

Misconception 1: "I can create one `ClientSession` per coroutine/request to keep the code simple."
Reality: Each `ClientSession` opens its own connection pool. Creating a new session per request means creating and tearing down connections for every single HTTP call  -  exactly what connection pooling exists to avoid. Create one session at application startup and inject it as a dependency.

Misconception 2: "aiohttp and httpx are interchangeable  -  I can pick either one without consequences."
Reality: aiohttp is async-only with no synchronous mode; httpx has both. aiohttp has a different API for timeouts, error handling, and response body reading. aiohttp includes a WebSocket client and a server component; httpx does not. For greenfield projects, httpx is simpler. For projects that need WebSocket client support or are already in the aiohttp ecosystem, aiohttp is the better fit.

---

## Why It Matters in Practice

aiohttp appears throughout the Python async ecosystem  -  in existing codebases, in tutorials, and as a dependency of other libraries. Understanding its session lifecycle, the double async-with pattern for response reading, and the connector configuration prevents the common mistakes of creating sessions per request or not awaiting response body methods. Even developers who choose httpx for new projects will encounter aiohttp code in the real world.

---

## Interview Angle

Common question forms:
- "How do you make concurrent async HTTP requests in Python?"
- "What is the difference between aiohttp and httpx?"
- "Why is it important to share a ClientSession rather than creating one per request?"

Answer frame:
aiohttp `ClientSession` is the async HTTP client  -  double async-with pattern: one for session lifecycle, one for response. Share one session across requests for connection pooling. Concurrent requests: `asyncio.gather()` with multiple `session.get()` calls. httpx vs aiohttp: httpx has sync+async modes and simpler API; aiohttp is async-only, has WebSocket client built-in, more mature at high throughput. Both require creating a single client at startup.

---

## Related Notes

- [[httpx|httpx]]
- [[requests-library|requests Library]]
- [[websocket-clients|WebSocket Clients]]
- [[async-await|Async/Await]]
- [[asyncio|asyncio]]
