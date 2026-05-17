---
title: 15 - aiohttp
description: "`aiohttp` is an async HTTP client/server library — `aiohttp.ClientSession` manages connection pooling and must be used as an async context manager; individual requests are also async context managers; the server side uses `aiohttp.web.Application` and request handlers are coroutines."
tags: [aiohttp, ClientSession, async-http, connection-pooling, web-application, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# aiohttp

> `aiohttp` is an async HTTP client/server library — `aiohttp.ClientSession` manages connection pooling and must be used as an async context manager; individual requests are also async context managers; the server side uses `aiohttp.web.Application` and request handlers are coroutines.

---

## Quick Reference

**Core idea:**
- `async with aiohttp.ClientSession() as session:` — creates a session; manages connection pool; must be closed (use `async with`)
- `async with session.get(url) as response:` — sends GET request; `response.status`, `await response.json()`, `await response.text()`
- `session.post(url, json=data)` / `session.put()` / `session.delete()` — other HTTP methods
- `aiohttp.web.Application()` — server-side; add routes with `app.router.add_get(path, handler)`
- `aiohttp.web.run_app(app)` — start the server (runs its own event loop)

**Tricky points:**
- Creating a `ClientSession` outside an async context (at module level) raises `DeprecationWarning` and may fail — always create inside a coroutine
- `await response.json()` reads and closes the response body; calling it after `async with` block exits raises `RuntimeError` — consume the response inside the `async with session.get(url) as response:` block
- `ClientSession` is not thread-safe — use one session per event loop; do not share sessions across threads
- `ClientSession` keeps connections alive (keep-alive) — reuse one session for multiple requests instead of creating a new one per request; creating a session per request is a common mistake that wastes connections
- Timeouts: pass `aiohttp.ClientTimeout(total=30)` to `ClientSession()` — not as a per-request parameter

---

## What It Is

Think of `aiohttp.ClientSession` as a reusable envelope factory. The factory maintains a stock of pre-addressed envelopes (persistent connections) so each new request doesn't need to start from scratch (TCP handshake + TLS negotiation). Sending a request is opening an envelope, writing the letter, sealing it, and waiting for the reply — all without blocking, so you can prepare dozens of letters concurrently while waiting for replies.

Without `aiohttp` (using `requests`), each HTTP call blocks the event loop. With `aiohttp`, each `await session.get(url)` yields to the event loop while waiting for the TCP response — hundreds of requests can be in-flight simultaneously within a single thread.

---

## How It Actually Works

Basic client usage:

```python
import aiohttp
import asyncio

async def fetch(session, url):
    async with session.get(url) as response:
        response.raise_for_status()
        return await response.json()

async def main():
    timeout = aiohttp.ClientTimeout(total=10)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        results = await asyncio.gather(
            fetch(session, "https://api.example.com/users/1"),
            fetch(session, "https://api.example.com/users/2"),
            fetch(session, "https://api.example.com/users/3"),
        )
    return results

asyncio.run(main())
```

Concurrent requests with rate limiting:

```python
async def fetch_all(urls):
    sem = asyncio.Semaphore(20)  # max 20 concurrent
    
    async def bounded_fetch(session, url):
        async with sem:
            async with session.get(url) as response:
                return await response.text()
    
    async with aiohttp.ClientSession() as session:
        tasks = [bounded_fetch(session, url) for url in urls]
        return await asyncio.gather(*tasks)
```

Server-side with `aiohttp.web`:

```python
from aiohttp import web

async def handle_users(request):
    user_id = request.match_info["id"]
    data = await db.get_user(user_id)
    return web.json_response(data)

app = web.Application()
app.router.add_get("/users/{id}", handle_users)

if __name__ == "__main__":
    web.run_app(app, port=8080)
```

---

## How It Connects

`aiohttp` is an async library built on asyncio — all its I/O operations yield to the event loop via `await`, enabling concurrent requests within a single thread.
[[asyncio|Asyncio]]

`asyncio.gather` is the primary way to run multiple `aiohttp` requests concurrently — each `session.get()` call is a coroutine that can be gathered.
[[asyncio-gather|asyncio.gather and asyncio.wait]]

---

## Common Misconceptions

Misconception 1: "Create a new `ClientSession` for each request."
Reality: `ClientSession` manages a connection pool. Creating a new session per request means new TCP connections per request, defeating HTTP keep-alive. Create one session for the lifetime of your program (or for a batch of related requests) and reuse it.

Misconception 2: "`response.json()` can be called after the `async with session.get()` block."
Reality: The response body is a stream. Once the `async with session.get(url) as response:` block exits, the connection is released and the response body may be gone. Always consume (`await response.json()`, `await response.text()`, `await response.read()`) inside the `async with` block.

---

## Why It Matters in Practice

Web scraping 1000 URLs with `aiohttp`:
```python
async def scrape(urls):
    results = []
    
    async def fetch_one(session, url):
        try:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=5)) as r:
                return {"url": url, "status": r.status, "body": await r.text()}
        except Exception as e:
            return {"url": url, "error": str(e)}
    
    async with aiohttp.ClientSession() as session:
        tasks = [fetch_one(session, url) for url in urls]
        results = await asyncio.gather(*tasks)
    return results
```

With `requests` (synchronous), 1000 URLs at 200ms each = 200 seconds. With `aiohttp` + `gather`, limited by network parallelism rather than sequential execution — typically 2–10 seconds for the same workload.

---

## Interview Angle

Common question forms:
- "How do you make concurrent HTTP requests in Python?"
- "What is wrong with using `requests` in an async application?"

Answer frame: `requests` is synchronous — each call blocks the event loop, preventing other coroutines from running. `aiohttp.ClientSession` is the async alternative: `async with session.get(url) as response:` yields to the event loop while waiting for the TCP response. Use one session for the lifetime of the program (connection pool reuse). Combine with `asyncio.gather` for concurrent requests. Use `asyncio.Semaphore` to rate-limit. For truly CPU-heavy response processing, offload to `run_in_executor`.

---

## Related Notes

- [[asyncio|Asyncio]]
- [[asyncio-gather|asyncio.gather and asyncio.wait]]
- [[async-context-managers|Async Context Managers]]
- [[running-sync-in-async|Running Sync Code in Async]]
