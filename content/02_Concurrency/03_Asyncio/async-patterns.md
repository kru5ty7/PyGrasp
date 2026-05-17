---
title: 13 - Async Patterns
description: "Common async programming patterns: fan-out/fan-in with `gather`, producer-consumer with `asyncio.Queue`, circuit breaker with `asyncio.Semaphore`, retry with exponential backoff, and timeout composition with `asyncio.wait_for` — these patterns compose to handle real-world async workloads."
tags: [async-patterns, fan-out, producer-consumer, circuit-breaker, retry, timeout, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Async Patterns

> Common async programming patterns: fan-out/fan-in with `gather`, producer-consumer with `asyncio.Queue`, circuit breaker with `asyncio.Semaphore`, retry with exponential backoff, and timeout composition with `asyncio.wait_for` — these patterns compose to handle real-world async workloads.

---

## Quick Reference

**Core idea:**
- **Fan-out/fan-in**: `await asyncio.gather(*tasks)` — scatter work across concurrent tasks, collect results
- **Producer-consumer**: `asyncio.Queue` bridges producers and consumers; `await queue.join()` waits for all items
- **Rate limiting**: `asyncio.Semaphore(n)` caps concurrent operations at `n`
- **Timeout**: `await asyncio.wait_for(coro, timeout=5.0)` — raises `asyncio.TimeoutError` on timeout
- **Retry with backoff**: `while retries > 0: try: await op() except: await asyncio.sleep(backoff); retries -= 1`

**Tricky points:**
- `asyncio.wait_for` cancels the inner task on timeout — the task receives `CancelledError`; if the task catches `CancelledError` and continues, the timeout has no effect
- `asyncio.gather` with `return_exceptions=False` cancels all tasks if any raises — use `return_exceptions=True` to collect partial results and handle errors per-task
- In a producer-consumer setup, producers must signal completion (e.g., `None` sentinel, `queue.join()`) — without it, consumers loop forever
- `asyncio.TaskGroup` (Python 3.11+) cancels all sibling tasks if any raises — use it instead of `gather` when you want all-or-nothing semantics with better error visibility

---

## What It Is

Async patterns are reusable solutions to coordination problems that appear repeatedly in async programming. Just as design patterns exist for OOP, these async patterns are the vocabulary for writing correct and efficient async programs.

The problems they solve: how to distribute work across many concurrent tasks (fan-out), how to collect results without blocking (fan-in), how to prevent overwhelming downstream services (rate limiting), how to handle partial failures gracefully (return_exceptions), and how to avoid hanging indefinitely (timeouts).

---

## How It Actually Works

**Fan-out / fan-in:**
```python
async def process_batch(items):
    sem = asyncio.Semaphore(50)  # limit concurrency
    
    async def process_one(item):
        async with sem:
            return await api_call(item)
    
    results = await asyncio.gather(
        *[process_one(item) for item in items],
        return_exceptions=True,
    )
    errors = [r for r in results if isinstance(r, Exception)]
    successes = [r for r in results if not isinstance(r, Exception)]
    return successes, errors
```

**Producer-consumer pipeline:**
```python
async def pipeline(urls):
    fetch_queue = asyncio.Queue(maxsize=100)
    parse_queue = asyncio.Queue(maxsize=100)
    
    async def fetcher():
        async with aiohttp.ClientSession() as session:
            while True:
                url = await fetch_queue.get()
                if url is None:
                    await parse_queue.put(None)
                    fetch_queue.task_done()
                    return
                html = await session.get(url).text()
                await parse_queue.put(html)
                fetch_queue.task_done()
    
    async def parser():
        while True:
            html = await parse_queue.get()
            if html is None:
                parse_queue.task_done()
                return
            result = parse(html)
            store(result)
            parse_queue.task_done()
    
    for url in urls:
        await fetch_queue.put(url)
    await fetch_queue.put(None)
    
    await asyncio.gather(fetcher(), parser())
```

**Retry with exponential backoff:**
```python
async def with_retry(coro_factory, max_retries=3, base_delay=1.0):
    for attempt in range(max_retries):
        try:
            return await coro_factory()
        except (aiohttp.ClientError, asyncio.TimeoutError) as e:
            if attempt == max_retries - 1:
                raise
            delay = base_delay * (2 ** attempt)
            await asyncio.sleep(delay)

# Usage:
result = await with_retry(lambda: fetch(session, url))
```

**Timeout composition:**
```python
async def fetch_with_timeout(url, timeout=5.0):
    try:
        return await asyncio.wait_for(fetch(url), timeout=timeout)
    except asyncio.TimeoutError:
        return None

async def main(urls):
    results = await asyncio.gather(
        *[fetch_with_timeout(url) for url in urls]
    )
    return [r for r in results if r is not None]
```

---

## How It Connects

`asyncio.gather` and `asyncio.wait` are the primitives for fan-out/fan-in — understanding their cancellation semantics is required to use them correctly.
[[asyncio-gather|asyncio.gather and asyncio.wait]]

`asyncio.Queue` is the backbone of producer-consumer patterns in async programs.
[[asyncio-queues|Asyncio Queues]]

---

## Common Misconceptions

Misconception 1: "Async code automatically handles failures gracefully."
Reality: Unhandled exceptions in gathered tasks cancel siblings (with `return_exceptions=False`) or are silently swallowed (with `return_exceptions=True` if you don't check the results). Explicit error handling — `return_exceptions=True` + type checking on results — is necessary to handle partial failures without losing work.

Misconception 2: "More concurrent tasks always means faster throughput."
Reality: Unbounded concurrency overwhelms downstream services (rate limits, connection limits), causes `ConnectionRefusedError`, and can make overall throughput worse. `asyncio.Semaphore` for rate limiting and `asyncio.Queue(maxsize=n)` for backpressure are the standard tools for controlling concurrency.

---

## Why It Matters in Practice

A complete data pipeline combining all patterns:
```python
async def data_pipeline(source_urls, dest_db, max_concurrent=20, timeout=10.0):
    sem = asyncio.Semaphore(max_concurrent)
    
    async def fetch_and_store(url):
        async with sem:
            try:
                data = await asyncio.wait_for(fetch(url), timeout=timeout)
                await dest_db.insert(data)
                return url, "ok"
            except asyncio.TimeoutError:
                return url, "timeout"
            except Exception as e:
                return url, f"error: {e}"
    
    results = await asyncio.gather(
        *[fetch_and_store(url) for url in source_urls],
        return_exceptions=False,
    )
    
    summary = {"ok": 0, "timeout": 0, "error": 0}
    for _, status in results:
        key = "error" if status.startswith("error") else status
        summary[key] += 1
    return summary
```

This pattern — semaphore + wait_for + gather with return_exceptions + status tracking — is the standard structure for robust batch async operations in production.

---

## Interview Angle

Common question forms:
- "How would you implement a rate-limited async HTTP client?"
- "How do you handle partial failures in `asyncio.gather`?"

Answer frame: Rate limiting: `asyncio.Semaphore(n)` + `async with sem:` inside each task. Partial failures: `gather(*tasks, return_exceptions=True)` — check each result for `isinstance(result, Exception)`. Timeouts: `asyncio.wait_for(coro, timeout=n)` — catches `TimeoutError`. Retry: coroutine factory + loop with `await asyncio.sleep(backoff)`. For pipelines, `asyncio.Queue` with sentinels (None) to signal producer completion; `await queue.join()` to wait for all items to be processed.

---

## Related Notes

- [[asyncio-gather|asyncio.gather and asyncio.wait]]
- [[asyncio-queues|Asyncio Queues]]
- [[asyncio-locks|Asyncio Locks]]
- [[aiohttp|aiohttp]]
- [[asyncio-tasks|Asyncio Tasks]]
