---
title: 05 - Gunicorn
description: "Gunicorn is a pre-fork WSGI server — it spawns multiple worker processes that each handle HTTP requests independently; supports sync, gevent, and Uvicorn workers; used in production to provide process supervision and horizontal scaling."
tags: [gunicorn, wsgi, pre-fork, workers, UvicornWorker, production-deployment, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Gunicorn

> Gunicorn is a pre-fork WSGI server — it spawns multiple worker processes that each handle HTTP requests independently; supports sync, gevent, and Uvicorn workers; used in production to provide process supervision and horizontal scaling.

---

## Quick Reference

**Core idea:**
- `gunicorn myapp:app -w 4` — starts 4 worker processes; master process manages them
- `-w/--workers` — number of worker processes; rule of thumb: `2 * CPU_COUNT + 1`
- `-k/--worker-class` — worker type: `sync` (default), `gevent`, `uvicorn.workers.UvicornWorker`
- `--timeout` — worker killed if no response in this many seconds (default 30); increase for slow endpoints
- `--bind 0.0.0.0:8000` — address and port to listen on

**Tricky points:**
- Gunicorn is WSGI-native — running FastAPI under Gunicorn requires `-k uvicorn.workers.UvicornWorker`; the `UvicornWorker` handles the ASGI interface
- `sync` workers are one-request-at-a-time per process — they block the worker while processing; for I/O-bound apps, use `gevent` workers or move to Uvicorn
- Worker count × peak memory usage = total memory needed — more workers = more parallelism but also more RAM
- Gunicorn's master process automatically restarts workers that crash — this is its primary value in production
- Signals: `SIGHUP` gracefully reloads workers (zero-downtime config change); `SIGTERM` graceful shutdown; `SIGKILL` immediate stop

---

## What It Is

Gunicorn implements the pre-fork model: before any requests arrive, it forks N worker processes from the master. Each worker is an independent Python process with its own memory, GIL, and connection handler. The master process only monitors workers and restarts any that die — it doesn't serve requests itself.

This model bypasses the GIL for parallelism (separate processes) and provides resilience (a crashing worker is replaced without affecting others or the master). It's the standard production server for WSGI frameworks (Django, Flask) and, via the `UvicornWorker`, for ASGI frameworks (FastAPI).

---

## How It Actually Works

Production deployment command:
```bash
gunicorn myapp:app \
  --workers 4 \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000 \
  --timeout 60 \
  --access-logfile - \
  --error-logfile -
```

Gunicorn config file (`gunicorn.conf.py`):
```python
workers = 4
worker_class = "uvicorn.workers.UvicornWorker"
bind = "0.0.0.0:8000"
timeout = 60
keepalive = 5
loglevel = "info"
```

Worker types:
```
sync           → one request at a time; default; fine for CPU-bound
gthread        → threaded sync workers; N threads per worker; moderate I/O
gevent         → green threads; high I/O concurrency; requires gevent-compatible libs
uvicorn.workers.UvicornWorker  → ASGI worker; for FastAPI/Starlette
```

Zero-downtime deployment:
```bash
# Send SIGHUP to gracefully reload workers (new workers pick up new code)
kill -HUP $(cat /var/run/gunicorn.pid)
```

---

## How It Connects

Gunicorn serves WSGI apps directly and ASGI apps via the `UvicornWorker` — understanding the WSGI/ASGI interface explains why the worker class matters.
[[wsgi-vs-asgi|WSGI vs ASGI]]

Uvicorn is the ASGI server often used standalone in development; in production it's run as a Gunicorn worker for process management.
[[uvicorn|Uvicorn]]

---

## Common Misconceptions

Misconception 1: "More workers always means better performance."
Reality: More workers = more parallelism for CPU-bound work, but also more memory. For I/O-bound async apps, a single Uvicorn worker may handle more concurrent requests than 4 sync workers. The right worker count depends on the workload type.

Misconception 2: "Gunicorn alone is sufficient for production."
Reality: Gunicorn should sit behind a reverse proxy (Nginx, Caddy, or a cloud LB). The reverse proxy handles TLS termination, static file serving, rate limiting, and connection buffering. Gunicorn is not designed to be directly internet-facing.

---

## Why It Matters in Practice

Typical production stack:
```
Internet → Nginx (TLS, static files, rate limiting)
         → Gunicorn (process management, workers)
         → UvicornWorker (ASGI event loop)
         → FastAPI application
```

Kubernetes/Docker: Gunicorn's process management is less important in containers (orchestrators restart crashed containers). Many containerized deployments use Uvicorn directly with a single worker — container orchestration handles scaling.

---

## Interview Angle

Common question forms:
- "How do you deploy a FastAPI app in production?"
- "What does Gunicorn do?"

Answer frame: Gunicorn is a pre-fork process manager — spawns N worker processes, restarts crashed ones. For FastAPI (ASGI), use `uvicorn.workers.UvicornWorker`. Workers = `2 * CPUs + 1` for CPU-bound; fewer for async I/O-heavy. Sits behind Nginx for TLS, static files, buffering. `SIGHUP` for zero-downtime reload.

---

## Related Notes

- [[uvicorn|Uvicorn]]
- [[wsgi-vs-asgi|WSGI vs ASGI]]
- [[wsgi|WSGI]]
- [[fastapi|FastAPI]]
