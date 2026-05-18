---
title: 01 - Celery
description: "Celery is a distributed task queue that lets Python applications offload work to background worker processes via a message broker, decoupling long-running operations from the request/response cycle."
tags: [celery, task-queue, redis, rabbitmq, workers, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Celery

> Celery separates the web application from slow, resource-intensive work — a request handler enqueues a task and returns immediately while a background worker processes it asynchronously.

---

## Quick Reference

**Core idea:**
- Producer (web app) serializes a task message and sends it to the broker (Redis or RabbitMQ)
- Worker process continuously polls the broker, receives messages, deserializes them, and executes the task function
- Broker stores and routes tasks; result backend stores return values and task status
- `app = Celery('myapp', broker='redis://localhost:6379/0', backend='redis://localhost:6379/1')`
- Start workers: `celery -A myapp worker --loglevel=info`

**Tricky points:**
- Broker and backend are separate: you need the backend only if you use `.get()` to retrieve results; without a backend, tasks are fire-and-forget
- Tasks must be importable at the module level — Celery discovers them via the `app.autodiscover_tasks()` mechanism or explicit `include` list
- Concurrency model defaults to `prefork` (multiprocessing) — for I/O-heavy tasks, `--pool=gevent` or `--pool=eventlet` is dramatically more efficient
- Serialization defaults to JSON — task arguments must be JSON-serializable; avoid passing ORM model instances directly
- Always set `task_always_eager = True` in test settings so tasks execute synchronously in tests without needing a broker

---

## What It Is

Imagine a restaurant kitchen. The waiter (web application) takes a customer's order, hands it to the kitchen (broker), and returns to attend other customers. The cook (Celery worker) picks up the ticket from the pass-through and prepares the dish. The waiter does not stand at the kitchen window waiting for the food — they are already helping the next customer. Celery implements exactly this pattern for software: the web application hands off work and moves on; the work happens separately.

This decoupling solves several practical problems. Sending an email, resizing an uploaded image, generating a PDF, syncing with a third-party API — all of these take longer than an HTTP request can reasonably wait. A user clicking "send invoice" should not stare at a loading spinner for ten seconds while the server generates and emails the document. With Celery, the handler creates a task, returns "your invoice is being generated," and a worker finishes the job in the background.

Celery has two required external components: a broker and an optional result backend. The broker is the message queue — Redis and RabbitMQ are the standard choices. When a producer calls `.delay()` or `.apply_async()`, Celery serializes the task name and arguments into a message and publishes it to the broker. Workers subscribe to the broker queue, receive messages, deserialize them, and execute the corresponding Python function. The result backend, when configured, stores the return value and final state of each task execution under the task's ID, allowing callers to poll for completion with `AsyncResult(task_id).get()`.

---

## How It Actually Works

Application setup defines the Celery instance, which carries all configuration. In a Django or FastAPI project, this lives in a dedicated module (e.g., `celery_app.py` or `worker.py`).

```python
from celery import Celery

app = Celery(
    "myapp",
    broker="redis://localhost:6379/0",
    backend="redis://localhost:6379/1",
    include=["myapp.tasks"],  # modules containing task definitions
)

app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    task_track_started=True,
)
```

Tasks are Python functions decorated with `@app.task`. Calling `.delay()` is shorthand for `.apply_async()` with positional arguments.

```python
# myapp/tasks.py
from .celery_app import app

@app.task
def send_email(recipient: str, subject: str, body: str):
    # actual email sending logic
    pass

# In a web handler
send_email.delay("user@example.com", "Welcome", "Thanks for signing up")
```

Workers run as separate processes, started from the command line. The `--loglevel` and `--concurrency` flags control verbosity and the number of parallel execution slots.

```bash
celery -A myapp worker --loglevel=info --concurrency=4
celery -A myapp inspect active    # see what workers are currently executing
celery -A myapp inspect reserved  # see queued tasks assigned but not started
```

Concurrency mode selection matters significantly for performance. The default `prefork` pool spawns N subprocesses, each handling one task at a time — correct for CPU-bound work where true parallelism is needed. For I/O-bound tasks (HTTP calls, database queries), gevent or eventlet pools use cooperative multitasking to handle thousands of tasks per worker process without spawning thousands of OS threads.

---

## How It Connects

Task definitions, retry logic, and task state management are covered in depth in the companion note — this note covers the infrastructure layer.

[[celery-tasks|Celery Tasks]]

Celery Beat is the scheduler process that generates periodic tasks, complementing the worker layer.

[[celery-beat|Celery Beat]]

---

## Common Misconceptions

Misconception 1: "Celery workers process tasks in the order they were submitted."
Reality: By default, Celery uses a single queue and workers process tasks in FIFO order within that queue. However, multiple workers processing the same queue can result in out-of-order execution. Priority queues require explicit routing configuration — assigning tasks to separate queues and running workers subscribed to specific queues.

Misconception 2: "The broker and backend are the same thing."
Reality: The broker routes task messages from producers to workers — it is only involved at enqueue and dequeue time. The backend stores results after a task completes — it is involved only if you call `.get()` on the result. You can run Celery without a backend (fire-and-forget tasks) but never without a broker.

---

## Why It Matters in Practice

Celery is the most widely deployed Python background task system. Understanding its architecture — producer/broker/worker separation, the distinction between broker and backend, and the concurrency model options — is required knowledge for any Python backend developer. Misconfiguring the pool type (using prefork for thousands of I/O-bound tasks) or omitting a backend when results are needed are two of the most common operational mistakes.

---

## Interview Angle

Common question forms:
- "Explain how Celery works."
- "What is the difference between a Celery broker and a Celery backend?"
- "What concurrency model would you use for I/O-bound tasks in Celery?"

Answer frame:
Celery is a distributed task queue. The web app serializes a task and sends it to the broker (Redis/RabbitMQ). A worker process picks it up, deserializes it, and runs the function. The broker routes messages; the backend stores results. For CPU-bound tasks use `prefork`; for I/O-bound tasks use `gevent` or `eventlet` for much higher concurrency per worker. Tasks should be idempotent because at-least-once delivery means a task may run more than once.

---

## Related Notes

- [[celery-tasks|Celery Tasks]]
- [[celery-beat|Celery Beat]]
- [[celery-workers|Celery Workers and Concurrency]]
- [[celery-monitoring|Monitoring Celery with Flower]]
- [[redis-python|Redis with Python]]
- [[rq|RQ (Redis Queue)]]
