---
title: Python Object Header
description: Every Python object in CPython begins with a fixed C struct header containing a reference count and a type pointer — this two-field header is the structural foundation of Python's entire object model and enables the reference counting GC and dynamic dispatch.
tags: [object-header, pyobject, refcount, type-pointer, cpython, memory, layer-0, core]
status: draft
difficulty: intermediate
layer: 0
domain: core
created: 2026-05-17
---

# Python Object Header

> Every Python object in CPython begins with a fixed C struct header containing a reference count and a type pointer — this two-field header is the structural foundation of Python's entire object model and enables the reference counting GC and dynamic dispatch.

---

## Quick Reference

**Core idea:**
- Every Python object is a C struct in memory whose first fields are `ob_refcnt` (reference count) and `ob_type` (pointer to the type object)
- This is defined in `Include/object.h` as `PyObject { Py_ssize_t ob_refcnt; PyTypeObject *ob_type; }`
- Variable-size objects (lists, strings) extend with `PyVarObject { PyObject ob_base; Py_ssize_t ob_size; }` — `ob_size` holds the count of elements
- `ob_type` is a pointer to the object's `PyTypeObject`, which contains all the methods, slots, and behavior of that type
- All CPython C API functions accept `PyObject *` — a pointer to this header — enabling generic handling of any Python object regardless of its actual type

**Tricky points:**
- `ob_refcnt` starts at 1 when an object is created; when it reaches 0, the object is immediately deallocated (no GC pause)
- The `ob_type` pointer enables **dynamic dispatch** — when you call `len(x)`, CPython follows `ob_type` to find the `sq_length` slot, then calls the C function pointed to by that slot
- `sys.getsizeof(obj)` returns the size of the object in bytes including the header, but **not** the sizes of objects referenced by it
- CPython 3.12+ introduced a more compact header format as part of the "compact objects" optimization — `ob_refcnt` and `ob_type` are packed differently on 64-bit systems
- The header is always present regardless of the Python-level type — `int`, `str`, `list`, `function`, `module` all start with these same C fields

---

## What It Is

Think of every Python object as a standardized shipping container. Every container in the world, regardless of what is inside it, has the same corner fittings and the same attachment points — this is what lets cranes and trucks handle any container without needing to know its contents. The contents of one container are electronics; another holds grain; another is refrigerated food. But every handler in the logistics chain grabs the same corners, reads the same label format, and moves the container the same way. Python's object header is those corner fittings. Every Python object — an integer, a list, a function, a class instance — starts with the same two fields, regardless of what follows. This is what allows CPython's C code to handle any Python object through a single generic interface.

The `PyObject` struct in CPython's C source is the universal base of everything. A Python integer is a C struct that starts with `PyObject` and then has an extra field for the integer value. A Python list is a C struct that starts with `PyObject` and then has a pointer to a C array of `PyObject *` pointers. A Python function has its `PyObject` header followed by fields for the bytecode object, the globals dict, and the default arguments. The `PyObject` header is what they all share — the reference count and the type pointer.

The type pointer (`ob_type`) is the object's link to its class. Every `PyTypeObject` is itself a Python object (with its own header) and contains a table of C function pointers — the "slots" — that implement the object's behavior: how to call it, how to compare it, how to iterate it, how to get its length, how to get and set its attributes. When Python evaluates `x + y`, it follows `x`'s `ob_type` to find the `nb_add` slot and calls the C function it points to. This is the mechanism behind operator overloading, and it is all mediated through the `ob_type` pointer in the header.

---

## How It Actually Works

In CPython's `Include/object.h`, the definition is:

```c
typedef struct _object {
    Py_ssize_t ob_refcnt;
    PyTypeObject *ob_type;
} PyObject;
```

Every Python object in memory is a pointer to a struct whose first two fields are these. When CPython receives a `PyObject *`, it can read the reference count and type without knowing what kind of object it is. The C API function `Py_TYPE(op)` extracts `ob_type`; `Py_REFCNT(op)` extracts `ob_refcnt`. Both are macros that just read the corresponding field — they work on any `PyObject *`.

Variable-size objects like lists and strings extend this with `PyVarObject`:

```c
typedef struct {
    PyObject ob_base;
    Py_ssize_t ob_size;
} PyVarObject;
```

`ob_size` for a list is the number of elements currently in the list. For a bytes object, it is the number of bytes. The C macro `Py_SIZE(op)` reads this field. This is why `len(my_list)` is O(1) in CPython — it reads `ob_size` from the header rather than counting elements.

Memory layout for a Python integer (`PyLongObject` in CPython 3.12+) is: the `PyObject` header (refcount + type pointer), followed by a compact representation of the integer value. For small integers (those in the small integer cache), the same `PyLongObject` struct is reused — the `ob_refcnt` of a cached integer is very high because every reference to `42` in Python code points to the same C struct in memory.

---

## How It Connects

The reference count field in the object header is the mechanism of CPython's reference-counting garbage collector. When `ob_refcnt` drops to zero, `_Py_Dealloc()` is called to free the memory. Understanding the header is understanding why reference counting is automatic and why `del x` decrements a counter rather than freeing memory directly.
[[reference-counting|Reference Counting]]

The `ob_type` pointer connects every object to its type. The type object is itself a Python object with a richer header — it is the `PyTypeObject` struct. Understanding the Python data model and how `type(x)` works at the C level is understanding the `ob_type` pointer in every object's header.
[[everything-is-an-object|Everything is an Object]]

The `ob_size` field in variable-size objects is the basis for `id()` returning the memory address and for `sys.getsizeof()` returning the object's size. The `id()` function in CPython simply returns the memory address — the value of the `PyObject *` pointer itself.
[[id-and-memory-address|id() and Memory Addresses]]

---

## Common Misconceptions

Misconception 1: "Python objects are expensive because they have a lot of overhead."
Reality: The `PyObject` header is 16 bytes on a 64-bit system (8 bytes for `ob_refcnt` as a `Py_ssize_t`, 8 bytes for `ob_type` as a pointer). For a Python integer, the total object size is around 28 bytes. By comparison, a C `int` is 4 bytes. This is a real overhead, but it buys the entire Python dynamic type system — runtime type checking, operator overloading, garbage collection, and introspection. The overhead is the cost of generality, not waste.

Misconception 2: "The `ob_type` pointer changes when you assign a new value to a variable."
Reality: Assigning `x = 42` after `x = "hello"` does not change the `ob_type` of any existing object. It changes which object the name `x` refers to. The string object `"hello"` still exists in memory with its type pointer pointing to `str`; the integer `42` is a different object with its type pointer pointing to `int`. Variable assignment changes the name binding in a namespace dict, not the type of an object.

---

## Why It Matters in Practice

The object header explains why Python's memory usage is higher than C for equivalent data. A list of one million Python integers uses not just the list's own memory but one `PyObject` per integer (around 28 bytes each) — totaling roughly 28 MB for a million integers, versus 4 MB for a C array of `int`. Using NumPy arrays instead stores data as raw C numeric types without per-element Python object overhead — this is the core reason NumPy is both faster and more memory-efficient for numeric data.

Understanding `__slots__` becomes clearer with knowledge of the object header. A regular Python instance object has a `__dict__` — a Python dict stored as part of the object, adding roughly 200+ bytes of overhead per instance. `__slots__` replaces this dict with fixed-offset C fields in the struct, storing attribute values directly after the header. This significantly reduces per-instance memory for classes with many instances.

---

## Interview Angle

Common question forms:
- "What is PyObject and why does it matter?"
- "How does CPython know the type of every object?"
- "Why is `len()` O(1) for lists in Python?"

Answer frame: Every CPython object starts with a `PyObject` header: `ob_refcnt` (reference count for GC) and `ob_type` (pointer to the type object). This universal header lets CPython's C code handle any Python object through a `PyObject *` pointer. `ob_type` enables dynamic dispatch — method and operator lookup follows the type pointer to find the right C function. Variable-size objects add `ob_size`, making `len()` O(1). Object size overhead: ~28 bytes per integer, explaining why NumPy arrays are more memory-efficient.

---

## Related Notes

- [[everything-is-an-object|Everything is an Object]]
- [[reference-counting|Reference Counting]]
- [[id-and-memory-address|id() and Memory Addresses]]
- [[python-memory-model|Python's Memory Model]]
