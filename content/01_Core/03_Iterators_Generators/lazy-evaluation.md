---
title: 06 - Lazy Evaluation
description: "Lazy evaluation defers computation until the result is actually needed  -  Python's generators, generator expressions, and `itertools` produce values on demand rather than upfront, enabling processing of infinite sequences and large datasets with constant memory."
tags: [lazy-evaluation, generators, itertools, on-demand, infinite-sequences, memory-efficiency, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Lazy Evaluation

> Lazy evaluation defers computation until the result is actually needed  -  Python's generators, generator expressions, and `itertools` produce values on demand rather than upfront, enabling processing of infinite sequences and large datasets with constant memory.

---

## Quick Reference

**Core idea:**
- **Eager evaluation**: compute everything now  -  `list(range(10**9))` allocates 8 GB immediately
- **Lazy evaluation**: compute on demand  -  `range(10**9)` is a lazy object; values are generated only when accessed
- Python's lazy primitives: generators (`yield`), generator expressions `(expr for ...)`, `range`, `map`, `filter`, `zip`, `enumerate`, `itertools` functions
- `next(iterator)` pulls one value; `list(iterator)` forces all values (eager materialisation)
- Short-circuit evaluation: `any(pred(x) for x in items)` stops at the first truthy result

**Tricky points:**
- Lazy iterators are **single-use**  -  once exhausted, re-iterating yields nothing; to iterate twice, use a list or recreate the iterator
- `range` is **not** a generator  -  it is a lazy sequence that supports `len()`, indexing, and membership testing; a generator does none of these
- Lazy pipelines do not improve worst-case performance for fully consumed sequences  -  they only help when: (a) work is avoided by early termination, or (b) memory is saved by not materializing the intermediate collection
- `zip(a, b)` is lazy  -  it stops at the shorter iterable; `itertools.zip_longest` fills with a fill value
- Debugging lazy pipelines is harder  -  errors manifest at `next()` call sites, not where the pipeline was constructed

---

## What It Is

Think of a restaurant where food is prepared when ordered versus a buffet where everything is cooked and laid out in advance. The buffet fills the table regardless of what guests will actually eat  -  food that is not consumed is wasted. The à la carte restaurant prepares only what is ordered, when it is ordered. Lazy evaluation is the à la carte model: computation is triggered only when the result is requested.

Python's `range(10**6)` is a canonical example. It does not store a million integers. It stores the start, stop, and step, and computes each integer on demand. `for i in range(10**6)` iterates through a million integers using constant memory  -  no list of integers is ever created. A list comprehension `[i for i in range(10**6)]` is the buffet  -  all million integers allocated at once.

The practical payoff is composability with memory efficiency. `map(f, filter(pred, large_file_lines()))` creates a lazy pipeline. Calling `next()` on it pulls one line from the file, checks the predicate, and if it passes, applies `f`. At any point, only one line is in memory. This is how Python processes files larger than RAM.

---

## How It Actually Works

Python's lazy objects implement the iterator protocol (`__iter__` and `__next__`). Calling `next()` on a lazy object performs the minimum work needed to produce the next value and returns it. The computation state is preserved between `next()` calls  -  in generators, this is the frame's execution point.

`itertools` provides a library of lazy combinators:
- `itertools.chain(a, b)`  -  lazily concatenates iterables
- `itertools.islice(it, n)`  -  lazily takes the first `n` elements (like `it[:n]` but for iterators)
- `itertools.takewhile(pred, it)`  -  lazily yields while predicate is true
- `itertools.count(start)`  -  infinite counting from `start`; must be stopped with `islice` or `takewhile`
- `itertools.cycle(it)`  -  infinite repetition of the iterable

Short-circuit evaluation in Python is a related form of laziness at the expression level. `a and b` does not evaluate `b` if `a` is falsy. `any(pred(x) for x in items)` stops at the first truthy result because `any` internally calls `next()` and returns immediately on the first truthy value.

---

## How It Connects

Generator expressions are the primary syntax for building lazy pipelines  -  `(f(x) for x in items if cond)` is lazy by default.
[[generator-expressions|Generator Expressions]]

Generators (`yield`) are the building blocks for custom lazy sequences  -  any function with `yield` creates a lazy iterator.
[[generators|Generators]]

---

## Common Misconceptions

Misconception 1: "Lazy evaluation is always faster than eager evaluation."
Reality: Lazy evaluation saves memory and enables early termination. If you will consume the entire sequence anyway, lazy evaluation adds iterator overhead without reducing work. For small in-memory collections, a list comprehension is faster than a generator expression because list iteration is more cache-friendly than generator function calls. Profile before choosing.

Misconception 2: "`range` is a generator."
Reality: `range` is a lazy sequence object that computes values on access, but it is not a generator. A generator is single-use; `range` can be iterated multiple times. A generator has no length; `len(range(10))` works. A generator does not support indexing; `range(10)[3]` works. `range` is a special lazy sequence with full sequence semantics.

---

## Why It Matters in Practice

Processing log files line by line: `(parse(line) for line in open("log.txt"))`  -  a generator expression over the file. Each line is read, parsed, and processed one at a time. The entire file is never in memory. Processing 10 GB logs on a 4 GB machine is feasible.

Infinite sequences: `itertools.count()`, `itertools.cycle()` are infinite lazy iterators. Combined with `itertools.islice`, they generate as many values as needed without preallocating: `list(itertools.islice(itertools.count(), 10))` -> `[0, 1, ..., 9]`.

Data pipelines: reading from a database, filtering, transforming, and writing to another store  -  each stage is a generator. Memory usage is proportional to one batch, not the entire dataset.

---

## Interview Angle

Common question forms:
- "What is lazy evaluation in Python?"
- "What is the difference between `range` and a generator?"
- "Why would you use a generator expression instead of a list comprehension?"

Answer frame: Lazy evaluation defers computation until a value is needed. In Python, generators, generator expressions, `range`, `map`, `filter`, and `itertools` are all lazy. Lazy evaluation saves memory (no intermediate list) and enables early termination. `range` is a lazy sequence (multi-use, supports indexing, has `len`), not a generator (single-use). Use generator expressions over list comprehensions when: processing large iterables, only consuming part of the result, or chaining transformations in a memory-efficient pipeline.

---

## Related Notes

- [[generator-expressions|Generator Expressions]]
- [[generators|Generators]]
- [[for-loop-internals|For Loop Internals]]
- [[iterators|Iterators]]
