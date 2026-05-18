---
title: 04 - Relative Imports
description: "Relative imports use leading dots to reference modules relative to the current package  -  `.utils` means \"utils in the same package,\" `..models` means \"models in the parent package\"; they only work inside packages and prevent naming conflicts with absolute imports."
tags: [relative-imports, absolute-imports, packages, import, dotted-names, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Relative Imports

> Relative imports use leading dots to reference modules relative to the current package  -  `.utils` means "utils in the same package," `..models` means "models in the parent package"; they only work inside packages and prevent naming conflicts with absolute imports.

---

## Quick Reference

**Core idea:**
- `from . import utils`  -  imports `utils` from the same package (sibling module)
- `from .utils import helper`  -  imports `helper` from `utils` in the same package
- `from .. import models`  -  imports `models` from the parent package
- `from ..models import User`  -  imports `User` from `models` in the parent package
- One dot = current package; two dots = parent package; three dots = grandparent package

**Tricky points:**
- Relative imports only work inside packages  -  a script run directly (`python mymodule.py`) has `__name__ = "__main__"` and no `__package__`, so relative imports raise `ImportError: attempted relative import with no known parent package`
- Running a module inside a package as a script: use `python -m mypackage.module` instead of `python mypackage/module.py`  -  the `-m` flag sets `__package__` correctly
- Relative imports cannot go above the top-level package  -  `from .... import x` in a module three levels deep tries to go above the root and raises `ImportError`
- PEP 328 made relative imports explicit (require leading dot) in Python 2.5+; in Python 3, all unqualified imports are absolute  -  `import utils` in a package module looks for a top-level `utils`, not a sibling
- `__package__` attribute  -  the package name of the current module; relative imports are resolved using this; set to `None` for top-level scripts

---

## What It Is

Think of relative imports as directions relative to where you are standing. "Go to the room next door" is a relative direction  -  it changes meaning depending on where you are. "Go to 42 Main Street" is absolute. Python's relative imports use the "room next door" style: `from . import utils` means "import `utils` from wherever this module is." If you move the entire package to a different location, the relative imports still work  -  the relationship between modules is preserved.

Absolute imports, by contrast, require the module to be findable from `sys.path`. If you reorganize a package and rename it, every absolute import of its submodules breaks. Relative imports within a package are immune to this because they only care about the internal structure, not the package's location in `sys.path`.

---

## How It Actually Works

Relative imports use `__package__` to resolve the target. For a module at `mypackage/subpkg/module.py`, `__package__` is `"mypackage.subpkg"`. `from . import utils` resolves to `"mypackage.subpkg.utils"`. `from .. import models` resolves to `"mypackage.models"`.

The number of leading dots determines how many levels to ascend:
- `.` = `__package__` (current package)
- `..` = parent of `__package__` (parent package)
- `...` = grandparent package

Python 3 requires explicit relative imports. `import utils` inside a package looks for a top-level `utils` package  -  it does not check the current package first. This change prevents silent import of the wrong module when a top-level module and a sibling module share a name.

`python -m mypackage.module` vs `python mypackage/module.py`:
- `-m` mode: Python sets `__package__ = "mypackage"`, relative imports work
- Direct execution: Python sets `__package__ = None`, relative imports fail

---

## How It Connects

Relative imports only work within packages  -  understanding the package structure is prerequisite.
[[packages|Packages]]

The import system resolves relative imports by combining the relative reference with `__package__` to get the full module name before looking it up.
[[import-system|The Import System]]

---

## Common Misconceptions

Misconception 1: "Relative imports are safer than absolute imports."
Reality: They have different tradeoffs. Relative imports are robust to package renaming (internal structure preserved) but fail when a module is run directly. Absolute imports are explicit and work everywhere but break when the package is renamed. PEP 8 recommends absolute imports for most cases; relative imports are appropriate for package-internal references in libraries.

Misconception 2: "`from . import x` and `from mypackage import x` are always equivalent."
Reality: From inside `mypackage`, yes  -  they resolve to the same module. But if you move the package or rename it, `from . import x` still works (relative, package-internal); `from mypackage import x` breaks (absolute, depends on the package name). Use relative for package-internal cross-module references, absolute for external dependencies.

---

## Why It Matters in Practice

Package-internal imports in library code: `from .database import Session`, `from .models import User`  -  relative imports keep submodules decoupled from the top-level package name. The library can be renamed or nested in another package without changing internal imports.

The `-m` flag is the solution for running package modules as scripts: `python -m pytest`, `python -m http.server`, `python -m mypackage.cli`  -  the `-m` flag initializes `__package__` correctly, enabling relative imports inside those modules.

Confusing error: `ImportError: attempted relative import with no known parent package`  -  this means the module was run directly or is not inside a package. Check: are you running with `python -m`, does the directory have `__init__.py`, is `__package__` set correctly?

---

## Interview Angle

Common question forms:
- "What is the difference between relative and absolute imports?"
- "Why does `from . import utils` fail?"

Answer frame: Relative imports use leading dots to reference modules relative to the current package. `.utils` = same package; `..models` = parent package. They only work inside packages  -  the module must have `__package__` set. Running `python module.py` directly sets `__package__ = None`; use `python -m package.module` instead. Python 3 requires explicit relative imports  -  `import utils` always looks for a top-level module, never a sibling.

---

## Related Notes

- [[packages|Packages]]
- [[import-system|The Import System]]
- [[modules|Modules]]
- [[sys-path|sys.path]]
