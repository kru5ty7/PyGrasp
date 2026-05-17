---
title: Multiple Inheritance
description: Multiple inheritance allows a class to inherit from more than one parent class — Python resolves attribute lookup order using the MRO (C3 linearization), and cooperative multiple inheritance with `super()` is the correct pattern for combining behaviors.
tags: [multiple-inheritance, mixin, super, mro, cooperative-inheritance, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Multiple Inheritance

> Multiple inheritance allows a class to inherit from more than one parent class — Python resolves attribute lookup order using the MRO (C3 linearization), and cooperative multiple inheritance with `super()` is the correct pattern for combining behaviors.

---

## Quick Reference

**Core idea:**
- `class C(A, B):` inherits from both `A` and `B` — methods and attributes from both are available on instances of `C`
- Attribute lookup follows the **MRO** — Python searches `C`, then `A`, then `B` (and their ancestors), in C3-linearization order
- **Mixins** are the primary use case — small classes that add one specific behavior (logging, caching, authentication) and are combined via multiple inheritance
- **Cooperative multiple inheritance**: every class in the hierarchy calls `super().__init__(**kwargs)` — ensures all `__init__` methods in the MRO are called exactly once
- The "diamond problem" (A inherits from B and C, both from D): Python's MRO solves it — D appears once in the MRO, after both B and C

**Tricky points:**
- A mixin should **not** inherit from the class it is meant to augment — `class LoggingMixin:` (no bases except `object`), not `class LoggingMixin(BaseClass):`
- Cooperative `super()` requires **all classes** in the chain to use it — one class that directly calls `Parent.__init__(self)` instead of `super().__init__()` breaks the chain
- **kwargs passing**: cooperative `__init__` chains must pass unrecognized kwargs up with `**kwargs`; `object.__init__` accepts `(self)` and should receive an empty kwargs dict at the end of the chain
- Mixins that define the same method name as the main class create silent overrides based on MRO order — list base classes with mixins first to ensure they override the main class
- Multiple inheritance with C extensions can cause metaclass conflicts — C extension types often have incompatible metaclasses

---

## What It Is

Think of a restaurant that combines a coffee shop and a bookstore. The combined business (a class with multiple inheritance) has all the capabilities of a coffee shop (making espresso, serving pastries) and all the capabilities of a bookstore (stocking books, handling returns). Customers can use both sets of services. The combined business had to figure out how to handle ambiguity — when both coffee shop and bookstore have a "greet customer" protocol, whose protocol do they follow? They adopt one first (the first in the inheritance list) and have the other as a fallback.

Multiple inheritance is Python's answer to the problem of combining behaviors from multiple sources. The classic use case is **mixins**: small, focused classes that add a single capability. `class TimestampMixin:` adds `created_at` and `updated_at` fields. `class SoftDeleteMixin:` adds a `deleted` flag and overrides `delete()`. `class AuditMixin:` logs changes. Combining these: `class UserModel(TimestampMixin, SoftDeleteMixin, AuditMixin, BaseModel):` creates a class with all four behaviors, without any single parent class needing to know about the others.

Mixins work well because they are designed for composition. Each mixin focuses on one concern, does not depend on the other mixins, and uses `super()` to participate in the cooperative call chain. The main class provides the primary behavior; the mixins add orthogonal enhancements. The MRO determines the order in which method calls traverse the chain.

---

## How It Actually Works

For `class D(B, C)` where `B(A)` and `C(A)`, the MRO is `[D, B, C, A, object]`. When `d.method()` is called, Python searches this order and calls the first matching definition. If only `A` and `C` define `method`, the one in `C` is called — not because `C` is "closer" to `D`, but because `C` appears before `A` in the MRO.

Cooperative `__init__` works through `super()`. In a cooperative hierarchy, every class calls `super().__init__(**kwargs)`:

```python
class A(object):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.a_setup()

class B(object):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.b_setup()

class C(A, B):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)  # calls A.__init__
        # A.__init__ calls super() → calls B.__init__
        # B.__init__ calls super() → calls object.__init__
```

The MRO for `C` is `[C, A, B, object]`. `C.__init__` calling `super().__init__()` hits `A.__init__`. `A.__init__` calling `super().__init__()` hits `B.__init__` (not `object`, because `B` comes before `object` in the MRO). `B.__init__` calling `super().__init__()` hits `object.__init__`. Every class is called exactly once, in MRO order.

This chain only works if all classes participate. A class that calls `A.__init__(self)` directly instead of `super().__init__()` short-circuits the chain — `B.__init__` would never be called.

---

## How It Connects

The MRO is the algorithm that makes multiple inheritance deterministic. C3 linearization computes the order of classes such that subclasses appear before their parents and declaration order is preserved. Understanding the MRO is required to predict which method is called in any multiple inheritance hierarchy.
[[mro|Method Resolution Order (MRO)]]

Abstract base classes use multiple inheritance for structural subtyping. `class MyList(MutableSequence, MyBase):` inherits abstract method requirements from `MutableSequence` and concrete behavior from `MyBase`. Understanding multiple inheritance is required to use the `abc` module effectively.
[[abstract-base-classes|Abstract Base Classes]]

---

## Common Misconceptions

Misconception 1: "Multiple inheritance is dangerous and should be avoided."
Reality: Multiple inheritance is dangerous when misused — when classes have tangled dependencies, when `super()` is not used cooperatively, or when inheritance is used for code reuse where composition would be more appropriate. Used correctly — with focused mixins, cooperative `super()`, and clear separation of concerns — multiple inheritance is powerful and widely used in Python frameworks (Django CBVs, Python's `io` module, `logging` handlers). The key is design discipline, not avoidance.

Misconception 2: "You should list the most important parent class last."
Reality: The order of base classes in `class C(A, B)` determines the MRO — `A` and its ancestors are searched before `B`. Mixins should typically be listed first because you want their method overrides to take precedence over the main class's methods. `class UserView(LoginRequiredMixin, View)` means `LoginRequiredMixin.dispatch()` (which checks login) is found before `View.dispatch()` — which is the intended behavior.

---

## Why It Matters in Practice

Django's class-based views (CBVs) are the most common real-world example of cooperative multiple inheritance in Python. `class ArticleDetailView(LoginRequiredMixin, PermissionRequiredMixin, DetailView)` combines authentication checking, permission checking, and the actual detail view rendering. Each mixin overrides `dispatch()` and calls `super().dispatch()` — the chain ensures all checks run before rendering. The MRO determines their order; listing them left-to-right in the class definition controls the check sequence.

The `collections.abc` module defines abstract base classes for containers using multiple inheritance. `MutableSequence` defines the abstract interface for list-like objects; implementing the required abstract methods (`__getitem__`, `__setitem__`, `__delitem__`, `__len__`, `insert`) gives the class all the derived methods (`append`, `extend`, `remove`, `pop`) through mixin methods inherited via MRO.

---

## Interview Angle

Common question forms:
- "Explain multiple inheritance in Python."
- "What is a mixin?"
- "How does `super()` work in multiple inheritance?"

Answer frame: Multiple inheritance: `class C(A, B)` inherits from both. MRO (C3 linearization) determines attribute lookup order — subclass first, then left-to-right bases, each appearing once. Mixin pattern: small, single-purpose classes with no state dependencies, combined via multiple inheritance. Cooperative `super()`: every class in the hierarchy calls `super().__init__(**kwargs)`, which threads the call through the full MRO so every `__init__` runs exactly once. Mixins listed left in the class definition take precedence.

---

## Related Notes

- [[mro|Method Resolution Order (MRO)]]
- [[abstract-base-classes|Abstract Base Classes]]
- [[class-creation|How Classes Are Created]]
- [[python-data-model|The Python Data Model]]
