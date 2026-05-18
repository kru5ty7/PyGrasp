---
title: 02 - Packages
description: "A Python package is a directory containing an `__init__.py` file  -  importing the package executes `__init__.py`; sub-packages and modules inside can be accessed with dotted names; namespace packages (PEP 420) allow packages without `__init__.py` spread across multiple directories."
tags: [packages, __init__.py, subpackages, namespace-packages, import, dotted-names, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Packages

> A Python package is a directory containing an `__init__.py` file  -  importing the package executes `__init__.py`; sub-packages and modules inside can be accessed with dotted names; namespace packages (PEP 420) allow packages without `__init__.py` spread across multiple directories.

---

## Quick Reference

**Core idea:**
- `mypackage/` with `__init__.py` inside is a package; `import mypackage` executes `__init__.py`
- `mypackage/utils.py` is accessible as `mypackage.utils`  -  `import mypackage.utils` or `from mypackage import utils`
- `__init__.py` can be empty, or can import submodules and define the public API (`__all__`)
- Dotted name `import a.b.c` imports `a`, then `a.b`, then `a.b.c`  -  all three are executed (if not cached)
- **Namespace packages** (Python 3.3+): a directory without `__init__.py` can still be a package; used for splitting a package across multiple directories (e.g., multiple distributions contributing to one namespace)

**Tricky points:**
- `import mypackage` does NOT automatically import submodules  -  `mypackage.utils` is not available unless `__init__.py` imports it or the caller does `import mypackage.utils` explicitly
- `from mypackage import utils` executes `mypackage/__init__.py` and then accesses the `utils` attribute  -  if `utils` is a submodule not yet imported, Python imports it
- `__init__.py` is the package's public face  -  it controls what `from mypackage import *` provides (via `__all__`) and which submodules are exposed as top-level attributes
- Circular imports within a package (module A imports module B which imports module A)  -  the partially initialized module is used; restructure or use deferred imports inside functions
- `__path__` attribute: a package has `__path__` (a list of directories); for regular packages it contains one path; for namespace packages it contains all contributing directories

---

## What It Is

Think of a package as a library building. The building (the directory) houses multiple rooms (modules). The lobby (`__init__.py`) controls what visitors see when they enter  -  it can display everything or curate a selection. The building's address (the package name) provides a namespace that prevents room naming conflicts with other buildings. "John's office" in Building A does not conflict with "John's office" in Building B.

Without packages, a large Python project would be a flat collection of module files  -  naming conflicts between modules would be unavoidable, and organizing code into logical groups would be impossible. Packages provide hierarchical namespacing: `myapp.database.models` is clearly distinct from `otherlib.database.models`.

`__init__.py` is the package's initialization code. An empty `__init__.py` just marks the directory as a package. A non-empty `__init__.py` can re-export submodule contents, set up package-level state, or define the public API.

---

## How It Actually Works

`import mypackage.utils`:
1. Check `sys.modules["mypackage"]`  -  if missing, find and execute `mypackage/__init__.py`, add to cache
2. Check `sys.modules["mypackage.utils"]`  -  if missing, find and execute `mypackage/utils.py`, add to cache
3. Set `mypackage.utils` attribute on the `mypackage` module object
4. In the current namespace, bind `mypackage` (not `mypackage.utils`)  -  access `mypackage.utils` via the attribute

`from mypackage.utils import fn`  -  the same loading happens, but only `fn` is bound in the current namespace.

`__init__.py` best practices:
- Import submodule public APIs for a flat access pattern: `from .utils import helper` lets callers use `from mypackage import helper` instead of `from mypackage.utils import helper`
- Set `__all__ = ["helper", "Client"]` to control `from mypackage import *`
- Avoid heavy computations  -  `__init__.py` runs on every import of the package

Namespace packages: Python 3.3+ allows a directory without `__init__.py` to be a package. This enables "split namespace packages" where `myorg.projectA` and `myorg.projectB` are in different directories but share the `myorg` namespace. The `myorg` directory in each location has no `__init__.py`; Python merges them via `__path__` containing both directories.

---

## How It Connects

Relative imports use the package structure  -  `from .utils import fn` means "from the utils module in the same package as this module." They only work inside packages.
[[relative-imports|Relative Imports]]

The import system handles discovering and loading packages  -  `sys.path` tells Python where to look for top-level packages.
[[import-system|The Import System]]

---

## Common Misconceptions

Misconception 1: "Importing a package automatically imports all its submodules."
Reality: `import mypackage` only executes `__init__.py`. Submodules like `mypackage.utils` are not imported unless `__init__.py` imports them or the caller imports them explicitly. `mypackage.utils.fn()` after `import mypackage` raises `AttributeError` unless `utils` was imported.

Misconception 2: "An empty `__init__.py` is useless."
Reality: An empty `__init__.py` serves two purposes: it marks the directory as a regular package (allowing dotted imports) and establishes a namespace. Without it (in Python 3.3+), the directory is treated as a namespace package with different import semantics. Many projects use empty `__init__.py` to be explicit about regular package semantics.

---

## Why It Matters in Practice

Library organization: `mylib/` contains `__init__.py` that exports the public API; implementation lives in submodules (`mylib/_core.py`, `mylib/_utils.py`). Callers use `from mylib import Client` without knowing which submodule `Client` is defined in. Reorganizing internals does not break the public API.

`__init__.py` as API aggregator: `from .models import User, Product` and `from .services import UserService` in `__init__.py` lets callers write `from myapp import User, UserService`  -  a flat import path regardless of the internal structure.

Namespace packages are used by large organizations to split a namespace across multiple packages: `google-cloud-storage` and `google-cloud-bigquery` both contribute to the `google.cloud` namespace without a shared `__init__.py`.

---

## Interview Angle

Common question forms:
- "What is a Python package?"
- "What is `__init__.py`?"

Answer frame: A package is a directory with `__init__.py`. Importing the package executes `__init__.py`. Submodules are accessed with dotted names (`mypackage.utils`) but must be imported explicitly unless `__init__.py` imports them. `__all__` in `__init__.py` controls `from package import *`. Namespace packages (Python 3.3+) work without `__init__.py` and allow a package to span multiple directories.

---

## Related Notes

- [[modules|Modules]]
- [[relative-imports|Relative Imports]]
- [[import-system|The Import System]]
- [[sys-path|sys.path]]
