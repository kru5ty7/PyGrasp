---
title: 01 - WSGI
description: WSGI (Web Server Gateway Interface) is the Python standard that defines how a web server passes an HTTP request to a Python application — it is a synchronous, one-request-per-call interface that powers Django, Flask, and most traditional Python web applications.
tags: [wsgi, web-server, http, interface, django, flask, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# WSGI

> WSGI (Web Server Gateway Interface) is the Python standard that defines how a web server passes an HTTP request to a Python application — it is a synchronous, one-request-per-call interface that powers Django, Flask, and most traditional Python web applications.

---

## Quick Reference

**Core idea:**
- WSGI (PEP 3333) defines a single interface: a **callable** that takes `(environ, start_response)` and returns an **iterable of byte strings**
- `environ` — a dict with all request data: `REQUEST_METHOD`, `PATH_INFO`, `QUERY_STRING`, `HTTP_*` headers, `wsgi.input` for the body
- `start_response(status, headers)` — a callback the app calls to set the status code and response headers before yielding the body
- WSGI is **synchronous and blocking** — one thread handles one request; the thread is occupied until the response is complete
- Common WSGI servers: **Gunicorn**, **uWSGI**, **mod_wsgi** (Apache); common frameworks: **Django**, **Flask**, **Bottle**

**Tricky points:**
- WSGI cannot handle **WebSockets or long-polling** — the request-response model ends when the response iterable is exhausted
- WSGI is **synchronous** — calling `await` inside a WSGI app is a `SyntaxError` (WSGI callables are not `async def`)
- `start_response` must be called **before** the first byte of the body is yielded — headers and body are sent in this order
- WSGI middleware wraps the app callable — `wrapped_app = middleware(app)`; the middleware receives `(environ, start_response)` and can modify either before passing to the inner app
- `wsgi.input` is a **file-like object**, not a string — you must call `.read()` to get the raw request body bytes

---

## What It Is

Think of a staffing agency that places workers in offices. The agency has a standard contract: every worker it places must speak English, follow a specific process for clocking in, and submit reports in a standard format. The office does not care which specific person the agency sends — they all follow the same contract. WSGI is that standard contract between Python web servers and Python web applications. A Gunicorn server does not care whether your application is built with Flask, Django, or a custom framework — as long as the application provides a callable that accepts `environ` and `start_response` and returns an iterable of bytes, Gunicorn can serve it.

WSGI was defined in PEP 333 (2003) and updated in PEP 3333 (2010) for Python 3. It solved a fragmentation problem: in Python's early web years, every web server required a different integration. Apache, lighttpd, and standalone servers each had different ways of connecting to Python applications. WSGI created a common interface so that any WSGI-compliant server could run any WSGI-compliant application without any framework-specific glue.

The interface is deliberately simple. A WSGI application is any callable — a function, a class with `__call__`, a method — that accepts two arguments and returns an iterable. The first argument, `environ`, is a Python dictionary containing all information about the incoming HTTP request: the request method, the URL path, query string, headers (prefixed with `HTTP_`), and a file-like object (`wsgi.input`) for reading the request body. The second argument, `start_response`, is a callback provided by the server that the application calls to declare the response status code and headers before it starts returning the body.

---

## How It Actually Works

When a WSGI server like Gunicorn receives an HTTP request, it parses the raw HTTP bytes into their constituent parts — method, path, headers, body. It populates the `environ` dict according to PEP 3333's specification. Key entries include: `REQUEST_METHOD` (the HTTP method as an uppercase string), `PATH_INFO` (the URL path), `QUERY_STRING` (everything after `?`), `SERVER_NAME` and `SERVER_PORT`, `HTTP_*` entries for each request header (the header name uppercased with dashes replaced by underscores), `wsgi.input` (a file-like object wrapping the request body), `wsgi.errors` (a stream for error output), and several others.

The server then calls the WSGI application: `result = app(environ, start_response)`. The application processes the request, calls `start_response("200 OK", [("Content-Type", "application/json")])` to declare the status and headers, and returns an iterable of byte strings — typically a list with one element, or a generator that yields chunks. The server reads the iterable and sends each chunk to the client over the TCP connection.

Gunicorn achieves concurrency by running multiple worker processes. Each worker process is a separate Python interpreter running the WSGI application. With `--workers 4`, Gunicorn forks four worker processes. Each worker handles one request at a time — while one request is processing (including waiting for a database response), that worker is occupied. The OS pre-empts threads between workers, but each worker itself is single-threaded by default. Gunicorn also supports threaded workers (`--worker-class gthread`) and gevent-based workers for higher concurrency, but the synchronous constraint of WSGI remains.

WSGI middleware is the canonical composition pattern. A middleware is a callable that wraps another WSGI app: it receives `(environ, start_response)`, optionally modifies them, calls the inner app, and optionally modifies the response. Django's middleware system, Flask's `before_request`/`after_request` hooks, and WSGI-level authentication layers all follow this pattern.

---

## How It Connects

Understanding what an HTTP request contains — method, path, headers, body — is the prerequisite for understanding what goes into the `environ` dictionary. WSGI is essentially a standardized Python-dict representation of an HTTP request, and each key in `environ` corresponds to a specific part of the HTTP protocol.
[[http-basics|HTTP Basics]]

ASGI is the async successor to WSGI. It preserves the core idea of a standard interface between servers and applications, but extends it to handle WebSockets, HTTP/2 server push, and long-lived connections that WSGI's synchronous request-response model cannot accommodate. Understanding WSGI makes ASGI's design choices clear.
[[asgi|ASGI]]

---

## Common Misconceptions

Misconception 1: "WSGI is slow because it is synchronous."
Reality: WSGI's synchronous model is not inherently slow — it matches the request-response model well for most web applications. Gunicorn running 4–8 WSGI workers can handle thousands of requests per second for CPU-light workloads. The limitation of WSGI is not raw throughput but concurrency: each worker can only handle one request at a time. For applications with many concurrent long-lived connections (chat, streaming, WebSockets) or very high I/O wait per request, the synchronous model becomes a bottleneck. For typical CRUD APIs, WSGI is perfectly sufficient.

Misconception 2: "Flask and Django are WSGI — they can't do async."
Reality: Flask (since 2.0) and Django (since 3.1) support `async def` view functions. However, they run in a WSGI context by default, which means async views are run in a synchronous thread using `asyncio.run()` — they do not share an event loop, and you do not get the concurrency benefits of true async I/O. To get those benefits with Django or Flask, you need to run them under an ASGI server (like Uvicorn or Hypercorn) using their ASGI mode.

---

## Why It Matters in Practice

WSGI is still the deployment model for the majority of Python web applications in production. Django on Gunicorn, Flask on uWSGI — these are the dominant patterns. Understanding WSGI means understanding how Gunicorn worker counts relate to concurrency, why a slow database query holds up a worker, and why adding more Gunicorn workers scales horizontally but not vertically. It explains why a WSGI app server in front of a slow database is a bottleneck and why connection pooling matters.

WSGI middleware is also the basis for many common patterns: authentication checks, request logging, CORS headers, rate limiting, and session management. In Django, these are Django middleware classes. In Flask, they are WSGI middleware wrappers or `before_request` hooks. In both cases, the underlying model is: intercept the request before the view function, process it, and optionally modify or short-circuit the response.

---

## Interview Angle

Common question forms:
- "What is WSGI?"
- "How does a web server communicate with a Django or Flask application?"
- "What is the difference between WSGI and ASGI?"

Answer frame: Define WSGI as a standard interface: a callable that takes `(environ, start_response)` and returns an iterable of bytes. Explain `environ` as a dict with all HTTP request data. Explain the synchronous, one-request-per-call model and how Gunicorn achieves concurrency through multiple worker processes. Contrast with ASGI: ASGI is async, handles WebSockets and long-lived connections, one application instance handles many concurrent connections on the event loop.

---

## Related Notes

- [[http-basics|HTTP Basics]]
- [[asgi|ASGI]]
