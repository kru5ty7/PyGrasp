---
title: 01 - Flask Basics
description: "Flask is a lightweight WSGI micro-framework that gives Python developers routing, request handling, and templating without imposing an architecture."
tags: [flask, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Flask Basics

> Flask is a WSGI micro-framework built on Werkzeug and Jinja2  -  the minimal foundation every Python web developer reaches for when they want control over every layer of their application.

---

## Quick Reference

**Core idea:**
- `Flask(__name__)` creates the application object  -  the central registry for routes, config, and extensions
- `@app.route('/path')` registers a URL rule against a view function
- `app.run()` starts Werkzeug's built-in development server (not for production)
- `debug=True` enables the interactive Werkzeug debugger and the auto-reloader
- Flask is a WSGI application  -  its `app` object is itself a callable that takes `(environ, start_response)`
- Jinja2 handles HTML templates; Werkzeug handles everything at the HTTP/WSGI layer

**Tricky points:**
- `Flask(__name__)` uses `__name__` to locate templates and static files relative to the calling module  -  passing the wrong value breaks static file resolution
- `app.run()` is only safe for development; production requires a proper WSGI server like Gunicorn
- `debug=True` exposes an interactive Python shell in the browser on exceptions  -  never enable it in production
- Flask does not enforce any project structure; that freedom is also its main source of architecture mistakes
- The application object is not thread-safe to configure after the first request has been handled

---

## What It Is

Think of Flask as the minimal scaffolding of a building  -  it provides the load-bearing columns and the floor plan, but leaves every interior decision to the architect. Unlike Django, which ships with an ORM, an admin panel, a form library, and a rigid directory layout, Flask ships with exactly two things: a request routing engine and a templating system. Everything else  -  the database layer, authentication, input validation, background tasks  -  you select and wire together yourself. This philosophy is called "micro" not because Flask is small in capability, but because it makes no decisions for you beyond the core request-response cycle.

Flask was created by Armin Ronacher in 2010, originally as an April Fools' joke that turned serious when developers recognized how useful a dependency-free, composable web framework could be. Its design drew heavily from Sinatra, the Ruby micro-framework, and from Ronacher's own Werkzeug library, which had already solved the low-level WSGI plumbing problem. Flask simply layered a pleasant API on top of Werkzeug and Jinja2, the two libraries that still form its entire dependency tree.

The application object created by `Flask(__name__)` is the central registry for the entire framework. Routes registered with `@app.route()` are stored on this object. Configuration lives on `app.config`. Extensions attach themselves to this object. When a request arrives, Flask consults its internal route map to find the matching view function, pushes the appropriate context objects onto its context stacks, calls the function, and converts the return value into a WSGI response. The simplicity of this flow is Flask's defining characteristic.

---

## How It Actually Works

Flask is a WSGI application, which means it is a Python callable that accepts two arguments  -  the WSGI `environ` dictionary and the `start_response` callable  -  and returns an iterable of response bytes. When you call `app.run()`, Flask starts Werkzeug's `run_simple` development server, which creates a socket, accepts HTTP connections, parses them into `environ` dictionaries, and calls `app(environ, start_response)` for each one. In production, a server like Gunicorn takes the role of `run_simple`, passing the same two arguments to the same callable.

```python
from flask import Flask

app = Flask(__name__)

@app.route('/')
def index():
    return 'Hello, World!'
```

Inside `app.__call__(environ, start_response)`, Flask delegates to Werkzeug's `Request` class to parse the raw `environ` into a convenient object with `.args`, `.form`, `.json`, and `.headers` attributes. It then runs the URL map  -  a `werkzeug.routing.Map`  -  against `request.path` to find the matching rule and the view function associated with it. Flask pushes an application context (containing `current_app` and `g`) and a request context (containing `request` and `session`) onto their respective thread-local stacks, calls the view function, and converts whatever it returns into a `werkzeug.wrappers.Response`. The response is then serialized back through the WSGI interface. When `debug=True`, Werkzeug installs a custom exception handler that catches unhandled exceptions before they propagate through the WSGI interface, rendering the interactive traceback debugger in the browser instead.

---

## How It Connects

Flask sits directly on top of the WSGI interface, so understanding what WSGI is and how it maps HTTP to Python callables is foundational to understanding every Flask behavior.

[[wsgi|WSGI]]

The request-response cycle describes the journey from HTTP packet to Python function return value  -  Flask implements this cycle on top of Werkzeug.

[[request-response-cycle|Request-Response Cycle]]

Flask's `@app.route()` decorator is a Python decorator that stores metadata on the application object  -  understanding how decorators work clarifies how route registration happens at import time, not at call time.

[[decorators|Decorators]]

---

## Common Misconceptions

Misconception 1: "Flask is only for small projects  -  for anything serious you need Django."
Reality: Flask powers large production systems at companies like Netflix and LinkedIn. The distinction is not scale but architecture preference: Flask requires you to design the architecture yourself, which is a strength for teams that want explicit control.

Misconception 2: "`app.run()` is how you run Flask in production."
Reality: `app.run()` starts Werkzeug's single-threaded development server, which is not designed for concurrent load, graceful shutdown, or process management. Production deployments always use a WSGI server like Gunicorn or uWSGI.

Misconception 3: "The `debug=True` flag just gives better error messages."
Reality: It also enables an interactive Python REPL in the browser on every unhandled exception. An attacker who can trigger an error in your application can execute arbitrary Python code on your server.

---

## Why It Matters in Practice

Flask's minimalism directly shapes the decisions a developer must make. Because Flask ships without an ORM, you are forced to choose one explicitly  -  which means you understand why it is there. Because Flask has no enforced project layout, teams that do not establish conventions early accumulate technical debt quickly. Understanding Flask's defaults and the reasoning behind common patterns like the application factory, blueprints, and extension initialization teaches architectural thinking that transfers directly to larger frameworks and systems.

Flask also remains the dominant choice for internal tools, data science APIs, and microservices in Python shops. A backend developer who cannot write a Flask application is missing a fundamental instrument in the Python web toolkit. More importantly, because Flask exposes the WSGI layer so directly, studying it clarifies how Python web frameworks in general  -  including Django and FastAPI  -  operate under the hood.

---

## Interview Angle

Common question forms:
- "What does 'micro-framework' mean and what are the tradeoffs?"
- "Walk me through what happens when a request hits a Flask application."
- "Why would you use Flask over Django?"

Answer frame:
A strong answer distinguishes between what Flask provides (routing, request parsing, templating, the application object as a registry) and what it deliberately omits (ORM, admin, auth). It explains the WSGI callable model  -  Flask is a function that takes `environ` and `start_response`  -  and traces the request through Werkzeug's routing map, context stack pushes, view function call, and response serialization. The tradeoff discussion acknowledges that Flask's freedom requires architectural discipline and that Django's conventions accelerate teams that accept them.

---

## Related Notes

- [[wsgi|WSGI]]
- [[request-response-cycle|Request-Response Cycle]]
- [[decorators|Decorators]]
- [[flask-routing|Flask Routing]]
- [[flask-request-response|Flask Request and Response]]
- [[flask-context|Flask Application and Request Context]]
