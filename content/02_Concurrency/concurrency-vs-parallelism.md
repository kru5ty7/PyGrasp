---
title: Concurrency vs Parallelism
description: Concurrency is about dealing with multiple tasks at once by interleaving progress; parallelism is about doing multiple tasks simultaneously on multiple cores — Python achieves concurrency with threads and asyncio (GIL-limited), and true parallelism with multiprocessing.
tags: [concurrency, parallelism, threads, multiprocessing, asyncio, GIL, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Concurrency vs Parallelism

> Concurrency is about dealing with multiple tasks at once by interleaving progress; parallelism is about doing multiple tasks simultaneously on multiple cores — Python achieves concurrency with threads and asyncio (GIL-limited), and true parallelism with multiprocessing.

---

## Quick Reference

**Core idea:**
- **Concurrency**: multiple tasks make progress, but not necessarily at the same instant — achieved by interleaving execution (switching between tasks)
- **Parallelism**: multiple tasks execute at the same instant on separate CPU cores — requires multiple hardware threads/processes
- Python's GIL prevents true parallelism for CPU-bound work within a single process — only one Python thread runs at a time
- **I/O-bound concurrent work**: threads and asyncio both work — the GIL is released during I/O, so other threads/tasks run
- **CPU-bound parallel work**: requires `multiprocessing` — each process has its own GIL, so they run truly in parallel

**Tricky points:**
- Concurrency is not the same as speed — concurrent code can be slower than sequential if the overhead of switching exceeds the benefit
- A single-core machine can have concurrency but never parallelism — tasks interleave on the same core
- asyncio concurrency is **cooperative** — tasks yield explicitly (at `await` points); a CPU-bound coroutine blocks the event loop entirely
- Thread concurrency is **preemptive** (the OS scheduler can interrupt threads) but the GIL limits Python byte-code execution to one thread at a time
- `concurrent.futures` provides a unified interface for both thread and process pools — the underlying mechanism determines whether you get concurrency or parallelism

---

## What It Is

Think of a chef in a kitchen. A chef who starts soup on the stove, then chops vegetables while the soup simmers, then checks the oven — this is concurrency. One chef, multiple tasks interleaved; progress on all fronts, but only one action at a time. Now imagine adding a second chef who simultaneously works on a different dish — that is parallelism. Two agents doing work at the same instant.

Python programs can be the first chef (concurrent, one CPU core), or can spawn sous chefs (parallel, multiple CPU cores via multiprocessing). The confusion arises because threads look like multiple chefs but are secretly one chef in a very fast-switching disguise — the GIL ensures only one thread executes Python code at a time, so threads give the appearance of parallelism for I/O but not for CPU work.

---

## How It Actually Works

Concurrency mechanisms in Python:
1. **Threads** (`threading`) — OS-level threads that Python manages; GIL means only one executes Python bytecode at a time; I/O releases the GIL, so I/O-bound threads run concurrently
2. **asyncio** — single-thread cooperative concurrency; `await` yields control back to the event loop; only one coroutine runs at a time; no GIL concern (no parallel execution)
3. **Multiprocessing** — multiple OS processes, each with its own GIL; truly parallel on multiple cores; communication via IPC (pipes, queues, shared memory)

Decision framework:
- I/O-bound (network, disk, database): use asyncio (lowest overhead) or threads (simpler for legacy code)
- CPU-bound (computation, image processing, ML preprocessing): use multiprocessing (bypass GIL) or C extensions
- Mixed: consider process pool for CPU parts, asyncio for I/O orchestration

Amdahl's Law applies: the maximum speedup from parallelism is limited by the fraction of work that cannot be parallelized. If 20% of work is sequential, maximum theoretical speedup is 5x regardless of CPU count.

---

## How It Connects

The GIL is the constraint that makes concurrency and parallelism different in CPython — understanding why the GIL exists explains why threads give concurrent but not parallel Python execution.
[[gil|The GIL]]

I/O-bound vs CPU-bound is the primary decision factor — the nature of the bottleneck determines which concurrency mechanism is appropriate.
[[io-bound-vs-cpu-bound|I/O Bound vs CPU Bound]]

---

## Common Misconceptions

Misconception 1: "Adding threads to a Python program makes it run faster on multiple cores."
Reality: Python threads do not achieve CPU parallelism due to the GIL — only one thread executes Python bytecode at a time. Threads can improve performance for I/O-bound work (the GIL is released during I/O syscalls), but CPU-bound work with threads may be slower than single-threaded due to GIL contention overhead. Use `multiprocessing` for CPU parallelism.

Misconception 2: "asyncio is faster than threads because it avoids overhead."
Reality: asyncio is more efficient than threads for I/O-bound workloads with many concurrent tasks (thousands of connections) because threads have memory overhead and OS scheduling cost, while coroutines are cheap. But asyncio is not automatically faster — a single slow synchronous call in a coroutine blocks the event loop, while a blocking thread only blocks that one thread. The right choice depends on the workload.

---

## Why It Matters in Practice

A web server handles many simultaneous requests. Each request waits for a database query. Using asyncio: one thread handles thousands of requests concurrently — while one request awaits the DB response, others are processed. Using threads: each request gets its own thread — higher overhead but simpler to reason about. Using processes: overkill for I/O-bound work but necessary if request handling is CPU-intensive.

Data processing pipelines: reading CSV files (I/O) → parsing and transforming (CPU). The I/O phase benefits from concurrency (asyncio or threads); the transformation phase benefits from parallelism (multiprocessing). `concurrent.futures.ProcessPoolExecutor` handles the parallel CPU phase.

---

## Interview Angle

Common question forms:
- "What is the difference between concurrency and parallelism?"
- "How do you achieve parallelism in Python?"

Answer frame: Concurrency = making progress on multiple tasks by interleaving (one at a time); parallelism = multiple tasks executing simultaneously (multiple CPUs). Python's GIL limits threads to concurrent (not parallel) Python bytecode execution. For CPU parallelism: `multiprocessing` (separate processes, each with its own GIL). For I/O concurrency: asyncio (cooperative, single-thread) or threads (preemptive, GIL released during I/O). asyncio scales to thousands of connections; threads scale to dozens before overhead dominates.

---

## Related Notes

- [[gil|The GIL]]
- [[io-bound-vs-cpu-bound|I/O Bound vs CPU Bound]]
- [[threads|Threads in Python]]
- [[asyncio|Asyncio]]
