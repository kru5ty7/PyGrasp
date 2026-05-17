---
title: 05 - Deadlocks
description: A deadlock occurs when two or more threads are each waiting for a lock held by the other, creating a circular dependency that no thread can break — the four necessary conditions (Coffman conditions) must all hold for a deadlock; prevention strategies include lock ordering, timeouts, and avoiding nested locks.
tags: [deadlocks, threading, locks, circular-wait, Coffman-conditions, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Deadlocks

> A deadlock occurs when two or more threads are each waiting for a lock held by the other, creating a circular dependency that no thread can break — the four necessary conditions (Coffman conditions) must all hold for a deadlock; prevention strategies include lock ordering, timeouts, and avoiding nested locks.

---

## Quick Reference

**Core idea:**
- Deadlock: Thread A holds Lock 1, waits for Lock 2. Thread B holds Lock 2, waits for Lock 1. Both wait forever.
- **Coffman conditions** — all four must hold for a deadlock:
  1. Mutual exclusion (only one thread can hold a lock)
  2. Hold and wait (a thread holds a lock while waiting for another)
  3. No preemption (locks cannot be forcibly taken away)
  4. Circular wait (a cycle in the "waiting for" graph)
- Prevention: lock ordering (always acquire locks in the same order), timeouts (`lock.acquire(timeout=...)`), or using a single lock
- `threading.Lock()` (and `RLock()`) do not have deadlock detection — the program simply hangs

**Tricky points:**
- A thread can deadlock with itself if it acquires a non-reentrant `Lock` twice — use `RLock` for recursive code that holds a lock
- Deadlocks are often non-deterministic — the program may work for months and then deadlock under high load when both threads happen to acquire their first lock simultaneously
- `lock.acquire(timeout=5.0)` returning `False` does not resolve the deadlock — the thread must decide what to do on timeout (retry? abort? log?); without a timeout, the program hangs silently
- Database deadlocks are detected and resolved by the database (one transaction is rolled back) — Python's threading module has no equivalent detection
- `logging` module uses an internal lock — calling a logger while holding a custom lock can deadlock if another thread holds the logger lock and waits for the custom lock

---

## What It Is

Think of two people at a narrow bridge, each from opposite ends. Person A is on the bridge and will only step aside after person B steps back. Person B is on the bridge and will only step aside after person A steps back. Neither moves. This is a deadlock: both are blocked on the other's cooperation, and neither can proceed.

In Python, Thread A acquires Lock1 and then waits for Lock2. Thread B acquires Lock2 and then waits for Lock1. A can't proceed without Lock2 (held by B). B can't proceed without Lock1 (held by A). Both wait forever.

Deadlocks are insidious because they do not produce error messages — the program simply stops responding. The threads are alive, they are not in an error state, they are just blocked. Without monitoring or timeouts, a deadlocked program looks like a hung program with no obvious cause.

---

## How It Actually Works

Classic deadlock in Python:

```python
import threading

lock1 = threading.Lock()
lock2 = threading.Lock()

def task_a():
    with lock1:          # acquires lock1
        # ... work ...
        with lock2:      # waits for lock2 — may deadlock
            # ... work ...

def task_b():
    with lock2:          # acquires lock2
        # ... work ...
        with lock1:      # waits for lock1 — may deadlock
            # ... work ...

t1 = threading.Thread(target=task_a)
t2 = threading.Thread(target=task_b)
t1.start(); t2.start()
```

If `t1` acquires `lock1` and `t2` acquires `lock2` before either tries for the second lock, deadlock occurs.

**Prevention: Lock Ordering**

Always acquire locks in a consistent global order (e.g., by id or by defined enum position):

```python
def safe_task(first_lock, second_lock):
    # Sort by id to ensure consistent acquisition order
    locks = sorted([first_lock, second_lock], key=id)
    with locks[0]:
        with locks[1]:
            # critical section — same order always
```

**Prevention: Timeout**

```python
if lock1.acquire(timeout=5.0):
    try:
        if lock2.acquire(timeout=5.0):
            try:
                # critical section
            finally:
                lock2.release()
        else:
            # failed to acquire lock2 — log, retry, or abort
    finally:
        lock1.release()
```

**Prevention: Single lock** — use one coarse-grained lock to cover all shared state; simpler but reduces concurrency.

---

## How It Connects

Locks are the prerequisite — deadlocks only arise with lock-based synchronization. Understanding how locks work explains why circular waits occur.
[[locks|Locks]]

Semaphores can also participate in deadlocks — any blocking synchronization primitive can create circular wait patterns.
[[semaphores|Semaphores]]

---

## Common Misconceptions

Misconception 1: "Deadlocks are easy to detect and debug."
Reality: Deadlocked threads appear as blocked threads — no exception, no error, just silence. Without proper tooling (stack traces, monitoring, timeouts), a deadlock looks like a hung program. `faulthandler.dump_traceback_later(timeout)` can print stack traces after a timeout, helping diagnose stuck programs.

Misconception 2: "RLock prevents deadlocks."
Reality: `RLock` prevents a single thread from deadlocking with itself (reentrant acquisition). It does not prevent deadlocks between multiple threads — Thread A holding Lock1 (an RLock) and waiting for Lock2, while Thread B holds Lock2 and waits for Lock1 is still a deadlock.

---

## Why It Matters in Practice

Lock ordering is the most reliable prevention strategy. Define a canonical order for all locks in the system (by module, by subsystem, by ID). Every code path that acquires multiple locks must acquire them in that order. If every thread acquires `db_lock` before `cache_lock`, no circular wait is possible between those two locks.

Debugging deadlocks: run `py-spy dump --pid <pid>` or use `faulthandler.dump_traceback_later(30)` at startup to print all thread stacks after 30 seconds — deadlocked threads show blocked on `lock.acquire()`.

Design to avoid nested locks: the most reliable prevention is to never hold multiple locks simultaneously. Restructure code to release one lock before acquiring another. If this is not possible, enforce a consistent acquisition order.

---

## Interview Angle

Common question forms:
- "What is a deadlock and how do you prevent it?"
- "What are the Coffman conditions?"

Answer frame: A deadlock is circular waiting — Thread A holds Lock1 and waits for Lock2; Thread B holds Lock2 and waits for Lock1. Both block forever. Four Coffman conditions must hold: mutual exclusion, hold-and-wait, no preemption, circular wait. Eliminate any one to prevent deadlock. Most practical strategy: lock ordering (always acquire in the same order). Also: use timeouts (`lock.acquire(timeout=...)`), avoid holding multiple locks, or redesign to use a single lock.

---

## Related Notes

- [[locks|Locks]]
- [[semaphores|Semaphores]]
- [[race-conditions|Race Conditions]]
- [[threads|Threads in Python]]
