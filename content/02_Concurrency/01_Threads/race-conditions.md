---
title: 03 - Race Conditions
description: A race condition occurs when the outcome of concurrent code depends on the interleaving order of thread operations on shared state — the result is non-deterministic and often incorrect; even simple-looking Python operations are not atomic at the bytecode level, making explicit synchronization necessary.
tags: [race-conditions, threading, atomicity, synchronization, shared-state, non-determinism, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Race Conditions

> A race condition occurs when the outcome of concurrent code depends on the interleaving order of thread operations on shared state — the result is non-deterministic and often incorrect; even simple-looking Python operations are not atomic at the bytecode level, making explicit synchronization necessary.

---

## Quick Reference

**Core idea:**
- A **race condition** is when two threads read-modify-write shared state concurrently, causing lost updates or incorrect results
- `x += 1` in Python is NOT atomic — it compiles to `LOAD_FAST`, `LOAD_CONST`, `BINARY_OP`, `STORE_FAST` — the GIL can be released between any of these
- `dict` and `list` operations have limited atomicity at the C level (`dict.__setitem__` holds the GIL for its duration) but logical read-modify-write sequences are not atomic
- **Thread-safe**: a piece of code that produces correct results when called from multiple threads concurrently — requires that all shared state mutations are synchronized
- The canonical fix: use a `threading.Lock` to protect critical sections

**Tricky points:**
- The GIL does NOT prevent race conditions — it prevents concurrent bytecode execution, but a thread can be preempted between bytecode instructions; `x += 1` is multiple bytecodes
- Race conditions are non-deterministic — code may work correctly most of the time and only fail under specific load patterns; they are notoriously hard to reproduce and debug
- CPython `dict` operations that appear atomic (e.g., `d[key] = value`) may not be safe if the operation triggers `__hash__` or `__eq__` on user objects that release the GIL
- `threading.local()` eliminates sharing entirely — each thread has its own copy; no race condition possible; the best solution when threads do not need to share the data
- `check-then-act` patterns are race-prone: `if key not in cache: cache[key] = compute(key)` — another thread may insert `key` between the check and the set

---

## What It Is

Think of two baristas at a café with a shared tip jar and a counter showing "tips today." Barista A reads the counter (shows 50), adds their tip (reads 50 + 3 = 53). Meanwhile, Barista B also reads the counter (shows 50), adds their tip (reads 50 + 5 = 55). A writes 53; B writes 55. The final count is 55 — but should be 58. One write clobbers the other. This "lost update" is a race condition: the result depends on who writes last, not on the logical sum of both updates.

In Python, `total += amount` looks atomic but compiles to separate bytecodes: load `total`, load `amount`, add them, store result. The GIL can switch between these steps. Thread A loads `total = 50`, is preempted. Thread B loads `total = 50`, adds 5, stores 55. Thread A resumes, adds 3 to its cached 50, stores 53. Result: 53 instead of 58 — the same lost update from the café.

---

## How It Actually Works

The critical section of a race condition is any sequence of operations that must execute atomically (as if no other thread could interrupt). In Python:

```python
# Thread A and Thread B both execute this:
counter += 1

# Bytecode (simplified):
# LOAD_GLOBAL counter  ? Thread can switch here
# LOAD_CONST  1
# BINARY_OP   +
# STORE_GLOBAL counter ? or here
```

The GIL switch interval is 5ms. In 5ms, a thread can execute millions of bytecodes. But if both threads execute `LOAD_GLOBAL counter` before either executes `STORE_GLOBAL counter`, both will store `original_value + 1` — losing one increment.

Demonstrations:

```python
import threading

counter = 0

def increment():
    global counter
    for _ in range(100_000):
        counter += 1

t1 = threading.Thread(target=increment)
t2 = threading.Thread(target=increment)
t1.start(); t2.start()
t1.join(); t2.join()

print(counter)  # should be 200_000, often less due to race
```

The fix: use a lock to make the increment atomic:

```python
lock = threading.Lock()

def increment():
    global counter
    for _ in range(100_000):
        with lock:
            counter += 1
```

---

## How It Connects

Locks are the primary tool for preventing race conditions — they ensure only one thread enters the critical section at a time.
[[locks|Locks]]

Thread-safe queues eliminate race conditions for producer-consumer patterns by using internal locks — the `queue.Queue` class provides atomic put/get operations.
[[thread-safe-queues|Thread-Safe Queues]]

---

## Common Misconceptions

Misconception 1: "Python's GIL prevents race conditions."
Reality: The GIL prevents concurrent bytecode execution but not race conditions. A thread can be preempted between any two bytecode instructions — the GIL only ensures one thread runs at a time, not that a logical sequence runs atomically. Multi-instruction sequences like `x += 1`, `if k not in d: d[k] = v`, and any read-modify-write pattern are still race-prone.

Misconception 2: "Race conditions always produce obviously wrong results."
Reality: Race conditions are non-deterministic and often produce correct-looking results most of the time. A race condition in a counter that increments a million times may only lose a few increments under light load — visible only under high concurrency. This non-determinism makes them difficult to catch in testing and dangerous in production.

---

## Why It Matters in Practice

The canonical thread-unsafe pattern in Python:

```python
if key not in shared_dict:
    shared_dict[key] = expensive_compute(key)
```

Thread A checks `key not in shared_dict` (True), is preempted. Thread B also checks (True), computes, stores. Thread A resumes, also computes, overwrites. Either `expensive_compute` is called twice (wasted work) or worse, the second write clobbers useful state. Fix: use a lock around the check-and-set, or use `shared_dict.setdefault(key, None)` (atomic in CPython).

Thread-safe patterns: `collections.deque.append()` and `popleft()` are thread-safe (single GIL-held operation). `queue.Queue` is fully thread-safe. `threading.local()` avoids sharing entirely. `concurrent.futures.ThreadPoolExecutor` manages thread pools safely.

---

## Interview Angle

Common question forms:
- "What is a race condition?"
- "Does the GIL prevent race conditions?"

Answer frame: A race condition is when the outcome of concurrent code depends on thread interleaving order — typically a read-modify-write sequence on shared state. The GIL does not prevent them: `x += 1` is multiple bytecodes and the GIL can switch between them. The fix: protect critical sections with `threading.Lock()`. Race conditions are non-deterministic — they appear infrequently under low load, making them hard to catch in tests. Use thread-safe data structures (`queue.Queue`, `threading.local()`) to eliminate the need for explicit locking where possible.

---

## Related Notes

- [[locks|Locks]]
- [[threads|Threads in Python]]
- [[thread-safe-queues|Thread-Safe Queues]]
- [[gil|The GIL]]
