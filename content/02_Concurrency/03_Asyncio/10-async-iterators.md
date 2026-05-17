---
title: 10 - Async Iterators
description: "Async iterators implement `__aiter__()` and `__anext__()` — `__anext__` is a coroutine that returns the next value or raises `StopAsyncIteration`; consumed via `async for`; async generators are the common way to create async iterators without writing a full class."
tags: [async-iterators, __aiter__, __anext__, StopAsyncIteration, async-for, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Async Iterators

> Async iterators implement `__aiter__()` and `__anext__()` — `__anext__` is a coroutine that returns the next value or raises `StopAsyncIteration`; consumed via `async for`; async generators are the common way to create async iterators without writing a full class.

---

## Quick Reference

**Core idea:**
- **Async iterable**: implements `__aiter__()` — returns an async iterator
- **Async iterator**: implements `__aiter__()` (returns `self`) and `__anext__()` (coroutine returning next value or raising `StopAsyncIteration`)
- `async for item in async_iterable:` — calls `await item.__anext__()` for each iteration
- `aiter(obj)` — calls `obj.__aiter__()`; `anext(it)` — calls `await it.__anext__()`
- Async generators automatically implement the async iterator protocol

**Tricky points:**
- `__anext__` must be a coroutine (defined with `async def`) — returning a plain value without `async def` causes a `TypeError` at runtime
- `StopAsyncIteration` raised inside `__anext__` signals exhaustion to `async for`; raising it inside a coroutine (not `__anext__`) is converted to `RuntimeError` (PEP 479 applied)
- An async iterable's `__aiter__` may return a different async iterator each time (like how a list returns a new list iterator) — or the same one (like a generator that is its own iterator)
- `async for` cannot be used on regular synchronous iterables — they need synchronous `for`; there is no automatic adaptation

---

## What It Is

Think of a newspaper delivery service that delivers issues one by one. Each delivery (getting the next item) involves waiting — the newspaper must be printed, packaged, and transported. An async iterator models this: asking for the next item (`__anext__`) is an async operation that may involve waiting for a network response, a database query, or a file read.

The async iterator protocol mirrors the synchronous iterator protocol, with two differences: `__aiter__` may itself be a coroutine (though usually it is not), and `__anext__` must be a coroutine. The `async for` loop drives the protocol by `await`-ing each `__anext__` call.

---

## How It Actually Works

A manual async iterator class:

```python
class AsyncCounter:
    def __init__(self, start, stop):
        self.current = start
        self.stop = stop
    
    def __aiter__(self):
        return self
    
    async def __anext__(self):
        if self.current >= self.stop:
            raise StopAsyncIteration
        await asyncio.sleep(0)  # yield to event loop
        value = self.current
        self.current += 1
        return value

async def main():
    async for n in AsyncCounter(0, 5):
        print(n)  # 0, 1, 2, 3, 4
```

`async for item in obj:` desugars to:

```python
_ait = obj.__aiter__()
while True:
    try:
        item = await _ait.__anext__()
    except StopAsyncIteration:
        break
    body
```

The async generator equivalent:

```python
async def counter(start, stop):
    for n in range(start, stop):
        await asyncio.sleep(0)
        yield n
```

This is shorter and equivalent — async generators are the practical way to create async iterators without the class boilerplate.

`aiter()` and `anext()` built-ins (Python 3.10+):
```python
ait = aiter(async_iterable)   # calls __aiter__
val = await anext(ait)         # calls await __anext__
val = await anext(ait, default)  # returns default on StopAsyncIteration
```

---

## How It Connects

Async generators implement the async iterator protocol automatically — they are the common practical tool for creating async iterators.
[[async-generators|Async Generators]]

The async iterator protocol mirrors the synchronous iterator protocol — understanding synchronous iterators provides the mental model.
[[iterators|Iterators]]

---

## Common Misconceptions

Misconception 1: "Wrapping a synchronous iterator in `async for` makes it async."
Reality: You cannot use `async for` on a regular synchronous iterable. `async for` requires an object with `__aiter__` returning an async iterator with `__anext__`. To adapt a synchronous iterator for async use, wrap it: `async def async_iter(it): for item in it: yield item`.

Misconception 2: "An async iterator can be used in a regular `for` loop."
Reality: Regular `for` calls `iter()` and `next()` — these are not coroutines and do not `await`. An async iterator's `__anext__` is a coroutine; calling it without `await` returns a coroutine object, not the actual value. Use `async for` for async iterators.

---

## Why It Matters in Practice

Database libraries (SQLAlchemy async, aiopg) provide async cursor objects that implement async iterators. `async for row in cursor:` streams database results without loading them all into memory.

File streaming: reading a large file asynchronously line by line:
```python
async def read_lines(path):
    async with aiofiles.open(path) as f:
        async for line in f:
            yield line.strip()
```

WebSocket message streaming: a WebSocket connection is naturally an async iterator — each `await websocket.recv()` returns the next message. aiohttp and websockets library objects implement `__aiter__`/`__anext__` so you can `async for` over incoming messages.

---

## Interview Angle

Common question forms:
- "What is an async iterator?"
- "How does `async for` work?"

Answer frame: Async iterators implement `__aiter__()` (returns self) and `__anext__()` (coroutine; returns next value or raises `StopAsyncIteration`). `async for` drives them by awaiting `__anext__` repeatedly. Async generators are the practical way to create async iterators without writing a class. Regular synchronous iterables cannot be used with `async for`. Use `aiter()` and `anext()` built-ins (Python 3.10+) for low-level access.

---

## Related Notes

- [[async-generators|Async Generators]]
- [[iterators|Iterators]]
- [[async-await|Async and Await]]
- [[asyncio|Asyncio]]
