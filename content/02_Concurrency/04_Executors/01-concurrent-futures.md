---
title: 01 - concurrent.futures
description: "`concurrent.futures` provides `ThreadPoolExecutor` and `ProcessPoolExecutor` — a unified high-level interface for running callables in thread or process pools; futures represent pending results; `as_completed()` and `wait()` allow flexible result collection."
tags: [concurrent-futures, ThreadPoolExecutor, ProcessPoolExecutor, Future, as_completed, wait, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# concurrent.futures

> `concurrent.futures` provides `ThreadPoolExecutor` and `ProcessPoolExecutor` — a unified high-level interface for running callables in thread or process pools; futures represent pending results; `as_completed()` and `wait()` allow flexible result collection.

---

## Quick Reference

**Core idea:**
- `executor.submit(fn, *args)` — schedule `fn(*args)` for execution; returns a `Future` immediately
- `future.result()` — blocks until the future is done; returns the result or raises the exception
- `future.done()`, `future.running()`, `future.cancelled()` — non-blocking state queries
- `executor.map(fn, items)` — like `map()`, returns an iterator of results in input order
- `concurrent.futures.as_completed(futures)` — yields futures as they complete (any order)
- `concurrent.futures.wait(futures, return_when=...)` — blocks until condition is met

**Tricky points:**
- `executor.map()` raises the exception immediately when iterating past the failed item — unlike `submit()` where `future.result()` raises when accessed
- `ThreadPoolExecutor` default workers (Python 3.8+): `min(32, os.cpu_count() + 4)` — tuned for I/O-bound workloads
- `ProcessPoolExecutor` default workers: `os.cpu_count()`
- Futures from different executors can be mixed in `as_completed()` and `wait()`
- `executor.shutdown(wait=True)` blocks until all submitted futures complete; the `with executor:` context manager calls `shutdown(wait=True)` automatically
- `future.cancel()` can cancel a task that has not yet started; returns `False` if the task is already running or done

---

## What It Is

Think of `concurrent.futures` as a universal remote control. You can press the "run task" button without caring whether it dispatches a thread or a process — the remote looks the same either way. The `Future` object is a ticket that says "your result is being prepared; come back and check later." The same ticket works regardless of whether a thread or process is doing the work.

Before `concurrent.futures`, using threads required `threading.Thread` + manually collecting results via shared state or a `queue.Queue`. Using processes required `multiprocessing.Pool` with a different API. `concurrent.futures` unifies these: swap `ThreadPoolExecutor` for `ProcessPoolExecutor` and your code works the same way (assuming picklable arguments).

The key abstraction is the `Future` — a handle to an asynchronous computation that may or may not be done yet. Futures decouple task submission from result collection: submit many tasks at once, then collect results as they complete.

---

## How It Actually Works

`ThreadPoolExecutor` maintains a thread pool and a task queue (`queue.SimpleQueue`). `submit(fn, *args)` puts the task in the queue and returns a `Future`. Worker threads pick tasks from the queue, execute them, and set the future's result or exception.

`ProcessPoolExecutor` uses `multiprocessing.Process` workers or a `multiprocessing.Pool`. Tasks are pickled and sent to workers via IPC; results are pickled and returned.

`Future` state machine:
- `PENDING`: submitted, not yet running
- `RUNNING`: being executed
- `CANCELLED`: cancelled before running
- `CANCELLED_AND_NOTIFIED`: cancellation complete
- `FINISHED`: done (with result or exception)

`as_completed(futures)` usage:
```python
futures = {executor.submit(fetch, url): url for url in urls}
for future in concurrent.futures.as_completed(futures):
    url = futures[future]
    try:
        result = future.result()
    except Exception as e:
        print(f"{url} failed: {e}")
    else:
        process(result)
```

`wait()` return when:
- `ALL_COMPLETED` — all futures done
- `FIRST_COMPLETED` — at least one done
- `FIRST_EXCEPTION` — at least one raised; returns immediately

Executor as context manager:
```python
with ThreadPoolExecutor(max_workers=10) as executor:
    futures = [executor.submit(task, item) for item in items]
# Block here until all futures complete (shutdown(wait=True))
results = [f.result() for f in futures]
```

---

## How It Connects

`ThreadPoolExecutor` is a high-level wrapper over `threading.Thread` with a pool lifecycle — lower-level thread management is in the threads notes.
[[threads|Threads in Python]]

`ProcessPoolExecutor` wraps `multiprocessing.Pool` — lower-level process pool control is in the process pool notes.
[[process-pool|Process Pool]]

---

## Common Misconceptions

Misconception 1: "`executor.map()` returns results in completion order."
Reality: `executor.map()` returns an iterator that yields results in the **original input order**, blocking on each item until it is available. `as_completed()` yields futures in completion order (whichever finishes first). Use `as_completed` when you want to process results as they become available regardless of input order.

Misconception 2: "Exceptions in futures are lost if you don't call `result()`."
Reality: If you never call `future.result()`, the exception is silently discarded when the future is garbage collected (the exception may also be logged with a `RuntimeWarning` in Python 3.9+). Always collect results — either via `future.result()`, `executor.map()` iteration, or `as_completed()`. In production, iterate all futures to ensure all exceptions are surfaced.

---

## Why It Matters in Practice

The `as_completed` pattern for concurrent I/O:

```python
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests

urls = [...]

with ThreadPoolExecutor(max_workers=20) as executor:
    futures = {executor.submit(requests.get, url): url for url in urls}
    for future in as_completed(futures):
        url = futures[future]
        response = future.result()
        save(url, response)
```

Twenty concurrent HTTP requests, results processed as they arrive — a clean pattern that scales.

Switching from threads to processes requires only changing `ThreadPoolExecutor` to `ProcessPoolExecutor` (and ensuring callables and arguments are picklable). This portability is the primary value of `concurrent.futures` over raw `threading`/`multiprocessing`.

---

## Interview Angle

Common question forms:
- "What is `concurrent.futures`?"
- "What is the difference between `map()` and `as_completed()`?"

Answer frame: `concurrent.futures` provides `ThreadPoolExecutor` and `ProcessPoolExecutor` with a unified `Future`-based API. `submit(fn, *args)` returns a `Future` immediately. `executor.map(fn, items)` blocks and yields results in input order. `as_completed(futures)` yields futures in completion order (first done, first yielded). Use `as_completed` for "process as ready" patterns. `ProcessPoolExecutor` vs `ThreadPoolExecutor`: swap to switch between thread and process pools — same API, different execution model (same GIL constraint difference applies).

---

## Related Notes

- [[thread-pool-executor|ThreadPoolExecutor]]
- [[process-pool|Process Pool]]
- [[asyncio-tasks|Asyncio Tasks]]
