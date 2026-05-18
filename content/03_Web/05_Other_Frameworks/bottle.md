---
title: 04 - Bottle
description: "Bottle is a single-file, zero-dependency Python micro-framework for WSGI web applications, designed for minimal footprint and maximum portability."
tags: [bottle, micro-framework, wsgi, minimal, web-framework, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Bottle

> Bottle is the entire Python web framework in one file with zero dependencies  -  the right tool when size and portability matter more than ecosystem, perfect for scripts, tools, and constrained environments.

---

## Quick Reference

**Core idea:**
- The entire framework is a single file (`bottle.py`), with no dependencies beyond the Python standard library
- WSGI-based, runs with any WSGI-compatible server or via its built-in development server (`app.run()`)
- Route decorators (`@route`, `@get`, `@post`) work identically to Flask's
- Module-level `request` and `response` objects are thread-local proxies  -  import and use directly
- Built-in simple template engine (`%` directives); Jinja2 and Mako can be used as alternatives
- Designed to fit in a single file; the entire framework including documentation is under 5000 lines

**Tricky points:**
- No Blueprints or equivalent  -  all routes live in one namespace, which becomes unmanageable for large applications
- The built-in server (`app.run()`) is single-threaded and for development only; production requires a WSGI server wrapper
- `request.json` raises `AttributeError` on Python 3 if `Content-Type: application/json` is missing  -  use `request.get_json()`
- Template variables must be passed as keyword arguments to `template()`  -  positional arguments are ignored
- Thread-local request/response pattern is the same as Flask's, with the same caveat: avoid storing mutable state on them across async boundaries (but Bottle is sync-only)

---

## What It Is

Most software tools exist on a spectrum between specialised minimalism and general-purpose completeness. A Swiss Army knife is not the best at any single task, but it fits in your pocket and covers a remarkable range of situations. Flask is the Swiss Army knife of Python web frameworks  -  versatile, well-equipped, with a thriving ecosystem of extensions. Bottle is the single pocket knife: one blade, no extra tools, fits anywhere, does its job without fuss. The entire framework is one Python file you can copy into any project directory and immediately use, with no pip install required.

Marcel Hellkamp created Bottle in 2009 as a personal project to build a simple web application without any dependencies. The decision to keep everything in one file was not an accident but a deliberate design constraint that has held for over fifteen years. That constraint forces ruthless prioritisation: every feature that goes into Bottle must justify its presence in that single file. The result is a framework that covers the 80% of web application basics  -  routing, request parsing, response construction, templating  -  in a package small enough to read in an afternoon.

The appeal of Bottle's zero-dependency design extends beyond convenience. In controlled environments  -  embedded systems running minimal Python, serverless functions with strict package size limits, corporate networks where package installation requires approval processes, or Docker images where every megabyte matters  -  the ability to drop one file and immediately have a working web framework is a genuine operational advantage. A Bottle script that serves a local admin panel, exposes a machine's metrics over HTTP, or provides a simple API wrapper for a command-line tool has exactly one Python file as its web dependency.

---

## How It Actually Works

Bottle's API surface is intentionally Flask-like, which makes it approachable:

```python
from bottle import route, run, request, response, template

@route("/hello/<name>")
def hello(name):
    return f"<h1>Hello, {name}!</h1>"

@route("/api/items", method="POST")
def create_item():
    data = request.json
    response.content_type = "application/json"
    return {"received": data, "created": True}

@route("/page/<name>")
def page(name):
    return template("{{name}} page", name=name)

run(host="localhost", port=8080, debug=True)
```

The module-level `request` and `response` are thread-local proxies. In a multi-threaded WSGI server, each request thread gets its own `request` context automatically. The route functions return values directly: strings are returned as `text/html`, dictionaries are serialized as JSON, file objects are served as downloads, and `HTTPResponse` objects provide full control.

Bottle's built-in server (`run(host, port)`) is single-threaded and loops on `wsgiref.simple_server`. For any production scenario, Bottle should be wrapped with a proper WSGI server. The `run()` function accepts a `server` parameter:

```python
run(host="0.0.0.0", port=8080, server="gunicorn", workers=4)
```

This delegates to Gunicorn's WSGI runner directly from Bottle's `run()` call. Bottle knows about Gunicorn, uWSGI, Twisted, and several other servers by name, and will attempt to import and use them if specified. In Docker deployments, the common pattern is to start Gunicorn with Bottle's WSGI application object directly: `gunicorn "myapp:app"` where `app` is the `Bottle()` instance.

The single-file nature makes Bottle useful in a specific class of Python scripts that need to expose a web interface without becoming a "real" web project. A data scientist writing a model-serving script, a sysadmin writing a webhook receiver, or a developer building a local development tool can add ten lines of Bottle code and have a working HTTP API without setting up a project structure, virtual environment layout, or configuration system.

---

## How It Connects

Bottle is a WSGI application  -  understanding what WSGI is and what the WSGI callable interface looks like explains how Bottle routes, request objects, and response objects relate to the underlying protocol.

[[wsgi|WSGI]]

Flask is the most natural comparison point: both are micro-frameworks with decorator-based routing, but Flask introduces Blueprints, an extension ecosystem, and a more structured application factory pattern that Bottle deliberately omits.

<!-- MISSING_NOTE: flask-basics -->

The framework comparison note provides a full decision matrix across all major Python web frameworks, which puts Bottle's specific niche  -  zero-dependency minimalism  -  in context alongside Flask, Django, FastAPI, and others.

[[framework-comparison|Python Web Framework Comparison]]

---

## Common Misconceptions

Misconception 1: "Bottle is too small to be useful for real work."
Reality: "Real work" depends on the problem. A webhook receiver, a metrics endpoint, a local development tool, or an internal admin panel for a small team are all real work. Bottle handles these cases with less overhead than Flask or FastAPI. The appropriate question is not "is it real enough?" but "does the problem size match the framework size?"

Misconception 2: "Bottle's single-file design means it has bad code quality."
Reality: Bottle's single file is clean, well-commented, and has been maintained and reviewed by the community for over fifteen years. Single-file is an architectural choice about deployment footprint, not a statement about internal code organisation. The source is readable and serves as a good reference for how a WSGI framework works internally.

Misconception 3: "I can use Bottle for a large application if I organise my code well."
Reality: Bottle's absence of Blueprints or sub-application composition makes it genuinely difficult to structure large applications. Route registration is global; there is no per-module namespace. At a certain scale, the workarounds required to manage Bottle's flat namespace become more complex than simply using Flask, which was designed for that scale.

---

## Why It Matters in Practice

Bottle matters in practice primarily in two scenarios. The first is constrained environments: Docker base images with minimal Python installations, scripts that must run without internet access for pip, or tools distributed as single files. The second is small, contained tools that would be over-engineered with Flask or FastAPI: a REST endpoint to trigger a build process, a simple status page server, a webhook handler that processes one event type. In these cases, Bottle's zero-setup approach genuinely reduces the time and cognitive overhead to produce a working solution.

For Python developers who have only used Flask or FastAPI, reading Bottle's source is also a valuable learning exercise. The entire WSGI application lifecycle  -  routing, request parsing, response construction, template rendering, error handling  -  is visible in one readable file. It is a more approachable deep dive into web framework internals than reading Flask's or Werkzeug's codebase, and it produces concrete understanding of what happens between nginx accepting a connection and your route handler function receiving a request object.

---

## Interview Angle

Common question forms:
- "When would you use Bottle instead of Flask?"
- "What does 'zero dependencies' mean for a web framework?"
- "What are Bottle's limitations compared to Flask?"

Answer frame:
A strong answer to the first question focuses on deployment constraints and project scope: Bottle when zero-dependency portability is a hard requirement or when the application is small enough that Flask's extension ecosystem adds no value. For the "zero dependencies" question, the answer should cover the operational benefits (no pip install, single file copy, works on minimal Python installations) and the trade-offs (no ecosystem of extensions, must re-implement things Flask has extensions for). For limitations, the key answers are no Blueprints, no extension ecosystem, no async support, and a built-in server that is development-only.

---

## Related Notes

- [[wsgi|WSGI]]
- [[framework-comparison|Python Web Framework Comparison]]
- [[http-basics|HTTP Basics]]
- [[request-response-cycle|Request-Response Cycle]]
