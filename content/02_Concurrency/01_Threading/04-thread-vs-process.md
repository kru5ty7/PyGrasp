---
title: Threads vs Processes
description: Threads and processes are Python's two OS-level concurrency models — threads share memory and are limited by the GIL; processes are isolated and bypass the GIL — the choice between them comes down to whether your bottleneck is I/O or CPU, and whether you need shared state.
tags: [threads, processes, concurrency, GIL, parallelism, IPC, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Threads vs Processes

> Threads and processes are Python's two OS-level concurrency models — threads share memory and are limited by the GIL; processes are isolated and bypass the GIL — the choice between them comes down to whether your bottleneck is I/O or CPU, and whether you need shared state.

---

## Quick Reference

**Core idea:**
- **Threads**: same memory space, GIL-limited for CPU work, cheap to create (~few ms), great for I/O-bound work
- **Processes**: isolated memory, own GIL, expensive to create (~50–200ms + startup), great for CPU-bound work
- **Shared state**: threads share automatically; processes require explicit IPC (Queue, Pipe, shared memory)
- **Communication cost**: threads pass references (zero copy); processes must pickle and transfer data
- **Failure isolation**: a crash in one thread can kill the whole process; a crashed process does not affect others

**Tricky points:**
- "Processes are always safer" — wrong; process isolation only helps with crashes and memory corruption; logic bugs are equally possible in both
- The **pickling overhead** of inter-process communication can dominate for tasks with small computation but large data
- Threads have **no isolation** — a segfault in a C extension or a corrupted C-level data structure in one thread crashes the whole process
- **Daemon threads** die silently when the main thread exits; **daemon=False processes** (the default) keep running even after the parent exits
- For web scraping or API calls: **threads or async** are the right choice, not processes — the bottleneck is network, not CPU

---

## What It Is

Think of two ways to organize a large team of researchers. The first way: everyone works in the same open-plan office. They can shout across the room, share documents by handing them over, and see each other's screens. This is fast and easy, but they can also distract each other and someone leaving a mess affects everyone. The second way: each researcher has their own separate office with locked doors. To share information, they must make a copy and send it via inter-office mail. It is slower and more formal, but each researcher's workspace is completely independent. Python threads are the open-plan office; Python processes are the separate offices.

Threads are lighter and faster to create than processes. A new thread shares everything with its parent: the same heap, the same loaded modules, the same open file descriptors, the same global variables. Communication between threads is a matter of reading and writing shared variables — no serialization, no copying. The cost is that sharing requires protection. Any shared data that threads read and write must be guarded with locks to prevent race conditions. And the GIL means that only one thread runs Python bytecode at a time, capping CPU parallelism.

Processes are heavier and slower to create, but each is a fully independent program. A new process has its own copy of the Python interpreter, its own memory space, its own GIL. Two processes can run Python bytecode on two different CPU cores simultaneously with no interference. The cost is communication: to pass data between processes, it must be serialized (pickled), sent through a pipe or queue, and deserialized on the other side. Shared state between processes requires explicit shared memory structures.

---

## How It Actually Works

At the OS level, a thread is a lightweight execution context within a process. The OS scheduler can run threads from the same process on different CPU cores simultaneously. What prevents this from giving Python CPU parallelism is the GIL — not the OS. The OS is perfectly happy to run two Python threads on two cores; CPython's GIL ensures only one of them is executing Python bytecode at a given moment.

A process is an independent address space managed by the OS. When a child process is forked, the OS creates a new virtual address space and sets up copy-on-write mappings to the parent's memory pages. Pages are copied only when either process writes to them, so the initial cost of fork is low. When a child process is spawned, a fresh Python interpreter starts, loads the modules it needs, and begins execution — there is no shared memory at all.

The actual performance boundary between threads and processes is determined by three factors: the ratio of I/O wait to CPU time, the size of data passed between workers, and the number of workers. For I/O-bound work (network requests, database queries), threads are clearly better — lower overhead, easier communication, and the GIL is irrelevant because it is released during I/O. For CPU-bound work with small data inputs (e.g., computing prime numbers, compressing a small buffer), processes are clearly better — true parallelism outweighs the startup cost. For CPU-bound work with large data inputs (e.g., processing a 1 GB array in each worker), the pickling cost may negate the parallelism benefit, and a different approach (shared memory, NumPy with GIL-releasing C code) may be needed.

---

## How It Connects

The GIL is the reason threads cannot provide CPU parallelism in CPython and why the thread vs process choice matters at all. Without the GIL, threads would be universally preferable — same parallelism as processes, lower overhead, easier communication. The GIL tips the balance toward processes for CPU-bound work.
[[gil|The GIL]]

The I/O-bound vs CPU-bound classification determines which model to reach for. I/O-bound tasks wait with the GIL released — threads work. CPU-bound tasks hold the GIL throughout — processes are required for parallelism.
[[io-bound-vs-cpu-bound|I/O Bound vs CPU Bound]]

---

## Common Misconceptions

Misconception 1: "Use processes for everything to be safe — they're isolated."
Reality: Processes provide memory isolation, not logic isolation. A bug in your business logic will produce wrong results whether you use threads or processes. Process isolation helps with crashes (one process dying doesn't kill others) and with GIL-limited parallelism. It does not make your algorithms correct, it does not eliminate race conditions in your IPC code, and it adds significant overhead in creation time and communication cost.

Misconception 2: "Threads are always faster because they have less overhead."
Reality: Threads have less creation overhead and cheaper communication. But for CPU-bound work, the GIL serializes their execution, making multiple threads perform worse than a single thread due to GIL contention overhead. Threads are "faster" for I/O-bound work; processes are "faster" for CPU-bound work. The overhead comparison is only one dimension of the trade-off.

---

## Why It Matters in Practice

Most real-world Python programs have a mix of I/O-bound and CPU-bound work. A web application typically handles many concurrent requests (I/O-bound — threads or async) but some of those requests may trigger heavy computation (CPU-bound — processes or worker queues). The typical architecture is: an async web framework handles concurrency at the HTTP layer, with CPU-intensive work offloaded to a separate process pool (Celery, RQ, or `ProcessPoolExecutor`) rather than blocking the web server.

The choice between threads and processes also affects debuggability and error handling. Threads share a process — an unhandled exception in one thread does not automatically terminate others (though it can, depending on the exception type and how the thread was created). A crashed process is completely isolated. For production systems handling sensitive work, process isolation provides a cleaner failure model: a crashed worker process is restarted, while the rest of the system continues.

---

## Interview Angle

Common question forms:
- "When would you use threads versus processes in Python?"
- "Why can't Python use threads for CPU parallelism?"
- "What are the trade-offs between threads and processes?"

Answer frame: Start with the GIL — threads cannot parallelize CPU-bound Python code. State the rule: I/O-bound → threads (or async); CPU-bound → processes. List the key trade-offs: threads share memory (easy comm, race condition risk, GIL limit); processes are isolated (expensive IPC, true parallelism, crash isolation). Mention the pickling cost for processes as the hidden trade-off. Close with the typical production pattern: async for HTTP concurrency, process pools for CPU work.

---

## Related Notes

- [[threads|Threads in Python]]
- [[processes|Processes in Python]]
- [[gil|The GIL]]
- [[io-bound-vs-cpu-bound|I/O Bound vs CPU Bound]]
