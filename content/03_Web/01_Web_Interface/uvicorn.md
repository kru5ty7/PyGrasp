---
title: 04 - Uvicorn
description: "Uvicorn is a fast ASGI server built on `uvloop` and `httptools`  -  it is the production server that accepts TCP connections, parses HTTP, and calls your ASGI application, sitting between the network and frameworks like FastAPI or Starlette."
tags: [uvicorn, asgi, server, uvloop, httptools, production, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Uvicorn

> Uvicorn is a fast ASGI server built on `uvloop` and `httptools`  -  it is the production server that accepts TCP connections, parses HTTP, and calls your ASGI application, sitting between the network and frameworks like FastAPI or Starlette.

---

## Quick Reference

**Core idea:**
- Uvicorn's role: **accept TCP connections -> parse HTTP -> build scope/receive/send -> call your ASGI app -> write response bytes back**
- Built on `uvloop` (faster event loop) and `httptools` (fast C-based HTTP parser, from Node.js's `llhttp`)
- Run: `uvicorn app:app --host 0.0.0.0 --port 8000 --workers 1`
- `--reload` watches for file changes and restarts  -  **development only**, not for production
- Production deployment: **Gunicorn as process manager** + Uvicorn workers: `gunicorn app:app -w 4 -k uvicorn.workers.UvicornWorker`

**Tricky points:**
- `--workers N` in Uvicorn forks N **separate processes**  -  each with its own event loop; this is different from concurrency within one process
- `--reload` uses file-system watchers  -  it adds overhead and is unreliable in some environments (Docker volumes, network filesystems); never use in production
- Uvicorn does **not** handle TLS termination in production  -  put Nginx or a cloud load balancer in front for HTTPS
- `uvicorn.run(app, ...)` in code starts Uvicorn programmatically  -  useful for testing but the CLI is standard for production
- `--limit-concurrency N` limits simultaneous in-flight requests  -  prevents a flood of requests from exhausting memory

---

## What It Is

Think of a city's mail sorting facility. The postal service (Uvicorn) sits between the outside world (the internet) and the individual offices (your ASGI application). It receives all incoming mail, sorts it by destination, prepares it in the standard format each office expects, delivers it, waits for a reply, and sends the reply back out. The offices do not deal with raw envelopes  -  they only deal with the sorted, standardized deliveries the facility prepares. Uvicorn is that facility: it handles the raw network layer so your application only needs to handle the standardized ASGI events.

Uvicorn is what the internet actually talks to when a request arrives at your server. A browser or API client connects to Uvicorn over TCP, sends raw HTTP bytes, and receives raw HTTP bytes back. Uvicorn is the software that parses those bytes, extracts the method, path, headers, and body, constructs the ASGI `scope` dict, and calls your application with `(scope, receive, send)`. Your application never sees a raw TCP socket  -  it only sees the clean ASGI interface Uvicorn provides.

The name Uvicorn combines "uvloop" and "unicorn." `uvloop` is an alternative Python event loop implementation built on `libuv` (the same C library that Node.js uses), which is significantly faster than CPython's default `asyncio` event loop for high-throughput I/O. `httptools` is a Python binding to `llhttp` (Node.js's HTTP parser), a highly optimized C library for parsing HTTP requests. Together, these two components make Uvicorn one of the fastest Python ASGI servers available.

---

## How It Actually Works

Uvicorn's startup sequence creates an `asyncio` event loop (using `uvloop` if available and not disabled), binds a TCP socket to the configured host and port, and registers a connection handler with the event loop. When a new TCP connection arrives, the event loop fires the connection handler, which creates a protocol object to manage that connection.

For HTTP/1.1, Uvicorn creates an `HttpToolsProtocol` object that uses `httptools` to parse the incoming bytes. As `httptools` parses the request incrementally, it fires callbacks: `on_url` (when the URL is complete), `on_header` (for each header), `on_headers_complete` (when all headers are received), `on_body` (for body chunks), `on_message_complete` (when the full request is received). Uvicorn's protocol handler collects these callbacks into the `scope` dict and the `receive` queue.

Once the request headers are complete, Uvicorn calls the ASGI application: `await app(scope, receive, send)`. The `receive` callable returns events from an internal queue  -  `"http.request"` events as body chunks arrive. The `send` callable accepts events from the application and writes them to the TCP socket: `"http.response.start"` writes the status line and headers; `"http.response.body"` writes body bytes.

For production deployments, Uvicorn is typically run as a Gunicorn worker type (`uvicorn.workers.UvicornWorker`). Gunicorn acts as a process manager: it starts multiple Uvicorn worker processes, monitors them for crashes, and restarts failed workers. Each Uvicorn worker is an independent Python process with its own event loop, handling its own set of connections. This gives you both the concurrency of async I/O within each worker and the CPU parallelism and fault isolation of multiple processes.

---

## How It Connects

ASGI defines the interface Uvicorn calls  -  `async def app(scope, receive, send)`. Uvicorn is the server-side implementation of that interface: it builds the scope, implements receive and send, and drives the coroutine. Understanding ASGI is what makes Uvicorn's behavior fully transparent.
[[asgi|ASGI]]

Uvicorn's performance comes from using `uvloop` instead of CPython's default `asyncio` event loop. `uvloop` is a drop-in replacement that runs the same coroutines but processes I/O events through `libuv`'s C-level implementation, reducing the Python overhead in the inner event loop. This is why FastAPI benchmarks typically require `uvloop` to achieve top performance numbers.
[[event-loop|The Event Loop]]

---

## Common Misconceptions

Misconception 1: "Running `uvicorn app:app --workers 4` makes my app handle 4× more concurrent requests on the same CPU core."
Reality: `--workers 4` creates 4 separate OS processes, each running a separate Python interpreter with its own event loop. You get 4× more CPU capacity (across 4 cores), not 4× more concurrency within one event loop. Each worker handles its own concurrent requests through async I/O. The `--workers` flag is about CPU parallelism and fault isolation, not about increasing async concurrency within a single process.

Misconception 2: "Uvicorn handles TLS/SSL directly and is production-ready as a standalone server."
Reality: Uvicorn can be configured with TLS certificates (`--ssl-keyfile`, `--ssl-certfile`) but this is not recommended for production. TLS termination, HTTP/2, certificate rotation, and load balancing are better handled by a reverse proxy like Nginx or a cloud load balancer. Uvicorn should sit behind that proxy receiving plain HTTP (or HTTP/2 over the internal network). Running Uvicorn directly exposed to the internet without a reverse proxy loses access to Nginx's caching, rate limiting, static file serving, and operational maturity.

---

## Why It Matters in Practice

Understanding Uvicorn's role prevents a class of deployment mistakes. The `--reload` flag is frequently seen in tutorials and is appropriate for local development, but it must never be used in production  -  it adds a file-system watcher that consumes resources and restarts the server on any file change, including log file rotation or a temp file appearing. The Gunicorn + UvicornWorker pattern is the correct production setup: Gunicorn handles process management, worker restart, and graceful shutdown; Uvicorn handles the ASGI event loop within each worker.

The number of Uvicorn workers to configure depends on workload. For I/O-bound applications (most web APIs), `workers = 2 × CPU_count + 1` is a reasonable starting point  -  each worker can handle many concurrent requests through async I/O, and multiple workers provide CPU parallelism for request parsing overhead. For CPU-bound endpoints, more workers help more. Monitoring per-worker memory usage is important  -  each worker is a full Python process, and memory usage multiplies with worker count.

---

## Interview Angle

Common question forms:
- "What is Uvicorn and what role does it play?"
- "How do you deploy a FastAPI application in production?"
- "What is the difference between `uvicorn --workers 4` and async concurrency?"

Answer frame: Define Uvicorn as the ASGI server: accepts TCP connections, parses HTTP with `httptools`, builds `(scope, receive, send)`, calls the app. Explain the production deployment pattern: Gunicorn as process manager with `UvicornWorker`. Clarify `--workers`: separate processes for CPU parallelism, not additional async concurrency. Note that `--reload` is dev-only. Mention the Nginx reverse proxy layer for TLS, caching, and load balancing.

---

## Related Notes

- [[asgi|ASGI]]
- [[event-loop|The Event Loop]]
- [[fastapi|FastAPI]]
