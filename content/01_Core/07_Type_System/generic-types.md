---
title: 03 - Generic Types
description: "Generic types parameterize a class or function by one or more type variables, allowing a single implementation to work correctly with multiple concrete types while preserving type information — `list[int]`, `dict[str, int]`, and user-defined `class Stack(Generic[T])` are all generic types."
tags: [generics, TypeVar, Generic, type-parameters, parametric-polymorphism, python-3.12, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Generic Types

> Generic types parameterize a class or function by one or more type variables, allowing a single implementation to work correctly with multiple concrete types while preserving type information — `list[int]`, `dict[str, int]`, and user-defined `class Stack(Generic[T])` are all generic types.

---

## Quick Reference

**Core idea:**
- `T = TypeVar("T")` — creates a type variable; conventionally named `T`, `S`, `K`, `V`
- `def first(lst: list[T]) -> T` — a generic function: T is inferred from the argument type, and the return type matches
- `class Stack(Generic[T])` — a generic class parameterized by T; `Stack[int]` is a concrete parameterization
- Python 3.12+ syntax: `def first[T](lst: list[T]) -> T` — new `[T]` syntax replaces `TypeVar`
- `__class_getitem__` — the dunder called by `list[int]` at runtime; returns a `_GenericAlias`

**Tricky points:**
- `TypeVar` constraints vs bounds: `T = TypeVar("T", int, str)` means T is exactly `int` or `str`; `T = TypeVar("T", bound=Number)` means T is `Number` or any subclass; constraints restrict to specific types, bounds allow the subtype hierarchy
- Generic type erasure at runtime: `list[int]` at runtime is just `list` — `isinstance(x, list[int])` raises `TypeError`; use `isinstance(x, list)` and check element types separately
- A TypeVar that appears only in the return type (not the arguments) is **unbound** at call time — type checkers warn and default to `Any`
- `covariant=True` / `contravariant=True` on TypeVar affects subtyping: `list[Dog]` is not a `list[Animal]` (invariant by default), but a `Sequence[Dog]` can be a `Sequence[Animal]` if `T` is covariant
- `ParamSpec` (Python 3.10+) captures the full parameter spec of a callable for use in decorator type signatures

---

## What It Is

Think of a shipping container specification. "A container holds cargo" is generic — it applies to any cargo type. "A refrigerated container holds frozen fish" is concrete — the type of cargo is specified. In Python, `list` is like "a container holds items" — generic. `list[int]` is like "a container holds integers" — concrete. The type annotation `list[int]` tells the type checker that this list should only contain integers, and operations on elements should be treated as integer operations.

Generic types solve the tension between reuse and type safety. A `first(lst)` function that returns the first element of a list should work for `list[int]`, `list[str]`, and `list[User]`. Without generics, you would either write separate `first_int`, `first_str`, `first_user` functions, or annotate the return type as `Any` (losing type information). With generics: `def first(lst: list[T]) -> T` — one implementation, type-checked correctly for every list element type.

---

## How It Actually Works

`T = TypeVar("T")` creates a `TypeVar` object. When a type checker sees `def first(lst: list[T]) -> T`, it notes that `T` is used in both the parameter and return type. When `first([1, 2, 3])` is called, the checker infers `T = int` and concludes the return type is `int`. If `first(["a", "b"])` is called, `T = str`.

At runtime, `list[int]` calls `list.__class_getitem__(int)`, which returns a `_GenericAlias` object — a lightweight wrapper that remembers `list` and `int`. This alias is not a type itself at runtime: `isinstance([], list[int])` raises `TypeError`. The alias is used for type checker introspection and `typing.get_args()`.

A generic class:

```python
from typing import Generic, TypeVar

T = TypeVar("T")

class Stack(Generic[T]):
    def __init__(self) -> None:
        self._items: list[T] = []
    def push(self, item: T) -> None:
        self._items.append(item)
    def pop(self) -> T:
        return self._items.pop()
```

`Stack[int]()` creates a `Stack` instance annotated for integers. The type checker enforces that `push` only accepts ints and `pop` returns an int.

Python 3.12 introduced the `[T]` syntax as a cleaner alternative:

```python
class Stack[T]:
    def push(self, item: T) -> None: ...
    def pop(self) -> T: ...
```

---

## How It Connects

The `typing` module provides `TypeVar`, `Generic`, and the runtime aliases. Understanding the full typing vocabulary is prerequisite to using generics effectively.
[[typing-module|The typing Module]]

Variance (covariant, contravariant, invariant) determines how generic types relate under subtyping. `Sequence[T]` in `typing` uses a covariant TypeVar, which is why `Sequence[Dog]` is a subtype of `Sequence[Animal]` but `list[Dog]` is not a subtype of `list[Animal]`.
[[protocols|Protocols and Structural Subtyping]]

---

## Common Misconceptions

Misconception 1: "`list[int]` enforces that the list only contains integers at runtime."
Reality: `list[int]` is purely an annotation — no runtime enforcement. `x: list[int] = [1, "two", 3]` stores a mixed list without error. The annotation is checked statically by mypy/pyright, not enforced by CPython. Use `isinstance` checks or validation libraries (Pydantic) for runtime enforcement.

Misconception 2: "A generic `T` in a return type is the same as `Any`."
Reality: `T` in a return type that is also in a parameter type is inferred from the argument. `def identity(x: T) -> T` — the type checker knows the return type matches the input type, which is more precise than `Any`. `Any` opts out of type checking entirely; a TypeVar preserves the relationship between types.

---

## Why It Matters in Practice

Generic functions are essential for utility code. A `find_first(items: list[T], pred: Callable[[T], bool]) -> Optional[T]` function works for any list type and returns the correct element type. Without `TypeVar`, the return type would be `Any`, losing the type information.

The standard library's `collections.abc` uses generics heavily. `Iterable[int]`, `Iterator[str]`, `Mapping[str, int]` — all generic. Understanding that these are parameterized types helps when reading type errors involving them.

`ParamSpec` enables typing decorators that preserve the wrapped function's signature. Without `ParamSpec`, a decorator's return type must be `Callable[..., T]` — the `...` means "unknown parameters." With `ParamSpec`, the exact parameter types flow through.

---

## Interview Angle

Common question forms:
- "What is a TypeVar in Python?"
- "What does `Generic[T]` mean?"
- "What is the difference between `TypeVar` bounds and constraints?"

Answer frame: `TypeVar("T")` creates a type variable for generic functions and classes. In `def first(lst: list[T]) -> T`, `T` is inferred from the argument type and the return type matches. Generic classes inherit from `Generic[T]`. Bounds (`bound=Number`) allow `T` to be any subtype of `Number`. Constraints (`T`, `int`, `str`) restrict `T` to exactly those types. At runtime, `list[int]` is a lightweight alias — no runtime enforcement of element types.

---

## Related Notes

- [[typing-module|The typing Module]]
- [[protocols|Protocols and Structural Subtyping]]
- [[type-hints|Type Hints]]
- [[mypy|mypy]]
