---
title: HTTP Request Lifecycle in FastAPI
description: The full lifecycle of an HTTP request through a FastAPI application — from TCP bytes arriving at Uvicorn, through the ASGI interface, Starlette's middleware and routing, FastAPI's validation, the handler, and back out as a response.
tags: [http, request-lifecycle, fastapi, asgi, uvicorn, starlette, middleware, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# HTTP Request Lifecycle in FastAPI

> The full lifecycle of an HTTP request through a FastAPI application — from TCP bytes arriving at Uvicorn, through the ASGI interface, Starlette's middleware and routing, FastAPI's validation, the handler, and back out as a response.

---

## Quick Reference

**Core idea:**
- A request travels through 5 distinct layers: **Uvicorn → ASGI scope/receive/send → Starlette middleware chain → FastAPI routing and validation → handler → response back out**
- Uvicorn parses raw TCP bytes into HTTP components and builds the `scope` dict; it then calls `await app(scope, receive, send)`
- Starlette's middleware chain is entered outermost-first; each middleware wraps the inner app and can modify the request or short-circuit the response
- FastAPI's `APIRoute` resolves path params, validates query params and body via Pydantic, resolves `Depends()` graph, calls the handler
- The response travels back through the middleware chain in reverse order before Uvicorn writes bytes to the TCP socket

**Tricky points:**
- Middleware runs **before** routing — a middleware cannot know which route matched; it sees only the raw request
- **Generator dependencies** (those that `yield`) have their cleanup run **after** the response is sent — their `finally` blocks run in the response teardown phase, not before the response
- A `def` (sync) handler is dispatched to a **thread pool** by Starlette's `run_in_executor` — it does not block the event loop but it does occupy a thread
- **Exception handlers** registered with `@app.exception_handler(SomeException)` intercept exceptions raised during handler execution, **after** middleware has already processed the request
- Request body reading is lazy — `await request.body()` or `await request.json()` pulls from the `receive` queue; the body is not pre-read by the middleware or routing layer

---

## What It Is

Think of a large hospital emergency department. A patient arrives at the entrance (the TCP connection). The receptionist (Uvicorn) triages them: checks insurance, fills out the standard admission form (the ASGI scope), and calls the appropriate department. The patient is then passed through a series of checkpoints (middleware): security, infection control, triage nursing — each checkpoint can send the patient through or turn them away. Finally the patient reaches the specialist (the route handler) who diagnoses and treats them. The specialist's response travels back through the same checkpoints on the way out, and the receptionist formally discharges the patient (sends the HTTP response bytes). Understanding this path in detail explains every behavior you observe in a FastAPI application — where headers are set, where authentication runs, why some code runs after the response.

The lifecycle matters for debugging and architecture. Knowing that middleware cannot see the matched route explains why route-specific logic does not belong in middleware. Knowing that dependency cleanup runs after the response explains why a database session closed in a generator dependency's `finally` block does not delay the client — the client has already received the response before the cleanup runs. Knowing that Uvicorn, Starlette, and FastAPI are three distinct layers with distinct responsibilities means a bug in request handling can be attributed to the correct layer and diagnosed appropriately.

---

## How It Actually Works

**Phase 1 — Uvicorn: TCP to ASGI.** The event loop fires when a new TCP connection arrives. Uvicorn's `HttpToolsProtocol` feeds incoming bytes to `httptools`, which parses them incrementally. On `on_headers_complete`, Uvicorn constructs the `scope` dict: `{"type": "http", "method": "POST", "path": "/items/42", "query_string": b"include_deleted=false", "headers": [...], ...}`. It then calls `await app(scope, receive, send)`, where `app` is the outermost middleware layer. `receive` returns events from the internal queue as body chunks arrive; `send` writes bytes to the socket as the application emits response events.

**Phase 2 — Starlette middleware chain.** Each middleware was registered as a wrapper around the inner app during application startup. A `CORSMiddleware`, for example, wraps the router: it checks `scope["headers"]` for an `Origin` header, and if the request is a CORS preflight, it calls `await send(...)` directly to return the preflight response, never calling the inner app. For regular requests, it calls `await call_next(request)`, which calls the inner app, and then adds CORS headers to the response before returning. The middleware chain processes the request inward (outer middleware first) and the response outward (outer middleware last).

**Phase 3 — Starlette router: route matching.** The `Router` inspects `scope["path"]` and `scope["method"]`, iterates its registered routes in order, and finds the first matching `APIRoute`. It extracts path parameters from the URL (e.g., `item_id=42` from `/items/42`) and stores them in `scope["path_params"]`. It creates a `Request` object wrapping `scope` and `receive`, and calls `await route.handle(scope, receive, send)`.

**Phase 4 — FastAPI APIRoute: validation and dependency resolution.** The `APIRoute.handle()` method uses the pre-built parameter map to extract values: path parameters from `scope["path_params"]`, query parameters from `scope["query_string"]`, and body by calling `await request.json()` if a body parameter was declared. Body data is passed to Pydantic's `model_validate()`. If validation fails, a `RequestValidationError` is raised, which FastAPI's default exception handler converts to a 422 JSON response. If validation succeeds, FastAPI resolves the `Depends()` graph — calling each dependency function in leaf-first order, caching results within the request — and calls the handler with the fully resolved arguments.

**Phase 5 — Handler execution and response.** If the handler is `async def`, FastAPI `await`s it directly on the event loop. If it is `def`, FastAPI dispatches it to the thread pool via `asyncio.run_in_executor()` and `await`s the future — the event loop can process other requests while this handler runs in a thread. The handler's return value passes through `jsonable_encoder()` and optionally through the `response_model` filter, then into a `JSONResponse`. The `JSONResponse.__call__(scope, receive, send)` emits the `http.response.start` and `http.response.body` ASGI events.

**Phase 6 — Response teardown.** After `http.response.body` with `more_body=False` is sent, generator dependencies run their post-yield cleanup in `finally` blocks. BackgroundTasks, if any, run now — the client has received the response and the tasks execute on the event loop without blocking any future request.

**Phase 7 — Uvicorn: ASGI to TCP.** The `send` callable in Uvicorn writes the status line, headers, and body to the TCP socket buffer. Uvicorn's transport layer flushes the buffer and optionally closes the connection (for HTTP/1.0 or `Connection: close`) or returns it to the connection pool (for HTTP/1.1 keep-alive). The event loop is free to handle the next request on this connection or new connections from other clients.

---

## How It Connects

Uvicorn is the first and last layer in this lifecycle — it translates TCP bytes into ASGI events at the start, and ASGI events back into TCP bytes at the end. Its `httptools`-based parser and `uvloop` event loop are what make high-concurrency FastAPI deployments possible.
[[uvicorn|Uvicorn]]

The ASGI interface is the contract between Uvicorn and the application. The `scope` dict, `receive` callable, and `send` callable are the precise mechanism through which request data enters the application and response data exits it. Every layer described above is an implementation of the ASGI interface.
[[asgi|ASGI]]

Starlette's middleware chain and router form phases 2 and 3 of the lifecycle. Understanding Starlette's `Route`, `Mount`, and middleware wrapping pattern is understanding what happens between Uvicorn's call to `app(scope, receive, send)` and FastAPI's parameter resolution.
[[starlette|Starlette]]

FastAPI's parameter map, Pydantic validation, and dependency resolution form phase 4. These are the layers that transform raw HTTP data into typed Python objects and call the handler — the layer unique to FastAPI and absent in raw Starlette.
[[fastapi|FastAPI]]

The event loop is the thread on which phases 1 through 7 execute (except for synchronous handler dispatch). Understanding that a single event loop thread interleaves all of these phases across many concurrent connections explains why blocking the event loop — with a long synchronous call inside an `async def` handler — degrades performance for all connections simultaneously.
[[event-loop|The Event Loop]]

---

## Common Misconceptions

Misconception 1: "Middleware can modify which route handles a request."
Reality: Middleware runs before routing. By the time a middleware processes a request, no route matching has occurred. Middleware can redirect requests (by calling `send` directly without calling the inner app), can modify the path in scope, or can reject the request entirely. But middleware cannot conditionally route to different handlers — that is the router's job. If you need route-specific behavior, use a dependency or the `APIRoute` class directly.

Misconception 2: "Generator dependency cleanup happens before the response reaches the client."
Reality: Generator dependencies run their post-yield code in a teardown phase that begins after the response body event has been sent to the client. The client receives the response, and then the database session is closed, the file is flushed, the lock is released. This is intentional — cleanup should not delay the client. It does mean that if cleanup raises an exception, that exception occurs after the response and cannot change the HTTP status code or response body the client received.

---

## Why It Matters in Practice

Tracing a bug through this lifecycle is the most reliable debugging approach. A request that returns 422 with no body touched your code only as far as phase 4 — Pydantic validation failed before the handler was called. A request that returns 500 after the handler ran means the exception was raised during execution and caught by an exception handler. A request that returns correct data but with missing headers means middleware that was supposed to add those headers did not run — either the middleware was not registered or it short-circuited before calling the inner app.

The ordering of middleware registration matters because of how the chain is constructed. Middleware registered last wraps everything registered before it — it is the outermost layer and sees requests first. This means authentication middleware should be registered last (to run first), and logging or metrics middleware that should capture request duration including auth time should be registered even later (wrapped around auth). The Starlette documentation and FastAPI documentation describe this as "the last middleware added is the first to run" — an important inversion of the intuitive order.

---

## Interview Angle

Common question forms:
- "Walk me through what happens when a request hits a FastAPI endpoint."
- "Where does authentication run in a FastAPI request?"
- "When does database session cleanup happen in a FastAPI app using generator dependencies?"

Answer frame: Describe the 7 phases: TCP bytes → Uvicorn parses → ASGI scope/receive/send built → middleware chain (outermost first) → Starlette router matches → FastAPI validates and resolves dependencies → handler runs (event loop or thread pool) → response events sent → generator dependency cleanup → background tasks. Locate authentication: in middleware (before routing) or in a dependency (after routing, before handler). Locate DB session cleanup: after response is sent. Explain the event loop thread — single-threaded, interleaved; `async def` handlers run on it, `def` handlers in thread pool.

---

## Related Notes

- [[uvicorn|Uvicorn]]
- [[asgi|ASGI]]
- [[starlette|Starlette]]
- [[fastapi|FastAPI]]
- [[event-loop|The Event Loop]]
- [[http-basics|HTTP Basics]]
