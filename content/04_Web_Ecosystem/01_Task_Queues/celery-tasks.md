---
title: 02 - Celery Tasks
description: "Celery tasks are Python functions decorated to run asynchronously in worker processes, with built-in support for retries, state tracking, and idempotent execution patterns."
tags: [celery, tasks, retry, idempotency, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Celery Tasks

> A Celery task is a Python function that can be called immediately or deferred to run in a background worker  -  understanding the task lifecycle, retry mechanics, and idempotency requirement is what separates reliable Celery code from brittle code.

---

## Quick Reference

**Core idea:**
- `@app.task` registers a function as a Celery task; `@shared_task` avoids coupling the task to a specific app instance
- `.delay(arg1, arg2)` enqueues with positional args; `.apply_async(args, kwargs, countdown=60, eta=datetime)` gives full control
- Task states progress: `PENDING` -> `STARTED` (if `task_track_started=True`) -> `SUCCESS` or `FAILURE` or `RETRY`
- `bind=True` passes the task instance as `self`  -  required for `self.retry()`, `self.request.id`, and accessing task metadata
- Tasks may execute more than once  -  design them to produce the same result regardless of how many times they run

**Tricky points:**
- `task.retry()` re-raises by default to move the task to `RETRY` state  -  call it inside an `except` block and pass the exception with `exc=exc`
- `max_retries=None` means infinite retries  -  always set an explicit limit unless you have a specific reason not to
- `countdown` is seconds until the next retry attempt; use exponential backoff: `countdown=2 ** self.request.retries`
- `apply_async(eta=datetime)` schedules the task for a specific UTC time  -  the worker will not execute it until then
- `@app.task(ignore_result=True)` skips writing to the result backend  -  set this for fire-and-forget tasks to reduce backend load

---

## What It Is

A Celery task function looks like any other Python function but carries additional machinery. When you decorate a function with `@app.task`, Celery wraps it in a `Task` class that knows how to serialize itself into a broker message, track its execution state, handle retries, and store its result. The decorated function becomes an object with methods like `.delay()`, `.apply_async()`, and `.retry()`.

The distinction between `@app.task` and `@shared_task` matters for project structure. `@app.task` binds the task directly to a specific Celery application instance  -  this creates a hard dependency between the task module and the module where the app is created. `@shared_task` defers the binding until the task is actually used, making it suitable for reusable library code or Django apps that want to avoid importing the Celery app directly.

The task state machine is central to understanding Celery's behavior. A task starts as `PENDING`  -  it exists as a message in the broker queue but no worker has acknowledged it yet. Once a worker picks it up, the state becomes `STARTED` (only if `task_track_started=True` is configured). After execution, the state is either `SUCCESS` (return value stored in backend) or `FAILURE` (exception information stored). If the task calls `self.retry()`, it transitions through `RETRY` back to `PENDING` as a new message is sent to the broker.

---

## How It Actually Works

A basic task with error handling and retry logic demonstrates the full lifecycle. The `bind=True` argument makes the task instance available as `self`, which is necessary to call `self.retry()` and access metadata like `self.request.id` (the unique task ID) and `self.request.retries` (how many times this task has been retried so far).

```python
from celery import shared_task
from celery.exceptions import MaxRetriesExceededError
import logging

logger = logging.getLogger(__name__)

@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def send_email(self, recipient: str, subject: str, body: str):
    try:
        # call email service
        email_service.send(recipient, subject, body)
    except email_service.TemporaryError as exc:
        # Retry with exponential backoff
        raise self.retry(exc=exc, countdown=2 ** self.request.retries)
    except email_service.PermanentError as exc:
        # Log and do not retry
        logger.error("Permanent email failure for %s: %s", recipient, exc)
        raise
```

Calling the task from application code:

```python
# Fire-and-forget
send_email.delay("user@example.com", "Welcome", "Thanks for signing up")

# With delay (send in 5 minutes)
send_email.apply_async(
    args=["user@example.com", "Reminder", "Don't forget to complete setup"],
    countdown=300,
)

# Get result (blocks until complete)
result = send_email.delay("user@example.com", "Test", "body")
value = result.get(timeout=30)  # raises exception if task failed
```

Idempotency is not optional in Celery  -  it is a requirement of the at-least-once delivery model. The broker guarantees that a task is delivered at least once, not exactly once. If a worker crashes after executing a task but before acknowledging the message, the broker will re-deliver the message to another worker. A task that creates a database record must check whether the record already exists before creating it. A task that sends an email should use a deduplication key to ensure the same email is not sent twice.

```python
@shared_task(bind=True)
def create_invoice(self, order_id: int):
    # Idempotent: check before creating
    if Invoice.objects.filter(order_id=order_id).exists():
        return {"status": "already_exists", "order_id": order_id}
    invoice = Invoice.objects.create(order_id=order_id)
    return {"status": "created", "invoice_id": invoice.id}
```

---

## How It Connects

Celery infrastructure  -  the app object, broker configuration, and worker startup  -  is covered in the parent note on Celery itself.

[[celery|Celery]]

Scheduled periodic tasks that automatically enqueue these task functions are managed by Celery Beat.

[[celery-beat|Celery Beat]]

---

## Common Misconceptions

Misconception 1: "Calling `self.retry()` inside an except block immediately retries the task."
Reality: `self.retry()` raises a `Retry` exception internally, which signals Celery to re-enqueue the task message to the broker with the specified delay. The current task execution terminates at that point. The retry runs as a new task execution after `countdown` seconds, not immediately in the same process.

Misconception 2: "A task decorated with `@app.task` is automatically idempotent."
Reality: Celery provides no idempotency guarantees at the framework level. The developer is entirely responsible for writing tasks that are safe to execute multiple times. This typically means using database-level uniqueness constraints or existence checks before performing writes.

---

## Why It Matters in Practice

Tasks that are not idempotent silently corrupt data under failure conditions  -  a duplicate email, a double charge, an extra database record. These bugs are intermittent (they appear only when workers crash or the broker redelivers) and hard to reproduce in tests. Writing idempotent tasks from the start, setting explicit `max_retries`, and using exponential backoff prevents an entire category of production incidents.

---

## Interview Angle

Common question forms:
- "What does it mean for a Celery task to be idempotent and why does it matter?"
- "How do you implement retry logic in a Celery task?"
- "What is the difference between `.delay()` and `.apply_async()`?"

Answer frame:
Idempotent means running the task N times produces the same result as running it once  -  required because Celery's at-least-once delivery can cause redeliveries on worker crash. Retry: use `bind=True`, catch the exception, call `self.retry(exc=exc, countdown=2**self.request.retries)` for exponential backoff with `max_retries` set. `.delay(args)` is shorthand; `.apply_async(args, kwargs, countdown, eta)` is the full version for scheduling.

---

## Related Notes

- [[celery|Celery]]
- [[celery-beat|Celery Beat]]
- [[celery-workers|Celery Workers and Concurrency]]
- [[celery-monitoring|Monitoring Celery with Flower]]
