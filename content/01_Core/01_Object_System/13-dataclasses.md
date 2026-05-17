---
title: Dataclasses
description: "`@dataclass` auto-generates `__init__`, `__repr__`, and `__eq__` from class-level field annotations, reducing boilerplate for data-holding classes while supporting optional features like ordering, immutability, and `__slots__`."
tags: [dataclasses, __init__, __repr__, field, frozen, slots, python-3.7, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Dataclasses

> `@dataclass` auto-generates `__init__`, `__repr__`, and `__eq__` from class-level field annotations, reducing boilerplate for data-holding classes while supporting optional features like ordering, immutability, and `__slots__`.

---

## Quick Reference

**Core idea:**
- `@dataclass` inspects class-level annotations and generates `__init__`, `__repr__`, and `__eq__` automatically
- `field(default_factory=list)` is required for mutable defaults — `default=[]` raises `ValueError` at class definition time
- `@dataclass(frozen=True)` makes instances immutable by generating `__setattr__` and `__delattr__` that raise `FrozenInstanceError`
- `@dataclass(order=True)` generates `__lt__`, `__le__`, `__gt__`, `__ge__` based on field order — fields are compared as if they were a tuple
- `@dataclass(slots=True)` (Python 3.10+) generates `__slots__` automatically from field annotations

**Tricky points:**
- Fields with defaults must come after fields without defaults — same rule as function parameters with defaults
- `field(init=False)` excludes a field from `__init__` — it must have a `default` or `default_factory`, or be set in `__post_init__`
- `__post_init__` is called at the end of the generated `__init__` — use it for computed fields and cross-field validation
- `field(repr=False)` excludes a field from `__repr__` — useful for large or sensitive data
- `@dataclass(eq=False)` skips generating `__eq__` — the default `object.__eq__` (identity) is used instead; needed when inheriting from a class with custom `__eq__`
- `InitVar[T]` annotations are init-only parameters — passed to `__post_init__` but not stored as instance attributes

---

## What It Is

Think of a government form that auto-fills standard fields from your ID. When you file a new address form, the system pre-populates your name, date of birth, and ID number from your existing record — you only fill in the new address. The auto-population is mechanical and consistent; the system doesn't need to ask you to write your name in a different format each time. Python dataclasses are that auto-population system for class boilerplate: given a set of field annotations, the system mechanically generates the repetitive `__init__`, `__repr__`, and `__eq__` that every data-holding class needs — consistently and correctly.

Without `@dataclass`, writing a simple `Point` class requires explicitly writing an `__init__` that assigns `self.x = x`, `self.y = y`, a `__repr__` that formats them, and an `__eq__` that compares them. For a 10-field class, this is 30+ lines of mechanical code that provides no insight — it is just declaration plumbing. `@dataclass` collapses those 30 lines to the 10 field annotations, which are the only lines that contain real information.

The design principle is "declare the structure once, derive the behavior automatically." The field annotations are the specification. The generated methods are mechanical consequences of that specification. When a field is added or renamed, only the annotation changes — all generated methods update automatically.

---

## How It Actually Works

`@dataclass` is a class decorator that inspects `cls.__annotations__` to discover fields. For each annotation, it checks whether the class body has a default value (plain value → `default`, or `field(...)` → field descriptor). It then generates and sets methods on the class using `setattr`.

The generated `__init__` looks roughly like:

```python
def __init__(self, x: int, y: int):
    self.x = x
    self.y = y
```

If `__post_init__` is defined on the class, the generated `__init__` calls `self.__post_init__()` at the end.

`field(default_factory=list)` stores a callable. The generated `__init__` calls `default_factory()` for each new instance — so each instance gets its own list, not a shared reference. This is why plain `default=[]` is rejected: a mutable default would be shared across all instances (the same bug as mutable default function arguments).

`@dataclass(frozen=True)` generates:

```python
def __setattr__(self, name, value):
    raise FrozenInstanceError('cannot assign to field ...')
def __delattr__(self, name):
    raise FrozenInstanceError('cannot delete field ...')
```

It also generates `__hash__` (since frozen instances are immutable and can be hashed). Non-frozen dataclasses with `eq=True` set `__hash__ = None` (making them unhashable) to avoid the inconsistency of equal objects with different hashes.

`@dataclass(slots=True)` (3.10+) creates a new class with `__slots__` set to the field names. It cannot modify the existing class in-place because `__slots__` must be set at class creation — the decorator creates a replacement class with the same methods but with `__slots__`.

---

## How It Connects

`@dataclass(frozen=True)` generates `__hash__` in addition to `__eq__`, making frozen dataclasses usable in sets and as dict keys. The general rule for `__hash__` and `__eq__` consistency is part of the Python data model.
[[python-data-model|The Python Data Model]]

`@dataclass(slots=True)` eliminates per-instance `__dict__` by generating `__slots__` from the field list. The memory savings and tradeoffs are the same as manually defined `__slots__`.
[[slots|__slots__]]

---

## Common Misconceptions

Misconception 1: "`@dataclass` is a replacement for `__init__` only."
Reality: `@dataclass` generates `__init__`, `__repr__`, and `__eq__` by default. With options, it also generates `__hash__`, `__lt__`/`__le__`/`__gt__`/`__ge__` (for ordering), `__setattr__`/`__delattr__` (for frozen), and `__slots__`. It is a complete boilerplate elimination tool, not just an `__init__` shortcut.

Misconception 2: "Mutable defaults work fine in dataclasses because Python protects you."
Reality: `@dataclass` raises `ValueError` at class definition time if you write `field_name: list = []` — it detects the mutable default and refuses to proceed. The correct form is `field_name: list = field(default_factory=list)`. The `field()` object wraps the factory callable; the generated `__init__` calls it for each new instance.

---

## Why It Matters in Practice

Dataclasses are the default choice for data-holding classes in modern Python. A `User(id, name, email, created_at)` class needs nothing more than `@dataclass` — the generated `__init__`, `__repr__`, and `__eq__` cover all standard uses. `@dataclass(frozen=True)` is the right pattern for value objects (coordinates, configuration entries, cache keys) that should not change after creation — they get `__hash__` for free and behave correctly in sets and dicts.

`__post_init__` is the escape hatch for logic that cannot be expressed as simple field assignments. A `Rectangle` with fields `width` and `height` might validate `width > 0` in `__post_init__`. A `FullName` might compute `self.display = f"{self.first} {self.last}"` as a computed field (marked with `field(init=False)`). `__post_init__` keeps the `__init__` generated while adding custom logic.

---

## Interview Angle

Common question forms:
- "What does `@dataclass` do?"
- "What is `field(default_factory=...)`?"
- "How do you make a dataclass immutable?"

Answer frame: `@dataclass` generates `__init__`, `__repr__`, and `__eq__` from class-level annotations. `field(default_factory=list)` is required for mutable defaults because a shared default list would be a bug — the factory is called once per instance. `@dataclass(frozen=True)` generates `__setattr__` and `__delattr__` that raise on write, making the instance immutable, and also generates `__hash__`. `__post_init__` runs after the generated `__init__` for computed fields and validation.

---

## Related Notes

- [[python-data-model|The Python Data Model]]
- [[slots|__slots__]]
- [[dunder-methods|Dunder Methods]]
- [[type-hints|Type Hints]]
