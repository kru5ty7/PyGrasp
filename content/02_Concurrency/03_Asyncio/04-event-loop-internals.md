---
title: 04 - Event Loop Internals
description: The asyncio event loop is a selector-based scheduler — it maintains a ready queue of callbacks and a selector that monitors file descriptors for I/O readiness; when I/O completes, the associated coroutine is scheduled to resume; understanding this explains why blocking calls freeze the loop.
tags: [event-loop, asyncio, selector, callbacks, I/O-multiplexing, epoll, kqueue, layer-2, concurrency]
status: draft
difficulty: advanced
layer: 2
domain: concurrency
created: 2026-05-17
---

# Event Loop Internals

> The asyncio event loop is a selector-based scheduler — it maintains a ready queue of callbacks and a selector that monitors file descriptors for I/O readiness; when I/O completes, the associated coroutine is scheduled to resume; understanding this explains why blocking calls freeze the loop.

---

## Quick Reference

**Core idea:**
- The event loop runs on a single OS thread — all coroutines share the thread; no OS context switches between coroutines
- **Selector**: an OS-level I/O multiplexing interface (`epoll` on Linux, `kqueue` on macOS, `IOCP` on Windows) — monitors multiple file descriptors for readiness without blocking
- **Ready queue**: a deque of callbacks scheduled to run in the current iteration
- **I/O selector**: watched file descriptors with associated callbacks; `select()` / `epoll_wait()` is called with a timeout = time until next scheduled callback
- `loop.call_soon(callback)` — schedule a callback for the next iteration; `loop.call_later(delay, callback)` — schedule after `delay` seconds

**Tricky points:**
- A blocking call in a coroutine (e.g., `time.sleep(1)`) blocks the **entire event loop** — no other coroutine runs during this time; all I/O operations stall
- `await asyncio.sleep(1)` registers a callback for 1 second later and yields to the event loop — other coroutines can run
- CPU-bound work in a coroutine blocks the loop proportionally to its execution time; use `loop.run_in_executor()` to offload to a thread or process
- The selector's `timeout` parameter makes the event loop responsive to both I/O completion and scheduled timeouts — the loop wakes up as soon as I/O is ready or a timer fires, whichever comes first
- `asyncio.get_event_loop()` vs `asyncio.get_running_loop()`: the latter raises `RuntimeError` if no loop is running; prefer it inside coroutines; the former may create a new loop if none exists (deprecated behavior in 3.10+)

---

## What It Is

Think of the event loop as a very attentive switchboard operator managing hundreds of phone lines. The operator cannot have a separate conversation on every line simultaneously — there is only one of them. Instead, they scan all lines that have activity (the selector), handle the most urgent ones (the ready queue), and check the others briefly (`select()` call) before looping. When someone starts talking (I/O data arrives on a file descriptor), the operator routes the call (resumes the associated coroutine). The operator's speed comes not from doing many things at once, but from switching between lines so quickly that all callers feel attended to.

The key insight is that real-world network I/O involves waiting. A web server receives a request, sends a database query, and waits for the response. During the wait, the CPU is idle — the OS is handling the network. The event loop uses this waiting time productively by running other coroutines. The selector (`epoll`) allows waiting for hundreds of sockets simultaneously with a single system call.

---

## How It Actually Works

The event loop's main iteration (`_run_once()` in CPython's asyncio):

```
1. Process the ready queue:
   while ready_queue:
       callback = ready_queue.popleft()
       callback()

2. Determine timeout:
   if scheduled_callbacks:
       timeout = min(sched.when - loop.time() for sched in scheduled_callbacks)
   else:
       timeout = None  # block indefinitely

3. Run the selector:
   events = selector.select(timeout)
   # selector.select() calls epoll_wait()/kqueue()/select() OS syscall
   # Returns when: I/O is ready, OR timeout expires, OR signal received

4. Process I/O events:
   for key, mask in events:
       callback = key.data
       ready_queue.append(callback)

5. Process scheduled callbacks that have fired:
   now = loop.time()
   while scheduled_callbacks and scheduled_callbacks[0].when <= now:
       callback = scheduled_callbacks.heappop()
       ready_queue.append(callback)

6. Go to step 1
```

`await asyncio.sleep(1)`:
1. Creates a `TimerHandle` scheduled for `loop.time() + 1`
2. Yields control to the event loop (returns to step 1)
3. After 1 second, the timer fires (step 5), the coroutine is added to the ready queue
4. The coroutine resumes in step 1

`await network_read()`:
1. Registers the socket's file descriptor with the selector
2. Yields control to the event loop
3. When the selector detects the socket is readable, the associated callback resumes the coroutine

A blocking synchronous call (`requests.get(url)`) inside a coroutine does not go through the event loop — it calls OS `read()` directly and blocks the OS thread. The event loop's thread is stuck in `read()`; the selector never gets called; all other coroutines freeze.

---

## How It Connects

Understanding the event loop internals explains why `await asyncio.sleep()` is cooperative (yields to the loop) but `time.sleep()` blocks the loop. The distinction between "suspending" and "blocking" is the core of async programming.
[[event-loop|The Event Loop]]

Running blocking/CPU-bound code in an executor (`loop.run_in_executor`) moves it to a thread pool, freeing the event loop to continue serving other coroutines.
[[running-sync-in-async|Running Sync Code in Async Context]]

---

## Common Misconceptions

Misconception 1: "asyncio runs multiple threads internally."
Reality: The default asyncio event loop runs on a single OS thread. All coroutines run on that one thread, switched cooperatively at `await` points. No OS context switches between coroutines (only between the event loop and the OS's I/O syscall). This is why blocking calls are catastrophic — they block the one thread everything depends on.

Misconception 2: "The event loop's selector blocks while waiting for I/O."
Reality: `selector.select(timeout)` does block the event loop — but only until I/O is ready or the timeout expires. This blocking is at the OS kernel level (the kernel manages the file descriptor monitoring) and is efficiently implemented. The event loop is "doing nothing" during this wait, which is correct — it means there is genuinely no work to do (no ready coroutines, no fired timers).

---

## Why It Matters in Practice

Diagnosing "frozen event loop" issues: if your asyncio application is unresponsive, a blocking call is the most likely cause. Add `loop.set_debug(True)` to get warnings when a callback blocks for more than 100ms. Use `asyncio.sleep(0)` to yield control if you have a CPU-intensive loop.

Custom event loop backends: `uvloop` (using `libuv`) replaces CPython's default event loop with a faster implementation — same API, but uses libuv's more optimized I/O multiplexing. Drop-in replacement: `uvloop.install()`.

Protocol/Transport vs async/await: asyncio's low-level Protocol/Transport API is callback-based (directly using the event loop API). High-level coroutine-based code (`async def`, `await`) is built on top of this low-level callback system by the coroutine machinery.

---

## Interview Angle

Common question forms:
- "How does asyncio work internally?"
- "Why does a blocking call freeze the event loop?"

Answer frame: The asyncio event loop is a single-threaded selector-based scheduler. Each iteration: process the ready callback queue, call `epoll_wait()/kqueue()` with a timeout (waiting for I/O or timer), then process completed I/O and fired timers. `await asyncio.sleep(1)` suspends the coroutine and schedules it to resume in 1 second — the event loop runs other coroutines in the meantime. A blocking `time.sleep(1)` holds the OS thread — the event loop thread is stuck, nothing else runs.

---

## Related Notes

- [[event-loop|The Event Loop]]
- [[async-await|Async and Await]]
- [[running-sync-in-async|Running Sync Code in Async Context]]
- [[asyncio|Asyncio]]
