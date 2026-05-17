---
title: Metaclasses
description: A metaclass is the class of a class — it controls how a class is created, what attributes it has, and what happens when instances are created from it; `type` is the default metaclass, and custom metaclasses subclass `type` to customize class-level behavior.
tags: [metaclasses, type, class-creation, python-data-model, advanced, layer-1, core]
status: draft
difficulty: advanced
layer: 1
domain: core
created: 2026-05-17
---

# Metaclasses

> A metaclass is the class of a class — it controls how a class is created, what attributes it has, and what happens when instances are created from it; `type` is the default metaclass, and custom metaclasses subclass `type` to customize class-level behavior.

---

## Quick Reference

**Core idea:**
- A metaclass is to a class what a class is to an instance — it is the "factory" that creates class objects
- Specify a metaclass with `class Foo(metaclass=MyMeta):` — Python calls `MyMeta(name, bases, namespace)` to create the class object
- Custom metaclasses override `__new__` (to control the class object itself) or `__init__` (to initialize it after creation)
- `__init_subclass__` (on a base class) is a simpler alternative that runs when a subclass is defined — no metaclass needed
- Class decorators (`@decorator` on a class) are another, simpler alternative for most metaclass use cases

**Tricky points:**
- **Metaclass conflict**: if a class has multiple bases with different metaclasses, Python raises `TypeError` unless one metaclass is a subclass of all others
- `__prepare__` is a metaclass classmethod called before the class body executes — it returns the namespace dict (allowing ordered dicts, special namespaces, etc.)
- Metaclass `__new__` receives `(mcs, name, bases, namespace)` — `mcs` is the metaclass itself, similar to how `cls` is used in `__new__`
- Metaclasses affect **all instances** of all classes using them — a metaclass that adds a method to every class makes that method available on every instance of those classes
- Most metaclass use cases in modern Python are better solved by `__init_subclass__`, class decorators, or `__set_name__` — reserve metaclasses for framework-level class registration and deep customization

---

## What It Is

Think of a government building code agency. The agency does not build any specific building — it defines the rules that all buildings must follow: minimum ceiling height, required number of exits, permitted materials. When a builder (a class statement) creates a new building (a class), the agency's rules are applied: certain features are added automatically, others are checked and rejected. The agency is the metaclass; the buildings are classes; the rooms in buildings are instances. The agency operates at a higher level than any individual building or room.

A metaclass intercepts the class creation process. Normally, `class Foo:` triggers Python to: collect the class body in a namespace dict, then call `type("Foo", (), namespace)` to build the class object. When a metaclass is specified, Python calls `MyMeta("Foo", (), namespace)` instead. The metaclass's `__new__` and `__init__` methods have full control over the resulting class object: they can add attributes, modify the namespace before the class is created, register the class in a global registry, validate that certain methods are defined, or wrap methods automatically.

This makes metaclasses the right tool for framework-level concerns that apply to every class in a hierarchy. Django's ORM uses a metaclass to process field definitions: when you write `name = CharField(max_length=100)` in a model class body, the metaclass's `__new__` discovers these `Field` instances in the namespace, builds the `_meta` attribute, sets up database column names, and creates the SQL column definitions. The developer-written class body is minimal; the metaclass does the heavy lifting of wiring up the ORM.

---

## How It Actually Works

When Python processes `class Foo(Base, metaclass=MyMeta):`, it determines the metaclass by: checking for an explicit `metaclass=` keyword, then checking the metaclasses of all base classes, then defaulting to `type`. If found, Python calls `MyMeta.__prepare__(name, bases)` to get the initial namespace dict (default: `{}`). The class body executes with this namespace as the local scope — definitions (`def`, assignments) populate the namespace. Finally, Python calls `MyMeta(name, bases, namespace)`.

`MyMeta.__new__(mcs, name, bases, namespace)` receives these arguments and must return the new class object. The typical implementation calls `super().__new__(mcs, name, bases, namespace)` to let `type.__new__` do the actual class construction, then modifies the resulting class object before returning it. For example, registering the class:

```python
class RegistryMeta(type):
    registry = {}
    def __new__(mcs, name, bases, namespace):
        cls = super().__new__(mcs, name, bases, namespace)
        mcs.registry[name] = cls
        return cls
```

Every class defined with `metaclass=RegistryMeta` or inheriting from a class with this metaclass is automatically added to `RegistryMeta.registry`.

`__init_subclass__` is the modern, lighter-weight alternative. Defined on a base class, it is called automatically when a subclass is defined:

```python
class Base:
    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        # cls is the new subclass being defined
```

This achieves most metaclass registration and validation use cases without requiring a custom metaclass, avoiding the metaclass conflict problem.

---

## How It Connects

`type` is the default metaclass and the base that all custom metaclasses inherit from. Understanding `type` as both the metaclass of all classes and as a factory function (`type(name, bases, dict)`) is the foundation for understanding how metaclasses extend that factory behavior.
[[type-and-object|type and object]]

Class creation — the full sequence of steps from `class` statement to class object — is what metaclasses intercept. The class creation note describes this sequence in detail: resolving the metaclass, calling `__prepare__`, executing the class body, calling the metaclass.
[[class-creation|How Classes Are Created]]

---

## Common Misconceptions

Misconception 1: "You need metaclasses to customize class behavior."
Reality: Most class customization that used to require metaclasses can now be done with simpler mechanisms. `__init_subclass__` handles subclass registration and validation. Class decorators handle per-class transformations. `__set_name__` (called on descriptors when they are assigned in a class body) handles descriptor registration. The Python data model has evolved to reduce metaclass necessity. Use metaclasses only when you need to intercept the namespace dict before the class body executes (`__prepare__`) or when you need to modify how `type.__new__` works at the C level.

Misconception 2: "Metaclass `__new__` is called every time an instance is created."
Reality: Metaclass `__new__` is called once, when the class itself is created — not when instances of that class are created. `MyClass()` calls `MyClass.__new__(MyClass)` (defined in `MyClass` or inherited from `object`) and then `MyClass.__init__(instance)`. The metaclass's `__new__` already ran when Python processed the `class` statement — hours or days earlier in a server process.

---

## Why It Matters in Practice

Django's `ModelBase` metaclass is the canonical production example. It processes `Field` descriptors declared in model class bodies, builds the `Options` object (`Model._meta`), registers the model in a global app registry, and sets up deferred class initialization for related fields. This metaclass runs once per model class definition (at import time) and sets up the entire ORM infrastructure for that model. Without metaclasses (or a very complex `__init_subclass__`), this initialization would require explicit setup calls in every model class — Django's metaclass makes it automatic and invisible.

Abstract Base Classes (`abc.ABCMeta`) use a metaclass to implement `@abstractmethod` enforcement. The `ABCMeta.__new__` collects all methods marked with `@abstractmethod` in the class body and stores them. `ABCMeta.__call__` (which runs when you instantiate the class) checks if any abstract methods remain unimplemented and raises `TypeError` if so. This is impossible to implement with `__init_subclass__` alone.

---

## Interview Angle

Common question forms:
- "What is a metaclass?"
- "When would you use a metaclass?"
- "What is the difference between a metaclass and a class decorator?"

Answer frame: A metaclass is the class of a class — it controls how class objects are created. `type` is the default metaclass; custom metaclasses inherit from `type` and override `__new__` or `__init__`. Specify with `class Foo(metaclass=MyMeta)`. Use cases: class registration (Django models), interface enforcement (ABCMeta), automatic attribute wiring (ORMs). Modern alternatives: `__init_subclass__` for subclass hooks, class decorators for per-class transformation. Metaclass conflict: multiple bases with incompatible metaclasses raises TypeError.

---

## Related Notes

- [[type-and-object|type and object]]
- [[class-creation|How Classes Are Created]]
- [[python-data-model|The Python Data Model]]
- [[abstract-base-classes|Abstract Base Classes]]
