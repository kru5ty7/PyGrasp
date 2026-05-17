---
title: Type Narrowing
description: Type narrowing is how static type checkers refine the type of a variable within a conditional branch — `isinstance` checks, `None` checks, `assert`, and `TypeGuard` all signal to mypy/pyright that a broader type can be treated as a narrower, more specific type in that branch.
tags: [type-narrowing, isinstance, TypeGuard, mypy, pyright, Union, type-guards, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Type Narrowing

> Type narrowing is how static type checkers refine the type of a variable within a conditional branch — `isinstance` checks, `None` checks, `assert`, and `TypeGuard` all signal to mypy/pyright that a broader type can be treated as a narrower, more specific type in that branch.

---

## Quick Reference

**Core idea:**
- After `if isinstance(x, int):`, the type checker knows `x` is `int` in the `if` block
- After `if x is None:`, the type checker knows `x` is `None` in the `if` block, and `not None` (narrowed) in the `else`
- After `assert isinstance(x, str)`, the type checker narrows `x` to `str` for the rest of the function
- `typing.TypeGuard[T]` (Python 3.10+) annotates a function that acts as a type narrowing predicate
- `match` statement patterns (Python 3.10+) narrow types within their cases

**Tricky points:**
- Narrowing is not transitive through function calls — `def check(x): return isinstance(x, int)` does not narrow `x` at the call site; only `isinstance` directly in the conditional narrows; use `TypeGuard` for user-defined narrowing functions
- `Union[str, int]` is not automatically narrowed by string methods — `x.upper()` on `Union[str, int]` is a type error even if `str` has `upper`; narrow first: `if isinstance(x, str): x.upper()`
- The `else` branch narrows by subtraction: if `x: Union[str, int, None]` and `if isinstance(x, str):` is checked, the `else` branch knows `x: Union[int, None]`
- Assignment also resets narrowing: if `x: Optional[str]` is narrowed to `str` in a branch but then assigned `x = maybe_none()`, the type is broadened again
- `TypeGuard` is asymmetric — it only narrows when the guard returns `True`; the `else` branch is **not** narrowed to the complement

---

## What It Is

Think of a package arriving at a sorting facility. The package is initially labeled "unknown contents." When a scanner detects it is a fragile item, the handlers in that area treat it as fragile — they know the specific properties and handle it accordingly. Other areas where the scan hasn't been performed still treat it as unknown. Type narrowing is that scanning: after an `isinstance` check, the type checker knows the specific type within that scanned region (the conditional branch) and can verify that operations on the value are appropriate for that type.

Without narrowing, working with `Union` types is awkward. If `x: Union[str, int]`, calling `x.upper()` is a type error — the type checker cannot know whether `x` is a `str` in every code path. The `isinstance(x, str)` check narrows `x` to `str` in the `if` block, unlocking `str`-specific operations. In the `else` block, `x` is narrowed to `int` by subtraction.

This is one of the key features that makes Python's gradual typing system usable — you can write `Union` types that are broad at the boundary, then narrow them at the points where specific types are actually needed.

---

## How It Actually Works

Type checkers maintain a type state for each variable at each program point. The state starts at the declared type. When a conditional check is encountered, the checker forks the state for the `if` and `else` branches.

Narrowing conditions recognized by mypy and pyright:
- `isinstance(x, T)` — narrows `x` to `T` in the `if` branch
- `x is None` / `x is not None` — narrows out `None`
- `x is SomeClass` — narrows to the specific class
- `type(x) is T` — narrows to `T` (strict equality, not subclass)
- Truthiness checks on `Optional[T]` — truthy branch narrows out `None`
- `assert isinstance(x, T)` — narrows for the rest of the function scope
- `match` patterns — each case narrows to the matched type

`typing.TypeGuard[T]`:

```python
from typing import TypeGuard

def is_str_list(lst: list[object]) -> TypeGuard[list[str]]:
    return all(isinstance(item, str) for item in lst)

def process(items: list[object]) -> None:
    if is_str_list(items):
        items[0].upper()  # narrowed: items is list[str]
```

`TypeGuard` tells the type checker: when this function returns `True`, the argument satisfies the narrower type. The `else` branch is not narrowed (the function returning `False` does not guarantee the complement).

---

## How It Connects

`Union` and `Optional` types are the primary reason narrowing is needed — they express that a value can be one of several types, and narrowing resolves which one applies in a given branch.
[[typing-module|The typing Module]]

mypy is the primary tool that implements these narrowing rules. Understanding what mypy recognizes as narrowing conditions is essential for writing mypy-compatible code.
[[mypy|mypy]]

---

## Common Misconceptions

Misconception 1: "Calling a function that does `isinstance` inside it narrows the type at the call site."
Reality: Only direct `isinstance` (or other recognized forms) in the conditional expression narrows the type. A helper function `def is_str(x): return isinstance(x, str)` does not narrow `x` at `if is_str(x):` — the type checker cannot see inside the helper. Use `TypeGuard[str]` on the return type of the helper to explicitly mark it as a narrowing function.

Misconception 2: "After `isinstance(x, str)` narrows `x`, the entire function knows `x` is `str`."
Reality: Narrowing is **branch-local**. After the `if` block, the narrowing no longer applies. If the `if` block contains `return` or `raise`, the type checker may infer that all remaining code has `x` narrowed (this is called "control flow narrowing via early return"), but otherwise narrowing ends at the `if` block boundary.

---

## Why It Matters in Practice

`Optional[str]` narrowing is the most common case. A function receiving `Optional[str]` checks `if x is not None:` and then uses `x` as a `str`. The type checker knows `x` is `str` in that branch — no `cast()` needed.

Exhaustive pattern matching on `Union` types uses narrowing to verify all cases are handled. If `x: Union[str, int, None]` and you check each case with `isinstance`/`is None`, mypy can verify that all possible types are handled and the code after the chain is unreachable (or the final branch handles `Never`).

`TypeGuard` is essential for complex validation functions in library code: a function that validates a dict has specific keys can be annotated to narrow `dict[str, Any]` to `TypedDict`.

---

## Interview Angle

Common question forms:
- "What is type narrowing in Python?"
- "How does mypy know the type after an `isinstance` check?"

Answer frame: Type narrowing is how type checkers refine a variable's type within a conditional branch. After `isinstance(x, str)`, the checker knows `x` is `str` in the `if` block. The `else` branch narrows by subtraction. Common narrowing forms: `isinstance`, `is None`, `assert`. `TypeGuard[T]` annotates user-defined narrowing predicates. Narrowing is branch-local and does not transfer through function calls unless `TypeGuard` is used.

---

## Related Notes

- [[typing-module|The typing Module]]
- [[mypy|mypy]]
- [[type-hints|Type Hints]]
- [[runtime-vs-static-typing|Runtime vs Static Typing]]
