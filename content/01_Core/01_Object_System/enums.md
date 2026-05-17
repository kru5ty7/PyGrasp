---
title: 15 - Enums
description: "Python's `enum.Enum` creates named constants that are instances of the enum class — they have identity, comparison semantics, and iteration, preventing the \"magic string/integer\" anti-pattern while providing type-checker-visible named values."
tags: [enum, Enum, IntEnum, Flag, named-constants, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Enums

> Python's `enum.Enum` creates named constants that are instances of the enum class — they have identity, comparison semantics, and iteration, preventing the "magic string/integer" anti-pattern while providing type-checker-visible named values.

---

## Quick Reference

**Core idea:**
- `class Color(Enum): RED = 1; GREEN = 2` creates an enum where `Color.RED` is a `Color` instance with `.name = "RED"` and `.value = 1`
- Enum members are singletons — `Color.RED is Color.RED` is always `True`
- `Enum` equality uses identity: `Color.RED == Color.RED` is `True`; `Color.RED == 1` is `False` (even though the value is 1)
- `IntEnum` members compare equal to integers: `Color.RED == 1` is `True` — useful for legacy code expecting integers
- `list(Color)` iterates over all members in definition order
- `Color(1)` looks up a member by value; `Color["RED"]` looks up by name — both return `Color.RED`

**Tricky points:**
- Enum members with the same value are treated as **aliases** — the second member is an alias for the first; `list(Color)` does not include aliases
- `@unique` decorator raises `ValueError` if any two members share the same value
- `auto()` generates values automatically — defaults to incrementing integers starting at 1 (not 0)
- `Flag` and `IntFlag` support bitwise operations — `Permission.READ | Permission.WRITE` creates a combined Flag value
- Enum class bodies are not regular class bodies — you cannot define arbitrary attributes inside without making them enum members; use `_ignore_` or put them in methods

---

## What It Is

Think of a traffic light. The light can only ever be in one of three states: red, yellow, or green. Representing this as integers (0, 1, 2) or strings ("red", "yellow", "green") invites bugs: typos in strings, wrong integer values, no enforcement of the valid set. An enum is the formal version of "only these specific values are valid." It names the values, makes them a type, and lets the language enforce that only members of the set can be used.

Before `enum`, Python code used module-level constants: `STATUS_PENDING = 0`, `STATUS_ACTIVE = 1`, `STATUS_CLOSED = 2`. These constants had no shared type — any integer could be passed where `STATUS_*` was expected. Functions accepting a status had no way to enforce the valid range. Enums solve this: `Status.PENDING`, `Status.ACTIVE`, and `Status.CLOSED` are instances of `Status`, and a function typed `def handle(status: Status)` can only receive `Status` instances — not arbitrary integers.

The key property of an enum member is that it is a **singleton instance** of its class. `Color.RED` is always the same object. Comparing with `is` is valid and faster than `==`. The name and value are attributes of the instance: `Color.RED.name == "RED"`, `Color.RED.value == 1`. This makes enums introspectable — you can always ask a member what it is called and what its underlying value is.

---

## How It Actually Works

`enum.EnumMeta` is the metaclass for all `Enum` classes. When a class body with enum members is processed, `EnumMeta.__new__` intercepts the class creation and converts each name-value pair in the body into an `Enum` instance stored as a class attribute.

The generated enum class is also a mapping: `Color._member_map_` is an `OrderedDict` of `{"RED": Color.RED, "GREEN": Color.GREEN, ...}`. `Color(1)` calls `EnumMeta.__call__`, which looks up the value in `Color._value2member_map_`. `Color["RED"]` is `Color._member_map_["RED"]`.

Aliases are detected during class creation: if two members share the same value, the second name maps to the first member object. `list(Color)` uses `Color._member_names_` which excludes aliases.

`auto()` is a descriptor in the enum class body. `EnumMeta` detects `auto()` values and calls `Enum._generate_next_value_(name, start, count, last_values)` to produce the actual value. The default implementation returns `max(last_values) + 1` (starting at 1). Subclasses can override `_generate_next_value_` to use a different scheme — e.g., uppercase string values.

`Flag` extends `Enum` to support bitwise composition. `Permission.READ | Permission.WRITE` returns a new `Permission` member whose value is the bitwise OR of the two values. Iterating a combined flag yields the constituent single-bit members.

---

## How It Connects

Enums are often used alongside type hints — a function parameter annotated `status: Status` is verifiable by mypy, which knows only `Status` members are valid values. This is one of the key practical benefits of enums over plain integer constants.
[[type-hints|Type Hints]]

`EnumMeta` is a custom metaclass — it intercepts class creation and transforms the class body into a set of singleton instances. The mechanics of how `EnumMeta.__new__` processes the class body are the same metaclass machinery described in the metaclasses and class creation notes.
[[metaclasses|Metaclasses]]

---

## Common Misconceptions

Misconception 1: "`Enum` values compare equal to their underlying integers."
Reality: Plain `Enum` members do **not** compare equal to integers — `Color.RED == 1` is `False`. Enum uses identity-based equality: `Color.RED == Color.RED` is `True`. Use `IntEnum` if you need integer comparison (`IntEnum` members inherit from both `int` and `Enum`, so `Color.RED == 1` is `True`). The tradeoff: `IntEnum` members can be passed anywhere an integer is expected, losing the type safety benefit of regular `Enum`.

Misconception 2: "Duplicate values create separate enum members."
Reality: Duplicate values create **aliases** — the second name points to the same object as the first. `Status.CLOSED = 2` and `Status.DONE = 2` means `Status.DONE is Status.CLOSED` is `True`. `list(Status)` includes only `CLOSED` (the first), not `DONE`. Use `@unique` to raise an error if any duplicate values exist.

---

## Why It Matters in Practice

Enums prevent the "magic value" pattern that makes code hard to read and maintain. A function that takes `order_status: int` and checks `if status == 3` is opaque — 3 means nothing without the constant definition. `if status == OrderStatus.SHIPPED` is self-documenting and type-checkable.

`IntEnum` is the migration path for codebases that use integer constants everywhere. `class Status(IntEnum): PENDING = 0; ACTIVE = 1` lets you replace `STATUS_PENDING` with `Status.PENDING` while maintaining backward compatibility with code that compares to integers.

`Flag` is the correct representation for bitmask permissions or options. `Permission.READ | Permission.WRITE | Permission.EXECUTE` is readable, composable, and iterable — you can ask `Permission.READ in combined` to test membership.

---

## Interview Angle

Common question forms:
- "What is a Python enum and when would you use it?"
- "What is `IntEnum`?"
- "How do you iterate over enum members?"

Answer frame: `Enum` creates named singleton constants that are instances of the enum class. Members have `.name` and `.value` attributes. `Color(1)` looks up by value; `Color["RED"]` looks up by name; `list(Color)` gives all non-alias members. `IntEnum` members compare equal to integers — useful for legacy integer-based code. `@unique` prevents duplicate values. `auto()` generates sequential values. `Flag` supports bitwise OR for combined values. The primary benefit over module constants: type safety, introspection, and no magic numbers.

---

## Related Notes

- [[type-hints|Type Hints]]
- [[metaclasses|Metaclasses]]
- [[python-data-model|The Python Data Model]]
- [[dunder-methods|Dunder Methods]]
