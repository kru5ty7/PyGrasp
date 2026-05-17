---
title: 01 - OS Processes and Threads
description: "An OS process is an isolated program instance with its own memory space; a thread is a unit of execution within a process sharing its memory — Python's `threading` maps to OS threads, `multiprocessing` creates OS processes; understanding the OS-level distinction explains Python's GIL, IPC requirements, and memory model for concurrent code."
tags: [processes, threads, OS, memory-space, IPC, context-switching, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# OS Processes and Threads

> An OS process is an isolated program instance with its own memory space; a thread is a unit of execution within a process sharing its memory — Python's `threading` maps to OS threads, `multiprocessing` creates OS processes; understanding the OS-level distinction explains Python's GIL, IPC requirements, and memory model for concurrent code.

---

## Quick Reference

**Core idea:**
- **Process**: independent program instance; own virtual address space, file descriptors, signal handlers; created by `fork()` or `CreateProcess()` (Windows)
- **Thread**: lightweight execution unit within a process; shares the process's memory, file descriptors, and globals; created by `pthread_create()` (Unix) or `CreateThread()` (Windows)
- Python's `threading.Thread` → OS thread in the same process (shared memory, subject to GIL)
- Python's `multiprocessing.Process` → OS process (separate memory; GIL is independent per process)
- Thread creation is faster and cheaper than process creation; thread communication is trivial (shared memory) but unsafe without locks; process communication requires IPC

**Tricky points:**
- Threads share memory — global variables, module-level state, heap objects are all shared; concurrent writes without locks cause data corruption
- Processes do not share memory by default — after `fork()`, the child gets a copy of the parent's memory; subsequent writes to shared objects in one process are invisible to the other
- `fork()` on Unix copies the parent's state including open sockets, locks (partially held), and non-fork-safe state — forking a process that has open database connections or active threads can cause deadlocks or corruption
- On macOS (Python 3.8+) and Windows, the default multiprocessing start method is `spawn` (not `fork`) — the child starts fresh by importing `__main__`, which requires the `if __name__ == "__main__":` guard
- Thread stacks are typically 1–8 MB each (OS-dependent) — creating thousands of threads exhausts virtual memory; asyncio coroutines use ~few KB each

---

## What It Is

Think of processes and threads like a building with offices. Each office (process) is self-contained — it has its own furniture, files, and phone line. Workers in an office (threads) share all the office's resources — they use the same desk, read from the same filing cabinet, and can talk to each other instantly. But one office cannot read another office's filing cabinet directly — they need to send messages through the mail room (IPC). The GIL is like a token that only one worker in the building can hold at a time to use the Python interpreter — multiple offices each have their own token.

Understanding the OS-level model explains Python's behavior. Threads share memory so Python can't safely have two threads modify a reference count simultaneously — hence the GIL. Processes are isolated so `multiprocessing` must explicitly serialize (pickle) objects to pass them across the process boundary. Thread creation is cheap (allocate a stack, register with the scheduler) while process creation copies the entire address space (or spawns and re-imports).

---

## How It Actually Works

On Linux, both processes and threads are represented as `task_struct` objects in the kernel — the distinction is in how much state is shared. `clone()` with different flags creates either a thread (sharing memory, file descriptors) or a process (not sharing).

Python's `threading.Thread` calls `pthread_create()` on Unix, which allocates a stack and registers the new thread with the OS scheduler. The new thread is part of the same process and shares `sys.modules`, `sys.path`, the interpreter state, and all Python objects.

Python's `multiprocessing.Process` calls `os.fork()` on Unix (creating a copy of the process memory) or uses `spawn` (starting a new Python interpreter and re-importing the target module). After fork, both processes run independently — writes to objects in one process do not affect the other.

Memory layout:
- Process: virtual address space divided into text (code), data (globals), heap (dynamic allocations), and stack (per-thread)
- Threads within a process: each has its own stack; all share the same text, data, and heap regions
- Python heap (managed by pymalloc): shared among all threads in a process; protected by the GIL during memory operations

On Windows, there is no `fork()` — `multiprocessing` always uses `spawn` (start fresh), which is why the `if __name__ == "__main__":` guard is required to prevent infinite spawning.

---

## How It Connects

The GIL exists because threads share the Python interpreter state — without a lock, concurrent threads would corrupt reference counts and the interpreter's internal data structures.
[[gil|The GIL]]

Inter-Process Communication mechanisms (Queues, Pipes, shared memory) are needed because processes have isolated memory spaces — objects must be serialized and transmitted between them.
[[inter-process-communication|Inter-Process Communication]]

---

## Common Misconceptions

Misconception 1: "Python threads share all memory so communication is free."
Reality: Thread communication via shared memory is fast but requires explicit synchronization (locks, semaphores). Without synchronization, concurrent reads and writes to shared objects cause race conditions — partial writes, stale reads, and data corruption. "Shared memory" is an opportunity, not a guarantee of safety.

Misconception 2: "Process creation is always too expensive for short-lived tasks."
Reality: Process creation via `fork()` on Linux uses copy-on-write — memory pages are not copied until a process writes to them, making fork cheaper than it sounds for read-heavy scenarios. `ProcessPoolExecutor` amortizes process creation cost by reusing a pool of workers. The real overhead is the startup time when using `spawn` (re-importing the module).

---

## Why It Matters in Practice

Choosing between threads and processes depends on the use case. CPU-bound work: processes (each has its own GIL). I/O-bound work: threads or asyncio (shared memory for fast communication, GIL released during I/O). Long-running background work: processes (isolation prevents bugs in one worker from corrupting others).

`fork()` safety: forking a process that uses threads (e.g., has a background database connection pool) is dangerous — the child inherits partially-acquired locks and open connections in inconsistent states. The `multiprocessing` `spawn` and `forkserver` start methods avoid this by not forking a thread-using process.

---

## Interview Angle

Common question forms:
- "What is the difference between a process and a thread?"
- "Why does multiprocessing require the `if __name__ == '__main__':` guard?"

Answer frame: Processes have isolated memory spaces; threads share memory within a process. Python threads → OS threads (GIL-limited); Python multiprocessing → OS processes (GIL-independent). Threads communicate via shared objects but need locks. Processes communicate via IPC and require serialization. The `if __name__ == "__main__":` guard prevents infinite spawning on Windows/macOS where multiprocessing uses `spawn` (re-imports `__main__`).

---

## Related Notes

- [[gil|The GIL]]
- [[concurrency-vs-parallelism|Concurrency vs Parallelism]]
- [[context-switching|Context Switching]]
- [[threads|Threads in Python]]
