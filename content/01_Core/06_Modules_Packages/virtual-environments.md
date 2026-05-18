---
title: 06 - Virtual Environments
description: "A virtual environment is an isolated Python installation with its own `site-packages` directory  -  `python -m venv .venv` creates one; activating it redirects `python` and `pip` to the isolated environment, preventing package version conflicts between projects."
tags: [virtual-environments, venv, pip, site-packages, isolation, python-environment, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Virtual Environments

> A virtual environment is an isolated Python installation with its own `site-packages` directory  -  `python -m venv .venv` creates one; activating it redirects `python` and `pip` to the isolated environment, preventing package version conflicts between projects.

---

## Quick Reference

**Core idea:**
- `python -m venv .venv`  -  creates a virtual environment in `.venv/` directory
- Activate: `source .venv/bin/activate` (Unix) / `.venv\Scripts\activate` (Windows PowerShell)
- Deactivate: `deactivate`
- When activated: `python` and `pip` refer to the venv's executables; packages install to the venv's `site-packages`
- `pip freeze > requirements.txt`  -  captures installed packages and versions; `pip install -r requirements.txt` restores them

**Tricky points:**
- Virtual environments are not portable  -  they contain absolute paths; moving a venv to another directory or machine breaks it; recreate from `requirements.txt` instead
- The venv does not include the standard library  -  it inherits it from the Python interpreter used to create it
- `python -m venv --system-site-packages .venv`  -  creates a venv that also sees the system site-packages; useful when system packages are hard to install in the venv but generally avoided
- `pip install` without an active venv installs to the system or user Python  -  `--user` flag installs to `~/.local/lib/...`
- Modern tooling: `uv` (Astral), `poetry`, `hatch` manage venvs automatically; understanding the underlying `venv` + `pip` flow is still valuable

---

## What It Is

Think of a virtual environment as a dedicated workbench for each project. The workshop (your system Python) has some tools on it already, but each project gets its own workbench with exactly the tools it needs  -  isolated from other projects. Installing a new version of a tool on one workbench does not affect other workbenches. When you work on a project, you sit at that project's workbench.

Without virtual environments, all Python projects on a machine share one set of packages. Project A needs Django 3.2; Project B needs Django 4.1. Installing one breaks the other. Virtual environments give each project its own `site-packages` directory  -  packages are installed per-project.

---

## How It Actually Works

`python -m venv .venv` creates:
```
.venv/
├── bin/ (or Scripts/ on Windows)
│   ├── python -> /usr/bin/python3  (symlink)
│   ├── pip
│   └── activate  (shell script)
├── include/
├── lib/
│   └── python3.11/
│       └── site-packages/  (packages installed here)
└── pyvenv.cfg  (stores Python version and include-system-site-packages)
```

The `activate` script sets `PATH` to put `.venv/bin` first and sets `VIRTUAL_ENV` environment variable. With the venv activated, typing `python` runs `.venv/bin/python`, which has its own `sys.prefix` pointing to `.venv/`  -  this causes `site.py` to add `.venv/lib/python3.11/site-packages` to `sys.path` instead of the system site-packages.

When you run `pip install requests` in an activated venv, `pip` installs to `.venv/lib/python3.11/site-packages/`. The system Python's site-packages is not affected.

`python -m venv` uses the Python interpreter it is called with. `python3.11 -m venv .venv` creates a Python 3.11 venv. To use a different Python version, use that version's executable.

`requirements.txt` is a plain-text list of package specifiers:
```
requests==2.31.0
flask>=2.3,<3.0
```
`pip install -r requirements.txt` installs exactly these versions. `pip freeze` generates a fully pinned list (all transitive dependencies with exact versions)  -  good for deployment, but brittle for libraries (too rigid).

---

## How It Connects

`sys.path` is what makes virtual environments work  -  activating a venv modifies `sys.path` to prioritize the venv's `site-packages` over system packages.
[[sys-path|sys.path]]

`pip-and-packaging` covers distributing packages  -  the companion to installing them.
[[pip-and-packaging|pip and Packaging]]

---

## Common Misconceptions

Misconception 1: "Deleting and recreating a virtual environment loses important data."
Reality: A virtual environment contains only installed packages and the Python interpreter symlink. All project code lives outside the venv. Recreating the venv from `requirements.txt` recovers the exact same environment. Commit `requirements.txt` (or `pyproject.toml`); never commit the venv directory.

Misconception 2: "One virtual environment per machine is enough."
Reality: One virtual environment per **project** is the standard practice. Different projects have different, potentially incompatible dependencies. A single shared environment creates the version conflict problem that virtual environments solve.

---

## Why It Matters in Practice

Every Python project should have its own virtual environment. Add `.venv/` or `venv/` to `.gitignore`. Store dependencies in `requirements.txt` or `pyproject.toml`. Teammates recreate the environment from the requirements file  -  reproducible, consistent setup.

CI/CD: create a fresh venv in each pipeline run and install from requirements. This verifies the requirements file is complete and reproducible.

Modern tooling: `uv venv && uv pip install -r requirements.txt` is the fast alternative (uv is a Rust-based pip replacement). `poetry` and `hatch` manage venvs transparently as part of project management. The underlying mechanism is the same.

---

## Interview Angle

Common question forms:
- "What is a virtual environment and why would you use one?"
- "How do you create and activate a virtual environment?"

Answer frame: A virtual environment is an isolated Python installation with its own `site-packages`. It prevents package version conflicts between projects. Create with `python -m venv .venv`; activate with `source .venv/bin/activate` (Unix) or `.venv\Scripts\activate` (Windows). Activated: `python` and `pip` point to the venv. Capture deps with `pip freeze > requirements.txt`; recreate with `pip install -r requirements.txt`. Never commit the venv directory; always commit the requirements file.

---

## Related Notes

- [[sys-path|sys.path]]
- [[pip-and-packaging|pip and Packaging]]
- [[import-system|The Import System]]
