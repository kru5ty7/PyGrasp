---
title: 16 - id() and Memory Addresses
description: In CPython, id(obj) returns the memory address of the object — the integer value of the PyObject* pointer — making it a reliable proxy for object identity and the basis of the is operator's implementation.
tags: [id, memory-address, identity, is-operator, cpython, pyobject, layer-0, core]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# id() and Memory Addresses

> In CPython, id(obj) returns the memory address of the object — the integer value of the PyObject* pointer — making it a reliable proxy for object identity and the basis of the is operator's implementation.

---

## Quick Reference

**Core idea:**
- `id(obj)` returns an integer guaranteed to be **unique and constant** for the object's lifetime — in CPython, this is the memory address of the `PyObject` struct
- `a is b` is equivalent to `id(a) == id(b)` — both check whether `a` and `b` point to the same object in memory
- Two objects with `id(a) == id(b)` at **different times** may be different objects — if `a` is deleted and `b` is created at the same address, their ids will match even though they are different objects
- In CPython specifically: `id(42)` is the address of the cached integer object 42; this address is constant for the lifetime of the interpreter
- `id()` is the low-level mechanism behind `dict` key lookup for objects that do not define `__hash__` — the default `__hash__` returns `id(self) // 16`

**Tricky points:**
- `id()` returning the memory address is a **CPython implementation detail** — other Python implementations (PyPy, Jython) return arbitrary unique integers, not memory addresses
- A **dead object's address can be reused**: `id(SomeClass()) == id(SomeClass())` may be `True` — both temporary objects are created and destroyed at the same address
- `ctypes.cast(id(obj), ctypes.py_object).value` dereferences the pointer and returns the object — this is how you can observe CPython internals, though it is highly unsafe
- `id()` on a small integer like `id(0)` returns the same value always (the cached integer's address is fixed); `id(10000)` in a fresh context returns a different value each run
- The `is` operator is a single pointer comparison in C — O(1) and extremely fast, regardless of the objects' types or sizes

---

## What It Is

Think of every Python object as a building in a city. Every building has a street address — a unique number that identifies exactly which building it is and where it sits on the street map. `id()` is the city's address lookup: it gives you the street number for any building. Two names that refer to the same building (two variables that reference the same object) will return the same street number. Two buildings that look identical but are at different locations (two equal but distinct objects) have different street numbers. The `is` operator compares street numbers: it asks "are these two names pointing to the same building?" not "do these two buildings look the same?"

In CPython's implementation, every Python object exists somewhere in the process's virtual memory space. The `PyObject *` pointer that CPython uses to refer to an object is a memory address — a 64-bit integer on a 64-bit system identifying the byte offset within the process's address space where the object's C struct begins. `id(obj)` in CPython simply returns this pointer cast to a Python integer: `(Py_uintptr_t)op` in C.

This address-as-identity model makes `id()` both very fast (a single pointer read) and semantically meaningful: since two distinct objects cannot occupy the same memory address simultaneously, equal `id()` values guarantee the same object. The Python language specification only guarantees uniqueness and constancy during the object's lifetime; CPython's use of memory addresses happens to satisfy this guarantee as a natural consequence of how memory allocation works.

---

## How It Actually Works

In CPython's `Objects/object.c`, the `id()` built-in is implemented as:

```c
static PyObject *
builtin_id(PyObject *self, PyObject *v)
{
    return PyLong_FromVoidPtr(v);
}
```

`PyLong_FromVoidPtr(v)` converts the pointer `v` (a `void *`, which is `PyObject *` implicitly converted) to a Python integer. On a 64-bit system this returns a large integer like `140234567890` — the hexadecimal representation of that address is what you see when you print `hex(id(obj))`.

The `is` operator in bytecode is the `IS_OP` instruction (or `COMPARE_OP` with `is` in older versions). The C implementation compares `PyObject *` pointers directly: `left == right`. This single pointer comparison is why `is` is always O(1) regardless of object size or complexity — it does not look at the object's contents at all.

The "dead object id reuse" trap: `id([1,2,3]) == id([1,2,3])`. This is True in CPython because the first list is created (gets some address), `id()` is called and returns that address, the list has no more references and is immediately freed, and then the second list is allocated at the same address (pymalloc reuses the freed memory). The returned ids are equal but refer to two different (now-defunct) objects. This only happens for temporary objects with no other references.

---

## How It Connects

The id of an object is the numeric value of the `PyObject *` pointer, which points to the object's header struct in memory. The object header is where the reference count and type pointer live. Understanding the header is understanding what exactly the memory address returned by `id()` points to.
[[object-header|Python Object Header]]

Interning makes `id()` particularly meaningful: `id(42) == id(42)` is always True in CPython because there is only one integer object for 42 (the cached instance). For non-interned values, equal objects can have different ids.
[[interning|Object Interning]]

---

## Common Misconceptions

Misconception 1: "If `id(a) == id(b)`, then `a` and `b` are the same variable."
Reality: `id(a) == id(b)` means `a` and `b` reference the same object — the same position in memory. There can be many variable names, list elements, dict values, and other references that all point to the same object and thus return the same id. Variable names are just labels; `id()` identifies the object, not the name.

Misconception 2: "You can safely use `id()` to compare objects across time."
Reality: An object's `id` is only meaningful while the object is alive. After an object is deleted, its memory can be reused for a new object at the same address. Storing `id(obj)` in a variable and later checking another object's id against it is unreliable — the original object may be gone and the id reused. If you need to compare objects across time, keep a reference to the original object (which prevents it from being freed) and use `is` directly.

---

## Why It Matters in Practice

`id()` is used by `copy.deepcopy()` as the key in its memo dict: `memo[id(original)] = copy`. This prevents infinite recursion when copying cyclic object graphs — if the same object is encountered again during traversal, its id is already in the memo dict and the previously created copy is returned instead of recursing again. This is a direct, practical use of `id()` as an object identity key.

The default `__hash__` implementation returns `id(self) // 16` (the right-shift discards alignment bits that are always zero on most allocators, giving better hash distribution). This means every Python object is hashable by default (and therefore usable as a dict key or set element), with identity-based hash semantics. Overriding `__eq__` without overriding `__hash__` sets `__hash__` to `None`, making the class unhashable — Python enforces the invariant that equal objects must have equal hashes.

---

## Interview Angle

Common question forms:
- "What does `id()` return in Python?"
- "What is the difference between `==` and `is`?"
- "When can two different objects have the same id?"

Answer frame: In CPython, `id(obj)` returns the memory address of the object — the `PyObject *` pointer as an integer. `is` compares these addresses (single pointer equality check, O(1)). Equal id means same object; `==` tests value equality via `__eq__`. Two different objects can have the same id sequentially: when the first is freed and the second is allocated at the same address. Never compare ids across time; use `is` for live object identity checks.

---

## Related Notes

- [[object-header|Python Object Header]]
- [[interning|Object Interning]]
- [[reference-counting|Reference Counting]]
- [[everything-is-an-object|Everything is an Object]]
