---
title: 02 - For Loop Internals
description: "Python's `for` loop calls `iter()` on the target to get an iterator, then repeatedly calls `next()` until `StopIteration` is raised — understanding this desugaring explains how `for` works with any custom object and how `break`/`else` fit in."
tags: [for-loop, iter, next, StopIteration, iterator-protocol, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# For Loop Internals

> Python's `for` loop calls `iter()` on the target to get an iterator, then repeatedly calls `next()` until `StopIteration` is raised — understanding this desugaring explains how `for` works with any custom object and how `break`/`else` fit in.

---

## Quick Reference

**Core idea:**
- `for x in obj:` desugars to: `_it = iter(obj)` → loop calling `x = next(_it)` → catch `StopIteration` to exit
- `iter(obj)` calls `obj.__iter__()` — must return an iterator (an object with `__next__`)
- `next(it)` calls `it.__next__()` — returns the next value or raises `StopIteration`
- `for...else` — the `else` block runs if the loop completed normally (no `break`); it does **not** run if the loop was exited by `break`
- Any object implementing `__iter__` (or `__getitem__` with integer indices starting at 0) can be used in a `for` loop

**Tricky points:**
- `iter(obj)` can be called on the same iterable repeatedly — each call creates a fresh iterator; but calling `iter(iterator)` returns the same iterator (iterators are their own iterators: `__iter__` returns `self`)
- Modifying a list while iterating over it causes unexpected behavior — the internal index advances but the list shrinks/grows; iterate over `list(original)` or use a comprehension instead
- `StopIteration` inside a generator (raised manually or propagated from `next()`) causes the generator to silently return — this was changed in Python 3.7 (PEP 479); it is now converted to `RuntimeError`
- `for` loops over `dict` iterate over keys by default; use `.items()`, `.values()` for other views

---

## What It Is

Think of a vending machine dispenser. You do not interact with the entire row of items at once — you request one item at a time by pressing "next." The machine handles the internal tracking of which item comes next and signals "empty" when nothing is left. Python's `for` loop is exactly this model: it acquires a dispenser (the iterator) from the collection, then requests items one at a time with `next()`. When the dispenser signals "empty" with `StopIteration`, the loop ends.

This design is why `for` loops work with everything: lists, tuples, strings, dicts, files, generators, network streams, custom objects. As long as an object can produce an iterator (via `__iter__`), the `for` loop can consume it. The loop does not need to know how the iterator works internally — it only speaks the `next()` protocol.

The protocol separation — iterable (`__iter__`) vs iterator (`__next__`) — is intentional. An iterable can produce fresh iterators on demand. An iterator is stateful and single-use. This means you can loop over a list multiple times (each `for` gets a fresh list iterator), but you can only consume a generator once (the generator object is its own iterator).

---

## How It Actually Works

The Python bytecode for `for x in obj: body` is roughly:

```
GET_ITER        # calls iter(obj), pushes iterator onto stack
FOR_ITER +end   # calls next(iterator); if StopIteration, jump to +end
STORE_FAST x    # assign to loop variable
... body ...
JUMP_BACK       # back to FOR_ITER
+end:           # loop exits here
```

`GET_ITER` calls `obj.__iter__()`. If the object does not have `__iter__` but has `__getitem__`, CPython creates a wrapper iterator that calls `obj[0]`, `obj[1]`, ... until `IndexError` — this is legacy support for old-style sequences.

`FOR_ITER` calls `iterator.__next__()`. If `StopIteration` is raised, it jumps past the loop body. If a value is returned, it is placed on the stack and execution continues with the loop body.

`for...else` is implemented by having the `else` block immediately after the loop's `+end` target, with `break` implemented as a `JUMP` that bypasses both the loop body and the `else` block.

The desugaring:

```python
for x in obj:
    body
else:
    else_body

# equivalent to:
_it = iter(obj)
while True:
    try:
        x = next(_it)
    except StopIteration:
        else_body
        break
    else:
        body
```

---

## How It Connects

The iterator protocol (`__iter__` + `__next__`) is the foundation that `for` loop uses. An object must implement this protocol to be usable in a `for` loop.
[[iterators|Iterators]]

Generators implement `__iter__` and `__next__` automatically — `yield` pauses execution and returns a value as the next `next()` result.
[[generators|Generators]]

---

## Common Misconceptions

Misconception 1: "`for` loops only work with sequences."
Reality: `for` works with any iterable — any object with `__iter__`. Files, network sockets, database cursors, generators, infinite sequences — all work with `for`. The loop has no concept of "sequence" or "length"; it only calls `next()` until `StopIteration`.

Misconception 2: "`for...else` means the `else` runs when the loop is empty."
Reality: `for...else` means the `else` runs when the loop completes without a `break` — this includes the case where the iterable is empty (zero iterations) and the case where all iterations complete normally. The `else` does NOT run if `break` exits the loop. The primary use case: search loops — `else` signals "not found" when a `break` (which would signal "found") never occurred.

---

## Why It Matters in Practice

The `for...else` pattern is underused but valuable for search:

```python
for item in collection:
    if condition(item):
        result = item
        break
else:
    result = default_value
```

This is cleaner than using a sentinel variable or a flag.

Understanding the iterator protocol enables writing lazy data pipelines. A class with `__iter__` returning a generator processes items one at a time without loading the entire dataset into memory. The `for` loop consuming it does not need to know it is reading from a database, a file, or a network connection.

The "modifying while iterating" bug is avoided by iterating over a copy: `for item in list(my_list):` or using a comprehension to build a new list.

---

## Interview Angle

Common question forms:
- "How does a Python `for` loop work internally?"
- "What is `for...else`?"
- "What is the difference between an iterable and an iterator?"

Answer frame: `for x in obj` calls `iter(obj)` to get an iterator, then calls `next(iterator)` in a loop until `StopIteration`. `iter()` calls `__iter__`; `next()` calls `__next__`. An iterable has `__iter__` (can produce iterators). An iterator has both `__iter__` (returns self) and `__next__`. `for...else`: the `else` runs if the loop completes without `break` — used in search patterns to detect "not found."

---

## Related Notes

- [[iterators|Iterators]]
- [[generators|Generators]]
- [[generator-expressions|Generator Expressions]]
- [[list-comprehensions|List Comprehensions]]
