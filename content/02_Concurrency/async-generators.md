---
title: Async Generators
description: "An async generator is an `async def` function containing `yield` — it produces values asynchronously; consumed with `async for`; each `yield` suspends the generator and allows the event loop to run other coroutines; useful for async data streams, paginated API results, and database cursors."
tags: [async-generators, async-for, yield, async-iteration, aiter, anext, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Async Generators

> An async generator is an `async def` function containing `yield` — it produces values asynchronously; consumed with `async for`; each `yield` suspends the generator and allows the event loop to run other coroutines; useful for async data streams, paginated API results, and database cursors.

---

## Quick Reference

**Core idea:**
- `async def gen(): yield value` — async generator function; calling it returns an async generator object
- `async for item in gen():` — async iteration; calls `await aiter.__anext__()` for each item; stops on `StopAsyncIteration`
- `aiter(async_iterable)` — returns the async iterator; `anext(async_iterator)` — awaits the next value
- Async generators can `await` inside their body — unlike regular generators which cannot
- `asyncio.Queue` can be consumed as an async generator: `while True: item = await queue.get(); yield item`

**Tricky points:**
- Async generators do NOT support `send()` or `throw()` in the coroutine sense — they are generators, not full coroutines
- `async for` must be used inside `async def` — it cannot be used in synchronous code
- Async generator cleanup: if the `async for` loop exits early (via `break`), the generator's `aclose()` method is called to run any `finally` blocks — this requires the generator to be properly finalized (the event loop handles this for normally exiting code, but manual cleanup may be needed for early exits outside event loop context)
- `yield from` does not work in async generators — use `async for item in other_gen: yield item` instead
- An async generator expression: `(expr async for var in async_iterable)` — lazy async generator; works like a generator expression but with `async for` inside

---

## What It Is

Think of a pagination API that delivers results one page at a time, each requiring a network call. A regular generator produces all pages synchronously (blocking for each network call), making the entire pipeline synchronous. An async generator makes a network call, yields the page when it arrives, then makes the next call — between each call, the event loop can serve other requests.

The mental model: an async generator is a coroutine that can pause at multiple points (`yield`) and resume later, and can also await between yields. The consumer uses `async for` to drive it, receiving one item per loop iteration after awaiting the generator's next step.

This is the natural tool for streaming data: paginated REST API responses, database cursors, file streaming over a network, real-time event feeds.

---

## How It Actually Works

An async generator function returns an `async_generator` object with `__aiter__` and `__anext__` methods:

```python
async def paginated_results(url):
    page = 1
    while True:
        response = await fetch(f"{url}?page={page}")  # await inside generator
        data = response["data"]
        if not data:
            return
        for item in data:
            yield item  # yield suspends; caller awaits
        page += 1
```

`async for item in paginated_results(url):` desugars to:

```python
_aiter = paginated_results(url).__aiter__()
while True:
    try:
        item = await _aiter.__anext__()
    except StopAsyncIteration:
        break
    process(item)
```

`__anext__()` resumes the generator from its last `yield`, runs until the next `yield` or `return`, and resolves the awaitable with the yielded value or raises `StopAsyncIteration`.

Async generator expression:
```python
# Async generator expression:
active_users = (user async for user in db.iter_users() if user.is_active)
# Consumed with:
async for user in active_users:
    process(user)
```

---

## How It Connects

Async generators implement the async iterator protocol — `__aiter__` + `__anext__`. Async iterators are covered separately with their own protocol details.
[[async-iterators|Async Iterators]]

Regular generators use `yield` to produce values synchronously. Async generators extend this with `await` support inside the generator body.
[[generators|Generators]]

---

## Common Misconceptions

Misconception 1: "Async generators work in regular (non-async) `for` loops."
Reality: `async for` is required — regular `for` loops cannot drive async iterators. Using `for` instead of `async for` with an async generator raises `TypeError: 'async_generator' object is not iterable`.

Misconception 2: "Async generators and coroutines are the same thing."
Reality: Both use `async def`, but they are different objects. A coroutine (`async def` without `yield`) is awaited once and returns a value. An async generator (`async def` with `yield`) produces a stream of values via `async for`. A coroutine cannot be used with `async for`; an async generator cannot be `await`-ed.

---

## Why It Matters in Practice

Database cursor streaming:
```python
async def stream_records(session, table):
    async with session.execute(f"SELECT * FROM {table}") as cursor:
        async for row in cursor:
            yield dict(row)

async def process_all():
    async for record in stream_records(session, "users"):
        await process(record)
```

The records stream from the database one at a time — the async generator does not load all records into memory. The event loop can interleave this with other coroutines.

Rate-limited API scraping:
```python
async def fetch_pages(urls):
    sem = asyncio.Semaphore(5)
    for url in urls:
        async with sem:
            response = await fetch(url)
            yield response

async for page in fetch_pages(urls):
    parse_and_store(page)
```

---

## Interview Angle

Common question forms:
- "What is an async generator?"
- "How does `async for` work?"

Answer frame: An async generator is `async def` with `yield` — produces values asynchronously. `async for item in gen()` drives it by calling `await gen().__anext__()` repeatedly until `StopAsyncIteration`. Inside the generator, you can `await` between `yield`s — e.g., waiting for an API response before yielding the next item. Used for: paginated APIs, database cursors, streaming data. Cannot use regular `for` — must use `async for` inside `async def`.

---

## Related Notes

- [[generators|Generators]]
- [[async-iterators|Async Iterators]]
- [[async-await|Async and Await]]
- [[asyncio|Asyncio]]
