---
title: Type Hints
description: Type hints are annotations that describe what types a variable, parameter, or return value is expected to hold — they are read by static analysis tools but ignored by CPython at runtime, making them documentation with machine-readable syntax.
tags: [type-hints, annotations, mypy, pyright, static-analysis, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Type Hints

> Type hints are annotations that describe what types a variable, parameter, or return value is expected to hold — they are read by static analysis tools but ignored by CPython at runtime, making them documentation with machine-readable syntax.

---

## Quick Reference

**Core idea:**
- Type hints are **not enforced at runtime** — CPython stores them as metadata and moves on
- Function annotations stored in `fn.__annotations__` (a dict); variable annotations stored in `__annotations__` at module or class level
- The `typing` module provides `List`, `Dict`, `Optional`, `Union`, `Callable`, `TypeVar`, etc. — mostly replaced by built-in generics in Python 3.9+
- Static type checkers (mypy, pyright, Pyrefly) analyze hints **before runtime** — they catch type errors without running the code
- `from __future__ import annotations` defers all annotation evaluation — annotations stored as strings, not evaluated at import time

**Tricky points:**
- `def f(x: int) -> str:` does **not** prevent you from passing a float — CPython never checks this; only a type checker does
- `Optional[X]` is exactly `Union[X, None]` — it does NOT mean "this parameter is optional (has a default)" — those are separate concepts
- `list[int]` (Python 3.9+) and `List[int]` from `typing` are **not** the same object — `list[int]` creates a `GenericAlias`; `List[int]` creates a `_GenericAlias` — both work for type checking but behave differently at runtime
- Using `from __future__ import annotations` means all annotations are lazy strings — `fn.__annotations__` shows `'int'` not `int`; breaks code that reads annotations at runtime (Pydantic, dataclasses with `__post_init__`)

---

## What It Is

Think of a blueprint for a building. The blueprint describes what the building should look like — the dimensions of each room, the placement of walls, the intended materials. But the blueprint itself is not a building. It does not prevent a contractor from using the wrong materials; it just documents what was intended. A building inspector (the type checker) can look at the blueprint and warn you before construction begins if something seems wrong. CPython is the contractor who may or may not follow the blueprint — it runs your code whether the types match or not. Type hints are the blueprint; static type checkers are the inspectors.

Type hints were introduced in Python 3.5 via PEP 484. Before that, Python had no formal annotation syntax for types, though the `# type: int` comment convention was used. The basic syntax uses a colon for variable and parameter annotations and an arrow for return types: `def greet(name: str) -> str:`. These annotations are syntactically part of the language but semantically they carry no meaning to CPython's runtime. They are stored and ignored.

The value of type hints is the ecosystem built around them. Tools like mypy, pyright, and Pyrefly read your source files, examine the type annotations, and flag places where the types do not align — where you pass an `int` where a `str` is expected, or where a function that might return `None` is used without a None check. This analysis happens entirely outside CPython, before your program runs. The result is a class of bugs caught early, without the overhead of runtime type checking on every operation.

---

## How It Actually Works

When CPython compiles a function with type annotations, it evaluates the annotation expressions and stores them in the function's `__annotations__` dictionary. The keys are parameter names (and `"return"` for the return annotation); the values are whatever the annotation expressions evaluated to — usually type objects like `int` or `str`, but they can be anything. CPython then proceeds to compile the function body as if the annotations were not there. No bytecode is generated to check types. No runtime overhead is added.

Variable annotations at module or class scope are handled similarly. An annotated assignment like `x: int = 42` stores `int` in the module or class's `__annotations__` dict under the key `"x"`, and assigns `42` to `x`. An annotated declaration without assignment (`x: int` at module level) only writes to `__annotations__`; it does not create the variable. This matters: after `x: int` at module level, `x` is not defined — referencing `x` raises `NameError`.

`from __future__ import annotations` (PEP 563, available since Python 3.7) changes this behavior: all annotations in the module are stored as their source text as strings rather than being evaluated. `def f(x: int)` stores `"int"` in `__annotations__`, not the `int` type object. This avoids `NameError` for forward references (where an annotation refers to a class not yet defined) and prevents circular import issues caused by annotation evaluation at import time. The tradeoff is that libraries that inspect `__annotations__` at runtime — Pydantic, dataclasses, FastAPI's dependency injection — must handle string annotations explicitly using `typing.get_type_hints()` to resolve them.

---

## How It Connects

Type hints are stored as metadata on Python objects — functions store them in `__annotations__`, which is just a Python dict attribute on the function object. The fact that everything is an object, including functions and types, is what makes this storage natural: annotations are just another attribute of a function object.
[[everything-is-an-object|Everything is an Object]]

Pydantic uses type hints as the core of its data validation system. FastAPI uses them to define request and response shapes. These frameworks work by reading `__annotations__` at runtime and using the type information to validate, coerce, and document data — showing how type hints cross from static analysis into runtime use.
[[pydantic|Pydantic]]

---

## Common Misconceptions

Misconception 1: "Type hints make Python type-safe at runtime."
Reality: CPython ignores type hints entirely during execution. Passing a `list` where `str` is annotated raises no error at runtime. Type safety from hints only exists if you run a static type checker (mypy, pyright) as part of your development or CI process. The hints are documentation with structure; enforcement is opt-in and happens outside CPython.

Misconception 2: "`Optional[str]` means the parameter is optional and has a default value."
Reality: `Optional[str]` is `Union[str, None]` — it means the value can be either a string or `None`. It says nothing about whether the parameter has a default. A function `def f(x: Optional[str])` still requires `x` to be passed; `x` just happens to accept `None` as a valid value. To make a parameter truly optional (with a default), you write `def f(x: Optional[str] = None)` — the default value is separate from the type annotation.

---

## Why It Matters in Practice

Type hints pay dividends in proportion to the size and lifetime of a codebase. In a 50-line script you run once, they add noise for little benefit. In a multi-module project maintained over years with multiple contributors, they serve as machine-checked documentation: every function signature is a contract, and the type checker tells you immediately when code breaks that contract. Refactoring becomes safer — rename a field, change a return type, and the type checker finds every call site that needs to be updated.

Type hints also enable IDE intelligence that goes beyond keyword completion. When a type checker knows that `response` is of type `httpx.Response`, your editor can offer accurate attribute completions, detect attribute access on potentially-`None` values, and warn you about method calls with wrong argument types. This feedback loop shortens the time between writing wrong code and discovering it, without needing to run the program. The key mental shift is treating the type checker as a test suite that runs on every save.

---

## Interview Angle

Common question forms:
- "Are Python type hints enforced at runtime?"
- "What is the difference between `Optional[str]` and a parameter with a default value of `None`?"
- "What does `from __future__ import annotations` do?"

Answer frame: Open with the key fact — hints are stored in `__annotations__` and ignored by CPython at runtime. Explain that enforcement comes from external static checkers. Clarify `Optional` as `Union[X, None]` and separate it from default values. For `from __future__ import annotations`, explain lazy evaluation — annotations stored as strings, not evaluated at import time — and the tradeoff for runtime annotation users like Pydantic.

---

## Related Notes

- [[everything-is-an-object|Everything is an Object]]
- [[pydantic|Pydantic]]
