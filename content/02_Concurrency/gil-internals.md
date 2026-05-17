---
title: GIL Internals
description: The GIL is implemented as a mutex with a condition variable — Python 3.2 replaced the "check every N bytecodes" mechanism with a 5ms forced release interval using a timed wait; understanding the switching mechanism, "GIL battle" problem, and new-GIL fixes explains thread performance characteristics.
tags: [GIL, gil-internals, mutex, condition-variable, sys.getswitchinterval, ceval, layer-2, concurrency]
status: draft
difficulty: advanced
layer: 2
domain: concurrency
created: 2026-05-17
---

# GIL Internals

> The GIL is implemented as a mutex with a condition variable — Python 3.2 replaced the "check every N bytecodes" mechanism with a 5ms forced release interval using a timed wait; understanding the switching mechanism, "GIL battle" problem, and new-GIL fixes explains thread performance characteristics.

---

## Quick Reference

**Core idea:**
- The GIL is a `PyMutex` (or `pthread_mutex`) plus a condition variable (`pthread_cond`)
- Pre-3.2: GIL was released every 100 bytecodes (`sys.getcheckinterval()`) — caused unfair starvation, especially on multi-core
- Python 3.2+ (new GIL): GIL is released after `sys.getswitchinterval()` seconds (default 5ms) using a timed wait; a "request" flag signals the running thread to drop the GIL
- **eval_breaker**: an atomic flag in the interpreter loop that the running thread checks; set by the requesting thread; causes the running thread to release the GIL
- Python 3.13 introduced an optional "free-threaded" build (`--disable-gil`) with per-object locking replacing the GIL

**Tricky points:**
- The GIL is released by the running thread voluntarily — there is no preemption at the bytecode level; the `eval_breaker` flag is polled at safe points
- Releasing the GIL does not guarantee the waiting thread gets it — the OS decides which thread runs; on multi-core, the woken thread may not be scheduled immediately (the "GIL battle")
- C extensions that do not call into CPython's evaluation loop (pure C computation) can release the GIL explicitly: `Py_BEGIN_ALLOW_THREADS` / `Py_END_ALLOW_THREADS` — NumPy uses this for array operations
- The GIL is acquired/released per-call when calling into C extension functions that manage it; a pure Python tight loop holds the GIL for up to 5ms before releasing
- Deadlock if a C extension acquires the GIL while already holding a Python-level lock: the GIL must always be acquired first

---

## What It Is

Think of the GIL as a "hot potato" passed between Python threads. Only the thread holding the hot potato can execute Python bytecode. After holding it for 5ms, the running thread must either pass it (if another thread is waiting and requested it) or keep it (if no one wants it). The request mechanism is an "I want it" flag that another thread sets — the potato holder sees the flag, finishes its current safe point, and drops the potato.

The old GIL (pre-3.2) checked the flag every 100 bytecodes. This was simple but problematic on multi-core: a CPU-bound thread could keep the GIL because after releasing it, the other core immediately acquires it and releases it back before the first core's OS thread is even scheduled. Two cores spent more time fighting over the GIL than doing work — the "GIL battle."

The new GIL (3.2+) uses a timed wait. If a thread wants the GIL and it is held, it waits 5ms, then sets the `gil_drop_request` flag. The holding thread sees this flag and drops the GIL. The requesting thread acquires it and runs. This ensures the GIL changes hands at most every 5ms, regardless of bytecode count — fairer and more predictable.

---

## How It Actually Works

Relevant CPython source (simplified from `Python/ceval_gil.c`):

```c
// Thread waiting for GIL:
MUTEX_LOCK(gil_mutex);
while (GIL_IS_LOCKED) {
    // Wait up to INTERVAL (5ms) for the GIL to be released
    timed_wait(gil_mutex, gil_cond, INTERVAL);
    if (still_locked_after_wait) {
        SET_eval_breaker();  // signal holding thread to drop GIL
    }
}
ACQUIRE_GIL;
MUTEX_UNLOCK(gil_mutex);

// Thread releasing GIL (triggered by eval_breaker):
if (eval_breaker) {
    check_pending_signals();
    if (gil_drop_request) {
        DROP_GIL;
        MUTEX_LOCK(gil_mutex);
        NOTIFY_WAITING_THREAD;
        MUTEX_UNLOCK(gil_mutex);
        ACQUIRE_GIL;  // immediately try to reacquire
    }
}
```

The `eval_breaker` flag is an atomic integer checked in the main interpreter evaluation loop (`Python/ceval.c`, the `_PyEval_EvalFrameDefault` function). It is checked after each bytecode instruction via a fast path: if zero, no action; if non-zero, enter the slower path that handles GIL drops, signals, and async exceptions.

C extensions releasing the GIL: `Py_BEGIN_ALLOW_THREADS` saves the current thread state and releases the GIL. `Py_END_ALLOW_THREADS` reacquires the GIL and restores the thread state. Between these macros, the C code can run on any number of OS threads simultaneously — CPython is not involved, so no GIL protection is needed.

---

## How It Connects

The GIL's existence and behavior directly shapes Python's concurrency model — understanding the internals explains why threads help I/O-bound work but not CPU-bound work.
[[gil|The GIL]]

Free-threaded Python (3.13+) removes the GIL entirely and replaces it with per-object locking — a different internal model that changes the performance characteristics.
[[free-threaded-python|Free-Threaded Python (3.13+)]]

---

## Common Misconceptions

Misconception 1: "The GIL is released between every bytecode instruction."
Reality: The GIL is held continuously across bytecodes until the `eval_breaker` flag triggers — which happens every 5ms if another thread is waiting. In a single-threaded program, the GIL is never released (no one is requesting it). In a multi-threaded program, it is released every ~5ms when threads are competing.

Misconception 2: "NumPy operations are GIL-limited."
Reality: NumPy releases the GIL during array operations by using `Py_BEGIN_ALLOW_THREADS`. Multiple NumPy operations on different threads can run truly in parallel if each releases the GIL during the computation. The GIL only applies to Python bytecode execution, not to C extension code that explicitly manages the GIL.

---

## Why It Matters in Practice

Understanding the GIL switch mechanism explains the 5ms granularity of thread switching — a tight CPU-bound loop in Python will hold the GIL for up to 5ms before yielding. If a real-time system requires sub-millisecond responsiveness, threads are not the solution regardless of GIL management — use asyncio or processes.

C extension authors: any C function that does significant computation should release the GIL with `Py_BEGIN_ALLOW_THREADS` / `Py_END_ALLOW_THREADS` to allow other Python threads to run. Failure to do this causes a thread holding a C extension to block all other Python threads for the duration of the computation.

The Python 3.13 free-threaded build changes the model fundamentally — per-object locks replace the GIL, enabling true thread parallelism at the cost of higher per-object overhead and complex synchronization requirements.

---

## Interview Angle

Common question forms:
- "How does the GIL actually work internally?"
- "Why did the GIL mechanism change in Python 3.2?"

Answer frame: The GIL is a mutex + condition variable. Old GIL (pre-3.2): released every 100 bytecodes — caused multi-core "GIL battle" where two cores fought over the lock. New GIL (3.2+): a waiting thread sets `eval_breaker` after 5ms; the running thread drops the GIL at the next safe point. C extensions can release the GIL with `Py_BEGIN_ALLOW_THREADS` for non-Python computation. Python 3.13 adds a `--disable-gil` build with per-object locking.

---

## Related Notes

- [[gil|The GIL]]
- [[free-threaded-python|Free-Threaded Python (3.13+)]]
- [[context-switching|Context Switching]]
- [[threads|Threads in Python]]
