---
title: 06 - RQ (Redis Queue)
description: "RQ is a simple Python task queue backed exclusively by Redis that enqueues plain Python functions as jobs, offering a much lower-friction setup than Celery for projects that only need Redis."
tags: [rq, redis-queue, task-queue, workers, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# RQ (Redis Queue)

> RQ is the minimal-setup alternative to Celery — if your broker is Redis and your tasks are Python functions, RQ enqueues and executes them with almost no configuration overhead.

---

## Quick Reference

**Core idea:**
- `q = Queue(connection=Redis())` creates a queue; `job = q.enqueue(my_function, arg1, arg2)` enqueues
- Workers run as a separate process: `rq worker` (subscribes to `default` queue) or `rq worker high low`
- `job.result` holds the return value after completion; `job.get_status()` returns `queued`, `started`, `finished`, `failed`
- Failed jobs go to the `failed` queue automatically; inspect with `rq info` or the `FailedJobRegistry`
- `rq info` shows queue lengths and worker status from the command line

**Tricky points:**
- RQ requires the task function to be importable by the worker — the worker and the application must share the same Python path and package structure
- No built-in scheduled tasks — use `rq-scheduler` as a separate component (equivalent to Celery Beat)
- Result TTL: `job.result` is stored in Redis with a default TTL of 500 seconds; jobs that complete before you check `job.result` may have expired results
- Retry: `q.enqueue(func, retry=Retry(max=3, interval=[10, 30, 60]))` — not automatic, must be specified at enqueue time
- RQ is Redis-only — if your architecture requires RabbitMQ or another broker, use Celery or Dramatiq instead

---

## What It Is

Celery is powerful but it brings significant configuration surface: broker URL, backend URL, serializer settings, concurrency model, task discovery modules, Beat scheduler, Flower monitoring. For many projects — particularly smaller services, internal tools, or prototypes — this complexity is not justified. RQ offers an alternative philosophy: keep it as simple as a Python function call, use Redis as the only backend, and require almost zero configuration.

The core concept in RQ is the job. A job is a Python function together with its arguments, serialized via pickle into Redis. Enqueueing a job takes one line. A worker process — started with the `rq worker` command — polls Redis for jobs, deserializes them, and calls the function. The worker needs no special configuration beyond the Redis connection URL. The task function itself needs no decorator or registration — any callable in the Python path is a valid RQ job.

This simplicity comes with deliberate constraints. RQ supports only Redis. It has no built-in cron-style scheduling (though `rq-scheduler` adds this). It uses pickle for serialization, which means job arguments can be complex Python objects — but pickle has known security implications if untrusted data reaches the worker. For projects where these constraints are acceptable, RQ provides a faster path to working background jobs than any other Python task queue.

---

## How It Actually Works

The producer side is minimal. Import the function, create a queue with a Redis connection, and call `enqueue()`.

```python
from redis import Redis
from rq import Queue
from myapp.tasks import send_email, process_image

redis_conn = Redis(host="localhost", port=6379)
q = Queue(connection=redis_conn)
default_q = Queue("default", connection=redis_conn)
high_q = Queue("high", connection=redis_conn)

# Basic enqueue
job = q.enqueue(send_email, "user@example.com", "Subject", "Body")
print(job.id)  # UUID string

# With timeout and TTL
job = q.enqueue(
    process_image,
    "/uploads/photo.jpg",
    job_timeout=120,        # max 2 minutes before worker kills it
    result_ttl=3600,        # keep result in Redis for 1 hour
    failure_ttl=86400,      # keep failed job info for 24 hours
)

# With retry
from rq.job import Retry
job = q.enqueue(send_email, "user@example.com", retry=Retry(max=3, interval=[10, 30, 60]))

# Check status
print(job.get_status())   # "queued", "started", "finished", "failed"
print(job.result)         # return value (None if not finished or expired)
```

Workers are started from the command line, optionally with a list of queues to subscribe to. Workers process queues left to right — a worker subscribed to `["high", "default", "low"]` will always clear all `high` jobs before looking at `default`.

```bash
rq worker                        # subscribes to "default"
rq worker high default low       # priority order
rq worker --url redis://myhost:6379/0 high default
```

Failed jobs go to the `FailedJobRegistry`. Inspect and retry from the Python shell or a management script.

```python
from rq.job import Job
from rq.registry import FailedJobRegistry

failed_registry = FailedJobRegistry("default", connection=redis_conn)
for job_id in failed_registry.get_job_ids():
    job = Job.fetch(job_id, connection=redis_conn)
    print(job.exc_info)   # exception traceback
    job.requeue()         # move back to the original queue
```

---

## How It Connects

RQ uses Redis as its only backend — understanding Redis connection management and the connection pool pattern applies directly to how RQ manages its broker connection.

[[redis-python|Redis with Python]]

Celery is the more powerful alternative when RabbitMQ support, advanced routing, or built-in scheduling is needed — knowing both allows an informed choice.

[[celery|Celery]]

---

## Common Misconceptions

Misconception 1: "RQ is a good choice for scheduled periodic tasks."
Reality: RQ has no built-in scheduler. `rq-scheduler` adds periodic scheduling as a separate process, but it is not as mature or feature-rich as Celery Beat. If periodic tasks are a primary requirement, Celery with Beat is the more complete solution.

Misconception 2: "RQ and Celery have equivalent operational complexity once configured."
Reality: Celery has more knobs — concurrency models, serializers, routing, priorities, result expiry — which means more configuration surface and more things to misconfigure. RQ's operational simplicity is permanent, not just at initial setup. For teams that do not need Celery's advanced features, this simplicity has ongoing value.

---

## Why It Matters in Practice

RQ appears frequently in smaller Django and Flask projects and internal tooling. Knowing its API — `Queue`, `enqueue()`, `job.get_status()`, `FailedJobRegistry` — and its constraints (Redis-only, no built-in scheduling) allows fast integration and informed trade-off decisions. The choice between RQ and Celery should be deliberate, not defaulted.

---

## Interview Angle

Common question forms:
- "What are the trade-offs between RQ and Celery?"
- "How does RQ handle failed jobs?"

Answer frame:
RQ is simpler: Redis-only, no decorator required, minimal config. Celery is more powerful: multiple broker options, advanced routing, built-in scheduling with Beat, multiple concurrency models. RQ failed jobs go to `FailedJobRegistry` automatically and can be requeued. Use RQ for simple background jobs in Redis-only stacks; use Celery when you need RabbitMQ, scheduled tasks, or fine-grained routing.

---

## Related Notes

- [[celery|Celery]]
- [[redis-python|Redis with Python]]
- [[dramatiq|Dramatiq]]
