---
title: 12 - Flask Middleware
description: "Flask middleware operates at two levels: WSGI middleware wraps the application callable before Flask processes any request, and Flask hooks intercept requests inside Flask's own context."
tags: [flask, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Flask Middleware

> Flask middleware spans two layers  -  WSGI middleware wraps the entire application callable for concerns that must run before Flask is involved, while Flask's before/after request hooks handle cross-cutting concerns inside the application context.

---

## Quick Reference

**Core idea:**
- WSGI middleware: `app.wsgi_app = MyMiddleware(app.wsgi_app)`  -  wraps the raw WSGI callable, runs before Flask sees the request
- Flask hooks: `@app.before_request`, `@app.after_request`, `@app.teardown_request`  -  run inside Flask's context, after routing
- WSGI middleware receives `(environ, start_response)` directly  -  no Flask request object, no app context
- `DispatcherMiddleware` from Werkzeug mounts multiple WSGI apps at different URL prefixes
- `teardown_request` runs after every request regardless of whether an exception occurred  -  correct place for cleanup

**Tricky points:**
- Do not wrap `app` directly with WSGI middleware  -  wrap `app.wsgi_app` instead, otherwise `app.run()` and URL generation break because Flask's debug tools and test client reference `app`, not `app.wsgi_app`
- `before_request` hooks run after routing  -  WSGI middleware runs before routing; the two intercept at genuinely different points in the pipeline
- `after_request` does NOT run if the view function raises an unhandled exception  -  `teardown_request` does
- `DispatcherMiddleware` requires both mounted apps to be complete WSGI callables; the paths it dispatches on must include everything after the prefix
- Returning a response from `before_request` short-circuits the view function but still runs `after_request` hooks

---

## What It Is

In plumbing, a water treatment system has two distinct zones: the main line treatment, which conditions all water before it enters the building (filtration, pressure regulation), and the per-fixture filters, which apply additional treatment at individual taps. Flask's middleware architecture works the same way. WSGI middleware is the main line  -  it intercepts every HTTP connection before the building's internal systems (Flask's router, context stacks, view functions) are involved at all. Flask's before/after request hooks are the per-fixture filters  -  they run inside Flask's own context, after the request has been parsed and a route has been matched.

The WSGI middleware pattern is a consequence of Flask being a WSGI application. A WSGI application is any callable that accepts `(environ, start_response)` and returns an iterable of bytes. Middleware is simply another callable of the same shape that wraps the original. When `app.wsgi_app = MyMiddleware(app.wsgi_app)` is executed, `app.wsgi_app` is replaced with a new callable. When a request arrives, the WSGI server calls `app(environ, start_response)`, Flask's `__call__` delegates to `self.wsgi_app(environ, start_response)`, and `self.wsgi_app` is now `MyMiddleware`, which runs its own logic before (optionally) passing `environ` and `start_response` to the original Flask callable. The wrapping can be nested  -  multiple middleware layers can be stacked, each wrapping the previous.

Flask's `before_request`, `after_request`, and `teardown_request` hooks serve a different purpose. They run inside Flask's context  -  after the WSGI layer, after the request has been parsed into a `Request` object, after the app and request contexts have been pushed, and after routing has selected a view function. This means they have access to `request`, `g`, `current_app`, extensions, and the session. They are the correct tool for application-level cross-cutting concerns: checking authentication tokens (which requires reading request headers as a `Request` object), injecting CORS headers into responses (which requires modifying a `Response` object), logging request durations (which requires access to application config and the request path), and releasing per-request resources like database connections.

---

## How It Actually Works

A WSGI middleware is a class or function that takes the wrapped WSGI app as an argument and returns a new WSGI callable. Its `__call__` method receives `environ` and `start_response`, inspects or modifies `environ`, and either calls the wrapped app or returns a response directly (short-circuiting the wrapped app entirely).

```python
import time
from werkzeug.middleware.dispatcher import DispatcherMiddleware
from werkzeug.serving import run_simple

# WSGI middleware: runs before Flask processes anything
class RequestTimingMiddleware:
    def __init__(self, wsgi_app):
        self.wsgi_app = wsgi_app

    def __call__(self, environ, start_response):
        start = time.time()
        result = self.wsgi_app(environ, start_response)
        duration = time.time() - start
        # log duration here
        return result

# Apply to Flask app  -  wrap wsgi_app, not app itself
app.wsgi_app = RequestTimingMiddleware(app.wsgi_app)

# Flask hooks: run inside Flask's context
@app.before_request
def check_api_key():
    key = request.headers.get('X-API-Key')
    if not key or not is_valid_key(key):
        abort(401)

@app.after_request
def add_security_headers(response):
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    return response

@app.teardown_request
def close_db_connection(exception):
    db_conn = g.pop('db_conn', None)
    if db_conn is not None:
        db_conn.close()

# DispatcherMiddleware: mount two Flask apps
api_app = Flask('api')
admin_app = Flask('admin')

combined = DispatcherMiddleware(api_app, {
    '/admin': admin_app,
})
run_simple('localhost', 5000, combined)
```

`DispatcherMiddleware` is Werkzeug's tool for URL-prefix-based routing between multiple WSGI applications. When a request arrives for `/admin/users`, it strips the `/admin` prefix and dispatches the request (with the prefix removed from `PATH_INFO`) to `admin_app`. Requests that do not match any prefix go to the main app. This is a genuine multi-application setup  -  each app is completely independent, with its own routing, config, and context. It is different from blueprints, which share one application.

---

## How It Connects

Flask is itself a WSGI application  -  understanding what WSGI is and the `(environ, start_response)` interface explains why WSGI middleware works at the level it does, below Flask's own processing.

[[wsgi|WSGI]]

Flask's before/after request hooks are part of the request context lifecycle  -  knowing when contexts are pushed and popped clarifies when hook functions have access to `request`, `g`, and extensions.

[[flask-context|Flask Application and Request Context]]

Flask's application is built on top of Werkzeug, which provides `DispatcherMiddleware` and the `LocalProxy`-based request object  -  the basics note covers this foundational relationship.

[[flask-basics|Flask Basics]]

---

## Common Misconceptions

Misconception 1: "Wrapping `app` directly with middleware is equivalent to wrapping `app.wsgi_app`."
Reality: Flask's `__call__` method delegates to `self.wsgi_app` after its own setup. Wrapping `app` directly with WSGI middleware means the middleware runs before Flask's own `__call__`  -  which is fine for most cases but breaks Werkzeug's debugger, the interactive reloader, and some test client internals. Wrapping `app.wsgi_app` is the correct and documented approach.

Misconception 2: "`before_request` is the same as WSGI middleware  -  both intercept requests before the view function."
Reality: WSGI middleware intercepts at the raw WSGI level  -  before routing, before context pushing, before the `Request` object is created. `before_request` runs inside Flask's context, after routing. This means WSGI middleware cannot access `request.json` or `g`, while `before_request` cannot return a response before routing has occurred.

Misconception 3: "`teardown_request` only runs when an exception is raised."
Reality: `teardown_request` always runs, whether or not an exception occurred. It receives the exception as an argument (which is `None` when no exception occurred). This makes it the correct place for mandatory cleanup  -  connection releasing, temp file removal  -  that must happen regardless of the request outcome.

---

## Why It Matters in Practice

Middleware is the standard answer to cross-cutting concerns in web applications: logging, authentication, rate limiting, CORS, request tracing, and security headers all apply to every request. Flask gives you two placement options  -  WSGI middleware for pre-routing, pre-context concerns, and Flask hooks for post-routing, context-aware concerns  -  and choosing the wrong one produces subtle bugs. Injecting a header using WSGI middleware when you need to read `request.json` first requires the Flask layer; authenticating using `before_request` when you want to block requests before Flask even parses the body requires WSGI middleware.

`DispatcherMiddleware` is less commonly needed but solves a specific problem well: mounting a Flask admin panel at `/admin` and the main Flask API at `/` as two genuinely separate applications, each with its own config and extension state. This pattern appears in systems where the admin interface needs a different authentication mechanism or different database connection than the public API, and keeping them as separate WSGI apps enforces that separation more reliably than blueprints.

---

## Interview Angle

Common question forms:
- "What is the difference between Flask's `before_request` and WSGI middleware?"
- "How would you add request timing to every response in a Flask application?"
- "Why do you wrap `app.wsgi_app` instead of `app` when adding WSGI middleware?"

Answer frame:
A strong answer distinguishes WSGI middleware (runs before Flask, no `Request` object, no context) from `before_request` hooks (runs inside Flask, full context available), explains when each is appropriate, and demonstrates the `app.wsgi_app = Middleware(app.wsgi_app)` pattern. The timing middleware answer can use either approach  -  WSGI for pure timing before any Flask overhead, `before_request`/`after_request` for timing that correlates with Flask's route and context information. The `wsgi_app` wrapping answer cites Werkzeug debugger compatibility and test client correctness.

---

## Related Notes

- [[flask-basics|Flask Basics]]
- [[flask-context|Flask Application and Request Context]]
- [[flask-request-response|Flask Request and Response]]
- [[wsgi|WSGI]]
- [[flask-blueprints|Flask Blueprints]]
