---
title: 08 - How Python Dicts Work Internally
description: "A deep dive into CPython's compact dict implementation  -  the split indices/entries layout, hash collision via perturbation probing, load factor management, and why the 3.6 redesign preserved insertion order as a byproduct."
tags: [dict-internals, hash-table, compact-dict, open-addressing, ma_keys, dk_indices, layer-1, core]
status: draft
difficulty: advanced
layer: 1
domain: core
created: 2026-05-18
---

# How Python Dicts Work Internally

> CPython's dictionary is one of the most carefully engineered data structures in any language runtime  -  understanding the compact dict layout reveals why lookup is fast, why insertion order is free, and why hash collisions are survivable.

---

## Quick Reference

**Core idea:**
- Pre-3.6: single sparse hash table (`(hash, key, value)` per slot), iteration order was slot order (not insertion order)
- 3.6+ compact dict: two arrays  -  `dk_indices` (small, sparse, holds slot indices) + `dk_entries` (dense, insertion-ordered `(hash, key, value)` triples)
- Hash lookup: `slot = hash & mask` -> check `dk_indices[slot]` -> follow index into `dk_entries` -> compare key
- Collision resolution: perturbation probing  -  `slot = (5*slot + perturb + 1) & mask; perturb >>= PERTURB_SHIFT`
- Resize trigger: when `len(dk_entries) > dk_size * 2/3`, table doubles (approximately) and all entries are rehashed

**Tricky points:**
- `dict.__sizeof__()` reflects the internal struct; `sys.getsizeof()` adds GC header overhead
- A dict with 1000 deleted entries (tombstones in the indices array) but only 5 live entries may still hold a large allocation until resized
- Changing a dict's size during iteration invalidates the iterator  -  CPython tracks a `ma_version_tag` to detect this
- `dict.keys()` returns a view that reads `dk_entries` live  -  not a copy; do not mutate the dict while iterating a view
- Shared keys optimization: instances of the same class share `dk_keys` structure, storing only per-instance values in a separate array

---

## What It Is

Imagine an office building where every employee has a mailbox. The mailboxes are numbered, but they are not assigned in the order employees were hired  -  they are assigned based on each employee's employee ID run through a formula. To find someone's mailbox, you do not walk from box 1 upward; you apply the formula to their ID and go directly to the predicted box. If someone else's box is already at that address, you try the next one in a defined sequence. The whole system works because most IDs produce unique box numbers, so most lookups require exactly one step.

Python dicts are that mailbox system. The "employee ID" is the object's hash value, the mailbox assignment is the index into the hash table, and the "next box in sequence" rule is the collision resolution strategy. Because most hash values map to unique slots, most lookups find the answer immediately. The table is kept less than two-thirds full  -  enforced by automatic resizing  -  to ensure that collisions remain rare.

Before Python 3.6, the mailbox building stored each employee's full record (name, department, phone number) at their mailbox number. This meant the mailboxes had gaps  -  empty boxes between filled ones  -  because they had to be laid out in hash order, not hire order. Since 3.6, the building keeps a small directory (a number at each mailbox pointing to an employee record) and a separate, dense roster (all employee records in the order they were hired). Looking someone up checks the directory for their box number, which points into the roster. The roster is dense and ordered, so iterating all employees gives you hire order.

---

## How It Actually Works

The pre-3.6 dict used a single C array of `ma_table` entries, each being `(Py_hash_t hash, PyObject *key, PyObject *value)`. For a table with 8 slots, at most 5 could be filled before a resize, and the empty slots were scattered between filled ones. Iteration walked the full sparse array, returning entries in slot position order  -  which varied with the hash values of the keys and bore no relationship to insertion order.

The compact dict (`dictobject.c`, CPython 3.6+) splits this into two structures inside `PyDictKeysObject`:

```c
struct PyDictKeysObject {
    Py_ssize_t dk_refcnt;
    Py_ssize_t dk_size;         /* number of slots in dk_indices */
    dict_lookup_func dk_lookup;
    Py_ssize_t dk_usable;       /* number of free entries remaining */
    Py_ssize_t dk_nentries;     /* number of used entries in dk_entries */
    char dk_indices[];          /* hash table: stores indices into dk_entries */
    /* dk_entries follows in memory: array of PyDictKeyEntry */
};
```

`dk_indices` is a sparse array of small integers (1, 2, or 4 bytes per slot depending on table size). A slot contains either `DKIX_EMPTY` (-1), `DKIX_DUMMY` (-2, tombstone for deleted entries), or a non-negative index into `dk_entries`. `dk_entries` is a dense array of `(hash, key, value)` triples stored in insertion order. When you call `d["key"]`, Python computes `h = hash("key")`, calculates `slot = h & (dk_size - 1)`, reads `i = dk_indices[slot]`, and checks `dk_entries[i].key == "key"`. If the key matches, `dk_entries[i].value` is returned.

Collision resolution uses perturbation probing, derived from Python's original hash-table design by Tim Peters:

```
perturb = hash
while True:
    slot = (5 * slot + perturb + 1) & mask
    perturb >>= PERTURB_SHIFT   # PERTURB_SHIFT = 5
```

This sequence mixes the upper bits of the hash into the probe sequence, which prevents the clustering that affects pure linear probing when many keys share the same lower bits. The sequence visits all slots before repeating (because 5*i+1 mod 2^n is a permutation), so the table will always find an empty slot as long as one exists.

When `dk_usable` drops to 0 (roughly 2/3 of `dk_size` slots used), `dictresize()` is called. It allocates a new `PyDictKeysObject` with approximately double the `dk_size`, copies all live entries from `dk_entries` into the new structure in their original order, and recomputes all slot assignments. This is why iteration order is preserved through resizes  -  the entries array is copied in order, and only the indices are recomputed.

---

## How It Connects

The same hash-table principles  -  open addressing, load factor, perturbation probing  -  are used by Python sets. A set is essentially a dict with no values, and `setobject.c` uses the same collision resolution algorithm.

[[sets|Sets]]

The `__hash__` and `__eq__` contract defines what objects can serve as dict keys. Hash computation calls `type(obj).__hash__(obj)`, and the result must be stable for the lifetime of the object's membership in the dict.

[[dicts|Dictionaries]]

Shared-keys dicts (split-table dicts) are the mechanism behind CPython's memory optimization for class instances. When you create many instances of the same class, the `__dict__` of each instance shares the keys structure with all other instances, storing only the per-instance values separately.

[[class-creation|Class Creation]]

---

## Common Misconceptions

Misconception 1: "Dict insertion order in Python 3.6 is a CPython implementation detail."
Reality: Python 3.6 implemented it as a CPython detail, but Python 3.7 made it a language specification. All conforming Python implementations must preserve insertion order in dicts.

Misconception 2: "Deleting a dict key immediately frees memory."
Reality: Deletion places a tombstone (`DKIX_DUMMY`) in `dk_indices` to preserve probe sequences for subsequent lookups. The entry slot in `dk_entries` is also cleared, but the table's overall size does not shrink until the next resize event. Repeated deletion and insertion can leave a dict with many tombstones and excessive allocated size.

Misconception 3: "Two objects with the same `repr` are the same key."
Reality: Dict key identity is determined by `hash(key)` and `key == stored_key`. Two objects with identical string representation but different hashes or non-equal `__eq__` are different keys. Two objects with different `repr` but equal `__hash__` and `__eq__` (like `1` and `1.0`) map to the same key.

---

## Why It Matters in Practice

Understanding the load factor explains why `d.__sizeof__()` can be much larger than the amount of data it logically contains. A dict with 5 keys may allocate 8 or 16 slots. A dict built up to 1000 keys and then cleared to 5 keys still holds the large allocation until a resize happens. `copy()` or `{k: v for k, v in d.items()}` forces a fresh allocation sized to the current content.

The tombstone mechanism explains a subtle bug: iterating a dict view while deleting keys does not cause `RuntimeError` only if the table does not resize. Since resize is triggered by insertion (not deletion), you can sometimes delete during iteration without error  -  but the behavior depends on the table's current occupancy, making it an unreliable pattern. Always convert to `list(d.items())` before iterating if mutations are needed.

---

## Interview Angle

Common question forms:
- "Explain how Python dict lookup works."
- "What changed about Python dicts in version 3.6?"
- "Why do dict keys need to be hashable?"

Answer frame:
Dict lookup: compute `h = hash(key)`, `slot = h & mask`, read `dk_indices[slot]` to get an entry index, compare key at that index. On collision, use perturbation probing. Keys must be hashable because the hash determines which slot to check  -  a mutable object could change its hash after insertion, making it unfindable. The 3.6 change: split into a dense `dk_entries` array (insertion-ordered) and a sparse `dk_indices` array (hash table), making insertion order a structural property rather than an accident.

---

## Related Notes

- [[dicts|Dictionaries]]
- [[sets|Sets]]
- [[dunder-methods|Dunder Methods]]
- [[mutability|Mutability]]
- [[python-memory-model|Python Memory Model]]
