---
title: 09 - Shallow Copy vs Deep Copy
description: A shallow copy creates a new container object but populates it with references to the same inner objects; a deep copy recursively creates new copies of all nested objects — understanding the difference is essential when sharing mutable nested data structures.
tags: [shallow-copy, deep-copy, copy, mutability, references, layer-0, core]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# Shallow Copy vs Deep Copy

> A shallow copy creates a new container object but populates it with references to the same inner objects; a deep copy recursively creates new copies of all nested objects — understanding the difference is essential when sharing mutable nested data structures.

---

## Quick Reference

**Core idea:**
- **Shallow copy**: new outer container, same inner objects — `copy.copy(x)`, `list[:]`, `dict.copy()`, `list(original)`
- **Deep copy**: new outer container, new copies of all nested objects recursively — `copy.deepcopy(x)`
- For **flat containers** (list of ints, dict of strings), shallow copy is sufficient — immutable values cannot be modified, so sharing them is safe
- For **nested containers** (list of lists, dict of dicts), shallow copy shares the inner containers — modifying them via the copy also modifies the original
- **Assignment** (`b = a`) is neither — it creates a new reference to the same object, not a copy at all

**Tricky points:**
- `copy.deepcopy()` handles **circular references** — it maintains a memo dict of already-copied objects to avoid infinite recursion on cyclic object graphs
- Immutable objects (int, str, tuple of immutables) are returned **as-is** by both `copy.copy()` and `copy.deepcopy()` — copying them is pointless since they cannot be modified
- A tuple of mutable objects (e.g., `([1,2], [3,4])`) is immutable at the top level but shallow-copyable — the tuple cannot be changed, but the lists inside it can be mutated
- Custom classes can define `__copy__()` and `__deepcopy__()` to control copy behavior
- `copy.deepcopy()` is significantly slower for large nested structures — only use it when you actually need independent nested objects

---

## What It Is

Think of copying a filing cabinet. An assignment is giving someone the key to your filing cabinet — there is now one cabinet with two keys; changes either person makes affect what the other sees. A shallow copy is making a new filing cabinet and placing the same manila folders in it — the cabinet is new but the folders are shared. If you pull out a folder and add a page, the other cabinet's version of that folder also has the new page (it is the same folder object). A deep copy is making a new filing cabinet and also photocopying every folder inside it — the cabinet is new, the folders are new, and every piece of paper in every folder is a new copy. Changes to the copy's contents have no effect on the original.

Python variables are references to objects, not containers for values. When you write `b = a`, you give `b` a reference to the same object as `a`. There is one object with two names. Shallow copy and deep copy both produce genuinely new container objects — the container's identity (`id()`) differs from the original. What varies is what they put inside the new container.

Shallow copy creates the outer container and fills it by copying the references from the original. The references still point to the same inner objects. For a flat list of integers, this is fine — integers are immutable, so sharing them between the original and copy is safe. For a list of lists, the inner lists are mutable and shared — mutating an inner list via the copy mutates the same list object that the original also references.

---

## How It Actually Works

In CPython, `copy.copy(obj)` checks for `__copy__()` first. If the object defines it, that method is called and its return value is the copy. For built-in types, CPython has type-specific fast paths: `list.__copy__` creates a new list and copies the element pointers. For a list `[a, b, c]`, the new list contains the same three pointers — the objects at those pointers (whatever Python objects `a`, `b`, and `c` are) are not duplicated. `dict.copy()` similarly creates a new dict with the same key-value pointer pairs.

`copy.deepcopy(obj)` uses a `memo` dict (mapping `id(original_obj)` to `copied_obj`) to track every object it has already copied, preventing infinite recursion on cyclic structures. The algorithm: if the object's `id` is already in `memo`, return the already-created copy. Otherwise, create a new empty container of the same type, add the mapping `{id(obj): new_container}` to `memo`, then recursively deep-copy each element and add it to the new container. Immutable atoms (int, str, bool, None, float) are returned as-is from `deepcopy` — they are their own copies.

The slice notation `my_list[:]` is equivalent to `copy.copy(my_list)` — it produces a new list with copies of the element references. `dict.copy()` and `set.copy()` work the same way. Constructor calls like `list(original)` also produce a shallow copy. These are all shallow copies; `copy.deepcopy()` is the only standard mechanism for deep copies.

---

## How It Connects

The distinction between shallow and deep copy flows directly from Python's mutability model. Immutable objects (int, str, tuple) are safe to share between copies because no code can modify them through any reference. Mutable objects (list, dict, set, class instances) are unsafe to share if any code might modify them through either reference — this is exactly the case where deep copy is needed.
[[mutability|Mutability vs Immutability]]

The copy mechanism is built on Python's reference model — assignment binds a name to an object, and shallow copy duplicates the binding layer while sharing the object layer. Understanding that variables are references (not value containers) is what makes the shallow vs. deep distinction intuitive.
[[python-memory-model|Python's Memory Model]]

---

## Common Misconceptions

Misconception 1: "A tuple is always safe to shallow-copy because tuples are immutable."
Reality: A tuple is immutable at the top level — you cannot append to a tuple or change which objects it references. But if the tuple contains mutable objects (a list, a dict, a class instance), those inner objects can still be mutated. `t = ([1, 2], [3, 4]); t2 = copy.copy(t); t2[0].append(5)` will modify the same inner list that `t[0]` also references. For tuples of immutables (all ints, all strings), shallow copy is fine. For tuples containing mutables, deep copy is needed if you want true independence.

Misconception 2: "`copy.deepcopy()` is always the safe choice."
Reality: Deep copy is correct but potentially expensive. Deeply nested or large object graphs take proportionally longer to copy. For flat data or data where sharing inner objects is intentional (like sharing a configuration object), deep copy is wasteful. The right choice depends on whether the inner objects will be mutated. If they will not (immutable values, or code that guarantees no mutation), shallow copy is sufficient and faster. Deep copy is needed when you need guaranteed independence and inner objects are mutable.

---

## Why It Matters in Practice

The default argument trap in Python is one of the most common bugs caused by shallow sharing. `def fn(x, data=[]):` creates `data` once as a list object shared across all calls. `data.append(x)` mutates the shared list — the mutation persists between calls. The fix: `def fn(x, data=None): data = data or []`. This creates a new list on each call, rather than sharing one mutable list.

When passing a dict or list to a function, passing a reference means the function can mutate the caller's data. If the function should work on a private copy, use `my_dict.copy()` (shallow) or `copy.deepcopy(my_dict)` (deep) at the call site or function entry. This pattern — defensive copying at function boundaries — is essential for writing functions that do not inadvertently modify their callers' data structures.

---

## Interview Angle

Common question forms:
- "What is the difference between shallow and deep copy?"
- "When would you use `copy.deepcopy()`?"
- "What does `b = a` do when `a` is a list?"

Answer frame: Assignment creates a new reference to the same object — no copy. Shallow copy creates a new outer container with the same inner references — safe for flat data, dangerous for nested mutables. Deep copy recursively creates new objects for every level — safe for nested mutables, slower. The rule: if nested objects are immutable or will not be modified, shallow copy is sufficient; if nested mutable objects might be modified independently, use deep copy. Immutable objects (int, str) are not actually copied by either — they are returned as-is.

---

## Related Notes

- [[mutability|Mutability vs Immutability]]
- [[python-memory-model|Python's Memory Model]]
- [[reference-counting|Reference Counting]]
