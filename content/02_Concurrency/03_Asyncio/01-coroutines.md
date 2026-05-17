---
title: 01 - Coroutines
description: "A coroutine is a function that can suspend its execution at an `await` expression and resume later — built on the same frame-suspension mechanism as generators, and the foundation on which Python's entire async/await system is constructed."
tags: [coroutines, async, await, generators, event-loop, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Coroutines

> A coroutine is a function that can suspend its execution at an `await` expression and resume later — built on the same frame-suspension mechanism as generators, and the foundation on which Python's entire async/await system is constructed.

---

## Quick Reference

**Core idea:**
- `async def fn()` defines a coroutine function — calling it returns a **coroutine object**, not a result
- `await expr` suspends the current coroutine and passes control to `expr` (another awaitable)
- Coroutines are **awaitables**: objects that implement `__await__()` returning an iterator
- At the bytecode level, `await expr` compiles to `GET_AWAITABLE` + `SEND` opcodes — it is `yield from` for coroutines
- A coroutine does **nothing** until driven by an event loop or `asyncio.run()` — it is inert until something calls `next()` on it

**Tricky points:**
- Calling `async_fn()` returns a coroutine object and **runs zero lines** of the function body
- `await` can only appear inside `async def` — using it in a regular function is a `SyntaxError`
- A coroutine that is never awaited and never passed to `asyncio.run()` / `asyncio.create_task()` will never execute and will emit a `RuntimeWarning: coroutine was never awaited`
- `await` does **not** create parallelism — it suspends the current coroutine and runs the awaited one; only one coroutine runs at a time unless you use `asyncio.gather()` or `create_task()`
- An `async def` function that does not contain any `await` expression will still be a coroutine — it just never suspends

---

## What It Is

Think of a relay race where a runner can choose to pause at any point, hand the baton to a waiting runner, and later receive the baton back and continue from exactly where they stopped. Normal functions are sprinters who run from start to finish without stopping. Coroutines are relay runners — they can pause mid-race, hand off control, and pick up exactly where they left off when control returns. The pausing happens at `await` expressions, and the handoff goes to whatever the `await` is waiting for.

A coroutine in Python is defined with `async def`. Using `async def` does not make the function run asynchronously — it changes the function into a coroutine function, which means calling it does not execute the body. Instead, calling it creates a coroutine object: a suspended, not-yet-started execution of the function body, very similar to how calling a generator function creates a generator object. The body only runs when something drives the coroutine — typically an event loop that calls `send()` on it.

The word "coroutine" historically refers to any function that can cooperatively yield control to other functions and resume later. Python's coroutines are a specific implementation of this idea built on top of generators. They are called "native coroutines" (as opposed to generator-based coroutines, which existed before `async/await` and used `@asyncio.coroutine` with `yield from`). The `async/await` syntax, introduced in Python 3.5, is now the standard and only recommended way to write coroutines.

---

## How It Actually Works

CPython compiles an `async def` function almost identically to a generator function. The `PyCodeObject` for a coroutine has the `CO_COROUTINE` flag set (instead of `CO_GENERATOR`). When called, CPython checks this flag and creates a `PyCoroObject` instead of a `PyGenObject` — but the underlying mechanism is the same: a frame is allocated but not executed, and the coroutine object wraps the suspended frame.

The `await expr` syntax compiles to two opcodes. `GET_AWAITABLE` checks that `expr` is a valid awaitable (has an `__await__` method or is a coroutine/generator with the right flags) and calls `expr.__await__()` to get an iterator. `SEND` (in CPython 3.11+) or `YIELD_FROM` (in earlier versions) then drives that iterator, propagating values up and down the coroutine call chain. Effectively, `await coroutine` means "run this coroutine until it suspends or finishes, and if it suspends, suspend me too." The suspension propagates upward through the entire call chain until it reaches the event loop.

The event loop is the top-level driver. It holds a collection of coroutine objects in various states of suspension. It calls `coro.send(None)` to start or resume a coroutine (for the first call, `None` is the conventional value to send). When the coroutine yields a value — which happens when an `await` reaches an actual I/O wait that cannot complete immediately — the yielded value is a signal to the event loop about what to watch for (a file descriptor becoming readable, a timeout expiring). The event loop registers this with the OS, suspends the coroutine, and moves on to resume another waiting coroutine. When the OS signals that the I/O is ready, the event loop resumes the waiting coroutine by calling `send(result)` with the I/O result.

The `__await__` protocol is what makes custom awaitables possible. Any object that implements `__await__()` returning an iterator can be used with `await`. `asyncio.Future` implements this protocol: `await future` suspends the current coroutine and registers a callback on the future. When the future is resolved, the callback is called, which causes the event loop to resume the coroutine with the future's result.

---

## How It Connects

Coroutines are built directly on the generator frame suspension mechanism. The `CO_COROUTINE` flag and `PyCoroObject` are a thin layer over the same infrastructure that makes generators work. Understanding how generators save and restore frames — and how `yield from` propagates values through a chain of generators — is the prerequisite for understanding how `await` propagates suspension up the coroutine call stack.
[[generators|Generators]]

Coroutines are inert without a driver. The event loop is that driver — it holds coroutines, resumes them when they are ready, and coordinates I/O with the OS. Without an event loop, a coroutine object is just an unstarted frame sitting in memory. The event loop and coroutines together form the async execution model.
[[event-loop|The Event Loop]]

`async def` and `await` are the syntax layer over coroutines. They specify the behavior at the language level: what it means to define an async function and what it means to wait for something inside it. The async/await note covers the full picture of how these primitives combine to form concurrent programs.
[[async-await|Async and Await]]

---

## Common Misconceptions

Misconception 1: "Coroutines run concurrently as soon as you `await` them."
Reality: `await coroutine()` runs the coroutine **sequentially** — the current coroutine suspends and waits for the awaited one to finish before continuing. This is no different from a regular function call in terms of concurrency. To run multiple coroutines concurrently, you must schedule them as tasks with `asyncio.create_task()` or pass them to `asyncio.gather()`. Concurrency in async Python is opt-in, not automatic.

Misconception 2: "Coroutines use multiple threads under the hood."
Reality: Coroutines are cooperative and single-threaded. The event loop runs on a single OS thread. All coroutines are executed on that same thread, one at a time, with each one running until it hits an `await` and voluntarily suspends. There is no OS-level thread switching involved. The concurrency is at the Python level — the event loop decides which coroutine to resume next — not at the OS level.

---

## Why It Matters in Practice

Coroutines are the building block from which all of Python's async ecosystem is built. FastAPI uses them for route handlers. `aiohttp` uses them for HTTP requests. `asyncpg` uses them for database queries. SQLAlchemy's async support uses them. Every `async def` function in every async Python library is a coroutine, and they all work through the same mechanism: frame suspension, `__await__`, and the event loop.

The most important practical insight about coroutines is that they provide concurrency, not parallelism. Ten coroutines making ten network requests can all be in-flight simultaneously — each suspended at its `await` while the network works — because waiting does not require CPU. But if those ten coroutines were doing heavy computation instead of waiting, running them concurrently would provide no benefit, because only one can actually run at any moment. Coroutines trade CPU for simplicity: no threads, no locks, no race conditions for code that is waiting anyway.

---

## Interview Angle

Common question forms:
- "What is a coroutine in Python?"
- "What is the difference between a coroutine and a generator?"
- "Does `await` create parallelism?"

Answer frame: Define a coroutine as a function defined with `async def` that can suspend at `await`. Explain that calling it returns an inert coroutine object — nothing runs until driven by an event loop. Connect to generators: coroutines use the same frame suspension mechanism, `CO_COROUTINE` vs `CO_GENERATOR`, `__await__` vs `__iter__`. Address the concurrency question: `await coroutine()` is sequential; `create_task()` or `gather()` is concurrent. Clarify that coroutines are single-threaded — the event loop runs on one OS thread.

---

## Related Notes

- [[generators|Generators]]
- [[event-loop|The Event Loop]]
- [[async-await|Async and Await]]
