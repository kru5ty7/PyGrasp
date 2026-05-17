---
title: classmethod vs staticmethod
description: `@classmethod` makes a method receive the class as its first argument instead of an instance, enabling alternative constructors and class-level operations; `@staticmethod` makes a method receive no implicit first argument, making it a namespace-scoped plain function.
tags: [classmethod, staticmethod, method-types, descriptors, factory-methods, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# classmethod vs staticmethod

> `@classmethod` makes a method receive the class as its first argument instead of an instance, enabling alternative constructors and class-level operations; `@staticmethod` makes a method receive no implicit first argument, making it a namespace-scoped plain function.

---

## Quick Reference

**Core idea:**
- **Regular method**: `def method(self, ...)` — receives the instance as `self`; called as `obj.method()`
- **`@classmethod`**: `def method(cls, ...)` — receives the class as `cls`; called on class or instance; most useful for alternative constructors
- **`@staticmethod`**: `def method(...)` — receives no implicit argument; is a plain function placed in the class namespace
- Both `classmethod` and `staticmethod` are **descriptors** — their `__get__` methods transform how the underlying function is called
- `classmethod` is inherited correctly in subclasses — `cls` refers to the subclass that the method was called on, not the class where it was defined

**Tricky points:**
- `cls` in a classmethod is the **calling class**, not the defining class — `SubClass.from_string(...)` gives `cls = SubClass`, not `BaseClass`; this is what makes classmethods correct for factory methods in inheritance
- `@staticmethod` methods cannot call other class or instance methods without an explicit reference — they have no `self` or `cls`; they are pure functions inside a namespace
- `classmethod` called on an instance still receives the **class** as `cls`, not the instance — `obj.from_string(s)` is equivalent to `type(obj).from_string(s)`
- `@classmethod @property` (combined) is deprecated in Python 3.11 and removed in 3.13 — they should not be stacked
- `staticmethod` objects accessed via the class return the raw function; via an instance also return the raw function — no binding occurs at all

---

## What It Is

Think of a company's different types of employees. A regular method is a floor employee who reports to their specific manager (the instance) and knows exactly which department they are in based on their badge. A classmethod is a company-level liaison who represents the entire department — whichever department calls on them. When the Marketing department calls a classmethod, `cls` is `Marketing`; when Sales calls the same method, `cls` is `Sales`. A staticmethod is a consultant who has no badge at all — they show up to the office (the class namespace) but are not affiliated with any specific department or employee; they just do their independent work.

The most important use case for `@classmethod` is alternative constructors — factory methods that create instances from different input formats. `datetime.now()`, `datetime.fromtimestamp(ts)`, and `datetime.fromisoformat(s)` are all classmethods on `datetime`. Each creates a `datetime` instance from a different input format. They call `cls(year, month, day, ...)` internally — using `cls` instead of `datetime` directly ensures that subclasses of `datetime` that call `cls.fromisoformat(s)` get a subclass instance, not a base class instance.

`@staticmethod` is the right choice when a method logically belongs in the class namespace but does not need access to the class or any instance. A utility function that validates a date format string: it does not need `self` or `cls` — it only needs the string argument. Placing it as a `staticmethod` signals this independence explicitly, and tools like linters and type checkers can flag accidental use of `self` or `cls` inside static methods.

---

## How It Actually Works

Both `classmethod` and `staticmethod` are descriptors. `classmethod.__get__(self, obj, objtype)` returns a bound method where the first argument is bound to `objtype` (the class). When called as `MyClass.method(arg)`, CPython calls `classmethod.__get__(None, MyClass)` which returns a partial-applied callable that passes `MyClass` as the first argument. When called as `instance.method(arg)`, CPython calls `classmethod.__get__(instance, type(instance))` which returns a partial-applied callable with `type(instance)` as the first argument.

`staticmethod.__get__(self, obj, objtype)` simply returns the underlying function — no binding, no class, no instance. Accessing `MyClass.static_method` or `instance.static_method` both return the same unwrapped function.

The inheritance behavior of classmethod is its most important property. Given:

```python
class Base:
    @classmethod
    def create(cls):
        return cls()

class Sub(Base):
    pass
```

`Sub.create()` calls `create` with `cls = Sub` and returns a `Sub()` instance. `Base.create()` calls `create` with `cls = Base` and returns a `Base()` instance. If `create` had used `Base()` directly instead of `cls()`, subclasses would always get `Base` instances from inherited factory methods — a common bug in older Python code.

---

## How It Connects

`classmethod` and `staticmethod` are descriptors. Their descriptor `__get__` methods implement the binding behavior. Understanding the descriptor protocol explains why calling `MyClass.classmethod()` automatically receives the class as the first argument.
[[descriptors|Descriptors]]

Alternative constructors are the primary use case for classmethods. They are part of the broader class creation and instantiation topic — a classmethod creates an instance via `cls(...)`, which calls `cls.__new__` and `cls.__init__`.
[[class-creation|How Classes Are Created]]

---

## Common Misconceptions

Misconception 1: "A `@classmethod` always receives the defining class."
Reality: A classmethod receives the **calling class** — the class (or the class of the instance) from which it was called. `Sub.create()` receives `cls=Sub` even though `create` is defined in `Base`. This is the design feature that makes classmethods correct for factory methods: `cls()` creates an instance of the right subclass. If you want the defining class, you can hardcode `Base()` — but that defeats the purpose of subclass-aware factories.

Misconception 2: "`@staticmethod` is just a regular function outside the class."
Reality: There is a practical difference. A `staticmethod` inside the class is accessible via the class namespace (`MyClass.static_method()`) and is inherited by subclasses — `Sub.static_method()` works. A module-level function is not part of any class and not inherited. `staticmethod` is for utility functions that conceptually belong with a class (they operate on or relate to the class's domain) but do not need `self` or `cls`. It is a namespace and inheritance decision, not just "put it outside the class."

---

## Why It Matters in Practice

The `datetime.fromisoformat()` pattern is worth internalizing. Whenever a class can be constructed from multiple input formats, the right design is classmethods: `User.from_dict(d)`, `User.from_json(s)`, `User.from_row(row)`. Each classmethod validates and transforms its input format before calling `cls(...)`. The `__init__` stays clean and simple (receives already-validated values). The factory methods handle the diversity of input formats.

`@staticmethod` for utility functions that live in a class namespace reduces cognitive load: it signals "this function has no side effects on the instance or class state — it is a pure computation." Type checkers can verify this. Code reviewers can trust it. It is a documentation choice as much as an implementation one.

---

## Interview Angle

Common question forms:
- "What is the difference between `@classmethod` and `@staticmethod`?"
- "When would you use a classmethod?"
- "How are classmethods inherited?"

Answer frame: Regular method receives `self` (instance). `@classmethod` receives `cls` (the calling class, not necessarily the defining class). `@staticmethod` receives nothing — it is a plain function in the class namespace. Classmethods are correct for factory/alternative constructors: `cls()` inside the classmethod creates an instance of whatever class called the method, not the class where the method is defined. Staticmethods are for utility functions that conceptually belong with the class but don't need instance or class state.

---

## Related Notes

- [[descriptors|Descriptors]]
- [[class-creation|How Classes Are Created]]
- [[python-data-model|The Python Data Model]]
- [[dunder-methods|Dunder Methods]]
