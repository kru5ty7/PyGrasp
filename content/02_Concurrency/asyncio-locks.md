---
title: Asyncio Locks
description: "`asyncio.Lock` and `asyncio.Semaphore` are coroutine-safe synchronization primitives — `async with lock:` yields to the event loop when blocked instead of blocking an OS thread; they are NOT thread-safe and must be used only within the same event loop."
tags: [asyncio, Lock, Semaphore, Event, Condition, async-with, synchronization, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Asyncio Locks

> `asyncio.Lock` and `asyncio.Semaphore` are coroutine-safe synchronization primitives — `async with lock:` yields to the event loop when blocked instead of blocking an OS thread; they are NOT thread-safe and must be used only within the same event loop.

---

## Quick Reference

**Core idea:**
- `lock = asyncio.Lock()` — mutual exclusion; `async with lock:` acquires on entry, releases on exit
- `await lock.acquire()` / `lock.release()` — manual acquire/release; prefer `async with`
- `asyncio.Semaphore(n)` — limits concurrency to `n` coroutines; `async with sem:`
- `asyncio.Event` — one-time signal; `await event.wait()` blocks until `event.set()` is called
- `asyncio.Condition` — like `threading.Condition`; `async with cond:` then `await cond.wait()` / `cond.notify()`

**Tricky points:**
- `asyncio.Lock` is NOT thread-safe — it uses futures internally; do not acquire/release from different OS threads; for cross-thread signaling use `loop.call_soon_threadsafe()`
- `asyncio.Lock` is NOT reentrant — a coroutine that tries to `acquire()` a lock it already holds will deadlock (there is no async RLock in the standard library)
- `lock.locked()` is a snapshot — another coroutine may acquire the lock between the check and your next `await`
- `asyncio.BoundedSemaphore` raises `ValueError` if released more times than acquired; prefer it over `Semaphore` to catch bugs
- Unlike `threading.Lock`, asyncio primitives do not have a `timeout` parameter on `acquire()` — wrap with `asyncio.wait_for()` for timeouts

---

## What It Is

Think of `asyncio.Lock` as a one-person bathroom at a restaurant. When the coroutine holding the lock is inside (working), all other coroutines that try to enter (`await lock.acquire()`) yield to the event loop — they wait in line without blocking any threads. When the coroutine exits (`lock.release()`), the next waiter is woken up.

The key difference from `threading.Lock`: a `threading.Lock.acquire()` that is blocked parks the OS thread — no other work can happen on that thread. `asyncio.Lock.acquire()` that is blocked creates a future and yields — the event loop continues running other coroutines. This is the distinction between parallelism (threads) and cooperative multitasking (asyncio).

---

## How It Actually Works

`asyncio.Lock` internals:

```python
class Lock:
    def __init__(self):
        self._locked = False
        self._waiters = collections.deque()  # futures waiting to acquire
    
    async def acquire(self):
        if not self._locked:
            self._locked = True
            return True
        fut = self._loop.create_future()
        self._waiters.append(fut)
        await fut  # yields; woken when previous holder releases
        self._locked = True
    
    def release(self):
        if self._waiters:
            fut = self._waiters.popleft()
            fut.set_result(True)  # schedules the waiter to resume
        else:
            self._locked = False
```

Limiting concurrent API calls with `asyncio.Semaphore`:

```python
async def fetch(session, url, sem):
    async with sem:
        async with session.get(url) as response:
            return await response.json()

async def main(urls):
    sem = asyncio.Semaphore(10)  # max 10 concurrent requests
    async with aiohttp.ClientSession() as session:
        tasks = [fetch(session, url, sem) for url in urls]
        return await asyncio.gather(*tasks)
```

`asyncio.Event` for one-time signaling:

```python
ready = asyncio.Event()

async def producer():
    await setup()
    ready.set()  # signal all waiters

async def consumer():
    await ready.wait()  # blocks until set() is called
    await do_work()
```

---

## How It Connects

`asyncio.Lock` is the async counterpart to `threading.Lock` — same mutual exclusion semantics, but yields to the event loop instead of blocking a thread.
[[locks|Locks and RLock]]

Async context managers (`async with`) are how asyncio primitives are consumed — `Lock`, `Semaphore`, and `Condition` all implement `__aenter__`/`__aexit__`.
[[async-context-managers|Async Context Managers]]

---

## Common Misconceptions

Misconception 1: "`asyncio.Lock` prevents data corruption like `threading.Lock`."
Reality: `asyncio.Lock` prevents re-entry between `await` points — a coroutine holding the lock will not be interrupted mid-execution (asyncio is cooperative, not preemptive). Data corruption in async code happens when a coroutine yields (via `await`) in the middle of a multi-step operation and another coroutine modifies shared state. The lock prevents this correctly. But unlike threading, non-awaiting code within a coroutine is never preempted, so short atomic operations don't need a lock.

Misconception 2: "`asyncio.Lock` can be used from multiple threads."
Reality: `asyncio.Lock` stores futures tied to a specific event loop. Calling `await lock.acquire()` from a thread that is not running that event loop will fail or corrupt the lock's state. For cross-thread synchronization, use `threading.Lock` or communicate via `loop.call_soon_threadsafe()`.

---

## Why It Matters in Practice

Rate limiting with semaphore:
```python
class RateLimiter:
    def __init__(self, rate):
        self._sem = asyncio.Semaphore(rate)
    
    async def __aenter__(self):
        await self._sem.acquire()
        asyncio.get_event_loop().call_later(1.0, self._sem.release)
    
    async def __aexit__(self, *args):
        pass  # release handled by timer

async def throttled_fetch(url):
    async with RateLimiter(10):  # max 10 per second
        return await fetch(url)
```

Cache with lock to prevent "thundering herd" (multiple coroutines computing the same value):
```python
_cache = {}
_lock = asyncio.Lock()

async def get_user(user_id):
    if user_id in _cache:
        return _cache[user_id]
    async with _lock:
        if user_id not in _cache:  # double-check after acquiring
            _cache[user_id] = await db.fetch_user(user_id)
    return _cache[user_id]
```

---

## Interview Angle

Common question forms:
- "How do you prevent race conditions in asyncio?"
- "What is `asyncio.Semaphore` used for?"

Answer frame: `asyncio.Lock` provides mutual exclusion — `async with lock:` ensures only one coroutine at a time runs the protected block. Race conditions in asyncio occur at `await` points; the lock prevents re-entry. `asyncio.Semaphore(n)` limits concurrency to `n` — used for rate-limiting. These primitives are NOT thread-safe (event-loop only). For timeouts, wrap `await lock.acquire()` in `asyncio.wait_for()`.

---

## Related Notes

- [[locks|Locks and RLock]]
- [[semaphores|Semaphores]]
- [[async-context-managers|Async Context Managers]]
- [[asyncio|Asyncio]]
