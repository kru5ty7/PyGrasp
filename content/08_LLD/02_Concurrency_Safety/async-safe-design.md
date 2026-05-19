---
title: 05 - Designing for Async Safety
description: Async-safe design ensures that coroutines sharing state do not corrupt it when control yields at await points, applying concurrency principles to Python's single-threaded asyncio model.
tags: [concurrency, asyncio, async-safety, coroutines, layer-7, lld]
status: draft
difficulty: advanced
layer: 7
domain: lld
created: 2026-05-18
---

# Designing for Async Safety

> Async safety ensures that shared state remains consistent when coroutines yield control at `await` points, using asyncio locks, atomic operations, and careful state management.

---

## Quick Reference

**Core idea:**
- Asyncio is single-threaded but still has concurrency: coroutines yield control at every `await`, letting other coroutines run
- A race condition occurs when a coroutine reads shared state, `await`s, and then writes - another coroutine may have changed the state in between
- `asyncio.Lock` serializes access to shared state across coroutines, similar to `threading.Lock` for threads
- Code between two `await` points runs atomically (no other coroutine can interleave), but you cannot always predict where `await` points are in library code
- Prefer immutable data, message passing (`asyncio.Queue`), and pure functions to minimize shared mutable state

**Tricky points:**
- `threading.Lock` must NOT be used in async code - it blocks the entire event loop
- `asyncio.Lock` is not reentrant - acquiring it twice in the same coroutine causes a deadlock
- Operations that look atomic (`dict[key] = value`) are safe in asyncio (no await points), but compound operations (check-then-act) are not
- Database transactions across `await` points are inherently unsafe without proper isolation levels

---

## What It Is

Think of a cooperative multitasking office. Each worker does their task at a shared desk, and when they need to wait for a printer (I/O), they step away and let someone else use the desk. The rule is: nobody interrupts you while you are actively working at the desk. But the moment you step away to wait for the printer, someone else sits down and might rearrange your papers. If you left a half-completed calculation on the desk, the next person might overwrite it.

Asyncio works the same way. Coroutines run on a single thread and yield control only at `await` points. Between two `await` expressions, your code runs without interruption. But at every `await`, the event loop can switch to another coroutine. If you read a shared variable, `await` something, and then modify the variable based on what you read, another coroutine might have changed it during your `await`. This is an async race condition.

The solutions mirror thread safety: use `asyncio.Lock` to serialize access, use `asyncio.Queue` for message passing, use immutable data that cannot be corrupted, and minimize the time between reading and writing shared state. The key difference is that `threading.Lock` blocks the OS thread (and thus the event loop), while `asyncio.Lock` suspends the coroutine and lets others run.

---

## How It Actually Works

An async race condition occurs in the check-then-act pattern: check a condition, `await` something, then act on the condition. The condition might have changed during the `await`. The fix is to hold an `asyncio.Lock` across the entire check-then-act sequence, ensuring no other coroutine can interleave.

```python
import asyncio


# ASYNC RACE CONDITION: check-then-act across an await
class UnsafeRateLimiter:
    def __init__(self, max_requests: int):
        self._max = max_requests
        self._count = 0

    async def allow(self) -> bool:
        if self._count < self._max:   # check
            await asyncio.sleep(0.01)  # simulates I/O - OTHER COROUTINES RUN HERE
            self._count += 1           # act - but count may have changed!
            return True
        return False


# ASYNC-SAFE: lock protects the check-then-act sequence
class SafeRateLimiter:
    def __init__(self, max_requests: int):
        self._max = max_requests
        self._count = 0
        self._lock = asyncio.Lock()  # NOT threading.Lock!

    async def allow(self) -> bool:
        async with self._lock:
            if self._count < self._max:
                await asyncio.sleep(0.01)  # safe: lock held
                self._count += 1
                return True
            return False


async def demo_race_condition():
    limiter = UnsafeRateLimiter(max_requests=5)

    async def make_request(request_id: int) -> str:
        if await limiter.allow():
            return f"Request {request_id}: allowed"
        return f"Request {request_id}: denied"

    # Launch 20 concurrent requests with limit of 5
    results = await asyncio.gather(
        *[make_request(i) for i in range(20)]
    )
    allowed = sum(1 for r in results if "allowed" in r)
    print(f"Unsafe: {allowed} allowed (expected max 5)")


async def demo_safe():
    limiter = SafeRateLimiter(max_requests=5)

    async def make_request(request_id: int) -> str:
        if await limiter.allow():
            return f"Request {request_id}: allowed"
        return f"Request {request_id}: denied"

    results = await asyncio.gather(
        *[make_request(i) for i in range(20)]
    )
    allowed = sum(1 for r in results if "allowed" in r)
    print(f"Safe: {allowed} allowed (expected max 5)")


asyncio.run(demo_race_condition())
asyncio.run(demo_safe())


# Async-safe shared cache with lock
class AsyncCache:
    def __init__(self):
        self._data: dict[str, str] = {}
        self._lock = asyncio.Lock()

    async def get_or_fetch(self, key: str) -> str:
        """Fetch from cache, or load and cache if missing."""
        # Check without lock (safe: dict access is atomic in asyncio)
        if key in self._data:
            return self._data[key]

        async with self._lock:
            # Double-check under lock (another coroutine may have populated it)
            if key in self._data:
                return self._data[key]

            # Fetch and cache
            value = await self._fetch_from_db(key)
            self._data[key] = value
            return value

    async def _fetch_from_db(self, key: str) -> str:
        await asyncio.sleep(0.1)  # simulate DB query
        return f"value_for_{key}"


# Async-safe with message passing (no shared state)
async def pipeline_example():
    queue: asyncio.Queue[str | None] = asyncio.Queue(maxsize=10)

    async def producer():
        for i in range(5):
            await queue.put(f"item-{i}")
            await asyncio.sleep(0.01)
        await queue.put(None)  # sentinel

    async def consumer():
        while True:
            item = await queue.get()
            if item is None:
                break
            print(f"Processing: {item}")

    await asyncio.gather(producer(), consumer())

asyncio.run(pipeline_example())
```

---

<iframe src="/static/visualizers/async-safe-design.html" width="100%" height="440px" style="border:none;border-radius:6px;"></iframe>

---

## How It Connects

Async safety applies concurrency principles from threading to asyncio's cooperative model. Understanding asyncio's event loop and coroutine scheduling is prerequisite.

[[asyncio-event-loop|Asyncio Event Loop]]

[[asyncio-locks|Asyncio Locks]]

[[race-conditions|Race Conditions]]

Thread safety basics (locks, atomicity, shared state) apply to async code with different mechanisms (`asyncio.Lock` instead of `threading.Lock`).

[[thread-safety-basics|Thread Safety Basics]]

Asyncio queues provide message passing for coroutines, the same way `queue.Queue` does for threads.

[[asyncio-queues|Asyncio Queues]]

---

## Common Misconceptions

Misconception 1: "Asyncio is single-threaded, so there cannot be race conditions."
Reality: Concurrency does not require parallelism. Every `await` is a potential context switch where another coroutine runs. If two coroutines share mutable state and either one reads-then-writes across an `await`, the read value might be stale when the write happens. This is the same logical race condition as in threading, just with cooperative instead of preemptive switching.

Misconception 2: "I can use `threading.Lock` in async code."
Reality: `threading.Lock.acquire()` blocks the OS thread, which in asyncio is the event loop thread. Blocking the event loop freezes all coroutines. Use `asyncio.Lock`, which suspends only the calling coroutine while others continue.

---

## Why It Matters in Practice

FastAPI, aiohttp, and other async frameworks handle hundreds of concurrent requests as coroutines. If those coroutines share any mutable state (caches, rate limiters, connection counts, session stores), that state must be async-safe. A race condition in a rate limiter can let thousands of requests through. A race condition in a cache can cause duplicate expensive computations.

---

## Interview Angle

Common question forms:
- "Can you have race conditions in asyncio?"
- "How is asyncio concurrency different from threading?"
- "What is the difference between asyncio.Lock and threading.Lock?"

Answer frame:
Explain that asyncio has concurrency at `await` points. Show the check-then-act race condition. Demonstrate `asyncio.Lock` as the fix. Emphasize never using `threading.Lock` in async code. Discuss the double-check pattern for caches.

---

## Related Notes

- [[asyncio-event-loop|Asyncio Event Loop]]
- [[asyncio-locks|Asyncio Locks]]
- [[race-conditions|Race Conditions]]
- [[thread-safety-basics|Thread Safety Basics]]
- [[asyncio-queues|Asyncio Queues]]
