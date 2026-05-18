---
title: 03 - Dictionaries
description: "Python dicts are hash tables with open addressing that, since 3.6, use a compact layout preserving insertion order — understanding their internals explains hash collisions, load factors, and why keys must be hashable."
tags: [dicts, hash-table, open-addressing, compact-dict, insertion-order, __hash__, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Dictionaries

> A Python dictionary is a hash table that trades memory for speed — every lookup is O(1) because Python knows exactly which slot to check before it even looks.

---

## Quick Reference

**Core idea:**
- Since 3.6: compact dict — a small `indices` array (sparse, holds slot numbers) plus a dense `entries` array (hash, key, value triples in insertion order)
- Load factor threshold: ~2/3 — when filled, dict doubles (approximately) and rehashes all entries
- `__hash__` and `__eq__` must be consistent: objects that compare equal must have equal hashes
- Dict views (`keys()`, `values()`, `items()`) are live proxies — they reflect changes to the dict in real time
- `len(d)` is O(1) — stored as a separate counter, not computed by scanning

**Tricky points:**
- Changing a dict's size during iteration raises `RuntimeError` — the indices array may have been reallocated
- Float `1.0` and int `1` hash to the same value and compare equal — `{1: 'a', 1.0: 'b'}` has one key
- Default `object.__hash__` is based on `id()` — two distinct objects are never equal unless `__eq__` says otherwise
- `dict.update()` and `|=` (3.9+) are in-place; `d1 | d2` creates a new dict
- `dict.setdefault(k, v)` inserts only if `k` is absent — more efficient than `if k not in d: d[k] = v`

---

## What It Is

Imagine a massive library where every book has a unique call number. Instead of walking the shelves linearly, you apply a formula to the call number that tells you exactly which shelf to check. If that shelf is occupied by a different book (a collision), you check the next shelf according to a fixed rule until you find either the book or an empty shelf. Because this formula is fast and shelves are rarely full, you almost always find your book in one or two steps.

That is how a hash table works, and Python's `dict` is an exceptionally well-tuned one. You provide a key, Python calls `hash(key)` to get a number, uses that number to select a slot in a C array, and either finds your value there or finds out the key does not exist — all in constant time on average. The price you pay is memory: the table must stay less than two-thirds full to keep collisions rare, which means at least a third of every dict's allocated capacity sits empty.

Since Python 3.7, dictionaries also preserve insertion order. This is not a side effect — it is a language guarantee. The mechanism that makes this work without sacrificing hash-table lookup speed is the compact dict layout introduced in CPython 3.6: a small, sparse indices array stores slot numbers, while a dense entries array holds key-value pairs in the order they were inserted. Iteration over the entries array gives you insertion order; the indices array handles fast lookup.

---

## How It Actually Works

Before 3.6, a CPython dict was a single sparse array where each slot held `(hash, key, value)`. Because the array had to be sparse to keep collision rates low, a 6-item dict might allocate 8 slots, leaving 2 empty — and more importantly, iteration order was the order of slot positions, which is not insertion order.

The compact dict (introduced by Raymond Hettinger and shipped in 3.6) splits the structure into two parts. The `ma_keys` object contains a compact `dk_entries` array — one `(hash, key, value)` triple per item, stored densely in insertion order — plus a small `dk_indices` lookup array whose slots contain either a sentinel (empty or deleted) or an index into `dk_entries`. For a dict with 6 items, `dk_entries` has exactly 6 entries; `dk_indices` might be 8 slots, but each occupied slot is just a small integer. This layout is both cache-friendlier (the entries array is dense) and memory-efficient (the indices array holds integers, not full triples).

```python
import sys
d = {'a': 1, 'b': 2, 'c': 3}
print(d.__sizeof__())   # internal struct size in bytes
print(sys.getsizeof(d)) # includes GC header
```

When a key is looked up, Python computes `h = hash(key)`, then calculates `slot = h & (dk_size - 1)` (a bitmask, since table sizes are powers of two). If `dk_indices[slot]` is empty, the key is absent. If it holds index `i`, Python checks `dk_entries[i].key == key`. If they match, the value is returned. If they do not (a collision), Python probes the next slot using a perturbation algorithm: `slot = (5*slot + perturbation + 1) & mask; perturbation >>= PERTURB_SHIFT`. This is open addressing with a scheme that mixes the upper bits of the hash into subsequent probes, avoiding the clustering that pure linear probing suffers.

---

## How It Connects

The `__hash__` and `__eq__` contract is the foundation of every dict operation. Any class that overrides `__eq__` without overriding `__hash__` becomes unhashable by default in Python 3 — the language enforces the contract.

[[dunder-methods|Dunder Methods]]

The compact dict's insertion-order guarantee made `OrderedDict` mostly redundant for ordering purposes, but understanding the pre-3.6 sparse layout explains why `OrderedDict` existed and why it still has unique methods like `move_to_end`.

[[dict-internals|How Python Dicts Work Internally]]

Sets use the same hash table machinery as dicts — a set is essentially a dict with keys only and no values. Their shared lineage means identical performance characteristics: O(1) average lookup, the same load factor, the same collision resolution.

[[sets|Sets]]

---

## Common Misconceptions

Misconception 1: "Dict insertion order is just a CPython implementation detail — don't rely on it."
Reality: Since Python 3.7, insertion order preservation is a language specification guarantee, not an implementation detail. Every compliant Python implementation must preserve it.

Misconception 2: "Dict views like `keys()` and `items()` return lists that you can modify."
Reality: Dict views are live proxy objects. `d.keys()` does not create a snapshot — it reflects the current state of `d`. Iterating a view while modifying the underlying dict raises `RuntimeError`.

Misconception 3: "Any object can be a dict key as long as it has a unique value."
Reality: Keys must be hashable — they must implement `__hash__` and `__eq__`. Lists, sets, and other mutable containers are not hashable and cannot be dict keys.

---

## Why It Matters in Practice

Dict lookup being O(1) is the reason patterns like `if name in lookup_dict` scale to millions of entries while `if name in list_of_names` does not. The choice of data structure here can be the difference between a 10ms response time and a 10-second one. Whenever code searches a list for membership more than once, replacing the list with a set or the keys of a dict drops the operation from O(n) to O(1).

The live-proxy behavior of dict views is a frequent source of bugs. Code that captures `keys = d.keys()` and then modifies `d` before iterating `keys` will reflect the modifications — or raise `RuntimeError` if the size changed. Always convert to a list (`list(d.keys())`) before iterating if you intend to modify the dict during the loop.

---

## Interview Angle

Common question forms:
- "How does Python implement dictionaries internally?"
- "What happens when two keys hash to the same value?"
- "Why did Python 3.7 guarantee dict ordering?"

Answer frame:
A strong answer covers: hash tables with open addressing, the compact dict layout (indices array + dense entries array), collision resolution via perturbation probing, load factor ~2/3 triggering resize and rehash, and the `__hash__`/`__eq__` contract. For the 3.7 ordering question: the compact layout stores entries densely in insertion order as a side effect of the design — the language spec formalized what the implementation already guaranteed.

---

## Related Notes

- [[dict-internals|How Python Dicts Work Internally]]
- [[sets|Sets]]
- [[dunder-methods|Dunder Methods]]
- [[mutability|Mutability]]
- [[python-memory-model|Python Memory Model]]
