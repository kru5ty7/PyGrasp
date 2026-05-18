---
title: 14 - Background Tasks
description: "`fastapi.BackgroundTask` runs a function after the response is sent  -  injected via `BackgroundTasks` parameter; used for non-blocking post-response work (emails, notifications, cache invalidation); for long-running jobs, use Celery or asyncio Tasks instead."
tags: [fastapi, background-tasks, BackgroundTasks, post-response, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Background Tasks

> `fastapi.BackgroundTask` runs a function after the response is sent  -  injected via `BackgroundTasks` parameter; used for non-blocking post-response work (emails, notifications, cache invalidation); for long-running jobs, use Celery or asyncio Tasks instead.

---

## Quick Reference

**Core idea:**
- `background_tasks: BackgroundTasks`  -  FastAPI injects this automatically when declared as a parameter
- `background_tasks.add_task(func, *args, **kwargs)`  -  schedules `func` to run after the response is sent
- Both sync and async functions can be added as background tasks
- `BackgroundTasks` can also be injected into dependencies  -  dependency can add tasks without the handler knowing

**Tricky points:**
- Background tasks run in the same process/event loop as the request handler  -  they are NOT in a separate worker; a long-running task blocks other requests
- If the server restarts, pending background tasks are lost  -  there is no persistence or retry mechanism
- `BackgroundTasks` does NOT run tasks concurrently with the request  -  tasks run after the response is sent; the client receives the response before tasks complete
- Adding a sync blocking function as a background task runs it in a thread pool (FastAPI wraps sync background tasks in `run_in_executor`); adding an async function awaits it directly
- For actually long-running or reliable background work, use Celery, ARQ, or Dramatiq with a message broker

---

## What It Is

Background tasks solve the "send confirmation email after registration" problem: the user shouldn't wait for the email to send before receiving the 201 response. With `BackgroundTasks`, you return the response immediately and the email is sent after.

This is appropriate for fast, best-effort operations (sending a notification, invalidating a cache entry, logging to an external system). It is NOT appropriate for work that takes more than a few seconds, requires retry on failure, or must survive server restarts.

---

## How It Actually Works

Basic usage:
```python
from fastapi import BackgroundTasks, FastAPI

app = FastAPI()

def send_welcome_email(email: str):
    # Runs after response is sent
    email_client.send(to=email, template="welcome")

@app.post("/users", status_code=201)
async def create_user(user: UserCreate, background_tasks: BackgroundTasks):
    db_user = await create_user_in_db(user)
    background_tasks.add_task(send_welcome_email, user.email)
    return db_user  # response sent immediately; email sent after
```

Async background task:
```python
async def invalidate_cache(user_id: int):
    await redis.delete(f"user:{user_id}")

@app.patch("/users/{id}")
async def update_user(id: int, update: UserUpdate, background_tasks: BackgroundTasks):
    user = await db.update(id, update)
    background_tasks.add_task(invalidate_cache, id)
    return user
```

Background tasks in dependencies:
```python
def notify_analytics(action: str, user_id: int):
    analytics_client.track(action, user_id)

def get_current_user_with_tracking(
    token: str = Depends(oauth2_scheme),
    background_tasks: BackgroundTasks = None,
) -> User:
    user = validate_token(token)
    if background_tasks:
        background_tasks.add_task(notify_analytics, "login", user.id)
    return user
```

---

## How It Connects

Background tasks are a lightweight alternative to asyncio tasks for post-response work  -  for truly concurrent in-flight work, use `asyncio.create_task()` instead.
[[asyncio-tasks|Asyncio Tasks]]

For reliable, distributed background jobs (retry, scheduling, cross-process), Celery or similar task queues are the right tool.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "Background tasks run in parallel with the request."
Reality: Background tasks run sequentially after the response is sent. The client receives the response before any background tasks start. Multiple background tasks run one after the other (not concurrently).

Misconception 2: "Background tasks survive server restarts."
Reality: Background tasks are in-memory. If the server crashes or restarts while a task is pending, the task is lost. For critical operations that must complete (charging a card, updating a record), use a persistent task queue.

---

## Why It Matters in Practice

Good uses for `BackgroundTasks`:
- Sending welcome/notification emails after account creation
- Writing audit logs to a slow external system
- Cache invalidation after data updates
- Sending webhooks to third-party services

NOT good uses:
- Processing a video (takes minutes)
- Anything requiring retry on failure
- Tasks that must survive restarts
- Tasks that modify the same database record being returned

---

## Interview Angle

Common question forms:
- "How do you send an email after responding to a request in FastAPI?"
- "What are background tasks in FastAPI?"

Answer frame: `BackgroundTasks` parameter  -  `background_tasks.add_task(func, *args)` schedules a function to run after the response is sent. Best for fast, best-effort post-response work (emails, cache invalidation). NOT for long-running or critical work  -  use Celery/task queues for persistence and retry. Tasks run in the same process  -  a slow task blocks the event loop.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[asyncio-tasks|Asyncio Tasks]]
- [[fastapi-dependencies|FastAPI Dependencies]]
