---
title: The Python Data Model
description: "The Python data model is the system of protocols that defines how objects interact with Python's built-in syntax and functions — implement the right methods, and your object works with `+`, `len()`, `for`, `with`, and every other language construct as naturally as a built-in type."
tags: [data-model, dunder, protocols, cpython, slots, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# The Python Data Model

> The Python data model is the system of protocols that defines how objects interact with Python's built-in syntax and functions — implement the right methods, and your object works with `+`, `len()`, `for`, `with`, and every other language construct as naturally as a built-in type.

---

## Quick Reference

**Core idea:**
- The data model defines how Python's **syntax maps to method calls** on your objects
- `len(x)` → `x.__len__()`; `x + y` → `x.__add__(y)`; `x[i]` → `x.__getitem__(i)`; `for x in obj` → `obj.__iter__()`
- These methods are called **dunder methods** (double underscore on both sides)
- At the C level, dunder methods map to **type slots** in `PyTypeObject` (e.g., `__len__` → `sq_length`)
- The data model is a **protocol system** — implement the right methods, get the language feature; no inheritance required

**Tricky points:**
- `len(x)` is **not** `x.__len__()` in CPython — `len()` goes through `PyObject_Size`, which reads the C slot directly; calling `__len__` manually bypasses some safety checks
- `x + y` tries `x.__add__(y)` first; if that returns `NotImplemented`, Python tries `y.__radd__(x)` — knowing this matters when implementing numeric types
- A class with `__getitem__` but **no `__iter__`** is still iterable — Python falls back to calling `__getitem__` with integers starting at 0 until `IndexError`; this is a legacy protocol
- `__eq__` without `__hash__` makes your class **unhashable** — Python sets `__hash__ = None` automatically

---

## What It Is

Think of a city's building code. The code does not care what a building looks like or what it is made of. It only asks: does it have fire exits? Does it meet load-bearing requirements? Is the wiring up to standard? Any building that satisfies the code participates fully in city life — it can be listed on maps, receive utilities, host businesses, and be sold. A building that ignores the code is rejected. Python's data model works the same way. Python does not care whether your object is a built-in type or something you wrote yourself. It only asks: does it implement the right methods? Any object that does participates in Python's language constructs as a first-class citizen.

When you write `len(my_object)`, Python does not have a hard-coded list of types it knows the length of. Instead, it calls `my_object.__len__()`. When you write `my_object + other`, Python calls `my_object.__add__(other)`. When you iterate over `my_object` in a `for` loop, Python calls `my_object.__iter__()` to get an iterator. These special methods — named with double underscores on both sides — are the data model's vocabulary. They are the contract between your object and the Python language.

This design means Python's language features are extensible without modifying the language itself. You can write a class that behaves like a number, like a container, like a function, or like a context manager, purely by implementing the appropriate dunder methods. The `+` operator, the `in` operator, the `with` statement, the `[]` subscript — all of these are defined in terms of methods that any class can provide. This is not duck typing as a philosophy; it is duck typing as a formal specification.

---

## How It Actually Works

At the C level, CPython does not call `__len__` as a Python method lookup when you use `len()`. Instead, CPython maintains a table of C function pointers inside every type object (`PyTypeObject`). These are called type slots. Each slot corresponds to one or more dunder methods. The `sq_length` and `mp_length` slots correspond to `__len__`. The `nb_add` slot corresponds to `__add__`. The `tp_call` slot corresponds to `__call__`. The `tp_iter` slot corresponds to `__iter__`. When CPython evaluates `len(x)`, it calls the C function `PyObject_Size(x)`, which reads the `sq_length` or `mp_length` slot from `x`'s type object and calls it directly — no Python-level attribute lookup involved.

For built-in types like `list` and `dict`, these slots are populated with C functions directly. There is no `__len__` method object; there is just a C function pointer in the slot. For user-defined classes, CPython populates the slots with wrapper functions that perform a Python-level method lookup and call the corresponding dunder method. This is why calling `len(my_object)` is slightly faster than calling `my_object.__len__()` directly in some situations — `len()` goes through the C slot; the direct method call goes through Python's attribute lookup machinery.

The slot table is also why the data model is defined at the type level, not the instance level. You cannot give a single instance of a class a custom `__add__` that differs from other instances of the same class — the slot is on the type, not the instance. The data model is a type-level contract. User-defined classes implement it by defining dunder methods in the class body, which CPython then wraps and registers in the class's type slot table when the class is created.

---

## How It Connects

The slot table that implements the data model lives inside `ob_type` — the type pointer in every `PyObject`. Every object's type object contains the slot table that defines how that object responds to language constructs. The "everything is an object" principle is what makes the data model uniform: because every value has a type, every value can participate in the protocol system.
[[everything-is-an-object|Everything is an Object]]

The data model defines what dunder methods exist and what they are for. The concrete reference — the full list of every dunder method, what protocol it belongs to, and what Python construct calls it — is covered separately because the list is large and each method has its own rules.
[[dunder-methods|Dunder Methods]]

The iterator protocol — `__iter__` and `__next__` — is one of the most important protocols in the data model. It defines how `for` loops, comprehensions, `zip`, `map`, and dozens of other constructs interact with your objects. Understanding iterators is understanding one of the data model's most-used protocols in practice.
[[iterators|Iterators and Iterables]]

---

## Common Misconceptions

Misconception 1: "You need to inherit from a base class to make Python treat your object as a sequence or mapping."
Reality: Python's data model is protocol-based, not inheritance-based. A class with `__getitem__` and `__len__` works as a sequence with `for`, `in`, and indexing without inheriting from `list` or `Sequence`. Inheriting from `collections.abc` base classes gives you default implementations of derived methods for free, but it is not required for the basic protocol to work.

Misconception 2: "Dunder methods are just regular methods with a special naming convention."
Reality: Dunder methods are looked up on the type, not the instance. CPython skips the normal instance attribute lookup for special method dispatch — it goes directly to the type's slot table. This means that setting `instance.__len__ = lambda: 42` does not make `len(instance)` return 42, because `len()` reads the type's `sq_length` slot, not the instance's `__len__` attribute. This instance-level override works for some dunders when called explicitly (`instance.__len__()`), but not for built-in operations that go through the C slot machinery.

---

## Why It Matters in Practice

The data model is what makes Python's standard library composable. `sorted()` works on any object with `__lt__`. `sum()` works on any object with `__add__` and `__radd__`. `json.dumps()` can be extended with a custom encoder that defines `default()`. `pathlib.Path` supports `/` for path joining because it implements `__truediv__`. These are not special cases built into the language — they are all consequences of objects implementing data model methods.

Understanding the data model also demystifies Python's syntax. Every time you see `x[i]`, know that CPython is calling `__getitem__`. Every time you see `with obj:`, know that CPython is calling `__enter__` and `__exit__`. Every time you see `if x:`, know that CPython is calling `__bool__`, falling back to `__len__` if `__bool__` is not defined. The syntax is a layer of readability over a consistent method-dispatch protocol, and knowing the protocol means you always know what is actually happening.

---

## Interview Angle

Common question forms:
- "What is Python's data model?"
- "How does Python's `for` loop work?"
- "How would you make your class work with `len()` and `in`?"

Answer frame: Define the data model as the protocol system that maps language syntax to method calls. Give two or three concrete examples (`len` → `__len__`, `+` → `__add__`, `for` → `__iter__`). Mention that the methods are looked up on the type, not the instance, and that built-in operations go through C-level type slots. Show that protocol-based design means no inheritance is required — implement the methods and you get the behavior.

---

## Related Notes

- [[everything-is-an-object|Everything is an Object]]
- [[dunder-methods|Dunder Methods]]
- [[iterators|Iterators and Iterables]]
- [[cpython|CPython]]
