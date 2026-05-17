---
title: 06 - Semaphores
description: "A semaphore is a counter-based synchronization primitive — `Semaphore(n)` allows up to `n` threads in a section simultaneously, making it suitable for rate limiting, connection pool management, and bounded concurrency; `BoundedSemaphore` prevents the counter from exceeding its initial value."
tags: [semaphores, threading, Semaphore, BoundedSemaphore, concurrency-control, rate-limiting, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Semaphores

> A semaphore is a counter-based synchronization primitive — `Semaphore(n)` allows up to `n` threads in a section simultaneously, making it suitable for rate limiting, connection pool management, and bounded concurrency; `BoundedSemaphore` prevents the counter from exceeding its initial value.

---

## Quick Reference

**Core idea:**
- `sem = threading.Semaphore(n)` — internal counter starts at `n`; `acquire()` decrements (blocks at 0); `release()` increments
- `sem.acquire()` — if counter > 0, decrement and proceed; if counter == 0, block until another thread releases
- `sem.release()` — increment counter; wake one waiting thread if any
- `with sem:` — acquires on enter, releases on exit (same pattern as Lock)
- `threading.BoundedSemaphore(n)` — like `Semaphore` but `release()` raises `ValueError` if counter exceeds initial value

**Tricky points:**
- A `Semaphore(1)` is functionally equivalent to a `Lock` but allows the counter to exceed 1 if `release()` is called more times than `acquire()` — `BoundedSemaphore(1)` prevents this and is the correct choice for mutual exclusion
- `Semaphore` does not track ownership — any thread can call `release()`, not just the one that called `acquire()`; `Lock` requires the acquiring thread to release
- asyncio has `asyncio.Semaphore(n)` for coroutine-level rate limiting — does not block OS threads, only pauses coroutines at `await`
- Using a semaphore as a simple counter for signaling (starts at 0, producer `release()`s, consumer `acquire()`s) is a valid pattern
- Releasing a semaphore without acquiring it first (`BoundedSemaphore`) prevents "phantom permits" that could allow more concurrent access than intended

---

## What It Is

Think of a parking garage with a fixed number of spaces and a sign at the entrance showing the count of available spaces. A car can enter if the count is greater than zero (decrement count). When a car leaves, the count increases (increment). If the count is zero, new cars wait at the entrance until a space opens. A `Semaphore(10)` is a parking garage with 10 spaces — at most 10 threads can hold the "parking permit" simultaneously.

A `Lock` is a special case: a parking garage with one space. A semaphore generalizes this to any number of simultaneous holders. The practical use case is resource pool management: a semaphore guards access to a pool of `n` resources (database connections, network sockets, file handles) — at most `n` threads can have a resource from the pool at once.

---

## How It Actually Works

`threading.Semaphore` internally uses a `Lock` and a `Condition`:

```python
class Semaphore:
    def __init__(self, value=1):
        self._value = value
        self._cond = threading.Condition(threading.Lock())
    
    def acquire(self, blocking=True, timeout=None):
        with self._cond:
            while self._value == 0:
                if not blocking:
                    return False
                self._cond.wait(timeout)
            self._value -= 1
            return True
    
    def release(self, n=1):
        with self._cond:
            self._value += n
            for _ in range(n):
                self._cond.notify()
```

`BoundedSemaphore` adds a check in `release()`:
```python
def release(self):
    with self._cond:
        if self._value >= self._initial_value:
            raise ValueError("Semaphore released too many times")
        # ... increment and notify
```

A semaphore as a rate limiter:

```python
import threading
import requests

sem = threading.Semaphore(5)  # max 5 concurrent requests

def fetch(url):
    with sem:
        return requests.get(url)

threads = [threading.Thread(target=fetch, args=(url,)) for url in urls]
for t in threads: t.start()
for t in threads: t.join()
```

At most 5 threads hold the semaphore simultaneously — even if 50 threads are started, only 5 execute `requests.get()` concurrently.

---

## How It Connects

Semaphores are built on top of locks and condition variables — they are a higher-level synchronization primitive.
[[locks|Locks]]

asyncio provides `asyncio.Semaphore` for coroutine-level rate limiting — the same concept, implemented cooperatively rather than preemptively.
[[asyncio-locks|Asyncio Locks]]

---

## Common Misconceptions

Misconception 1: "`Semaphore(1)` is the same as `Lock`."
Reality: Functionally similar but not identical. `Lock` tracks the owning thread — only the acquiring thread can release it, and acquiring it twice (without RLock) deadlocks. `Semaphore(1)` allows any thread to `release()`, and `release()` without a prior `acquire()` increments the counter above 1 (unless `BoundedSemaphore`). Use `Lock` for mutual exclusion; use `BoundedSemaphore` when you need ownership semantics with a count.

Misconception 2: "Semaphores guarantee fairness — threads are served in FIFO order."
Reality: Python's `threading.Semaphore` does not guarantee FIFO ordering. When the semaphore is released, one of the waiting threads is notified — but which one depends on the OS scheduler. Under high contention, some threads may wait much longer than others (starvation). For FIFO behavior, use `queue.Queue` (which uses an internal semaphore with FIFO ordering).

---

## Why It Matters in Practice

Connection pool management: `Semaphore(max_connections)` limits the number of simultaneous database connections. Threads acquire before borrowing a connection and release when returning it — effectively implementing a connection pool without a dedicated pool library.

Download rate limiting: an API client that can make at most `n` simultaneous requests uses `Semaphore(n)` to enforce the limit across all worker threads — simpler than managing an explicit pool of request slots.

Asyncio rate limiting: `asyncio.Semaphore(n)` is the standard pattern for limiting concurrent outbound connections in async web scrapers and API clients.

---

## Interview Angle

Common question forms:
- "What is a semaphore and how does it differ from a lock?"
- "When would you use a semaphore instead of a lock?"

Answer frame: A semaphore has an internal counter; `acquire()` decrements (blocks at 0); `release()` increments. `Semaphore(n)` allows at most `n` threads in the section simultaneously. A lock is `Semaphore(1)` with ownership — only the acquiring thread can release. Use semaphores for: rate limiting (max N concurrent requests), connection pool management (max N connections). Use `BoundedSemaphore` to prevent accidental over-release. asyncio has its own `asyncio.Semaphore`.

---

## Related Notes

- [[locks|Locks]]
- [[deadlocks|Deadlocks]]
- [[thread-safe-queues|Thread-Safe Queues]]
- [[asyncio-locks|Asyncio Locks]]
