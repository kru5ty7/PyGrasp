---
title: 07 - Pyright
description: "Pyright is Microsoft's static type checker for Python  -  stricter than mypy in several areas, the engine behind Pylance in VS Code, and configured via pyrightconfig.json with four checking modes."
tags: [pyright, static-type-checking, pylance, type-narrowing, pyrightconfig, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Pyright

> Pyright is a static type checker written in TypeScript that runs on Node.js  -  its TypeScript heritage gives it fast incremental analysis and narrowing rules that differ meaningfully from mypy's.

---

## Quick Reference

**Core idea:**
- Pyright is the engine behind Pylance (VS Code's Python language server)  -  it runs on every keystroke in the editor
- Four checking modes: `off`, `basic`, `standard`, `strict`  -  controlled by `typeCheckingMode` in `pyrightconfig.json`
- Faster incremental checking than mypy  -  uses a persistent language server rather than re-analyzing from scratch
- `# type: ignore` suppresses both mypy and pyright; `# pyright: ignore[reportGeneralTypeIssues]` is pyright-specific
- Pyright uses TypeScript-inspired bidirectional type inference  -  it infers types bottom-up and top-down simultaneously

**Tricky points:**
- Pyright and mypy can disagree on the same code  -  both can be correct given their different inference models
- Pyright narrows both branches of `TypeGuard`-returning functions only with `TypeIs` (3.13+), not with plain `TypeGuard`
- Pyright is stricter about `Optional`  -  it will not accept `None` where `str` is expected even if mypy would
- `pyrightconfig.json` at the project root; `venvPath` and `venv` tell pyright where to find installed stubs
- `reportMissingImports` is separate from `reportMissingModuleSource`  -  the former fails on unresolvable imports, the latter on imports with no type stubs

---

## What It Is

Imagine hiring two separate code reviewers, each with a different background. One trained entirely on Python's own documentation and PEPs  -  meticulous, authoritative on edge cases, occasionally conservative. The other trained on TypeScript's type system  -  faster, stricter about certain patterns, and occasionally more aggressive about flagging things the first reviewer would let slide. Both are trying to help you write correct code; they just bring different intuitions.

Mypy and Pyright are those two reviewers. Both check Python type annotations, both catch the same broad categories of errors, and both implement the Python type system as described in PEPs 484, 526, 544, and friends. But their inference engines make different choices when the specification is ambiguous, and their strictness settings differ in important ways. Pyright's TypeScript heritage means it inherits TypeScript's bidirectional ("contextual") type inference, where the expected type of an expression influences how sub-expressions are typed  -  a model that catches more errors in some patterns while occasionally flagging valid code in others.

For everyday Python development, Pyright's most visible presence is through Pylance, VS Code's Python language server. Every hover-over type annotation, every inline type error squiggle, every auto-complete type hint in VS Code is computed by Pyright running in the background. Understanding Pyright's configuration and error codes is therefore not just academic  -  it is how you tune the feedback loop that runs on every file save.

---

## How It Actually Works

Pyright is a Node.js application that maintains a persistent analysis server. When Pylance starts, it loads and analyzes all Python files in the workspace, building a dependency graph and type information for every symbol. Subsequent edits trigger incremental re-analysis of only the affected files and their dependents  -  in contrast to running `mypy` as a CLI tool, which re-analyzes everything unless its daemon mode (`mypy --daemon`) is used.

Configuration lives in `pyrightconfig.json` at the project root:

```json
{
  "include": ["src"],
  "exclude": ["**/node_modules", "**/__pycache__"],
  "venvPath": ".",
  "venv": ".venv",
  "typeCheckingMode": "standard",
  "reportMissingImports": "error",
  "reportUnusedImport": "warning"
}
```

Pyright resolves type stubs in order: bundled typeshed stubs, stubs from installed packages (`py.typed` marker or stub packages like `pandas-stubs`), and inline annotations in source files. The `typeshedPath` setting overrides the bundled typeshed.

Error suppression has two forms. `# type: ignore` is the PEP 484 standard  -  both mypy and pyright respect it. Pyright-specific suppression uses `# pyright: ignore[errorCode]`, where `errorCode` is the pyright diagnostic rule name (e.g., `reportGeneralTypeIssues`, `reportAttributeAccessIssue`). The advantage of pyright-specific suppression is that it does not silence mypy on the same line and it documents which checker raised the error.

```python
x: str = some_func()  # type: ignore  # silences both mypy and pyright
y: str = some_func()  # pyright: ignore[reportReturnType]  # pyright only
```

---

## How It Connects

Pyright's type narrowing model determines how `isinstance` checks, `TypeGuard`, `TypeIs`, and union narrowing interact. Its model differs from mypy's in several narrowing scenarios  -  particularly around negative narrowing in the `else` branch.

[[type-narrowing|Type Narrowing]]

Pyright checks the same `TypeGuard[T]` annotations as mypy, but was earlier to implement `TypeIs` (PEP 742) from Python 3.13. If you use `TypeGuard` in a codebase checked by both tools, understanding both checkers' behavior is necessary.

[[type-guards|Type Guards]]

The `mypy` note covers a different tool in the same space  -  the original Python type checker. A codebase may run both; they serve as complementary linters with distinct error codes and suppression mechanisms.

[[mypy|mypy]]

---

## Common Misconceptions

Misconception 1: "Pyright and mypy check the same things  -  pick one and they are equivalent."
Reality: Both implement PEP 484, but their inference models diverge on generics, narrowing, and `Protocol` matching. Code that passes mypy can fail pyright and vice versa. Many codebases run both in CI to catch different classes of errors.

Misconception 2: "`# type: ignore` is all you need to suppress a pyright error."
Reality: `# type: ignore` works for pyright but is a blunt instrument  -  it silences all type errors on that line for all checkers. Pyright-specific `# pyright: ignore[errorCode]` suppresses only the named error for only pyright, leaving mypy checks unaffected.

Misconception 3: "Pyright strict mode is the same as mypy strict mode."
Reality: `typeCheckingMode: strict` in pyright enables a different set of rules than `mypy --strict`. The specific set of checks, their severity levels, and what counts as a violation differ. Strict mode in either tool requires explicit opt-in and typically produces many errors in an unannotated codebase.

---

## Why It Matters in Practice

The most immediate practical effect of understanding Pyright is configuring it correctly for your project so that it provides useful signal without excessive noise. A misconfigured `pyrightconfig.json` (wrong `venvPath`, missing `include`) produces hundreds of spurious `reportMissingImports` errors that drown out real ones. Correct configuration means the type errors you see are genuine.

The second practical effect is knowing which suppressions to use. `# type: ignore` in a pyright-strict shop silently suppresses mypy errors on the same line  -  if you only have a pyright problem, use `# pyright: ignore` to preserve mypy checking. Codebases that run both tools in CI benefit from checker-specific suppression comments that document exactly which tool flagged which issue.

---

## Interview Angle

Common question forms:
- "What is the difference between mypy and Pyright?"
- "How do you configure Pyright for a project?"
- "What is Pylance and how does it relate to Pyright?"

Answer frame:
Pyright is Microsoft's TypeScript-based Python type checker, mypy is Python's reference implementation. Both check PEP 484 annotations but differ in inference rules and strictness defaults. Pyright powers Pylance (VS Code), runs as a language server for incremental feedback. Configuration via `pyrightconfig.json` with `typeCheckingMode` from off to strict. They can disagree  -  running both in CI catches more errors.

---

## Related Notes

- [[mypy|mypy]]
- [[type-narrowing|Type Narrowing]]
- [[type-guards|Type Guards]]
- [[type-hints|Type Hints]]
- [[typing-module|typing Module]]
