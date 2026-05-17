---
title: type and object
description: "In Python's type system, `object` is the base class of every class and `type` is the metaclass of every class — they form a circular bootstrap relationship where each is an instance of the other, making them the two roots of Python's entire object hierarchy."
tags: [type, object, metaclass, class-hierarchy, cpython, python-data-model, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# type and object

> In Python's type system, `object` is the base class of every class and `type` is the metaclass of every class — they form a circular bootstrap relationship where each is an instance of the other, making them the two roots of Python's entire object hierarchy.

---

## Quick Reference

**Core idea:**
- `object` is the **base class** of all Python classes — every class implicitly inherits from `object` if no other base is specified
- `type` is the **metaclass** of all Python classes — every class is an instance of `type` (including `type` itself)
- The circular relationship: `isinstance(object, type)` is `True`; `isinstance(type, object)` is `True`; `type(type) is type` is `True`
- `type(x)` returns the type of `x`; `type(name, bases, dict)` creates a new class dynamically — the same `type` serves both purposes
- All built-in types (`int`, `str`, `list`, `dict`) are instances of `type` and subclasses of `object`

**Tricky points:**
- `type` is both a **class** and a **function** — `type(x)` with one argument inspects the type; `type(name, bases, dict)` with three arguments creates a class
- `isinstance(42, object)` is `True` — every Python object, including built-in values, is an instance of `object` through the inheritance chain
- `type.__mro__` is `(type, object)` — `type` inherits from `object`; `object.__class__` is `type` — they each reference the other
- Custom metaclasses are subclasses of `type` — they inherit `type`'s class-creation behavior and can customize it
- In CPython C code, `type` is `PyType_Type` and `object` is `PyBaseObject_Type` — hardcoded C structs at the base of the type system

---

## What It Is

Think of a manufacturing company that makes both products and the machines that make products. The machines are themselves products — they were made by other machines. At the very base are two primal machines: the "factory maker" (which made itself) and the "base product" (from which all products derive their basic properties). Every product has the base product's properties. Every machine was made by the factory maker. The factory maker was made by itself. The base product was made by the factory maker. This circular bootstrap is exactly the relationship between `type` and `object`.

In Python, every value is an object, and every object has a type. The type of `42` is `int`. The type of `"hello"` is `str`. The type of a class like `int` itself is... `type`. `type` is the class of classes — it is the metaclass, the thing that creates classes. And `type` is itself a class, so it must have a metaclass too — which is `type` itself. `type(type) is type` is True. This self-referential loop is a design choice that provides a consistent object model: everything, without exception, is an object with a type.

`object` is the other root. Every Python class inherits from `object` unless explicitly prevented (which is not normally possible in Python 3 — all classes are "new-style" and implicitly inherit from `object`). `object` provides the default implementations of `__repr__`, `__str__`, `__eq__`, `__hash__`, `__init__`, and other fundamental methods. When a class does not define `__repr__`, it uses `object.__repr__`, which returns the familiar `<MyClass object at 0x...>` string.

---

## How It Actually Works

In CPython's C implementation, `type` is the C struct `PyType_Type` and `object` is `PyBaseObject_Type`. They are hardcoded C-level objects, not created dynamically. Their `ob_type` fields are set to point to each other during interpreter initialization — this bootstrapping is performed in `typeobject.c` with direct C struct initialization, bypassing the normal Python object creation mechanism that would otherwise require both to already exist.

`type` in Python serves two roles via `__new__`. `type.__new__(mcs, name, bases, namespace)` creates a new type object. When Python processes a `class` statement, it calls `type.__new__(type, name, bases, namespace)` — or the metaclass's `__new__` if the class specifies `metaclass=SomeMeta`. The created type object has `ob_type = type` (or the metaclass) and `tp_bases` pointing to the specified base classes.

The MRO (Method Resolution Order) for any class includes `object` as the last entry before the empty tuple. `SomeClass.__mro__` always ends with `(..., object)`. This ensures that if no other class in the hierarchy defines a method, `object`'s implementation is found. `object.__init__` accepts `(self)` and does nothing; `object.__new__` allocates memory for a new instance. These are the defaults that all classes implicitly inherit.

---

## How It Connects

Metaclasses are subclasses of `type` that customize class creation. Understanding `type` as the default metaclass — and as the result of `type(SomeClass)` — is the prerequisite for understanding how metaclasses work and what `class Foo(metaclass=Meta)` means.
[[metaclasses|Metaclasses]]

The Python data model describes all the special methods that `object` provides as defaults. Every class inherits from `object`, so every class starts with a working implementation of `__repr__`, `__eq__`, `__hash__`, and others — customized by overriding in the subclass.
[[python-data-model|The Python Data Model]]

---

## Common Misconceptions

Misconception 1: "`type` and `object` have a confusing relationship that you don't need to understand."
Reality: The `type`/`object` relationship is foundational to Python's uniform object model. `isinstance(x, object)` is True for literally every Python value — this is why `object` is the right base class for catch-all code. `type(MyClass) is type` is True for every class defined with `class` syntax — this is why `type` is the entry point for metaclass customization. These are not exotic edge cases; they explain fundamental Python behaviors.

Misconception 2: "`type(x)` and `x.__class__` always return the same thing."
Reality: For most objects they are equivalent. For old-style class instances (Python 2), they differed. In Python 3, `type(x)` and `x.__class__` return the same value for standard classes. However, `__class__` is a slot that can be reassigned (for compatible types), while `type(x)` always reads the `ob_type` field of the object's C struct. For objects with `__class__` overridden in `__get__`, they can differ.

---

## Why It Matters in Practice

`isinstance(obj, type)` is True for any class — you can use this to test whether something is a class rather than an instance. `isinstance(cls, type)` where `cls = SomeClass` is True; `isinstance(SomeClass(), type)` is False. This is useful in frameworks that accept either class objects or instance objects as arguments.

`type(name, bases, namespace)` is a programmatic class factory used in code generation and testing. `MyClass = type("MyClass", (BaseClass,), {"method": lambda self: 42})` creates a class at runtime. Django's ORM, SQLAlchemy, and many testing frameworks use this to create model classes dynamically from configuration rather than static `class` definitions.

---

## Interview Angle

Common question forms:
- "What is the relationship between `type` and `object`?"
- "What is a metaclass?"
- "What does `type(x)` do?"

Answer frame: `object` is the base class of all classes; every class inherits from it. `type` is the metaclass of all classes; every class is an instance of `type`. They bootstrap each other: `type(object) is type` and `isinstance(type, object)` are both True. `type` with one argument inspects the type; with three arguments it creates a new class. Custom metaclasses subclass `type` and override `__new__` or `__init__` to customize class creation.

---

## Related Notes

- [[python-data-model|The Python Data Model]]
- [[metaclasses|Metaclasses]]
- [[dunder-methods|Dunder Methods]]
- [[mro|Method Resolution Order]]
