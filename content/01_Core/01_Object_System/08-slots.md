---
title: 08 - __slots__
description: __slots__ replaces the per-instance __dict__ with a fixed set of C-level member descriptors, reducing per-instance memory usage and slightly speeding up attribute access — the tradeoff is loss of dynamic attribute assignment and some flexibility.
tags: [slots, memory-optimization, __dict__, descriptors, cpython, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# __slots__

> __slots__ replaces the per-instance __dict__ with a fixed set of C-level member descriptors, reducing per-instance memory usage and slightly speeding up attribute access — the tradeoff is loss of dynamic attribute assignment and some flexibility.

---

## Quick Reference

**Core idea:**
- Defining `__slots__ = ('x', 'y')` in a class body prevents creation of `__dict__` per instance — attributes are stored as fixed-offset C struct fields instead
- Without `__slots__`: each instance has a `__dict__` (typically 200+ bytes overhead) for storing instance attributes
- With `__slots__`: no `__dict__`, each slot is a C-level `member_descriptor` in the class — roughly 50–100 bytes overhead per class (not per instance)
- The memory saving is per instance — for a class with millions of instances, `__slots__` can save hundreds of MB
- Access to slot attributes is slightly faster than dict lookup — the C descriptor does a direct struct field offset read

**Tricky points:**
- `__slots__` on a class does **not** prevent subclasses from having `__dict__` — unless every class in the MRO defines `__slots__`
- If `__dict__` is not in `__slots__`, you cannot add attributes not listed in `__slots__`: `obj.new_attr = 1` raises `AttributeError`
- Adding `'__dict__'` to `__slots__` explicitly re-enables the instance dict — usually defeating the purpose
- `__weakref__` must be included in `__slots__` if you want instances to be weakly referenceable — it is normally provided by `__dict__`-having classes automatically
- `__slots__` interacts with multiple inheritance: all classes in the MRO should define `__slots__` for maximum memory savings; mixing `__slots__` and `__dict__`-having classes causes `__dict__` to appear

---

## What It Is

Think of the difference between a general-purpose warehouse (instance `__dict__`) and a factory assembly line with fixed workstations (`__slots__`). A warehouse can store anything anywhere — flexible, but the shelving system, tracking inventory, and managing space takes overhead regardless of how many items are stored. A factory assembly line has fixed workstations: station 1 is always for fastening, station 2 is always for painting. There is no inventory management overhead — every station is at a known, fixed position. The tradeoff: you cannot add a new station without redesigning the line.

Every standard Python instance carries a `__dict__` — a Python dictionary that stores its attribute names and values. The `dict` itself has significant overhead: on a 64-bit CPython, a freshly created empty dict takes ~200 bytes. For a simple `Point` class with just `x` and `y`, the instance dict uses 200+ bytes to store two attributes that could fit in 16 bytes. Multiply by a million point instances in a computational geometry application, and the overhead is 200 MB just for the empty dicts.

`__slots__` replaces this with per-class member descriptors. Each slot name corresponds to a fixed memory offset in the instance's C struct. Reading `point.x` reads a pointer at a known offset; writing `point.x = 5` writes a pointer at a known offset — no dict lookup, no hash computation, no memory allocation for the dict itself. The savings are significant for classes with many instances and a fixed set of attributes.

---

## How It Actually Works

When `__slots__` is defined in a class body, `type.__new__` does not create an instance `__dict__` slot in the type's layout. Instead, for each name in `__slots__`, it creates a `member_descriptor` — a C-level descriptor stored as a class attribute. The `member_descriptor.__get__` and `member_descriptor.__set__` read and write to a fixed byte offset within the instance struct.

The memory layout of a `__slots__` instance is: `PyObject` header (16 bytes: refcount + type pointer) + one pointer per slot (8 bytes each on 64-bit). For `class Point(__slots__=('x','y'))`, each instance is 32 bytes: 16 bytes header + 8 bytes for x slot + 8 bytes for y slot. Compared to a non-slotted instance with `__dict__`: 16 bytes header + 8 bytes for the `__dict__` pointer + 200+ bytes for the dict = 224+ bytes.

Inheritance with `__slots__` requires care. If `Parent` defines `__slots__ = ('a',)` and `Child(Parent)` also defines `__slots__ = ('b',)`, `Child` instances have slots for `a` and `b` but no `__dict__`. If `Child` does not define `__slots__`, `Child` will have `__dict__` (from the default behavior) even though `Parent` tried to avoid it — `Parent`'s optimization is lost for `Child` instances.

`sys.getsizeof(instance)` reports the instance's own memory in bytes. Comparing `sys.getsizeof(SlottedPoint(1,2))` versus `sys.getsizeof(RegularPoint(1,2))` (without `__slots__`) directly shows the difference.

---

## How It Connects

`__slots__` creates member descriptors — C-level data descriptors that implement `__get__`, `__set__`, and `__delete__` for each slot. The descriptor protocol is what makes slot access work transparently: `obj.x` follows the same attribute lookup path, finds the member descriptor in the class, and calls its `__get__` to read the slot value.
[[descriptors|Descriptors]]

`__slots__` is most relevant in the context of the object header and Python's memory model. Without `__slots__`, the `__dict__` pointer in the instance struct adds indirection and allocates a separate dict. With `__slots__`, the data is inline in the struct, reducing both memory and indirection.
[[object-header|Python Object Header]]

---

## Common Misconceptions

Misconception 1: "Using `__slots__` on a base class means all subclasses benefit from reduced memory usage."
Reality: Subclasses must also define `__slots__` to avoid getting a `__dict__`. If `Parent` has `__slots__` but `Child(Parent)` does not, `Child` instances will have both the parent's slots and a `__dict__`. The `__dict__` is inherited via default class behavior unless explicitly suppressed with `__slots__ = ()` (an empty tuple) in the subclass.

Misconception 2: "`__slots__` is always the right optimization for memory."
Reality: `__slots__` saves memory only for classes with many instances where the attribute set is fixed. It complicates pickling (requires `__getstate__`/`__setstate__`), breaks some dynamic attribute patterns, requires explicit `__weakref__` for weak references, and prevents the common "store arbitrary metadata on an instance" pattern. Profile memory usage first; `__slots__` is an optimization for specific high-instance-count scenarios.

---

## Why It Matters in Practice

`__slots__` is standard practice in data-heavy scientific computing and high-frequency game objects. A particle simulator with 10 million `Particle` instances each with `x`, `y`, `z`, `vx`, `vy`, `vz` attributes: with `__slots__`, each instance uses ~64 bytes (header + 6 slot pointers); without `__slots__`, each uses ~240+ bytes (header + dict pointer + dict). Total: 640 MB vs. 2.4 GB for the same data. `__slots__` is the difference between fitting in RAM and not.

For Python data classes (`@dataclass`), there is a `slots=True` parameter (Python 3.10+) that automatically generates `__slots__` from the field declarations. `@dataclass(slots=True)` gives memory savings with the clean `@dataclass` syntax and without manually listing slot names.

---

## Interview Angle

Common question forms:
- "What is `__slots__` and why would you use it?"
- "How does `__slots__` reduce memory usage?"

Answer frame: `__slots__` prevents CPython from creating a `__dict__` per instance. Instead, each attribute listed in `__slots__` gets a C-level member descriptor at a fixed struct offset. Memory saving: a regular instance needs 200+ bytes for its `__dict__`; a slotted instance needs only 8 bytes per slot. Use case: classes with many instances (thousands to millions) and a fixed attribute set. Tradeoff: no dynamic attribute assignment, must include `__weakref__` explicitly, complicates inheritance. Every subclass must also define `__slots__` to maintain the optimization.

---

## Related Notes

- [[descriptors|Descriptors]]
- [[object-header|Python Object Header]]
- [[python-memory-model|Python's Memory Model]]
- [[dunder-methods|Dunder Methods]]
