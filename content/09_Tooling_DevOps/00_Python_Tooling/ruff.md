---
title: 03 - Ruff
description: "Ruff is a Rust-based Python linter and formatter that replaces Flake8, isort, pyupgrade, and dozens of plugins with a single tool that runs 10–100x faster by operating on Python ASTs without spawning subprocess chains."
tags: [ruff, linter, formatter, ast, rust, flake8-replacement, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Ruff

> Ruff is a Rust-based Python linter and formatter — it consolidates Flake8, isort, pyupgrade, and over 700 lint rules into a single binary that analyzes Python code at the AST level and runs in milliseconds instead of seconds.

---

## Quick Reference

**Core idea:**
- `ruff check .` — lint the current directory; exit code non-zero if violations found
- `ruff check --fix .` — auto-fix all safely fixable violations in place
- `ruff format .` — format code (Black-compatible output)
- Configuration lives in `pyproject.toml` under `[tool.ruff]` or in `ruff.toml`
- Rules are selected by code prefix: `E` (pycodestyle errors), `F` (Pyflakes), `I` (isort), `UP` (pyupgrade), etc.
- `ruff check --select ALL .` — enables all rules (useful for exploring; usually too strict for daily use)

**Tricky points:**
- Ruff's formatter and Black produce identical output in almost all cases — they can coexist or Ruff can replace Black entirely
- `ruff check` and `ruff format` are separate commands — running one does not trigger the other
- Rule codes are organized by plugin prefix: `E`/`W` = pycodestyle, `F` = Pyflakes, `I` = isort, `N` = pep8-naming, `UP` = pyupgrade, `B` = flake8-bugbear, `C90` = mccabe complexity
- The `--fix` flag only applies safe fixes by default; `--unsafe-fixes` enables fixes that could theoretically change behavior
- Ruff respects `# noqa: E501` inline suppression comments compatible with Flake8

---

## What It Is

Think of Ruff as a code quality scanner that reads your Python source files, converts them to abstract syntax trees, and checks every node in those trees against a library of rules — all in a single Rust process, without spawning Python subprocesses. The traditional Python linting workflow involved at least three separate tools: Flake8 (style and error checking), isort (import ordering), and pyupgrade (modernizing syntax). Each tool ran as a separate Python process, loaded its own plugins, and applied its rules independently. For a medium-sized codebase with thousands of files, this could take 30 seconds in CI.

Ruff was created by Astral (the same team as uv) with the observation that all of these tools do essentially the same thing — parse Python source into an AST, traverse the tree, and emit diagnostics. By reimplementing the rules in Rust and sharing a single parse pass, Ruff can run the equivalent of all those tools simultaneously, on all files in parallel, in the time it would take Flake8 alone to start up.

The practical effect is that linting becomes fast enough to run on every keystroke in an editor extension, on every `git commit` in a pre-commit hook, and on every push in CI — without any of those contexts feeling slow. When linting has no perceptible cost, developers stop disabling it or working around it. The tool changes behavior simply by being fast.

---

## How It Actually Works

Ruff parses each Python file into a concrete syntax tree using a Rust parser (`ruff_python_parser`, based on the `rustpython-parser` project), then walks the tree applying all selected rules in a single traversal. Each rule is a visitor that pattern-matches on specific node types — for example, the `F401` rule (unused import) checks `ImportFrom` and `Import` nodes against the set of names referenced elsewhere in the module. Because all rules share the same parse pass and the same AST, there is no redundant work.

Configuration in `pyproject.toml`:

```toml
[tool.ruff]
line-length = 88
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B"]
ignore = ["E501"]  # line too long — handled by formatter

[tool.ruff.lint.isort]
known-first-party = ["myapp"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
```

The `--fix` flag writes safe auto-corrections back to disk. A "safe fix" is one that the Ruff authors have determined cannot change program semantics — removing an unused import, sorting imports, updating `Optional[X]` to `X | None` for Python 3.10+ targets. An "unsafe fix" is one that could theoretically change behavior — for example, removing a `__all__` entry for an unused name that might be imported by other modules.

Ruff's formatter is not a wrapper around Black. It is an independent implementation of the same formatting algorithm (the "Black-compatible" formatter), written in Rust. It produces output identical to Black on the vast majority of real-world Python code. The rare differences are in edge cases involving trailing commas and certain magic trailing comma behaviors.

---

## How It Connects

Ruff replaces isort for import ordering — understanding what isort's rules are (stdlib, third-party, local sections) clarifies what the `I` rule prefix in Ruff is enforcing.

[[isort|isort]]

Pre-commit hooks are the most common deployment mechanism for Ruff — the `ruff` hook in `.pre-commit-config.yaml` runs on every staged file before each commit.

[[pre-commit|Pre-commit Hooks]]

Black is the formatter that Ruff's formatter is designed to be compatible with — if a project uses Black, switching to `ruff format` should produce identical output.

[[black|Black]]

---

## Common Misconceptions

Misconception 1: "Ruff is just a faster Flake8."
Reality: Ruff reimplements rules from Flake8 but also reimplements isort, pyupgrade, flake8-bugbear, flake8-comprehensions, and dozens of other plugins. It also includes a formatter (replacing Black). It is not a Flake8 wrapper — it is an independent implementation of the same rules, written in Rust, with a unified configuration system.

Misconception 2: "I need to keep Flake8 and isort because Ruff might miss some rules."
Reality: Ruff implements over 700 rules covering all major Flake8 plugins. For most projects, Ruff alone is sufficient. If a specific obscure Flake8 plugin is required (some domain-specific ones exist), it might not yet be in Ruff — check the Ruff documentation for coverage. The Ruff team actively adds rules from community requests.

Misconception 3: "`ruff format` and `ruff check --fix` do the same thing."
Reality: `ruff format` applies style formatting (whitespace, quotes, line length, trailing commas) — the same things Black does. `ruff check --fix` applies lint auto-corrections (removing unused imports, modernizing deprecated syntax, sorting imports). They operate on different aspects of the code and are designed to be run together.

---

## Why It Matters in Practice

In a pre-commit hook, Ruff running on a 100-file diff takes under 100 milliseconds. The equivalent Flake8 + isort + pyupgrade pipeline takes 3–8 seconds. For developers committing frequently, this difference is felt on every single commit. Fast feedback from tooling changes developer behavior — when the tool is fast, developers fix issues immediately rather than batching them or suppressing them.

In a CI pipeline, replacing a three-tool lint stage with a single `ruff check .` command also simplifies configuration significantly. There is one tool to version, one configuration section in `pyproject.toml`, and one command to run. Configuration drift between `setup.cfg` (Flake8) and `pyproject.toml` (Black) — a common source of conflicts — is eliminated.

---

## Interview Angle

Common question forms:
- "What linting tools do you use in a Python project?"
- "How would you set up code quality enforcement in a new Python project?"

Answer frame:
A strong answer names Ruff as the primary tool, explains that it consolidates Flake8, isort, and other plugins, mentions the rule selection system (E, F, I, UP), and describes where it is enforced: pre-commit hooks locally, and a `ruff check` step in CI. Mentioning that `ruff format` replaces Black shows awareness of the full formatter capability.

---

## Related Notes

- [[black|Black]]
- [[isort|isort]]
- [[pre-commit|Pre-commit Hooks]]
- [[pyproject-toml|pyproject.toml]]
- [[poetry|Poetry]]
