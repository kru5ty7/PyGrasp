---
title: Learning Path — Concurrency
description: How Python handles threads, processes, and async — including the GIL, the event loop, and when to use each model.
tags: [moc, learning-path, concurrency, layer-2]
---

# Learning Path — Concurrency

> The GIL, threads, processes, and async/await — why they exist, how they differ, and when to reach for each. Assumes Layer 0 (CPython internals).

---

## Layer 2a — Foundations

1. [[io-bound-vs-cpu-bound|I/O Bound vs CPU Bound]]
2. [[concurrency-vs-parallelism|Concurrency vs Parallelism]]
3. [[os-processes-and-threads|OS Processes and Threads]]
4. [[context-switching|Context Switching]]
5. [[gil|The GIL]]
6. [[gil-internals|GIL Internals]]
7. [[free-threaded-python|Free-Threaded Python (3.13+)]]

---

## Layer 2b — Threads

1. [[threads|Threads in Python]]
2. [[thread-lifecycle|Thread Lifecycle]]
3. [[race-conditions|Race Conditions]]
4. [[locks|Locks]]
5. [[deadlocks|Deadlocks]]
6. [[semaphores|Semaphores]]
7. [[thread-safe-queues|Thread-Safe Queues]]
8. [[thread-pool-executor|ThreadPoolExecutor]]
9. [[daemon-threads|Daemon Threads]]
10. [[thread-local-storage|Thread Local Storage]]

---

## Layer 2c — Processes

1. [[processes|Processes in Python]]
2. [[multiprocessing-module|The multiprocessing Module]]
3. [[process-pool|Process Pool]]
4. [[inter-process-communication|Inter-Process Communication]]
5. [[shared-memory|Shared Memory]]
6. [[thread-vs-process|Threads vs Processes]]
7. [[concurrent-futures|concurrent.futures]]

---

## Layer 2d — Async

1. [[coroutines|Coroutines]]
2. [[async-await|Async and Await]]
3. [[event-loop|The Event Loop]]
4. [[event-loop-internals|Event Loop Internals]]
5. [[asyncio|Asyncio]]
6. [[asyncio-tasks|Asyncio Tasks]]
7. [[asyncio-gather|asyncio.gather and asyncio.wait]]
8. [[async-context-managers|Async Context Managers]]
9. [[async-generators|Async Generators]]
10. [[async-iterators|Async Iterators]]
11. [[asyncio-queues|Asyncio Queues]]
12. [[asyncio-locks|Asyncio Locks]]
13. [[running-sync-in-async|Running Sync Code in Async Context]]
14. [[aiohttp|aiohttp]]
15. [[async-patterns|Common Async Patterns]]
