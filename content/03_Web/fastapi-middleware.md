---
title: Middleware in FastAPI
description: "FastAPI middleware wraps every request and response — declared with `@app.middleware('http')` or `app.add_middleware()`; runs before route matching and after response generation; used for logging, timing, authentication, request ID injection, and error handling."
tags: [fastapi, middleware, ASGI, request-processing, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Middleware in FastAPI

> FastAPI middleware wraps every request and response — declared with `@app.middleware('http')` or `app.add_middleware()`; runs before route matching and after response generation; used for logging, timing, authentication, request ID injection, and error handling.

---

## Quick Reference

**Core idea:**
- `@app.middleware("http")` — decorates an async function `(request, call_next)` that wraps every HTTP request
- `call_next(request)` — calls the next middleware or the route handler; returns the `Response`
- `app.add_middleware(SomeMiddlewareClass, param=value)` — adds class-based middleware (ASGI middleware)
- Execution order: middleware is a stack — added last runs outermost (first for requests, last for responses)
- Built-in middleware: `CORSMiddleware`, `GZipMiddleware`, `TrustedHostMiddleware`, `HTTPSRedirectMiddleware`

**Tricky points:**
- `@app.middleware("http")` runs after Starlette's exception handling — unhandled exceptions in the route are already converted to responses before the middleware sees them; use `try/except` around `call_next` to catch them
- Middleware cannot access the request body directly without consuming it — body is a stream; reading it in middleware and passing it on requires buffering (not recommended for large files)
- `response.body` is not directly accessible in middleware — the response body may stream; use `BackgroundTask` or `response.headers` for post-processing without reading the body
- Adding too many `@app.middleware("http")` decorators can impact performance — each one wraps all requests; keep middleware focused
- Class-based ASGI middleware (inheriting from `BaseHTTPMiddleware`) has subtleties with streaming responses — the `BaseHTTPMiddleware` approach can buffer responses unexpectedly

---

## What It Is

Middleware is a pipeline that every request travels through before reaching a route handler and every response travels through before reaching the client. It's the correct place for cross-cutting concerns that apply uniformly across all (or most) endpoints: logging request/response times, injecting correlation IDs, enforcing HTTPS, handling GZIP compression.

Think of it as an onion: each middleware layer wraps the inner layer. Request processing goes inward (outer middleware → inner → handler); response processing goes outward (handler → inner → outer).

---

## How It Actually Works

Custom timing middleware:
```python
import time
import uuid
from fastapi import FastAPI, Request

app = FastAPI()

@app.middleware("http")
async def timing_and_request_id(request: Request, call_next):
    request_id = str(uuid.uuid4())
    start = time.perf_counter()
    
    response = await call_next(request)
    
    elapsed = time.perf_counter() - start
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Process-Time"] = f"{elapsed:.4f}"
    return response
```

Class-based middleware (CORS example — using the built-in):
```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.example.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

Error handling in middleware:
```python
@app.middleware("http")
async def error_handler(request: Request, call_next):
    try:
        response = await call_next(request)
        return response
    except Exception as e:
        # Log unexpected errors
        logger.exception(f"Unhandled error: {e}")
        return JSONResponse(status_code=500, content={"detail": "Internal server error"})
```

Middleware order (last added = outermost):
```python
app.add_middleware(CORSMiddleware, ...)   # added second → outermost (handles CORS first)
app.add_middleware(GZipMiddleware, ...)   # added first → inner
```

---

## How It Connects

Middleware is an ASGI concept — it sits between the ASGI server and the FastAPI application, wrapping the ASGI interface.
[[asgi|ASGI]]

CORS is implemented as middleware — the `CORSMiddleware` adds `Access-Control-*` headers based on configuration.
[[cors|CORS]]

---

## Common Misconceptions

Misconception 1: "Middleware runs after dependency injection."
Reality: Middleware runs at the ASGI level, before FastAPI's routing and dependency injection. This means middleware cannot access FastAPI route parameters or injected dependencies. For logic that needs route context, use `Depends()` instead.

Misconception 2: "`@app.middleware('http')` and `app.add_middleware()` are equivalent."
Reality: `@app.middleware("http")` creates a function-based middleware wrapped in `BaseHTTPMiddleware`. `app.add_middleware()` adds an ASGI middleware class. The `BaseHTTPMiddleware` wrapper has known limitations with streaming responses — pure ASGI middleware (`add_middleware`) is more correct for streaming use cases.

---

## Why It Matters in Practice

Correlation ID pattern (essential for distributed tracing):
```python
import contextvars

request_id_var: contextvars.ContextVar[str] = contextvars.ContextVar("request_id", default="")

@app.middleware("http")
async def set_request_id(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    request_id_var.set(request_id)
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response
```

Every log line can include `request_id_var.get()` — all logs for a single request share the same ID, making distributed tracing possible.

---

## Interview Angle

Common question forms:
- "How do you add request logging to a FastAPI app?"
- "Where does middleware fit in FastAPI's request lifecycle?"

Answer frame: Middleware wraps every request — runs before the route handler and after the response. `@app.middleware("http")` for function-based; `app.add_middleware(Class)` for class-based. Execution order: last added runs first for requests. Use cases: timing, request IDs, CORS, GZip, HTTPS redirect. For logic needing route context (DB, auth), use `Depends()` instead of middleware.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[cors|CORS]]
- [[asgi|ASGI]]
- [[fastapi-dependencies|FastAPI Dependencies]]
