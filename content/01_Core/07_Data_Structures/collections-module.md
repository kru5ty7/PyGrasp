---
title: 07 - collections Module
description: "The collections module provides specialized container types  -  deque, defaultdict, Counter, OrderedDict, and namedtuple  -  each solving a specific limitation of the built-in list, dict, and tuple."
tags: [collections, deque, defaultdict, counter, ordereddict, namedtuple, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# collections Module

> The `collections` module is Python's answer to "the built-in containers are almost right"  -  each type in it fills exactly one gap that `list`, `dict`, or `tuple` cannot fill efficiently.

---

## Quick Reference

**Core idea:**
- `deque`: doubly-linked list of fixed-size blocks  -  O(1) `appendleft`/`popleft` (unlike list's O(n))
- `defaultdict`: `dict` subclass that calls `__missing__` with a factory when a key is absent, eliminating `KeyError`
- `Counter`: multiset  -  maps elements to integer counts; supports arithmetic (`+`, `-`, `&`, `|`) between counters
- `OrderedDict`: predates 3.7 ordering guarantee; still unique for `move_to_end()` and equality that considers order
- `namedtuple`: factory function that generates a `tuple` subclass class with named field descriptors  -  not a decorator

**Tricky points:**
- `deque` is not a list  -  it does not support O(1) random access by index; `deque[500]` is O(n)
- `defaultdict(list)` passes the factory callable, not the result  -  `defaultdict(list)` not `defaultdict([])`
- `Counter` subtraction clips at zero: `Counter('aab') - Counter('ab')` gives `Counter({'a': 1})`, not `Counter({'a': 1, 'b': -1})`
- `namedtuple` creates a class, not a class instance  -  the result of calling `namedtuple(...)` must itself be instantiated
- `deque(maxlen=n)` creates a bounded deque  -  appending beyond capacity silently drops from the opposite end

---

## What It Is

Imagine a Swiss Army knife versus a specialized tool kit. A regular kitchen knife can spread butter, but a palette knife does it better. A dict can count occurrences with `d[k] = d.get(k, 0) + 1`, but `Counter` does it in one line and adds mathematical operations on top. The built-in containers are excellent general tools; the `collections` module provides the specialized blades that make specific patterns both faster and more readable.

`deque` (double-ended queue) solves the problem that Python lists are poor at front-end operations. A list stores elements in a contiguous C array; adding to the front requires shifting every existing element one position to the right  -  O(n). A `deque` uses a doubly-linked structure of fixed-size blocks (each block holds several pointers). Adding to either end means either filling the next slot in an existing end-block or allocating a new block  -  O(1). The tradeoff is that `deque` loses random O(1) index access: to find `dq[500]`, you must walk the linked block chain.

`defaultdict` eliminates a ubiquitous pattern. Code that groups items by category almost always needs to create a new empty list when a category is seen for the first time: `if key not in d: d[key] = []`. The `defaultdict(list)` version skips that check  -  the first access to any missing key automatically creates the default value. This is implemented by overriding `__missing__`, which is called by `dict.__getitem__` when a key is not found.

---

## How It Actually Works

`deque` in `_collectionsmodule.c` is implemented as a doubly-linked list of `BLOCKLEN`-element blocks (currently 64 elements per block in CPython). Rather than pointers to individual elements, the linked list connects fixed-size C arrays. This gives `deque` cache locality similar to a list within each block, while still allowing O(1) prepend and append by maintaining `leftblock`/`rightblock` pointers and `leftindex`/`rightindex` offsets. When `appendleft` is called and `leftindex` is 0, a new block is prepended to the chain.

```python
from collections import deque
dq = deque([1, 2, 3], maxlen=5)
dq.appendleft(0)   # O(1)
dq.append(4)       # O(1)
print(dq)          # deque([0, 1, 2, 3, 4], maxlen=5)
dq.append(5)       # deque([1, 2, 3, 4, 5])  -  leftmost dropped
```

`Counter` is a `dict` subclass. Its `__missing__` returns `0` rather than raising `KeyError`, and it adds `most_common(n)` (which uses `heapq.nlargest` for small n, a full sort for large n), and arithmetic operators. `Counter` arithmetic clips at zero for subtraction and intersection: negative counts are silently discarded, enforcing the mathematical multiset semantics where you cannot have fewer than zero of something.

`namedtuple` is a factory function, not a class itself. Calling `Point = namedtuple('Point', ['x', 'y'])` executes a string template of Python class source code, compiles it, and `exec`s it into a fresh namespace  -  returning the resulting class. The generated class is a genuine `tuple` subclass. Field access by name (`p.x`) is implemented by descriptor objects at the class level that call `tuple.__getitem__(self, index)`  -  no `__dict__` per instance, same memory layout as a plain tuple.

```python
from collections import namedtuple
Point = namedtuple('Point', ['x', 'y'])
p = Point(1, 2)
print(p.x, p[0])       # 1 1  -  name and index both work
print(p._asdict())      # {'x': 1, 'y': 2}
p2 = p._replace(x=10)  # returns new instance
print(Point._fields)   # ('x', 'y')
```

---

## How It Connects

`deque` exists because `list` uses a C array that makes front insertion O(n). Understanding why lists are fast at the back and slow at the front makes the deque's block-chain design make sense.

[[lists|Lists]]

`namedtuple` produces a tuple subclass. Its memory layout is identical to a plain tuple  -  one contiguous C array of pointers  -  but with named field access via descriptors. The modern `typing.NamedTuple` syntax provides the same result with type annotations.

[[namedtuples|Named Tuples]]

`Counter` is a `dict` subclass, and `defaultdict` is a `dict` subclass. Both extend dict behavior through `__missing__`  -  a hook in the dict lookup protocol for handling absent keys.

[[dicts|Dictionaries]]

---

## Common Misconceptions

Misconception 1: "`deque` is just a list with a different name  -  use whichever feels right."
Reality: `deque` has O(1) `appendleft`/`popleft` but O(n) random index access. `list` has O(1) random access but O(n) `insert(0, x)`. They serve different use cases  -  a deque is not a drop-in replacement for a list.

Misconception 2: "`defaultdict` catches `KeyError` from any source."
Reality: `defaultdict.__missing__` is only called by `__getitem__`  -  subscript access like `d[missing_key]`. It is not called by `d.get(missing_key)` (which returns `None`) or `missing_key in d` (which returns `False`). Only `d[missing_key]` triggers the factory.

Misconception 3: "`OrderedDict` is now identical to `dict` in Python 3.7+`."
Reality: Regular `dict` preserves insertion order, but `OrderedDict` still has unique behavior: two `OrderedDict`s with the same items in different insertion orders are considered unequal, while two `dict`s with the same items are equal regardless of insertion order. `OrderedDict.move_to_end()` also has no equivalent on plain `dict`.

---

## Why It Matters in Practice

`defaultdict` is the idiomatic way to group items in Python. The pattern `grouped = defaultdict(list); for item in data: grouped[item.category].append(item)` is cleaner, faster (no repeated `in` checks), and more readable than manually initializing empty lists. Similarly, `Counter(words)` replaces a common `collections.defaultdict(int)` word-count pattern with a single expression that also adds useful methods.

`deque` matters whenever you implement a BFS (breadth-first search), a sliding window, a producer-consumer queue, or any algorithm that needs FIFO access. Using a list for `popleft` in these cases is a common performance mistake that becomes catastrophic at scale  -  O(1) vs O(n) per operation, O(n) vs O(n²) overall.

---

## Interview Angle

Common question forms:
- "How would you implement a sliding window of the last N items?"
- "What is the most efficient way to count word frequencies in Python?"
- "Why would you use `defaultdict` instead of a regular `dict`?"

Answer frame:
Sliding window -> `deque(maxlen=n)`: O(1) append drops the oldest item automatically. Word count -> `Counter(words)`: cleaner than `dict.get` and adds `most_common`. `defaultdict` -> avoids explicit key-existence checks, calls the factory via `__missing__` only on `__getitem__`, not on `.get()` or `in`.

---

## Related Notes

- [[lists|Lists]]
- [[dicts|Dictionaries]]
- [[namedtuples|Named Tuples]]
- [[itertools|itertools Module]]
- [[python-data-model|Python Data Model]]
