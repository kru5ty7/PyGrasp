---
title: 03 - CI Testing Pipeline
description: "A CI testing pipeline sequences lint, type checking, tests, and coverage in a deliberate order so that cheap fast checks run first and failures are caught before expensive slow checks, minimizing feedback time and compute cost."
tags: [ci, testing, pipeline, lint, coverage, fail-fast, github-actions, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# CI Testing Pipeline

> A CI testing pipeline is a sequence of quality gates — lint, type check, test, coverage — ordered from cheapest to most expensive so that failures discovered early abort the pipeline before wasting time on later stages, a principle called fail-fast.

---

## Quick Reference

**Core idea:**
- Stage order: **lint → type-check → test → coverage** (fastest and most fundamental first)
- Fail-fast: if lint fails, the pipeline stops; no point running tests against unformatted code
- Coverage gates: `pytest --cov --cov-fail-under=80` fails if coverage drops below 80%
- Artifacts: upload test results and coverage reports for later inspection (`actions/upload-artifact`)
- Status checks in GitHub: required status checks block PRs from merging until CI passes
- Separate jobs for parallelism; `needs:` for sequential dependencies where required

**Tricky points:**
- Not everything should fail-fast: `fail-fast: false` on a matrix lets all Python versions complete even if one fails — more information, slower to see first failure
- Coverage percentage alone is a weak signal — 80% coverage can mean 80% of lines were executed, not that the tests are meaningful; coverage gates are floors, not ceilings
- Flaky tests (tests that sometimes pass and sometimes fail non-deterministically) corrupt CI trust — developers ignore CI when it fails randomly; fix or quarantine flaky tests immediately
- Type checking (mypy) is often the slowest step because it must analyze the entire codebase; cache mypy's `.mypy_cache` directory between runs
- Test artifacts (JUnit XML, coverage HTML) uploaded as GitHub Actions artifacts can be downloaded and inspected locally when a test fails in CI

---

## What It Is

A CI pipeline is the automated quality gate that every code change must pass before it is merged. The pipeline's purpose is to give the team confidence that a proposed change does not break anything that was previously working, and that it meets the project's quality standards. Without CI, quality checking is manual, inconsistent, and scales poorly as the team grows.

The fail-fast principle is the organizing philosophy of pipeline design. Checks are ordered from cheapest (in time and compute) to most expensive. If a check fails, the pipeline stops immediately — there is no value in running expensive tests against code that fails the lint check. A developer whose change breaks linting learns this in 30 seconds (when the lint job fails) rather than in 5 minutes (when they would have learned it if tests had run first). This respects developer attention: failures are reported as quickly as possible, so developers are still mentally engaged with the code that caused the failure.

The practical implications of this ordering are: linting must run first because it catches trivial errors (unused imports, style violations) cheaply and quickly. Type checking runs second because it catches type errors before tests run, and type errors that would cause test failures are better caught statically. Tests run third because they are slower and require a running application or database. Coverage analysis runs last because it requires tests to have completed.

---

## How It Actually Works

A complete CI pipeline for a Python project:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  # Stage 1: Lint (fastest — catches style and trivial errors)
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"
      - run: pip install ruff
      - name: Ruff lint
        run: ruff check .
      - name: Ruff format check
        run: ruff format --check .

  # Stage 2: Type check (medium speed — static analysis)
  typecheck:
    name: Type Check
    runs-on: ubuntu-latest
    needs: lint           # Only run if lint passes
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"
      - run: pip install mypy types-requests
      - name: Restore mypy cache
        uses: actions/cache@v4
        with:
          path: .mypy_cache
          key: mypy-${{ runner.os }}-${{ hashFiles('**/*.py') }}
      - name: Mypy type check
        run: mypy src/

  # Stage 3: Test with coverage (slowest — requires running code)
  test:
    name: Test (Python ${{ matrix.python-version }})
    runs-on: ubuntu-latest
    needs: lint           # Parallel with typecheck, both need lint to pass
    strategy:
      matrix:
        python-version: ["3.11", "3.12"]
      fail-fast: false    # See all failures, not just the first
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: "pip"
      - name: Install dependencies
        run: pip install -e ".[dev]"
      - name: Run tests with coverage
        run: |
          pytest tests/ \
            --tb=short \
            --junitxml=test-results/junit.xml \
            --cov=src \
            --cov-report=xml:coverage.xml \
            --cov-report=term-missing \
            --cov-fail-under=80
      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()     # Upload even on failure — useful for debugging
        with:
          name: test-results-${{ matrix.python-version }}
          path: |
            test-results/
            coverage.xml

  # Stage 4: Coverage report (only on main branch — informational)
  coverage:
    name: Coverage Report
    runs-on: ubuntu-latest
    needs: test
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: test-results-3.12
      - name: Upload to Codecov
        uses: codecov/codecov-action@v4
        with:
          files: coverage.xml
          token: ${{ secrets.CODECOV_TOKEN }}
```

The `if: always()` on the artifact upload step is critical for debugging. Without it, the upload step only runs when the previous steps succeeded. If a test fails, you want the XML report with the failure details to be available. `if: always()` overrides the step's default condition (which would skip it after a failure) and uploads regardless of test outcome.

**Pytest flags for CI:**
- `--tb=short` — shorter tracebacks in CI output (less scrolling)
- `--junitxml=results.xml` — produces JUnit XML that GitHub can parse for inline test results
- `--cov-fail-under=80` — fails the job if coverage drops below 80%
- `-x` — stop on first failure (useful for a developer running locally, but not in CI where you want to see all failures)

---

## How It Connects

GitHub Actions provides the runner infrastructure that executes this pipeline — the basic workflow syntax is covered in the foundation note.

[[github-actions-basics|GitHub Actions Basics]]

Python-specific setup (actions/setup-python, pip caching, matrix strategy) feeds into the test stage here.

[[github-actions-python|GitHub Actions for Python]]

The CD pipeline triggers after the CI pipeline succeeds — only green CI results in a deployment.

[[cd-docker|CD with Docker]]

---

## Common Misconceptions

Misconception 1: "Running all checks in one job is simpler and equivalent to separate jobs."
Reality: One monolithic job runs everything sequentially. Separate jobs run in parallel. lint and typecheck both depending on lint passes means lint runs, then lint and typecheck run in parallel, then test begins. This parallelism can cut total CI time by 30–50% for medium-sized projects. The structured dependency graph (via `needs:`) also makes the failure source immediately visible in the GitHub Actions UI.

Misconception 2: "100% code coverage means the code is well-tested."
Reality: 100% line coverage means every line was executed during tests — not that every important behavior was verified. A test that calls a function but asserts nothing can achieve 100% coverage with zero meaningful validation. Coverage is a useful floor (below 60% is a warning sign) but a poor ceiling metric. Use it as an indicator, not a quality guarantee.

Misconception 3: "CI should catch everything, so I don't need pre-commit hooks locally."
Reality: CI gives feedback minutes after a push. Pre-commit hooks give feedback in seconds, before the commit is even created. Both serve different points in the workflow. Pre-commit hooks catch issues during development (fast local feedback). CI catches issues for every push, providing team-wide enforcement even for developers who skipped `pre-commit install`.

---

## Why It Matters in Practice

The biggest operational benefit of a well-designed CI pipeline is that it changes the culture of code review. When CI is fast, reliable, and catches real issues, reviewers trust that any PR with green CI is free of lint errors, type errors, and regression bugs. Code review focuses on design and business logic, not on catching things the machine should catch. When CI is slow, unreliable, or catches nothing important, developers stop waiting for it.

The coverage gate is particularly important for teams with legacy code. A `--cov-fail-under` threshold on the test job means that new code which reduces overall coverage (by adding code without tests) fails CI. This creates a ratchet: coverage can only stay the same or go up, never down, as long as all PRs pass the coverage gate.

---

## Interview Angle

Common question forms:
- "How would you structure a CI pipeline for a Python project?"
- "What is fail-fast and why does it matter?"

Answer frame:
Describe the stage order: lint → type-check → test → coverage. Explain fail-fast: cheap checks first so expensive checks are not wasted on code that fails basic checks. Mention parallel vs sequential jobs (`needs:`) and the artifact upload for debugging failing tests. Address the `--cov-fail-under` gate. A senior answer discusses the two-layer enforcement model: pre-commit hooks for instant local feedback, CI for team-wide enforcement.

---

## Related Notes

- [[github-actions-basics|GitHub Actions Basics]]
- [[github-actions-python|GitHub Actions for Python]]
- [[cd-docker|CD with Docker]]
- [[pre-commit|Pre-commit Hooks]]
- [[pytest|Pytest]]
