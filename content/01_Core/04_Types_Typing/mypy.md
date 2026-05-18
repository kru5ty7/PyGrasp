---
title: 06 - mypy
description: "mypy is Python's de-facto static type checker  -  it analyzes type annotations without running code, catches type mismatches, verifies `Optional` are handled, and can be configured from permissive to strict; understanding its common errors and configuration options is essential for typed Python codebases."
tags: [mypy, static-type-checker, type-checking, pyright, strict-mode, type-errors, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# mypy

> mypy is Python's de-facto static type checker  -  it analyzes type annotations without running code, catches type mismatches, verifies `Optional` are handled, and can be configured from permissive to strict; understanding its common errors and configuration options is essential for typed Python codebases.

---

## Quick Reference

**Core idea:**
- `mypy file.py`  -  checks a single file; `mypy src/`  -  checks a directory; `mypy --strict src/`  -  enables all strict checks
- Common mypy errors:
  - `error: Argument 1 to "f" has incompatible type "str"; expected "int"`  -  type mismatch
  - `error: Item "None" of "Optional[str]" has no attribute "upper"`  -  unhandled `None`
  - `error: Missing return statement`  -  function is annotated to return non-None but has no `return`
  - `error: Need type annotation for "x"` (with `--strict`)  -  unannotated variable
- `# type: ignore`  -  suppresses mypy errors on a line; `# type: ignore[error-code]` targets specific errors
- `reveal_type(x)`  -  not a real function; mypy outputs the inferred type of `x` when it encounters this

**Tricky points:**
- mypy does not check unannotated functions by default  -  add `--disallow-untyped-defs` to require all functions to be annotated
- `Any` is contagious  -  passing an `Any` value into typed code suppresses type errors for that value; operations on `Any` return `Any`
- Third-party library stubs: if a library has no type annotations, mypy treats it as returning `Any` unless type stubs (`.pyi` files) are available via `types-*` packages (e.g., `types-requests`)
- `--ignore-missing-imports` silences errors for untyped libraries; necessary in many real projects until stubs are available
- pyright (Microsoft) is an alternative with faster analysis, stricter rules by default, and better VS Code integration; most code is compatible with both

---

## What It Is

Think of mypy as a proof-reader for types. A proof-reader does not run the document  -  they read it and flag inconsistencies. "You said this function returns a string, but here you return an integer." "You said this parameter accepts a User, but here you pass a string." mypy reads your code's type annotations and verifies that all uses are consistent with them, without executing a single line.

The value is catching errors before they become runtime exceptions. A `None` dereference in production  -  `obj.name` when `obj` is `None`  -  shows up as `error: Item "None" of "Optional[User]" has no attribute "name"` in mypy output, caught at review time. A mismatched argument type  -  passing a `list[str]` where `list[int]` is required  -  is flagged before the function even runs.

mypy implements Python's gradual typing model: unannotated code is `Any` (compatible with everything). You can add annotations incrementally and run mypy only on the annotated parts. Over time, as more code is annotated, mypy catches more errors.

---

## How It Actually Works

mypy performs a multi-phase analysis:
1. **Parsing**: reads source files and third-party stubs (`.pyi` files)
2. **Symbol resolution**: builds a symbol table mapping names to types
3. **Type inference**: infers types for unannotated variables using assignment context
4. **Type checking**: verifies all operations are consistent with inferred/annotated types

For each function call, mypy checks that argument types match parameter annotations and that the return type matches the declared return. For attribute access, it verifies the attribute exists on the inferred type. For `Union` types, it verifies all branches are handled or narrowed.

**Configuration** via `mypy.ini` or `pyproject.toml`:

```ini
[mypy]
python_version = 3.11
strict = True
ignore_missing_imports = True

[mypy.tests.*]
disallow_untyped_defs = False
```

**Key strict-mode flags**:
- `--disallow-untyped-defs`  -  all functions must have annotations
- `--no-implicit-optional`  -  `def f(x: str = None)` is an error (must be `Optional[str]`)
- `--warn-return-any`  -  warn when returning `Any` from an annotated function
- `--strict-equality`  -  `str == int` is always False, flag it

`reveal_type(x)` is a special mypy directive that outputs the inferred type without affecting runtime:

```python
x = [1, 2, 3]
reveal_type(x)  # note: Revealed type is "list[int]"
```

---

## How It Connects

mypy enforces the static side of Python's gradual typing system. The annotations written using `typing` module constructs are what mypy checks.
[[runtime-vs-static-typing|Runtime vs Static Typing]]

Type narrowing  -  `isinstance` checks, `None` guards  -  are what allow mypy to verify that `Optional` types are safely used. Without narrowing, accessing attributes on `Optional[T]` is always a mypy error.
[[type-narrowing|Type Narrowing]]

---

## Common Misconceptions

Misconception 1: "mypy is too strict for real-world code."
Reality: mypy's default mode is permissive  -  unannotated code is silently treated as `Any`. Strict mode can be enabled incrementally. The practical approach: start with basic annotations on public interfaces, fix errors, then gradually enable stricter flags. Most large Python codebases (Google, Dropbox, Instagram) run mypy in CI.

Misconception 2: "If mypy passes, the code is correct."
Reality: mypy only checks types  -  logic errors, runtime exceptions from valid types (division by zero, index out of range), and edge cases are not caught. mypy is a tool for one class of errors (type mismatches), not a replacement for tests.

---

## Why It Matters in Practice

mypy in CI prevents a class of runtime errors from reaching production. The most common catches: `None` dereferences (`Optional` not checked), wrong argument type passed to a library function, function return type inconsistency.

`reveal_type` is a debugging tool for complex inference situations  -  when mypy reports an unexpected type error, `reveal_type` on the problematic variable shows what mypy actually inferred, which usually explains the error.

Third-party stubs: `pip install types-requests` installs stubs for the `requests` library, enabling mypy to check `requests` API usage. Many popular libraries now ship inline type annotations (no separate stubs needed).

---

## Interview Angle

Common question forms:
- "What is mypy and why would you use it?"
- "What is `reveal_type`?"
- "What does `# type: ignore` do?"

Answer frame: mypy is a static type checker  -  it analyzes type annotations without running code and flags type mismatches. Key errors: argument type mismatch, unhandled `None` in `Optional`, missing return. `reveal_type(x)` outputs mypy's inferred type for `x`. `# type: ignore` suppresses mypy errors on a line. Configuration in `mypy.ini`: `strict` mode requires full annotations; `ignore_missing_imports` handles untyped third-party libraries. mypy works alongside tests  -  it catches type errors; tests catch logic errors.

---

## Related Notes

- [[runtime-vs-static-typing|Runtime vs Static Typing]]
- [[type-narrowing|Type Narrowing]]
- [[typing-module|The typing Module]]
- [[type-hints|Type Hints]]
