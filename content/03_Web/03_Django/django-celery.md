---
title: 17 - Celery with Django
description: "Celery integrates with Django to offload time-consuming work to background worker processes via a message broker, decoupling task execution from the HTTP request cycle."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Celery with Django

> Celery is the answer to "I need to do something that takes more than a second in a web request"  -  by offloading work to background workers via a message broker, it keeps HTTP responses fast while ensuring expensive tasks still complete.

---

## Quick Reference

**Core idea:**
- `celery.py` in the project package: `app = Celery('myproject')`, `app.config_from_object('django.conf:settings', namespace='CELERY')`
- `@shared_task`: defines a task without importing the Celery app directly  -  works in any installed app
- `CELERY_BROKER_URL` (usually `redis://`) and `CELERY_RESULT_BACKEND` in settings
- `task.delay(arg1, arg2)` enqueues with positional args; `task.apply_async(args=[arg1], countdown=10)` allows options
- Workers started with `celery -A myproject worker --loglevel=info`
- Django ORM is fully available inside tasks, but tasks run in a separate process with their own database connections

**Tricky points:**
- Celery tasks receive serialized arguments  -  only JSON-serializable types by default; passing a model instance serializes its PK, not the object
- `task.delay()` is a shortcut for `task.apply_async()` with no options  -  both enqueue the task
- Tasks in `ATOMIC_REQUESTS = True` projects still run outside the request transaction  -  do not assume the database is updated before the task runs
- Worker processes hold open database connections; connection pool exhaustion is a production concern requiring `CONN_MAX_AGE = 0` or PgBouncer

---

## What It Is

Celery is a distributed task queue system that operates through a message broker. The mental model is a restaurant kitchen with a service window. When a customer (HTTP request) orders a complex dish (a slow operation: sending emails, resizing images, generating reports, calling third-party APIs), the waiter (the Django view) writes the order on a ticket and passes it through the service window (the message broker). The chef (a Celery worker) picks up the ticket, prepares the dish, and delivers it  -  but the waiter does not stand at the window waiting. The waiter immediately returns to the floor and takes new orders. The customer's response is instant ("Your order is in preparation") even though the dish takes minutes to prepare.

The integration with Django is configured in a `celery.py` file inside the project package. This file creates the `Celery` application instance, configures it to read settings from Django's settings module using the `CELERY_` namespace prefix, and calls `autodiscover_tasks()` to find all tasks defined in the `tasks.py` files of every installed app. The `CELERY_BROKER_URL` setting points Celery to a message broker  -  Redis is the most common choice for Django projects because Redis is already used for caching and sessions, reducing the number of infrastructure dependencies. The `CELERY_RESULT_BACKEND` setting points to where task results (return values and error details) are stored; this is also typically Redis, or it can be the Django database via `django-celery-results`.

`@shared_task` is the decorator used in app-level `tasks.py` files. Unlike `@app.task`, which requires importing the Celery application instance directly, `@shared_task` uses a proxy that resolves to the actual Celery app at runtime. This keeps each app self-contained  -  a `notifications` app defines its email tasks without importing the project-level `celery.py` module, which would create a dependency from an app to the project and prevent the app from being reusable across projects.

---

## How It Actually Works

When `send_welcome_email.delay(user_id=42)` is called in a Django view, Celery serializes the task name and arguments into a JSON message and publishes it to the Redis broker using the AMQP or Redis protocol. The view returns immediately. The broker holds the message in a queue. One of the running Celery worker processes picks up the message, imports the `send_welcome_email` function from the registered task module, deserializes the arguments, and calls the function. If the function completes successfully, the result is optionally stored in the result backend. If the function raises an exception, Celery catches it, stores the error in the result backend, and  -  depending on configuration  -  can retry the task automatically.

The database connection situation in tasks requires attention. Each Celery worker process opens its own connections to the database, separate from the Django HTTP server processes. With `CONN_MAX_AGE` set to a non-zero value in Django, connections are reused across requests. In long-running worker processes, a connection can become stale (if the database server closes it due to idle timeout), leading to `OperationalError: server closed the connection unexpectedly` errors. The standard fix is either `CONN_MAX_AGE = 0` (close and reopen connections for each task, which is safe but slightly less efficient) or using a connection pooler like PgBouncer. Inside tasks, you should also be aware that tasks run outside the HTTP request's database transaction  -  `ATOMIC_REQUESTS = True` wraps each HTTP request in a transaction, but it has no effect on task execution.

```python
# myproject/celery.py
import os
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'myproject.settings')

app = Celery('myproject')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()

# myproject/__init__.py
from .celery import app as celery_app
__all__ = ['celery_app']

# notifications/tasks.py
from celery import shared_task
from django.core.mail import send_mail

@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def send_welcome_email(self, user_id):
    from django.contrib.auth import get_user_model
    User = get_user_model()
    try:
        user = User.objects.get(pk=user_id)
        send_mail(
            subject='Welcome!',
            message=f'Hello {user.first_name}',
            from_email='noreply@example.com',
            recipient_list=[user.email],
        )
    except Exception as exc:
        raise self.retry(exc=exc)

# settings.py
CELERY_BROKER_URL = 'redis://localhost:6379/0'
CELERY_RESULT_BACKEND = 'redis://localhost:6379/0'
CELERY_TASK_SERIALIZER = 'json'
CELERY_ACCEPT_CONTENT = ['json']
```

---

## How It Connects

Celery tasks are commonly triggered from signal receivers  -  using `transaction.on_commit()` ensures the task is only enqueued after the triggering database transaction commits.

[[django-signals|Django Signals]]

Redis is the standard broker and result backend for Celery in Django projects  -  understanding Redis key expiry and memory management helps diagnose result backend behavior.

[[redis-python|Redis with Python]] *(MISSING_NOTE)*

Celery is one integration where the async/sync boundary matters: Celery workers are synchronous Python processes unless you use the `gevent` or `eventlet` pool, not to be confused with Python's native `asyncio`.

[[async-await|Async/Await]]

---

## Common Misconceptions

Misconception 1: "task.delay() returns the task result."
Reality: `task.delay()` returns an `AsyncResult` object immediately, before the task has run. The `AsyncResult` has a `result` attribute and a `state` attribute, but accessing `result` before the task completes either blocks (if you call `.get()`) or returns `None`. Celery tasks are fire-and-forget by default; polling for results in a Django view with `.get()` blocks the HTTP worker and defeats the purpose of background processing.

Misconception 2: "I can pass a Django model instance as a task argument."
Reality: Celery serializes task arguments to JSON before sending them through the broker. Model instances are not JSON-serializable by default. Passing a model instance works with pickle serialization (a security risk) but not with JSON serialization (the recommended default). Always pass the primary key (`user_id=user.pk`) and re-fetch the object inside the task.

Misconception 3: "Celery workers have access to the same in-memory state as the Django web server."
Reality: Celery workers are separate processes, potentially on separate machines. They have no access to the web server's in-memory cache, module-level singletons, or any state that is not persisted to the database or shared storage. `LocMemCache` entries set in a view are invisible to workers. Cross-process communication must go through the broker, database, Redis, or similar persistent medium.

---

## Why It Matters in Practice

Background task processing is a requirement for almost every production web application. Email sending, PDF generation, image resizing, report generation, payment processing callbacks, data synchronization, and external API calls all have response time characteristics that are incompatible with an HTTP response that should complete in under 200 milliseconds. Celery is the standard tool for this in the Django ecosystem, and its integration with Django is well-established and mature.

The operational complexity of Celery is non-trivial: it requires a broker process (Redis or RabbitMQ), worker processes, a result backend, monitoring (Flower is the standard Celery monitoring dashboard), and careful thought about retry logic and idempotency. But the alternative  -  doing slow work inside HTTP handlers  -  produces a worse user experience and a less robust system. The key discipline is designing tasks to be idempotent (safe to retry without side effects) and passing data by reference (primary keys, not objects) to keep messages small and serialization simple.

---

## Interview Angle

Common question forms:
- "How do you integrate Celery with a Django project?"
- "What is the difference between task.delay() and task.apply_async()?"
- "Why should you pass a model's pk to a task rather than the model instance itself?"

Answer frame:
A strong answer describes the `celery.py` setup file, `@shared_task` for app-level tasks, and `CELERY_BROKER_URL` as the minimal configuration. It explains `delay()` as a shortcut for `apply_async()` with no options, and `apply_async()` as the full interface for `countdown`, `eta`, `queue`, and other scheduling options. For argument passing, it explains that Celery serializes arguments to JSON by default, making model instances non-serializable, and that passing primary keys with re-fetching inside the task is the correct pattern for both serialization and data freshness.

---

## Related Notes

- [[django-signals|Django Signals]]
- [[django-views|Django Views]]
- [[django-testing|Testing Django Apps]]
- [[redis-python|Redis with Python]] *(MISSING_NOTE)*
- [[celery|Celery]] *(MISSING_NOTE)*
- [[async-await|Async/Await]]
