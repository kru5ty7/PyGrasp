---
title: 09 - Daemon Threads
description: "A daemon thread is a background thread that is automatically killed when all non-daemon threads have exited — marked with `t.daemon = True` before `t.start()`; use for background tasks (heartbeats, log flushing, monitors) that should not prevent program exit."
tags: [daemon-threads, threading, background-threads, thread-lifecycle, layer-2, concurrency]
status: draft
difficulty: beginner
layer: 2
domain: concurrency
created: 2026-05-17
---

# Daemon Threads

> A daemon thread is a background thread that is automatically killed when all non-daemon threads have exited — marked with `t.daemon = True` before `t.start()`; use for background tasks (heartbeats, log flushing, monitors) that should not prevent program exit.

---

## Quick Reference

**Core idea:**
- `t = Thread(target=fn, daemon=True)` or `t.daemon = True` (must be set before `t.start()`)
- The Python process exits when all **non-daemon** threads have finished — daemon threads are abruptly killed
- By default, all threads are non-daemon — the process waits for all non-daemon threads to complete
- `threading.main_thread().daemon` is `False` — the main thread is always non-daemon
- New threads inherit the daemon status of the creating thread — if a daemon thread creates a thread, that thread is also daemon by default

**Tricky points:**
- Daemon threads are **killed abruptly** — their `finally` blocks, `__exit__` methods, and cleanup code may NOT run; do not use daemon threads for work that requires cleanup (file writes, DB commits, network connections to close)
- `t.daemon = True` must be set before `t.start()` — setting it after raises `RuntimeError: cannot set daemon status of active thread`
- A daemon thread can be joined with `t.join()` — this blocks until the daemon thread terminates naturally or the timeout expires; `join()` does not change the daemon status
- The `threading.Thread(daemon=True)` constructor argument is available in Python 3.3+ and is equivalent to setting `t.daemon = True`
- When the main thread exits due to `sys.exit()` or returning from `main()`, daemon threads are killed before the interpreter shuts down

---

## What It Is

Think of workers in an office building. When the last manager leaves and locks up for the night, the building's automated systems (heating, security monitors, lighting timers) shut down too — they exist to support the office work, and when the work is done, they are no longer needed. These are the daemon threads. The managers who need to finish their report before leaving are non-daemon threads — the building stays open until they are done.

The practical distinction is about what the thread does. A thread that produces work that must be saved, committed, or confirmed before exit is non-daemon — you join it and wait. A thread that just monitors, polls, or provides background services — a heartbeat sender, a log batcher, a cache refresher — is daemon. If the process is shutting down, these services can be abandoned without loss of critical data.

---

## How It Actually Works

Python's interpreter shutdown sequence (when all non-daemon threads finish):
1. Mark daemon threads for termination
2. Call each daemon thread's OS thread kill mechanism (no graceful shutdown signal)
3. Run `atexit` handlers (in the main thread, after daemon threads are killed)
4. Finalize the interpreter

Daemon threads are killed by the OS (not by Python signaling them) — they receive no notification. Any code in the daemon thread that has not yet executed is abandoned. `finally` blocks that have not been entered will not execute; `finally` blocks already entered and waiting may also be abandoned depending on the exact termination point.

Non-daemon lifecycle:
```python
# Main thread waits for all non-daemon threads:
# Process exits only when this condition is met:
all(not t.is_alive() for t in threading.enumerate() if not t.daemon)
```

Checking daemon status:
```python
t = threading.Thread(target=fn)
t.daemon = True
print(t.daemon)      # True
t.start()
print(t.is_alive())  # True (while running)
```

Inheriting daemon status: a thread spawned by a daemon thread is daemon by default. This means a daemon "manager" thread that creates worker threads produces daemon workers — all will be killed when non-daemon threads finish.

---

## How It Connects

Daemon threads are part of the thread lifecycle — they follow the same start/run/terminate states, but termination is forced when the process exits.
[[thread-lifecycle|Thread Lifecycle]]

The `ThreadPoolExecutor` in Python 3.9+ creates daemon threads for its worker pool — the pool does not block program exit if the executor is not explicitly shut down.
[[thread-pool-executor|ThreadPoolExecutor]]

---

## Common Misconceptions

Misconception 1: "Daemon threads are lighter than regular threads."
Reality: Daemon threads use the same OS thread resources as non-daemon threads — same stack memory, same OS thread handle, same scheduling overhead. The only difference is in process exit behavior. There is no resource advantage to making a thread daemon.

Misconception 2: "A daemon thread's `finally` block will run on process exit."
Reality: Daemon threads are killed abruptly — `finally` blocks that have not yet been entered will not execute. If the daemon thread is inside a `try/finally` block when it is killed, the `finally` may or may not execute depending on the OS and Python implementation. Never rely on cleanup in daemon threads.

---

## Why It Matters in Practice

Background monitor thread pattern:

```python
import threading
import time

def heartbeat_sender():
    while True:
        send_heartbeat()
        time.sleep(30)

t = threading.Thread(target=heartbeat_sender, daemon=True)
t.start()

# Main program continues; heartbeat runs in background
# When main program exits, heartbeat thread is killed automatically
```

Without `daemon=True`, the process would hang after the main code finishes, waiting for the heartbeat thread's infinite loop.

Log flush thread: `logging.handlers.MemoryHandler` and similar buffered handlers can be flushed in a daemon thread. However, since the thread may be killed before the final flush, configure `atexit.register(handler.flush)` in the main thread to ensure the last batch is written on clean exit.

---

## Interview Angle

Common question forms:
- "What is a daemon thread?"
- "When would you use a daemon thread?"

Answer frame: A daemon thread is killed when all non-daemon threads finish — it does not prevent process exit. Set with `t.daemon = True` before `start()`. Use for background tasks that can be abandoned without data loss: heartbeats, monitors, log batchers. Do NOT use for work that must complete: DB writes, file flushes, connection cleanup — daemon threads are killed without running `finally` blocks. Default threads are non-daemon (process waits for them).

---

## Related Notes

- [[thread-lifecycle|Thread Lifecycle]]
- [[thread-pool-executor|ThreadPoolExecutor]]
- [[threads|Threads in Python]]
