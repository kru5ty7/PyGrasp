---
title: Abstract Base Classes
description: "Abstract base classes (ABCs) define interfaces that concrete subclasses must implement — using `abc.ABCMeta` and `@abstractmethod`, Python enforces that subclasses provide required methods before instances can be created."
tags: [abc, abstract-base-classes, abstractmethod, interface, protocol, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Abstract Base Classes

> Abstract base classes (ABCs) define interfaces that concrete subclasses must implement — using `abc.ABCMeta` and `@abstractmethod`, Python enforces that subclasses provide required methods before instances can be created.

---

## Quick Reference

**Core idea:**
- An **abstract base class** defines methods with `@abstractmethod` that subclasses **must** override — instantiating a subclass that has not implemented all abstract methods raises `TypeError`
- Use `class MyABC(ABC):` (from `abc` module) or `class MyABC(metaclass=ABCMeta):` to create an ABC
- `@abstractmethod` marks a method as requiring concrete implementation; `@abstractproperty`, `@abstractclassmethod`, and `@abstractstaticmethod` do the same for properties/classmethods/staticmethods
- `abc.ABC` is a convenience class that uses `ABCMeta` as its metaclass — inherit from it instead of specifying `metaclass=ABCMeta` directly
- ABCs in `collections.abc` define standard container interfaces (`Iterable`, `Sequence`, `Mapping`, `MutableSet`) with concrete mixin methods for classes that implement the abstract ones

**Tricky points:**
- Abstract method enforcement happens at **instantiation time**, not at class definition time — defining a subclass that does not implement abstract methods does not immediately raise an error
- A class is concrete (can be instantiated) if it has **zero** `__abstractmethods__` — the `__abstractmethods__` frozenset can be inspected on any class
- **Virtual subclasses** via `abc.register(cls)` tell an ABC that `cls` is a subclass even if it does not inherit from the ABC — `isinstance(cls_instance, MyABC)` returns `True` without inheritance
- Overriding an abstract method with another `@abstractmethod` keeps the method abstract — the subclass can still not be instantiated
- `collections.abc.Sequence` provides `__contains__`, `__iter__`, `__reversed__`, `index`, and `count` as mixin implementations based on `__getitem__` and `__len__` — implement only the required methods and get the rest for free

---

## What It Is

Think of an employment contract template. The template specifies required duties that any employee filling this role must perform — without completing those duties, the employment contract cannot be finalized. An abstract base class is that template: it declares the required "duties" (methods) that any concrete implementation must provide. If a class claims to fill the role (inherits from the ABC) but has not fulfilled all required duties (implemented all abstract methods), Python refuses to create instances of it — the equivalent of refusing to finalize the contract.

ABCs solve the problem of accidental interface violations. Without ABCs, a class that is supposed to behave like a `Sequence` (supporting `__getitem__`, `__len__`, `__contains__`, `__iter__`, etc.) could forget to implement some of those methods, and the omission would only be discovered at runtime when the missing method is called. ABCs make the interface explicit and enforce completeness at instantiation time — you discover the missing method when you try to create an instance, not when some caller uses the missing functionality.

Python's `collections.abc` module defines ABCs for the standard container protocols: `Container`, `Iterable`, `Iterator`, `Sequence`, `MutableSequence`, `Mapping`, `MutableMapping`, `Set`, `MutableSet`. These ABCs come with abstract methods (that you must implement) and concrete mixin methods (that you get for free once you implement the required ones). Implementing `__getitem__` and `__len__` on a class that inherits from `Sequence` automatically provides working `__contains__`, `__iter__`, `__reversed__`, `index`, and `count` methods.

---

## How It Actually Works

`ABCMeta` is the metaclass that implements abstract method enforcement. When a class is defined with `ABCMeta` as its metaclass, `ABCMeta.__new__` scans the class namespace and all base classes for methods decorated with `@abstractmethod`. The set of abstract method names is stored in `cls.__abstractmethods__` as a frozenset.

When an instance is created (`cls()`), `type.__call__` checks `cls.__abstractmethods__`. If the frozenset is non-empty, `TypeError: Can't instantiate abstract class X with abstract method(s) Y` is raised. If the subclass defines all abstract methods (overriding each with a non-abstract implementation), `__abstractmethods__` is empty and instantiation succeeds.

`@abstractmethod` is a decorator that sets `func.__isabstractmethod__ = True`. `ABCMeta.__new__` collects all names in the namespace with `__isabstractmethod__ = True`. A subclass that provides a concrete implementation of `method` (without `@abstractmethod`) causes the name to be removed from the subclass's `__abstractmethods__`.

`abc.register()` implements the virtual subclass mechanism. `MyABC.register(SomeExistingClass)` adds `SomeExistingClass` to a list that `__instancecheck__` and `__subclasscheck__` consult. `isinstance(some_existing_instance, MyABC)` returns `True` without `SomeExistingClass` inheriting from `MyABC`. This enables "duck typing with explicit registration" — you can declare that an existing class satisfies an ABC's interface without modifying that class.

---

## How It Connects

ABCs are related to Protocols (Python 3.8+), which take a different approach to interface definition. ABCs use nominal subtyping: a class must explicitly inherit from (or register with) the ABC to be considered a subclass. Protocols use structural subtyping: any class that has the required methods is considered to satisfy the protocol, with no inheritance or registration needed.
[[protocols|Protocols and Structural Subtyping]]

Multiple inheritance enables the mixin methods in `collections.abc`. `MutableSequence` uses multiple inheritance to inherit abstract methods from `Sequence` and add its own, while providing concrete mixin methods. A class that inherits from `MutableSequence` and implements the required abstract methods gets all mixin methods through the MRO.
[[multiple-inheritance|Multiple Inheritance]]

---

## Common Misconceptions

Misconception 1: "You cannot instantiate an abstract class at all."
Reality: You cannot instantiate a class that has abstract methods (non-empty `__abstractmethods__`). An abstract base class that defines no abstract methods (used purely as a shared base for registration or mixin behavior) can be instantiated. `ABC` itself can be instantiated: `abc.ABC()` works. The restriction is specifically on classes with unimplemented abstract methods.

Misconception 2: "ABCs and Protocols serve the same purpose."
Reality: ABCs and Protocols both define interfaces, but via different subtyping models. ABCs require explicit registration or inheritance — a class must inherit from `Iterable` or register with it to be considered `Iterable`. Protocols are structural — any class with an `__iter__` method is `Iterable[T]` from mypy's perspective without any declaration. ABCs are checked at runtime (`isinstance`); Protocols are primarily a static type checking tool. They are complementary, not alternatives.

---

## Why It Matters in Practice

Custom ABCs are most useful in framework code where you want to define a plugin interface that third parties implement. `class StorageBackend(ABC): @abstractmethod def store(self, key, value): ...` defines a contract. Any storage implementation (S3, local filesystem, Redis) that inherits from `StorageBackend` and implements `store` (and other required methods) will fail at instantiation time if it misses any method. This is far better than discovering a missing method at production runtime when that specific code path is exercised.

`isinstance(x, collections.abc.Mapping)` is a reliable duck-type check because built-in types like `dict` are registered with `collections.abc.Mapping`. `isinstance({}, collections.abc.Mapping)` is True even though `dict` does not literally inherit from `Mapping`. This registration-based duck typing is safer than `hasattr(x, "__getitem__")` because it checks against a full interface, not just one method.

---

## Interview Angle

Common question forms:
- "What is an abstract base class?"
- "How do you enforce an interface in Python?"
- "What is the difference between ABCs and Protocols?"

Answer frame: ABCs define required methods with `@abstractmethod`; subclasses that do not implement all abstract methods raise `TypeError` when instantiated. Use `class Foo(ABC)`. `collections.abc` provides ABCs for standard container protocols with free mixin methods. `abc.register()` adds virtual subclasses without inheritance. Difference from Protocols: ABCs are nominal (explicit inheritance/registration); Protocols are structural (any class with the right methods qualifies, checked statically by mypy). ABCs provide runtime `isinstance` checks; Protocols are primarily static type checking.

---

## Related Notes

- [[protocols|Protocols and Structural Subtyping]]
- [[multiple-inheritance|Multiple Inheritance]]
- [[mro|Method Resolution Order (MRO)]]
- [[dunder-methods|Dunder Methods]]
