---
title: 07 - pip and Packaging
description: "pip is Python's package installer — `pip install`, `pip freeze`, and `pip show` manage packages from PyPI; `pyproject.toml` is the modern standard for project metadata and build configuration; understanding the packaging ecosystem is needed to distribute and consume Python libraries."
tags: [pip, packaging, pyproject-toml, PyPI, setuptools, wheel, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# pip and Packaging

> pip is Python's package installer — `pip install`, `pip freeze`, and `pip show` manage packages from PyPI; `pyproject.toml` is the modern standard for project metadata and build configuration; understanding the packaging ecosystem is needed to distribute and consume Python libraries.

---

## Quick Reference

**Core idea:**
- `pip install package` — downloads and installs from PyPI into the current Python environment
- `pip install package==1.2.3` — installs a specific version; `>=1.0,<2.0` — version range
- `pip install -e .` — editable install: installs the current directory as a package with a `.pth` file so changes are immediately visible
- `pip freeze` — lists installed packages with exact versions (suitable for `requirements.txt`)
- `pyproject.toml` — the modern standard for project metadata (`[project]` section) and build system configuration (`[build-system]` section)
- `python -m build` — creates distribution packages (`sdist` and `wheel`) for upload to PyPI

**Tricky points:**
- `pip install` without an active virtual environment installs globally — always activate a venv first
- `pip install --upgrade package` upgrades to the latest version; pip does not auto-upgrade dependencies unless `--upgrade-deps` is specified
- `pip install -r requirements.txt` installs a list of packages; `pip freeze > requirements.txt` creates this list with exact pinned versions
- `setup.py` and `setup.cfg` are the legacy packaging formats; `pyproject.toml` is the current standard (PEP 517/518/621)
- Wheels (`.whl`) are pre-built binary distributions; `sdist` (`.tar.gz`) is the source distribution; pip prefers wheels for speed

---

## What It Is

Think of pip and PyPI as an app store for Python libraries. PyPI (Python Package Index) is the store — a public registry of hundreds of thousands of Python packages. pip is the installer app. When you `pip install requests`, pip fetches the `requests` package from PyPI and installs it into your Python environment.

Packaging is the other direction: you write a library, describe it in `pyproject.toml` (metadata: name, version, dependencies, entry points), build it into a distributable format, and upload it to PyPI. Other developers then `pip install` your package.

The packaging ecosystem evolved from `setup.py` (legacy, executable setup file) through `setup.cfg` (declarative configuration) to `pyproject.toml` (modern, tool-agnostic standard). Understanding this history explains why older projects have different configuration styles.

---

## How It Actually Works

`pip install requests` workflow:
1. Query PyPI API for the latest compatible version of `requests`
2. Download the wheel (`.whl`) file (preferred over sdist)
3. Extract the wheel into the current `site-packages` directory
4. Install any missing dependencies (from `requests`'s metadata)

A wheel is a zip archive with `.whl` extension containing:
- The package code
- Compiled extensions (if any)
- Metadata (`METADATA` file with name, version, dependencies)
- Entry points (command-line scripts to install)

`pyproject.toml` structure:

```toml
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.backends.legacy:build"

[project]
name = "mypackage"
version = "1.0.0"
description = "A short description"
requires-python = ">=3.11"
dependencies = [
    "requests>=2.28",
    "pydantic>=2.0",
]

[project.scripts]
mycli = "mypackage.cli:main"
```

`[build-system]` specifies the build backend. `[project]` is the standardized metadata (PEP 621). `[project.scripts]` defines command-line entry points.

`pip install -e .` creates a `.pth` file in `site-packages` pointing to the project root — Python adds that path to `sys.path`, making the package importable while allowing in-place editing.

Version specifiers follow PEP 440: `==1.0.0` (exact), `>=1.0,<2.0` (range), `~=1.4.2` (compatible release — equivalent to `>=1.4.2,<1.5`).

---

## How It Connects

Virtual environments isolate `site-packages` per project — `pip install` in an activated venv only affects that venv's packages.
[[virtual-environments|Virtual Environments]]

`pip install -e .` modifies `sys.path` via a `.pth` file — the mechanism that makes editable installs work.
[[sys-path|sys.path]]

---

## Common Misconceptions

Misconception 1: "`pip freeze` output is the right format for project dependencies."
Reality: `pip freeze` outputs fully pinned versions of all installed packages (including transitive dependencies) — good for deployment lockfiles, bad for library `install_requires`. A library should specify flexible version ranges in `pyproject.toml` (`requests>=2.28`) so users can install compatible versions. `pip freeze` output in `pyproject.toml` would force every user to install exactly those versions, causing conflicts.

Misconception 2: "`setup.py` is deprecated and should never be used."
Reality: `setup.py` is not deprecated, but the recommended approach has moved to `pyproject.toml`. Existing projects with `setup.py` still work and pip handles them. New projects should use `pyproject.toml`. Legacy `setup.py` projects can be incrementally migrated.

---

## Why It Matters in Practice

Every Python project that will be shared, deployed, or distributed needs `pyproject.toml`. It specifies the package name (for PyPI), version, dependencies, Python version requirements, and entry points. Even internal tools benefit from `pip install -e .` to make imports work cleanly.

Dependency management tools (Poetry, Hatch, PDM) wrap around `pyproject.toml` and provide lock files for reproducible installations. They all ultimately produce pip-installable packages.

`pip check` detects version conflicts in the current environment — useful when multiple packages have conflicting requirements.

---

## Interview Angle

Common question forms:
- "What is pip and PyPI?"
- "What is the difference between `pip freeze` and project dependencies?"

Answer frame: pip downloads and installs packages from PyPI. Always use a virtual environment. `pip install -e .` for editable development installs. `pyproject.toml` is the modern standard for project metadata with `[project]` (name, version, dependencies) and `[build-system]` sections. `pip freeze` captures exact versions of all installed packages for deployment lockfiles. Project `dependencies` in `pyproject.toml` should use flexible version ranges. `python -m build` creates wheel and sdist for distribution; upload to PyPI with `twine`.

---

## Related Notes

- [[virtual-environments|Virtual Environments]]
- [[sys-path|sys.path]]
- [[packages|Packages]]
- [[modules|Modules]]
