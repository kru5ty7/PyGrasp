---
title: 06 - Method Resolution Order (MRO)
description: "The MRO is the ordered list of classes Python searches when looking up an attribute  -  it is computed by the C3 linearization algorithm, accessible via `__mro__`, and determines which class's method wins in multiple inheritance hierarchies."
tags: [mro, method-resolution-order, c3-linearization, multiple-inheritance, cpython, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Method Resolution Order (MRO)

> The MRO is the ordered list of classes Python searches when looking up an attribute  -  it is computed by the C3 linearization algorithm, accessible via `__mro__`, and determines which class's method wins in multiple inheritance hierarchies.

---

## Quick Reference

**Core idea:**
- `SomeClass.__mro__` is a tuple of classes in the order Python searches for attributes  -  starts with the class itself, ends with `object`
- Python uses the **C3 linearization** algorithm to compute the MRO, which guarantees: (1) subclasses appear before their parents, (2) base class order from the `class` definition is respected
- Attribute lookup: `obj.attr` searches each class in `type(obj).__mro__` in order, returning the first match
- `super()` returns a proxy that searches the MRO starting **after** the current class  -  it does not directly call the parent class
- An inconsistent MRO (one that cannot satisfy the C3 constraints) raises `TypeError` at class definition time

**Tricky points:**
- `super()` is **not** "call the parent class"  -  it is "call the next class in the MRO"  -  this matters in cooperative multiple inheritance where multiple classes `super().__init__()` to form a chain
- The MRO is computed once at class creation and stored in `__mro__`  -  it does not change at runtime
- `type.mro(cls)` can be overridden in a metaclass to provide a custom MRO  -  rarely needed but occasionally used in ORMs
- **Diamond inheritance** (A inherits from B and C, both inheriting from D) is handled correctly by C3  -  D appears only once in the MRO, after both B and C
- `object` is always the last class in every Python class's MRO  -  every class ultimately inherits from `object`

---

## What It Is

Think of a company's organizational chart where an employee reports to multiple managers. When the employee needs to escalate a decision, they go to their direct manager first. If that manager cannot handle it, they go to the next manager in a specific order. The question "which manager do I ask first?" is answered by the MRO  -  a predetermined order that ensures consistency and avoids asking the same manager twice. Python's MRO answers the same question for attribute lookup: when Python cannot find `method` on `obj`'s own class, it checks the next class in the MRO, then the next, until found or exhausted.

Single inheritance is simple: `Dog` inherits from `Animal` which inherits from `object`. The MRO is `(Dog, Animal, object)`. Attribute lookup tries `Dog` first, then `Animal`, then `object`. Multiple inheritance complicates this: `class C(A, B)` inherits from both `A` and `B`. If both define a `method`, which wins? The MRO provides a deterministic answer  -  the class listed first in the `class C(A, B)` bases list comes first in the search order.

The C3 algorithm is what makes Python's MRO more principled than a naive depth-first left-to-right search. C3 ensures two properties: a subclass always appears before its superclasses (local precedence), and the base class order specified by the programmer is preserved (monotonicity). These properties together prevent surprising attribute resolution in complex diamond-shaped inheritance hierarchies.

---

## How It Actually Works

The C3 linearization algorithm computes the MRO as follows. For class `C(B1, B2, ..., BN)`, the MRO is computed as: `C` + merge(MRO(B1), MRO(B2), ..., MRO(BN), [B1, B2, ..., BN]). The `merge` operation takes the first element of the first non-empty list if that element does not appear in the tail of any other list; outputs it, removes it from all lists, and repeats. If no valid element can be found, the MRO is inconsistent and a `TypeError` is raised.

For a diamond: `class D(B, C)` where `B(A)` and `C(A)`: MROs are `B = [B, A, object]`, `C = [C, A, object]`. Merge: try `D`'s first list head `B`  -  `B` not in tail of `[C, A, object]` or `[B, C]`? `B` not in any tail, so output `B`. Next: `[A, object]`, `[C, A, object]`, `[C]`. Try head `A`  -  `A` appears in tail of `[C, A, object]`. Skip. Try head `C`  -  `C` not in any tail. Output `C`. Continue until done. Result: `[D, B, C, A, object]`. `A` appears once, after both `B` and `C`.

`super()` with no arguments (the common modern form) works by reading `__class__` (the cell variable capturing the class being defined) and the first argument `self`. It finds `type(self).__mro__`, locates `__class__` in the MRO, and returns a proxy that starts searching from the next position. This is why `super().__init__()` in a class method calls the next class's `__init__` in the MRO  -  which may not be the direct parent class in complex multiple inheritance.

---

## How It Connects

Class creation is where the MRO is computed and stored. When `type.__new__` creates a class object from its bases, it calls `type.mro()` to compute the MRO and stores the result in `cls.__mro__`. An inconsistent MRO raises `TypeError` at class definition time, before any instances can be created.
[[class-creation|How Classes Are Created]]

Multiple inheritance is the scenario where the MRO matters most. For single inheritance, the MRO is trivially `(class, parent, ..., object)`. For multiple inheritance  -  especially the cooperative multiple inheritance pattern where all classes in a hierarchy use `super()`  -  understanding the MRO is essential to predicting which `__init__` methods are called and in what order.
[[multiple-inheritance|Multiple Inheritance]]

---

## Common Misconceptions

Misconception 1: "`super().__init__()` calls the parent class's `__init__`."
Reality: `super().__init__()` calls the next class in the MRO's `__init__`. In single inheritance, this is the parent class. In multiple inheritance with cooperative `super()` calls, it may call a "sibling" class's `__init__` before the grandparent's. The MRO for `class D(B, C)` where `B(A)` and `C(A)` is `[D, B, C, A]`. `D.__init__` calling `super().__init__()` calls `B.__init__`. If `B.__init__` also calls `super().__init__()`, it calls `C.__init__`, not `A.__init__`  -  because the MRO says `C` comes before `A`.

Misconception 2: "An inconsistent MRO causes a runtime error when the method is called."
Reality: Python detects an inconsistent MRO at class definition time and raises `TypeError` immediately. The `class` statement fails; the class is never created. This is a compile-time-ish error (at import time for module-level classes), not a runtime error. Python checks MRO consistency eagerly to fail fast rather than allowing a class to exist with undefined lookup behavior.

---

## Why It Matters in Practice

Cooperative multiple inheritance  -  where every class in a hierarchy uses `super().__init__(**kwargs)` and passes unrecognized kwargs upward  -  is the correct pattern for combining multiple behaviors through multiple inheritance. The MRO guarantees that every class's `__init__` is called exactly once, in the order the MRO specifies, with `object.__init__` at the end of the chain. This pattern is used in Django class-based views, where `View`, `LoginRequiredMixin`, `PermissionRequiredMixin`, and `TemplateResponseMixin` combine through multiple inheritance, each adding behavior to `dispatch()` and `__init__`.

`inspect.getmro(cls)` and `cls.__mro__` both give the MRO  -  use them to debug unexpected method resolution. When a method call produces the wrong implementation, printing the MRO immediately shows which class will be searched first and explains which definition "wins."

---

## Interview Angle

Common question forms:
- "What is the MRO in Python?"
- "How does `super()` work in multiple inheritance?"
- "What is C3 linearization?"

Answer frame: The MRO is the ordered tuple of classes Python searches for attribute lookup  -  computed by C3 linearization, stored in `__mro__`. C3 guarantees subclasses before superclasses and respects declaration order. `super()` finds the current class in `type(self).__mro__` and returns a proxy starting from the next class. In diamond inheritance, `super()` enables cooperative MRO traversal  -  each class calls `super().__init__()` so every class gets called exactly once. Inconsistent MRO raises TypeError at class definition time.

---

## Related Notes

- [[multiple-inheritance|Multiple Inheritance]]
- [[class-creation|How Classes Are Created]]
- [[python-data-model|The Python Data Model]]
- [[dunder-methods|Dunder Methods]]
