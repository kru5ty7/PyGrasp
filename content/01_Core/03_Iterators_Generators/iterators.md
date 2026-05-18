---
title: 01 - Iterators and Iterables
description: "An iterable is any object that can produce an iterator; an iterator is an object that produces values one at a time  -  together they define the protocol that powers every `for` loop, comprehension, and unpacking operation in Python."
tags: [iterators, iterables, protocol, dunder, generators, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Iterators and Iterables

> An iterable is any object that can produce an iterator; an iterator is an object that produces values one at a time  -  together they define the protocol that powers every `for` loop, comprehension, and unpacking operation in Python.

---

## Quick Reference

**Core idea:**
- **Iterable**: implements `__iter__()`  -  returns a fresh iterator each time
- **Iterator**: implements both `__iter__()` (returns `self`) and `__next__()` (returns next value or raises `StopIteration`)
- Every iterator is an iterable, but **not every iterable is an iterator**
- A `for` loop is exactly: `it = iter(obj); while True: try: x = next(it); ... except StopIteration: break`
- Generators are iterators  -  they implement both `__iter__` and `__next__` automatically

**Tricky points:**
- A list is **iterable but not an iterator**  -  `iter(my_list)` returns a new `list_iterator` object; the list itself has no `__next__`
- Iterators are **single-pass and stateful**  -  once exhausted, they stay exhausted; calling `iter()` on an exhausted iterator returns the same exhausted object (because `__iter__` returns `self`)
- A class with only `__getitem__` (no `__iter__`) is still iterable via the **legacy sequence protocol**  -  Python calls `__getitem__` with 0, 1, 2 … until `IndexError`
- Unpacking (`a, b = obj`) also uses the iterator protocol  -  it calls `iter(obj)` and calls `next()` exactly as many times as there are targets
- `zip`, `map`, `filter`, `enumerate` all return **iterators** (lazy); wrapping with `list()` materializes them

---

## What It Is

Think of a library and a librarian separately. The library is an iterable  -  it holds the books and can provide a librarian to guide you through them. The librarian is the iterator  -  they walk you through the collection one book at a time, remembering where you are, handing you each book in sequence, and telling you when there are no more. The library itself does not remember your position; it just creates a fresh librarian each time you ask. The librarian does remember your position, but can only go forward.

Python formalizes this distinction with two protocols. An iterable is any object that implements `__iter__()`  -  a method that returns a fresh iterator. A list is iterable. A string is iterable. A dict is iterable (over its keys). A custom class becomes iterable by implementing `__iter__`. When you write `for item in my_object:`, Python calls `iter(my_object)` which calls `my_object.__iter__()` to get an iterator, then repeatedly calls `next()` on that iterator until `StopIteration` is raised.

An iterator is an object with two methods: `__iter__` (which returns the iterator itself, so iterators are also iterables) and `__next__` (which returns the next value or raises `StopIteration` when there are no more). Iterators are stateful: they remember where they are in the sequence. Once exhausted, they cannot be reset. This is the key difference from the collection (the iterable): the collection can produce fresh iterators at any time; the iterator is a single cursor moving through the data.

---

## How It Actually Works

CPython's `for` statement compiles to a specific sequence of bytecode. Before the loop body, the compiler emits `GET_ITER` (which calls `iter()` on the subject), producing an iterator and pushing it onto the evaluation stack. At the top of each loop iteration, `FOR_ITER` calls `next()` on the iterator. If `next()` returns a value, the loop body executes. If `next()` raises `StopIteration`, `FOR_ITER` jumps past the loop body. This is compiled directly  -  there is no visible try/except in the bytecode, but `FOR_ITER` is implemented in C to catch `StopIteration` internally.

`iter()` (the built-in) does not just call `__iter__`. It first checks whether the object has `tp_iter` (the type slot for `__iter__`). If it does, it calls it. If it does not, it checks for `sq_length` and `sq_item` (the type slots for `__len__` and `__getitem__`)  -  this is the legacy sequence protocol. If those are present, `iter()` returns a `seqiterator` object that calls `__getitem__(0)`, `__getitem__(1)`, etc., until `IndexError`. This backward-compatibility path is why old-style Python 2 classes with `__getitem__` still work in `for` loops.

`next()` (the built-in) calls the `tp_iternext` slot on the iterator's type, which corresponds to `__next__`. For generator objects, `tp_iternext` is the function that resumes the generator's frame. For list iterators, it is a C function that increments an internal index and returns the next element from the list's internal array. For custom classes, it calls the Python-level `__next__` method via a slot wrapper.

---

## How It Connects

Generators are the most common kind of custom iterator in Python. A generator function with `yield` produces a generator object that automatically implements both `__iter__` and `__next__`  -  CPython builds the iterator protocol into the generator machinery. Understanding generators gives you a template for how to think about any stateful iterator.
[[generators|Generators]]

The iterator protocol is one of the central protocols defined by the Python data model. `__iter__` and `__next__` are dunder methods like any others  -  they are looked up on the type's slot table, not the instance, and they follow all the same rules as other data model methods.
[[python-data-model|The Python Data Model]]

---

## Common Misconceptions

Misconception 1: "You can iterate over a list multiple times because lists are iterators."
Reality: Lists are iterables, not iterators  -  they have `__iter__` but not `__next__`. Each time you write `for x in my_list:`, Python calls `iter(my_list)` which creates a new `list_iterator` object, starting at index 0. The list itself does not track position. This is why you can iterate a list as many times as you like. A generator, by contrast, is an iterator  -  it tracks its own position. You cannot iterate an exhausted generator again.

Misconception 2: "Raising `StopIteration` inside a generator signals the end of iteration."
Reality: Since Python 3.7 (PEP 479), raising `StopIteration` inside a generator converts it to a `RuntimeError`. This was changed because accidentally raising `StopIteration` deep inside a generator (from a helper function) would silently terminate the generator as if it had finished, with no warning. The correct way to end a generator is to let the function return (implicitly or via `return`). Only the `FOR_ITER` opcode  -  which wraps the `tp_iternext` call in a C-level StopIteration catch  -  is supposed to handle `StopIteration`.

---

## Why It Matters in Practice

The iterator protocol is the single most reused interface in the Python standard library. `sorted()`, `sum()`, `min()`, `max()`, `list()`, `tuple()`, `set()`, `dict()`, `zip()`, `map()`, `filter()`, `enumerate()`, `any()`, `all()`  -  every one of these functions takes an iterable as its argument and works with any object that implements `__iter__`. Writing a class that implements the iterator protocol means your class works with all of these functions for free, with no extra code.

Lazy iterators are particularly valuable in data pipelines. Instead of loading a dataset, filtering it, transforming it, and then writing it  -  holding all stages in memory at once  -  you can chain iterators: each stage yields one item at a time to the next stage. `(transform(item) for item in filter(predicate, source))` is a two-stage lazy pipeline that processes items one at a time regardless of the source's size. Libraries like `itertools` are built entirely on this model, providing composable lazy building blocks that chain together with zero memory overhead per stage.

---

## Interview Angle

Common question forms:
- "What is the difference between an iterable and an iterator?"
- "How does Python's `for` loop work under the hood?"
- "Why can you iterate over a list multiple times but not a generator?"

Answer frame: Define iterable (has `__iter__`, returns a fresh iterator each time) and iterator (has `__iter__` returning self, and `__next__` returning values or raising `StopIteration`). Show the `for` loop expansion: `GET_ITER` + `FOR_ITER` bytecodes. Explain that lists are iterables  -  they produce a new `list_iterator` each time  -  while generators are iterators that track their own position and are single-pass. Use this to explain the multiple-iteration difference.

---

## Related Notes

- [[python-data-model|The Python Data Model]]
- [[generators|Generators]]
- [[dunder-methods|Dunder Methods]]
