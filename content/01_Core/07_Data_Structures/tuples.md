---
title: 02 - Tuples
description: "Tuples are immutable, fixed-size C arrays of PyObject pointers with no over-allocation  -  lighter than lists, cacheable by CPython, and the right choice whenever a sequence should not change."
tags: [tuples, immutable, fixed-size, tuple-cache, unpacking, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Tuples

> A tuple is Python's promise that a sequence will not change  -  and CPython takes that promise seriously enough to cache small ones and allocate them without the overhead lists carry.

---

## Quick Reference

**Core idea:**
- `PyTupleObject` stores a fixed-length C array of `PyObject *` with no `allocated` field  -  length IS capacity
- CPython caches the empty tuple: `() is ()` evaluates to `True`  -  there is only ever one empty tuple object
- CPython maintains a free-list of up to 20 single-element tuples per size (up to size 20) across the interpreter
- Tuple iteration has no bounds check on each step (length is fixed), making it marginally faster than list iteration
- `sys.getsizeof(())` is 40 bytes; each element adds 8 bytes (pointer)  -  no slack allocation

**Tricky points:**
- A "mutable tuple" is not a contradiction  -  `t = ([1,2], 3)` is valid; the tuple is immutable, the list inside is not
- `(x,)` is a one-element tuple; `(x)` is just `x` in parentheses  -  the comma is what makes the tuple
- Tuple packing/unpacking is syntax-level, not a method call  -  it happens in the compiler's bytecode
- `t._asdict()` does not exist on plain tuples  -  only on `namedtuple` instances
- Comparing tuples uses lexicographic element-by-element comparison, same as lists

---

## What It Is

Imagine sealing a row of items inside a strip of clear acrylic resin. Once cured, you can see and access every item by position, but nothing can be inserted, removed, or replaced. The items themselves may be changeable objects  -  if one of them is a jar, the jar's contents can change  -  but you cannot swap out the jar for a different jar, and you cannot add another jar to the strip.

That sealed-strip model is exactly how tuples behave. A tuple is an ordered, indexed collection of references, and those references are frozen at construction time. Because CPython knows the tuple will never need to grow or shrink, it allocates precisely the memory required  -  no over-allocation, no `allocated` field separate from length. This makes tuples cheaper to create and cheaper to store than lists of the same logical size.

Tuples serve as Python's structural record type. A function returning multiple values (`return x, y`) is really returning a tuple. Argument packing with `*args` produces a tuple. Dictionary iteration over `.items()` yields two-element tuples. The language leans on tuples wherever a fixed-shape, positionally-indexed group of values is needed  -  and the reason is not just convention but the performance and semantic guarantees that immutability provides.

---

## How It Actually Works

In CPython's `tupleobject.c`, the struct is:

```c
typedef struct {
    PyObject_VAR_HEAD
    PyObject *ob_item[1];  /* flexible array member */
} PyTupleObject;
```

Unlike `PyListObject`, there is no separate `allocated` field. `ob_size` (the length) doubles as the capacity because it can never change. When you write `t = (1, 2, 3)`, the compiler emits a `BUILD_TUPLE` or `LOAD_CONST` bytecode instruction, and CPython allocates a single contiguous block: the struct header plus exactly `n * sizeof(PyObject *)` bytes. No further allocation ever touches this object for the purpose of resizing.

CPython maintains a per-size free-list for small tuples. When a tuple of size k is garbage-collected, rather than returning its memory to the allocator, CPython stores it in `free_list[k]` (up to 20 items per size, for sizes 1 - 20). The next time a tuple of that exact size is constructed, the cached struct is reused, avoiding both `malloc` and `free`. The empty tuple occupies a special singleton slot: `_Py_EMPTY_TUPLE` is set once at interpreter startup, and `()` always returns that exact object. This is why `() is ()` is always `True`  -  you are getting a cached singleton, not a new allocation. For single-item tuples, a similar (though implementation-version-dependent) caching mechanism exists in some CPython builds.

---

## How It Connects

Tuples being hashable (when all their elements are hashable) is what allows them to serve as dictionary keys and set members. The hash of a tuple is derived from the hashes of its elements using a mixing formula  -  the tuple's immutability guarantees the hash will never change after construction.

[[dicts|Dictionaries]]

Named tuples extend the plain tuple by adding name-based field access via descriptors, while preserving the same memory layout and full tuple compatibility.

[[namedtuples|Named Tuples]]

Because tuples and lists share the same underlying C array model for element storage, their iteration and indexing behavior is nearly identical. The difference in allocation strategy is what makes tuples the right choice for fixed-shape data.

[[lists|Lists]]

---

## Common Misconceptions

Misconception 1: "Tuples are immutable, so you can't store mutable objects in them."
Reality: Tuple immutability means the references stored in the tuple cannot be replaced. The objects those references point to can be freely mutated  -  `t = ([],); t[0].append(1)` works fine.

Misconception 2: "Tuples are just 'read-only lists'  -  use whichever feels right."
Reality: The distinction is semantic, not just performance. A list signals a homogeneous sequence of variable length. A tuple signals a fixed-shape record where position has meaning. Using a tuple for `(latitude, longitude)` communicates intent; using a list says the collection might grow.

Misconception 3: "`(x)` creates a single-element tuple."
Reality: `(x)` is just `x` wrapped in parentheses for grouping. The trailing comma is what creates a tuple: `(x,)` or simply `x,`.

---

## Why It Matters in Practice

Functions that return multiple values rely on tuple packing and unpacking implicitly. When a function returns `return x, y`, Python constructs a tuple; when the caller writes `a, b = func()`, Python unpacks it. Knowing this makes `*rest` unpacking, `_` throwaway variables, and nested unpacking patterns legible rather than magical.

Memory footprint matters in batch operations. Storing a million two-element records as tuples rather than lists saves the per-list overhead (the `PyListObject` header with its `allocated` field, plus the over-allocated pointer slots). For numerical data at scale, this is usually superseded by NumPy arrays, but for general Python objects, the tuple is the tightest fixed-shape container available without resorting to `__slots__`.

---

## Interview Angle

Common question forms:
- "What is the difference between a list and a tuple in Python?"
- "Why are tuples faster than lists?"
- "Can you use a tuple as a dictionary key? Can you use a list?"

Answer frame:
A strong answer goes beyond "tuples are immutable" to explain that `PyTupleObject` has no `allocated` field, no over-allocation, a free-list cache for small sizes, and a singleton empty tuple. Tuples are hashable (when elements are) because immutability guarantees hash stability. Lists cannot be hashed because their contents can change after construction, making any previously-computed hash stale.

---

## Related Notes

- [[lists|Lists]]
- [[namedtuples|Named Tuples]]
- [[dicts|Dictionaries]]
- [[mutability|Mutability]]
- [[python-memory-model|Python Memory Model]]
