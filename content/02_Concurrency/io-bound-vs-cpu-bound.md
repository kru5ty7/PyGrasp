---
title: I/O Bound vs CPU Bound
description: I/O-bound tasks spend most of their time waiting for external operations; CPU-bound tasks spend most of their time computing — this distinction determines which Python concurrency tool will actually help and which will do nothing.
tags: [io-bound, cpu-bound, concurrency, performance, GIL, layer-2, concurrency]
status: draft
difficulty: beginner
layer: 2
domain: concurrency
created: 2026-05-17
---

# I/O Bound vs CPU Bound

> I/O-bound tasks spend most of their time waiting for external operations; CPU-bound tasks spend most of their time computing — this distinction determines which Python concurrency tool will actually help and which will do nothing.

---

## Quick Reference

**Core idea:**
- **I/O-bound**: the bottleneck is waiting — for the network, disk, database, external API
- **CPU-bound**: the bottleneck is computation — crunching numbers, image processing, parsing, encryption
- **Threading / async**: help with I/O-bound work — while one task waits, another runs (GIL released during I/O)
- **Multiprocessing**: helps with CPU-bound work — each process has its own GIL and runs on a separate CPU core
- **Profile first**: most programs have both kinds of work; identify where time is actually spent before choosing

**Tricky points:**
- Adding threads to a **CPU-bound** Python program can make it **slower** — thread switching overhead + GIL contention with no parallelism
- A task that does I/O inside a tight loop may still be **CPU-bound** if the I/O responses are instant (e.g., reading from a memory-mapped file)
- `asyncio` does **not** bypass the GIL — it is single-threaded; it only helps with I/O-bound work by overlapping waiting, not computing
- "Use multiprocessing for CPU-bound work" has a hidden cost: **inter-process data transfer requires pickling**, which itself is CPU work

---

## What It Is

Think of a restaurant kitchen. Some orders are slow because the chef has to wait — for the oven to preheat, for the delivery driver to bring the ingredient, for the pasta to boil. The chef is idle during that wait. This is I/O-bound work: the limiting factor is waiting for something external, not the chef's own speed. Other orders are slow because the chef is doing something that requires intense, continuous attention — hand-rolling pasta, deboning a complex cut. The chef cannot do anything else while working. This is CPU-bound work: the limiting factor is the chef's own computation, not any external wait.

In programming, I/O-bound tasks are those where the program spends most of its time waiting for something outside the CPU to complete. Reading a file means waiting for the disk. Making an HTTP request means waiting for the network round trip. Querying a database means waiting for the database server to respond. While the program waits, the CPU is idle — the program has submitted a request and is just sitting there until the response arrives.

CPU-bound tasks are those where the program keeps the CPU busy with actual computation for most of their duration. Compressing a video, training a machine learning model, computing a large matrix multiplication, running a cryptographic hash over a large file — these tasks give the CPU real work to do continuously. The CPU is not waiting for anything external; it is just not done yet.

---

## How It Actually Works

When CPython makes a system call for I/O — reading from a socket, writing to a file, waiting for a subprocess — it releases the GIL before entering the kernel and reacquires it when the call returns. The release happens inside CPython's C code via the `Py_BEGIN_ALLOW_THREADS` macro, which saves the current thread state and sets the thread state pointer to `NULL`, signaling to other threads that they may acquire the GIL. During this window, other Python threads can run their bytecode. This is why threading helps with I/O-bound work: while one thread is inside a blocking I/O syscall with the GIL released, other threads can execute Python code.

For CPU-bound work, the GIL is never voluntarily released by the program — it is only released at the automatic check interval (every 5 milliseconds by default). Thread A runs for 5ms, yields the GIL, thread B runs for 5ms, yields it back. Two threads doing CPU-bound work on a dual-core machine do not run in parallel — they alternate, each running on a single core, each paying the cost of GIL acquisition and context switching. The wall-clock time is worse than a single thread, not better.

The distinction also maps to different operating system behaviors. An I/O operation is typically a system call that blocks — the OS suspends the thread in a wait queue until the I/O device signals completion. A CPU-bound operation is computation that runs without blocking — the OS scheduler pre-empts threads on a time slice, but no voluntary blocking occurs. `asyncio`'s event loop works by asking the OS to monitor multiple I/O descriptors simultaneously (via `select`, `epoll`, or `kqueue`) and notifying the event loop when any of them becomes ready, so the event loop can resume the waiting coroutine. This works because I/O involves waiting; it would not work for CPU-bound tasks because there is nothing to wait on.

---

## How It Connects

The GIL is the reason that the I/O-bound/CPU-bound distinction matters so much in Python specifically. In a language without a GIL, threads provide parallelism for both kinds of work. In CPython, threads only provide parallelism for I/O-bound work. Understanding the GIL is the next step after understanding why this distinction is so consequential for Python.
[[gil|The GIL]]

Async/await is the modern Python mechanism for overlapping I/O-bound operations efficiently on a single thread. It is built on coroutines that yield control back to the event loop when they hit an I/O wait. It only helps with I/O-bound work for the same reason threading does — the bottleneck is waiting, and async replaces that waiting with doing something else.
[[async-await|Async and Await]]

Processes bypass the GIL entirely — each Python process has its own interpreter and its own GIL. For CPU-bound work where you want true parallelism across CPU cores, `multiprocessing` is the right tool. Understanding when to reach for processes versus threads versus async requires knowing what kind of bound your task is.
[[processes|Processes in Python]]

---

## Common Misconceptions

Misconception 1: "Adding threads to my Python program will make it faster."
Reality: Threading speeds up I/O-bound programs. For CPU-bound programs, threading in CPython provides no speedup and often makes things slower due to GIL contention and thread-switching overhead. Before adding threads, identify whether the slow part of your code is waiting (I/O-bound) or computing (CPU-bound). Only then can you choose the right tool.

Misconception 2: "asyncio is faster than threading because it avoids the GIL."
Reality: `asyncio` runs on a single thread — the GIL is still held for all Python bytecode execution. `asyncio` does not avoid the GIL. What it avoids is the overhead of OS thread creation and context switching. It is more efficient than threading for high-concurrency I/O (thousands of simultaneous connections) because goroutine-style cooperative scheduling has lower overhead than OS thread switching at scale. But for CPU-bound work, neither asyncio nor threading helps.

---

## Why It Matters in Practice

Choosing the wrong concurrency model for the wrong kind of work is one of the most common performance mistakes in Python. A web scraper that fetches hundreds of URLs is I/O-bound — threading or async will make it dramatically faster because the bottleneck is network latency, not Python's speed. A data processing pipeline that parses JSON, computes statistics, and transforms records is CPU-bound — threading will not help at all; multiprocessing or a library like NumPy that releases the GIL in C will.

The practical workflow is: profile first. Use `cProfile` or `py-spy` to find where your program actually spends its time. If the hot spots are syscalls and I/O waits, reach for async or threading. If the hot spots are Python bytecode executing arithmetic or string operations, reach for multiprocessing, Cython, or NumPy. If the hot spots are C extension calls that already release the GIL (like NumPy operations), threading may already give you parallelism without any further changes.

---

## Interview Angle

Common question forms:
- "When would you use threading versus multiprocessing in Python?"
- "Why doesn't adding more threads speed up a CPU-intensive Python program?"
- "What is the GIL and how does it affect concurrency choices?"

Answer frame: Define I/O-bound (waiting dominates) and CPU-bound (computation dominates). Explain that CPython's GIL is released during I/O syscalls but held during bytecode execution, making threads useful for I/O-bound but not CPU-bound work. State the rule: I/O-bound → threading or async; CPU-bound → multiprocessing (separate processes, separate GILs, true parallelism). Emphasize that async is single-threaded and only helps with I/O-bound work.

---

## Related Notes

- [[gil|The GIL]]
- [[async-await|Async and Await]]
- [[processes|Processes in Python]]
- [[threads|Threads in Python]]
