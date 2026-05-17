---
title: Modules
description: A Python module is any `.py` file — `import` executes the file and caches the resulting module object in `sys.modules`; subsequent imports return the cached object; modules have their own namespace (`__dict__`), `__name__`, `__file__`, and `__spec__` attributes.
tags: [modules, import, sys.modules, namespace, __name__, module-attributes, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Modules

> A Python module is any `.py` file — `import` executes the file and caches the resulting module object in `sys.modules`; subsequent imports return the cached object; modules have their own namespace (`__dict__`), `__name__`, `__file__`, and `__spec__` attributes.

---

## Quick Reference

**Core idea:**
- `import module_name` — finds, executes, and caches the module; returns the module object
- `from module import name` — imports the module and binds `name` from its namespace into the current namespace
- Module objects are cached in `sys.modules` keyed by their fully qualified name — `import x` twice is only one execution
- Module attributes: `__name__` (fully qualified name, or `"__main__"` if run directly), `__file__` (path to the `.py` file), `__dict__` (the module's namespace)
- `if __name__ == "__main__":` — code that runs only when the file is executed directly, not when imported

**Tricky points:**
- Modifying a module's object is visible everywhere that object is referenced — `import mymodule; mymodule.x = 99` changes `x` for all importers of `mymodule`
- `from module import name` creates a local binding — later changes to `module.name` do NOT affect the local binding; `import module` + `module.name` always sees the current value
- Circular imports: if A imports B and B imports A, the partially initialized module is used — can cause `ImportError: cannot import name 'X'` if `X` is not yet defined when the circular import resolves; fix by moving imports inside functions or restructuring
- `importlib.reload(module)` re-executes the module code — the module object is updated in-place, but existing references to objects from the old module are not updated
- `__all__` in a module controls what `from module import *` imports — without `__all__`, all public names (not starting with `_`) are imported

---

## What It Is

Think of a module as a toolbox. Each toolbox (`math`, `os`, `json`) is a self-contained collection of tools (functions, classes, constants). When you `import math`, Python opens the toolbox once and caches it. Subsequent `import math` calls hand you the same cached toolbox — the toolbox is not re-opened. This is why modules are objects: they have an identity, attributes, and live in memory once loaded.

The `if __name__ == "__main__":` pattern is the "run directly vs imported" distinction. When Python executes a file directly (`python myfile.py`), `__name__` is `"__main__"`. When another file imports it, `__name__` is the module's dotted name. This lets a file serve as both a standalone script and an importable module.

---

## How It Actually Works

`import x` follows these steps (simplified):
1. Check `sys.modules["x"]` — if present, return it
2. Find the module using `sys.meta_path` finders (file system, zip imports, etc.)
3. Create a new module object and add it to `sys.modules["x"]` (before executing, to handle circular imports)
4. Execute the module's code in the module object's `__dict__` namespace
5. Return the module object

Step 3 (adding to `sys.modules` before executing) is why circular imports can partially work — module A is in `sys.modules` by the time module B tries to import it, but only with the names defined so far.

`from module import name`:
1. Performs a full `import module` (steps above)
2. Accesses `module.name`
3. Binds the resulting object to `name` in the current namespace

The local binding is a snapshot — it points to the object that `module.name` referred to at import time. If `module.name` is later reassigned, the local `name` still points to the original object.

---

## How It Connects

The import system — finders, loaders, `sys.meta_path`, `sys.path` — is the machinery that `import` calls into. Modules are the output of that machinery.
[[import-system|The Import System]]

Packages extend the module concept to directories — a package is a directory with an `__init__.py` that can contain multiple modules.
[[packages|Packages]]

---

## Common Misconceptions

Misconception 1: "`import x` re-executes the module code on every import."
Reality: The first import executes the code and caches the result in `sys.modules`. Every subsequent `import x` returns the cached module object without re-executing. This is why global state in a module is shared across all importers.

Misconception 2: "`from module import name` keeps in sync with changes to `module.name`."
Reality: `from module import func` binds `func` to the same object `module.func` pointed to at import time. If `module.func = new_function` is executed later, the local `func` still points to the original. Use `import module` and access `module.func` to always get the current value.

---

## Why It Matters in Practice

`if __name__ == "__main__":` is essential for scripts that also provide importable functionality. Entry point logic (argument parsing, calling main functions) goes in this block; everything else (class definitions, utility functions) is importable.

Mutable module-level state: `import config; config.debug = True` affects all code that subsequently accesses `config.debug`. This can be useful (shared config) or dangerous (hidden global state). Modules are effectively singleton objects.

`importlib.reload` is useful in interactive development (Jupyter, REPL) where you want to pick up changes to a module without restarting. It does not work reliably for classes already instantiated from the old module.

---

## Interview Angle

Common question forms:
- "What happens when you `import` a module?"
- "What is `if __name__ == '__main__':`?"
- "What is `sys.modules`?"

Answer frame: `import x` checks `sys.modules` for a cached module, finds it (or loads it), executes the code once, and caches the result. Subsequent imports return the cache. `from module import name` binds the name locally — not synchronized with later changes to `module.name`. `__name__ == "__main__"` is `True` only when the file is run directly, not when imported. `sys.modules` is the cache — `del sys.modules["x"]` followed by `import x` re-executes the module.

---

## Related Notes

- [[import-system|The Import System]]
- [[packages|Packages]]
- [[sys-path|sys.path]]
- [[namespaces-and-scopes|Namespaces and Scopes]]
