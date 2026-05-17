---
title: The multiprocessing Module
description: Python's `multiprocessing` module provides Process, Pool, Queue, and Pipe primitives for creating and coordinating OS processes — each process runs a separate Python interpreter with its own GIL, enabling true CPU parallelism; objects are communicated via pickling.
tags: [multiprocessing, Process, Pool, Queue, Pipe, pickling, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# The multiprocessing Module

> Python's `multiprocessing` module provides Process, Pool, Queue, and Pipe primitives for creating and coordinating OS processes — each process runs a separate Python interpreter with its own GIL, enabling true CPU parallelism; objects are communicated via pickling.

---

## Quick Reference

**Core idea:**
- `multiprocessing.Process(target=fn, args=())` — creates a child process; `p.start()` starts it; `p.join()` waits for completion
- `multiprocessing.Pool(n)` — creates a pool of `n` worker processes; `.map()`, `.apply_async()`, `.starmap()` for task distribution
- `multiprocessing.Queue()` — inter-process queue; objects are serialized with `pickle` to cross process boundary
- `multiprocessing.Pipe()` — returns `(conn1, conn2)` pair; `conn.send(obj)` / `conn.recv()` for bidirectional communication
- Start methods: `spawn` (default Windows/macOS), `fork` (default Linux), `forkserver` — set with `multiprocessing.set_start_method()`

**Tricky points:**
- All objects passed between processes must be **picklable** — lambdas, closures, database connections, file handles are NOT picklable; use module-level functions as targets
- `if __name__ == "__main__":` is required on Windows/macOS (spawn start method) — without it, spawning a new process re-imports `__main__` and recursively spawns more processes
- `Pool.map()` is synchronous — it blocks until all results are ready; use `Pool.map_async()` for non-blocking
- Worker process exceptions are caught and re-raised in the parent when the result is accessed — check `.get()` in a try/except
- `multiprocessing.Manager()` provides proxy objects (dict, list, Value, Array) that are safe to share across processes — but they are much slower than regular objects due to IPC overhead

---

## What It Is

Think of a research lab with multiple scientists (processes). Each has their own lab (memory space, GIL) and can work independently in parallel. The head researcher (main process) hands them experiments (tasks) and collects results. But scientists cannot share reagents directly — they must describe them in a protocol (pickle) and physically transfer them to the other lab. Each lab has its own supply of common reagents (Python interpreter, stdlib), so setup has some cost.

The `multiprocessing` module is the framework for managing this distributed lab. `Process` is one scientist hired and directed. `Pool` is an employment agency providing a pre-staffed team. `Queue` and `Pipe` are the messaging systems for handing experiments and collecting results.

---

## How It Actually Works

`Process(target=fn, args=(arg,))` internals:
- `p.start()` calls the platform's process creation mechanism based on start method
- `spawn`: starts a fresh Python interpreter, imports the module containing `fn`, and calls `fn(arg)` — requires `fn` to be importable (module-level function)
- `fork`: duplicates the parent process memory — child starts from the `fork` call point with parent's memory; fast but unsafe with threads
- `forkserver`: a pre-forked server process creates new children via `fork` without the thread-safety issues of direct `fork`

Pickling requirement: all arguments to `target`, return values from workers, and objects sent via `Queue`/`Pipe` must be picklable. Python's `pickle` serializes the object to bytes, sends the bytes through the IPC channel, and deserializes on the other side. Objects with open file handles, OS-level resources, or closures over non-picklable state cannot be pickled.

`Pool.map(fn, items)`:
```python
with Pool(4) as pool:
    results = pool.map(compute, large_list)
# Each item in large_list is sent to a worker process
# Results are collected in order
```

`Pool.map_async(fn, items).get()` for non-blocking dispatch. `Pool.starmap(fn, pairs)` for multi-argument functions.

`Pool` context manager: `with Pool(4) as pool:` calls `pool.terminate()` on exit if still running. For graceful shutdown: `pool.close()` (no new tasks) + `pool.join()` (wait for all tasks).

---

## How It Connects

`multiprocessing.Process` creates OS processes — understanding what makes processes different from threads (isolated memory, pickling requirement) is essential context.
[[os-processes-and-threads|OS Processes and Threads]]

`concurrent.futures.ProcessPoolExecutor` is the modern high-level interface over a process pool — it uses `multiprocessing.Pool` internally with a futures-based API.
[[concurrent-futures|concurrent.futures]]

---

## Common Misconceptions

Misconception 1: "`multiprocessing.Pool.map()` always uses all available CPU cores."
Reality: `Pool(n)` creates exactly `n` workers. `Pool()` with no argument defaults to `os.cpu_count()`, which uses all logical CPUs. But "all cores" does not mean "all performance" — the bottleneck may be IPC overhead (pickling), memory bandwidth, or the sequential portion of the task. Profile to determine whether adding more processes helps.

Misconception 2: "Exceptions in worker processes crash the parent."
Reality: Exceptions in workers are caught and stored. They are re-raised when the parent accesses the result — `result.get()` for async calls, or `pool.map()` propagates the first exception encountered. The parent process continues running; only result access triggers the re-raise.

---

## Why It Matters in Practice

The canonical use case: CPU-bound transformation over a large dataset.

```python
from multiprocessing import Pool
import os

def process_record(record):
    # CPU-intensive computation
    return transform(record)

if __name__ == "__main__":
    with Pool(os.cpu_count()) as pool:
        results = pool.map(process_record, records)
```

The dataset is split across `cpu_count()` worker processes, each processing a chunk independently. If the processing is truly CPU-bound and pickling overhead is small relative to computation time, speedup is roughly linear with CPU count.

Avoid for: I/O-bound work (use asyncio or threads — process overhead is not justified), very small tasks (pickling overhead exceeds computation time), or work requiring frequent communication between workers.

---

## Interview Angle

Common question forms:
- "How do you parallelize CPU-bound work in Python?"
- "Why must objects be picklable for multiprocessing?"

Answer frame: `multiprocessing` creates separate OS processes — each has its own Python interpreter and GIL, enabling true CPU parallelism. Objects are passed via IPC using pickle serialization. `Pool.map(fn, items)` distributes work across a process pool and collects results. Common pitfall: lambdas and closures are not picklable — use module-level functions as targets. Always wrap multiprocessing code in `if __name__ == "__main__":` on Windows/macOS.

---

## Related Notes

- [[processes|Processes in Python]]
- [[os-processes-and-threads|OS Processes and Threads]]
- [[concurrent-futures|concurrent.futures]]
- [[inter-process-communication|Inter-Process Communication]]
