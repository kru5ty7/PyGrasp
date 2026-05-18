---
title: 06 - Flask Application and Request Context
description: "Flask manages two context stacks  -  the application context and the request context  -  that control when and where proxies like current_app, request, g, and session are accessible."
tags: [flask, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Flask Application and Request Context

> Flask's context system is the mechanism that makes `request`, `current_app`, `g`, and `session` feel like global variables while remaining thread-safe  -  understanding it is essential for writing correct code in background threads, CLI commands, and tests.

---

## Quick Reference

**Core idea:**
- Two separate stacks: the application context stack (holds `current_app` and `g`) and the request context stack (holds `request` and `session`)
- Pushing a request context automatically pushes an application context if one is not already active
- `g` is per-request scratch space  -  populated during a request and cleared when the request context is popped
- `current_app` is a proxy to the Flask application bound to the current application context stack
- `app.app_context()` is the context manager for manually pushing an application context outside a request

**Tricky points:**
- `g` does not persist between requests  -  it is a per-request dictionary, not a per-session or per-application store
- `current_app` raises `RuntimeError: Working outside of application context` in background threads unless you push the app context manually
- Pushing a request context inside a test does not make the test client's request attributes available  -  you need the actual test client to push a real request context
- The application context is not pushed inside `@app.cli.command()` functions until Flask 1.0  -  before that, CLI commands needed explicit `with app.app_context():` wrappers
- `session` is backed by a signed cookie by default  -  reading it without a secret key configured raises a `RuntimeError`

---

## What It Is

Think of Flask's context system as a valet stand at a hotel. When a guest (an HTTP request) arrives, the valet stand is stocked with everything relevant to that guest  -  their room key (session), their immediate requests (request object), and a notepad for jotting down things relevant only to this visit (g). When the guest leaves, the valet stand is cleared entirely. The next guest gets a fresh, empty stand. Different guests never see each other's items, even if they arrive simultaneously  -  each concurrent request has its own valet stand. This is what Flask's context stacks accomplish: isolated per-request storage that looks like a shared global space but is actually thread-specific.

Flask maintains two distinct stacks rather than one. The application context stack holds `current_app`  -  a proxy to the active Flask application  -  and `g`, the per-request scratch space. The request context stack holds `request`  -  the proxy to the current HTTP request  -  and `session`  -  the per-user signed cookie dictionary. They are separate because the application context has a broader scope: it is needed not only during HTTP requests but also during CLI commands, background tasks, and test setup, where there is no HTTP request at all. You can push an application context without a request context; you cannot push a request context without also having an application context.

The `g` object is frequently misunderstood. It is not a global cache. It is not per-session state. It is a per-request scratch pad that exists purely for passing data between different parts of the code that handle the same request without using global variables or function parameters. A common pattern is to load the authenticated user in a `before_request` hook and store it in `g.user`, then access `g.user` in view functions and templates. When the request ends and the context is popped, `g` is discarded. The next request starts with a fresh, empty `g`.

---

## How It Actually Works

Flask implements its context stacks using Werkzeug's `LocalStack`  -  a stack that stores different values for different threads (and, in newer versions, different async tasks). When a request arrives, Flask calls `ctx = RequestContext(app, environ)` and then `ctx.push()`. The `push()` method places the request context on the `LocalStack` and, if no application context is already present, pushes one as well. When Flask finishes generating the response, it calls `ctx.pop()`, which removes the request context and, if it was the one that pushed the application context, removes that too. The `request` and `session` proxies call `_cv_tokens.get()` (using `contextvars.ContextVar` in modern Flask) to retrieve the current request context from this stack.

```python
# Manually pushing contexts  -  required for background threads, CLI, and tests
from flask import Flask, current_app, g

app = Flask(__name__)
app.config['SECRET_KEY'] = 'dev'

# CLI command  -  app context pushed automatically by Flask CLI runner
@app.cli.command('seed-db')
def seed_db():
    print(current_app.config['SQLALCHEMY_DATABASE_URI'])

# Background thread  -  must push app context manually
import threading

def background_job(app):
    with app.app_context():
        # current_app and extensions are accessible here
        print(current_app.name)

thread = threading.Thread(target=background_job, args=(app,))
thread.start()

# Test fixture
def test_something(app):
    with app.app_context():
        # set up data using extensions
        pass
```

Since Flask 2.2, context variables use Python's `contextvars.ContextVar` rather than threading.local, which means they also work correctly in async code  -  each `asyncio` task has its own context variable slot. When you push an app context using `app.app_context()` as a context manager, Python's `contextvar` mechanism ensures the context is available within the `with` block and automatically cleaned up when the block exits, even if an exception is raised.

---

## How It Connects

The `g` object's per-request lifecycle is governed by the request context  -  knowing when the context is pushed and popped tells you exactly how long `g` values are available.

[[flask-request-response|Flask Request and Response]]

The application factory pattern creates the app object whose context needs to be pushed  -  understanding why `with app.app_context():` is necessary in CLI commands and tests requires knowing what the factory produces.

[[flask-application-factory|Flask Application Factory Pattern]]

Context managers are the Python mechanism that Flask uses to push and pop context stacks  -  the `with app.app_context():` syntax is a direct application of the context manager protocol.

[[context-managers|Context Managers]]

---

## Common Misconceptions

Misconception 1: "`g` stores data that persists across multiple requests, like a user session."
Reality: `g` is cleared at the end of every request. It exists only for the duration of a single request-response cycle. For data that persists across requests, use `session` (for per-user data stored in a cookie) or a database/cache.

Misconception 2: "Pushing the app context in a background thread automatically gives access to the current request."
Reality: The application context gives access to `current_app` and extensions. The request context gives access to `request` and `session`. A background thread can push an app context, but there is no ongoing request for it to access  -  `request` remains unavailable in background threads.

Misconception 3: "If I import `current_app` at the top of my module, it will always point to my app."
Reality: `current_app` is a proxy that resolves to whatever app is on the current context stack at the time it is accessed. If there is no app context, accessing `current_app` raises `RuntimeError`. The import just imports the proxy object; it does not capture the app at import time.

---

## Why It Matters in Practice

Context errors  -  `RuntimeError: Working outside of application context` and `RuntimeError: Working outside of request context`  -  are among the most common errors for developers new to Flask beyond simple tutorials. They appear when writing background tasks, Celery workers, management commands, and test fixtures. Understanding that these errors mean "you are accessing a proxy that has nothing on the stack below it" immediately points to the fix: push the appropriate context with `with app.app_context():`.

The broader lesson is architectural: Flask's context system is the reason that view functions can access `request`, `db.session`, and `g` without these being passed as function parameters. The context stack is Flask's implicit dependency injection mechanism. When code works correctly inside a view but fails in a background job or test, the context system is almost always the explanation.

---

## Interview Angle

Common question forms:
- "What is the difference between Flask's application context and request context?"
- "What is `g` in Flask and how long does it live?"
- "Why does `current_app` raise a `RuntimeError` in a background thread?"

Answer frame:
A strong answer distinguishes the two stacks  -  app context (current_app, g) versus request context (request, session)  -  explains that pushing a request context automatically pushes an app context but not vice versa, and explains `g` as per-request scratch space cleared at context pop. The background thread answer explains that threads have no implicit context and require `with app.app_context():` to push one manually. Mentioning `contextvars.ContextVar` (modern Flask) or `threading.local` (older Flask/Werkzeug) as the thread-safety mechanism demonstrates depth.

---

## Related Notes

- [[flask-basics|Flask Basics]]
- [[flask-application-factory|Flask Application Factory Pattern]]
- [[flask-request-response|Flask Request and Response]]
- [[flask-blueprints|Flask Blueprints]]
- [[context-managers|Context Managers]]
