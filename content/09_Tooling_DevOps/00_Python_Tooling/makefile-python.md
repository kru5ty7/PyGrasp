---
title: 07 - Makefiles for Python Projects
description: "A Makefile in a Python project defines named targets like `test`, `lint`, and `format` that sequence tool invocations, giving every contributor a single consistent interface to project operations without memorizing the full command for each tool."
tags: [makefile, make, automation, developer-workflow, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Makefiles for Python Projects

> A Makefile is a recipe file that defines named targets — `make test`, `make lint`, `make format` — which sequence the exact commands needed for each project task, providing a self-documenting, consistent interface that works the same for every developer and every CI system.

---

## Quick Reference

**Core idea:**
- `make test` — runs the test suite with the correct flags (defined in `Makefile`)
- `make lint` — runs all linters in sequence
- `make format` — applies formatters in place
- `make clean` — removes build artifacts, `__pycache__`, `.pyc` files
- `.PHONY: test lint format clean` — declares targets that are not actual filenames
- Targets can depend on other targets: `make ci: lint test` runs lint then test

**Tricky points:**
- Makefile recipes must be indented with a **tab**, not spaces — this is the most common beginner error and produces an obscure error: `Makefile:N: *** missing separator. Stop.`
- `.PHONY` is required for targets that do not produce output files — without it, `make test` might skip running if a file named `test` happens to exist in the directory
- Each line in a Makefile recipe runs in its own subshell — `cd subdir && command` is necessary to change directory within a recipe
- Variables in Makefiles use `$(VAR)` syntax — `$VAR` expands only the first character, a common mistake from shell scripting
- `make` uses the first target in the file as the default when called with no arguments — conventionally `help` or `all`

---

## What It Is

A Makefile is a build automation file originally designed for C compilation workflows, where `make` would determine which source files had changed and recompile only what was necessary. Python projects do not need incremental compilation, but they inherit the Makefile pattern for a different reason: it gives every contributor a single, consistent interface to all project operations.

Without a Makefile, a new contributor must read documentation (if it exists) or ask colleagues: "How do I run the tests? Do I need to activate the virtual environment first? Which pytest flags do you use? How do I run the linter?" With a Makefile, the answer to all of these questions is: look at the Makefile and run the target. The Makefile serves as executable documentation — it shows not just what commands to run, but their exact flags and the correct order.

The appeal for Python projects is not Make's dependency tracking (which Python projects rarely need), but Make's interface: a short, memorable name for a potentially complex sequence of commands. `make lint` might internally run `ruff check .`, then `mypy src/`, then `ruff format --check .` — three separate commands with different flags. With a Makefile target, a developer types two words and gets all three checks, in the right order, with the right configuration.

---

## How It Actually Works

A Makefile consists of rules in the form `target: prerequisites` followed by indented recipe lines:

```makefile
.PHONY: install test lint format clean ci

# Install all dependencies (development mode)
install:
	uv sync --all-groups

# Run the test suite with coverage
test:
	uv run pytest tests/ -v --cov=src --cov-report=term-missing

# Run all linters
lint:
	uv run ruff check .
	uv run mypy src/

# Apply formatters in place
format:
	uv run ruff format .
	uv run ruff check --fix .

# Remove build artifacts
clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -name "*.pyc" -delete
	rm -rf .pytest_cache .ruff_cache dist/ build/ *.egg-info

# Full CI check: lint then test
ci: lint test

# Self-documenting help target
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
```

The `.PHONY` declaration tells Make that these target names do not correspond to files. Without `.PHONY`, if a file named `test` existed in the project root, `make test` would see the file as up-to-date and do nothing — a silent failure. Declaring targets as phony ensures the recipe always runs.

The `@` prefix before a command suppresses printing the command itself before executing it. Without `@`, `make help` would print `grep -E '^...` before showing the help output. The `@` keeps the output clean.

Make variables allow configuration without duplicating values:

```makefile
PYTHON := uv run python
TEST_DIR := tests/
SRC_DIR := src/

test:
	$(PYTHON) -m pytest $(TEST_DIR) -v --cov=$(SRC_DIR)
```

The tab indentation requirement is a notorious gotcha. Make was designed in 1976 and the tab requirement is a historical artifact. Many editors silently convert tabs to spaces, which breaks Makefiles. The error message `*** missing separator` means a recipe line used spaces where a tab was required. Configure your editor to preserve tabs in Makefiles.

---

## How It Connects

The commands in a Makefile's `lint` target typically invoke Ruff — the Makefile orchestrates the tools without replacing them.

[[ruff|Ruff]]

CI pipelines frequently call Makefile targets rather than duplicating command sequences in the YAML workflow file — `make ci` in GitHub Actions runs the same checks as `make ci` locally.

[[ci-testing-pipeline|CI Testing Pipeline]]

The `install` target typically calls uv or Poetry commands — the Makefile is the interface, the package manager is the implementation.

[[uv|uv]]

---

## Common Misconceptions

Misconception 1: "Makefiles are for C projects, not Python."
Reality: Make is a general-purpose task runner. Python projects use Makefiles for the same reason C projects do: to define a consistent, self-documenting interface to common operations. The dependency tracking and incremental compilation features of Make are not needed for Python, but the `make target-name` interface is universally useful.

Misconception 2: "I can use spaces to indent Makefile recipes."
Reality: Makefile recipes must be indented with a tab character (ASCII 0x09), not spaces. This is a hard requirement from Make's original 1976 syntax and has never changed. Most modern editors can be configured to preserve tabs in files named `Makefile`. The error `missing separator` is the diagnostic for space-indented recipes.

Misconception 3: "Each line in a recipe runs in the same shell session, so I can set variables or change directory at the start."
Reality: Each line in a recipe runs in a new subshell. `export VAR=value` on one line does not affect the next line. `cd subdir` on one line does not affect the next line. To run multiple commands in the same shell context, chain them with `&&` on a single line: `cd subdir && make test`.

---

## Why It Matters in Practice

Onboarding time for a new developer on a project with a well-written Makefile is dramatically shorter. The `make help` target (if implemented) displays all available targets with descriptions. A new team member can run `make install` to set up dependencies, `make test` to run tests, `make lint` to check code quality — without reading documentation for each individual tool.

In CI, calling `make ci` or `make lint && make test` in the workflow YAML means the CI definition is short and readable, and local developer commands mirror CI commands exactly. There is no drift between "what CI runs" and "what I run locally" — they call the same Makefile target.

---

## Interview Angle

Common question forms:
- "How do you standardize development commands across a team?"
- "How do you structure automation for a Python project?"

Answer frame:
Describe the Makefile as a project interface: `make install`, `make test`, `make lint`, `make format`. Explain `.PHONY` (prevents file collision), tab indentation (historical requirement), and the pattern of calling tool commands from Makefile targets. Mention that Makefiles mirror CI commands, reducing "works locally but fails in CI" problems.

---

## Related Notes

- [[ruff|Ruff]]
- [[pre-commit|Pre-commit Hooks]]
- [[uv|uv]]
- [[ci-testing-pipeline|CI Testing Pipeline]]
- [[pytest|Pytest]]
