---
title: Asyncio Tasks
description: An asyncio `Task` is a coroutine scheduled to run concurrently on the event loop — `asyncio.create_task(coro)` wraps a coroutine and immediately schedules it; tasks run concurrently but cooperate via `await`; cancellation and result access use the `Task` object.
tags: [asyncio, Task, create_task, gather, cancellation, TaskGroup, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Asyncio Tasks

> An asyncio `Task` is a coroutine scheduled to run concurrently on the event loop — `asyncio.create_task(coro)` wraps a coroutine and immediately schedules it; tasks run concurrently but cooperate via `await`; cancellation and result access use the `Task` object.

---

## Quick Reference

**Core idea:**
- `task = asyncio.create_task(coro())` — wraps the coroutine in a `Task` and schedules it for the next event loop iteration; does not await yet
- `result = await task` — suspends the current coroutine until `task` completes; retrieves the result or re-raises the exception
- `task.cancel()` — requests cancellation; injects `CancelledError` into the task at its next `await` point
- `task.done()`, `task.result()`, `task.exception()` — non-blocking state and result access
- `asyncio.TaskGroup` (Python 3.11+) — context manager for creating and managing a group of tasks with proper error propagation

**Tricky points:**
- Creating a task does NOT run it immediately — it is scheduled for the next event loop iteration; the current coroutine continues until it hits an `await`
- If the task is garbage collected before being awaited, a warning is issued — always await or handle all created tasks
- `task.cancel()` injects `CancelledError` — the task may catch and suppress it (considered bad practice unless re-raising); properly written tasks let `CancelledError` propagate
- Cancelling a task that is awaiting another task propagates the cancellation inward — the entire await chain is cancelled
- `asyncio.TaskGroup` (3.11+) cancels all sibling tasks if any task raises — preferable to `asyncio.gather(return_exceptions=True)` for strict error handling

---

## What It Is

Think of an asyncio task as a work order sent to the event loop's dispatch desk. When you create a task with `create_task(coro())`, you hand the work order to the desk — it is queued for execution. The desk does not do the work immediately; your current operation continues. Later, when your coroutine hits an `await` point and pauses, the event loop picks up work orders from the queue and begins executing them. Multiple work orders can be in progress simultaneously — each advances whenever its awaited I/O completes.

The difference between `await coro()` and `asyncio.create_task(coro())` then `await task`: the former is sequential (the coroutine runs to completion before the next line); the latter is concurrent (the task is scheduled to run while the creating coroutine also continues running until it awaits).

---

## How It Actually Works

`asyncio.create_task(coro())`:
1. Wraps `coro()` (a coroutine object) in a `Task` instance
2. Schedules the task's first step with `loop.call_soon(task.__step)`
3. Returns the `Task` object immediately — the coroutine has not run yet

`task.__step()`:
1. Called by the event loop's ready queue
2. Advances the coroutine to the next `await` point with `coro.send(None)`
3. If the coroutine yields a `Future`, registers `task.__step` as the future's callback
4. If the coroutine returns, sets `task._result`; if it raises, sets `task._exception`

`await task`:
1. If the task is not done, registers the current coroutine as a callback on the task's completion future
2. The current coroutine is suspended
3. When the task completes, the callback resumes the waiting coroutine

`TaskGroup` (Python 3.11+):
```python
async with asyncio.TaskGroup() as tg:
    task1 = tg.create_task(fetch(url1))
    task2 = tg.create_task(fetch(url2))
# All tasks complete when the `async with` block exits
# If any task raises, all others are cancelled
```

Pre-3.11 equivalent with `gather`:
```python
results = await asyncio.gather(fetch(url1), fetch(url2))
```

---

## How It Connects

Tasks are built on top of `asyncio.Future` — a lower-level awaitable that represents a pending value. Tasks are futures that run a coroutine.
[[asyncio|Asyncio]]

`asyncio.gather` and `asyncio.wait` are the standard tools for managing multiple tasks concurrently — they use tasks internally.
[[asyncio-gather|asyncio.gather and asyncio.wait]]

---

## Common Misconceptions

Misconception 1: "`create_task` starts the task immediately."
Reality: `create_task` schedules the task for the next event loop iteration. The current coroutine runs until it hits an `await` before the event loop has a chance to start the new task. If you `create_task()` and immediately `time.sleep(10)` (blocking), the task will not run for 10 seconds.

Misconception 2: "Cancelling a task stops it immediately."
Reality: `task.cancel()` sends a cancellation request — it injects `CancelledError` at the next `await` in the task. If the task has no more `await` points before completing, the cancellation may arrive after the task is already done. Also, a task can catch `CancelledError` and continue running (though this is considered bad practice unless the exception is re-raised).

---

## Why It Matters in Practice

The concurrent fetch pattern:
```python
async def fetch_all(urls):
    tasks = [asyncio.create_task(fetch(url)) for url in urls]
    results = []
    for task in tasks:
        results.append(await task)
    return results
```

All `fetch` coroutines are scheduled before any is awaited — they run concurrently. `asyncio.gather(*tasks)` is a cleaner one-liner for the same pattern.

Timeout with cancellation:
```python
try:
    result = await asyncio.wait_for(task, timeout=5.0)
except asyncio.TimeoutError:
    # task was cancelled
    handle_timeout()
```

`asyncio.wait_for` creates a task (if not already one), awaits it with a timeout, and cancels it on timeout.

---

## Interview Angle

Common question forms:
- "What is an asyncio Task?"
- "What is the difference between `await coro()` and `asyncio.create_task(coro())`?"

Answer frame: A Task wraps a coroutine and schedules it to run on the event loop. `create_task(coro())` schedules immediately but does not run yet — returns control to the current coroutine. `await coro()` is sequential; `create_task()` + `await task` allows concurrent execution. `task.cancel()` injects `CancelledError` at the next `await`. Use `TaskGroup` (3.11+) for structured concurrency; `gather` for the classic pattern.

---

## Related Notes

- [[asyncio|Asyncio]]
- [[asyncio-gather|asyncio.gather and asyncio.wait]]
- [[async-await|Async and Await]]
- [[event-loop|The Event Loop]]
