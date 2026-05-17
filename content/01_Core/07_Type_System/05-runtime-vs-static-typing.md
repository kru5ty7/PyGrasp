---
title: 05 - Runtime vs Static Typing
description: "Python's type annotations are ignored at runtime by default — static type checkers (mypy, pyright) analyze them without executing code; runtime type enforcement requires explicit validation via `isinstance`, Pydantic, or similar libraries; understanding this distinction prevents the common mistake of assuming annotations validate data."
tags: [runtime-typing, static-typing, annotations, mypy, pydantic, gradual-typing, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Runtime vs Static Typing

> Python's type annotations are ignored at runtime by default — static type checkers (mypy, pyright) analyze them without executing code; runtime type enforcement requires explicit validation via `isinstance`, Pydantic, or similar libraries; understanding this distinction prevents the common mistake of assuming annotations validate data.

---

## Quick Reference

**Core idea:**
- **Static typing**: type annotations are analyzed before running the program; type errors are caught without executing any code
- **Runtime typing**: type checks occur when the program runs; wrong types raise exceptions at runtime
- Python annotations are **decorative by default** — they are stored in `__annotations__` but not enforced; calling `f(x: int)` with a string does not raise at runtime
- `isinstance(x, int)` is a runtime check — it raises or branches based on the actual type of `x`
- **Gradual typing**: Python supports mixing annotated and unannotated code; `Any` is the escape hatch

**Tricky points:**
- `from __future__ import annotations` makes all annotations strings (lazy) — useful for forward references and performance, but breaks code that inspects annotations at runtime (e.g., `dataclass`, Pydantic use `typing.get_type_hints()` to evaluate them)
- Pydantic and `@dataclass` **do** enforce types at runtime (via `__init__` validation or `get_type_hints`), unlike bare annotations
- `typing.get_type_hints(fn)` resolves string annotations to actual types — used by frameworks to do runtime introspection of annotations
- `cast(T, x)` is a static typing hint only — at runtime it is a no-op, just returns `x`; it tells the type checker to treat `x` as `T` without any actual conversion
- Python's type system is **gradual**: unannotated code is implicitly typed as `Any`, which is compatible with everything; you can add types incrementally

---

## What It Is

Think of two kinds of proof-reading. Static typing is like an editor reading a manuscript before publication — they flag errors (type mismatches) without the manuscript ever being "run." Runtime typing is like a reader encountering an incomprehensible sentence mid-reading — the error is detected only when that part is executed. Python's annotations are editor notes — they exist in the text, a good editor (mypy) can check them, but the printer (CPython) ignores them.

This distinction matters because Python's annotations are stored as metadata but not enforced. `def f(x: int) -> str: return x * 2` — mypy flags the return type mismatch (returns `int`, not `str`), but CPython runs it without complaint and returns an `int`. The annotation is there for the editor, not the printer.

Runtime validation requires code that actually checks types: `isinstance`, assertion, or a framework that processes annotations and generates validation code. Pydantic does exactly this — it reads the annotations of a model class and generates `__init__` code that validates and coerces input values.

---

## How It Actually Works

Annotations are stored in `fn.__annotations__` (for functions) and `cls.__annotations__` (for classes). They are evaluated at function/class definition time (unless `from __future__ import annotations` is used, in which case they are stored as strings).

CPython's `CALL` bytecode does not consult `__annotations__` — there is no checking step. The annotations are purely decorative from CPython's perspective.

Static type checkers (mypy, pyright) work differently: they parse the AST of your source files, resolve imports, and build a type graph. They then check that all type-annotated uses are consistent — function calls, attribute access, assignments. This is a separate analysis pass, not execution.

`typing.get_type_hints(obj, globalns=None, localns=None)` evaluates string annotations in the proper namespace, resolving forward references. Frameworks use this to implement runtime annotation introspection:

```python
# Pydantic-style (simplified)
import typing

class Model:
    name: str
    age: int

hints = typing.get_type_hints(Model)
# {'name': <class 'str'>, 'age': <class 'int'>}
# Pydantic generates __init__ that validates against these types
```

`Any` is the gradual typing escape hatch. A value of type `Any` is compatible with every type — it can be passed anywhere. Unannotated functions are implicitly `(*Any) -> Any`. This is why annotated code can interoperate with unannotated code.

---

## How It Connects

mypy is the most widely used static type checker — it implements the static analysis step that Python itself does not perform.
[[mypy|mypy]]

Type narrowing is the technique type checkers use to refine `Union` and `Optional` types within conditional branches — a static analysis feature with no runtime equivalent.
[[type-narrowing|Type Narrowing]]

---

## Common Misconceptions

Misconception 1: "Type annotations validate data at runtime."
Reality: Python's built-in annotation syntax does nothing at runtime. `def f(x: int): ...` accepts any value for `x` at runtime. Validation requires explicit runtime code: `isinstance`, `assert`, or a validation framework. Pydantic's models are the common tool for runtime-validated data models.

Misconception 2: "`cast(int, x)` converts `x` to `int` at runtime."
Reality: `typing.cast(T, x)` is a static typing hint with **no runtime effect**. It returns `x` unchanged. It tells the type checker "treat `x` as `T` here," but no conversion, coercion, or validation occurs. For actual conversion, use `int(x)`.

---

## Why It Matters in Practice

The boundary between static and runtime typing determines where bugs are caught. A statically typed codebase catches type mismatches before deployment. A dynamically typed runtime catches them when that code path is executed — which may be in production, on an edge case, or in a test.

Gradual typing strategy: start with unannotated code (all `Any`), add annotations to public interfaces first, then internal functions. mypy's `--strict` flag escalates to requiring full annotations.

For data validation (API inputs, config parsing), runtime validation is essential — you cannot trust that external data matches your types. Pydantic, `attrs` with validators, and `@dataclass` with `__post_init__` validation are the standard tools.

---

## Interview Angle

Common question forms:
- "Are Python type annotations enforced at runtime?"
- "What is the difference between static and runtime typing?"

Answer frame: Python annotations are stored in `__annotations__` but ignored by CPython at runtime — no validation occurs. Static type checkers (mypy, pyright) analyze annotations without running code and flag type errors. Runtime type enforcement requires explicit `isinstance` checks or validation frameworks like Pydantic. `cast(T, x)` is a static hint with no runtime effect. Gradual typing: unannotated code is `Any` (compatible with everything); annotations can be added incrementally.

---

## Related Notes

- [[mypy|mypy]]
- [[type-narrowing|Type Narrowing]]
- [[typing-module|The typing Module]]
- [[type-hints|Type Hints]]
