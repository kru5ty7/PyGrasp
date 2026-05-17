---
title: yield from
description: "`yield from iterable` delegates iteration to a sub-iterator — it transparently forwards `next()`, `send()`, and `throw()` calls to the sub-generator, enables composing generators, and is the foundation for coroutine chaining in `asyncio` (before `async/await`)."
tags: [yield-from, generators, delegation, subgenerators, coroutines, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# yield from

> `yield from iterable` delegates iteration to a sub-iterator — it transparently forwards `next()`, `send()`, and `throw()` calls to the sub-generator, enables composing generators, and is the foundation for coroutine chaining in `asyncio` (before `async/await`).

---

## Quick Reference

**Core idea:**
- `yield from iterable` — yields all values from `iterable` one by one, as if each were individually `yield`-ed
- When `iterable` is a generator, it also forwards: `send()` values, `throw()` exceptions, and captures the `return` value via `StopIteration.value`
- `result = yield from subgen()` — `result` receives the value from `return value` inside `subgen` (delivered as `StopIteration.value`)
- Replaces the boilerplate: `for item in subgenerator(): yield item` — but with full bidirectional communication support
- Was added in Python 3.3 (PEP 380); is the mechanism `asyncio` used before `async`/`await` syntax

**Tricky points:**
- `yield from` on a plain iterable (list, range) just yields its elements — the full bidirectional delegation only applies to generators
- `return value` inside a `yield from` generator sends `value` as `StopIteration.value` to the **delegating** generator — not to the outermost caller
- The delegating generator is suspended for the entire duration of the sub-generator's run — it does not resume until the sub-generator is exhausted
- `throw()` on the delegating generator is forwarded to the sub-generator; if the sub-generator does not handle it, the exception propagates to the delegating generator
- `close()` on the delegating generator calls `close()` on the sub-generator first

---

## What It Is

Think of a manager who delegates a task to an employee. The manager is not idle — they are paused waiting for the employee to finish. While the employee works, the employee directly communicates results to the client, and the client's instructions go directly to the employee. When the employee finishes, the manager resumes and receives the summary report. `yield from` is that delegation: the delegating generator pauses; all communication (values out, values in via `send`, exceptions via `throw`) passes directly between the sub-generator and the outermost caller; when the sub-generator returns, the delegating generator resumes with the return value.

Before `yield from`, composing generators required a loop:

```python
def chain(a, b):
    for item in a:
        yield item
    for item in b:
        yield item
```

With `yield from`:

```python
def chain(a, b):
    yield from a
    yield from b
```

For simple cases (plain iterables), these are equivalent. But the loop version does not forward `send()` or `throw()` — it breaks bidirectional communication. `yield from` preserves the full generator protocol.

---

## How It Actually Works

CPython implements `yield from` with `SEND` bytecode. The delegating generator maintains a pointer to the current sub-iterator. On each `next()` / `send()` call from outside:

1. The delegating generator calls `send(value)` on the sub-generator (passing the sent value or `None` for `next()`)
2. If the sub-generator yields a value, that value is forwarded to the caller; the delegating generator stays suspended
3. If the sub-generator raises `StopIteration(value)`, the delegating generator captures `value` as the `result` of `yield from` and resumes execution
4. If the sub-generator raises any other exception, it propagates to the delegating generator (which may handle or re-raise it)

The `return value` ↔ `result = yield from` connection:

```python
def subgen():
    yield 1
    yield 2
    return "done"  # becomes StopIteration("done")

def delegating():
    result = yield from subgen()  # result == "done" after subgen exhausts
    print(result)
```

This is how `asyncio` coroutines worked before `async`/`await`: `yield from asyncio.sleep(1)` delegated to the sleep future; the event loop could `send()` results back when the sleep completed; `result = yield from future` captured the future's value.

---

## How It Connects

`yield from` is built on the generator protocol — the same `send()`, `throw()`, `close()` interface that generator objects expose.
[[generators|Generators]]

`async/await` syntax replaced `yield from` for coroutines in Python 3.5. Under the hood, `await expr` is semantically equivalent to `yield from expr` — the event loop and coroutine machinery is the same, just with cleaner syntax and additional restrictions.
[[async-await|async/await]]

---

## Common Misconceptions

Misconception 1: "`yield from iterable` is just a shorthand for `for item in iterable: yield item`."
Reality: For plain iterables, they produce the same output. But `yield from` also forwards `send()` and `throw()` to the sub-generator — the loop version does not. If you are composing generators that use `send()` (coroutine-style), the loop breaks bidirectional communication; `yield from` is required.

Misconception 2: "`return` inside a generator called via `yield from` raises `StopIteration` for the outermost caller."
Reality: `return value` inside a sub-generator raises `StopIteration(value)`, but `yield from` catches this and makes the value available as the result of the `yield from` expression in the delegating generator. The outermost caller only sees `StopIteration` when the **outermost** generator (the delegating one) finishes.

---

## Why It Matters in Practice

Flattening nested iterables is the simplest use case:

```python
def flatten(nested):
    for item in nested:
        if isinstance(item, list):
            yield from flatten(item)
        else:
            yield item
```

`yield from flatten(sub)` recursively delegates without the boilerplate of a nested loop.

For coroutine-based code predating `async/await`, understanding `yield from` is essential for reading older `asyncio` code and third-party libraries. `asyncio.coroutine` + `yield from` is the 3.4-era pattern; `async def` + `await` is the 3.5+ replacement.

Return values from generators: building a tree-walking generator that counts items while yielding — the `return count` at the end is delivered via `yield from` to the caller that collects the final tally.

---

## Interview Angle

Common question forms:
- "What does `yield from` do?"
- "How does `yield from` differ from `for x in sub: yield x`?"

Answer frame: `yield from subgen` delegates to `subgen` — the sub-generator runs until exhausted, yielding each value to the outer caller. Unlike a loop, `yield from` also forwards `send()` values and `throw()` exceptions to the sub-generator. `return value` in the sub-generator becomes the result of the `yield from` expression in the delegating generator (via `StopIteration.value`). This bidirectional delegation is what makes it the foundation for `async/await` under the hood.

---

## Related Notes

- [[generators|Generators]]
- [[generator-expressions|Generator Expressions]]
- [[async-await|async/await]]
- [[lazy-evaluation|Lazy Evaluation]]
