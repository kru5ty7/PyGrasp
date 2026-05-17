---
title: 02 - uv
description: "uv is a Rust-based Python package and project manager from Astral that replaces pip, pip-tools, and virtualenv with a unified CLI that is 10–100x faster due to parallel downloads, a global package cache, and Rust-native dependency resolution."
tags: [uv, package-manager, pip-replacement, virtualenv, rust, astral, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# uv

> uv is an extremely fast Python package and project manager written in Rust — it replaces pip, pip-tools, venv, and parts of Poetry with a single binary that performs dependency resolution and installation 10–100x faster through parallelism and a global content-addressed cache.

---

## Quick Reference

**Core idea:**
- `uv pip install requests` — drop-in pip replacement, same interface, dramatically faster
- `uv venv` — creates a virtual environment (replaces `python -m venv`)
- `uv run python script.py` — runs a command in the project's managed environment
- `uv sync` — installs all dependencies from `uv.lock` (analogous to `poetry install`)
- `uv add requests` — adds a dependency to `pyproject.toml` and updates the lockfile
- `uv pip compile requirements.in -o requirements.txt` — drop-in pip-tools replacement

**Tricky points:**
- uv is a standalone binary — it does not require a prior Python installation to use, though it still installs packages for a Python interpreter
- `uv run` automatically creates a virtual environment if one does not exist — it is the "just works" entry point for project-managed workflows
- The global cache stores packages by content hash; installing the same package in 100 projects costs disk space for only one copy
- uv respects `pyproject.toml` and `uv.lock` for project workflows, but also works in "tool mode" as a pip drop-in without a project file
- Speed comes partly from parallelizing all HTTP requests and wheel installations — pip processes packages sequentially by default

---

## What It Is

uv is best understood as the pip-ecosystem rewritten from scratch in Rust with modern software engineering constraints: speed, correctness, and a unified interface. The Python packaging ecosystem historically evolved as a collection of independent tools — pip for installing, virtualenv or venv for isolation, pip-tools for lockfiles, twine for publishing. Each tool had its own interface, its own quirks, and its own speed characteristics. Installing a project's dependencies in CI could take minutes simply because pip's sequential download model did not take advantage of available bandwidth and CPU.

Astral, the company behind Ruff (the linter), built uv as the packaging complement to that tooling philosophy: use Rust where Python is the bottleneck, maintain compatibility with existing standards and interfaces, and provide a single cohesive tool instead of a fragmented toolchain. uv is not a new packaging standard — it still installs standard Python wheels and sdists, still respects `pyproject.toml` and PEP 517/518 build semantics, and still talks to PyPI. What it replaces is the Python-based implementation of those operations.

The speed differential is not marginal. On a cold cache, installing a typical web project's dependencies takes pip several minutes; uv does the same in seconds. On a warm cache — which is the normal case in CI with proper caching configured — uv installs from local disk with essentially zero network time, because the global cache has already stored the wheel content. This changes the economics of CI — faster feedback loops mean developers are less tempted to skip the CI run.

---

## How It Actually Works

uv's performance comes from several compounding architectural decisions. First, all HTTP requests are issued in parallel — while pip fetches package metadata and then wheels sequentially, uv fetches everything concurrently. Second, uv uses a global content-addressed cache at `~/.cache/uv/` (or the platform equivalent). Every wheel downloaded anywhere on the machine is stored once, keyed by its content hash. When a second project needs the same wheel, uv hardlinks (or copies, depending on filesystem) from the cache rather than downloading again. Third, the dependency resolver is implemented in Rust using a backtracking SAT solver (PubGrub-style) that is substantially faster than pip's Python-based resolver for complex dependency graphs.

The project workflow mirrors Poetry's concepts: `uv init` creates a `pyproject.toml`, `uv add` adds dependencies, `uv sync` installs from `uv.lock`. The lockfile records exact versions and hashes for the full transitive dependency graph:

```bash
# Create and manage a new project
uv init my-project
cd my-project
uv add fastapi uvicorn
uv add --dev pytest ruff

# Install everything from lockfile (deterministic)
uv sync

# Run within the project environment
uv run uvicorn app.main:app --reload
```

In "pip mode" — without a `pyproject.toml` — uv acts as a direct pip replacement:

```bash
# Create a virtual environment
uv venv .venv

# Install into it (same flags as pip)
uv pip install -r requirements.txt
uv pip install "fastapi>=0.100" uvicorn

# Compile a requirements.in to a locked requirements.txt
uv pip compile requirements.in -o requirements.txt
```

The `uv tool run` (or `uvx`) command runs a CLI tool in an ephemeral environment without installing it into the project. `uvx ruff check .` runs Ruff without adding it as a project dependency — useful for one-off operations.

---

## How It Connects

uv creates and manages virtual environments using the same underlying Python venv semantics — understanding what a virtual environment is explains what uv is automating.

[[virtual-environments|Virtual Environments]]

uv's project workflow is conceptually similar to Poetry's, both using `pyproject.toml` and a lockfile. Knowing both tools helps when inheriting different projects.

[[poetry|Poetry]]

In CI pipelines, uv's speed makes it the preferred installation tool — the cache can be shared across GitHub Actions runs using the standard caching action.

[[github-actions-python|GitHub Actions for Python]]

---

## Common Misconceptions

Misconception 1: "uv is just a faster pip — it only works as a drop-in replacement."
Reality: uv has two modes. In "pip compatibility mode" it is a drop-in replacement for pip and pip-tools commands. In "project mode" it is a full project manager with its own lockfile (`uv.lock`), dependency groups, and `uv add`/`uv sync` commands that compete with Poetry. The two modes can coexist — a project can use `uv sync` for development and `uv pip install` in the Dockerfile.

Misconception 2: "I need to uninstall pip before using uv."
Reality: uv and pip coexist without conflict. uv is an independent binary. Many workflows use uv for speed in development and CI while keeping pip for the final Docker image layer because pip is already present in the base Python image, eliminating a binary download step.

Misconception 3: "The global cache is dangerous because it could corrupt multiple projects."
Reality: The global cache is read-only for consumers — uv copies or hardlinks from it into each virtual environment. A corrupt cache entry affects only the package that cached entry represents, and `uv cache clean` rebuilds it. The cache holds immutable wheel content and is keyed by content hash, so there is no risk of one project's install polluting another.

---

## Why It Matters in Practice

The practical impact of uv is most visible in CI/CD environments. A typical GitHub Actions workflow using pip might spend 2–4 minutes installing dependencies. The same workflow with uv, combined with the uv cache action, can reduce that to under 10 seconds. Over thousands of CI runs, this is not just a convenience — it is a material reduction in infrastructure cost and developer feedback time.

For local development, `uv run` eliminates the activation ceremony. Instead of `source .venv/bin/activate && python script.py`, developers just run `uv run python script.py`. uv creates the environment if needed, syncs from the lockfile, and executes the command. This is especially useful in scripts and Makefiles where environment activation is fragile across shells.

---

## Interview Angle

Common question forms:
- "Why would you choose uv over pip and venv?"
- "What makes uv faster than pip?"

Answer frame:
The answer should cover three things: parallelism (uv fetches all packages concurrently), the global content-addressed cache (same wheel is never downloaded twice across projects), and Rust-native resolution (faster SAT solver for complex dependency graphs). A senior answer adds that uv is also a project manager (like Poetry) with its own lockfile, not just a pip replacement — and explains the two modes.

---

## Related Notes

- [[virtual-environments|Virtual Environments]]
- [[poetry|Poetry]]
- [[pip-and-packaging|pip and Packaging]]
- [[github-actions-python|GitHub Actions for Python]]
