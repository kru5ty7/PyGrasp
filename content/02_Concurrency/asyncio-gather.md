---
title: asyncio.gather and asyncio.wait
description: "`asyncio.gather()` runs awaitables concurrently and returns results in input order; `asyncio.wait()` returns sets of done/pending futures without ordering; together they cover the main patterns for coordinating multiple concurrent tasks."
tags: [asyncio, gather, wait, concurrent-tasks, return_exceptions, FIRST_COMPLETED, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# asyncio.gather and asyncio.wait

> `asyncio.gather()` runs awaitables concurrently and returns results in input order; `asyncio.wait()` returns sets of done/pending futures without ordering; together they cover the main patterns for coordinating multiple concurrent tasks.

---

## Quick Reference

**Core idea:**
- `results = await asyncio.gather(coro1(), coro2(), coro3())` — runs all concurrently; returns `[result1, result2, result3]` in input order
- `asyncio.gather(*aws, return_exceptions=False)` — if `return_exceptions=True`, exceptions are returned as values instead of raised
- `done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)` — waits for the first task to complete; returns sets
- `return_when` options: `FIRST_COMPLETED`, `FIRST_EXCEPTION`, `ALL_COMPLETED`
- `asyncio.gather()` cancels all tasks if any raises (when `return_exceptions=False`); `asyncio.wait()` does not cancel

**Tricky points:**
- `gather()` with coroutines (not tasks): coroutines are automatically wrapped in tasks; the resulting tasks are cancelled if any raises (default `return_exceptions=False`)
- If you cancel the `gather()` itself, all gathered tasks are cancelled — cancellation propagates inward
- `asyncio.wait()` requires tasks (or futures), not raw coroutines (in Python 3.8+, passing coroutines raises a `DeprecationWarning` → use `asyncio.create_task()` first)
- Nested `gather()` calls: if an inner `gather()` has `return_exceptions=False` and raises, the outer `gather()` sees a `CancelledError` from the cancelled inner tasks
- `asyncio.as_completed(aws)` — yields coroutine objects that can be awaited; they complete as tasks finish; result order = completion order (fastest first)

---

## What It Is

Think of `asyncio.gather` as sending a batch of requests to multiple services simultaneously and waiting for all responses. A single API call that fetches a user's profile, orders, and recommendations from three separate services — you start all three requests at once and wait for all three to respond, rather than sequencing them.

`asyncio.wait` is more surgical — you start multiple tasks and specify when to stop waiting: on the first completion, on the first exception, or when all are done. It returns the tasks themselves (as sets of done and pending futures), giving you more control over what to do next.

The key difference: `gather` is higher-level (result ordering guaranteed, simpler API) while `wait` is lower-level (more flexible, returns task objects for further manipulation).

---

## How It Actually Works

`asyncio.gather(*aws)`:
1. Wraps each coroutine in a `Task` (those not already tasks)
2. Returns an aggregating future that collects all results
3. When all tasks complete, the aggregating future resolves with a list of results in input order
4. If any task raises (and `return_exceptions=False`), the aggregating future raises that exception and cancels all other tasks

```python
async def main():
    # Sequential (1 + 2 + 3 seconds = 6 seconds total):
    r1 = await fetch(url1)
    r2 = await fetch(url2)
    r3 = await fetch(url3)

    # Concurrent (max(1, 2, 3) = 3 seconds total):
    r1, r2, r3 = await asyncio.gather(fetch(url1), fetch(url2), fetch(url3))
```

`asyncio.wait(tasks, return_when=...)`:
```python
tasks = [asyncio.create_task(work(i)) for i in range(10)]

# Process results as they complete:
while tasks:
    done, tasks = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    for task in done:
        result = task.result()
        process(result)
```

`asyncio.as_completed`:
```python
for coro in asyncio.as_completed([fetch(url) for url in urls]):
    result = await coro  # awaits the next-completed task
    process(result)
```

`gather` with `return_exceptions=True`:
```python
results = await asyncio.gather(task1(), task2(), task3(), return_exceptions=True)
for result in results:
    if isinstance(result, Exception):
        handle_error(result)
    else:
        process(result)
```

---

## How It Connects

Both `gather` and `wait` operate on asyncio Tasks — understanding the Task lifecycle explains how cancellation propagates.
[[asyncio-tasks|Asyncio Tasks]]

`TaskGroup` (Python 3.11+) is the structured concurrency alternative to `gather` — cleaner error handling and automatic cancellation of sibling tasks.
[[asyncio|Asyncio]]

---

## Common Misconceptions

Misconception 1: "`asyncio.gather()` is always the right tool for concurrent tasks."
Reality: `gather()` works well when you need all results and want cancellation on first exception. For "process as ready" patterns, `as_completed` is better. For fine-grained control over which tasks continue after one fails, `wait` is better. For Python 3.11+, `TaskGroup` is often preferable to `gather` for structured concurrency.

Misconception 2: "`asyncio.wait()` cancels pending tasks when `return_when=FIRST_COMPLETED`."
Reality: `asyncio.wait()` does not cancel pending tasks — it just returns them in the `pending` set. You must explicitly cancel them if needed: `for task in pending: task.cancel(); await asyncio.gather(*pending, return_exceptions=True)`.

---

## Why It Matters in Practice

The most common use: parallel API calls or database queries in a web handler.

```python
@app.get("/dashboard")
async def dashboard():
    user, orders, recommendations = await asyncio.gather(
        get_user(user_id),
        get_orders(user_id),
        get_recommendations(user_id),
    )
    return build_response(user, orders, recommendations)
```

Without `gather`, these three queries run sequentially. With `gather`, they run in parallel — if each takes 100ms, sequential takes 300ms; parallel takes ~100ms.

Timeout handling:
```python
try:
    results = await asyncio.wait_for(
        asyncio.gather(*tasks),
        timeout=5.0
    )
except asyncio.TimeoutError:
    # gather was cancelled; all tasks were cancelled
    return fallback_response()
```

---

## Interview Angle

Common question forms:
- "What does `asyncio.gather()` do?"
- "What is the difference between `gather` and `wait`?"

Answer frame: `gather(*coros)` runs all coroutines concurrently and returns a list of results in input order. If any raises (with `return_exceptions=False`), it cancels all others and re-raises. `wait(tasks, return_when=...)` is lower-level — returns done/pending sets at the specified condition without cancelling. `as_completed` yields tasks in completion order (fastest first). For Python 3.11+, prefer `TaskGroup` for structured concurrency over `gather`.

---

## Related Notes

- [[asyncio-tasks|Asyncio Tasks]]
- [[asyncio|Asyncio]]
- [[async-await|Async and Await]]
