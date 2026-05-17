---
title: Async and Await
description: `async` and `await` are the two keywords that define Python's native coroutine syntax — `async def` creates a coroutine function, `await` suspends it until an awaitable finishes, and together they enable concurrent I/O-bound programs on a single thread without callbacks or locks.
tags: [async, await, coroutines, asyncio, concurrency, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Async and Await

> `async` and `await` are the two keywords that define Python's native coroutine syntax — `async def` creates a coroutine function, `await` suspends it until an awaitable finishes, and together they enable concurrent I/O-bound programs on a single thread without callbacks or locks.

---

## Quick Reference

**Core idea:**
- `async def fn()` — defines a coroutine function; calling it returns a coroutine object (body does not run)
- `await expr` — suspends the current coroutine until `expr` completes; can only appear inside `async def`
- `asyncio.run(coro)` — creates an event loop, runs `coro` to completion, shuts down the loop; the standard entry point
- `asyncio.create_task(coro)` — schedules `coro` to run **concurrently** (returns immediately); this is what actually creates concurrency
- `asyncio.gather(*coros)` — runs multiple coroutines concurrently and waits for all of them; returns results in order
- `async for` / `async with` — async versions of iteration and context management; require `__aiter__`/`__anext__` and `__aenter__`/`__aexit__`

**Tricky points:**
- `await slow_function()` is **sequential** — the current coroutine suspends and waits; no other coroutine runs concurrently unless it was already scheduled as a task
- `asyncio.run()` **cannot** be called inside an already-running event loop (Jupyter notebooks run one already — use `await` directly or `asyncio.get_event_loop().run_until_complete()`)
- `async def` functions that contain **no `await`** are still coroutines — they never yield and run to completion without suspending, but they must still be awaited
- Forgetting `await` on an async call (writing `result = async_fn()` instead of `result = await async_fn()`) gives you a coroutine object, not the result — silent bug
- **Blocking code in async context** (regular `requests.get()`, `time.sleep()`, file reads) blocks the **entire event loop** — all other coroutines freeze

---

## What It Is

Imagine a single chef in a kitchen who is extraordinarily efficient at multitasking. When they put something in the oven, they do not stand there watching it — they immediately start chopping vegetables for the next dish. When the timer goes off, they handle the oven. When they are waiting for water to boil, they prep the salad. They never do two things at the same physical instant, but they are always doing something useful instead of waiting. This is exactly the model async/await enables: a single thread doing useful work instead of blocking while waiting for I/O.

`async def` marks a function as a coroutine function. The function body works exactly like a regular function, with one addition: inside it you can write `await` before any awaitable expression. When execution reaches `await something`, two things happen. If `something` is not ready (a network response hasn't arrived, a file read hasn't completed), the current coroutine is suspended — its frame is saved — and the event loop is free to run another coroutine that is ready. When `something` completes, the event loop resumes the suspended coroutine and the `await` expression evaluates to the result.

The critical insight is that `await` is a cooperative yield point — the coroutine is volunteering to pause, not being preempted. The coroutine only suspends when it explicitly awaits something. Between `await` expressions, the coroutine runs uninterrupted. This is why async code is free of the race conditions that plague multi-threaded code: there is only one thread, and it can only be interrupted at `await` points. You always know exactly where a coroutine can be suspended.

---

## How It Actually Works

`asyncio.run(coro)` is the standard entry point for async Python programs. It creates a new event loop, calls `loop.run_until_complete(coro)`, and shuts down the loop when done. `run_until_complete` wraps the coroutine in a `Task` and runs the event loop until that task is done. The event loop is a `while True` loop that repeatedly asks the OS "which file descriptors are ready for I/O?" (via `select`/`epoll`/`kqueue`), runs any callbacks registered for those descriptors, and resumes the coroutines waiting on those results.

`asyncio.create_task(coro)` wraps a coroutine in a `Task` object and schedules it to run on the event loop. The task is added to the event loop's ready queue. The next time the event loop iterates, it will call `task.__step()`, which resumes the coroutine by calling `coro.send(None)`. If the coroutine hits an `await` on something not immediately ready, it yields back to the event loop with information about what it is waiting for. The event loop registers this with the OS, marks the task as suspended, and moves on to the next ready task.

`await asyncio.sleep(0)` is a special pattern: it suspends the current coroutine for zero seconds — meaning it yields control to the event loop immediately, gives other tasks a chance to run, and resumes on the next event loop iteration. It is the async equivalent of `time.sleep(0)` in threaded code — a way to explicitly yield the CPU. It is useful in coroutines that do substantial work in a loop without any I/O, to avoid starving other tasks.

`async for` and `async with` work exactly like their synchronous counterparts but with async dunder methods. `async with obj:` calls `await obj.__aenter__()` and `await obj.__aexit__(...)`. `async for item in obj:` calls `await obj.__aiter__()` to get an async iterator, then `await async_iter.__anext__()` for each item, catching `StopAsyncIteration` to end the loop. These are needed for resources like database connections that require awaiting setup and teardown.

---

## How It Connects

`async def` and `await` are syntax for coroutines. Every `async def` function is a coroutine function, and the frame suspension mechanism underneath is the same as generators. Understanding coroutines — how they are compiled, how the event loop drives them, what `__await__` does — provides the complete picture beneath the `async`/`await` surface.
[[coroutines|Coroutines]]

Async and await are useless without an event loop to drive them. The event loop is the engine that resumes suspended coroutines, monitors I/O, and orchestrates execution. Every `await` is ultimately a yield to the event loop. Understanding the event loop completes the picture of how concurrent async code actually runs.
[[event-loop|The Event Loop]]

`asyncio` is the standard library that provides the event loop implementation, task scheduling, async I/O primitives, and synchronization tools. Knowing `async def` and `await` covers the language syntax; the `asyncio` note covers the standard library ecosystem around it.
[[asyncio|Asyncio]]

Running blocking code (synchronous I/O, CPU work) inside an async program blocks the event loop. `ThreadPoolExecutor` with `loop.run_in_executor()` or `asyncio.to_thread()` is the standard way to offload blocking work to threads without freezing the event loop.
[[thread-pool-executor|ThreadPoolExecutor]]

---

## Common Misconceptions

Misconception 1: "async/await makes my code run faster by using multiple cores."
Reality: async/await is single-threaded. All coroutines run on the same OS thread, using the same CPU core. It does not provide CPU parallelism. It provides concurrency for I/O-bound work: instead of one thread blocking on a network call, the thread continues running other coroutines while the network call is in progress. For CPU-bound work, async/await provides no benefit and adds overhead.

Misconception 2: "`await fn()` runs `fn` in the background while the current code continues."
Reality: `await fn()` suspends the current coroutine and waits for `fn()` to complete before continuing. It is sequential from the caller's perspective. To run something in the background while continuing, use `asyncio.create_task(fn())` — this schedules `fn()` as a concurrent task and returns immediately, allowing the current coroutine to continue. The task runs whenever the event loop gets control (i.e., when the current coroutine hits another `await`).

---

## Why It Matters in Practice

Async/await is the standard model for high-performance Python web servers. FastAPI, Starlette, and aiohttp handle thousands of concurrent HTTP connections on a single thread by awaiting I/O at every network operation. Each request is a coroutine — while one request waits for a database query, another handles its response, another reads its request body. The event loop orchestrates all of them without thread overhead or locking complexity. A well-written async web server can serve thousands of simultaneous connections from a single Python process.

The hardest thing about async Python is the viral nature of `await`. An `async def` function can only be called with `await` from another `async def` function. Once any function in your call chain is async, everything that calls it must also be async, all the way up to the entry point. This is sometimes called "async all the way down" — you cannot mix blocking and async code freely. The boundary between the sync and async world requires explicit bridging (`asyncio.run()` for sync-to-async, `loop.run_in_executor()` for async-to-sync), and managing that boundary is often the hardest part of adopting async in an existing codebase.

---

## Interview Angle

Common question forms:
- "What is the difference between `async def` and a regular function?"
- "What does `await` do?"
- "What is the difference between `await coroutine()` and `asyncio.create_task(coroutine())`?"

Answer frame: Define `async def` as creating a coroutine function — calling it returns an inert coroutine object. Define `await` as a cooperative suspension point — the current coroutine pauses and the event loop can run others. Draw the sequential vs concurrent distinction: `await fn()` is sequential (wait for fn to finish); `create_task(fn())` is concurrent (schedule fn and continue). Address the "multiple cores" misconception: async is single-threaded; it overlaps I/O waiting, not computation.

---

## Related Notes

- [[coroutines|Coroutines]]
- [[event-loop|The Event Loop]]
- [[asyncio|Asyncio]]
- [[thread-pool-executor|ThreadPoolExecutor]]
