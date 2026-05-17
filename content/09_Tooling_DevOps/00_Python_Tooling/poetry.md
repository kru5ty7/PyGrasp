---
title: 01 - Poetry
description: "Poetry is a Python dependency management and packaging tool that uses pyproject.toml as a single source of truth, a lockfile for reproducible installs, and a built-in build backend for publishing packages."
tags: [poetry, dependency-management, packaging, pyproject-toml, lockfile, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Poetry

> Poetry is a Python dependency management and packaging tool that centers everything around `pyproject.toml` — it manages virtual environments, resolves dependencies with a lockfile, and packages your project for PyPI, all through a single CLI.

---

## Quick Reference

**Core idea:**
- `poetry new my-project` — scaffolds a new project with `pyproject.toml` and a src layout
- `poetry add requests` — adds a dependency, resolves, and updates `poetry.lock`
- `poetry add --group dev pytest` — adds a dev-only dependency into a named group
- `poetry install` — installs all dependencies from the lockfile (reproducible)
- `poetry run python app.py` — runs a command inside the managed virtual environment
- `poetry build && poetry publish` — builds a wheel/sdist and publishes to PyPI

**Tricky points:**
- `poetry install` with a lockfile installs exact pinned versions; `poetry update` re-resolves; never confuse the two
- `poetry.lock` should be committed in applications (reproducibility) but debated for libraries (flexibility for downstream users)
- Dependency groups (`--group dev`, `--group test`) replace the older `[tool.poetry.dev-dependencies]` section from Poetry 1.2+
- Poetry manages its own virtualenv by default; `poetry env info` shows where it is; `poetry config virtualenvs.in-project true` puts it in `.venv/` next to the project
- `pyproject.toml` version specifiers use `^1.2.3` (caret — minor-compatible) and `~1.2.3` (tilde — patch-compatible) — different from pip's `>=`/`==` syntax

---

## What It Is

Think of Poetry as a project manager for Python, in the same way that `cargo` is for Rust or `npm` is for Node. Before Poetry, a Python project typically had at least three separate concerns: `requirements.txt` for runtime dependencies, `requirements-dev.txt` for development tools, a `setup.py` or `setup.cfg` for packaging metadata, and separate documentation for which Python version the project expects. These files were often maintained inconsistently and manually. Poetry collapses all of that into one file: `pyproject.toml`.

The core value proposition is reproducibility through a lockfile. When you run `poetry add requests`, Poetry does not simply record `requests` in `pyproject.toml` and move on. It runs a full dependency resolution, computes the complete transitive closure of all packages that need to be installed, and writes every package name plus its exact hash into `poetry.lock`. The next developer who runs `poetry install` does not re-resolve — they install the exact same graph, byte for byte. This eliminates the entire class of bugs that comes from "it works on my machine" because two developers happened to get different transitive dependency versions.

Poetry also handles the packaging side. When a project is ready for distribution, `poetry build` produces a wheel and a source distribution using the metadata already in `pyproject.toml`. `poetry publish` uploads to PyPI. There is no need to write a separate `MANIFEST.in`, maintain `setup.py`, or understand the details of `twine`. This makes Poetry particularly compelling for library authors who otherwise had to context-switch between multiple tools.

---

## How It Actually Works

When `poetry add requests` is invoked, Poetry reads the existing `pyproject.toml` to understand current constraints, then queries PyPI (or a configured private index) for the available versions of `requests` and all of its declared dependencies. It runs a SAT-solver-style resolution algorithm that finds a set of versions that satisfies all constraints simultaneously — the version specifiers you declared plus the transitive dependencies of those packages. The result is written to both `pyproject.toml` (the human-maintained constraint) and `poetry.lock` (the machine-generated exact solution).

The `[tool.poetry.dependencies]` section of `pyproject.toml` holds version constraints like `requests = "^2.28.0"`. The caret constraint `^2.28.0` means ">=2.28.0 and <3.0.0" — it allows minor and patch updates but not major version jumps. The lockfile records the exact version that satisfied this constraint at resolution time:

```toml
# pyproject.toml (human-authored constraint)
[tool.poetry.dependencies]
python = "^3.11"
requests = "^2.28.0"

[tool.poetry.group.dev.dependencies]
pytest = "^7.4"
ruff = "^0.1"
```

```
# poetry.lock (machine-generated, exact)
[[package]]
name = "requests"
version = "2.31.0"
description = "Python HTTP for Humans."
...
[package.metadata]
files = [
    {file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:..."},
]
```

Poetry manages virtual environments automatically. On first use in a project directory, it creates an environment either in a central cache directory or (if configured) in `.venv/`. All commands like `poetry run`, `poetry shell`, and `poetry install` operate on this environment without requiring manual activation.

---

## How It Connects

Poetry reads and writes `pyproject.toml` — understanding the structure of that file is foundational to understanding what Poetry generates.

[[pyproject-toml|pyproject.toml]]

Poetry's virtual environment management is built on top of the same `venv` mechanism used by bare Python. Understanding what a virtual environment is clarifies why Poetry creates one per project.

[[virtual-environments|Virtual Environments]]

Ruff and Black are commonly added as dev dependencies via Poetry's dependency groups, and their configuration lives in the same `pyproject.toml` file that Poetry manages.

[[ruff|Ruff]]

---

## Common Misconceptions

Misconception 1: "Running `poetry install` after pulling new changes will upgrade my packages to the latest versions."
Reality: `poetry install` always installs from the lockfile — it never re-resolves or upgrades. It is deterministic by design. To upgrade dependencies, run `poetry update`, which re-resolves constraints and rewrites the lockfile. Then commit the updated lockfile.

Misconception 2: "I should not commit `poetry.lock` to the repository."
Reality: For applications, committing the lockfile is essential for reproducible deployments. Every developer and every CI run gets the same exact package graph. For libraries, the convention is more nuanced — the lockfile is used by the library's own development environment, but downstream consumers resolve their own. Many library authors still commit it for CI reproducibility while documenting that end users should not rely on it.

Misconception 3: "Poetry replaces pip entirely."
Reality: Poetry uses pip internally for certain operations and creates standard-compliant packages. It is a higher-level tool that generates standard artifacts (wheels, sdists) that pip can install. In production Docker images it is common to export a `requirements.txt` via `poetry export` and install with pip for minimal image footprint.

---

## Why It Matters in Practice

In a team setting, a shared lockfile means that dependency drift — where two developers independently end up with slightly different package versions — is impossible as long as everyone installs from the lock. This eliminates an entire category of environment-specific bugs. In CI/CD, `poetry install --no-root` installs all dependencies but not the project itself, which is the correct pattern for testing or building applications.

The build and publish workflow matters when writing libraries or internal packages. A project that starts with Poetry never needs to add `setup.py` or learn the PEP 517/518 build backend ecosystem directly — Poetry handles it. When the project grows and needs to be published to a private PyPI server (Artifactory, Nexus, or AWS CodeArtifact), Poetry's `[[tool.poetry.source]]` configuration section handles authentication and routing without modifying how the rest of the toolchain works.

---

## Interview Angle

Common question forms:
- "What is the difference between `requirements.txt` and a lockfile?"
- "How does Poetry manage dependencies differently from pip?"
- "What is the purpose of `poetry.lock`?"

Answer frame:
A strong answer explains that `requirements.txt` is a constraint file — it records what your project needs. A lockfile records the exact solution to those constraints, including transitive dependencies and their hashes. Poetry maintains both: `pyproject.toml` has your constraints, `poetry.lock` has the exact resolved solution. `poetry install` installs from the lock (deterministic), while `poetry update` re-resolves. This is the key mental model: constraints vs. solutions.

---

## Related Notes

- [[pyproject-toml|pyproject.toml]]
- [[virtual-environments|Virtual Environments]]
- [[pip-and-packaging|pip and Packaging]]
- [[uv|uv]]
- [[pre-commit|Pre-commit Hooks]]
