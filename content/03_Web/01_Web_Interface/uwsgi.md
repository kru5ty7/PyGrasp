---
title: 07 - uWSGI
description: "uWSGI is a full-featured C-based application server that implements the WSGI protocol and its own uwsgi binary protocol, commonly used in Django production deployments."
tags: [uwsgi, wsgi, application-server, deployment, django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# uWSGI

> uWSGI is a C-based application server with deep configuration options and a proprietary binary protocol that has powered Django and Flask in production for over a decade — understanding it is essential when maintaining or inheriting older Python web infrastructure.

---

## Quick Reference

**Core idea:**
- uWSGI implements the WSGI spec to serve Python web applications, but its native transport is the uwsgi binary protocol (distinct from WSGI)
- A master process forks worker processes; workers handle WSGI requests and are replaced after configurable request counts
- Configuration lives in a `.ini` file; command-line flags are available but `.ini` is standard for production
- `--harakiri N` kills a worker that takes more than N seconds to respond, preventing hung processes from exhausting the pool
- Works behind nginx via the `uwsgi_pass` directive using the fast uwsgi binary protocol, not HTTP
- Provides optional features: spooler (background task queue), caching, internal routing, and stats server

**Tricky points:**
- The uwsgi protocol (lowercase, binary) and the WSGI spec (uppercase, Python interface) are different things with confusing names
- `--http` flag makes uWSGI speak HTTP directly; `--socket` (or `--uwsgi-socket`) uses the binary protocol — omitting this distinction causes nginx configuration errors
- `--master` must be enabled for harakiri, signal handling, and graceful reloads to work correctly
- `--lazy-apps` loads the app in each worker rather than pre-forking from the master, required when the app has thread-unsafe resources
- Pre-forking means file descriptors and connections opened before `fork()` are shared — database connections should be opened after fork

---

## What It Is

uWSGI's role in a production stack can be understood through an analogy to a factory floor. Nginx is the loading dock — it receives incoming shipments (HTTP requests from the internet) and routes them to the correct department. uWSGI is the factory manager: it maintains a pool of workers (forked Python processes), assigns each incoming job to an available worker, and enforces time limits so that one slow job does not halt the entire floor. Workers communicate with nginx via the uwsgi binary protocol, a compact wire format that is faster than HTTP for internal communication because it carries exactly the fields needed to reconstruct the WSGI environment.

Created by Roberto De Lio and first released in 2009, uWSGI predates many modern alternatives and became the de facto standard for Django deployments through the early 2010s. Its longevity is partly due to its breadth of features — it is not merely a WSGI server but an application container framework with built-in caching, background task queuing (the spooler), process supervision, and a stats server that exposes metrics as JSON. For teams that chose to lean into this ecosystem, uWSGI became a load-bearing part of their infrastructure beyond just serving requests.

The master/worker model is uWSGI's core architecture. When started with `--master`, uWSGI launches a master process that manages a pool of worker processes. Each worker loads a copy of the WSGI application and handles requests independently. The master monitors worker health and can respawn crashed workers, enforce memory limits via `--reload-on-as`, and handle Unix signals for graceful reloads (`kill -HUP <master-pid>` or `--touch-reload`). This model is conceptually similar to Gunicorn's preforking architecture, but uWSGI layers significantly more configurability on top.

---

## How It Actually Works

A minimal production `uwsgi.ini` for a Django project looks like this:

```ini
[uwsgi]
module = myproject.wsgi:application
master = true
workers = 4
threads = 2
socket = /run/myproject/uwsgi.sock
chmod-socket = 660
vacuum = true
harakiri = 30
max-requests = 1000
```

The `module` directive points to the WSGI callable using the same dotted-path notation as `gunicorn`. `socket` creates a Unix domain socket for nginx to connect to via `uwsgi_pass unix:/run/myproject/uwsgi.sock`. `vacuum = true` removes the socket file on exit, preventing stale socket errors on restart. `max-requests = 1000` causes workers to be recycled after 1000 requests, which mitigates slow memory leaks in application code.

The `harakiri` directive is one of uWSGI's most operationally important features. If a worker does not complete a request within the specified number of seconds, the master process sends SIGKILL to that worker and spawns a replacement. This prevents slow database queries or external API calls from permanently consuming a worker slot. In nginx + Gunicorn stacks, this timeout must be implemented at the nginx proxy level (`proxy_read_timeout`) and at the application level; uWSGI handles it natively in the server process.

The uwsgi binary protocol that nginx uses internally is not HTTP. When nginx receives an HTTP request and proxies it to uWSGI via `uwsgi_pass`, it constructs a uwsgi packet containing the HTTP headers encoded as a modifier+key/value structure. uWSGI reads this packet, reconstructs the `environ` dict that the WSGI spec requires, and passes it to the application callable. The response comes back as a plain HTTP response which nginx forwards to the browser. This split — binary protocol inbound to uWSGI, HTTP outbound to the client — is why uWSGI's `--socket` and `--http` flags serve different purposes.

---

## How It Connects

uWSGI implements the WSGI interface — understanding what WSGI is and what contract it defines is prerequisite knowledge for configuring uWSGI correctly and knowing what the `module` directive must point to.

[[wsgi|WSGI]]

Gunicorn is the most direct alternative to uWSGI for WSGI applications; comparing the two illuminates where uWSGI's additional complexity is justified and where Gunicorn's simplicity is preferable.

[[gunicorn|Gunicorn]]

The contrast between WSGI servers like uWSGI and ASGI servers like uvicorn explains the architectural boundary where uWSGI becomes inappropriate for async-first Python applications.

[[wsgi-vs-asgi|WSGI vs ASGI]]

---

## Common Misconceptions

Misconception 1: "The uwsgi protocol and WSGI are the same thing."
Reality: WSGI (PEP 3333) is a Python interface specification — it defines how a web server calls a Python callable and what arguments it passes. The uwsgi protocol is a binary wire format used for network communication between nginx and the uWSGI server process. They share a name similarity only because uWSGI implements the WSGI spec using its own protocol for transport.

Misconception 2: "uWSGI is outdated and should be replaced with Gunicorn for all projects."
Reality: uWSGI's harakiri timeout, spooler, and stats server provide capabilities that Gunicorn requires additional tooling (separate task queues, reverse proxy timeouts) to replicate. For teams already invested in uWSGI's ecosystem, migration carries real risk and cost. The choice should be driven by operational requirements, not age.

Misconception 3: "Adding more workers always improves performance."
Reality: Each worker is a forked Python process consuming independent memory. A Django application with many workers on a memory-limited server will cause the OS to start swapping, which degrades performance severely. The formula `workers = 2 * CPU_cores + 1` is a starting heuristic, not a universal rule.

---

## Why It Matters in Practice

uWSGI appears in virtually every older Django production deployment documented on the internet, and many organizations still run it in production today. A Python developer inheriting or maintaining a Django application deployed on a VPS or on-premises server will almost certainly encounter uWSGI `.ini` files, systemd unit files that manage the uWSGI process, and nginx configurations with `uwsgi_pass` directives. Knowing how to tune `workers`, set `harakiri`, enable graceful reloads, and interpret the stats server output is practical operational knowledge that directly affects uptime.

For new projects, Gunicorn is typically the simpler choice for synchronous WSGI applications, and uvicorn or Hypercorn is the correct choice for ASGI applications. uWSGI's primary ongoing advantage is in its spooler (for background tasks without a separate broker) and in environments where operations teams have deep existing familiarity with its configuration model.

---

## Interview Angle

Common question forms:
- "How would you deploy a Django application for production?"
- "What is the role of uWSGI in a typical nginx + uWSGI deployment?"
- "What does harakiri do in a uWSGI configuration?"

Answer frame:
A strong answer to the deployment question describes the three-tier stack: nginx as the reverse proxy and static file server, uWSGI as the application server managing Python worker processes, and the WSGI application itself. For the harakiri question, a strong answer explains that it is a request timeout enforced by the master process — a worker that exceeds the limit is killed and replaced, preventing one slow request from permanently consuming a worker slot. Connecting this to the broader problem of process pool exhaustion in web servers shows depth.

---

## Related Notes

- [[wsgi|WSGI]]
- [[gunicorn|Gunicorn]]
- [[wsgi-vs-asgi|WSGI vs ASGI]]
- [[asgi|ASGI]]
