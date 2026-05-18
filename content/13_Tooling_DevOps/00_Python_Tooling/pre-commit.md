---
title: 06 - Pre-commit Hooks
description: "Pre-commit is a framework that runs configured hooks automatically before each git commit, catching linting errors, formatting issues, and test failures at the source before they enter the repository."
tags: [pre-commit, git-hooks, automation, linting, ci-enforcement, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Pre-commit Hooks

> Pre-commit is a framework for managing and running git hooks  -  scripts that execute automatically at specific points in the git workflow, most commonly right before a commit is recorded, to enforce code quality standards before bad code enters version control.

---

## Quick Reference

**Core idea:**
- `pre-commit install`  -  installs the hooks into `.git/hooks/pre-commit` (run once per clone)
- `.pre-commit-config.yaml`  -  configuration file listing which hooks to run and from where
- `pre-commit run --all-files`  -  run all hooks against every file (useful for initial setup or CI)
- Hooks run only on staged files by default  -  fast feedback on the specific diff
- `pre-commit autoupdate`  -  updates hook versions to the latest tagged releases
- A failing hook blocks the commit and leaves the repository unchanged

**Tricky points:**
- `pre-commit install` must be run by each developer after cloning  -  it is not automatic; adding it to `Makefile` targets or onboarding docs helps
- Hooks that auto-fix files (like Ruff with `--fix`) will modify and unstage the file  -  the developer must re-stage the fixed files and recommit
- `SKIP=ruff git commit -m "..."` skips a specific hook by name when genuinely needed
- Hook versions in `.pre-commit-config.yaml` are pinned by `rev:`  -  out-of-date hooks can have bugs or miss rules; run `pre-commit autoupdate` periodically
- In CI, run `pre-commit run --all-files` rather than relying on the commit hook  -  CI may not have `pre-commit install` run

---

## What It Is

Git hooks are shell scripts that git executes at defined points in the version control workflow: before a commit, after a commit, before a push, and so on. The `pre-commit` hook  -  a script at `.git/hooks/pre-commit`  -  runs before git records the commit. If this script exits with a non-zero code, git aborts the commit. This mechanism exists in git itself and requires no additional tools. The problem is that `.git/hooks/` is not version-controlled  -  hooks written directly in this directory are not shared with teammates and are not reproducible across machines.

The `pre-commit` framework (the Python package, not the git hook mechanism itself) solves this by treating hook configuration as code. The `.pre-commit-config.yaml` file lists what hooks to run and from which sources, is committed to the repository alongside the code, and is identical for all developers and CI systems. When a developer runs `pre-commit install`, the framework writes a generated script to `.git/hooks/pre-commit` that reads the config and delegates to the configured hooks. The actual hook implementations are stored in a separate cache, downloaded and installed the first time each hook runs.

The conceptual value is shifting quality enforcement left. Without pre-commit hooks, quality issues are caught in CI  -  minutes or hours after the developer pushed. With pre-commit hooks, they are caught in milliseconds, before the commit is even created. The developer is still at their keyboard, the context is fresh, and fixing the issue is trivial. Issues that escape to CI require switching context, finding the failed build, reading logs, and re-pushing.

---

## How It Actually Works

A `.pre-commit-config.yaml` file defines a list of repos, each containing a list of hooks:

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.4.4
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-merge-conflict

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.10.0
    hooks:
      - id: mypy
        additional_dependencies: [types-requests]
```

Each `repo` entry points to a git repository containing hook definitions. The `rev` field pins an exact git tag or commit hash. When `pre-commit install` runs, the framework clones the hook repos into a local cache (`~/.cache/pre-commit/`) and installs them in isolated environments. Hooks from Python repos get their own virtualenvs  -  they do not interact with the project's virtualenv.

The execution model for a commit:
1. Developer runs `git commit -m "message"`
2. git executes `.git/hooks/pre-commit`
3. The pre-commit framework determines which files are staged
4. For each configured hook, it runs the hook against the staged files (or all files if the hook is not file-aware)
5. If any hook exits non-zero, the commit is aborted and the output is shown
6. The developer fixes the issues, re-stages the files, and re-runs `git commit`

To run hooks in CI without a real commit:

```bash
# In GitHub Actions or any CI
pip install pre-commit
pre-commit run --all-files
```

This runs every hook against every tracked file and exits non-zero if any hook fails  -  providing the same enforcement as the local hook but in CI.

---

## How It Connects

Ruff and Black are the most commonly configured hooks  -  their hook IDs (`ruff`, `ruff-format`, `black`) are what populate the `hooks:` section of `.pre-commit-config.yaml`.

[[ruff|Ruff]]

[[black|Black]]

In a complete CI/CD pipeline, the pre-commit check is typically one step in the full CI pipeline  -  it runs the same hooks that developers run locally, ensuring consistency.

[[ci-testing-pipeline|CI Testing Pipeline]]

---

## Common Misconceptions

Misconception 1: "Pre-commit hooks are enforced on all contributors automatically."
Reality: `pre-commit install` must be run manually by each developer after cloning the repository. git does not run `pre-commit install` automatically. The `.pre-commit-config.yaml` is version-controlled, but it only activates when a developer explicitly installs the hooks. This is why CI enforcement with `pre-commit run --all-files` is essential  -  it catches commits where hooks were not installed.

Misconception 2: "If a hook modifies a file, the commit continues with the modification."
Reality: If a hook modifies a file (like `ruff --fix` fixing an import), the modified file is now different from what was staged. The commit is aborted, and the developer sees the modified file in their working directory. They must `git add` the fixed file and run `git commit` again. This is intentional  -  the developer should review automated changes before committing them.

Misconception 3: "Pre-commit hooks slow down every commit significantly."
Reality: Hooks run only on staged files by default, and tools like Ruff are fast enough that even a large staged diff runs in under a second. The first time a hook runs, there is a one-time setup cost to download and install the hook environment. Subsequent runs use the cache and are fast. The perceived slowness is usually the first run or hooks that invoke slow tools like mypy on large codebases.

---

## Why It Matters in Practice

Teams that enforce pre-commit hooks in CI (not just locally) gain a meaningful guarantee: every commit in the main branch has passed the quality checks. This changes the meaning of code review  -  reviewers can trust that any PR that has passed CI has already been linted, formatted, and had basic checks applied. The review focuses on design, logic, and correctness rather than style.

For open source projects, pre-commit hooks with a CI check lower the standard for contribution quality. Contributors who are unfamiliar with the project's style guide can run `pre-commit run --all-files` before submitting a PR and have the automated tools fix what they can, leaving only genuine logic issues for the maintainers to review.

---

## Interview Angle

Common question forms:
- "How do you enforce code quality standards in a team Python project?"
- "What are git hooks and how do you use them?"

Answer frame:
Describe the two-layer enforcement model: pre-commit hooks catch issues locally (before commit), CI enforces the same checks on every push (catching commits where hooks were skipped). Explain `.pre-commit-config.yaml` as the version-controlled hook configuration. Mention common hooks: Ruff for linting and formatting, check-yaml and trailing-whitespace for basics, mypy for type checking. Note that hooks that auto-fix require a re-stage.

---

## Related Notes

- [[ruff|Ruff]]
- [[black|Black]]
- [[isort|isort]]
- [[ci-testing-pipeline|CI Testing Pipeline]]
- [[poetry|Poetry]]
