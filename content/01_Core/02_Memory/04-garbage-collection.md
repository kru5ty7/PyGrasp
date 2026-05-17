---
title: Garbage Collection
description: CPython's garbage collector is a supplementary memory management system that finds and frees objects kept alive only by reference cycles — the one case reference counting alone cannot handle.
tags: [garbage-collection, gc, reference-cycles, memory, cpython, core]
status: draft
difficulty: advanced
layer: 0
domain: core
created: 2026-05-17
---

# Garbage Collection

> CPython's garbage collector is a supplementary memory management system that finds and frees objects kept alive only by reference cycles — the one case reference counting alone cannot handle.

---

## Quick Reference

**Core idea:**
- GC's **only job**: find and free reference cycles — objects that keep each other alive with no external references
- **Generational collector**: 3 generations (0 = new, 2 = old); gen 0 collected most often; gen 2 rarely
- Algorithm: **reference count delta** — subtract internal refs; objects with effective count = 0 are unreachable
- Only **container objects** are tracked (list, dict, set, class instances) — int, str, float are not
- `gc` module: `gc.collect()`, `gc.disable()`, `gc.get_count()`, `gc.freeze()` (Python 3.7+)

**Tricky points:**
- **GC does NOT free most objects** — reference counting does; GC is strictly for cycles
- `gc.collect()` does **NOT return memory to the OS** — freed memory goes back to pymalloc pools
- Common cycle sources: **parent↔child references**, closures capturing their owner, exception tracebacks, callbacks holding `self`
- `gc.disable()` is safe if you're certain your code has no cycles — used in performance-critical tight loops to avoid collection pauses
- Python 3.4+ (PEP 442): `__del__` inside cycles is now handled safely — no longer stranded in `gc.garbage`

---

## What It Is

Imagine you are auditing a company's internal loan system. Most loans are straightforward: someone borrowed money, they repaid it, the ledger balance hits zero, the account is closed. Reference counting handles this case — when an object's reference count reaches zero, it is freed immediately. But now imagine two departments that borrowed from each other simultaneously and neither has repaid: Department A owes Department B, and Department B owes Department A. Neither balance reaches zero on its own, even though both departments are inactive and their funds are effectively trapped. A special auditor must come in periodically, examine the whole system, detect this circular dependency, and write off both debts together. That special auditor is CPython's garbage collector.

The garbage collector's only job is to handle reference cycles. A reference cycle exists when a set of objects form a chain of references that loops back on itself, with no references from outside the cycle keeping any of them alive. The simplest cycle is two objects that reference each other: a parent object holding a reference to a child, and the child holding a reference back to the parent. Each has a reference count of at least one (from the other), so neither will ever be freed by reference counting alone, even after all external references are removed. The garbage collector finds these orphaned cycles and frees them.

The garbage collector is not constantly running. It runs periodically, triggered by the number of new object allocations since the last run. You can inspect and control it using the `gc` module: `gc.collect()` triggers a manual collection, `gc.get_count()` shows the current allocation counters, and `gc.disable()` turns it off entirely (which is safe if you know your program does not create reference cycles). Most Python programs never need to interact with the `gc` module directly — the default settings handle the common cases automatically.

---

## How It Actually Works

CPython's garbage collector is a generational collector. It divides objects into three generations, numbered 0, 1, and 2. Newly created objects start in generation 0. If an object survives a collection of generation 0 (meaning it still has references at the time the collector runs), it is promoted to generation 1. If it survives a collection of generation 1, it moves to generation 2. Generation 0 is collected most frequently; generation 2 is collected rarely. The reasoning is the generational hypothesis: most objects die young. If something has survived multiple collections, it is likely to be a long-lived object (a module, a cached value, a global), and scanning it repeatedly wastes time.

The collection algorithm is mark-and-sweep, but implemented without a separate mark phase. Instead, CPython uses a technique based on reference count deltas. Every object tracked by the GC is on a doubly-linked list (maintained by the GC, separate from `pymalloc`'s internal lists). When a collection begins, the GC traverses all objects in the target generation and, for each object, subtracts the internal reference counts — the references from other objects in the same generation. After this pass, any object whose effective count is zero (meaning all its references come from other objects in the generation, not from outside) is unreachable from the outside world and is part of a cycle.

Not all Python objects are tracked by the GC. CPython only tracks container objects — objects that can hold references to other objects, like lists, dicts, sets, and user-defined instances. Simple objects like integers, strings, and floats are not tracked, because they cannot form cycles on their own. This is an important optimization: the GC only pays the overhead for objects that could participate in a cycle.

When CPython finds a set of objects forming a cycle, it checks whether any of them have a `__del__` method. Objects with `__del__` inside a cycle are problematic: CPython cannot know in what order to call the destructors, because the objects are mutually dependent. In Python 3.4 and earlier, such objects were placed on `gc.garbage` (a list of uncollectable objects) and never freed. In Python 3.4+, PEP 442 changed this: CPython calls `__del__` in an arbitrary but safe order, then frees the objects. `gc.garbage` still exists but is only populated in cases where CPython cannot safely handle finalization.

---

## How It Connects

The garbage collector exists because reference counting cannot handle cycles. To understand why cycles are a problem for reference counting and why the count never reaches zero in a cycle, you need to understand how reference counting works — what increments the count, what decrements it, and what the count represents.
[[reference-counting|Reference Counting]]

The garbage collector only tracks container objects — objects allocated through CPython's GC-aware allocation path. The layered memory allocator is what actually manages the raw memory for these objects. When the GC decides to free a cycle, it works with the same allocator structures that reference counting uses.
[[python-memory-model|Python's Memory Model]]

---

## Common Misconceptions

Misconception 1: "Python's garbage collector is what frees objects when they go out of scope."
Reality: Objects are freed by reference counting the moment their reference count hits zero. The garbage collector only runs periodically and only handles reference cycles. If you assign `x = None` and `x` was the last reference to a large list, that list is freed immediately by reference counting — no GC involved. The GC is a backup mechanism, not the primary one.

Misconception 2: "Calling `gc.collect()` will free all the memory my program is using."
Reality: `gc.collect()` only frees objects in reference cycles. Objects that are still reachable — referenced by any live variable, module global, or container — are not freed regardless of how many times you call `gc.collect()`. And even freed objects do not necessarily return memory to the OS; they return to `pymalloc`'s pool system. `gc.collect()` is useful for freeing cyclic garbage, but it is not a general-purpose memory reclamation tool.

---

## Why It Matters in Practice

Reference cycles are more common than developers expect. The most frequent sources are: objects with `__del__` methods that hold a reference back to their owner, closures that capture a variable from an enclosing scope that also holds the closure, parent-child relationships where the child stores a `parent` attribute, and exception tracebacks, which keep references to every local variable in every frame in the call stack. Any of these patterns can keep a large object graph alive well past when you expected it to be freed.

Disabling the garbage collector (`gc.disable()`) is sometimes done in performance-critical code that creates and discards many objects rapidly, because the GC's periodic scan has a cost proportional to the number of tracked objects. If you are certain your code does not create reference cycles, disabling the GC can reduce latency spikes from collection pauses. The `gc` module's `freeze()` function (Python 3.7+) is a related tool: it moves all currently tracked objects into a permanent "frozen" generation that is never collected, which makes subsequent GC runs faster because they scan fewer objects.

---

## Interview Angle

Common question forms:
- "Does Python have a garbage collector? How does it relate to reference counting?"
- "What is a reference cycle? Can you give an example?"
- "Can Python programs have memory leaks?"

Answer frame: Establish that reference counting is the primary mechanism and handles most cases immediately. Explain that reference cycles defeat reference counting — give a two-object mutual-reference example. Describe the GC as a periodic, generational collector that finds these cycles using a reference count delta approach. Confirm that Python programs can have memory leaks: objects in cycles with `__del__`, or long-lived containers accumulating entries that are never removed.

---

## Related Notes

- [[reference-counting|Reference Counting]]
- [[python-memory-model|Python's Memory Model]]
