---
title: 01 - Sanic
description: "Sanic is an async Python web framework with a built-in server designed for high-throughput I/O-bound services."
tags: [sanic, async, web-framework, performance, uvloop, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Sanic

> Sanic is an async Python web framework with its own built-in HTTP server — designed from the ground up for high concurrency, it trades ecosystem breadth for raw I/O throughput.

---

## Quick Reference

**Core idea:**
- Async-native framework with a built-in server (not ASGI — Sanic manages its own event loop and HTTP handling)
- Uses `uvloop` by default for significantly faster event loop throughput than the standard asyncio loop
- Route handlers, middleware, and listeners are all `async def`
- `Blueprints` group related routes, similar to Flask Blueprints or FastAPI Routers
- `request.json` and `response.json()` handle JSON I/O; `sanic.response` provides response constructors
- Worker management is built-in via `app.run(workers=N)` — no Gunicorn or uvicorn wrapper required

**Tricky points:**
- Sanic is not ASGI — ASGI middlewares and ASGI-compatible libraries cannot be dropped in without an adapter
- The built-in server bypasses nginx in simple deployments, but production still benefits from a reverse proxy for TLS termination and static files
- Sanic's own ORM and testing tooling ecosystem is smaller than FastAPI's or Django's
- Version compatibility across major releases has historically been inconsistent — pin your version carefully
- Signal handling for background tasks (`@app.signal`) uses a distinct internal event bus, not asyncio signals

---

## What It Is

Imagine building a courier dispatch system. One design hires many couriers (threads or processes) and assigns each package to one courier who carries it from pickup to delivery without doing anything else in between. Another design hires fewer couriers but gives each one a phone: while a package is in transit (I/O is in progress), the courier can take the next call and start another job. Sanic is the second design applied to web serving. It uses Python's asyncio event loop — accelerated by uvloop — to handle many simultaneous connections on a small number of OS threads by suspending handlers that are waiting on I/O.

Sanic was created in 2016 by Channelmanics with the explicit goal of benchmarking as fast as Node.js and Go web servers. At the time, Python's async web story was fragmented: aiohttp existed for clients, but high-performance async servers were scarce. Sanic filled that gap by pairing Flask-like route decorator syntax with asyncio handlers and a C-accelerated event loop. When benchmark results spread on Hacker News, it attracted considerable attention and contributed to the broader shift in the Python community toward async-first web development.

The framework is self-contained in a way that sets it apart from frameworks that delegate serving to external tools. Running `app.run(host="0.0.0.0", port=8000, workers=4)` starts Sanic's own HTTP server, manages worker processes, and handles graceful shutdowns. There is no conceptual equivalent of "pick a Sanic-compatible ASGI server" — Sanic is the server. This means the deployment model is simpler for small services (one command, no server plumbing), but it also means that any server-level capability (HTTP/2, HTTP/3, middleware protocols) must be implemented inside Sanic itself rather than by swapping the server.

---

## How It Actually Works

A Sanic application is structured around an `app` object and decorated route handlers:

```python
from sanic import Sanic
from sanic.response import json

app = Sanic("MyApp")

@app.get("/items/<item_id:int>")
async def get_item(request, item_id):
    return json({"id": item_id, "name": "Widget"})

@app.middleware("request")
async def add_request_id(request):
    request.ctx.id = "req-001"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, workers=4, fast=True)
```

The `fast=True` flag lets Sanic determine the optimal worker count based on CPU core count. Workers are OS processes (not threads), each running their own uvloop event loop. Sanic uses `multiprocessing` to fork workers, meaning the application object is initialized in the master process and then inherited by workers — a pattern similar to Gunicorn's preforking model.

Blueprints provide route grouping with optional URL prefixes and shared middleware:

```python
from sanic import Blueprint

items_bp = Blueprint("items", url_prefix="/items")

@items_bp.get("/<item_id:int>")
async def get_item(request, item_id):
    return json({"id": item_id})

app.blueprint(items_bp)
```

Sanic's built-in server handles keep-alive connections and manages the HTTP lifecycle internally. For TLS in production, Sanic can accept a certificate and key directly (`app.run(ssl={"cert": ..., "key": ...})`), but the more common production pattern places nginx in front for TLS termination and proxies requests to Sanic over HTTP on a local socket.

---

## How It Connects

Understanding asyncio's event loop model is foundational for understanding why Sanic's approach yields high concurrency — each `await` point in a route handler returns control to the event loop, which can then advance other requests.

[[async-await|Async/Await]]

Sanic's framework model is an alternative to FastAPI for async Python web development; comparing the two reveals where FastAPI's ASGI architecture and Pydantic integration add value over Sanic's simpler, lower-level approach.

[[fastapi|FastAPI]]

The WSGI vs ASGI note provides context for why Sanic's non-ASGI architecture is a meaningful distinction when evaluating middleware and library compatibility.

[[wsgi-vs-asgi|WSGI vs ASGI]]

---

## Common Misconceptions

Misconception 1: "Sanic is ASGI-compatible because it's async."
Reality: Being async does not imply ASGI compatibility. ASGI is a specific protocol interface (scope/receive/send callables). Sanic implements its own HTTP handling and does not expose or consume the ASGI interface. ASGI middleware (Starlette's `CORSMiddleware`, for example) cannot be used directly with Sanic.

Misconception 2: "Sanic's benchmark numbers mean it will be faster for my application."
Reality: Framework benchmarks measure request parsing and routing overhead with minimal application logic. Real application latency is dominated by database queries, external API calls, and business logic. At realistic query loads, the difference between Sanic and FastAPI is negligible compared to the cost of a single database round-trip.

Misconception 3: "Sanic is no longer maintained."
Reality: Sanic has had consistent releases through 2024 and maintains an active community. It underwent significant architecture changes in version 21.x and continues to receive updates. However, its ecosystem is smaller than FastAPI's, which means fewer third-party integrations and less community documentation.

---

## Why It Matters in Practice

Sanic is the right choice when building a narrow, I/O-heavy service — a webhook forwarder, a real-time event aggregator, a thin API gateway — where maximum HTTP throughput matters and the application logic is simple enough that a smaller framework ecosystem is acceptable. Its self-contained server model also simplifies Dockerized deployments: one `CMD` in the Dockerfile, no server orchestration layer.

For most new Python web projects, FastAPI or Starlette offers a better balance: ASGI compatibility, Pydantic validation, automatic OpenAPI documentation, and a richer middleware ecosystem. Sanic's niche is the performance-first use case where those features are unnecessary overhead. Teams maintaining existing Sanic services should understand Blueprints, the request context (`request.ctx`), and Sanic's signals system for decoupled event handling.

---

## Interview Angle

Common question forms:
- "When would you choose Sanic over FastAPI?"
- "How does Sanic handle concurrency?"
- "Is Sanic an ASGI framework?"

Answer frame:
A strong answer to the first question focuses on the use case rather than technical trivia: Sanic is appropriate for high-concurrency, I/O-bound services where raw HTTP throughput is the primary concern and the broader FastAPI/ASGI ecosystem is not needed. For the concurrency question, the answer should explain uvloop as the accelerated event loop and the async handler model where `await` yields control. For the ASGI question, the correct answer is no — Sanic is not ASGI, it has its own server and event system — and a strong answer explains what that means for middleware compatibility.

---

## Related Notes

- [[async-await|Async/Await]]
- [[fastapi|FastAPI]]
- [[wsgi-vs-asgi|WSGI vs ASGI]]
- [[starlette|Starlette]]
- [[framework-comparison|Python Web Framework Comparison]]
