---
title: 06 - Concurrent Data Structures
description: Concurrent data structures are designed for safe access by multiple threads or coroutines without external locking, providing thread-safe alternatives to standard Python collections.
tags: [concurrency, data-structures, thread-safety, queue, layer-7, lld]
status: draft
difficulty: advanced
layer: 7
domain: lld
created: 2026-05-18
---

# Concurrent Data Structures

> Concurrent data structures handle synchronization internally, letting multiple threads access and modify them safely without external locks.

---

## Quick Reference

**Core idea:**
- Standard Python collections (`list`, `dict`, `set`) are not thread-safe for compound operations
- `queue.Queue`, `queue.LifoQueue`, and `queue.PriorityQueue` are thread-safe with blocking get/put
- `collections.deque` has thread-safe `append()` and `popleft()` due to the GIL (for atomic operations only)
- `multiprocessing.Manager` provides shared data structures for multi-process programs
- For async code, use `asyncio.Queue` instead of `queue.Queue`

**Tricky points:**
- GIL-protected atomicity is an implementation detail of CPython - do not rely on it for correctness
- `dict[key] = value` is atomic in CPython, but "check if key exists, then set" is not atomic
- `queue.Queue` is thread-safe but slow for high-throughput scenarios due to lock overhead
- For multi-process sharing, use `multiprocessing.Queue` or shared memory (`multiprocessing.Value`, `multiprocessing.Array`)

---

## What It Is

Think of a vending machine. Multiple people can press buttons simultaneously, but the machine's internal mechanism ensures that each transaction completes properly - one person gets one item, the inventory decrements by one, and the money is counted correctly. The machine handles concurrency internally. You do not need to coordinate with other customers to avoid conflicts. The machine is a concurrent data structure.

Standard Python collections are like a cash register without a lock. A `list` does not prevent two threads from appending at the same time and getting a corrupted internal state. A `dict` does not prevent two threads from both checking that a key is missing and both inserting it. You need either external locks or data structures that handle synchronization internally.

Python provides several concurrent data structures. `queue.Queue` is the workhorse: thread-safe FIFO queue with blocking operations. `collections.deque` provides thread-safe append and pop at both ends (for atomic, single-method operations). `multiprocessing.Queue` works across processes. For async code, `asyncio.Queue` provides the same interface for coroutines. For thread-safe counters and accumulators, you wrap standard types with locks or use `threading.Lock` protected operations.

---

## How It Actually Works

Thread-safe data structures wrap standard operations with internal locks. `queue.Queue` uses a `threading.Lock` and two `threading.Condition` variables (one for "not empty" to wake consumers, one for "not full" to wake producers). Every `put()` and `get()` acquires the lock, ensuring atomic access.

For simpler needs, a `threading.Lock`-wrapped dict or a lock-free approach using atomic operations can be sufficient. Python 3.12+ provides `threading.Barrier` for synchronization points and improved GIL behavior.

```python
import queue
import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field


# 1. queue.Queue - thread-safe FIFO
def queue_demo():
    q: queue.Queue[int] = queue.Queue(maxsize=5)

    def producer():
        for i in range(10):
            q.put(i)  # blocks if full
            print(f"Produced: {i}")

    def consumer():
        for _ in range(10):
            item = q.get(timeout=2)  # blocks if empty
            print(f"Consumed: {item}")
            q.task_done()

    t1 = threading.Thread(target=producer)
    t2 = threading.Thread(target=consumer)
    t1.start(); t2.start()
    t1.join(); t2.join()

queue_demo()


# 2. Thread-safe dict wrapper
class ConcurrentDict:
    """Dict with internal locking for compound operations."""

    def __init__(self):
        self._data: dict = {}
        self._lock = threading.Lock()

    def get(self, key, default=None):
        with self._lock:
            return self._data.get(key, default)

    def set(self, key, value):
        with self._lock:
            self._data[key] = value

    def setdefault(self, key, default):
        """Atomic check-and-set."""
        with self._lock:
            if key not in self._data:
                self._data[key] = default
            return self._data[key]

    def pop(self, key, default=None):
        with self._lock:
            return self._data.pop(key, default)

    def update_if(self, key, condition, new_value):
        """Atomic compare-and-swap."""
        with self._lock:
            if key in self._data and condition(self._data[key]):
                self._data[key] = new_value
                return True
            return False

cache = ConcurrentDict()

def worker(thread_id: int):
    for i in range(100):
        key = f"key-{i % 10}"
        cache.setdefault(key, thread_id)  # atomic: first writer wins

with ThreadPoolExecutor(max_workers=4) as pool:
    futures = [pool.submit(worker, i) for i in range(4)]
    for f in futures:
        f.result()

print(f"Cache size: {len(cache._data)}")


# 3. Thread-safe counter
class AtomicCounter:
    def __init__(self, initial: int = 0):
        self._value = initial
        self._lock = threading.Lock()

    def increment(self, amount: int = 1) -> int:
        with self._lock:
            self._value += amount
            return self._value

    def decrement(self, amount: int = 1) -> int:
        with self._lock:
            self._value -= amount
            return self._value

    @property
    def value(self) -> int:
        return self._value  # atomic read in CPython

counter = AtomicCounter()

def count_work():
    for _ in range(10_000):
        counter.increment()

with ThreadPoolExecutor(max_workers=4) as pool:
    futures = [pool.submit(count_work) for _ in range(4)]
    for f in futures:
        f.result()

print(f"Counter: {counter.value}")  # Always 40,000


# 4. Bounded buffer with deque (thread-safe for atomic ops)
class BoundedBuffer:
    """Thread-safe bounded buffer using deque."""

    def __init__(self, maxsize: int):
        self._buffer: deque = deque(maxlen=maxsize)
        self._lock = threading.Lock()
        self._not_empty = threading.Condition(self._lock)
        self._not_full = threading.Condition(self._lock)

    def put(self, item):
        with self._not_full:
            while len(self._buffer) >= self._buffer.maxlen:
                self._not_full.wait()
            self._buffer.append(item)
            self._not_empty.notify()

    def get(self):
        with self._not_empty:
            while len(self._buffer) == 0:
                self._not_empty.wait()
            item = self._buffer.popleft()
            self._not_full.notify()
            return item


# 5. Priority queue for task scheduling
@dataclass(order=True)
class PrioritizedTask:
    priority: int
    task_id: str = field(compare=False)
    payload: str = field(compare=False)

pq: queue.PriorityQueue = queue.PriorityQueue()
pq.put(PrioritizedTask(3, "low", "background sync"))
pq.put(PrioritizedTask(1, "high", "user request"))
pq.put(PrioritizedTask(2, "med", "email notification"))

while not pq.empty():
    task = pq.get()
    print(f"Processing [{task.priority}] {task.task_id}: {task.payload}")
# Output: high, med, low (priority order)
```

---

## How It Connects

Concurrent data structures build on locks and conditions. Understanding these primitives helps you build custom concurrent structures.

[[locks|Locks]]

[[thread-safety-basics|Thread Safety Basics]]

`queue.Queue` is the key data structure for the Producer-Consumer pattern. Priority queues enable task scheduling with priorities.

[[producer-consumer-pattern|Producer Consumer Pattern]]

For multi-process programs, `multiprocessing.Queue` and shared memory provide cross-process concurrent data structures.

[[multiprocessing|Multiprocessing]]

---

## Common Misconceptions

Misconception 1: "Python dicts are thread-safe."
Reality: Individual dict operations (`d[k] = v`, `d.get(k)`) are atomic in CPython due to the GIL, but compound operations ("check if key exists, then insert") are not. Two threads can both check that a key is absent and both insert, with one overwriting the other. For compound operations, you need external locking.

Misconception 2: "`queue.Queue` is slow - I should use a `list` with a lock."
Reality: `queue.Queue` adds overhead per operation (~microseconds), but it handles blocking, signaling, and backpressure correctly. A `list` with a lock requires you to implement blocking and signaling yourself, which is error-prone. The performance difference rarely matters outside of extremely high-throughput scenarios (millions of operations per second).

---

## Why It Matters in Practice

Every Python web server, task queue, and background processing system uses concurrent data structures. Connection pools, request queues, metric counters, and rate limiters all require thread-safe operations. Using the right concurrent data structure avoids the complexity and bugs of manual lock management while providing the safety guarantees your application needs.

---

## Interview Angle

Common question forms:
- "What Python data structures are thread-safe?"
- "How would you implement a thread-safe cache?"
- "What is the difference between queue.Queue and collections.deque?"

Answer frame:
List thread-safe structures: `queue.Queue`, `queue.PriorityQueue`. Explain that dict/list are atomic for single operations but not compound ones. Show `ConcurrentDict` with internal locking for compound operations. Mention `asyncio.Queue` for async code. Discuss the tradeoff between `queue.Queue` (full safety) and `deque` (faster but limited safety).

---

## Related Notes

- [[locks|Locks]]
- [[thread-safety-basics|Thread Safety Basics]]
- [[producer-consumer-pattern|Producer Consumer Pattern]]
- [[multiprocessing|Multiprocessing]]
