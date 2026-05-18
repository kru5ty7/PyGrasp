---
title: 02 - GitHub Actions for Python
description: "Python-specific GitHub Actions patterns include using actions/setup-python for version management, caching pip or uv packages to reduce install time, and matrix strategies to test across multiple Python versions simultaneously."
tags: [github-actions, python, setup-python, pip-cache, matrix-strategy, uv, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# GitHub Actions for Python

> Python-specific GitHub Actions workflows use `actions/setup-python` to install a specific Python version on the runner, pip caching to avoid re-downloading packages on every run, and matrix strategies to validate compatibility across multiple Python versions in parallel.

---

## Quick Reference

**Core idea:**
- `uses: actions/setup-python@v5` with `python-version: "3.12"`  -  installs Python on the runner
- `cache: pip` in `actions/setup-python`  -  caches pip's downloaded wheel cache between runs
- `strategy: matrix: python-version: [3.11, 3.12, 3.13]`  -  runs the job once per version in parallel
- `pip install -e ".[dev]"`  -  installs the project with dev extras from `pyproject.toml`
- uv alternative: `pip install uv && uv sync`  -  faster install, especially on warm cache
- `${{ matrix.python-version }}`  -  interpolates the current matrix value into steps

**Tricky points:**
- The pip cache key should include the `requirements.txt` or `pyproject.toml` hash  -  if requirements change, the cache must be invalidated
- `cache: pip` in `setup-python` caches pip's HTTP cache (downloaded wheels), not the installed virtualenv  -  packages are still installed on each run, just from local cache without network
- Poetry + GitHub Actions: `pip install poetry` then `poetry install --no-interaction` is the standard pattern; add `--no-root` to install dependencies without the project itself when the goal is testing
- `actions/cache` (manual caching) gives more control over cache keys than the built-in pip cache option
- Matrix failures: by default, all matrix variants continue when one fails; `fail-fast: false` under `strategy:` allows all variants to run to completion even after a failure

---

## What It Is

A GitHub Actions workflow for a Python project requires a few Python-specific considerations that are not present in language-agnostic CI setups. The runner VM is a clean Ubuntu (or macOS, or Windows) instance with only system Python available. The workflow must install the correct Python version, install project dependencies, and then run project-specific commands. Each of these steps has Python-specific tooling and caching opportunities.

The most impactful optimization is caching. Installing 20 - 50 Python packages from PyPI can take 60 - 120 seconds on each CI run  -  downloading wheels, unpacking them, and installing into site-packages. With a warm cache, the wheel files are already on disk and the install takes under 10 seconds. GitHub Actions provides a cache mechanism keyed on arbitrary strings (typically a hash of the requirements file), storing and restoring cache between runs. When the requirements file has not changed, the cache hit rate is 100% and the CI install step becomes negligible.

Matrix strategies are the second Python-specific feature. A library author needs to verify that their package works on all supported Python versions. Rather than creating separate jobs manually, a matrix strategy defines a list of Python versions and GitHub Actions automatically creates one job per version, running all of them in parallel. The result is that CI validates multiple Python versions in the same time as validating one.

---

## How It Actually Works

**Standard workflow with caching:**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"              # Caches ~/.cache/pip between runs

      - name: Install dependencies
        run: |
          pip install --upgrade pip
          pip install -r requirements.txt

      - name: Run linter
        run: ruff check .

      - name: Run tests
        run: pytest tests/ -v --tb=short
```

**Matrix strategy for multiple Python versions:**

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.11", "3.12", "3.13"]
      fail-fast: false        # Continue running all matrix variants on failure

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python ${{ matrix.python-version }}
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: "pip"

      - name: Install dependencies
        run: pip install -e ".[dev]"    # Install from pyproject.toml with dev extras

      - name: Test
        run: pytest tests/ --tb=short
```

**Poetry workflow:**

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-python@v5
    with:
      python-version: "3.12"

  - name: Install Poetry
    run: pip install poetry

  - name: Configure Poetry
    run: poetry config virtualenvs.create false   # Install into system Python, not a venv

  - name: Cache Poetry dependencies
    uses: actions/cache@v4
    with:
      path: ~/.cache/pypoetry
      key: poetry-${{ runner.os }}-${{ hashFiles('poetry.lock') }}

  - name: Install dependencies
    run: poetry install --no-interaction --no-root

  - name: Run tests
    run: poetry run pytest tests/
```

**uv workflow (fastest option):**

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-python@v5
    with:
      python-version: "3.12"

  - name: Install uv
    run: pip install uv

  - name: Cache uv packages
    uses: actions/cache@v4
    with:
      path: ~/.cache/uv
      key: uv-${{ runner.os }}-${{ hashFiles('uv.lock') }}

  - name: Install dependencies
    run: uv sync --frozen

  - name: Run tests
    run: uv run pytest tests/
```

**Cache key design** is important for correctness:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cache/pip
    key: pip-${{ runner.os }}-${{ hashFiles('requirements.txt') }}
    restore-keys: |
      pip-${{ runner.os }}-
```

The `key` includes the requirements file hash  -  when `requirements.txt` changes, the hash changes, the key changes, and the old cache is not used (preventing stale installs). The `restore-keys` fallback allows partial cache hits when only some dependencies changed.

---

## How It Connects

The GitHub Actions basics (jobs, steps, triggers) are the foundation these Python-specific patterns build on.

[[github-actions-basics|GitHub Actions Basics]]

A complete CI pipeline for Python combines the setup described here with specific lint -> test -> coverage stages.

[[ci-testing-pipeline|CI Testing Pipeline]]

uv's speed advantage is most visible in CI where the global package cache eliminates redundant downloads between runs.

[[uv|uv]]

---

## Common Misconceptions

Misconception 1: "Setting `cache: pip` in `actions/setup-python` means I never reinstall packages."
Reality: The built-in pip cache stores pip's HTTP download cache (the wheel files), not the installed virtual environment. Packages are still installed on each run, but from the local disk cache instead of downloading from PyPI. The install step still runs; it is just faster. Using `actions/cache` to cache the entire virtual environment directory is an alternative that avoids reinstallation entirely, but requires a more complex cache key strategy.

Misconception 2: "Matrix strategies double or triple my CI time."
Reality: Matrix jobs run in parallel, not sequentially. Three matrix variants (Python 3.11, 3.12, 3.13) all start simultaneously and complete in roughly the same time as one variant. The trade-off is parallel runner slots  -  large matrices on free-tier GitHub Actions may be queued. The typical result is the same wall-clock time with more coverage.

Misconception 3: "I need to use the exact Python version string  -  `3.12.3` not `3.12`."
Reality: `actions/setup-python` with `python-version: "3.12"` installs the latest available patch version of 3.12. Using `"3.12"` is intentional  -  it means "the latest 3.12.x available." Pinning to a specific patch version like `"3.12.3"` means the workflow breaks when that exact version is removed from the runner's toolcache. Use minor version specifiers in CI; let the runner provide the latest patch.

---

## Why It Matters in Practice

CI setup time (the time from `git push` to "tests passed" notification) directly affects developer workflow. A CI pipeline that takes 8 minutes because it re-downloads packages on every run trains developers to push less frequently or to stop waiting for CI results. A pipeline that takes 90 seconds because packages are cached and tests run in parallel keeps CI in the developer's natural feedback loop.

Library maintainers with Python version matrix testing catch compatibility issues before releasing a new version. Finding that a package uses a Python 3.12-only `typing` feature that breaks on 3.11 in CI (before release) is vastly better than finding it from user bug reports after release.

---

## Interview Angle

Common question forms:
- "How do you set up a Python CI pipeline in GitHub Actions?"
- "How do you test a library across multiple Python versions?"

Answer frame:
Describe the four-step structure: checkout -> setup-python -> install dependencies (with cache) -> test. Explain the pip cache key design (hash of requirements file for cache invalidation). Describe matrix strategies for multi-version testing. Mention uv as a faster alternative to pip for CI installs. A senior answer discusses the trade-off between caching the download cache (what `cache: pip` does) vs caching the installed environment (what manual `actions/cache` on the venv directory achieves).

---

## Related Notes

- [[github-actions-basics|GitHub Actions Basics]]
- [[ci-testing-pipeline|CI Testing Pipeline]]
- [[uv|uv]]
- [[poetry|Poetry]]
- [[pytest|Pytest]]
