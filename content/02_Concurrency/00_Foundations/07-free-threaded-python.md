---
title: Free-Threaded Python (3.13+)
description: "Python 3.13 introduced an experimental \"free-threaded\" build (`python3.13t`) that disables the GIL — threads can now execute Python bytecode in parallel on multiple cores; the tradeoff is per-object locking overhead, memory ordering constraints, and an immature extension ecosystem."
tags: [free-threaded, nogil, python-3.13, per-object-locking, thread-safety, PEP-703, layer-2, concurrency]
status: draft
difficulty: advanced
layer: 2
domain: concurrency
created: 2026-05-17
---

# Free-Threaded Python (3.13+)

> Python 3.13 introduced an experimental "free-threaded" build (`python3.13t`) that disables the GIL — threads can now execute Python bytecode in parallel on multiple cores; the tradeoff is per-object locking overhead, memory ordering constraints, and an immature extension ecosystem.

---

## Quick Reference

**Core idea:**
- Free-threaded Python is a separate build (`python3.13t`) — standard `python3.13` still has the GIL
- Enable with `python3.13 -X gil=0` (experimental runtime toggle) or use the `t` build
- Without the GIL, multiple threads can execute Python bytecode simultaneously on multiple cores — true thread parallelism
- Thread safety requires **explicit synchronization** — the GIL previously provided implicit protection; without it, shared mutable state needs locks
- Per-object "biased locking" and immortalization of commonly shared objects replace the GIL's global protection

**Tricky points:**
- Free-threaded Python is **experimental** — not all C extensions support it; extension modules must declare `Py_mod_gil` support to be loaded without the GIL
- Performance in the free-threaded build is slower for single-threaded code (~10–15% overhead) due to per-object locking
- Race conditions that were previously impossible (GIL protected them) are now possible — global variables, module-level state, and lazy-initialized attributes need explicit locks
- `sys.flags.ignore_environment` does not suppress the GIL warning in the `t` build
- CPython 3.13 uses "immortalization" for certain objects (small integers, interned strings, `None`, `True`, `False`) to avoid per-object lock overhead for these frequently accessed objects

---

## What It Is

Think of the GIL as a traffic light that forces all threads to take turns — only one car (thread) can go through the intersection (Python interpreter) at a time. Free-threaded Python removes this traffic light and replaces it with individual lane guards at each resource (per-object locks). Cars can now go through multiple lanes simultaneously, but each car must acquire the specific lane's guard before using that lane. The result: much higher throughput, but also much more responsibility for each driver to acquire the right guards.

The GIL gave Python a strong implicit safety guarantee: no two threads could corrupt CPython's internal state simultaneously because only one executed at a time. Without the GIL, every shared mutable object — including Python's built-in types — needs thread-safe access. CPython 3.13 implements this with a combination of per-object locks (for rarely-accessed objects) and immortalization (for universally shared immutable objects).

---

## How It Actually Works

CPython 3.13 free-threaded changes:

**Immortalization**: `None`, `True`, `False`, small integers, interned strings, and certain other objects are "immortalized" — their reference counts are never modified. This eliminates lock contention for the most-accessed objects. `Py_INCREF` on an immortal object is a no-op.

**Biased locking**: Each object has a "biased" owner thread — the thread that primarily uses it can lock/unlock it with a single atomic operation (no OS mutex). If another thread contends for the lock, the bias is revoked and an unbiased lock is used. This optimizes the common single-owner case.

**Thread state**: Each OS thread has its own Python thread state (`PyThreadState`) — this was already the case, but in the free-threaded build, more state is per-thread to avoid sharing.

**Reference counting**: In free-threaded mode, reference counts are updated with atomic operations — `_Py_INCREF_IF_NONZERO` uses `Py_ATOMIC_ADD`. This is slower than the non-atomic increment in the GIL mode.

Extension compatibility: C extensions that use `Py_TPFLAGS_DEFAULT` without `Py_TPFLAGS_BASETYPE` are automatically wrapped to acquire the GIL. Extensions must explicitly declare support for the no-GIL mode by setting `Py_mod_gil = Py_MOD_GIL_NOT_USED` in their module definition.

---

## How It Connects

The GIL internals explain what free-threaded Python replaces — understanding the mutex/condition variable model of the GIL contextualizes the per-object locking approach.
[[gil-internals|GIL Internals]]

Free-threaded Python changes the thread safety model — code that relied on the GIL for implicit protection now requires explicit synchronization.
[[locks|Locks]]

---

## Common Misconceptions

Misconception 1: "Free-threaded Python makes all existing code thread-safe."
Reality: The GIL provided implicit thread safety for Python bytecode execution, but not for logical correctness. `if x not in cache: cache[x] = compute(x)` was already unsafe with the GIL (it's not atomic). Free-threaded Python removes even the bytecode-level safety — a `list.append()` in one thread can now interleave with `list.pop()` in another at the C level. Code with shared mutable state needs explicit synchronization.

Misconception 2: "Free-threaded Python is the default in Python 3.13."
Reality: Python 3.13 ships two builds: the standard `python3.13` (with GIL) and the experimental `python3.13t` (free-threaded). The GIL build remains the default. The free-threaded build is opt-in and experimental — not production-ready for all workloads. Future Python versions may make free-threaded the default.

---

## Why It Matters in Practice

CPU-bound thread parallelism: with free-threaded Python, a compute-intensive Python function can be parallelized with threads instead of multiprocessing. This avoids the overhead of process creation, pickling data for IPC, and managing process pools — for workloads where parallelism overhead dominates, this can be a significant improvement.

The ecosystem transition: popular libraries (NumPy, pandas, SQLAlchemy) are gradually adding support for the free-threaded build. Check `python3.13t -c "import numpy; print('ok')"` — if it works, NumPy supports the free-threaded build. If it falls back to GIL mode, it does not yet support it.

For most production code today: the GIL build is the safe choice. The free-threaded build is valuable for exploratory performance work and for C extension authors who need to verify thread safety.

---

## Interview Angle

Common question forms:
- "What is free-threaded Python?"
- "Does Python 3.13 remove the GIL?"

Answer frame: Python 3.13 introduces an experimental free-threaded build (`python3.13t`) that disables the GIL, enabling true thread parallelism. The standard build retains the GIL. The free-threaded build replaces global GIL protection with per-object biased locking and immortalization of common objects. Single-threaded performance is ~10–15% slower. Existing code relying on the GIL for implicit thread safety may have race conditions in the free-threaded build. C extensions need explicit opt-in.

---

## Related Notes

- [[gil-internals|GIL Internals]]
- [[gil|The GIL]]
- [[locks|Locks]]
- [[concurrency-vs-parallelism|Concurrency vs Parallelism]]
