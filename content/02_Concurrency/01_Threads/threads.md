---
title: 01 - Threads in Python
description: "Python threads are real OS threads managed by the `threading` module — they run concurrently but not in parallel for CPU-bound work because of the GIL, making them the right tool for I/O-bound concurrency but the wrong tool for CPU-intensive parallelism."
tags: [threads, threading, GIL, concurrency, OS-threads, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Threads in Python

> Python threads are real OS threads managed by the `threading` module — they run concurrently but not in parallel for CPU-bound work because of the GIL, making them the right tool for I/O-bound concurrency but the wrong tool for CPU-intensive parallelism.

---

## Quick Reference

**Core idea:**
- Python threads are **real OS threads** — `pthread` on Unix/macOS, Win32 threads on Windows
- The `threading` module provides: `Thread`, `Lock`, `RLock`, `Event`, `Condition`, `Semaphore`, `Barrier`, `Timer`, `local`
- Threads **share memory** — all threads in a process see the same objects; no serialization needed for communication
- The **GIL limits** threads to one executing Python bytecode at a time — I/O-bound tasks benefit; CPU-bound do not
- Thread creation: `t = Thread(target=fn, args=(a,)); t.start(); t.join()`

**Tricky points:**
- `thread.join()` blocks until the thread finishes — forgetting it means the main thread may exit before the worker finishes
- `threading.Lock` is **not reentrant** — if the same thread tries to acquire a Lock it already holds, it deadlocks; use `RLock` instead
- Daemon threads (`t.daemon = True`) are **killed abruptly** when the main thread exits — no cleanup, no `finally` blocks run
- `n += 1` is **not thread-safe** even with the GIL — the GIL is released between instructions; protect shared state with a `Lock`
- `threading.local()` creates thread-local storage — each thread gets its own copy of the variable, independent of other threads

---

## What It Is

Imagine a restaurant with several waiters. All waiters work in the same building, share the same kitchen, and can talk to each other directly by walking over. If waiter A needs information from waiter B, they just ask — no special communication protocol required. When one waiter is waiting for the kitchen to finish an order, the other waiters can keep taking orders and delivering food. Python threads are like those waiters: multiple workers in the same process, sharing the same memory, able to communicate directly, each doing their part while others wait.

A Python thread is an OS thread — a unit of execution that the operating system schedules independently, just like threads in any other language. When you create a `threading.Thread` and call `start()`, CPython calls the platform's native thread creation API: `pthread_create` on Linux and macOS, `CreateThread` on Windows. The OS then schedules this thread to run on available CPUs, manages its stack, and handles context switching between threads. Python is not simulating threads in software; it is using real OS-level threads.

The unique aspect of Python threads is the GIL. While the OS is free to run Python threads on multiple CPU cores simultaneously, CPython's GIL prevents more than one thread from executing Python bytecode at any given moment. One thread runs, the other waits. The GIL is yielded periodically and during blocking I/O, which allows threads to take turns. For I/O-bound work — where threads spend most of their time waiting for the network, disk, or other external resources — this is fine. One thread waits with the GIL released while another runs. For CPU-bound work, where threads need to execute Python code continuously, the GIL makes them serial rather than parallel.

---

## How It Actually Works

When `threading.Thread.start()` is called, CPython calls `_thread.start_new_thread()`, a C function that calls the platform thread API to create a new OS thread. The new OS thread begins execution in a C bootstrap function that sets up the Python thread state — an allocation that includes the thread's frame stack, exception state, and GIL acquisition record. The bootstrap then calls the Python target function.

The thread state (`PyThreadState`) is the per-thread structure that CPython uses to track execution. There is one thread state per OS thread. When the GIL is acquired, the acquiring thread's `PyThreadState` becomes the "current" thread state for the interpreter. When the GIL is released (at the switch interval or during I/O), the current thread state is "detached" — any other waiting thread can acquire the GIL and become current. The `_Py_atomic_load_relaxed_int32` on the eval breaker flags is how the interpreter loop notices it is time to yield the GIL.

Synchronization primitives in `threading` map directly to OS synchronization objects. `threading.Lock` wraps a platform mutex (`pthread_mutex_t` on Unix). `threading.Event` wraps a condition variable. `threading.Semaphore` wraps a semaphore. These primitives all interact with the GIL correctly: acquiring a `Lock` in Python releases the GIL while waiting, so a blocked thread does not hold the GIL and prevent other threads from running. This is essential — if `Lock.acquire()` held the GIL while blocking, all other threads would be frozen waiting.

Thread-local storage via `threading.local()` allocates a separate storage namespace per thread. Under the hood, `threading.local()` creates an object backed by a dictionary keyed by thread identifier. Each thread sees its own dictionary when accessing attributes on a `local()` object. This is used in web frameworks (storing the current request), database libraries (storing connections per thread), and any code that needs per-thread state without passing it explicitly through function calls.

---

## How It Connects

The GIL is the single most important constraint on Python threads. Every thread in a Python process competes for the same lock, and only the holder can execute bytecode. Whether threads are useful for a given task depends entirely on whether the GIL is released while the thread is doing its work — which is determined by whether the work is I/O-bound (GIL released during the wait) or CPU-bound (GIL held throughout).
[[gil|The GIL]]

Threads and processes are the two OS-level concurrency models available in Python. Threads share memory; processes are isolated. Understanding when to use each requires knowing the trade-offs: threads have lower overhead and easier communication; processes provide true CPU parallelism. The thread-vs-process note puts these trade-offs side by side.
[[thread-vs-process|Threads vs Processes]]

`ThreadPoolExecutor` from `concurrent.futures` provides a higher-level API for using threads: submit work items, get back `Future` objects, and let a managed pool handle thread creation and reuse. It is the recommended way to use threads for most practical I/O-bound workloads, avoiding the manual `Thread` + `join` pattern.
[[thread-pool-executor|ThreadPoolExecutor]]

---

## Common Misconceptions

Misconception 1: "Python threads run in parallel on multiple CPU cores."
Reality: Python threads are real OS threads and the OS will assign them to multiple CPU cores. However, the GIL ensures that only one thread executes Python bytecode at a time. Even with 8 cores and 8 threads, only one is running Python at any moment. For I/O-bound work, this is not a problem — threads spend most of their time waiting with the GIL released. For CPU-bound pure Python code, you get single-core performance regardless of how many threads or cores you have.

Misconception 2: "Using a `threading.Lock` makes everything thread-safe."
Reality: A lock only protects what you put inside it. If two pieces of code both modify the same shared data and only one uses a lock, the other can still corrupt the data. Thread safety requires consistent locking conventions across all code that touches shared state. A lock also introduces the risk of deadlock if multiple locks are acquired in inconsistent orders across threads. Locks solve race conditions for the specific operations they protect — nothing more.

---

## Why It Matters in Practice

Threads are the right tool for I/O-bound concurrency when you need to run existing blocking code concurrently and cannot easily rewrite it with async/await. A Python web scraper that calls `requests.get()` (a blocking call) in a loop can be made concurrent by running multiple calls in parallel threads, each waiting independently. A program that reads from multiple sockets can use threads to handle each connection without blocking the others. In both cases, the threads spend most of their time waiting for I/O with the GIL released, so the GIL is not the bottleneck.

The main alternative to threads for I/O-bound work is async/await. Async has lower overhead for high-concurrency scenarios (thousands of simultaneous I/O operations) because thread creation and OS context switching costs grow with the number of threads, while coroutine switching is implemented in Python with no OS involvement. However, async requires your entire I/O stack to have async-compatible libraries. Threads work with any existing blocking library. The choice depends on the scale of concurrency you need and whether async-compatible libraries exist for your use case.

---

## Interview Angle

Common question forms:
- "Are Python threads real OS threads?"
- "When would you use threads versus async/await?"
- "Why doesn't using threads speed up CPU-intensive Python code?"

Answer frame: Confirm that Python threads are real OS threads (`pthread`/Win32). Explain the GIL: one thread runs bytecode at a time; the GIL is released during I/O. Give the rule: threads help I/O-bound work (GIL released during waits), not CPU-bound work (GIL held throughout). Compare to async: threads work with blocking libraries but have higher overhead; async requires async libraries but scales better. For CPU parallelism, multiprocessing is the answer.

---

## Related Notes

- [[gil|The GIL]]
- [[io-bound-vs-cpu-bound|I/O Bound vs CPU Bound]]
- [[thread-vs-process|Threads vs Processes]]
- [[thread-pool-executor|ThreadPoolExecutor]]
