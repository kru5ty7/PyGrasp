---
title: Processes in Python
description: Python processes are separate OS processes with fully isolated memory spaces and their own Python interpreter — they bypass the GIL entirely, enabling true CPU parallelism at the cost of higher creation overhead and explicit inter-process communication.
tags: [processes, multiprocessing, GIL, parallelism, IPC, pickling, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Processes in Python

> Python processes are separate OS processes with fully isolated memory spaces and their own Python interpreter — they bypass the GIL entirely, enabling true CPU parallelism at the cost of higher creation overhead and explicit inter-process communication.

---

## Quick Reference

**Core idea:**
- Each Python process has its own **memory space, Python interpreter, and GIL** — they cannot interfere with each other
- The `multiprocessing` module provides: `Process`, `Pool`, `Queue`, `Pipe`, `Manager`, `Value`, `Array`
- Data between processes must be **serialized (pickled)** — not all Python objects are picklable
- Process creation: `fork` (Unix, copies parent memory), `spawn` (all platforms, starts fresh), `forkserver` (Unix only)
- `ProcessPoolExecutor` from `concurrent.futures` provides a higher-level API mirroring `ThreadPoolExecutor`

**Tricky points:**
- `fork` on macOS with multiple threads is **unsafe** (known deadlock risk with Objective-C runtime) — Python 3.8+ defaults to `spawn` on macOS
- **Pickling is the hidden tax** — sending a large object to a worker process must serialize it, transfer it, and deserialize it; for small tasks this cost can exceed the computation
- `multiprocessing.Pool.map()` vs `concurrent.futures.ProcessPoolExecutor.map()` — similar API, but `Pool` is older; `ProcessPoolExecutor` integrates with `asyncio` via `loop.run_in_executor()`
- In a spawned process, **module-level code runs again** — protect process creation code with `if __name__ == "__main__":` or it will loop infinitely on Windows/macOS
- `Manager` objects for shared state use a **separate server process** — operations on them are slow compared to in-process data structures

---

## What It Is

Think of a company with separate offices in different buildings. Each office has its own staff, its own files, and its own keys. One office burning down does not affect the others. If offices need to share information, they must physically send documents back and forth — there is no shared filing system. Python processes are like those separate offices. Each process is a completely independent running program: its own memory, its own copy of Python, its own GIL. Two processes can run Python code on two different CPU cores simultaneously, with no interference, because they do not share any state.

The key difference from threads is isolation. Threads share a process's memory — all threads see the same Python objects, the same global variables, the same open files. Processes do not share anything by default. A variable modified in process A is invisible to process B unless explicitly communicated. This isolation is what allows processes to run truly in parallel: there is no shared state to protect, no GIL to fight over, no lock contention. Each process runs its own Python interpreter with its own GIL, completely independently.

The `multiprocessing` module creates and manages Python processes. `multiprocessing.Process` is the fundamental building block: you give it a Python function to run and it forks or spawns a new OS process to execute that function. `multiprocessing.Pool` creates a pool of worker processes and distributes work to them. The `concurrent.futures.ProcessPoolExecutor` provides the same Pool functionality with a cleaner API. These tools exist because for CPU-bound Python work, processes are the only built-in mechanism that provides true parallelism.

---

## How It Actually Works

When you create a `multiprocessing.Process` and call `start()`, Python creates a new OS process using one of three start methods, selectable via `multiprocessing.set_start_method()`.

With `fork`, the OS duplicates the parent process's entire memory space using copy-on-write semantics. The child process starts with an exact copy of the parent's state — all objects, all file descriptors, all module-level globals. The child then diverges as it runs its own code. Fork is fast (the copy is virtual until writes occur) but dangerous if the parent has multiple threads, because fork only copies the calling thread. Any other threads — including those holding locks — simply vanish from the child's perspective. The child inherits locked mutexes with no threads to unlock them, leading to potential deadlock.

With `spawn`, Python starts a completely fresh Python interpreter in the child process, with no copy of the parent's state. The child imports the `multiprocessing` module and the target module from scratch, then calls the target function with the provided arguments. The arguments must be passed by value, serialized using `pickle`. Spawn is slower than fork (full Python startup from scratch) but safe with threads and the default on Windows (which has no `fork`) and macOS (since Python 3.8).

Inter-process communication is handled by `multiprocessing.Queue` and `multiprocessing.Pipe`. Both use OS-level IPC mechanisms underneath: pipes (byte streams) with Python's `pickle` serialization layered on top. Sending an object through a Queue pickles it in the sender, writes the bytes to the pipe, and unpickles it in the receiver. This means the cost of sending an object includes serialization time proportional to the object's size. Shared memory alternatives — `multiprocessing.Value`, `multiprocessing.Array`, and `multiprocessing.shared_memory` — bypass pickling by mapping raw memory shared between processes, but they only work with simple C types or bytes.

---

## How It Connects

Processes exist specifically to bypass the GIL. Understanding what the GIL is and why it prevents CPU parallelism with threads is what makes the process model's value clear. Each process has its own GIL, so two processes executing CPU-bound code run on two separate CPUs with no interference.
[[gil|The GIL]]

Choosing between threads and processes requires understanding both models and their trade-offs. Threads share memory (easy communication, race condition risk, GIL limitation). Processes have isolated memory (safe, truly parallel, expensive communication). The thread-vs-process note provides the side-by-side comparison.
[[thread-vs-process|Threads vs Processes]]

`ProcessPoolExecutor` provides the same high-level API as `ThreadPoolExecutor` but uses processes instead of threads. It integrates with `asyncio` via `loop.run_in_executor()`, which is the standard way to run CPU-bound work from an async program without blocking the event loop.
[[thread-pool-executor|ThreadPoolExecutor]]

---

## Common Misconceptions

Misconception 1: "Multiprocessing is always the right choice for parallelism in Python."
Reality: Processes are the right choice for CPU-bound work in pure Python. But they come with significant overhead: process creation takes milliseconds, inter-process communication requires pickling, and shared state requires explicit synchronization via `Manager` or shared memory. For I/O-bound work, threads or async/await are far more appropriate — they have much lower overhead and simpler communication. And for CPU-bound work, C extensions or libraries like NumPy that release the GIL can provide parallelism within a single process.

Misconception 2: "A `multiprocessing.Queue` is as fast as passing objects directly between threads."
Reality: A Queue between processes requires pickling the object, writing bytes to a pipe, reading bytes from the pipe, and unpickling. This is orders of magnitude slower than passing a reference between threads. For small objects (numbers, short strings), the cost is manageable. For large objects (large arrays, complex graphs), the IPC overhead can exceed the computation you were trying to parallelize. This is the "pickling tax" and it must be factored into any performance analysis of multiprocessing code.

---

## Why It Matters in Practice

Processes are the correct tool when you have CPU-bound Python code that you want to run in parallel across multiple CPU cores. Data processing pipelines that parse large files, simulation codes, parallel test runners — these benefit from `ProcessPoolExecutor.map()` or `multiprocessing.Pool.map()`. The worker function receives input, does computation, and returns output — all via pickle. As long as the computation time dominates the serialization overhead, you get near-linear speedup with the number of cores.

The `if __name__ == "__main__":` guard is not optional when using `spawn` start method (Windows and macOS default). When a worker process is spawned, Python re-imports the main module to load the target function. If the process creation code runs at module level (outside the guard), each worker spawns more workers, which spawn more workers — a process fork bomb. The guard prevents this by ensuring process creation code only runs in the original parent process, not in spawned workers.

---

## Interview Angle

Common question forms:
- "How do you achieve parallelism in Python?"
- "What is the difference between `multiprocessing.Process` and `threading.Thread`?"
- "What is the `if __name__ == '__main__':` guard for?"

Answer frame: Start with why processes exist — GIL prevents thread parallelism for CPU-bound work; each process has its own Python interpreter and GIL. Explain isolation: no shared memory, communication via pickling. Describe start methods: fork (fast, copies parent, risky with threads), spawn (safe, fresh interpreter, slower). Address the `__main__` guard: spawn re-imports the main module; the guard prevents process-spawning code from running in worker processes.

---

## Related Notes

- [[gil|The GIL]]
- [[io-bound-vs-cpu-bound|I/O Bound vs CPU Bound]]
- [[thread-vs-process|Threads vs Processes]]
- [[thread-pool-executor|ThreadPoolExecutor]]
