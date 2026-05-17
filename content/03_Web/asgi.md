---
title: ASGI
description: ASGI (Asynchronous Server Gateway Interface) is the async successor to WSGI — it defines how async-capable Python web servers communicate with applications, supporting HTTP, WebSockets, and long-lived connections that the synchronous WSGI model cannot handle.
tags: [asgi, async, websockets, http, interface, starlette, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# ASGI

> ASGI (Asynchronous Server Gateway Interface) is the async successor to WSGI — it defines how async-capable Python web servers communicate with applications, supporting HTTP, WebSockets, and long-lived connections that the synchronous WSGI model cannot handle.

---

## Quick Reference

**Core idea:**
- An ASGI app is an **async callable**: `async def app(scope, receive, send)` — no return value
- `scope` — a dict describing the connection type (`"http"`, `"websocket"`, `"lifespan"`) and its metadata
- `receive` — an async callable the app calls to get the next event (request body chunk, WebSocket message, etc.)
- `send` — an async callable the app calls to send events (response start, response body, WebSocket message, etc.)
- ASGI supports **HTTP, WebSockets, and lifespan** (startup/shutdown hooks) natively in the same interface

**Tricky points:**
- ASGI is **event-driven, not request-driven** — an HTTP request is a sequence of events (connection, body chunks, disconnect), not a single `environ` dict
- `scope` is created **once per connection** for WebSockets (long-lived); for HTTP, it is created per request
- The `lifespan` scope type is how ASGI apps do startup/shutdown — send `"lifespan.startup.complete"` after initializing resources; this replaces WSGI's lack of lifecycle hooks
- ASGI middleware wraps the app: `wrapped = Middleware(app, **kwargs)`; `await wrapped(scope, receive, send)`
- A WSGI app can run under an ASGI server via `a2wsgi.WSGIMiddleware(wsgi_app)` — a shim that runs the WSGI app in a thread pool

---

## What It Is

Think of the difference between a standard mail service (WSGI) and a real-time communication system like a phone call or instant messaging (ASGI). The mail service is simple: you drop a letter in the slot, it is delivered, you get a reply, the transaction is complete. The phone system handles something more complex: both parties stay connected, either can speak at any time, and the connection persists until both agree to hang up. WSGI handles letters. ASGI handles phone calls — and also letters, since it is backward-compatible with the simple request-response model.

ASGI was designed to solve the problems WSGI cannot. WebSockets require a persistent connection over which either side can send messages at any time. HTTP/2 server push requires the server to initiate data transfers. Long-polling requires a request to stay open for an extended period. None of these fit WSGI's model of "one call, one response." ASGI uses an event-based model instead: the application receives an async callable it calls to get the next event (a WebSocket message arriving, a request body chunk being received) and another callable it calls to send events (a response chunk, a WebSocket message). The connection can stay open for as long as needed.

The ASGI interface is: an `async def` callable that takes three arguments. `scope` is a dict describing what kind of connection this is — `"http"` for a regular request, `"websocket"` for a WebSocket connection, or `"lifespan"` for startup/shutdown events. `receive` is an async callable that the app calls to await the next event from the client. `send` is an async callable that the app calls to send an event to the client. For an HTTP request, the app calls `receive()` to get the request body and `send()` twice — once with the response headers and once with the response body.

---

## How It Actually Works

For an HTTP request under ASGI, the exchange works as a sequence of events. The server calls the app with a scope dict containing `type: "http"`, the method, path, headers, and other metadata. The app calls `await receive()` to get the request body event (`{"type": "http.request", "body": b"...", "more_body": False}`). Then the app calls `await send({"type": "http.response.start", "status": 200, "headers": [...]})` to send the response status and headers. Finally, the app calls `await send({"type": "http.response.body", "body": b"...", "more_body": False})` to send the body. The `more_body` flag allows streaming large responses in chunks.

For a WebSocket connection, the scope has `type: "websocket"`. The app calls `await receive()` to get events: `"websocket.connect"` when the client connects, `"websocket.receive"` for each incoming message, `"websocket.disconnect"` when the client disconnects. The app calls `await send()` to send `"websocket.accept"` (accepting the connection) and `"websocket.send"` events (sending messages back). The connection stays open until a disconnect event is received or the app sends a `"websocket.close"` event.

The `lifespan` scope is ASGI's solution to a WSGI pain point. WSGI has no standard way to run code at application startup (to create a database connection pool) or shutdown (to close it cleanly). ASGI defines a `lifespan` protocol: on startup, the server sends a `"lifespan.startup"` event; the app initializes resources and responds with `"lifespan.startup.complete"`. On shutdown, the server sends `"lifespan.shutdown"` and the app cleans up. FastAPI exposes this as the `lifespan` context manager parameter on the `FastAPI()` constructor.

---

## How It Connects

ASGI is async by design — the application callable is `async def`, every event exchange uses `await`. The entire model is built on the coroutine and event loop infrastructure from Layer 2. A single ASGI server instance (Uvicorn) running on a single event loop can handle thousands of simultaneous WebSocket connections or HTTP requests, each as a separate coroutine, because the event loop interleaves their I/O waits.
[[async-await|Async and Await]]

WSGI is ASGI's synchronous predecessor. ASGI deliberately kept the core idea — a standard interface callable with a structured dict argument — while extending it from a synchronous request/response to an async event stream. Understanding WSGI's limitations explains every design decision ASGI made differently.
[[wsgi|WSGI]]

Starlette is the most widely used Python ASGI framework and the foundation that FastAPI is built on. Starlette implements the ASGI interface and provides routing, middleware, WebSocket support, and request/response abstractions on top of it. Understanding ASGI is what makes Starlette's behavior transparent.
[[starlette|Starlette]]

Uvicorn is the ASGI server implementation — the software that actually calls your ASGI app with `(scope, receive, send)`. Understanding ASGI explains exactly what Uvicorn does: it accepts TCP connections, builds the scope dict, creates the async receive/send callables, and calls your app.
[[uvicorn|Uvicorn]]

---

## Common Misconceptions

Misconception 1: "ASGI is just WSGI with async def."
Reality: ASGI is a different interface model, not just an async version of WSGI. WSGI passes a complete request in one call and expects a complete response iterable back. ASGI uses an event-stream model: the app and server exchange events over the lifetime of a connection. This is a fundamental difference that enables WebSockets, streaming responses, and long-lived connections — none of which are possible in the WSGI model regardless of whether you add `async`.

Misconception 2: "Using an ASGI server automatically makes my Django or Flask app async."
Reality: Running a WSGI app under an ASGI server (via a WSGI-to-ASGI shim like `a2wsgi`) runs the WSGI app in a thread pool. The app itself remains synchronous. You get the benefit of the ASGI server's efficient I/O handling at the TCP layer, but the app does not gain async concurrency. True ASGI benefits — single-threaded handling of thousands of connections — require the application to be written as an ASGI app (Starlette, FastAPI, Django in ASGI mode) with genuinely async handlers.

---

## Why It Matters in Practice

ASGI is why FastAPI can handle thousands of concurrent requests on a single server without Gunicorn's multi-process model. Each request is a coroutine that suspends at every database query, HTTP call, or file read. The event loop runs hundreds of these concurrently on one OS thread. The ASGI interface is what makes this possible: by receiving and sending events via async callables, the application integrates natively with the event loop rather than blocking a thread.

ASGI's lifespan protocol is also practically important. The correct way to manage shared resources in a FastAPI application — database connection pools, HTTP client sessions, ML model instances — is via the lifespan context manager. Resources initialized in lifespan startup are available for the entire application lifetime and cleaned up on shutdown, even if the server is interrupted. This is cleaner and more reliable than module-level initialization, which has no guaranteed cleanup path.

---

## Interview Angle

Common question forms:
- "What is ASGI and how does it differ from WSGI?"
- "How does ASGI handle WebSockets?"
- "What is the lifespan protocol in ASGI?"

Answer frame: Define ASGI as an async event-stream interface: `async def app(scope, receive, send)`. Contrast with WSGI: WSGI is one call per request with an environ dict and response iterable; ASGI is an ongoing event exchange over the connection lifetime. Explain the three scope types: http, websocket, lifespan. For WebSockets: app receives connect/message/disconnect events and sends accept/message/close events over the open connection. For lifespan: startup and shutdown hooks with explicit completion signals.

---

## Related Notes

- [[wsgi|WSGI]]
- [[http-basics|HTTP Basics]]
- [[async-await|Async and Await]]
- [[starlette|Starlette]]
- [[uvicorn|Uvicorn]]
