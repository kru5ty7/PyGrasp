---
title: 03 - Celery Beat
description: "Celery Beat is a scheduler process that enqueues Celery tasks on a cron or interval schedule, acting as the clock that triggers periodic work in a Celery deployment."
tags: [celery-beat, scheduler, crontab, periodic-tasks, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Celery Beat

> Celery Beat is the clock of the Celery system — it runs as a separate process, reads a schedule configuration, and enqueues tasks at the right times, just as a cron daemon fires shell scripts.

---

## Quick Reference

**Core idea:**
- Beat is a standalone process: `celery -A myapp beat --loglevel=info`
- `beat_schedule` in Celery config maps schedule names to task + schedule combinations
- `crontab(minute='*/15')` for interval-based; `crontab(hour=0, minute=0)` for daily midnight UTC
- Beat stores last-run state in `celerybeat-schedule` file (shelve format) by default
- Run exactly one Beat process — multiple instances cause duplicate task submissions

**Tricky points:**
- Beat enqueues tasks into the broker; workers execute them — Beat itself does no task execution
- If Beat is down, tasks for that period are not retroactively submitted when it restarts — they are simply missed
- `celerybeat-schedule` file must be writable by the Beat process; in containers, use a persistent volume or the database scheduler
- `crontab()` times are in UTC unless `timezone` is configured in the Celery app — mismatch between app timezone and host timezone causes subtle scheduling bugs
- `django-celery-beat` stores the schedule in the Django database and provides an admin UI for editing schedules without redeploying code

---

## What It Is

Every production system eventually needs work that runs on a schedule: clean up expired sessions at midnight, generate yesterday's analytics report at 1 AM, poll an external API every five minutes, send a weekly digest email every Monday at 9 AM. Linux systems have cron for this; Celery has Beat.

Celery Beat is a process that runs alongside your web application and workers. It maintains a schedule of tasks — each entry specifies a task function path and a schedule expression. At the appropriate moment, Beat creates a task message and sends it to the broker queue, exactly as an application handler would when a user triggers an action. A Celery worker picks up the message and executes the task. From the worker's perspective, there is no difference between a task triggered by Beat and one triggered by a web request.

The Beat process itself is deliberately simple. It reads the schedule at startup, tracks the last execution time for each scheduled task, computes when each task is next due, sleeps until the nearest due time, and then submits the task to the broker. This simplicity is also its constraint: Beat has no built-in web interface, no persistence in a shared database by default, and no distributed coordination. Running two Beat processes against the same schedule will produce duplicate task submissions — Beat does not use distributed locking to prevent this.

---

## How It Actually Works

The schedule lives in the Celery application configuration. Each entry is a dict with `task`, `schedule`, and optionally `args`, `kwargs`, and `options` keys.

```python
from celery.schedules import crontab
from datetime import timedelta

app.conf.beat_schedule = {
    # Run every 15 minutes
    "cleanup-expired-tokens": {
        "task": "myapp.tasks.cleanup_expired_tokens",
        "schedule": timedelta(minutes=15),
    },
    # Run daily at midnight UTC
    "generate-daily-report": {
        "task": "myapp.tasks.generate_daily_report",
        "schedule": crontab(hour=0, minute=0),
    },
    # Run every weekday at 9 AM UTC
    "send-morning-digest": {
        "task": "myapp.tasks.send_morning_digest",
        "schedule": crontab(hour=9, minute=0, day_of_week="mon-fri"),
    },
    # Pass arguments to the task
    "sync-partner-feed": {
        "task": "myapp.tasks.sync_feed",
        "schedule": crontab(minute="*/30"),
        "args": ("partner_a",),
        "kwargs": {"priority": "high"},
    },
}
```

`crontab()` accepts the same fields as standard cron: `minute`, `hour`, `day_of_month`, `month_of_year`, `day_of_week`. Each field accepts integers, ranges (`'1-5'`), step values (`'*/10'`), comma-separated lists (`'1,3,5'`), or `'*'` for any.

In production deployments using Django, `django-celery-beat` replaces the file-based schedule with a database-backed one. Schedules can be created and modified through the Django admin interface without restarting the Beat process.

```python
# Celery config to use Django database scheduler
app.conf.beat_scheduler = "django_celery_beat.schedulers:DatabaseScheduler"
```

Beat is started as a separate process, distinct from workers. In Docker Compose or Kubernetes deployments, it runs as its own service, often alongside a `--scheduler` argument when using the database backend.

```bash
# Basic startup
celery -A myapp beat --loglevel=info

# With database scheduler (django-celery-beat)
celery -A myapp beat --scheduler django_celery_beat.schedulers:DatabaseScheduler --loglevel=info
```

---

## How It Connects

Beat enqueues tasks that workers consume — the task definitions it references are the same functions described in the tasks note.

[[celery-tasks|Celery Tasks]]

Workers are the processes that actually execute the tasks Beat enqueues — Beat and workers are separate processes but part of the same deployment.

[[celery-workers|Celery Workers and Concurrency]]

---

## Common Misconceptions

Misconception 1: "Running two Beat processes provides high availability — if one crashes, the other takes over."
Reality: Two Beat processes both read the same schedule independently and both submit tasks at the same time. There is no leader election or coordination. The result is duplicate task submissions — every scheduled task runs twice. High availability for Beat requires a distributed lock or a solution like `redbeat` (uses Redis for distributed locking) or `django-celery-beat` (workers with a single database-backed scheduler).

Misconception 2: "If Beat misses a scheduled run (because it was down), it will catch up and run the missed tasks when it restarts."
Reality: Beat tracks the last-run time for each task and submits only the next due occurrence after restart. Missed runs during downtime are permanently lost. If catching up on missed runs is a requirement, the task logic itself must handle the backfill.

---

## Why It Matters in Practice

Beat is the component of Celery deployments that most often causes silent production problems: duplicate runs from two Beat instances, missed runs from improper container restart policies, or timezone mismatch causing tasks to run at the wrong local time. Knowing that Beat must run as exactly one instance and that its schedule times are UTC by default prevents two common incident types.

---

## Interview Angle

Common question forms:
- "How do you schedule a periodic task in Celery?"
- "Why should you run only one Celery Beat process?"

Answer frame:
Celery Beat reads `beat_schedule` config, computes task due times, and enqueues task messages to the broker on schedule. Workers execute the tasks. Beat must run as exactly one process — two instances submit duplicate messages because there is no coordination. For production, `django-celery-beat` stores the schedule in the database and supports live edits without restart.

---

## Related Notes

- [[celery|Celery]]
- [[celery-tasks|Celery Tasks]]
- [[celery-workers|Celery Workers and Concurrency]]
- [[celery-monitoring|Monitoring Celery with Flower]]
