---
title: 01 - GitHub Actions Basics
description: "GitHub Actions is a CI/CD platform where workflows are YAML files in .github/workflows/ that define event triggers, jobs running on GitHub-hosted runners, and sequential steps executing shell commands or reusable actions."
tags: [github-actions, ci-cd, workflows, runners, jobs, steps, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# GitHub Actions Basics

> GitHub Actions is a CI/CD platform built into GitHub  -  workflows are YAML files triggered by repository events, defining jobs that run on virtual machines (runners), each job containing a sequence of steps that execute commands or call reusable actions.

---

## Quick Reference

**Core idea:**
- Workflows live in `.github/workflows/*.yml`  -  any `.yml` file there is a workflow
- Triggers (`on:`) define when the workflow runs: `push`, `pull_request`, `schedule`, `workflow_dispatch`
- `jobs:` contains one or more jobs; each job runs on its own fresh runner VM
- `steps:` within a job run sequentially; a failed step stops the job
- `uses: actions/checkout@v4`  -  the most common first step: clones the repository into the runner
- Jobs run in parallel by default; use `needs: [job-name]` to declare sequential dependencies

**Tricky points:**
- Each job runs on a completely fresh runner VM  -  files created in one job are not available to another job without using artifacts
- `steps` share the same runner filesystem; one step can pass state to the next via files or `$GITHUB_OUTPUT`
- `GITHUB_TOKEN` is automatically available as a secret in every workflow  -  it has repo-scoped permissions for GitHub API operations
- `on: push` triggers on all branches by default; use `branches: [main]` to restrict to specific branches
- `workflow_dispatch:` adds a manual "Run workflow" button to the GitHub Actions UI  -  useful for deployment workflows

---

## What It Is

GitHub Actions is the CI/CD platform that executes automated workflows in response to repository events. Every time a developer pushes code, opens a pull request, or creates a release tag, GitHub Actions can run a set of jobs  -  linting the code, running tests, building a Docker image, or deploying to production. These workflows are defined as YAML files in the `.github/workflows/` directory of the repository, making them version-controlled alongside the code they test and deploy.

The platform is event-driven. A workflow file specifies one or more triggering events  -  a push to any branch, a pull request targeting `main`, a cron schedule, or a manual button click. When the event occurs, GitHub queues the workflow for execution on a runner  -  a virtual machine managed by GitHub (or self-hosted by the organization) that clones the repository and executes the workflow's jobs.

The key mental model is: events trigger workflows; workflows contain jobs; jobs run on runners; jobs contain steps; steps run commands or call actions. Each layer of this hierarchy is independently configurable. An action is a reusable, versioned unit of work  -  `actions/checkout@v4` clones the repository, `actions/setup-python@v5` installs Python, `actions/cache@v4` caches dependencies. Actions abstract common setup operations so workflow authors focus on the project-specific commands.

---

## How It Actually Works

A minimal Python workflow:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    name: Run tests
    runs-on: ubuntu-latest      # GitHub-hosted Ubuntu runner

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install dependencies
        run: |
          pip install -r requirements.txt

      - name: Run tests
        run: |
          pytest tests/ -v
```

Key structural elements:

**Triggers (`on:`):**
```yaml
on:
  push:
    branches: [main, develop]
  pull_request:              # Runs on every PR
  schedule:
    - cron: "0 9 * * 1"     # Every Monday at 9 AM UTC
  workflow_dispatch:         # Manual trigger via GitHub UI
    inputs:
      environment:
        description: "Target environment"
        required: true
        default: "staging"
```

**Multi-job workflow with dependencies:**
```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ruff && ruff check .

  test:
    runs-on: ubuntu-latest
    needs: lint               # test only runs if lint passes
    steps:
      - uses: actions/checkout@v4
      - run: pytest tests/

  deploy:
    runs-on: ubuntu-latest
    needs: [lint, test]       # both must pass
    if: github.ref == 'refs/heads/main'  # only on main branch
    steps:
      - run: echo "Deploying..."
```

**Environment variables and secrets:**
```yaml
env:
  ENVIRONMENT: production     # Workflow-level env var

jobs:
  deploy:
    steps:
      - run: echo "API key is ${{ secrets.API_KEY }}"
        env:
          API_KEY: ${{ secrets.API_KEY }}   # Step-level; secrets are masked in logs
```

Secrets are stored in the repository or organization settings and referenced with `${{ secrets.SECRET_NAME }}`. Their values are masked in log output. `GITHUB_TOKEN` is automatically available without being added to secrets.

---

## How It Connects

The Python-specific workflow patterns  -  setup-python action, pip caching, matrix strategy  -  build directly on these basics.

[[github-actions-python|GitHub Actions for Python]]

A full CI pipeline structures jobs in a specific order (lint -> test -> build) for the fail-fast benefit.

[[ci-testing-pipeline|CI Testing Pipeline]]

The CD part of the pipeline (building and pushing Docker images) is a distinct phase that follows a successful CI run.

[[cd-docker|CD with Docker]]

---

## Common Misconceptions

Misconception 1: "Jobs in a workflow run sequentially by default."
Reality: Jobs run in parallel by default. This is a performance feature  -  lint, test, and security-scan can all run simultaneously. Use `needs:` to declare dependencies that force sequential execution when the output of one job is required by another.

Misconception 2: "Steps within a job run in separate processes and cannot share state."
Reality: Steps within the same job run sequentially on the same runner VM and share the filesystem and working directory. A file written by step 2 is available to step 3. Environment variables can be shared between steps by writing to `$GITHUB_ENV`. However, steps cannot share state with steps in a different job without using artifacts.

Misconception 3: "The `on: push` trigger fires only when code is pushed to the main branch."
Reality: `on: push` triggers on pushes to any branch unless restricted with `branches:`. This means every feature branch push triggers CI, which is usually desired (catch issues before merging) but can be surprising. Use `on: push: branches: [main]` to restrict to main, or `on: pull_request` to trigger on PR creation and update events.

---

## Why It Matters in Practice

GitHub Actions eliminates the need for separate CI infrastructure for most projects. It is tightly integrated with GitHub's pull request UI  -  workflow results appear inline on the PR, and required status checks can block merges until CI passes. This integration changes the development workflow: contributors see CI results within the PR interface, not in a separate CI dashboard, reducing context-switching.

The marketplace of pre-built actions (`actions/setup-python`, `aws-actions/configure-aws-credentials`, `docker/build-push-action`) means that common CI tasks have reusable, community-maintained implementations. A team setting up CI for a new project can compose a complete workflow from existing actions in under an hour.

---

## Interview Angle

Common question forms:
- "How would you set up CI for a Python project on GitHub?"
- "How do jobs and steps relate in GitHub Actions?"

Answer frame:
Describe the hierarchy: event -> workflow -> job -> step. Explain that jobs run in parallel by default, steps run sequentially within a job. Mention `needs:` for job dependencies, `uses:` for actions, `run:` for shell commands. Describe the common Python CI structure: checkout -> setup-python -> install dependencies -> lint -> test. Note that secrets are masked in logs and `GITHUB_TOKEN` is automatic.

---

## Related Notes

- [[github-actions-python|GitHub Actions for Python]]
- [[ci-testing-pipeline|CI Testing Pipeline]]
- [[cd-docker|CD with Docker]]
- [[pre-commit|Pre-commit Hooks]]
