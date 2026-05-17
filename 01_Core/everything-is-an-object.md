---
title: Everything is an Object
description: In Python, every value — integers, strings, functions, classes, even None — is an object in memory with a type, an identity, and a reference count. This is not a metaphor; it is a structural fact about how CPython allocates and tracks every value your program touches.
tags: [objects, CPython, memory, PyObject, type-system, core]
status: draft
difficulty: intermediate
layer: 0
domain: core
created: 2026-05-17
---

# Everything is an Object

> In Python, every value — integers, strings, functions, classes, even None — is an object in memory with a type, an identity, and a reference count. This is not a metaphor; it is a structural fact about how CPython allocates and tracks every value your program touches.

---

## Quick Reference

**Core idea:**
- Every Python value is a C struct starting with `PyObject`: `ob_refcnt` (reference count) + `ob_type` (pointer to its type)
- `ob_type` points to a **slot table** of C function pointers — `nb_add`, `tp_call`, `tp_getattro`, `tp_hash`, etc.
- Variables are **names that point to objects** — not boxes that contain values
- Functions, classes, types, modules, `None` — all objects; `type(int)` → `<class 'type'>`
- Small integers **-5 to 256** are pre-allocated singletons at CPython startup

**Tricky points:**
- `x = 1; y = 1` → `x is y` is `True` (cached singleton); `x = 1000; y = 1000` → `x is y` may be `False` (two separate allocations)
- `x + y` doesn't "add" — CPython looks up `nb_add` on `x`'s type and calls whatever C function is registered there
- A Python list of 1M integers = **1M heap-allocated PyObject structs**; NumPy array of 1M integers = **one C array allocation**
- Every Python operation pays the `PyObject` overhead — type lookup + reference count update — this is the baseline cost of Python's dynamic dispatch

---

## What It Is

Consider a museum where every item on display — paintings, sculptures, furniture, even the labels on the wall — is catalogued the same way. Every single item has a unique ID number, a record of what category it belongs to, and a count of how many times it has been referenced in the catalogue. The museum does not treat a painting differently from a label at the cataloguing level; both have the same basic record structure. Python's runtime is that museum. Every value, regardless of how simple or complex it is, gets the same basic treatment: an identity, a type, and a reference count.

When you write `x = 42` in Python, the number `42` is not stored as a raw 4-byte integer in memory the way it would be in C. Instead, CPython creates (or reuses) a Python integer object — a C struct in memory that contains the value `42`, plus a type pointer (pointing to the `int` type), plus a reference count. The variable `x` does not hold `42`. It holds a reference — a pointer — to that object in memory. This distinction is fundamental. In Python, variables are labels that point to objects. The object exists independently of the label.

This principle extends without exception. A function defined with `def` is an object. A class created with `class` is an object. A module you import is an object. The type `int` itself is an object — an instance of the type `type`. Even `None` is an object — a singleton of type `NoneType`. This uniformity is not just philosophical consistency; it is what makes Python's introspection capabilities, decorators, first-class functions, and dynamic typing all work the way they do.

---

## How It Actually Works

At the C level, every Python object begins with the same header: a reference count (`ob_refcnt`) and a pointer to its type object (`ob_type`). This header is defined in `Include/object.h` as `PyObject`. Every Python object in CPython is represented as a C struct whose first fields are this `PyObject` header. An integer object is a `PyLongObject` struct that starts with `PyObject`. A list object is a `PyListObject` struct that starts with `PyObject`. The evaluator can treat any Python value as a `PyObject *` pointer — it reads the type pointer to find out what kind of object it has, then dispatches to the appropriate C functions for that type.

The type pointer (`ob_type`) points to a type object, which is itself a `PyObject` containing a table of function pointers called the "type methods" or "slots." These slots define how the object behaves: how to add it (`nb_add`), how to get an attribute from it (`tp_getattro`), how to call it (`tp_call`), how to represent it as a string (`tp_repr`), how to compute its hash (`tp_hash`). When Python evaluates `x + y`, CPython does not have a hard-coded addition routine for every type. It looks at the type of `x`, finds the `nb_add` slot, and calls whatever C function is registered there. This dispatch through the type's slot table is how Python achieves runtime polymorphism — and why every operation on Python values carries some overhead compared to statically typed languages.

The reference count in `ob_refcnt` is incremented every time a new reference to the object is created — when you assign it to a variable, pass it as an argument, store it in a list. It is decremented when a reference goes away — when a variable goes out of scope, when a list element is removed. When the count reaches zero, CPython immediately frees the object's memory. This instant deallocation on zero references is the foundation of Python's memory management, and it is what makes the Global Interpreter Lock necessary.

---

## How It Connects

The reference count inside every `PyObject` is the mechanism CPython uses to manage memory. It is not just a number — it determines when objects are freed. Understanding how reference counting works, what increments and decrements it, and what happens at zero is the next level of detail beneath the "everything is an object" principle.
[[reference-counting|Reference Counting]]

Because every value is a `PyObject *` at the C level, Python needs a safe strategy for deciding how values are stored and whether they can be changed after creation. Mutability — the distinction between objects that can be modified in place and those that cannot — is directly tied to the internal structure of the C structs that represent different object types.
[[mutability|Mutability vs Immutability]]

The Python data model is the formal description of how objects interact with the language. When you use `+`, `len()`, `for`, `with`, or `in`, Python calls specific methods on the objects involved. The data model defines what those methods are and when they are called — and it only makes sense because every value is an object with a defined type.
[[python-data-model|The Python Data Model]]

CPython's memory allocator does not simply call `malloc` for every object. It uses a layered allocator designed specifically for the pattern of many small, short-lived objects that Python programs produce. Understanding Python's memory model requires understanding both the `PyObject` structure and how CPython manages the heap it allocates objects into.
[[python-memory-model|Python's Memory Model]]

---

## Common Misconceptions

Misconception 1: "Python integers are just numbers stored in memory like in C."
Reality: Python integers are `PyLongObject` structs. A simple `x = 1` in Python involves a heap-allocated C struct with a reference count, a type pointer, and the integer value itself. For small integers (-5 to 256), CPython preallocates and caches these objects at startup, so `x = 1` and `y = 1` point to the same cached object. For larger integers, CPython allocates a new struct on every assignment. This is why `x is y` is `True` for `x = 1; y = 1` but may be `False` for `x = 1000; y = 1000` — two separate allocations.

Misconception 2: "Functions are special — they're not really objects like integers are."
Reality: A function defined with `def` is a `PyFunctionObject`, which is a Python object with all the same properties as any other object. You can assign it to a variable, store it in a list, pass it as an argument, add attributes to it, and inspect its `__code__`, `__defaults__`, and `__closure__`. The fact that functions are objects is precisely what makes decorators, closures, partial application, and higher-order functions work in Python. There is no special "function slot" in Python — functions are just another type of object.

---

## Why It Matters in Practice

The fact that everything is an object is the reason Python's introspection capabilities are so powerful. You can inspect any object's type with `type()`, its attributes with `dir()`, its source with `inspect.getsource()`. You can modify a class after it has been defined, swap out methods at runtime, and store metadata on functions as attributes. None of this requires special language support — it all follows from the fact that types, functions, and classes are objects that live in memory and can be manipulated like any other value.

The cost side is just as real. Every Python value carries the overhead of a `PyObject` header. Storing a million integers in a Python list means a million heap-allocated structs, each with a type pointer and reference count, plus a million pointer-sized entries in the list's internal array. A NumPy array of a million integers, by contrast, stores raw 8-byte values in a contiguous C array with a single Python object wrapper around it. The performance difference between "a list of Python integers" and "a NumPy array of integers" is a direct consequence of the fact that everything is an object.

---

## Interview Angle

Common question forms:
- "What does 'everything is an object' mean in Python?"
- "Why is `x = 1` in Python different from `int x = 1` in C?"
- "Why does `x is y` return True for small integers but not for large ones?"

Answer frame: Explain that every Python value is a C struct with a `PyObject` header — reference count and type pointer. Contrast with C where a raw integer is just bytes. Use the small integer cache to explain the `is` behavior — it reveals that the objects are the same allocated struct, not just equal values. Connect to performance: the `PyObject` overhead is why raw Python data structures are slower than NumPy for numeric work.

---

## Related Notes

- [[how-python-runs-code|How Python Runs Your Code]]
- [[reference-counting|Reference Counting]]
- [[mutability|Mutability vs Immutability]]
- [[python-data-model|The Python Data Model]]
- [[python-memory-model|Python's Memory Model]]
