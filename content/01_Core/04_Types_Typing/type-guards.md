---
title: 08 - Type Guards
description: "TypeGuard and TypeIs let you write custom type-narrowing functions that tell the type checker how to narrow a union type when your predicate returns True  -  extending isinstance-style narrowing to arbitrary logic."
tags: [type-guards, TypeGuard, TypeIs, type-narrowing, union, isinstance, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Type Guards

> A type guard is a function that returns `bool` but carries a type annotation that tells the type checker "if this returns `True`, then the argument is of this specific type"  -  the mechanism for teaching static checkers your custom narrowing logic.

---

## Quick Reference

**Core idea:**
- `TypeGuard[T]`: annotated return type meaning "if `True`, the argument is `T`"  -  narrows only the positive (True) branch
- `TypeIs[T]` (Python 3.13+, PEP 742): stricter form  -  narrows both `True` branch (to `T`) and `False` branch (to the remainder of the union)
- `isinstance(x, str)` narrows automatically  -  `TypeGuard` / `TypeIs` are for custom predicates the checker cannot see through
- The type guard function must take the value to narrow as its first parameter and return `bool`
- Both `TypeGuard` and `TypeIs` are in `typing` (3.10+ for `TypeGuard`, 3.13+ for `TypeIs`)

**Tricky points:**
- `TypeGuard[T]` does not narrow the `False` branch  -  the type checker treats the argument as still having its original union type after an `if not is_str(x)` check
- `TypeIs[T]` narrows the `False` branch to `X - T` (set subtraction), making it the correct choice when the function truly tests for `T` exclusively
- The function body is NOT analyzed by the type checker for correctness  -  the annotation is trusted; a wrong `TypeGuard` annotation produces incorrect narrowing silently
- `TypeGuard` works on both mypy and pyright; `TypeIs` requires pyright 1.1.x+ or mypy 1.5+
- Type guards are for runtime logic that returns `bool`  -  do not confuse with `cast()` which is a purely static hint with no runtime effect

---

## What It Is

Imagine a customs agent who checks whether a passenger has declared all their goods. The agent applies a custom inspection procedure  -  looking at receipts, asking questions, examining bags. After the inspection, the agent stamps a form: "this passenger is a resident" or "this passenger is a tourist." The airport's record system uses that stamp to apply different rules downstream. The stamp is the agent's declaration; the downstream system trusts it.

`TypeGuard` is that stamp. Python's type checker  -  mypy, pyright, or any conforming tool  -  can narrow types automatically when it sees `isinstance(x, str)` because it knows what `isinstance` does. But when you write `def is_valid_user(obj)` and implement it yourself, the checker has no way to know what narrowing conclusion it should draw when `is_valid_user(x)` returns `True`. Annotating the return type as `TypeGuard[User]` tells the checker: "trust me, if this returns `True`, then `x` is a `User`."

The limitation of `TypeGuard` is that it only narrows the positive branch. If you write `if is_str(x):` with a `TypeGuard[str]`, the type checker knows `x: str` inside the `if` block, but treats `x` as still having its original type in the `else` block. `TypeIs` (Python 3.13+) fixes this by also narrowing the negative branch  -  if `is_str(x)` is `False`, the checker narrows `x` to whatever remains of the union after removing `str`. `TypeIs` is the better choice when the predicate is a true membership test for a specific type.

---

## How It Actually Works

`TypeGuard` is defined in `typing` as a generic alias. At runtime, `TypeGuard[str]` is just an alias for `bool`  -  the annotation has no effect at runtime. The return value of a type guard function is a plain `bool`; it is only the static checkers that interpret the annotation.

```python
from typing import TypeGuard

def is_str(x: object) -> TypeGuard[str]:
    return isinstance(x, str)

def process(x: str | int) -> None:
    if is_str(x):
        # Here, x is narrowed to str
        print(x.upper())    # type checker: OK
    else:
        # Here, x is still str | int  -  TypeGuard does not narrow the else branch
        print(x)            # type checker: str | int
```

`TypeIs` (PEP 742, Python 3.13) imposes an additional constraint: the narrowed type `T` must be a subtype of the original type. This prevents the false narrowing that a `TypeGuard` annotation can accidentally express:

```python
from typing import TypeIs

def is_str(x: str | int) -> TypeIs[str]:
    return isinstance(x, str)

def process(x: str | int) -> None:
    if is_str(x):
        # x: str
        print(x.upper())
    else:
        # x: int   -  TypeIs narrows the else branch too
        print(x + 1)
```

The type checker processes these annotations during static analysis only. At runtime, calling `is_str(42)` returns `False`  -  the annotation changes nothing about the function's behavior. The annotation is purely a communication channel from the developer to the static checker.

---

## How It Connects

Type narrowing is the broader mechanism that `TypeGuard` and `TypeIs` extend. Python type checkers narrow unions automatically for `isinstance`, `is None`, comparison operators, and other built-in patterns  -  `TypeGuard` and `TypeIs` are the hooks for extending this to user-defined predicates.

[[type-narrowing|Type Narrowing]]

Pyright and mypy implement `TypeGuard` and `TypeIs` with slightly different rules  -  particularly around `TypeIs` and negative branch narrowing. Understanding which checker is in use matters when these differences affect real code.

[[pyright|Pyright]]

`TypeGuard` is part of the `typing` module's runtime annotation support. Like `Protocol`, `Literal`, and `Final`, it is a typing construct with no runtime semantics  -  it exists solely to carry information to static analysis tools.

[[typing-module|typing Module]]

---

## Common Misconceptions

Misconception 1: "Using `TypeGuard` makes the runtime behavior safer  -  it adds a type check."
Reality: `TypeGuard` has no runtime effect. It is purely a static annotation. The function body still runs its actual logic. A `TypeGuard[str]` that always returns `True` will not raise an error at runtime even if you pass an `int`  -  it will just mislead the type checker.

Misconception 2: "`TypeGuard` narrows the type in both branches of the `if/else`."
Reality: `TypeGuard` narrows only the `True` branch. In the `else` block, the type checker keeps the original union type. `TypeIs` (3.13+) narrows both branches.

Misconception 3: "You need `TypeGuard` to narrow `isinstance` checks."
Reality: Type checkers understand `isinstance` natively  -  `if isinstance(x, str): ...` narrows `x` to `str` in the `if` block automatically. `TypeGuard` is only needed for custom predicates that the checker cannot introspect.

---

## Why It Matters in Practice

`TypeGuard` becomes necessary whenever you have a helper function that validates or filters objects from a union type and you want downstream code to benefit from the narrowed type. A common pattern is a validator function: `def is_valid_config(obj: object) -> TypeGuard[Config]` that checks structure and field types. Without the `TypeGuard` annotation, every caller must re-check or use `cast()`. With it, the narrowing flows naturally.

The `TypeIs` form is superior for predicates that truly test for a specific type because it also eliminates the narrowed type from union branches where the test fails. This reduces the number of `assert` statements or additional `isinstance` checks that would otherwise be needed in the negative branch.

---

## Interview Angle

Common question forms:
- "What is `TypeGuard` and when would you use it?"
- "What is the difference between `TypeGuard` and `TypeIs`?"
- "How does a type checker narrow types through an `isinstance` check vs a custom function?"

Answer frame:
Type checkers understand `isinstance` and `is None` natively. `TypeGuard[T]` is the annotation for custom predicates  -  it tells the checker that a `True` return means the first argument is `T`. The limitation is it only narrows the positive branch. `TypeIs` (3.13+) also narrows the negative branch, making it correct for true type membership tests. Both have zero runtime effect.

---

## Related Notes

- [[type-narrowing|Type Narrowing]]
- [[pyright|Pyright]]
- [[mypy|mypy]]
- [[typing-module|typing Module]]
- [[type-hints|Type Hints]]
