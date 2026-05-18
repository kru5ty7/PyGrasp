---
title: 08 - itertools Module
description: "itertools provides a collection of lazy iterator-building functions — all return iterator objects that produce values on demand, making it possible to process arbitrarily large sequences with O(1) memory."
tags: [itertools, lazy-evaluation, functional, chain, islice, groupby, product, accumulate, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# itertools Module

> `itertools` is a toolkit for building lazy pipelines — every function returns an iterator that computes nothing until you ask for the next value, so the size of the input data never determines the memory your pipeline uses.

---

## Quick Reference

**Core idea:**
- All `itertools` functions return iterator objects — nothing is computed until `next()` is called
- Memory is O(1) relative to input size (each function holds at most a constant amount of state)
- `chain(*iterables)`: yields from each iterable in sequence without building a combined list
- `islice(it, stop)` / `islice(it, start, stop, step)`: lazy slicing of any iterator
- `groupby(iterable, key)`: yields `(key, group_iterator)` pairs for consecutive equal keys — input must be sorted by key

**Tricky points:**
- `groupby` groups consecutive equal keys only — it does not gather all equal elements across the whole iterable; sort first
- `product('AB', repeat=2)` gives the Cartesian product; `combinations` does not repeat; `permutations` does not repeat
- `cycle(it)` consumes the iterable once and caches all values — it is O(n) memory, unlike most itertools
- `accumulate` defaults to addition in Python 3.8+; pass `func=` for other binary operations (e.g., `operator.mul` for running product)
- Itertools iterators are single-pass — once exhausted, you must create a new iterator from the original source

---

## What It Is

Imagine a factory assembly line. Rather than stamping out ten thousand parts all at once and piling them in a warehouse, each station on the line processes one part at a time — takes a blank from the previous station, does its work, passes the result forward. The warehouse stays empty; the parts flow through. When the customer only needs a hundred parts, the line stops after a hundred, and the raw material is never touched beyond what was needed.

`itertools` implements that assembly-line model for data processing in Python. Each function in the module takes one or more iterators (or iterables) and returns a new iterator that applies a transformation. The key feature is that no transformation is applied until a consumer — a `for` loop, `list()`, `next()`, or another itertools function — asks for the next value. This means you can chain a dozen `itertools` functions together and still process a file of ten gigabytes without loading more than one line into memory at a time.

The module is not just about performance. It is about composability. Complex iteration patterns — every combination of items from two lists, every n-element window of a stream, every group of consecutive items with the same key — are each a one-liner with `itertools`. The same pattern written with nested loops and temporary lists is longer, harder to read, and harder to get right. `itertools` is the vocabulary for expressing these patterns in the idiom that Python's iterator protocol was designed to support.

---

## How It Actually Works

`itertools` functions are implemented in C in CPython (`Modules/itertoolsmodule.c`). Each function corresponds to a C struct that holds the iterator's state — the current position, a reference to the upstream iterator, and any configuration parameters. The `tp_iternext` slot on the struct's type object implements the `__next__` logic, so calling `next()` on an `itertools` object is a direct C function call with no Python overhead.

```python
import itertools, operator

# chain: yields from each source in order, one at a time
for x in itertools.chain([1, 2], [3, 4]):
    print(x)   # 1 2 3 4 — no combined list ever built

# islice: take first 3 items from any iterator
first_three = list(itertools.islice(range(10**9), 3))  # [0, 1, 2] — instantaneous

# accumulate: running total (or any binary function)
running_product = list(itertools.accumulate([1,2,3,4,5], operator.mul))
# [1, 2, 6, 24, 120]

# groupby: MUST sort first
data = sorted([('a', 1), ('b', 2), ('a', 3)], key=lambda x: x[0])
for key, group in itertools.groupby(data, key=lambda x: x[0]):
    print(key, list(group))
```

The `groupby` implementation maintains a single "current key" and a reference to the upstream iterator. When you call `next()` on the groupby object, it reads from upstream until it sees a key change, then returns the new `(key, group_iterator)` pair. The group iterator shares the same upstream position — consuming the group iterator and consuming the groupby object both advance the same underlying iterator. This is why the group iterator becomes invalid once you advance the groupby object to the next group.

`product` and `combinations` work differently: `product` is O(output size) memory because it needs to restart inner iterables repeatedly; it materializes the input iterables into tuples at construction time. `combinations` keeps only a running index array and recomputes each combination on demand. Both are still lazy in the sense that output is generated one tuple at a time.

---

## How It Connects

`itertools` functions return iterators, and iterators are governed by the iterator protocol — `__iter__` returning self and `__next__` advancing state. Every `itertools` object is a proper iterator that plugs into Python's `for` loop machinery.

[[iterators|Iterators]]

`itertools.accumulate` with a custom function is equivalent to `functools.reduce` applied to a growing prefix. The two modules are complementary — `itertools` for lazy streaming pipelines, `functools` for fold-style reductions.

[[generators|Generators]]

Generators are the Python-code equivalent of `itertools` functions — lazy, single-pass, O(1) memory for state. `itertools` provides the building blocks in C; generators let you write custom lazy sequences in pure Python.

[[lazy-evaluation|Lazy Evaluation]]

---

## Common Misconceptions

Misconception 1: "`itertools.groupby` groups all items with the same key together."
Reality: `groupby` groups only consecutive items with the same key. If `a` appears at positions 0, 5, and 9 in the input, you will get three separate groups for `a`. Sort the input by key first if you want one group per unique key value.

Misconception 2: "Itertools iterators can be reused after exhaustion."
Reality: All itertools iterators are single-pass. Once `StopIteration` is raised, the iterator is permanently exhausted. Re-iteration requires creating a new iterator from the original source. This is the standard iterator protocol and is not special to itertools.

Misconception 3: "`itertools.cycle` is O(1) memory."
Reality: `cycle(iterable)` must cache every value from the iterable on the first pass so it can replay them. It is O(n) memory where n is the length of the iterable. It is the one itertools function that does not provide O(1) memory.

---

## Why It Matters in Practice

`itertools.chain` is the right way to iterate over multiple sequences as if they were one, without the allocation of `list1 + list2`. `itertools.islice` is the right way to take the first N items from any iterator — including infinite ones — without building the full sequence. These two alone cover a large fraction of the real-world use cases.

The combination functions (`product`, `combinations`, `permutations`) generate all possibilities without storing them. A brute-force search over all pairs in a list of 10,000 items would require 50 million pair objects if materialized; `itertools.combinations(items, 2)` generates them one at a time. Code that filters these with `next(filter(predicate, itertools.combinations(...)))` finds the first match and stops immediately, potentially examining only a tiny fraction of the search space.

---

## Interview Angle

Common question forms:
- "How would you iterate over two lists as one without concatenating them?"
- "What is lazy evaluation and why does it matter for large datasets?"
- "Explain the behavior of `itertools.groupby` — what is its common gotcha?"

Answer frame:
`itertools.chain(a, b)` — yields from `a` then from `b`, O(1) memory, no new list. Lazy evaluation means computation happens on demand — `itertools.islice(huge_file_lines, 100)` reads only 100 lines regardless of file size. `groupby` groups consecutive equal keys — sorting is required before groupby if you want one group per unique value.

---

## Related Notes

- [[iterators|Iterators]]
- [[generators|Generators]]
- [[lazy-evaluation|Lazy Evaluation]]
- [[collections-module|collections Module]]
- [[functools|functools Module]]
