---
title: 05 - Monitoring Celery with Flower
description: "Flower is a real-time web-based monitoring tool for Celery that shows worker status, task history, queue depths, and allows task revocation from a browser interface."
tags: [celery, flower, monitoring, observability, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Monitoring Celery with Flower

> Flower is Celery's built-in web dashboard — it gives operators a live view of worker health, task throughput, and failure rates without writing any monitoring code.

---

## Quick Reference

**Core idea:**
- Start Flower: `celery -A myapp flower --port=5555`
- Dashboard shows: worker online/offline status, tasks per worker, active/queued/completed/failed counts
- Task history: drill into individual task details, arguments, result, exception traceback, execution time
- Task revocation: cancel a queued or running task from the UI with optional `terminate=True`
- Flower connects to the broker and listens to Celery's real-time event stream — no polling the database

**Tricky points:**
- Flower requires `task_send_sent_event=True` and `worker_send_task_events=True` in Celery config to show full task history — without these, it only sees events from workers that are currently online
- Flower state is in-memory by default — restarting Flower loses all history; use `--persistent=True` with a database for persistence
- Authentication: `--basic_auth=user:password` for simple protection; expose Flower only inside a private network or behind a VPN in production
- `--max_tasks=10000` limits how many tasks Flower keeps in memory — prevent unbounded memory growth in high-throughput systems
- Flower API: all UI actions are also available via REST endpoints at `/api/*` — useful for programmatic monitoring or alerting

---

## What It Is

Celery workers are silent by nature — they pull tasks from a queue and execute them without producing any visible output unless you look at logs. In a production system with dozens of workers processing thousands of tasks per hour, understanding the system state requires more than reading log files. How many tasks are queued? Are workers healthy? Which tasks are failing and at what rate? How long is the average task taking? Flower answers all of these questions through a web interface that updates in real time.

Flower connects to the Celery broker and subscribes to Celery's internal event stream. When a task is published, received, started, succeeded, or failed, Celery emits an event. Flower consumes these events and maintains an aggregated view of the system state. This event-driven architecture means Flower reflects the true live state of the system — there is no polling delay, no separate metrics database to maintain, and no instrumentation code to add to tasks.

The tool was created as part of the Celery ecosystem and ships as a separate Python package (`flower`). It runs as a standalone web application, typically on port 5555, and can be deployed alongside workers in the same container or as a separate service. Because it only reads events from the broker, it has no write access to tasks or workers — except for the revocation feature, which sends a control message through the broker's control channel.

---

## How It Actually Works

Flower is started as a Celery sub-command and requires the same `--app` flag used for workers and Beat.

```bash
# Basic start
celery -A myapp flower --port=5555

# With authentication and persistent state
celery -A myapp flower \
    --port=5555 \
    --basic_auth=admin:secretpassword \
    --persistent=True \
    --db=/var/lib/flower/flower.db \
    --max_tasks=50000
```

Celery configuration must enable event sending for Flower to receive complete task lifecycle information.

```python
app.conf.update(
    worker_send_task_events=True,    # workers emit events
    task_send_sent_event=True,       # also emit event when task is enqueued
)
```

Programmatic monitoring uses `celery inspect` commands that communicate with workers via the broker control channel. These are useful for alerting pipelines and health checks.

```bash
# Check which workers are online
celery -A myapp inspect ping

# See currently executing tasks
celery -A myapp inspect active

# See aggregate stats (pool type, total executed, etc.)
celery -A myapp inspect stats

# Revoke a task (prevent it from running if still queued)
celery -A myapp control revoke <task-uuid>

# Revoke and terminate if already running
celery -A myapp control revoke <task-uuid> --terminate
```

Flower exposes a REST API that mirrors its UI capabilities. The API is useful for building custom dashboards or integrating task status into application UIs.

```python
import httpx

# Get all workers
response = httpx.get("http://localhost:5555/api/workers")
workers = response.json()

# Get tasks for a specific worker
response = httpx.get("http://localhost:5555/api/tasks?workername=celery@worker1")
tasks = response.json()

# Revoke a task via API
httpx.post(f"http://localhost:5555/api/task/revoke/{task_id}", json={"terminate": False})
```

---

## How It Connects

Flower monitors the workers defined in the workers note — understanding worker configuration helps interpret what Flower reports.

[[celery-workers|Celery Workers and Concurrency]]

The task state machine described in the Celery tasks note is what Flower visualizes — PENDING, STARTED, SUCCESS, FAILURE, RETRY states appear in the Flower task list.

[[celery-tasks|Celery Tasks]]

---

## Common Misconceptions

Misconception 1: "Flower can recover and display tasks that completed before it was started."
Reality: Flower subscribes to the live event stream from the broker. Events from before Flower connected are not replayed. To see historical task data from before the current session, you need a persistent result backend (Redis or database) and query it separately, or use `--persistent=True` and keep Flower running continuously.

Misconception 2: "Flower is safe to expose on a public network without authentication."
Reality: Flower has read access to task arguments (which may contain sensitive user data) and write access via the revocation API. Always protect it behind authentication. In production, the safest approach is to restrict it to a private network or VPN and use `--basic_auth` as a second layer.

---

## Why It Matters in Practice

Celery problems are invisible without monitoring. A queue that is slowly filling up (workers slower than producers) causes task delays that accumulate over hours before becoming obvious failures. A worker that is consuming tasks but producing constant failures registers in application logs but not in system health checks. Flower surfaces these signals immediately. Knowing how to read it and how to configure event sending properly is a prerequisite for operating Celery in production.

---

## Interview Angle

Common question forms:
- "How do you monitor Celery in production?"
- "What does Flower show you and how does it get that information?"

Answer frame:
Flower subscribes to Celery's internal event stream from the broker — it sees every task state transition in real time. It shows worker health, queue depths, task history with arguments and results, and error rates. Configuration requires `worker_send_task_events=True` in the Celery app. For production: protect with `--basic_auth`, use `--persistent=True` to survive restarts, restrict network access. Programmatic alternatives: `celery inspect ping` and `celery inspect stats` for health checks in alerting pipelines.

---

## Related Notes

- [[celery|Celery]]
- [[celery-tasks|Celery Tasks]]
- [[celery-workers|Celery Workers and Concurrency]]
- [[celery-beat|Celery Beat]]
