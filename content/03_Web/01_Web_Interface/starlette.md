---
title: 06 - Starlette
description: Starlette is a lightweight ASGI framework that provides routing, middleware, request/response abstractions, WebSocket support, and background tasks  -  it is the foundation FastAPI is built on, and understanding it reveals what FastAPI does beneath its type-annotation layer.
tags: [starlette, asgi, framework, routing, middleware, websockets, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Starlette

> Starlette is a lightweight ASGI framework that provides routing, middleware, request/response abstractions, WebSocket support, and background tasks  -  it is the foundation FastAPI is built on, and understanding it reveals what FastAPI does beneath its type-annotation layer.

---

## Quick Reference

**Core idea:**
- Starlette is an **ASGI framework**: it implements the `async def app(scope, receive, send)` interface and provides routing, `Request`/`Response` objects, middleware, and WebSocket support
- A Starlette `Route` maps a URL path + HTTP method to an async function that accepts a `Request` and returns a `Response`
- Middleware is added via `Starlette(middleware=[Middleware(SomeMiddleware, **kwargs)])`  -  applies to all routes
- `BackgroundTask`/`BackgroundTasks` run coroutines after the response is sent  -  useful for non-blocking post-response work
- **FastAPI is a Starlette subclass**  -  `FastAPI` inherits from `Starlette` and adds type annotation inspection, Pydantic validation, and OpenAPI generation

**Tricky points:**
- Starlette's `Request.body()` is a **coroutine**  -  you must `await request.body()` to get bytes; `request.json()` is also async
- `Response` objects are **not returned** from handlers in ASGI terms  -  the handler calls the ASGI `send` callable internally; the `Response` abstraction handles this for you
- `TestClient` in `starlette.testclient` runs the ASGI app **synchronously** using a requests-compatible interface  -  it uses `anyio` to run the async app in a sync context
- `StaticFiles` and `Mount` allow sub-applications  -  any ASGI app can be mounted at a path prefix, enabling modular composition
- Starlette's `@app.route()` decorator is a lower-level API than FastAPI's `@app.get()`  -  it does no type-checking or validation

---

## What It Is

Think of Starlette as the chassis of a car. The chassis is the structural frame  -  wheels, axles, engine mount, suspension. It does not define what the car looks like on the outside, and it does not include the dashboard instruments. FastAPI is the complete car: it takes the Starlette chassis, adds the instrument panel (type annotation inspection), the automatic transmission (Pydantic validation), and the manual (OpenAPI documentation generation). If something unexpected happens in a FastAPI application, you often find the answer by looking at what Starlette does, because FastAPI delegates most of the actual ASGI handling to it.

Starlette sits between the raw ASGI interface and a developer-friendly routing and request/response API. Receiving raw ASGI events and sending raw responses is possible but verbose  -  you would manually build the `scope` checks, parse headers from byte tuples, and write response events. Starlette wraps this into clean objects: a `Request` object that gives you `request.method`, `request.url`, `request.headers`, `await request.json()`, and a family of `Response` classes (`JSONResponse`, `HTMLResponse`, `PlainTextResponse`, `StreamingResponse`) that handle the response event sequence for you.

Starlette is deliberately minimal. It provides the infrastructure layer  -  routing, middleware, request parsing, response serialization, WebSocket support, static file serving  -  without prescribing how you structure your application logic. It has no built-in ORM integration, no authentication system, no input validation beyond what you write yourself. These are left to libraries or to frameworks built on top of Starlette. FastAPI is the most prominent such framework, adding validation and documentation through its type annotation layer.

---

## How It Actually Works

Starlette's `Router` is an ASGI app. When called with `(scope, receive, send)`, it inspects `scope["type"]` to determine the connection type, then matches `scope["path"]` against its registered routes. For a matching route, it creates a `Request` object wrapping `scope` and `receive`, calls the route handler, and calls the handler's response with `send`. Routes are stored as a list of `Route`, `WebSocketRoute`, and `Mount` objects, checked in registration order.

Middleware in Starlette follows the ASGI wrapping pattern. Each middleware is an ASGI app that wraps the inner app: it receives `(scope, receive, send)`, optionally modifies them, calls the inner app, and optionally processes the result. `Starlette(middleware=[Middleware(CORSMiddleware, allow_origins=["*"])])` builds a chain: each middleware wraps the next, with the `Router` at the innermost layer. A request passes through the middleware chain from outermost to innermost on the way in, and from innermost to outermost on the way out.

`BackgroundTasks` are managed by wrapping the `send` callable. When a handler adds background tasks and returns a response, Starlette's response object runs the tasks after sending `"http.response.body"` with `more_body=False`. Because ASGI is coroutine-based, background tasks run on the same event loop  -  they are not on separate threads. This means they must be async-friendly; CPU-bound background work should still use `asyncio.to_thread()` or a task queue.

`WebSocket` support in Starlette provides a `WebSocket` object that wraps the ASGI receive/send interface for the `"websocket"` scope type. `await websocket.accept()` sends the `"websocket.accept"` event. `await websocket.receive_text()` calls `receive()` until a `"websocket.receive"` event arrives. `await websocket.send_text(data)` sends a `"websocket.send"` event. The WebSocket remains open until `await websocket.close()` or a disconnect event.

---

## How It Connects

Starlette is an ASGI application  -  every `Route` handler receives an ASGI scope, receive, and send, abstracted behind `Request` and `Response`. Understanding ASGI is understanding what Starlette sits on top of and what it hides from the developer.
[[asgi|ASGI]]

FastAPI subclasses Starlette. Every route registered with `@app.get()` in FastAPI is ultimately stored as a Starlette `Route`. The request parsing, middleware execution, and response sending are all Starlette's code. FastAPI's additions  -  type annotation inspection, Pydantic validation, `Depends()` resolution, OpenAPI schema generation  -  wrap around and complement Starlette's infrastructure.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "FastAPI and Starlette are competing frameworks."
Reality: FastAPI is built directly on Starlette. `FastAPI` is a subclass of `Starlette`. All of Starlette's routing, middleware, WebSocket, and static file features are available in FastAPI. FastAPI adds validation, dependency injection, and automatic documentation on top. Choosing FastAPI does not mean leaving Starlette behind  -  you are using both simultaneously.

Misconception 2: "Starlette's `TestClient` tests async code by running it asynchronously."
Reality: `TestClient` runs the ASGI app synchronously using `anyio` under the hood. It spins up a test server in a thread, makes HTTP requests to it using a `requests`-compatible API, and tears it down after the test. This means `TestClient` tests are synchronous test functions  -  they do not use `async def` or `await`. For testing async code that cannot run through HTTP (utility functions, async helpers), use `pytest-anyio` or `pytest-asyncio` with `async def` test functions directly.

---

## Why It Matters in Practice

Starlette matters for FastAPI developers because FastAPI's behavior at the ASGI level is Starlette's behavior. When you add a middleware to FastAPI, you are adding it to the Starlette Router. When you mount a sub-application, you are using Starlette's `Mount`. When you use `BackgroundTasks`, you are using Starlette's implementation. FastAPI's documentation covers the API layer; Starlette's documentation covers the infrastructure layer. Both are necessary for a complete understanding of what a FastAPI application does.

Starlette is also a good direct choice when you need a minimal ASGI framework without FastAPI's opinionated conventions. If you are building an API gateway, a reverse proxy, a WebSocket server, or a streaming endpoint where Pydantic validation is unnecessary or counterproductive, Starlette's direct ASGI access gives you control that FastAPI's abstractions hide. The `Router` and `Mount` primitives enable building modular ASGI applications where different sub-applications handle different paths.

---

## Interview Angle

Common question forms:
- "What is the relationship between Starlette and FastAPI?"
- "How does Starlette handle middleware?"
- "How would you add WebSocket support to a Starlette/FastAPI app?"

Answer frame: Define Starlette as a lightweight ASGI framework providing routing, request/response abstractions, and middleware. State the FastAPI relationship: FastAPI is a Starlette subclass that adds type annotation inspection, Pydantic validation, and OpenAPI generation. Explain middleware as ASGI wrapping  -  each middleware wraps the inner app, forming a chain. For WebSockets: `WebSocketRoute` with a handler receiving a `WebSocket` object; call `accept()`, then loop on `receive_text()`/`send_text()` until disconnect.

---

## Related Notes

- [[asgi|ASGI]]
- [[fastapi|FastAPI]]
- [[uvicorn|Uvicorn]]
