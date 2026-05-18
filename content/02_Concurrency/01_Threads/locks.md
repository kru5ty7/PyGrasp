---
title: 04 - Locks
description: "A lock (mutex) ensures only one thread executes a critical section at a time  -  `threading.Lock` is the basic mutual exclusion primitive; `RLock` (reentrant lock) allows the same thread to acquire it multiple times; always use the `with` statement to guarantee release."
tags: [locks, mutex, threading, Lock, RLock, critical-section, synchronization, layer-2, concurrency]
status: draft
difficulty: beginner
layer: 2
domain: concurrency
created: 2026-05-17
---

# Locks

> A lock (mutex) ensures only one thread executes a critical section at a time  -  `threading.Lock` is the basic mutual exclusion primitive; `RLock` (reentrant lock) allows the same thread to acquire it multiple times; always use the `with` statement to guarantee release.

---

## Quick Reference

**Core idea:**
- `lock = threading.Lock()`  -  creates a lock; two states: unlocked (free) and locked (held by one thread)
- `lock.acquire()`  -  blocks until the lock is free, then acquires it
- `lock.release()`  -  releases the lock; raises `RuntimeError` if called by a thread that doesn't hold it
- `with lock:`  -  acquires on enter, releases on exit (even if an exception occurs); always prefer this over manual acquire/release
- `threading.RLock()`  -  reentrant lock; the same thread can `acquire()` it multiple times; must `release()` as many times as it `acquire()`d

**Tricky points:**
- `lock.acquire(blocking=False)`  -  non-blocking try; returns `True` if acquired, `False` if lock was already held
- `lock.acquire(timeout=5.0)`  -  waits up to 5 seconds; returns `False` on timeout
- A plain `Lock` raises `RuntimeError` if the holding thread calls `acquire()` again  -  it would deadlock; use `RLock` for recursive acquisition
- `threading.Condition(lock)`  -  built on top of a lock; adds `wait()`, `notify()`, `notify_all()` for producer-consumer signaling
- Over-locking (holding locks for too long, or using too many fine-grained locks) causes contention and reduces throughput; under-locking causes race conditions

---

## What It Is

Think of a single-occupancy restroom with a key. Anyone who wants to use it must take the key from the hook (acquire the lock). While using it, the key is unavailable  -  others must wait. When done, they return the key (release), and the next waiting person can take it. This guarantees exclusive access: at most one person uses the restroom at any time.

In Python, the "restroom" is a critical section  -  code that accesses shared mutable state. Without a lock, multiple threads enter the critical section simultaneously, potentially corrupting the shared state. The lock forces mutual exclusion: acquire before entering, release after leaving, blocking all others in between.

The `with lock:` pattern is the safe way to use locks. It guarantees that `release()` is called even if the body raises an exception  -  equivalent to `try: lock.acquire(); ... finally: lock.release()`. Forgetting to release a lock after an exception is a common cause of deadlocks.

---

## How It Actually Works

`threading.Lock` is implemented in CPython as a wrapper around a platform mutex. On Linux: `pthread_mutex_t` with `PTHREAD_MUTEX_DEFAULT` (not recursive). On Windows: an Event object.

`lock.acquire()` calls `pthread_mutex_lock()`. If the mutex is held, the calling thread is suspended by the OS and added to the mutex's wait queue. When the mutex is released, the OS wakes one waiting thread.

`with lock:` desugars to:
```python
lock.__enter__()  # calls lock.acquire()
try:
    body
finally:
    lock.__exit__(...)  # calls lock.release()
```

`RLock` tracks the owning thread and acquisition count. `acquire()` in the owning thread increments the count without blocking; `release()` decrements it; when the count reaches 0, the lock is actually released. Non-owning threads block until the count is 0.

`threading.Condition` implements the monitor pattern:
```python
cond = threading.Condition()
# Producer:
with cond:
    queue.append(item)
    cond.notify()

# Consumer:
with cond:
    while not queue:
        cond.wait()  # releases lock and waits for notify
    item = queue.popleft()
```

`cond.wait()` releases the underlying lock and blocks until notified. On wakeup, it reacquires the lock before returning. The `while not queue:` loop is required because `wait()` may return spuriously.

---

## How It Connects

Locks are the solution to race conditions  -  they make critical sections atomic by preventing concurrent access.
[[race-conditions|Race Conditions]]

Deadlocks arise when two threads each hold a lock the other needs  -  proper lock ordering prevents them.
[[deadlocks|Deadlocks]]

---

## Common Misconceptions

Misconception 1: "Acquiring a lock guarantees the operation inside it is atomic from the OS perspective."
Reality: The OS can still context-switch a thread while it holds a lock  -  the lock prevents other threads from entering the same critical section, but the OS continues to schedule the lock-holding thread. Context switches during critical sections are fine from a correctness standpoint  -  the lock ensures only one thread is in the section at any time.

Misconception 2: "Using a single global lock for all shared state makes the code thread-safe and simple."
Reality: A global lock (like the GIL in CPython) makes everything thread-safe but serializes all access  -  no concurrent execution of any code that touches shared state. Fine-grained locks (one per data structure) allow concurrent access to different structures but require careful ordering to avoid deadlocks.

---

## Why It Matters in Practice

The standard pattern for thread-safe shared state:

```python
import threading

class Counter:
    def __init__(self):
        self._value = 0
        self._lock = threading.Lock()
    
    def increment(self):
        with self._lock:
            self._value += 1
    
    @property
    def value(self):
        with self._lock:
            return self._value
```

`threading.Event` is a simpler primitive for one-shot signaling  -  `event.set()` signals, `event.wait()` blocks until set. Used for "task started" or "shutdown requested" flags.

Lock contention profiling: if threads spend significant time waiting for locks, the critical section is too broad. Split it into finer-grained sections, use lock-free data structures (`queue.Queue`), or restructure to reduce sharing.

---

## Interview Angle

Common question forms:
- "What is a mutex/lock?"
- "What is the difference between `Lock` and `RLock`?"

Answer frame: A lock ensures only one thread executes the critical section at a time. `Lock` is a simple mutex  -  the holding thread cannot acquire it again without deadlocking. `RLock` is reentrant  -  the same thread can acquire it multiple times; `release()` must be called the same number of times. Always use `with lock:` to guarantee release on exceptions. `Condition` adds wait/notify signaling on top of a lock for producer-consumer patterns.

---

## Related Notes

- [[race-conditions|Race Conditions]]
- [[deadlocks|Deadlocks]]
- [[semaphores|Semaphores]]
- [[threads|Threads in Python]]
