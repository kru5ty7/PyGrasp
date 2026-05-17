---
title: 19 - Cyclic References
description: A cyclic reference occurs when two or more objects reference each other, forming a loop that prevents their reference counts from reaching zero — this is the class of memory leak that CPython's cyclic garbage collector exists to detect and break.
tags: [cyclic-references, reference-counting, garbage-collection, memory-leak, cpython, layer-0, core]
status: draft
difficulty: intermediate
layer: 0
domain: core
created: 2026-05-17
---

# Cyclic References

> A cyclic reference occurs when two or more objects reference each other, forming a loop that prevents their reference counts from reaching zero — this is the class of memory leak that CPython's cyclic garbage collector exists to detect and break.

---

## Quick Reference

**Core idea:**
- A cyclic reference: object A references object B, and B references A (directly or through a chain) — neither can ever reach `ob_refcnt == 0` through reference counting alone
- The simplest cycle: `a = []; a.append(a)` — the list contains a reference to itself; `del a` drops the external reference, but the list still has `ob_refcnt == 1` (from itself)
- CPython's **cyclic garbage collector** (`gc` module) detects and collects cycles — it runs periodically, not on every object deallocation
- Only **container objects** (objects that can hold references to other objects) can participate in cycles — `int`, `str`, `bytes` cannot
- `gc.collect()` triggers a manual collection cycle; `gc.disable()` turns the cyclic GC off (reference counting still works; only cycles are affected)

**Tricky points:**
- Reference counting handles the **vast majority** of deallocations in CPython — the cyclic GC is a supplemental collector for the edge cases reference counting cannot handle
- Objects with `__del__` (finalizers) that are part of cycles were historically un-collectable — CPython 3.4+ resolved this by running `__del__` before breaking the cycle
- `weakref.ref()` creates a **weak reference** that does not increment `ob_refcnt` — using weak references to break cycles is the manual alternative to relying on the cyclic GC
- The cyclic GC uses a **generational** scheme (3 generations) — long-lived objects are promoted to older generations and collected less frequently
- Cycles involving only objects in the young generation are collected most frequently; cross-generation cycles are collected rarely

---

## What It Is

Think of a hotel key card system with a quirk: a room can only be cleaned and released when no key cards for it exist. Most rooms work normally — the guest returns the key card, the count drops to zero, and the room is cleaned. But imagine two rooms that each grant access to the other: Room A's key is kept inside Room B's safe, and Room B's key is kept inside Room A's safe. No guest holds either key card directly. Both rooms are effectively abandoned, but neither can be cleaned because each room still has a key card — locked inside the other. This is a cyclic reference: two objects keeping each other alive with no external holder, each counting as "in use" when neither is actually reachable from any live code.

In Python, reference counting means every object tracks how many other objects or variable names point to it. When that count reaches zero, the object is immediately freed. Cycles defeat this mechanism: if A points to B and B points to A, and no external reference to either exists, both still have a reference count of 1 (from the other). They will never reach zero. Without intervention, they would remain allocated forever — a memory leak.

This is exactly what CPython's cyclic garbage collector handles. The `gc` module implements a mark-and-sweep-style algorithm specifically for container objects (lists, dicts, sets, tuples containing mutable objects, class instances). It periodically traces through all container objects, identifies groups that are only reachable from each other and not from the rest of the program, and frees them as a group, breaking the cycle's reference counts in the process.

---

## How It Actually Works

CPython's cyclic GC maintains three "generations" — three doubly linked lists of container objects, ordered by age. Every newly created container object is added to generation 0. When generation 0 reaches a threshold (default: 700 objects), the GC runs a collection cycle on generation 0. Objects that survive are promoted to generation 1. When generation 1 reaches its threshold, generation 1 and 0 are collected together, and survivors are promoted to generation 2. Generation 2 is collected only occasionally.

The collection algorithm is a simplified mark-and-sweep. For all objects in the target generation, the GC copies their `ob_refcnt` into a temporary count field. Then it iterates over each object and, for each object that the container references, decrements the corresponding temporary count. After this traversal, any object whose temporary count has reached zero can only be reached from within the cycle — no external references exist. These objects form the unreachable set. The GC then calls their finalizers (`__del__`) if any, breaks the reference cycles by clearing the container contents (calling `tp_clear` on each object), and frees the memory.

The `weakref` module provides an escape from this mechanism. A `weakref.ref(obj)` creates a reference to `obj` that does not increment `ob_refcnt`. If `obj`'s only remaining references are weak references, its reference count reaches zero and it is freed normally — no cyclic GC needed. This is why cache implementations, parent-child object graphs, and observer patterns often use weak references: they allow one direction of a potential cycle to be non-owning.

---

## How It Connects

Cyclic references are the direct limitation of reference counting. Understanding that reference counting works perfectly for acyclic object graphs but fails for cycles explains why CPython has two garbage collection mechanisms: the fast per-object reference counting and the periodic cyclic GC.
[[reference-counting|Reference Counting]]

The cyclic GC is the mechanism Python uses to collect cycles. Its generational scheme, threshold configuration, and interaction with `__del__` methods are described in detail in the garbage collection note.
[[garbage-collection|Garbage Collection]]

---

## Common Misconceptions

Misconception 1: "Cyclic references always cause memory leaks in Python."
Reality: CPython's cyclic GC collects cyclic garbage automatically. Cyclic references slow down collection (the periodic GC has overhead) and delay deallocation (objects are not freed until the next GC cycle rather than immediately when unreachable), but they do not cause permanent leaks in normal code. Memory leaks from cyclic references only occur if the cyclic GC is disabled (`gc.disable()`) or if objects have `__del__` methods that prevent collection (mostly resolved in Python 3.4+).

Misconception 2: "You should avoid creating any cyclic references in your code."
Reality: Many natural data structures form cycles — a doubly linked list (each node references its neighbors), a parent-child tree (each child has a reference back to its parent), an object that holds a reference to itself for caching. These are fine in CPython because the cyclic GC handles them. Cycles do incur GC overhead and delay deallocation, which matters for performance-sensitive or memory-constrained code. For those cases, weak references are the right tool — not avoiding cyclic data structures entirely.

---

## Why It Matters in Practice

Profiling memory in Python applications sometimes reveals that cyclic references are preventing timely deallocation of large objects — file handles, network connections, or large data structures that are part of a reference cycle. `gc.get_objects()` returns all objects tracked by the cyclic GC; combining it with `objgraph` (a third-party library) can trace the reference chain that keeps a specific object alive. Fixing the cycle (or using a weak reference for one edge) allows immediate deallocation when the external reference is dropped.

CPython extension modules written in C must register container types with the cyclic GC by implementing the `tp_traverse` and `tp_clear` slots. If a C extension defines a container type (one that holds references to Python objects) without these slots, the cyclic GC cannot trace its references, and cycles involving those objects will leak. This is a common source of memory leaks in poorly written C extensions.

---

## Interview Angle

Common question forms:
- "What is a cyclic reference and why is it a problem?"
- "How does Python handle memory leaks from cycles?"
- "What is the difference between reference counting and the cyclic garbage collector?"

Answer frame: A cyclic reference is a loop in the reference graph — A?B?A — where no external reference exists but neither object's count reaches zero. Reference counting cannot free them. CPython's cyclic GC supplements reference counting by periodically running a mark-and-sweep over container objects, finding unreachable cycles, and freeing them. Three generations — new objects collected frequently, old objects rarely. Weak references break cycles manually: one direction is a `weakref.ref()` that doesn't increment the count.

---

## Related Notes

- [[reference-counting|Reference Counting]]
- [[garbage-collection|Garbage Collection]]
- [[python-memory-model|Python's Memory Model]]
