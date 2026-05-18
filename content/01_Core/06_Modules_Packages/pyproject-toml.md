---
title: 08 - pyproject.toml
description: "pyproject.toml is the PEP 517/518 standard configuration file that replaces setup.py  -  it declares the build system, project metadata, dependencies, and tool-specific settings in one canonical location."
tags: [pyproject-toml, pep-517, pep-518, pep-621, packaging, build-system, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# pyproject.toml

> `pyproject.toml` is Python's unified project configuration file  -  the single source of truth for build system, package metadata, dependency lists, and every tool's settings, replacing the scattered `setup.py`/`setup.cfg`/`tox.ini`/`mypy.ini` approach.

---

## Quick Reference

**Core idea:**
- Three primary sections: `[build-system]` (PEP 517/518), `[project]` (PEP 621 metadata), `[tool.*]` (arbitrary tool config)
- `[build-system]` declares the build backend (`hatchling`, `setuptools`, `flit-core`, etc.) and its requirements
- `[project]` holds canonical metadata: `name`, `version`, `dependencies`, `requires-python`, `scripts`, `entry-points`
- `[project.optional-dependencies]` defines extras: `pip install mypackage[dev]` installs the `dev` group
- `pip install -e .` and `python -m build` both read `pyproject.toml`; `setup.py` is no longer required

**Tricky points:**
- `[project.dependencies]` uses PEP 508 dependency specifiers  -  same format as `requirements.txt` but without `==` pinning by convention
- `python -m build` produces an `sdist` (`.tar.gz`) and `wheel` (`.whl`) in `dist/`  -  it does not publish to PyPI
- `[tool.*]` is open-ended  -  any tool can define its own subtable; `pyproject.toml` makes no guarantees about these sections
- TOML arrays of inline tables vs. multiline tables have different syntax  -  mistakes here produce silent misparsing
- `dynamic = ["version"]` in `[project]` tells the build backend to read the version from elsewhere (e.g., `__version__` in `__init__.py`)

---

## What It Is

Imagine a building contractor who, before `pyproject.toml`, had to read the blueprint from five different documents: one for the foundation, one for the electrical plan, one for the plumbing, one for the inspections checklist, and one for the permit application. Each document had its own format, its own conventions, and its own way of specifying the same address. `pyproject.toml` is the unified project file  -  everything in one document, one format (TOML), one place to look.

Before `pyproject.toml`, a Python project's configuration was fragmented across `setup.py` (metadata and build instructions in executable Python code), `setup.cfg` (declarative metadata, if using the setuptools plugin), `MANIFEST.in` (what to include in source distributions), `tox.ini` (test runner configuration), `mypy.ini` (type checker configuration), `.flake8` or `pyproject.toml` for linters, and `pytest.ini`. Adding a new tool meant adding another file. Changing the package name meant updating it in three places.

PEP 517 (2017) defined a standard interface for build backends  -  any tool that implements the `build_wheel` and `build_sdist` hooks can be used to build a Python package. PEP 518 required a `pyproject.toml` with a `[build-system]` table declaring which backend to use. PEP 621 (2021) standardized the `[project]` table for package metadata. Together, these three PEPs make `pyproject.toml` the canonical configuration file for virtually all modern Python projects.

---

## How It Actually Works

A minimal `pyproject.toml` for a package built with `hatchling`:

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "mypackage"
version = "0.1.0"
description = "A short description"
readme = "README.md"
requires-python = ">=3.10"
license = {text = "MIT"}
dependencies = [
    "httpx>=0.24",
    "pydantic>=2.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7",
    "mypy>=1.0",
    "ruff",
]

[project.scripts]
mypackage = "mypackage.cli:main"

[tool.mypy]
strict = true
python_version = "3.11"

[tool.ruff]
line-length = 88
select = ["E", "F", "I"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-v"
```

When `pip install -e .` runs, pip reads `[build-system]` to determine which build backend to use, installs it in a temporary isolated environment, and calls the backend's hooks to install the package in editable mode. When `python -m build` runs, it does the same but produces an `sdist` and a `wheel` in `dist/`. Neither tool ever runs `setup.py` if `pyproject.toml` is present with a `[build-system]` table.

The `[tool.*]` namespace is open. There is no schema for `[tool.mypy]` or `[tool.ruff]`  -  each tool reads its own subtable. TOML parsing is strict (no trailing commas, no duplicate keys), so syntax errors in `pyproject.toml` will prevent any tool from reading it, which makes the "one file" approach a single point of failure that requires care.

`[project.optional-dependencies]` defines extras  -  groups of additional dependencies activated by `pip install mypackage[dev]`. By convention, `dev` holds development tooling, `test` holds test dependencies, and `docs` holds documentation build dependencies. This replaces the multiple `requirements-dev.txt` files that were common before standardization.

---

## How It Connects

`pyproject.toml` is the entry point for the packaging ecosystem. `pip` reads it to build and install packages. `twine` publishes what `python -m build` produces. Understanding `pyproject.toml` requires understanding how pip resolves dependencies and what `virtual environments` provide.

[[pip-and-packaging|pip and Packaging]]

Virtual environments isolate the packages declared in `[project.dependencies]` from system Python. The `venv` or `venvPath` settings in tool configurations (`pyright`, `mypy`) point at the virtual environment so type stubs can be found.

[[virtual-environments|Virtual Environments]]

The `[project.scripts]` and `[project.entry-points]` tables define how installed packages expose command-line tools and plugin hooks  -  mechanisms that rely on Python's import system and package discovery.

[[import-system|Import System]]

---

## Common Misconceptions

Misconception 1: "`pyproject.toml` replaces `requirements.txt`."
Reality: They serve different purposes. `[project.dependencies]` in `pyproject.toml` declares loose version constraints for a reusable library or application. `requirements.txt` (or `requirements.lock`) pins exact versions for reproducible deployments. A project can have both.

Misconception 2: "`python -m build` publishes the package to PyPI."
Reality: `python -m build` creates `dist/mypackage-0.1.0.tar.gz` and `dist/mypackage-0.1.0-py3-none-any.whl` locally. Publishing requires `twine upload dist/*` as a separate step.

Misconception 3: "`setup.py` is deprecated and must be removed."
Reality: `setup.py` is no longer required and is not recommended for new projects, but it is not deprecated in the sense of producing warnings. Existing projects using `setup.py` continue to work. The community recommendation is to migrate to `pyproject.toml` for new projects and during major refactors.

---

## Why It Matters in Practice

The consolidation of tool configuration into `pyproject.toml` eliminates the configuration-file proliferation that plagued Python projects. A new team member now reads one file to understand the build system, dependencies, type checker settings, linter rules, and test runner options  -  rather than hunting across five or six separate files in the project root.

For library authors specifically, the `[project.dependencies]` and `[project.optional-dependencies]` distinction matters for users. Over-constraining versions in `[project.dependencies]` (using `==` instead of `>=`) forces transitive dependency conflicts on library consumers. The convention is to use minimal lower-bound constraints in library `[project.dependencies]`, and reserve exact pinning for application-level `requirements.lock` files.

---

## Interview Angle

Common question forms:
- "What is the purpose of `pyproject.toml`?"
- "What is the difference between `[project.dependencies]` and a `requirements.txt`?"
- "How do you define optional dependency groups in a Python package?"

Answer frame:
`pyproject.toml` is the PEP 517/518/621 standard for Python project configuration  -  build system (`[build-system]`), package metadata (`[project]`), and tool settings (`[tool.*]`) in one TOML file. `[project.dependencies]` declares what a library needs to run (loose constraints). `requirements.txt` pins exact versions for deployment. Optional deps: `[project.optional-dependencies]` with named groups, installed via `pip install pkg[groupname]`.

---

## Related Notes

- [[pip-and-packaging|pip and Packaging]]
- [[virtual-environments|Virtual Environments]]
- [[modules|Modules]]
- [[packages|Packages]]
- [[import-system|Import System]]
