---
title: 04 - Sets
description: "Python sets are hash tables storing keys only — O(1) membership testing, mathematical set operations, and a frozenset variant that is hashable and usable as a dict key."
tags: [sets, frozenset, hash-table, membership, set-operations, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Sets

> A Python set is a hash table where every element is its own key and there is no value — which buys you O(1) membership testing and mathematical set algebra at the cost of unsorted, unindexed storage.

---

## Quick Reference

**Core idea:**
- Implemented as a hash table (same open-addressing design as `dict`) storing `(hash, key)` pairs, no values
- `add`, `discard`, `in` are all O(1) average; `remove` raises `KeyError` if absent, `discard` does not
- Set operations: `|` union, `&` intersection, `-` difference, `^` symmetric difference — all return new sets
- `frozenset` is the immutable variant: hashable, usable as a dict key or as a set member
- `set` itself is not hashable — attempting `hash(set())` raises `TypeError`

**Tricky points:**
- `{1, 2, 3}` is a set literal; `{}` is an empty dict — use `set()` for an empty set
- `set` is unordered — iteration order is not guaranteed and will differ between runs (hash randomization)
- `in` on a set is O(1); `in` on a list is O(n) linear scan — this distinction matters at scale
- `s.remove(x)` raises `KeyError` if `x` is absent; `s.discard(x)` is the safe no-error alternative
- Sets use hash randomization (since Python 3.3) — `PYTHONHASHSEED` controls reproducibility for testing

---

## What It Is

Think of a bouncer at an exclusive club who has memorized a guest list. When you arrive, the bouncer looks at your face, applies a mental formula to it, and instantly knows whether you are on the list or not — without scanning every name from top to bottom. The bouncer does not care what order names were added to the list, and no name appears twice. The ability to answer "are you on the list?" in constant time, regardless of list size, is exactly what makes a set valuable.

A Python set stores unique elements and answers membership questions fast. The uniqueness guarantee means adding the same element twice is a no-op — the set silently ignores the second addition. The lack of ordering means you cannot ask for the "first" or "third" element and you cannot index a set with `s[0]`. What you can do is test membership, iterate over all elements, and perform the classical mathematical set operations: union, intersection, difference, and symmetric difference.

Sets are the right container when the questions you ask are "is X present?", "what elements are in both A and B?", or "what elements are unique to A?". Replacing a list with a set for repeated membership testing is one of the highest-return micro-optimizations available in Python, and it requires only a single-character change in many cases.

---

## How It Actually Works

CPython's set implementation in `setobject.c` mirrors the dict's hash table design. Each entry is a `setentry` struct holding `(Py_hash_t hash, PyObject *key)`. The table starts with 8 slots, grows by roughly doubling when the load factor exceeds 2/3, and uses the same perturbation-based open addressing as dicts to resolve collisions.

```c
typedef struct {
    Py_hash_t hash;
    PyObject *key;
} setentry;
```

When you call `x in s`, Python computes `h = hash(x)`, masks it to find the initial slot, and then either finds `x` (returning `True`), finds an empty slot (returning `False`), or probes further on collision. Because hash computation is O(1) for most built-in types (strings cache their hash, integers compute it in constant time), and because the probe sequence terminates quickly when the load factor is kept below 2/3, membership testing is effectively constant time.

The difference between `set` and `frozenset` is purely about mutability and hashability. `frozenset` objects compute a hash lazily at first access, cache it in the object, and then return the cached value on subsequent calls. This is safe because `frozenset` content never changes. Regular `set` objects do not implement `__hash__` at all — `set.__hash__` is set to `None` explicitly, which causes `TypeError` when `hash()` is called, even if the set happens to be empty.

```python
fs = frozenset([1, 2, 3])
d = {fs: "value"}     # works — frozenset is hashable
s = {1, 2, 3}
d = {s: "value"}      # TypeError: unhashable type: 'set'
```

---

## How It Connects

Sets and dicts share the same hash table internals. Understanding dict internals — the compact layout, load factor, and collision resolution — transfers directly to sets.

[[dict-internals|How Python Dicts Work Internally]]

`frozenset` is the hashable cousin of `set`, just as `tuple` is the hashable cousin of `list`. The pattern of having a mutable/immutable pair with matching semantics recurs throughout Python's data model.

[[tuples|Tuples]]

The `__hash__` and `__eq__` contract governs what can be stored in a set. Any object stored in a set must have a stable hash for the lifetime of its membership — which is why mutable objects cannot reliably be set members.

[[dunder-methods|Dunder Methods]]

---

## Common Misconceptions

Misconception 1: "`{}` creates an empty set."
Reality: `{}` creates an empty dict. The empty set requires `set()`. This is a historical artifact — `{}` was dict syntax before set literals were added.

Misconception 2: "Sets maintain insertion order since Python 3.7, just like dicts."
Reality: The insertion-order guarantee in 3.7 applies to `dict` only. Sets remain explicitly unordered, and their iteration order can vary between runs due to hash randomization.

Misconception 3: "`frozenset` and `set` have the same performance characteristics."
Reality: For most operations they do, but `frozenset` is hashable and can be placed inside another set or used as a dict key, while `set` cannot. The hashability difference has significant design implications.

---

## Why It Matters in Practice

The O(1) vs O(n) membership test is the most impactful practical difference between sets and lists. Code that filters duplicates by checking `if item not in seen_list` runs in O(n²) time; replacing `seen_list` with a `seen_set` drops it to O(n). At a thousand items the difference is negligible; at a million it is the difference between a sub-second operation and something that takes minutes.

Set operations (`&`, `|`, `-`, `^`) enable elegant data reconciliation code. Finding rows present in dataset A but not dataset B, or the common elements across two lookup tables, are single-expression operations on sets. This replaces nested loops or manual tracking variables with something that is both faster and clearer to read.

---

## Interview Angle

Common question forms:
- "Why is `in` O(1) for a set but O(n) for a list?"
- "What is the difference between `set` and `frozenset`?"
- "How would you remove duplicates from a list while preserving order?"

Answer frame:
Sets use a hash table — lookup computes a hash and checks a specific slot, O(1). Lists require scanning element by element, O(n). `frozenset` is hashable because it is immutable; `set` is not. To deduplicate while preserving order: `list(dict.fromkeys(items))` (Python 3.7+), because dicts preserve insertion order and discard duplicate keys.

---

## Related Notes

- [[dicts|Dictionaries]]
- [[dict-internals|How Python Dicts Work Internally]]
- [[tuples|Tuples]]
- [[mutability|Mutability]]
- [[lists|Lists]]
