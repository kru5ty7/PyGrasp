---
title: 02 - Dunder Methods
description: Dunder methods are the specific Python methods whose names start and end with double underscores  -  they are the hooks the Python data model provides for your classes to participate in language syntax, built-in functions, and operator behavior.
tags: [dunder, magic-methods, data-model, protocols, cpython, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Dunder Methods

> Dunder methods are the specific Python methods whose names start and end with double underscores  -  they are the hooks the Python data model provides for your classes to participate in language syntax, built-in functions, and operator behavior.

---

## Quick Reference

**Core idea:**
- Dunder = **double underscore** on both sides: `__init__`, `__len__`, `__add__`, `__repr__`, `__enter__`, etc.
- Each dunder method corresponds to a specific **language construct or built-in function** that calls it
- Looked up on the **type**, not the instance  -  `len(x)` reads `type(x).__len__`, not `x.__len__`
- Return `NotImplemented` (not `NotImplementedError`) from binary ops to tell Python to try the **reflected method** on the other operand
- `__repr__` is for developers (used in REPL and debugging); `__str__` is for end users (`print()`); if only `__repr__` is defined, `str()` falls back to it

**Tricky points:**
- `__init__` does **not** create the object  -  `__new__` does; `__init__` just initializes it after creation
- Setting `__eq__` without `__hash__` makes your class **unhashable**  -  Python sets `__hash__ = None` automatically
- `__del__` is **not** a destructor you can rely on  -  it is called when the refcount hits zero, but cycles delay it indefinitely; use context managers for resource cleanup instead
- `instance.__len__ = lambda: 0` does **not** make `len(instance)` return 0  -  built-in operations bypass instance `__dict__` and read the type's slot
- `__bool__` is checked first for truthiness; if absent, Python falls back to `__len__`; if both absent, the object is always truthy

---

## What It Is

Think of a restaurant with a strict front-of-house system. There is a specific staff member for every role: someone who seats guests, someone who takes orders, someone who presents the bill. When a new event happens  -  a guest arrives, an order is placed, the meal ends  -  the system calls the right staff member for that event. You cannot substitute whoever you like; the system always calls the designated role. Python's dunder methods work the same way. For every language event  -  an object being created, two objects being added, an object being converted to a string, a context manager being entered  -  Python calls a specific designated method. Define that method, and your class handles the event. Leave it out, and Python falls back to a default or raises a `TypeError`.

The name "dunder" is a contraction of "double underscore." The convention signals that these are part of the language protocol, not regular instance methods  -  they are called by Python, not typically by user code directly. Calling `len(x)` is right; calling `x.__len__()` works but bypasses optimizations. The double underscores exist specifically to avoid name collisions with user-defined attributes: you are unlikely to accidentally define an attribute named `__len__` unless you mean it.

Every dunder method belongs to one or more protocols. The **object protocol** includes `__init__`, `__new__`, `__repr__`, `__str__`, `__bool__`, `__hash__`, `__del__`. The **numeric protocol** includes `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__floordiv__`, `__mod__`, `__pow__`, and their in-place variants (`__iadd__`, etc.) and reflected variants (`__radd__`, etc.). The **container protocol** includes `__len__`, `__getitem__`, `__setitem__`, `__delitem__`, `__contains__`, `__iter__`. The **context manager protocol** is just `__enter__` and `__exit__`. The **descriptor protocol** is `__get__`, `__set__`, `__delete__`.

---

## How It Actually Works

At the C level inside CPython, each dunder method has a corresponding slot in the `PyTypeObject` structure. When a class is created (by `type.__call__` for user-defined classes, or by C code for built-ins), CPython scans the class's `__dict__` for dunder methods and populates the type's slots with appropriate C wrappers. `__len__` populates `sq_length` and/or `mp_length`. `__add__` populates `nb_add`. `__iter__` populates `tp_iter`. `__call__` populates `tp_call`.

The lookup behavior for special methods is different from normal attribute lookup. When Python evaluates `len(x)`, it does not do `getattr(x, '__len__')()`. Instead, it calls `PyObject_Size(x)`, which reads `type(x)->sq_length` or `type(x)->mp_length` directly from the type slot. This means that `__len__` defined on the class is what counts  -  not `__len__` on the instance. You can verify this: after `x.__len__ = lambda: 99`, `len(x)` still returns the class-defined result.

The `NotImplemented` return value (a singleton object, not an exception) is a critical part of how binary operators work. When Python evaluates `a + b`, it calls `type(a).__add__(a, b)`. If that returns `NotImplemented`, Python then tries `type(b).__radd__(b, a)`. If both return `NotImplemented`, Python raises `TypeError`. This two-step lookup allows different types to cooperate  -  a custom numeric type can return `NotImplemented` for types it does not recognize, and those types can implement their own `__radd__` to handle the operation.

---

## How It Connects

Dunder methods are the concrete vocabulary of the Python data model. The data model defines which protocols exist and what their purpose is; dunder methods are the actual method names you implement to participate in those protocols. The data model note covers the big picture; this note covers the specifics.
[[python-data-model|The Python Data Model]]

The descriptor protocol (`__get__`, `__set__`, `__delete__`) is one of the most powerful dunder method groups. It is what makes properties, classmethods, staticmethods, and bound methods work in Python. When you access `instance.attr`, Python checks if the class's `attr` has a `__get__` method and calls it if so  -  the result is not necessarily the stored value.
[[python-data-model|The Python Data Model]]

Context managers rely entirely on two dunder methods: `__enter__` and `__exit__`. The `with` statement calls `__enter__` at the start and `__exit__` at the end  -  whether or not an exception occurred. `__exit__` receives exception information and can suppress it by returning a truthy value.
[[context-managers|Context Managers]]

---

## Common Misconceptions

Misconception 1: "`__init__` creates the object."
Reality: `__new__` creates the object. `__init__` receives an already-created object (as `self`) and initializes its attributes. If `__new__` returns an instance of the class, `__init__` is called on it. If it returns something else (or an instance of a different class), `__init__` is not called. This distinction matters when subclassing immutable types like `int` or `str`  -  you must override `__new__`, not `__init__`, because by the time `__init__` is called the immutable value is already set.

Misconception 2: "Returning `NotImplementedError` from a binary operator is the right way to signal unsupported operations."
Reality: Raising `NotImplementedError` from a dunder method raises the exception immediately and prevents Python from trying the reflected operation. Returning the singleton `NotImplemented` (no "Error") is the correct signal  -  it tells Python "I can't handle this, try the other operand." These are completely different behaviors and the distinction regularly confuses developers seeing them for the first time.

---

## Why It Matters in Practice

Dunder methods are the reason Python's standard library is composable with user-defined types. `sorted()` works on any object with `__lt__`. `collections.Counter` works because `Counter` implements `__add__` and `__sub__`. `pathlib.Path` supports `/` for path joining because it implements `__truediv__`. `contextlib.closing` turns any object with a `.close()` method into a context manager by wrapping it in `__enter__`/`__exit__`. When you understand what dunder methods a library function expects, you know exactly what your class needs to implement to work with it.

The most important dunder method to get right is `__repr__`. It is called in the REPL, in debuggers, in logging, and whenever Python needs to represent your object for a developer. A useful `__repr__` shows enough information to reconstruct the object or diagnose its state. A bad `__repr__`  -  returning something like `<MyObject object at 0x7f4>`  -  forces developers to add print statements or use debuggers instead of being able to inspect objects directly.

---

## Interview Angle

Common question forms:
- "What are dunder methods? Can you give some examples?"
- "What is the difference between `__str__` and `__repr__`?"
- "What does returning `NotImplemented` from `__add__` do?"

Answer frame: Define dunder methods as the protocol hooks defined by the Python data model, called by Python (not user code) in response to language constructs. Give examples across protocols: `__init__` (object creation), `__len__` (len()), `__add__` (+ operator), `__iter__` (for loop), `__enter__`/`__exit__` (with statement). Explain `__repr__` vs `__str__`: `repr` for developers, `str` for users. Explain `NotImplemented` (the singleton return value) vs `NotImplementedError` (an exception)  -  one allows reflection, the other aborts.

---

## Related Notes

- [[python-data-model|The Python Data Model]]
- [[context-managers|Context Managers]]
