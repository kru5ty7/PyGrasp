---
title: Asyncio
description: "`asyncio` is Python's standard library for async I/O — it provides the event loop implementation, task scheduling, async synchronization primitives, and network I/O utilities that make concurrent async programs work in practice."
tags: [asyncio, event-loop, tasks, gather, async, standard-library, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Asyncio

> `asyncio` is Python's standard library for async I/O — it provides the event loop implementation, task scheduling, async synchronization primitives, and network I/O utilities that make concurrent async programs work in practice.

---

## Quick Reference

**Core idea:**
- `asyncio.run(coro)` — **entry point**: creates a loop, runs `coro` to completion, closes the loop; use this in all new code
- `asyncio.create_task(coro)` — **schedules** a coroutine as a concurrent task; returns a `Task` that can be awaited or cancelled
- `asyncio.gather(*coros)` — runs multiple coroutines **concurrently**, waits for all; returns list of results in order
- `asyncio.sleep(n)` — suspends the current coroutine for `n` seconds **without blocking the event loop**; `sleep(0)` yields to the event loop
- `asyncio.Queue`, `asyncio.Lock`, `asyncio.Event`, `asyncio.Semaphore` — async-aware synchronization primitives; use these, not `threading` equivalents

**Tricky points:**
- `asyncio.gather()` **propagates the first exception** by default and cancels other tasks — use `return_exceptions=True` to collect all results/exceptions instead
- A `Task` created with `create_task()` starts running **immediately** (on next event loop iteration) even if you never await it — fire-and-forget is intentional but can lead to unhandled exceptions silently
- `asyncio.wait()` vs `asyncio.gather()`: `wait()` takes a set of tasks/futures and returns two sets (done, pending); it does **not** raise exceptions automatically — you check them on the returned tasks
- `asyncio.timeout(n)` (Python 3.11+) is preferred over `asyncio.wait_for()` for cancellation with a timeout — cleaner API
- Never use `threading.Lock` or `threading.Event` in async code — they block the event loop; use `asyncio.Lock` and `asyncio.Event` instead

---

## What It Is

Think of `asyncio` as the complete operations team for an air traffic control system. The event loop concept is like the controller — the role, the procedure. But `asyncio` is the entire system: the radar screens, the radio equipment, the scheduling software, the emergency protocols, the runways. It is the concrete implementation that takes the concept of an event loop and makes it something you can build programs with.

`asyncio` provides three layers of functionality. The first is the event loop itself — the engine that drives coroutines, monitors I/O, and runs callbacks. The second is the task management layer — `Task`, `create_task`, `gather`, `wait`, `wait_for`, `timeout` — the tools for scheduling and coordinating concurrent coroutines. The third is the network I/O layer — `asyncio.open_connection`, `asyncio.start_server`, `StreamReader`, `StreamWriter`, `DatagramEndpoint` — high-level APIs for async TCP and UDP I/O that build on the event loop's I/O multiplexing.

`asyncio` has evolved substantially since its introduction in Python 3.4. The older API — `asyncio.get_event_loop()`, `loop.run_until_complete()`, `@asyncio.coroutine`, `yield from` — is deprecated in favor of `asyncio.run()`, `create_task()`, and native `async def`/`await`. New code should use only the modern API.

---

## How It Actually Works

`asyncio.run(coro)` is the canonical entry point. It calls `events.new_event_loop()` to create a fresh `SelectorEventLoop` (or `ProactorEventLoop` on Windows), calls `loop.run_until_complete(coro)`, then calls `loop.close()`. `run_until_complete` wraps the coroutine in a `Task` and runs the event loop until that task is done.

A `Task` is a wrapper around a coroutine that integrates with the event loop's scheduler. `Task.__step()` is the method that resumes the coroutine — it calls `coro.send(None)` (or `coro.throw(exc)` to inject an exception). When the coroutine yields (suspends at `await`), `Task.__step()` inspects what was yielded and registers the appropriate callback with the event loop. When the callback fires (I/O ready, timer elapsed, another task done), it calls `Task.__step()` again to resume the coroutine.

`asyncio.gather(*aws)` creates a list of tasks from the given awaitables and waits for all of them to complete. It is implemented as a counter: it creates tasks for each awaitable, registers a callback on each, and decrements a counter when each completes. When the counter reaches zero, `gather` resolves with the list of results. If any task raises an exception, `gather` cancels all other tasks (unless `return_exceptions=True`) and propagates the exception.

`asyncio.Queue` is the standard pattern for async producer-consumer. It is implemented with an internal `deque` for items and `asyncio.Event`-like mechanisms for waking up coroutines waiting for items to be put or taken. Unlike `queue.Queue` (the synchronous version), `asyncio.Queue.get()` is a coroutine — it suspends if the queue is empty and resumes when an item is available, without blocking any thread. This makes it safe to use in the event loop without stalling other coroutines.

`asyncio.Lock` is the async analog of `threading.Lock`. Calling `await lock.acquire()` suspends the coroutine if the lock is held and resumes it when the lock is released. Since only one coroutine runs at a time in the event loop, the lock protects against re-entrancy at `await` points — not against preemption (there is none). The typical use is protecting access to shared state that must not be modified concurrently between two `await` expressions.

---

## How It Connects

The event loop is the engine beneath `asyncio`. Every feature in `asyncio` — tasks, queues, locks, network streams — runs on top of the event loop's I/O multiplexing and callback scheduling infrastructure. Understanding the event loop is what makes `asyncio`'s behavior predictable rather than mysterious.
[[event-loop|The Event Loop]]

`asyncio` is the runtime for coroutines. Every `async def` function in an asyncio program is a coroutine, and `asyncio` provides the tools to create, schedule, cancel, and await them. Knowing the coroutine model — frame suspension, `__await__`, the relationship between `await` and yield — is the prerequisite for using `asyncio` effectively.
[[async-await|Async and Await]]

FastAPI is built on top of `asyncio` via Starlette. Route handlers can be `async def` coroutines, and the server runs them on an `asyncio` event loop. Understanding `asyncio` explains how FastAPI handles thousands of concurrent requests, why blocking code in a route handler is harmful, and how background tasks and lifespan events work.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "Tasks created with `create_task()` only run when you `await` them."
Reality: `create_task(coro)` schedules `coro` to run on the next event loop iteration. The task starts running as soon as the current coroutine hits any `await` (which yields control to the event loop). Awaiting the returned `Task` object waits for it to finish, but the task has already started. If you never `await` the `Task`, it still runs to completion in the background — or raises an unhandled exception that logs a warning and is silently swallowed.

Misconception 2: "`asyncio.gather()` runs coroutines in parallel on multiple cores."
Reality: `asyncio.gather()` runs coroutines concurrently on the event loop's single thread. They interleave at `await` points — one coroutine runs until it suspends, then another runs. They are not parallel; they do not run simultaneously. For CPU-bound tasks, `gather` provides no speedup. For I/O-bound tasks, `gather` allows all of them to have their I/O in flight simultaneously, which is where the speedup comes from.

---

## Why It Matters in Practice

`asyncio` is the foundation of Python's async ecosystem. FastAPI, aiohttp, Starlette, Tornado (in async mode), Sanic, and Litestar all run on asyncio. Database libraries like `asyncpg`, `aiomysql`, and `databases` use asyncio. HTTP client libraries like `httpx` and `aiohttp` use asyncio. When you adopt any of these frameworks, you are adopting asyncio — understanding it means you can debug its failure modes, know when to use `create_task` vs `gather` vs `wait`, and understand why blocking code is dangerous.

The `asyncio.Queue` with producer/consumer pattern is one of the most useful asyncio patterns in practice. A web scraper can have a producer coroutine that generates URLs, worker coroutines that fetch them, and a consumer coroutine that processes results — all connected by asyncio Queues, all running concurrently on the event loop. This pipeline model provides natural backpressure (the queue limits how far ahead the producer can get) and clean separation of concerns, all without threads or inter-process communication.

---

## Interview Angle

Common question forms:
- "What is `asyncio` and how does it relate to `async/await`?"
- "What is the difference between `asyncio.gather()` and `asyncio.create_task()`?"
- "How do you run multiple async operations concurrently?"

Answer frame: Define `asyncio` as the event loop implementation plus task scheduling and I/O tools — the runtime that makes `async/await` practical. Explain `create_task` (schedule and continue) vs `await coro()` (schedule and wait). Show `gather` as the tool for running multiple tasks concurrently and collecting all results. Clarify that "concurrent" means interleaved on one thread, not parallel on multiple cores — the speedup comes from overlapping I/O waits.

---

## Related Notes

- [[event-loop|The Event Loop]]
- [[async-await|Async and Await]]
- [[coroutines|Coroutines]]
- [[fastapi|FastAPI]]
