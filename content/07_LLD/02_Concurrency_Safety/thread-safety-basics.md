---
title: 01 - Thread Safety Basics
description: Thread safety ensures that shared data remains consistent when multiple threads access it simultaneously, preventing race conditions through synchronization primitives like locks, atomic operations, and immutable data structures.
tags: [concurrency, thread-safety, locks, race-conditions, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Thread Safety Basics

> Thread safety means that shared state remains correct when accessed by multiple threads simultaneously, achieved through locks, atomic operations, or elimination of shared mutable state.

---

## Quick Reference

**Core idea:**
- Code is **thread-safe** if it produces correct results when called from multiple threads at the same time
- The root problem is **shared mutable state** - when two threads read-modify-write the same variable, the interleaving of operations can corrupt the result
- **Locks** (`threading.Lock`) serialize access to shared state - only one thread holds the lock at a time
- **Atomic operations** are indivisible - they complete fully or not at all, without interference
- The safest approach is **eliminating shared mutable state** entirely through immutable objects, thread-local storage, or message passing

**Tricky points:**
- Python's GIL does not make your code thread-safe - it prevents simultaneous bytecode execution but allows context switches between any two bytecodes
- A `counter += 1` is not atomic - it is LOAD, ADD, STORE at the bytecode level, and a context switch can happen between any of these steps
- Deadlocks occur when two threads each hold a lock the other needs - always acquire locks in a consistent order
- Holding a lock during I/O blocks other threads unnecessarily - keep critical sections as small as possible

---

## What It Is

Think of a shared bank account accessed by two ATMs simultaneously. Both ATMs read the balance ($100), both decide to withdraw $80, both see sufficient funds. ATM 1 sets the balance to $20. ATM 2, still working with its stale reading of $100, sets the balance to $20. The account should be overdrawn (or the second withdrawal should be rejected), but instead the bank lost $60. This is a race condition: the outcome depends on the timing of operations, and no synchronization prevents inconsistent states.

Thread safety is the discipline of preventing this kind of corruption. When multiple threads access shared data, you need to ensure that read-modify-write operations happen atomically (all-or-nothing) or are serialized (one at a time). Python provides several mechanisms: locks (`threading.Lock`) that let only one thread into a critical section at a time, reentrant locks (`threading.RLock`) that can be acquired multiple times by the same thread, conditions (`threading.Condition`) that let threads wait for a specific state, and semaphores (`threading.Semaphore`) that limit concurrent access to a resource.

The GIL (Global Interpreter Lock) is Python's mechanism for protecting the interpreter's own internal state, but it does not protect your application's state. The GIL ensures that only one thread executes Python bytecode at a time, but it releases between bytecode instructions. A `balance += amount` compiles to multiple bytecodes (LOAD_FAST, BINARY_ADD, STORE_FAST), and a thread switch can happen between any of them. This means that even in CPython, you need explicit synchronization for shared mutable state.

The best approach to thread safety is often to avoid shared mutable state entirely. Use immutable objects (data flows through, never modified in place). Use thread-local storage (`threading.local()`) for data that each thread owns independently. Use message-passing patterns (queues) where threads communicate by sending data rather than sharing it. When you eliminate shared mutation, you eliminate race conditions.

---

## How It Actually Works

A `threading.Lock` is a mutual exclusion (mutex) primitive. When a thread calls `lock.acquire()`, it either acquires the lock immediately (if no other thread holds it) or blocks until the lock is released. The thread that holds the lock is the only one that can execute the critical section. When it calls `lock.release()`, another waiting thread can acquire the lock. The `with lock:` syntax ensures the lock is always released, even if an exception occurs.

```python
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass


# RACE CONDITION: no synchronization
class UnsafeCounter:
    def __init__(self):
        self.value = 0

    def increment(self):
        # NOT atomic: LOAD value, ADD 1, STORE value
        self.value += 1

unsafe = UnsafeCounter()

def unsafe_work():
    for _ in range(100_000):
        unsafe.increment()

with ThreadPoolExecutor(max_workers=4) as pool:
    futures = [pool.submit(unsafe_work) for _ in range(4)]
    for f in futures:
        f.result()

# Expected: 400,000. Actual: often less due to race conditions
print(f"Unsafe counter: {unsafe.value}")  # e.g., 387,432


# THREAD-SAFE: using a lock
class SafeCounter:
    def __init__(self):
        self.value = 0
        self._lock = threading.Lock()

    def increment(self):
        with self._lock:  # only one thread at a time
            self.value += 1

safe = SafeCounter()

def safe_work():
    for _ in range(100_000):
        safe.increment()

with ThreadPoolExecutor(max_workers=4) as pool:
    futures = [pool.submit(safe_work) for _ in range(4)]
    for f in futures:
        f.result()

print(f"Safe counter: {safe.value}")  # Always 400,000


# Thread-local storage: each thread has its own copy
local_data = threading.local()

def worker(thread_id: int):
    local_data.id = thread_id  # each thread has its own .id
    # Other threads cannot see this thread's local_data.id
    print(f"Thread {thread_id}: local id = {local_data.id}")

threads = [threading.Thread(target=worker, args=(i,)) for i in range(3)]
for t in threads:
    t.start()
for t in threads:
    t.join()


# Deadlock example and prevention
lock_a = threading.Lock()
lock_b = threading.Lock()

# DEADLOCK-PRONE: inconsistent lock ordering
# Thread 1: acquire A, then B
# Thread 2: acquire B, then A
# Both wait forever.

# SAFE: always acquire in the same order
def transfer(from_account, to_account, amount):
    # Sort by id to ensure consistent ordering
    first, second = sorted([from_account, to_account], key=id)
    with first["lock"]:
        with second["lock"]:
            from_account["balance"] -= amount
            to_account["balance"] += amount
```

---

## How It Connects

Thread safety is about managing shared state in concurrent execution. Understanding Python's threading model and the GIL is prerequisite.

[[race-conditions|Race Conditions]]

[[locks|Locks]]

[[gil|GIL]]

Immutable objects eliminate the need for locks by preventing mutation. Using frozen dataclasses and tuples instead of mutable state is the safest form of thread safety.

[[immutable-objects|Immutable Objects for Safety]]

[[mutability|Mutability]]

Thread-safe queues are the preferred way for threads to communicate. They use locks internally and provide a clean message-passing interface.

[[thread-safe-queues|Thread Safe Queues]]

---

## Common Misconceptions

Misconception 1: "Python's GIL makes all Python code thread-safe."
Reality: The GIL prevents parallel bytecode execution but allows context switches between any two bytecodes. A compound operation like `balance += amount` is multiple bytecodes, and a switch can happen in the middle. The GIL protects CPython's internals, not your application's shared state.

Misconception 2: "If I use locks everywhere, my code is thread-safe."
Reality: Locks prevent race conditions on the specific data they protect, but they introduce new risks: deadlocks (circular lock dependencies), livelocks (threads keep yielding to each other), priority inversion (a high-priority thread waits for a low-priority one holding a lock), and performance degradation (lock contention serializes all threads).

Misconception 3: "Thread safety is only relevant in multi-threaded programs."
Reality: Asyncio's single-threaded model avoids threading race conditions but introduces its own: if two coroutines modify shared state, and either yields control (via `await`) between read and write, you have an async race condition. Thread safety principles apply to any concurrent model.

---

## Why It Matters in Practice

Web frameworks like FastAPI and Flask handle requests in separate threads (or async tasks). If your request handlers share mutable state - a cache dictionary, a rate limiter counter, a connection pool - that state must be thread-safe. A race condition in a rate limiter might let too many requests through. A race condition in a cache might serve stale or corrupted data.

Thread safety bugs are among the hardest to reproduce. They depend on timing, and adding print statements or debugger breakpoints changes the timing enough to mask the bug. This makes prevention (proper design) far more valuable than detection (debugging).

---

## Interview Angle

Common question forms:
- "What is thread safety?"
- "Is `counter += 1` thread-safe in Python?"
- "How do you prevent race conditions?"
- "What is a deadlock and how do you avoid it?"

Answer frame:
Define thread safety as correct behavior under concurrent access. Explain that `+=` is not atomic (LOAD-ADD-STORE). Show Lock usage. Explain GIL does not protect application state. Discuss alternatives: immutable objects, thread-local storage, queues. Define deadlock and the consistent-ordering prevention strategy.

---

## Related Notes

- [[race-conditions|Race Conditions]]
- [[locks|Locks]]
- [[gil|GIL]]
- [[immutable-objects|Immutable Objects for Safety]]
- [[mutability|Mutability]]
- [[thread-safe-queues|Thread Safe Queues]]
