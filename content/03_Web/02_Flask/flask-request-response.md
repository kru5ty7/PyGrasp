---
title: 03 - Flask Request and Response
description: "Flask exposes the HTTP request through a context-local proxy object and provides helpers for constructing JSON, redirect, and custom responses."
tags: [flask, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Flask Request and Response

> Flask wraps every incoming HTTP request in a context-local `request` object and provides `jsonify()`, `make_response()`, and request hooks to give view functions clean, complete control over the HTTP conversation.

---

## Quick Reference

**Core idea:**
- `from flask import request` — `request.args` (query string), `request.form` (POST body), `request.json` (JSON body), `request.files`, `request.headers`
- `request` is a context-local proxy — it appears global but is thread-safe because it points to the request bound to the current thread's context stack
- `jsonify(data)` returns a `Response` with `Content-Type: application/json` and proper serialization
- `make_response(body, status_code, headers)` constructs a fully customized response
- `@app.before_request` and `@app.after_request` register hooks that run before and after every request in the app

**Tricky points:**
- `request.json` returns `None` if the `Content-Type` header is not `application/json` — use `request.get_json(force=True)` to parse JSON regardless of content type
- `request.form` and `request.json` are mutually exclusive for a given request — a client sends either form-encoded or JSON data, not both
- `after_request` functions must return the response object, even if unmodified — forgetting the return causes a `TypeError`
- `request` raises a `RuntimeError` if accessed outside the request context (e.g., in a background thread or at module import time)
- `request.files` stores uploaded files as `FileStorage` objects, which must be saved explicitly — they are not persisted automatically

---

## What It Is

Every HTTP conversation is a two-part exchange: a client sends a request carrying a method, a URL, headers, and optionally a body, and the server sends back a response carrying a status code, headers, and a body. Flask represents each side of this exchange with dedicated objects and helpers. The `request` object is Flask's representation of what the client sent. It exposes everything the client included — the query string parsed into a dictionary, form fields, a parsed JSON body, uploaded files, cookie values, and raw headers — all accessible as clean Python attributes without any manual parsing.

The request object in Flask is not a simple global variable, even though you import it as if it were. It is a proxy — an object that looks up the actual request bound to the current execution context each time you access it. In a multi-threaded server where dozens of requests are being handled simultaneously, each thread has its own request bound to its own context stack. The `request` proxy consults this stack on every attribute access, ensuring that `request.json` in thread A refers to thread A's request body, not thread B's. This design lets Flask expose a clean, importable API while remaining safe under concurrent load.

On the response side, Flask accepts several return formats from view functions. Returning a plain string wraps it in a 200 OK response with `text/html` content type. Returning a dictionary automatically calls `jsonify()` on it. Calling `jsonify(data)` explicitly creates a `Response` object with the body serialized as JSON and the `Content-Type` set to `application/json`. For fine-grained control — custom status codes, custom headers, conditional responses — `make_response()` accepts a response body and optional status code and headers dictionary, returning a mutable `Response` object you can further modify before returning it.

---

## How It Actually Works

When a request arrives, Flask's request context is pushed onto a thread-local stack. This stack holds the `Request` object (a Werkzeug class that wraps the raw WSGI `environ`) and the `Session` object. The `request` proxy's `__getattr__` implementation calls `_get_current_object()`, which retrieves the top item from this stack. This is Werkzeug's `LocalProxy` pattern — a standard Python descriptor protocol trick that makes proxy access transparent. The key implementation detail is that `_get_current_object()` raises `RuntimeError: Working outside of request context` if the stack is empty, which is the error you see when you try to access `request` in a background thread that never had a request context pushed.

```python
from flask import Flask, request, jsonify, make_response, abort

app = Flask(__name__)

@app.before_request
def check_auth():
    token = request.headers.get('Authorization')
    if not token:
        abort(401)

@app.route('/data', methods=['POST'])
def receive_data():
    payload = request.get_json(force=True)
    if payload is None:
        return make_response(jsonify({'error': 'invalid JSON'}), 400)
    return jsonify({'received': payload}), 201

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    return response
```

`before_request` hooks run in the order they were registered, before the view function. If any `before_request` hook returns a value (rather than `None`), Flask treats that value as the response and skips the view function entirely — this is how authentication guards work. `after_request` hooks run after the view function, in reverse registration order, and each one receives the response object and must return it. `teardown_request` hooks run after the response is sent regardless of whether an exception occurred — they are used for cleanup like closing database connections.

---

## How It Connects

The `request` object is a context-local proxy, which relies on Flask's application and request context stacks — understanding those stacks explains why `request` is safe in threaded environments.

[[flask-context|Flask Application and Request Context]]

Request and response are the two sides of the HTTP exchange — the HTTP protocol defines what fields are valid in each and how status codes signal outcomes.

[[request-response-cycle|Request-Response Cycle]]

Flask's `before_request` hooks are a lightweight middleware pattern; for cross-cutting concerns that need to run at the WSGI layer (before Flask even processes the request), WSGI middleware is the correct tool.

[[flask-middleware|Flask Middleware]]

---

## Common Misconceptions

Misconception 1: "`request` is a global variable shared across all requests."
Reality: `request` is a `LocalProxy` that is bound per-thread (or per-async-task in newer setups). Each concurrent request has its own `Request` object on its own context stack. The import looks global, but the object it points to is always request-specific.

Misconception 2: "Returning a dictionary from a view function is the same as calling `jsonify()`."
Reality: Since Flask 1.0, returning a dictionary does invoke `jsonify()` automatically. However, returning a list only works from Flask 2.2+. For explicit control over status codes and headers, always use `jsonify()` combined with a status code return tuple, or use `make_response()`.

Misconception 3: "`after_request` is a good place to handle exceptions."
Reality: `after_request` only runs when the view function returns normally. If an unhandled exception is raised, Flask skips `after_request` and runs `teardown_request` instead. Exception handling belongs in `@app.errorhandler` decorators.

---

## Why It Matters in Practice

Almost every view function reads from the `request` object and constructs a response — these are the two operations that every Flask developer performs on every route. Getting the nuances right — knowing when `request.json` returns `None`, understanding why `after_request` must return the response, knowing the difference between `before_request` and `teardown_request` — prevents a class of silent bugs that are frustrating to diagnose. Understanding `request` as a `LocalProxy` also prevents the common mistake of passing `request` to a background thread, which fails with a cryptic `RuntimeError` because the context has been popped by the time the thread executes.

Request hooks (`before_request`, `after_request`) are the lightweight alternative to WSGI middleware for cross-cutting concerns like authentication, logging, and CORS header injection. Knowing when to use hooks versus full WSGI middleware versus a blueprint's `before_request` versus a per-route decorator is a fundamental Flask architecture skill.

---

## Interview Angle

Common question forms:
- "What is the `request` object in Flask and how is it thread-safe?"
- "What is the difference between `jsonify()` and returning a plain dictionary?"
- "How do you add a header to every response in Flask?"

Answer frame:
A strong answer explains `LocalProxy` — `request` is not a global but a thread-local proxy that looks up the current request from the context stack on every access. The `jsonify()` answer should mention `Content-Type: application/json` and the ability to pair it with status code tuples. The header answer should describe `after_request` and the requirement to return the modified response object, with a note that `teardown_request` exists for cleanup after exceptions.

---

## Related Notes

- [[flask-basics|Flask Basics]]
- [[flask-context|Flask Application and Request Context]]
- [[flask-routing|Flask Routing]]
- [[flask-middleware|Flask Middleware]]
- [[request-response-cycle|Request-Response Cycle]]
- [[http-basics|HTTP Basics]]
