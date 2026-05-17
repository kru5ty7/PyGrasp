---
title: 04 - Context Switching
description: Context switching is the OS mechanism of saving a thread's CPU state (registers, stack pointer, program counter) and restoring another's — it is how a single CPU appears to run multiple threads; in Python, the GIL adds an extra layer of switching on top of OS context switching.
tags: [context-switching, threads, GIL, OS-scheduler, sys.getswitchinterval, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Context Switching

> Context switching is the OS mechanism of saving a thread's CPU state (registers, stack pointer, program counter) and restoring another's — it is how a single CPU appears to run multiple threads; in Python, the GIL adds an extra layer of switching on top of OS context switching.

---

## Quick Reference

**Core idea:**
- **Context switch**: OS saves the CPU registers of the running thread, restores the registers of another; the preempted thread resumes later from exactly where it stopped
- OS scheduler determines which thread runs and for how long — on Linux, using the CFS (Completely Fair Scheduler)
- Context switch cost: typically 1–10 microseconds; involves kernel mode transition, cache invalidation, TLB flush
- Python's GIL switch interval: `sys.getswitchinterval()` (default 5ms) — how often Python checks whether another thread should run
- High thread counts increase context switch overhead — 1000 threads with frequent switching can spend more time context switching than doing work

**Tricky points:**
- Context switching is **transparent** to the code being switched — the thread does not know it was preempted and resumed
- The GIL switch is separate from the OS context switch — Python threads release the GIL periodically (every 5ms or at I/O) allowing another Python thread to acquire it; the OS may or may not context switch at the same time
- A sleeping thread (`time.sleep(n)`) yields its time slice voluntarily — efficient; the OS wakes it after `n` seconds
- I/O-blocked threads are moved to a "waiting" state by the OS — they don't consume CPU time but still hold OS resources (stack memory, file descriptors)
- asyncio avoids OS context switches by running everything on one thread — explicit `await` yields are cooperative switches with no OS kernel involvement

---

## What It Is

Think of a checkout clerk at a store with multiple customers. The clerk can only serve one customer at a time, but by quickly switching between them (helping one while another bags their items, then turning to the next) the clerk creates the impression of serving everyone simultaneously. Context switching is the CPU's equivalent: the OS rapidly switches between threads, giving each a slice of CPU time. Since switches happen fast enough (milliseconds), all threads appear to progress simultaneously.

The state that must be saved and restored is the "context" — the CPU's register values (intermediate computation results), the stack pointer (where we are in the current call stack), and the program counter (which instruction comes next). Saving and restoring this context has a cost — both the time to perform the save/restore and the indirect cost of invalidating CPU caches (the registers and stack of the new thread are different from the old).

Python adds its own layer: the GIL must also be acquired before a thread can execute Python bytecode. So a Python thread context switch involves: OS context switch (save/restore registers) + GIL acquisition (atomic operation, potential wait). This double overhead is why Python threads are more expensive than asyncio coroutines for high-concurrency workloads.

---

## How It Actually Works

OS-level context switch sequence:
1. Timer interrupt (or I/O completion, or voluntary yield) triggers the scheduler
2. Scheduler selects the next thread to run (based on priority, fairness, etc.)
3. Current thread's CPU registers are saved to its kernel stack
4. TLB (translation lookaside buffer) and CPU caches may be partially invalidated
5. Next thread's registers are restored from its kernel stack
6. CPU execution resumes at the restored program counter

Python GIL switch mechanism (CPython 3.2+ with the "new GIL"):
- The running thread checks `eval_breaker` flag after every 5ms (configurable via `sys.setswitchinterval(interval)`)
- If another thread is waiting for the GIL, the running thread releases it and signals the waiting thread
- The waiting thread acquires the GIL and begins running
- OS context switch may or may not occur — if both threads are on the same OS thread (impossible for Python threads, but illustrative), no OS switch is needed

The 5ms switch interval means that for CPU-bound work, each Python thread gets at most 5ms of Python execution before yielding. For I/O-bound work, the GIL is released during the I/O syscall — other threads can run while the first waits for the network or disk.

`sys.getswitchinterval()` / `sys.setswitchinterval(0.001)` — decrease the interval for more responsive switching between threads; increase it to reduce switch overhead at the cost of fairness.

---

## How It Connects

The GIL is released between threads at each switch interval and during I/O operations — the GIL switching mechanism rides on top of OS context switching.
[[gil|The GIL]]

asyncio avoids OS context switches entirely by keeping everything on a single thread — the event loop performs cooperative switches at `await` points, which are cheaper than preemptive OS context switches.
[[event-loop|The Event Loop]]

---

## Common Misconceptions

Misconception 1: "More threads = faster program (more parallelism)."
Reality: On a CPU with N cores, N threads can run in parallel. Adding more threads than cores increases context switch overhead without adding parallelism. For CPU-bound work in Python (where the GIL prevents true parallelism anyway), more threads only adds overhead. The optimal thread count for CPU-bound work is 1 (single thread) or use processes instead.

Misconception 2: "Context switching is free."
Reality: A context switch costs 1–10 microseconds of CPU time for OS-level switching. With 10,000 threads, if each is switched every 5ms, that is 2,000 switches per second per thread × 10,000 threads = 20 million switches per second — each costing ~5μs = 100 seconds of pure switch overhead per second. High thread counts can cause the program to spend most of its time switching rather than working (thrashing).

---

## Why It Matters in Practice

Thread count tuning: for I/O-bound workloads with `ThreadPoolExecutor`, setting `max_workers` too high increases context switch overhead and memory usage. A common heuristic for I/O-bound work: `min(32, os.cpu_count() + 4)` (the default in Python 3.8+). Profile to find the optimal count for your specific workload.

asyncio's advantage: for handling thousands of simultaneous connections (web servers, proxies), asyncio uses one thread — zero OS context switches during normal operation. All switching is cooperative and in-process, costing nanoseconds instead of microseconds.

`time.sleep(0)` voluntarily yields the CPU time slice — useful in tight loops to allow other threads to run without sleeping for any meaningful time.

---

## Interview Angle

Common question forms:
- "What is a context switch?"
- "Why does Python have a GIL switch interval?"

Answer frame: A context switch saves the current thread's CPU state (registers, stack pointer, program counter) and restores another's — it is how a single CPU appears to run multiple threads. Cost: 1–10 microseconds plus cache invalidation. Python adds a GIL switch on top: every 5ms (configurable), Python yields the GIL to allow another thread to run. High thread counts amplify context switch overhead — asyncio avoids this by staying on one thread with cooperative user-space switches.

---

## Related Notes

- [[gil|The GIL]]
- [[os-processes-and-threads|OS Processes and Threads]]
- [[threads|Threads in Python]]
- [[event-loop|The Event Loop]]
