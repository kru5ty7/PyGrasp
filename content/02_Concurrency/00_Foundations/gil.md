---
title: 05 - The GIL
description: The Global Interpreter Lock is a mutex inside CPython that ensures only one thread executes Python bytecode at a time  -  it exists to protect reference counting from race conditions, and it is the reason Python threads cannot achieve CPU parallelism.
tags: [GIL, concurrency, threads, reference-counting, cpython, layer-2, concurrency]
status: draft
difficulty: advanced
layer: 2
domain: concurrency
created: 2026-05-17
---

# The GIL

> The Global Interpreter Lock is a mutex inside CPython that ensures only one thread executes Python bytecode at a time  -  it exists to protect reference counting from race conditions, and it is the reason Python threads cannot achieve CPU parallelism.

---

## Quick Reference

**Core idea:**
- The GIL is a **single mutex** (`_PyMutex`) that any thread must hold to execute Python bytecode
- It exists to protect **`ob_refcnt`** (reference count)  -  a plain C int that is not atomic and would corrupt under concurrent writes
- Released automatically during **blocking I/O, `time.sleep()`, C extensions** that call `Py_BEGIN_ALLOW_THREADS`
- Switch interval: **~5ms** by default (`sys.getswitchinterval()`)  -  the GIL is offered to other threads this often
- CPython **3.13+**: GIL is optional (`python -X nogil`); per PEP 703, it may become permanently removable

**Tricky points:**
- The GIL does **not** make Python code thread-safe  -  `n += 1` is multiple bytecode instructions and is still a race condition
- Releasing the GIL during I/O does **not** mean threads run Python code in parallel  -  it means one thread waits (with GIL released) while another runs Python (with GIL held)
- C extensions can hold the GIL during heavy computation  -  some libraries do this and silently block all Python threads
- `multiprocessing` bypasses the GIL by using **separate processes**, each with their own GIL  -  this is the standard workaround for CPU-bound parallelism
- Removing the GIL would require making every `ob_refcnt` update atomic  -  roughly a **10 - 50% single-threaded slowdown** for reference implementations

---

## What It Is

Imagine a single microphone at a debate. Every speaker must hold the microphone to be heard. When one speaker holds it, all others must wait. The speakers can prepare their thoughts while waiting, but they can only speak  -  deliver their actual words  -  when they have the microphone. Python threads and the GIL work the same way. Every thread can exist, be scheduled by the OS, and do non-Python work. But to execute Python bytecode  -  to actually run Python instructions  -  a thread must hold the GIL. Only one thread holds it at a time.

The GIL is a mutex: a mutual exclusion lock. It is a global lock  -  there is one per Python interpreter instance, shared by all threads in that interpreter. When a thread wants to execute Python bytecode, it acquires the GIL. When it is done (either because the switch interval has elapsed, or because it is about to do blocking I/O, or because it explicitly yields), it releases the GIL. Another waiting thread then acquires it and runs.

The reason the GIL exists is narrow and specific: CPython's reference counting. Every Python object has an `ob_refcnt` field that CPython increments and decrements as references are created and destroyed. If two threads simultaneously increment or decrement the same object's `ob_refcnt`, the result is a data race  -  both threads read the current value, both add or subtract one, both write back, and one write overwrites the other. The result is a corrupted reference count, which leads to objects being freed too early (dangling pointer, use-after-free crash) or never freed (memory leak). The GIL prevents this by making bytecode execution  -  and therefore all reference count manipulation  -  single-threaded.

---

## How It Actually Works

The GIL is implemented in `Python/ceval_gil.c`. In CPython 3.12 and earlier, it is a combination of a mutex and a condition variable. In CPython 3.12+, it uses a `_PyMutex`  -  a lightweight mutex optimized for the single-holder pattern. The lock is stored in the interpreter state structure (`_PyRuntimeState`), accessible globally.

Thread switching is triggered by the eval breaker mechanism. The interpreter loop checks a set of flags called the "eval breaker" at the top of each iteration (in CPython 3.11+, it is checked between instructions rather than only at safe points). One of these flags signals that the current thread has held the GIL for longer than `sys.getswitchinterval()` (default 5ms). When this flag is set, the current thread calls `_PyEval_EvalBreaker`, which handles GIL release: it suspends execution, releases the GIL, and waits to reacquire it before continuing. This gives waiting threads an opportunity to run.

C extensions that want to do long-running work without blocking Python threads use two macros defined in `Include/cpython/pystate.h`: `Py_BEGIN_ALLOW_THREADS` saves the current thread state and releases the GIL; `Py_END_ALLOW_THREADS` reacquires the GIL and restores thread state. Any C extension that does blocking I/O (file reads, socket operations, database calls) should wrap the I/O call in these macros. NumPy operations on arrays release the GIL for the same reason  -  the actual computation is done in C with no Python object manipulation, so the GIL is unnecessary and releasing it allows other threads to run.

PEP 703 ("Making the Global Interpreter Lock Optional in CPython") was accepted for CPython 3.13. The `nogil` build replaces `ob_refcnt` with biased reference counting  -  each object has a "local" refcount for the thread that primarily owns it and a "shared" refcount (an atomic variable) for cross-thread references. Biased reference counting makes the common case (a single-threaded refcount update) as fast as the current approach while making the cross-thread case correct. The catch is that this changes the memory layout of every Python object and breaks some C extensions that access `ob_refcnt` directly.

---

## How It Connects

The GIL exists because of reference counting. Every `Py_INCREF` and `Py_DECREF` modifies `ob_refcnt`, a plain C integer. Without the GIL, two threads modifying the same object's refcount simultaneously would corrupt it. The entire GIL story is a consequence of the refcount-based memory management strategy.
[[reference-counting|Reference Counting]]

The GIL is checked and released inside the interpreter loop  -  the `_PyEval_EvalFrameDefault` function. The eval breaker flags, the switch interval check, and the GIL release mechanism are all implemented in `ceval.c` and `ceval_gil.c`. The loop's structure is inseparable from how the GIL is enforced.
[[interpreter-loop|The Interpreter Loop]]

The GIL is the reason the I/O-bound vs CPU-bound distinction matters so much in Python. For I/O-bound work, the GIL is released during the wait, and threads effectively overlap. For CPU-bound work, the GIL is never voluntarily released by user code, and threads cannot parallelize. Understanding the GIL makes the I/O-bound/CPU-bound framework fully concrete.
[[io-bound-vs-cpu-bound|I/O Bound vs CPU Bound]]

Threads in Python are real OS threads, and the GIL is the constraint that governs what they can and cannot do in parallel. To understand how to use threads effectively in Python  -  and why they are useful for I/O-bound work but not CPU-bound work  -  the GIL must be understood first.
[[threads|Threads in Python]]

---

## Common Misconceptions

Misconception 1: "The GIL makes Python thread-safe  -  I don't need locks."
Reality: The GIL serializes bytecode execution, but it does not make Python operations atomic. `n += 1` compiles to multiple bytecode instructions: `LOAD_FAST n`, `LOAD_CONST 1`, `BINARY_OP`, `STORE_FAST n`. The GIL can be released between any two of these instructions, allowing another thread to observe or modify `n` in between. The GIL only guarantees that individual bytecode instructions are atomic, not that multi-instruction sequences are. You still need `threading.Lock` for any shared state that requires multi-step consistency.

Misconception 2: "Removing the GIL would make Python fast for all concurrent workloads."
Reality: Removing the GIL is not free. It requires making every reference count update atomic (using CPU atomic operations like CAS), which is slower than a plain integer increment on current hardware. The nogil CPython build reports single-threaded performance slowdowns of roughly 10 - 50% depending on the workload. The GIL removal helps multi-threaded CPU-bound workloads, but it imposes a cost on single-threaded workloads (the vast majority of Python programs). This trade-off is why GIL removal is opt-in in CPython 3.13 rather than the default.

---

## Why It Matters in Practice

The GIL shapes nearly every architectural decision in Python's concurrency story. It is why `multiprocessing` exists as a first-class standard library module (separate processes bypass the GIL). It is why the async/await model became popular (single-threaded concurrency avoids GIL contention entirely). It is why C extension authors are instructed to release the GIL around long-running operations. It is why libraries like NumPy, Pandas, and SciPy can provide parallelism despite Python's GIL  -  they do their heavy work in C with the GIL released.

For a developer, the GIL's practical consequence is a single rule: Python threads do not give you CPU parallelism for pure-Python code. They give you concurrency for I/O-bound work, and they cost nothing when only one thread is running (the GIL acquisition is uncontested and very cheap). When you need CPU parallelism in Python, use `multiprocessing`, not `threading`.

---

## Interview Angle

Common question forms:
- "What is the GIL? Why does Python have it?"
- "Does the GIL make Python thread-safe?"
- "How do you achieve parallelism in Python despite the GIL?"

Answer frame: Define the GIL as a mutex allowing one thread to run bytecode at a time. State the reason: reference counting uses a plain C int (`ob_refcnt`) that is not atomic  -  concurrent writes corrupt it. Address thread safety: GIL serializes individual bytecodes but not multi-instruction operations  -  locks are still required. Give the parallelism workarounds: multiprocessing (separate processes, each with their own GIL), C extensions that release the GIL (NumPy), or the upcoming nogil CPython build.

---

## Related Notes

- [[reference-counting|Reference Counting]]
- [[interpreter-loop|The Interpreter Loop]]
- [[io-bound-vs-cpu-bound|I/O Bound vs CPU Bound]]
- [[threads|Threads in Python]]
- [[processes|Processes in Python]]
