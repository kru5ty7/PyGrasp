---
title: 04 - Prometheus with Python
description: "The prometheus_client library exposes Python application metrics via a /metrics HTTP endpoint that Prometheus scrapes, with FastAPI middleware tracking request rate, error rate, and duration automatically for every route."
tags: [prometheus, prometheus-client, fastapi, metrics, middleware, scrape-endpoint, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Prometheus with Python

> Integrating Prometheus with a Python application means creating metric instruments (Counter, Gauge, Histogram), incrementing them in application code or middleware, and exposing a `/metrics` endpoint that the Prometheus server scrapes on a configured interval.

---

## Quick Reference

**Core idea:**
- `pip install prometheus-client`  -  the official Python Prometheus client library
- `Counter`, `Gauge`, `Histogram`, `Summary` from `prometheus_client`  -  the four instrument types
- `make_asgi_app()` from `prometheus_client`  -  creates a WSGI/ASGI app that serves the `/metrics` endpoint
- FastAPI middleware tracks every request's duration and status automatically
- Prometheus scrapes `/metrics` every `scrape_interval` (default 15s)  -  no push, pull model
- `REGISTRY.unregister(metric)`  -  remove a metric from the default registry (useful in tests)

**Tricky points:**
- The default Prometheus registry (`prometheus_client.REGISTRY`) is global  -  registering the same metric name twice raises `ValueError`; use `Registry()` in tests to avoid cross-test contamination
- `start_http_server(8001)` runs a dedicated metrics HTTP server in a background thread  -  useful for non-web applications; for FastAPI, mount the metrics app instead
- `multiprocess_mode` is required when using `gunicorn` with multiple workers  -  each worker has separate memory; multiprocess mode uses a shared directory to aggregate metrics
- Do not expose `/metrics` to the public internet  -  it reveals internal implementation details; protect with network policy or HTTP authentication
- Labels are immutable once the metric is created  -  you cannot add new label names after registration

---

## What It Is

Prometheus with Python is the practice of instrumenting a Python application so that Prometheus can scrape its internal state. The `prometheus_client` library provides Python classes that mirror Prometheus's metric types  -  Counter, Gauge, Histogram, Summary  -  and manages the serialization of their current values into the Prometheus text exposition format. When Prometheus scrapes the application's `/metrics` endpoint, it reads this serialized representation and stores it as time series.

The pull model is a deliberate architectural choice. Rather than the application pushing metrics to a monitoring server, the monitoring server reaches out to the application on a schedule. This means the application does not need to know where Prometheus is running  -  it just needs to expose the HTTP endpoint. Prometheus's configuration determines which targets to scrape and how often. The pull model also means that if the application is down, Prometheus records a scrape failure, which is itself a useful signal.

For a FastAPI application, the cleanest integration pattern is a middleware that runs for every request and records the request count, error count, and request duration. This provides the three RED metrics for every endpoint without requiring any changes to route handlers. The middleware approach is also the safest: it measures what actually reached the application, including requests that were rejected early or that caused unhandled exceptions.

---

## How It Actually Works

**Basic metric definition and usage:**

```python
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST

# Define metrics at module level (not inside functions  -  they are global)
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "http_status"]
)

REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "endpoint"],
    buckets=[0.005, 0.010, 0.025, 0.050, 0.100, 0.250, 0.500, 1.000, 2.500, 5.000]
)

ACTIVE_REQUESTS = Gauge(
    "http_requests_in_progress",
    "HTTP requests currently in progress"
)
```

**FastAPI integration with middleware:**

```python
import time
from fastapi import FastAPI, Request, Response
from prometheus_client import make_asgi_app

app = FastAPI()

# Mount the metrics endpoint as a separate ASGI app
# This keeps /metrics separate from your API router
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

@app.middleware("http")
async def prometheus_middleware(request: Request, call_next):
    # Normalize path to avoid high-cardinality (e.g., /users/123 -> /users/{user_id})
    path = request.url.path

    ACTIVE_REQUESTS.inc()
    start_time = time.perf_counter()

    response = await call_next(request)

    duration = time.perf_counter() - start_time
    status_code = str(response.status_code)

    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=path,
        http_status=status_code,
    ).inc()

    REQUEST_DURATION.labels(
        method=request.method,
        endpoint=path,
    ).observe(duration)

    ACTIVE_REQUESTS.dec()

    return response
```

**Multiprocess mode** for Gunicorn with multiple workers:

```python
# app.py  -  required setup for multiprocess mode
import os
from prometheus_client import multiprocess, CollectorRegistry, make_asgi_app

def make_metrics_app():
    registry = CollectorRegistry()
    multiprocess.MultiProcessCollector(registry)
    return make_asgi_app(registry=registry)

# gunicorn.conf.py
def child_exit(server, worker):
    """Called when a worker exits  -  clean up its metrics files."""
    from prometheus_client import multiprocess
    multiprocess.mark_process_dead(worker.pid)

# Environment variable required:
# PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc
```

**Instrumenting non-HTTP code:**

```python
from prometheus_client import Counter, Histogram
import functools
import time

TASK_DURATION = Histogram(
    "background_task_duration_seconds",
    "Background task execution time",
    ["task_name"]
)

TASK_ERRORS = Counter(
    "background_task_errors_total",
    "Background task errors",
    ["task_name", "error_type"]
)

def track_task(task_name: str):
    """Decorator to track task duration and errors."""
    def decorator(func):
        @functools.wraps(func)
        async def wrapper(*args, **kwargs):
            with TASK_DURATION.labels(task_name=task_name).time():
                try:
                    return await func(*args, **kwargs)
                except Exception as e:
                    TASK_ERRORS.labels(
                        task_name=task_name,
                        error_type=type(e).__name__
                    ).inc()
                    raise
        return wrapper
    return decorator

@track_task("process_invoice")
async def process_invoice(invoice_id: int):
    ...
```

**Path normalization** is critical for cardinality control. The URL `/users/42` and `/users/99` are different paths but should be recorded as the same metric endpoint (`/users/{user_id}`). Without normalization, a service with millions of users would create millions of unique time series.

```python
import re

def normalize_path(path: str) -> str:
    """Replace path parameters with placeholders."""
    # Replace UUIDs
    path = re.sub(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '{uuid}', path)
    # Replace numeric IDs
    path = re.sub(r'/\d+', '/{id}', path)
    return path
```

---

## How It Connects

The four metric types (Counter, Gauge, Histogram, Summary) and the RED method rationale are covered in the metrics foundations note.

[[metrics-and-monitoring|Metrics and Monitoring]]

FastAPI middleware is the mechanism used to intercept every request for instrumentation  -  understanding how middleware works clarifies why the prometheus_middleware wraps `call_next`.

[[fastapi-middleware|Middleware in FastAPI]]

OpenTelemetry provides an alternative metrics API that can export to Prometheus  -  if a project uses OpenTelemetry for tracing, it makes sense to use OpenTelemetry metrics as well to have a single instrumentation API.

[[opentelemetry|OpenTelemetry]]

---

## Common Misconceptions

Misconception 1: "I should call `Counter('http_requests_total', ...)` inside request handler functions to create metrics."
Reality: Metric objects should be created once at module import time, not inside functions. Creating a metric object registers it with the default registry. Calling the creation code multiple times raises `ValueError: Duplicated timeseries`. Define metrics as module-level constants.

Misconception 2: "The `/metrics` endpoint is safe to expose publicly alongside the API."
Reality: The `/metrics` endpoint reveals application internals  -  endpoint names, error rates, background job names, database connection pool sizes. This information is useful to attackers (identifies internal structure, reveals error patterns). Restrict access with network policies (Kubernetes NetworkPolicy allowing only Prometheus scraper), HTTP middleware requiring an internal token, or by binding the metrics endpoint to a different port that is not publicly accessible.

Misconception 3: "With multiprocess workers, each worker's metrics are automatically combined."
Reality: Each Gunicorn worker is a separate process with separate memory. The default single-process registry does not work with multiple workers  -  each worker would return only its own partial metrics when scraped. Multiprocess mode requires setting `PROMETHEUS_MULTIPROC_DIR` to a shared directory where each worker writes its metric state, and using `MultiProcessCollector` to aggregate them at scrape time.

---

## Why It Matters in Practice

The operational value of Prometheus instrumentation is that it turns "the service seems slow" into "the service's p95 latency for `POST /api/payments` has increased from 150ms to 800ms in the last 10 minutes, and the `charge_gateway` duration histogram shows most of the increase is in the 0.5 - 2.5 second bucket." The specificity enables targeted diagnosis: the problem is in the payment gateway call, not in the database or in the request parsing.

Alert rules become reliable when grounded in Prometheus metrics. A rule like "page if `rate(http_requests_total{http_status=~'5..'}[5m]) / rate(http_requests_total[5m]) > 0.01` for 5 minutes" fires precisely when 1% of requests are errors, sustained for 5 minutes. This is a meaningful signal that is both sensitive enough to catch real problems and specific enough to avoid false alarms.

---

## Interview Angle

Common question forms:
- "How would you add Prometheus metrics to a FastAPI application?"
- "How do you handle Prometheus metrics with multiple Gunicorn workers?"

Answer frame:
Describe the three components: define metrics at module level, instrument them in middleware (for HTTP metrics) or decorators (for other code), and mount the `/metrics` endpoint using `make_asgi_app()`. Explain the cardinality concern  -  normalize path parameters before using them as label values. Describe multiprocess mode for Gunicorn. Note the security consideration: do not expose `/metrics` publicly.

---

## Related Notes

- [[metrics-and-monitoring|Metrics and Monitoring]]
- [[opentelemetry|OpenTelemetry]]
- [[fastapi-middleware|Middleware in FastAPI]]
- [[fastapi|FastAPI]]
