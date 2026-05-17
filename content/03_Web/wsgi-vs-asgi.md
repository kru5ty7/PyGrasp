---
title: WSGI vs ASGI
description: "WSGI (PEP 3333) is a synchronous interface — one request per thread/process at a time; ASGI (PEP 3400) is an asynchronous interface supporting concurrent connections with coroutines; ASGI handles WebSockets and long-lived connections that WSGI cannot."
tags: [wsgi, asgi, sync, async, uvicorn, gunicorn, web-interface, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# WSGI vs ASGI

> WSGI (PEP 3333) is a synchronous interface — one request per thread/process at a time; ASGI (PEP 3400) is an asynchronous interface supporting concurrent connections with coroutines; ASGI handles WebSockets and long-lived connections that WSGI cannot.

---

## Quick Reference

**Core idea:**
- **WSGI**: `def app(environ, start_response):` — synchronous callable; one thread handles one request; used by Django, Flask (legacy)
- **ASGI**: `async def app(scope, receive, send):` — async callable; one event loop handles thousands of connections; used by FastAPI, Django (async mode), Starlette
- **Concurrency model**: WSGI = thread-per-request (or process); ASGI = event-loop coroutines
- **Protocol support**: WSGI = HTTP only; ASGI = HTTP, WebSockets, Server-Sent Events, background tasks
- WSGI apps can run under ASGI via `WsgiToAsgi` adapter (in Starlette)

**Tricky points:**
- WSGI is synchronous — a blocking database call holds the thread; you need multiple workers (processes/threads) for concurrent requests
- ASGI is asynchronous — a blocking database call still blocks if not awaited; you must use async-compatible libraries (asyncpg, aiohttp, not psycopg2/requests)
- WSGI workers: Gunicorn uses OS processes (or threads with `-k gthread`); each worker handles one request at a time
- ASGI workers: Uvicorn with one worker handles many concurrent requests via the event loop; Gunicorn + `uvicorn.workers.UvicornWorker` combines process stability with async concurrency
- CPU-bound work is just as slow under ASGI — async only helps with I/O-bound concurrency

---

## What It Is

WSGI was the standard Python web interface from 2004 — it standardized how web servers communicate with Python applications and enabled ecosystem compatibility (any WSGI server with any WSGI framework). The synchronous model worked well for CPU-bound or database-heavy applications running in multiple processes.

ASGI emerged as async Python matured and use cases like WebSockets became common. WSGI cannot model a WebSocket — it has one request and one response. ASGI models the connection as a lifecycle (`lifespan`), messages flowing in (`receive`) and out (`send`), which naturally maps to persistent connections.

The practical consequence: FastAPI requires an ASGI server (Uvicorn). Django's async views require ASGI deployment. Old Flask/Django synchronous code runs fine on WSGI but cannot easily serve WebSocket endpoints.

---

## How It Actually Works

WSGI callable signature:
```python
def application(environ, start_response):
    # environ: dict with request data (method, path, headers, body)
    # start_response: callable to set status and headers
    start_response("200 OK", [("Content-Type", "application/json")])
    return [b'{"hello": "world"}']
```

ASGI callable signature:
```python
async def application(scope, receive, send):
    # scope: dict with connection info (type: 'http'/'websocket', path, headers)
    # receive: async callable → returns events (body chunks, disconnect signals)
    # send: async callable → sends events (start response, body bytes)
    
    if scope["type"] == "http":
        await send({"type": "http.response.start", "status": 200, 
                    "headers": [(b"content-type", b"application/json")]})
        await send({"type": "http.response.body", "body": b'{"hello": "world"}'})
    elif scope["type"] == "websocket":
        # Handle WebSocket lifecycle
        event = await receive()
        if event["type"] == "websocket.connect":
            await send({"type": "websocket.accept"})
```

Deployment comparison:
```bash
# WSGI (Gunicorn + Flask/Django)
gunicorn myapp:app -w 4 --timeout 30

# ASGI (Uvicorn + FastAPI)
uvicorn myapp:app --workers 4 --port 8000

# ASGI under Gunicorn (recommended for production)
gunicorn myapp:app -w 4 -k uvicorn.workers.UvicornWorker
```

---

## How It Connects

WSGI and ASGI are the interfaces that Gunicorn and Uvicorn implement — understanding the interface explains why you need a matching server.
[[wsgi|WSGI]]
[[asgi|ASGI]]

FastAPI is an ASGI framework — it receives `scope`, `receive`, `send` and builds the routing layer on top.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "ASGI is always faster than WSGI."
Reality: ASGI is faster for I/O-bound workloads (many simultaneous slow requests — database queries, external API calls). For CPU-bound workloads (image processing, computation), ASGI provides no advantage — both are limited by CPU, and ASGI's overhead can make it marginally slower.

Misconception 2: "You can run WSGI frameworks (Flask, Django) on Uvicorn without changes."
Reality: WSGI and ASGI have different interfaces. Running a WSGI app on an ASGI server requires an adapter (`WsgiToAsgi`). The app itself runs synchronously inside the adapter and blocks the event loop during request processing — you get ASGI deployment without ASGI concurrency benefits.

---

## Why It Matters in Practice

When to choose ASGI (FastAPI/Starlette/Django async):
- WebSockets, Server-Sent Events, long-polling
- High-concurrency I/O-heavy services (many simultaneous requests to external APIs/databases)
- Streaming responses

When WSGI is fine (Flask/Django sync):
- Simple CRUD with synchronous ORM (SQLAlchemy sync, Django ORM)
- CPU-bound work (adding more processes handles scale)
- Teams not yet comfortable with async Python

---

## Interview Angle

Common question forms:
- "What is the difference between WSGI and ASGI?"
- "Why does FastAPI require Uvicorn?"

Answer frame: WSGI is a synchronous callable (`def app(environ, start_response)`) — one thread handles one request. ASGI is async (`async def app(scope, receive, send)`) — one event loop handles many concurrent connections. ASGI adds WebSocket support. FastAPI is ASGI-only. Gunicorn is WSGI-native; Uvicorn is ASGI-native; production uses Gunicorn with `UvicornWorker` to get both process supervision and async concurrency.

---

## Related Notes

- [[wsgi|WSGI]]
- [[asgi|ASGI]]
- [[uvicorn|Uvicorn]]
- [[fastapi|FastAPI]]
