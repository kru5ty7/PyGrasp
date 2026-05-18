---
title: 02 - Thread Lifecycle
description: "A Python thread transitions through states  -  created, started, running, blocked (waiting on I/O or a lock), and terminated  -  managed by the OS scheduler and Python's GIL; `Thread.join()` waits for termination, daemon threads die when the main thread exits."
tags: [thread-lifecycle, threading, Thread, join, daemon, thread-states, layer-2, concurrency]
status: draft
difficulty: beginner
layer: 2
domain: concurrency
created: 2026-05-17
---

# Thread Lifecycle

> A Python thread transitions through states  -  created, started, running, blocked (waiting on I/O or a lock), and terminated  -  managed by the OS scheduler and Python's GIL; `Thread.join()` waits for termination, daemon threads die when the main thread exits.

---

## Quick Reference

**Core idea:**
- `t = Thread(target=fn, args=(...))`  -  creates a thread object (not yet started)
- `t.start()`  -  starts the thread; the OS creates the OS thread and schedules it
- `t.join()`  -  blocks the calling thread until `t` terminates; `t.join(timeout=5.0)` blocks for at most 5 seconds
- `t.is_alive()`  -  `True` if the thread has been started and not yet terminated
- Thread states: **new** (created, not started) ? **runnable** (started, waiting for CPU) ? **running** (executing) ? **blocked** (waiting on I/O/lock) ? **terminated** (function returned or raised)

**Tricky points:**
- A thread terminates when its `target` function returns or raises an uncaught exception  -  unhandled exceptions in threads are printed but do not crash the main program (in Python 3.8+, `threading.excepthook` is called)
- `Thread.start()` can only be called once  -  calling it again raises `RuntimeError: threads can only be started once`
- `Thread.join()` after the thread has already terminated returns immediately  -  it does not raise
- Setting `t.daemon = True` before `t.start()` makes the thread a daemon  -  the process exits when only daemon threads remain, killing them without waiting for completion
- Thread names (`Thread(name="worker-1")`) appear in `threading.enumerate()` and in exception messages; useful for debugging

---

## What It Is

Think of a thread's lifecycle like a hired contractor. First, the contractor is hired (Thread object created) but not yet on site. Then they show up (start) and join a work queue (runnable state, waiting for the OS scheduler to give them CPU time). When the scheduler assigns them a slot, they are working (running). If they need a part delivery (I/O) or the facility is locked (lock acquisition), they wait (blocked). When the job is done, they leave (terminated). The project manager can wait for the contractor to finish (`join`) or continue working on other things while the contractor works independently.

Python threads map one-to-one with OS threads. The OS scheduler manages their CPU time. Python's GIL adds an additional constraint: even if the OS gives a thread CPU time, it cannot execute Python bytecode unless it holds the GIL. So a "runnable" Python thread may be waiting for both OS CPU time and GIL acquisition.

---

## How It Actually Works

`Thread(target=fn, args=())` creates a `Thread` object in Python. No OS thread exists yet.

`t.start()`:
1. Calls `_start_new_thread(self._bootstrap, ())` (CPython internal)
2. OS creates a new thread (via `pthread_create` on Unix) with a small initial stack
3. The new thread begins executing `_bootstrap`, which sets up the thread state, acquires the GIL, and calls `fn(*args, **kwargs)`
4. `start()` returns in the calling thread without waiting

Thread cleanup: when `fn` returns (normally or via exception):
1. The exception (if any) is passed to `threading.excepthook` (default: print to stderr)
2. The thread state is cleaned up
3. The OS thread terminates

`t.join()` blocks the calling thread using a condition variable: the waiting thread sleeps until the target thread signals completion. This is efficient  -  no busy-waiting.

`threading.current_thread()` returns the current thread object. `threading.main_thread()` returns the main thread. `threading.enumerate()` returns all alive non-daemon threads.

Thread-local storage: `threading.local()` creates an object where each thread has its own independent instance of each attribute. Used by web frameworks to store per-request state (database connections, user sessions) without passing them explicitly through every function call.

---

## How It Connects

The thread lifecycle determines when a thread holds the GIL and when it is blocked  -  the GIL is released when a thread blocks on I/O or a lock.
[[gil|The GIL]]

Daemon threads are a special lifecycle variant  -  they are killed when the main thread exits rather than being joined.
[[daemon-threads|Daemon Threads]]

---

## Common Misconceptions

Misconception 1: "An unhandled exception in a thread crashes the entire program."
Reality: Unhandled exceptions in threads call `threading.excepthook` (default: print traceback to stderr) and terminate that thread. The main program continues running. This is why "fire and forget" threading bugs can be silent: the thread crashes, its exception is printed to stderr (possibly unnoticed), and the main program continues unaware.

Misconception 2: "`t.join()` is required to clean up the thread."
Reality: Thread resources are cleaned up when the thread terminates, regardless of whether `join()` is called. `join()` is for synchronization  -  waiting until the thread finishes before the calling thread proceeds. Failing to `join()` means the calling thread might exit before the worker thread finishes (which is acceptable for daemon threads but incorrect for non-daemon threads where the work must complete).

---

## Why It Matters in Practice

Always call `join()` on non-daemon threads in production code  -  if the main thread exits without joining workers, it may attempt to use results that have not yet been computed. Pattern:

```python
workers = [Thread(target=task, args=(item,)) for item in items]
for w in workers: w.start()
for w in workers: w.join()
```

Or use `concurrent.futures.ThreadPoolExecutor` which handles lifecycle management automatically.

Exception handling: set a custom `threading.excepthook` to log thread exceptions to a monitoring system rather than just printing to stderr. This is critical in production to catch silent thread failures.

---

## Interview Angle

Common question forms:
- "What are the states of a Python thread?"
- "What does `join()` do?"

Answer frame: Thread states: created ? started (runnable, waiting for CPU + GIL) ? running ? blocked (I/O or lock wait) ? terminated. `start()` creates the OS thread and begins execution; can only be called once. `join()` blocks the calling thread until the target thread terminates  -  used for synchronization. Unhandled exceptions in threads do not crash the process  -  they call `threading.excepthook` (prints to stderr by default). Daemon threads are killed when the main thread exits.

---

## Related Notes

- [[threads|Threads in Python]]
- [[daemon-threads|Daemon Threads]]
- [[locks|Locks]]
- [[gil|The GIL]]
