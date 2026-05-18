---
title: 13 - Iterator Pattern
description: The Iterator pattern provides a way to access elements of a collection sequentially without exposing its underlying structure, letting you traverse different data structures with a uniform interface.
tags: [design-patterns, iterator, behavioral, generator, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Iterator Pattern

> The Iterator pattern provides sequential access to elements of a collection without exposing whether the underlying structure is a list, tree, graph, database cursor, or infinite stream.

---

## Quick Reference

**Core idea:**
- An iterator provides a `__next__()` method that returns the next element and raises `StopIteration` when exhausted
- An iterable provides `__iter__()` which returns an iterator - this is what `for` loops call
- Python's iterator protocol (`__iter__` + `__next__`) is the language-level implementation of this pattern
- **Generators** (`yield`) are the Pythonic shorthand for creating iterators without writing a class
- Iterators enable lazy evaluation - elements are computed on demand, not stored in memory

**Tricky points:**
- An iterator is consumed after one pass - calling `next()` again after `StopIteration` keeps raising `StopIteration`
- An iterable can create multiple independent iterators (each `__iter__()` call returns a fresh iterator)
- Generators are iterators - but not all iterators are generators
- `iter(callable, sentinel)` creates an iterator from a function that is called repeatedly until it returns the sentinel value

---

## What It Is

Think of a playlist on a music app. You press "next" and the next song plays. You do not know or care whether the playlist is stored as an array, a linked list, a database query, or a streaming API. The "next" button is the iterator. The playlist is the collection. The iterator gives you one song at a time without revealing how the songs are stored.

The Iterator pattern formalizes this. It separates the traversal logic from the collection itself. A `TreeIterator` knows how to walk a tree (depth-first, breadth-first). A `DatabaseIterator` knows how to fetch rows in batches. A `FileIterator` knows how to read lines lazily. All three expose the same interface: give me the next element.

Python has this pattern built into the language. The `for` loop calls `iter()` on the collection to get an iterator, then calls `next()` on the iterator until `StopIteration` is raised. Generators (`yield`) create iterators with minimal syntax. This is so deeply integrated that most Python developers use iterators daily without thinking of them as a design pattern.

The key advantage is lazy evaluation. A list of a million elements occupies memory for all million. An iterator that computes elements on demand uses memory for only one element at a time. This is why `range(1_000_000_000)` in Python 3 does not allocate a billion integers - it is an iterable that computes each value on demand.

---

## How It Actually Works

Python's iterator protocol requires two methods. `__iter__()` returns the iterator object (usually `self` for iterators, or a new iterator for collections). `__next__()` returns the next value and raises `StopIteration` when there are no more values. The `for` loop is syntactic sugar for this protocol.

Generators use `yield` to produce values one at a time. Each `yield` suspends the generator's execution frame and resumes it on the next `next()` call. The generator's local variables are preserved between yields - this is how generators maintain state without explicit instance variables.

```python
from typing import Iterator, Iterable


# Manual iterator class
class CountDown:
    """Iterator that counts down from n to 1."""
    def __init__(self, start: int):
        self._current = start

    def __iter__(self) -> "CountDown":
        return self

    def __next__(self) -> int:
        if self._current <= 0:
            raise StopIteration
        value = self._current
        self._current -= 1
        return value

for num in CountDown(5):
    print(num, end=" ")  # 5 4 3 2 1
print()


# Generator - same thing, much less code
def countdown(start: int) -> Iterator[int]:
    current = start
    while current > 0:
        yield current
        current -= 1

for num in countdown(5):
    print(num, end=" ")  # 5 4 3 2 1
print()


# Lazy file reader - processes files of any size with constant memory
def read_csv_rows(path: str) -> Iterator[dict]:
    """Lazily yields one parsed row at a time."""
    with open(path) as f:
        headers = next(f).strip().split(",")
        for line in f:
            values = line.strip().split(",")
            yield dict(zip(headers, values))


# Tree traversal iterator - makes a tree iterable
class TreeNode:
    def __init__(self, value, left=None, right=None):
        self.value = value
        self.left = left
        self.right = right


def inorder(node: TreeNode | None) -> Iterator:
    """In-order traversal as a generator."""
    if node is None:
        return
    yield from inorder(node.left)
    yield node.value
    yield from inorder(node.right)


def preorder(node: TreeNode | None) -> Iterator:
    """Pre-order traversal - different strategy, same interface."""
    if node is None:
        return
    yield node.value
    yield from preorder(node.left)
    yield from preorder(node.right)


tree = TreeNode(4,
    TreeNode(2, TreeNode(1), TreeNode(3)),
    TreeNode(6, TreeNode(5), TreeNode(7))
)

print(list(inorder(tree)))   # [1, 2, 3, 4, 5, 6, 7]
print(list(preorder(tree)))  # [4, 2, 1, 3, 6, 5, 7]


# Infinite iterator
def fibonacci() -> Iterator[int]:
    a, b = 0, 1
    while True:
        yield a
        a, b = b, a + b

from itertools import islice
print(list(islice(fibonacci(), 10)))  # [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]


# Iterable vs Iterator distinction
class Sensors:
    """Iterable: creates a fresh iterator each time."""
    def __init__(self, readings: list[float]):
        self._readings = readings

    def __iter__(self) -> Iterator[float]:
        return iter(self._readings)  # fresh iterator each time

sensors = Sensors([22.5, 23.1, 21.8])
# Can iterate multiple times
print(list(sensors))  # [22.5, 23.1, 21.8]
print(list(sensors))  # [22.5, 23.1, 21.8] - works again
```

---

## How It Connects

Python's `for` loop, comprehensions, and unpacking all use the iterator protocol. Understanding iterators is foundational to understanding how Python handles sequences.

[[iterators|Iterators]]

[[for-loop-internals|For Loop Internals]]

Generators are the Pythonic way to create iterators. They use `yield` to produce values lazily and `yield from` to delegate to sub-iterators.

[[generators|Generators]]

[[yield-from|Yield From]]

The `itertools` module provides composable iterator building blocks (chain, zip, filter, map, accumulate) that follow this pattern.

[[design-patterns-overview|Design Patterns Overview]]

---

## Common Misconceptions

Misconception 1: "Iterators and iterables are the same thing."
Reality: An iterable has `__iter__()` that returns an iterator. An iterator has both `__iter__()` (returns self) and `__next__()`. A list is iterable but is not an iterator. `iter(my_list)` returns an iterator over the list. The distinction matters because iterables can be traversed multiple times; iterators are consumed after one pass.

Misconception 2: "You need to write iterator classes in Python."
Reality: Generators cover the vast majority of use cases with far less code. Write an iterator class only when you need to implement a complex protocol (like `__len__` or `__contains__` alongside iteration) or when you need the iterator to be picklable/serializable.

---

## Why It Matters in Practice

Iterators enable processing data that does not fit in memory. Reading a 50GB log file line by line, streaming rows from a database cursor, or processing an infinite event stream - all of these require iterators. Without lazy evaluation, you would need to load everything into memory before processing.

Python's ecosystem is built on iterators. Database ORMs return querysets (lazy iterators). Web frameworks stream responses. Data processing pipelines chain iterators. Understanding the pattern is essential for writing memory-efficient Python.

---

## Interview Angle

Common question forms:
- "What is the difference between an iterable and an iterator?"
- "Implement a custom iterator for a binary tree."
- "How do generators relate to the Iterator pattern?"

Answer frame:
Define the iterator protocol (`__iter__` + `__next__`). Distinguish iterables (can create iterators) from iterators (consumed after one pass). Show a generator as the Pythonic implementation. Explain lazy evaluation and its memory benefits. Give the tree traversal example with different traversal strategies.

---

## Related Notes

- [[iterators|Iterators]]
- [[for-loop-internals|For Loop Internals]]
- [[generators|Generators]]
- [[yield-from|Yield From]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[lazy-evaluation|Lazy Evaluation]]
