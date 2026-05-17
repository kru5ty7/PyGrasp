---
title: FastAPI
description: FastAPI is a modern Python web framework built on Starlette and Pydantic — it uses type annotations to auto-generate validation, serialization, and OpenAPI documentation, while delegating all ASGI infrastructure to Starlette underneath.
tags: [fastapi, starlette, pydantic, asgi, routing, validation, openapi, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# FastAPI

> FastAPI is a modern Python web framework built on Starlette and Pydantic — it uses type annotations to auto-generate validation, serialization, and OpenAPI documentation, while delegating all ASGI infrastructure to Starlette underneath.

---

## Quick Reference

**Core idea:**
- FastAPI is a **Starlette subclass**: all routing, middleware, WebSocket, and ASGI handling comes from Starlette; FastAPI adds type inspection on top
- Route handlers use **Python type annotations** to declare expected inputs — FastAPI inspects these at registration time and wires up validation, parsing, and serialization automatically
- `@app.get("/path")`, `@app.post("/path")`, etc. register routes and simultaneously generate OpenAPI schema entries
- **Pydantic models** as parameter types trigger body parsing and validation; primitive types in path/query positions are parsed from the URL
- `Depends()` is FastAPI's dependency injection mechanism — declare dependencies as function parameters and FastAPI resolves the full graph before calling the handler
- The `lifespan` async context manager is the correct place to initialize and clean up shared resources (DB pools, HTTP clients)

**Tricky points:**
- `async def` handlers run on the event loop; `def` (sync) handlers are run in a thread pool — FastAPI detects which and acts accordingly
- Path parameters, query parameters, request body, and headers are distinguished **by position and type**: path params match `{name}` in the path, body params come from Pydantic models, query params are everything else
- `Response` returned from a handler is used directly — FastAPI does **not** re-serialize a `Response` object through Pydantic, even if `response_model` is set
- `response_model` filters and validates the **output** — fields not in the response model are excluded from the response even if the handler returns them
- `HTTPException` is a Starlette exception; FastAPI handles it by returning a JSON error response — it is not the same as a Pydantic `ValidationError`

---

## What It Is

Think of FastAPI as a type-annotation interpreter layered on top of a well-built chassis. The chassis is Starlette: it handles TCP connections, HTTP parsing, routing, middleware, and WebSocket support. FastAPI's contribution is an interpreter that reads the type annotations on your route handler functions and, from those annotations alone, figures out how to validate incoming requests, parse path parameters from the URL, extract query parameters, deserialize the request body into Python objects, and serialize the return value back into JSON — all without you writing any of that logic yourself. You write the type annotations; FastAPI writes the plumbing.

The practical effect is dramatic compression of boilerplate. A route handler in a lower-level framework might require: manually parsing path parameters from the URL string, calling `request.json()` and catching JSON decode errors, validating required fields, returning a 422 response for invalid input, serializing the response dict, and setting the Content-Type header. In FastAPI, all of that disappears. You annotate the parameter as a Pydantic model, annotate the return type, and FastAPI handles every step between the raw ASGI event and your Python objects.

FastAPI also uses those same type annotations to generate OpenAPI documentation. Every route, its parameters, its expected request body shape, and its response shape are all derivable from the type annotations, and FastAPI derives them automatically. The `/docs` endpoint (Swagger UI) and `/redoc` endpoint are served by default, requiring no configuration. This is not a documentation-generation afterthought — it is the same type information used for validation, reused for documentation, which means the documentation is always in sync with the actual validation rules.

---

## How It Actually Works

At route registration time — when FastAPI processes `@app.get("/items/{item_id}")` — it calls `inspect.signature()` on the decorated function and examines every parameter. Parameters whose names appear in the path template are treated as path parameters; their type annotations determine how to convert the URL segment (always a string) into the Python type. Parameters annotated with Pydantic model types are treated as request body parameters. Remaining non-path parameters with simple types (`str`, `int`, `float`, `bool`, optional types) are treated as query parameters. Parameters with `Depends()` defaults are dependency declarations. FastAPI stores this resolved parameter map on the route at registration time — it does not inspect signatures on every request.

At request time, FastAPI's `APIRoute` class constructs a `request.args` dict, extracts path parameters from the matched URL, parses the query string, and reads the request body as JSON. It then runs Pydantic validation on the body if a model parameter was declared, converts path and query parameters to their annotated types, resolves all `Depends()` dependency chains, and passes the fully validated values to the handler. If Pydantic validation fails, FastAPI catches the `ValidationError` and returns an HTTP 422 response with a structured JSON body listing every validation failure. This error response shape is itself part of the OpenAPI schema.

The return value from the handler goes through `jsonable_encoder()`, which recursively converts Python objects — Pydantic models, dataclasses, `datetime`, `UUID`, `Enum` — into JSON-serializable primitives. If `response_model` was set on the route decorator, FastAPI first filters the return value through that model (constructing a model instance from the return value and then serializing it), which drops any fields not declared in the model and runs output validation. The final serialized dict is passed to a `JSONResponse`, which handles the ASGI `send` events. Everything after the handler returns is Starlette's code.

The `lifespan` parameter accepts an async context manager that FastAPI (via Starlette) runs via the ASGI lifespan protocol. Code before the `yield` runs at startup; code after runs at shutdown. Resources created in startup — a SQLAlchemy `async_sessionmaker`, an `httpx.AsyncClient`, a loaded ML model — should be stored somewhere accessible to dependency functions, typically on `app.state` or as module-level variables assigned during startup. The lifespan context manager is the correct pattern because it guarantees cleanup even on SIGTERM.

---

## How It Connects

FastAPI is a Starlette subclass. Every `@app.get()` route is stored as a Starlette `APIRoute` (a subclass of `Route`). Middleware added to FastAPI is added to the Starlette middleware stack. `Mount` and `StaticFiles` work identically to their Starlette counterparts. Understanding Starlette is understanding what FastAPI does at the ASGI level — FastAPI's own code is primarily the type-annotation inspection layer.
[[starlette|Starlette]]

FastAPI's validation and serialization are entirely delegated to Pydantic. When you annotate a route parameter with a Pydantic model, FastAPI passes the raw data to Pydantic's `model_validate()` and re-raises any `ValidationError` as an HTTP 422 response. The `response_model` feature calls `model_from_orm()` or constructs the model from the handler's return value. FastAPI does not implement its own validation logic.
[[pydantic|Pydantic]]

FastAPI's `Depends()` mechanism implements dependency injection — the system that resolves database sessions, authentication tokens, shared clients, and configuration objects before passing them to route handlers. The dependency resolution is the mechanism that makes FastAPI routes composable and testable.
[[dependency-injection|Dependency Injection]]

FastAPI runs on an `asyncio` event loop provided by Uvicorn. `async def` handlers run directly on the event loop as coroutines. `def` (synchronous) handlers are wrapped in `asyncio.to_thread()` (or `run_in_executor`) so they do not block the event loop. Whether a handler blocks the event loop or not depends on whether it uses `async def` — this has direct throughput implications.
[[async-await|Async and Await]]

---

## Common Misconceptions

Misconception 1: "FastAPI validates data at runtime by inspecting type annotations."
Reality: FastAPI reads annotations at **route registration time** (once, at startup) using `inspect.signature()`. At runtime, it uses the resolved parameter map built during registration. The actual validation at runtime is done by Pydantic, not by FastAPI inspecting annotations. FastAPI's role is to route raw request data to the correct Pydantic model and handle the `ValidationError` if one is raised.

Misconception 2: "A `def` (synchronous) handler in FastAPI blocks all other requests."
Reality: FastAPI detects whether a handler is `async def` or `def` and acts differently. `async def` handlers run directly on the event loop. `def` handlers are run in a thread pool executor (via `asyncio.run_in_executor`), so they do not block the event loop — other requests continue processing concurrently while the synchronous handler runs in a separate thread. The implication: if your synchronous handler makes I/O calls, those calls block their thread but not the event loop. The thread pool has a finite size, however — many simultaneous blocking `def` handlers can exhaust threads.

---

## Why It Matters in Practice

FastAPI's `response_model` is important for security as well as correctness. If your handler queries a user record from a database and returns the ORM object directly, without `response_model`, every field on that object — including hashed passwords, internal flags, and audit fields — is serialized into the response. `response_model` is the mechanism that prevents accidental data leakage: declare only the fields that should be in the response, and FastAPI will exclude everything else.

The distinction between `async def` and `def` handlers has concrete throughput consequences. A route that calls an external HTTP API using `requests` (the synchronous library) must be `def`, not `async def`, because `requests` calls block the thread. If it were `async def`, it would block the event loop and prevent all other requests from processing. The correct approach is either to use `async def` with an async HTTP client like `httpx.AsyncClient`, or to keep `def` and let FastAPI run it in the thread pool. Mixing `asyncio`-level concerns with synchronous blocking code inside `async def` handlers is one of the most common FastAPI performance bugs.

---

## Interview Angle

Common question forms:
- "How does FastAPI differ from Flask or Django?"
- "How does FastAPI handle request validation?"
- "What is the relationship between FastAPI and Pydantic/Starlette?"

Answer frame: FastAPI is a Starlette subclass with a type-annotation inspection layer. At route registration, it inspects handler signatures to build a parameter map; at request time, it routes raw data through Pydantic for validation and passes validated values to the handler. Starlette provides all ASGI infrastructure. Pydantic provides all validation. FastAPI's contribution is the bridge between them, plus OpenAPI schema generation from the same annotations. Distinguish `async def` handlers (event loop, non-blocking) from `def` handlers (thread pool, also non-blocking at the event loop level). Explain `response_model` for output filtering.

---

## Related Notes

- [[starlette|Starlette]]
- [[pydantic|Pydantic]]
- [[dependency-injection|Dependency Injection]]
- [[asgi|ASGI]]
- [[uvicorn|Uvicorn]]
- [[openapi|OpenAPI]]
