---
title: 04 - Reader Writer Locks
description: Reader-Writer locks allow multiple threads to read shared data simultaneously while ensuring exclusive access for writes, optimizing throughput in read-heavy workloads.
tags: [concurrency, reader-writer, locks, threading, layer-7, lld]
status: draft
difficulty: advanced
layer: 7
domain: lld
created: 2026-05-18
---

# Reader Writer Locks

> Reader-Writer locks allow multiple concurrent readers but only one exclusive writer, optimizing performance when reads vastly outnumber writes.

---

## Quick Reference

**Core idea:**
- **Readers** can access shared data concurrently - multiple reads do not conflict
- **Writers** need exclusive access - no readers or other writers can proceed during a write
- Standard `threading.Lock` forces all access to be serialized, including read-read, which is unnecessarily restrictive
- Python's standard library does not include a `ReadWriteLock`, but it can be built from `Lock` and `Condition`
- Useful when reads are frequent and writes are rare (config caches, lookup tables, routing tables)

**Tricky points:**
- **Writer starvation**: if readers continuously hold the lock, writers may never get access
- **Reader starvation**: if writers have priority, readers may be blocked indefinitely
- The overhead of reader-writer locks is higher than a simple mutex - beneficial only when reads significantly outnumber writes
- Python's GIL limits true parallelism for CPU-bound reads; reader-writer locks are most beneficial for I/O-bound scenarios or protecting data structures that require consistency

---

## What It Is

Think of a museum exhibit. Many visitors can view the paintings at the same time - viewing does not change anything. But when the curator needs to replace a painting (a write), the room must be cleared and closed to visitors until the swap is complete. A simple lock that allows only one person in the room at a time would create long queues of visitors waiting to see the exhibit one at a time. A reader-writer approach lets visitors flow freely but pauses them only when the curator is making changes.

A regular mutex lock serializes all access: only one thread enters the critical section, whether reading or writing. This is safe but pessimistic. If 99% of access is reading, you are forcing threads to wait in line for an operation that could safely happen in parallel. A reader-writer lock distinguishes between read access (shared, concurrent) and write access (exclusive, one at a time).

Python's standard library does not provide a reader-writer lock, but one can be constructed from `threading.Lock` and `threading.Condition`. The implementation tracks the number of active readers. When a reader enters, it increments the count. When it exits, it decrements. A writer waits until the reader count is zero, then acquires exclusive access and blocks all new readers until it finishes.

---

## How It Actually Works

The reader-writer lock maintains a reader count and a writer flag. Readers increment the count on entry and decrement on exit. Writers wait for the count to reach zero, set the writer flag, and proceed exclusively. When the writer finishes, waiting readers and writers are notified.

```python
import threading
import time
import random
from contextlib import contextmanager


class ReadWriteLock:
    """Allows multiple concurrent readers, exclusive writers."""

    def __init__(self):
        self._lock = threading.Lock()
        self._readers_ok = threading.Condition(self._lock)
        self._writers_ok = threading.Condition(self._lock)
        self._active_readers = 0
        self._active_writers = 0
        self._waiting_writers = 0

    @contextmanager
    def read_lock(self):
        """Acquire a shared read lock."""
        with self._lock:
            # Wait if a writer is active or writers are waiting (prevents writer starvation)
            while self._active_writers > 0 or self._waiting_writers > 0:
                self._readers_ok.wait()
            self._active_readers += 1

        try:
            yield
        finally:
            with self._lock:
                self._active_readers -= 1
                if self._active_readers == 0:
                    self._writers_ok.notify()

    @contextmanager
    def write_lock(self):
        """Acquire an exclusive write lock."""
        with self._lock:
            self._waiting_writers += 1
            while self._active_readers > 0 or self._active_writers > 0:
                self._writers_ok.wait()
            self._waiting_writers -= 1
            self._active_writers += 1

        try:
            yield
        finally:
            with self._lock:
                self._active_writers -= 1
                # Wake all waiting readers and one waiting writer
                self._readers_ok.notify_all()
                self._writers_ok.notify()


# Thread-safe cache using reader-writer lock
class ConfigCache:
    """Read-heavy, write-rare cache with optimized locking."""

    def __init__(self):
        self._data: dict[str, str] = {}
        self._rwlock = ReadWriteLock()

    def get(self, key: str) -> str | None:
        """Multiple threads can read simultaneously."""
        with self._rwlock.read_lock():
            return self._data.get(key)

    def get_all(self) -> dict[str, str]:
        with self._rwlock.read_lock():
            return dict(self._data)

    def update(self, key: str, value: str) -> None:
        """Only one thread can write at a time."""
        with self._rwlock.write_lock():
            self._data[key] = value

    def bulk_update(self, updates: dict[str, str]) -> None:
        """Atomic bulk update."""
        with self._rwlock.write_lock():
            self._data.update(updates)


# Simulate read-heavy workload
cache = ConfigCache()
cache.bulk_update({
    "db_host": "postgres.prod",
    "db_port": "5432",
    "cache_ttl": "300",
    "debug": "false",
})

stats = {"reads": 0, "writes": 0}
stats_lock = threading.Lock()

def reader(reader_id: int, iterations: int) -> None:
    for _ in range(iterations):
        value = cache.get("db_host")
        with stats_lock:
            stats["reads"] += 1
        time.sleep(random.uniform(0.001, 0.005))

def writer(writer_id: int, iterations: int) -> None:
    for i in range(iterations):
        cache.update("cache_ttl", str(300 + i))
        with stats_lock:
            stats["writes"] += 1
        time.sleep(random.uniform(0.01, 0.05))

# 10 readers, 1 writer - typical read-heavy workload
threads = []
for i in range(10):
    t = threading.Thread(target=reader, args=(i, 50))
    threads.append(t)
t = threading.Thread(target=writer, args=(0, 5))
threads.append(t)

for t in threads:
    t.start()
for t in threads:
    t.join()

print(f"Reads: {stats['reads']}, Writes: {stats['writes']}")
print(f"Final cache_ttl: {cache.get('cache_ttl')}")
```

---

## How It Connects

Reader-Writer locks build on basic locking primitives. Understanding `threading.Lock`, `threading.Condition`, and context managers is prerequisite.

[[locks|Locks]]

[[thread-safety-basics|Thread Safety Basics]]

[[context-managers|Context Managers]]

For simple cases, an immutable shared object with atomic replacement (swap the entire reference) may be simpler than a reader-writer lock.

[[immutable-objects|Immutable Objects for Safety]]

---

## Common Misconceptions

Misconception 1: "Reader-Writer locks are always faster than regular locks."
Reality: The reader-writer lock has more overhead (reader count tracking, condition variable signaling). For short critical sections or workloads where reads and writes are roughly balanced, a simple `Lock` is faster. Reader-writer locks win only when reads significantly outnumber writes (10:1 or more).

Misconception 2: "Python's GIL makes reader-writer locks pointless."
Reality: The GIL prevents parallel CPU execution, but reader-writer locks protect data structure consistency across bytecode boundaries. A dictionary read can see a partially updated state if a writer is mid-modification across multiple bytecodes. The reader-writer lock ensures readers see a complete, consistent snapshot.

---

## Why It Matters in Practice

Caches, routing tables, configuration stores, and lookup tables are read thousands of times per second and updated rarely. Using a simple mutex serializes all reads, creating a bottleneck. A reader-writer lock lets reads proceed in parallel and only serializes writes, dramatically improving throughput in these scenarios.

---

## Interview Angle

Common question forms:
- "What is a reader-writer lock?"
- "When would you use it instead of a regular mutex?"
- "How do you prevent writer starvation?"

Answer frame:
Define reader-writer lock as shared reads, exclusive writes. Explain when it helps (read-heavy workloads). Discuss starvation (readers blocking writers or vice versa). Implement using `threading.Condition`. Mention the simpler alternative of immutable data with atomic reference swaps.

---

## Related Notes

- [[locks|Locks]]
- [[thread-safety-basics|Thread Safety Basics]]
- [[context-managers|Context Managers]]
- [[immutable-objects|Immutable Objects for Safety]]
