---
title: 14 - Running Sync Code in Async
description: "`asyncio.run_in_executor()` offloads blocking synchronous calls to a thread pool (or process pool) so they don't block the event loop; `loop.run_in_executor(None, func, *args)` uses the default `ThreadPoolExecutor`; blocking the event loop freezes all coroutines."
tags: [run-in-executor, ThreadPoolExecutor, blocking, asyncio, sync-in-async, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Running Sync Code in Async

> `asyncio.run_in_executor()` offloads blocking synchronous calls to a thread pool (or process pool) so they don't block the event loop; `loop.run_in_executor(None, func, *args)` uses the default `ThreadPoolExecutor`; blocking the event loop freezes all coroutines.

---

## Quick Reference

**Core idea:**
- `await loop.run_in_executor(None, blocking_func, arg1, arg2)` — runs `blocking_func(arg1, arg2)` in a thread pool; `None` uses the default `ThreadPoolExecutor`
- `asyncio.get_event_loop().run_in_executor(executor, func, *args)` — explicit loop; prefer `asyncio.get_running_loop()` inside async context
- `loop.run_in_executor(ProcessPoolExecutor(), cpu_bound_func, data)` — use `ProcessPoolExecutor` for CPU-bound work to bypass the GIL
- `asyncio.to_thread(func, *args, **kwargs)` (Python 3.9+) — convenience wrapper; equivalent to `run_in_executor(None, func)`

**Tricky points:**
- Blocking the event loop (any call that doesn't `await`) freezes ALL other coroutines — a single `time.sleep(1)` stalls the entire program
- `run_in_executor` with `ThreadPoolExecutor` still holds the GIL between bytecodes — only useful for I/O-bound blocking calls (file I/O, `requests.get`); use `ProcessPoolExecutor` for CPU-bound
- Functions run in executors run in a separate thread — they must be thread-safe; they cannot safely access asyncio primitives (`asyncio.Queue`, `asyncio.Lock`) directly
- `asyncio.to_thread` does NOT work for coroutines — only for regular synchronous callables
- Default `ThreadPoolExecutor` size: `min(32, os.cpu_count() + 4)` — may need to increase for I/O-heavy workloads

---

## What It Is

Think of the event loop as a single-lane road — only one car (coroutine) moves at a time, and each car must cooperate by pulling over (`await`) to let others pass. A blocking call is a car that refuses to pull over, stalling all traffic behind it. `run_in_executor` is like diverting the blocking car onto a side road (thread pool) — the main road stays clear while the blocking work happens elsewhere, and the result merges back when ready.

Any synchronous blocking call in a coroutine — `time.sleep()`, `requests.get()`, `open().read()` on a slow disk, a CPU-heavy computation — blocks the event loop. No other coroutine can run until the blocking call returns. `run_in_executor` moves the call off the event loop thread.

---

## How It Actually Works

Detecting if you're blocking the event loop (use `asyncio.set_event_loop_policy` with a debug policy):

```python
import asyncio, time

async def bad():
    time.sleep(2)  # blocks event loop for 2 seconds

async def good():
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(None, time.sleep, 2)  # offloads to thread pool
```

`asyncio.to_thread` (Python 3.9+):
```python
import asyncio
import requests  # synchronous HTTP library

async def fetch(url):
    response = await asyncio.to_thread(requests.get, url)
    return response.json()

async def main():
    results = await asyncio.gather(
        fetch("https://api.example.com/a"),
        fetch("https://api.example.com/b"),
    )
```

CPU-bound with `ProcessPoolExecutor`:
```python
from concurrent.futures import ProcessPoolExecutor
import asyncio

def cpu_heavy(n):
    return sum(i * i for i in range(n))

async def main():
    loop = asyncio.get_running_loop()
    with ProcessPoolExecutor() as pool:
        result = await loop.run_in_executor(pool, cpu_heavy, 10_000_000)
    print(result)
```

How `run_in_executor` works: submits the callable to the executor's `submit()` method, wraps the resulting `concurrent.futures.Future` in an `asyncio.Future`, and returns an awaitable. When the thread finishes, the asyncio future is resolved and the coroutine resumes.

---

## How It Connects

`run_in_executor` uses `ThreadPoolExecutor` and `ProcessPoolExecutor` from `concurrent.futures` — understanding the executor model is necessary to choose the right one.
[[concurrent-futures|concurrent.futures]]

The event loop's selector model is why blocking calls freeze all coroutines — the loop can only advance when the current execution returns control.
[[event-loop-internals|Event Loop Internals]]

---

## Common Misconceptions

Misconception 1: "`run_in_executor` with `ThreadPoolExecutor` is good for CPU-bound work."
Reality: `ThreadPoolExecutor` threads share the GIL. CPU-bound code holds the GIL continuously, so multiple threads cannot run Python code in parallel. For CPU-bound work, use `ProcessPoolExecutor` to get true parallelism. `ThreadPoolExecutor` only helps with I/O-bound blocking code that releases the GIL during the blocking call (like C extensions doing file I/O or socket operations).

Misconception 2: "You can use asyncio primitives from inside a `run_in_executor` callback."
Reality: Code running in an executor runs in a separate thread. Asyncio primitives (`asyncio.Queue`, `asyncio.Lock`, coroutines) are not thread-safe — calling `await queue.put(item)` from the thread raises `RuntimeError`. Use `asyncio.run_coroutine_threadsafe(coro, loop)` or `loop.call_soon_threadsafe(callback)` to schedule async operations from a thread.

---

## Why It Matters in Practice

Mixing a synchronous library (e.g., `psycopg2`, `boto3`, `requests`) into an async program:
```python
import asyncio
import boto3

s3 = boto3.client("s3")

async def download_file(bucket, key):
    loop = asyncio.get_running_loop()
    data = await loop.run_in_executor(
        None,
        lambda: s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    )
    return data

async def main():
    files = await asyncio.gather(
        download_file("bucket", "file1.json"),
        download_file("bucket", "file2.json"),
    )
```

The `boto3` SDK is synchronous only. Wrapping its calls in `run_in_executor` allows async code to treat them as non-blocking — multiple downloads proceed concurrently through thread pool.

---

## Interview Angle

Common question forms:
- "How do you call blocking code from an async function?"
- "What happens when you call `time.sleep()` in a coroutine?"

Answer frame: `time.sleep()` in a coroutine blocks the event loop — all coroutines freeze. The fix: `await asyncio.to_thread(time.sleep, n)` or `await loop.run_in_executor(None, time.sleep, n)` — this offloads the call to a thread pool so the event loop stays responsive. For CPU-bound work, use `ProcessPoolExecutor` instead of `ThreadPoolExecutor` to bypass the GIL. Code in the executor runs in a thread and cannot safely call asyncio primitives directly.

---

## Related Notes

- [[event-loop-internals|Event Loop Internals]]
- [[concurrent-futures|concurrent.futures]]
- [[asyncio-tasks|Asyncio Tasks]]
- [[asyncio|Asyncio]]
