---
title: 05 - isort
description: "isort is a Python utility that automatically sorts import statements into three sections  -  standard library, third-party packages, and local modules  -  separated by blank lines, with alphabetical ordering within each section."
tags: [isort, imports, code-style, pep8, import-ordering, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# isort

> isort automatically organizes Python import statements into PEP 8-compliant sections  -  standard library, third-party, and local  -  separated by blank lines, and alphabetizes within each section, turning chaotic import blocks into structured, readable ones.

---

## Quick Reference

**Core idea:**
- `isort .`  -  sort imports in all Python files in place
- `isort --check-only .`  -  check without modifying; exit non-zero if any file would change
- `isort --diff .`  -  show what would change without modifying files
- Three sections: STDLIB -> THIRDPARTY -> FIRSTPARTY (local), each separated by a blank line
- `profile = "black"`  -  adjusts isort's output to match Black's expectations and avoid conflicts
- `known_first_party = ["myapp"]`  -  tells isort which packages are local (not auto-detectable)

**Tricky points:**
- isort and Black can produce conflicting results if run in the wrong order or without `profile = "black"`  -  isort may format an import block that Black then reformats differently
- isort detects third-party packages by checking if they are installed in the current virtual environment  -  packages not installed may be misclassified as local
- `STDLIB_LIST` is a hardcoded list of standard library module names  -  isort ships this list and updates it between versions
- `--force-sort-within-sections` changes sorting behavior within sections; the default is alphabetical by top-level module name
- In projects using Ruff, isort can be replaced entirely by Ruff's `I` rules with `select = ["I"]` in `pyproject.toml`

---

## What It Is

Import sections in Python files accumulate disorder over time. A module starts with a few clean imports, and over weeks of development, imports from different sources  -  standard library modules, installed packages, local application code  -  get interspersed, duplicated, and left in the order they happened to be added. This makes the import block harder to read and makes it difficult to quickly answer the question "what external packages does this module depend on?"

isort addresses this with a simple, well-defined rule: imports belong in three sections. The first section contains standard library imports (`os`, `sys`, `json`, `typing`). The second section contains third-party packages installed from PyPI (`requests`, `fastapi`, `sqlalchemy`). The third section contains imports from the project itself (`from myapp.models import User`). Each section is separated by a blank line, and within each section, imports are sorted alphabetically. This is the structure PEP 8 recommends, but humans rarely maintain it manually with any consistency.

The practical impact is that the import section of a file becomes informative at a glance. A reader can immediately see what the file's external dependencies are (the third-party section), what standard library features it uses, and what internal modules it touches. When combined with a pre-commit hook, this ordering is enforced automatically, so the import section never accumulates disorder in the first place.

---

## How It Actually Works

isort parses Python files using Python's `tokenize` module to identify import statements, then sorts them according to its section classification algorithm. The classification works by checking each module name against three data sources: a hardcoded list of known standard library modules (updated per Python version), the set of installed packages in the active virtual environment, and any explicitly configured `known_first_party` or `known_third_party` settings.

Configuration in `pyproject.toml`:

```toml
[tool.isort]
profile = "black"
known_first_party = ["myapp", "tests"]
line_length = 88
```

The `profile = "black"` setting adjusts several isort defaults to be compatible with Black's formatting rules. Without it, isort might sort imports in a way that Black then reformats, creating an endless loop where running both tools in sequence never reaches a stable state. With `profile = "black"`, the two tools' outputs are compatible  -  their fixed points are the same. The most important change the profile makes is setting `multi_line_output = 3` (hanging grid grouped) and `include_trailing_comma = True`, which matches Black's treatment of multi-line imports.

A typical sorted import block:

```python
# Standard library (section 1)
import os
import sys
from pathlib import Path
from typing import Optional

# Third-party packages (section 2)
import httpx
from fastapi import FastAPI, HTTPException
from sqlalchemy.orm import Session

# Local / first-party (section 3)
from myapp.config import settings
from myapp.models import User
```

When isort cannot determine whether a package is standard library or third-party  -  because it is not installed in the current virtual environment  -  it defaults to treating it as third-party. This is usually correct for CI environments where all dependencies are installed, but can produce unexpected results during local development when only a subset of packages is installed.

---

## How It Connects

The `profile = "black"` setting exists precisely because Black and isort can conflict  -  understanding Black's formatting model clarifies why the profile is necessary.

[[black|Black]]

Ruff implements isort's functionality in its `I` rule set  -  in a Ruff-based project, isort is typically replaced by `ruff check --select I --fix`, removing the need for a separate tool.

[[ruff|Ruff]]

isort is commonly run as a pre-commit hook  -  the `.pre-commit-config.yaml` entry for isort specifies the same configuration as `pyproject.toml` through hook arguments.

[[pre-commit|Pre-commit Hooks]]

---

## Common Misconceptions

Misconception 1: "isort and Black conflict, so I should only use one of them."
Reality: They solve different problems and are designed to coexist. Black handles all formatting except import ordering. isort handles import ordering. The conflict arises only when isort is used without `profile = "black"`. With the profile set, running both tools in sequence always reaches a stable, consistent state. Alternatively, Ruff can replace both.

Misconception 2: "isort knows automatically which packages are mine and which are third-party."
Reality: isort detects third-party packages by checking the active virtual environment's installed packages. If a local package has an unusual name that looks like a third-party package, or if the environment does not have all dependencies installed, isort can misclassify imports. Always configure `known_first_party` explicitly for local packages to ensure correct classification.

Misconception 3: "Import ordering is a cosmetic concern with no real impact."
Reality: Consistent import ordering prevents merge conflicts. When two developers add imports to the same file, if both follow the same ordering rule, their changes are more likely to appear in different lines and not conflict. It also enables grepping: `grep -n "^from fastapi" *.py` reliably identifies all FastAPI imports when they are consistently placed in the third-party section.

---

## Why It Matters in Practice

The maintenance value of sorted imports becomes apparent when inheriting a large codebase. In a consistently sorted codebase, you can quickly audit what external dependencies each module has, find where a specific library is used by grepping the import section, and identify circular import risks by seeing which local modules each file imports. In an unsorted codebase, this analysis requires reading and parsing the full import block.

For new projects, adding isort (or Ruff's `I` rules) from the start costs almost nothing and prevents import disorder from ever accumulating. Retrofitting isort onto an existing large codebase produces a large one-time diff that touches every file  -  worth doing, but plan for it to temporarily disrupt open pull requests due to merge conflicts.

---

## Interview Angle

Common question forms:
- "How do you organize imports in a Python project?"
- "What does isort do and why would you use it?"

Answer frame:
Describe the three-section structure (stdlib, third-party, local), explain that isort automates this, and mention `profile = "black"` for compatibility with Black. Note that in Ruff-based projects, isort is replaced by Ruff's `I` rules  -  this shows awareness of the modern toolchain.

---

## Related Notes

- [[black|Black]]
- [[ruff|Ruff]]
- [[pre-commit|Pre-commit Hooks]]
- [[pyproject-toml|pyproject.toml]]
