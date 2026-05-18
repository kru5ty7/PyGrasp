---
title: 03 - The Event Loop
description: The event loop is the scheduler at the heart of async Python  -  a single-threaded loop that monitors I/O readiness, resumes suspended coroutines, and runs callbacks, turning a single OS thread into a coordinator for thousands of concurrent I/O operations.
tags: [event-loop, asyncio, coroutines, I/O, epoll, layer-2, concurrency]
status: draft
difficulty: advanced
layer: 2
domain: concurrency
created: 2026-05-17
---

# The Event Loop

> The event loop is the scheduler at the heart of async Python  -  a single-threaded loop that monitors I/O readiness, resumes suspended coroutines, and runs callbacks, turning a single OS thread into a coordinator for thousands of concurrent I/O operations.

---

## Quick Reference

**Core idea:**
- The event loop is a **`while True` loop** that: runs ready callbacks/tasks -> asks the OS for I/O events -> wakes up tasks whose I/O is ready -> repeat
- It uses the OS's **I/O multiplexing API**: `epoll` (Linux), `kqueue` (macOS/BSD), `IOCP` (Windows)
- **One event loop per thread**  -  the standard pattern is one event loop on the main thread
- `asyncio.get_running_loop()` returns the currently running loop; `asyncio.get_event_loop()` is deprecated for most uses
- A coroutine runs **until it hits an `await`**  -  then it suspends and the event loop picks the next ready task

**Tricky points:**
- The event loop is **single-threaded**  -  calling blocking code (file I/O, CPU work, `time.sleep`) blocks the entire loop and all coroutines freeze
- `asyncio.run()` creates a **new** event loop every time  -  it cannot be called from inside a running loop
- `loop.call_soon(callback)` schedules a callback for the next iteration; `loop.call_later(delay, callback)` schedules after a delay  -  these are lower-level than tasks
- The `asyncio` event loop is **pluggable**  -  `uvloop` is a drop-in replacement built on libuv that is typically 2 - 4× faster
- `loop.run_in_executor(None, blocking_fn)` runs `blocking_fn` in a thread pool **without blocking the event loop**

---

## What It Is

Picture an air traffic control tower at a busy airport. The controller does not fly any planes  -  they coordinate all of them from a single position. They watch a radar screen showing every plane's status, communicate with pilots who are ready to land or take off, and direct them one action at a time. When a plane is holding (waiting for a runway), the controller moves on to another plane that is ready. When the holding plane is cleared, the controller comes back to it. One controller, many planes, all moving forward without any of them being ignored for long. The event loop is that controller, and coroutines are the planes.

The event loop is the engine that makes async Python work. It is a loop  -  literally a `while True`  -  that runs on a single OS thread. Each iteration of the loop does three things. First, it runs all tasks and callbacks that are currently ready to execute. Second, it asks the OS which I/O operations have completed (which file descriptors are readable, which are writable, which timers have fired). Third, it takes the coroutines that were waiting for those I/O operations and marks them as ready to run on the next iteration.

The crucial word is "cooperative." The event loop is only in control when coroutines voluntarily yield by hitting an `await`. Between `await` expressions, a coroutine runs without interruption. The event loop cannot pre-empt a coroutine mid-execution the way an OS pre-empts threads. This means the event loop's responsiveness depends entirely on coroutines being well-behaved  -  reaching `await` frequently enough that other tasks get a turn. A coroutine that does CPU-heavy work without any `await` blocks the entire event loop for the duration.

---

## How It Actually Works

At the OS level, the event loop is built on an I/O readiness notification API. On Linux, this is `epoll`. On macOS and BSD, it is `kqueue`. On Windows, it is I/O Completion Ports (IOCP). These APIs work by registering a set of file descriptors with the kernel and calling a blocking function (`epoll_wait`, `kevent`, etc.) that returns when any of the registered descriptors becomes ready for reading or writing. The event loop calls this function with a timeout  -  if no I/O events occur within the timeout period, the function returns anyway, allowing the loop to run any scheduled timers.

CPython's `asyncio` event loop implementation lives in `Lib/asyncio/selector_events.py` (for the selector-based implementation, used on Unix) and `Lib/asyncio/proactor_events.py` (for Windows IOCP). The `SelectorEventLoop` wraps Python's `selectors` module, which in turn wraps `select`/`poll`/`epoll`/`kqueue` depending on the platform. The loop maintains a `_ready` deque of callbacks to execute on the current iteration and a `_scheduled` heap of timed callbacks sorted by execution time.

When a coroutine awaits a socket read, for example, the following chain occurs: the coroutine calls `await reader.read(n)`. The StreamReader's read method creates a `Future` and suspends by yielding it to the event loop. The event loop receives the `Future` and registers the underlying socket's file descriptor with the OS's I/O multiplexer for read readiness. When the OS indicates the socket is readable, the event loop resolves the `Future`, which triggers the callback that resumes the waiting coroutine. The coroutine wakes up with the read data available. The entire round-trip  -  from `await` to resumption  -  involves no threads and no OS-level blocking from the Python program's perspective.

`uvloop` replaces CPython's event loop with one built on `libuv`, the same C library that Node.js uses. It implements the same `asyncio` event loop interface but at the C level with zero Python overhead for I/O callbacks. For high-throughput async servers, `uvloop` is a significant speedup because I/O callback processing is entirely in C, bypassing the Python interpreter for the inner loop.

---

## How It Connects

Coroutines are the work units the event loop schedules. Every `await` is a yield point where the coroutine hands control back to the event loop. The event loop's job is to decide which coroutine to resume next  -  and that decision is driven by which I/O operations have completed. The coroutine and the event loop are two sides of the same mechanism.
[[coroutines|Coroutines]]

`asyncio` is the standard library that provides the concrete event loop implementation, the `Task` scheduler, and all the async primitives. The event loop is the engine; `asyncio` is the full car. Understanding the event loop conceptually is the prerequisite for working effectively with `asyncio`'s task scheduling API.
[[asyncio|Asyncio]]

When async code needs to call blocking functions  -  database drivers that are not async-aware, CPU-bound computation  -  `run_in_executor()` offloads the work to a thread pool, allowing the event loop to continue running other coroutines. This is the bridge between the async world and the synchronous world.
[[thread-pool-executor|ThreadPoolExecutor]]

---

## Common Misconceptions

Misconception 1: "The event loop runs coroutines in parallel on multiple threads."
Reality: The standard asyncio event loop runs on a single OS thread. Coroutines do not run in parallel  -  only one coroutine executes at any given instant. The event loop provides concurrency (multiple coroutines making progress) not parallelism (multiple coroutines executing simultaneously). Parallelism requires multiple threads or multiple processes.

Misconception 2: "The event loop automatically handles blocking code."
Reality: The event loop has no way to pre-empt a coroutine. If a coroutine calls `time.sleep(5)` or reads a large file with the standard `open()`, the entire event loop freezes for the duration of that call. No other coroutines run. The event loop only interleaves coroutines at explicit `await` points. Blocking code must be moved to a thread via `asyncio.to_thread()` or `loop.run_in_executor()`.

---

## Why It Matters in Practice

The event loop is why async Python servers can handle thousands of concurrent connections without thousands of threads. A traditional synchronous web server assigns one thread per connection  -  at a thousand connections, it needs a thousand threads, each consuming stack memory and OS scheduling resources. An async server handles thousands of connections in a single event loop thread, because most connections spend most of their time waiting for network I/O, and the event loop processes that waiting efficiently through the OS's I/O multiplexer.

Understanding the event loop also explains a class of bugs unique to async code. Any synchronous blocking call  -  a poorly chosen library, a DNS lookup that is not async-aware, a CPU-intensive computation  -  can freeze the event loop for an unpredictable duration. In a web server, this means all in-flight requests stall while one request does blocking work. The fix  -  running blocking work via `run_in_executor()`  -  is only obvious if you understand that the event loop is single-threaded and cannot tolerate blocking.

---

## Interview Angle

Common question forms:
- "How does the asyncio event loop work?"
- "What happens when you call a blocking function in async code?"
- "How does the event loop handle thousands of connections with one thread?"

Answer frame: Describe the loop as a `while True` that runs ready callbacks, calls the OS I/O multiplexer (epoll/kqueue/IOCP), and resumes coroutines whose I/O completed. Emphasize single-threaded and cooperative: coroutines run until they `await`, then yield to the loop. Explain the blocking-code problem: no `await` means no yield means the loop freezes. Explain the scale advantage: thousands of I/O operations registered with the OS, zero threads-per-connection overhead.

---

## Related Notes

- [[coroutines|Coroutines]]
- [[async-await|Async and Await]]
- [[asyncio|Asyncio]]
- [[thread-pool-executor|ThreadPoolExecutor]]
