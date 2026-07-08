---
title: 07 - CI/CD Overview
description: "CI merges and verifies code continuously; Continuous Delivery keeps every build deployable with a human gate; Continuous Deployment removes the gate - plus artifact versioning, rollback strategies, and how Jenkins/GitLab CI/CircleCI compare to GitHub Actions and Harness."
tags: [ci-cd, continuous-integration, continuous-delivery, continuous-deployment, artifacts, rollback, jenkins, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-07-07
---

# CI/CD Overview

> The three terms are distinct and interviewers check: CI = integrate and verify on every change; Continuous Delivery = every green build *could* ship, a human decides; Continuous Deployment = every green build *does* ship, no human in the loop.

---

## Quick Reference

**Core idea:**
- **CI (Continuous Integration)**: merge small changes frequently; every merge triggers automated build + tests - integration pain surfaces in minutes, not at release time
- **Continuous Delivery**: the pipeline keeps a deployable artifact ready at all times; deployment is a *decision*, not a project
- **Continuous Deployment**: the decision is automated too - green pipeline → production, gated by automated checks only
- **Pipeline stages** (canonical order): lint/static analysis → unit tests → security scans (SAST, dependencies) → build artifact → integration tests → deploy staging → deploy prod
- **Artifacts**: build *once*, version immutably (semver or git SHA), promote the *same* artifact through environments - never rebuild per environment
- **Rollback strategies**: redeploy previous artifact version; blue-green traffic flip; canary abort; `helm rollback` / `kubectl rollout undo` - plus roll-*forward* when backward migration is impossible
- **Tool landscape**: Jenkins (self-hosted, plugin-heavy, aging but everywhere in enterprises), GitLab CI (integrated with GitLab, YAML), CircleCI (SaaS, fast), GitHub Actions (repo-native, marketplace), Harness (CD-focused, verification built in)

**Tricky points:**
- "We have CI/CD" often means "we have a build server" - the distinctions above are about *practices* (merge frequency, deployability), not tools
- Rebuilding an artifact for prod after testing a staging build breaks the whole promotion model - what ships is not what was tested
- Rollback assumes backward-compatible database schemas; an irreversible migration turns rollback into roll-forward whether you like it or not
- Continuous Deployment is a maturity outcome (test confidence + observability + fast rollback), not a config flag

---

## What It Is

CI attacks integration risk with frequency. When branches live for weeks, merging is an event with its own name ("integration hell"); when everyone merges small changes daily and every merge runs the full verification suite, integration problems are small, fresh, and attributable. The practice is the point - the server (Jenkins, Actions) just automates the verification.

The Delivery/Deployment distinction is about where human judgment sits. Continuous Delivery engineers the *capability*: trunk always green, artifacts versioned and ready, deployment a button-press - and the business chooses when to press. Continuous Deployment removes the button: merged means shipped, typically minutes later. Most regulated environments (banks included) run Delivery with controlled approval gates - change control and separation of duties are compliance requirements ([[pipeline-security-compliance|Pipeline Security and Compliance]]) - while pushing automation as close to the gate as possible.

Artifact discipline is the load-bearing detail. The pipeline builds one immutable, versioned artifact - a container image tagged with the git SHA, a wheel with a semver - and *promotes* that identical artifact: staging tests it, prod runs it. Rebuilding per environment reintroduces the exact drift CI exists to kill (different dependency resolution, different base image, different day). Immutable artifacts also make rollback honest: redeploying `v1.4.2` means bit-for-bit the thing that ran before.

The tool landscape matters at awareness level. Jenkins: self-hosted, infinitely pluggable, the incumbent in enterprises - NAB's NEF heritage includes the Jenkins Templating Engine for standardized pipelines - but plugin sprawl and Groovy pipelines are real maintenance costs. GitLab CI and CircleCI: YAML-native, clean, integrated/SaaS respectively. GitHub Actions: repo-native, huge marketplace, the default for GitHub-hosted code ([[github-actions-basics|GitHub Actions Basics]]). Harness: continuous-*delivery* focused, with deployment verification and rollback automation as first-class features ([[harness-concepts|Harness Concepts]]). The pattern worth naming: CI is commoditized; the differentiation now is in deployment safety and pipeline-as-product ergonomics.

---

## How It Actually Works

A minimal honest pipeline, stage by stage:

```
push → lint + typecheck        (seconds; fail fast)
     → unit tests              (minutes; no external deps)
     → SAST + dependency scan  (security gates - see pipeline security note)
     → build image, tag :gitsha, push to registry     ← the artifact is born
     → integration tests against the built image
     → deploy to staging (the same image)
     → smoke tests
     → [approval gate - Continuous Delivery stops here]
     → deploy to prod (the same image, canary/rolling)
     → post-deploy verification → auto-rollback on failure
```

Rollback decision tree: config-only issue → revert config; bad release, compatible schema → redeploy previous version (fast, safe); bad release, migrated schema → roll forward with a fix (rollback would corrupt); infrastructure issue → neither, fix the platform.

---

## How It Connects

Deployment strategies (canary, blue-green) and pipeline-as-a-product design build on these foundations.

[[cicd-design-questions|CI/CD Design Question Bank]]

The concrete GitHub Actions implementation of these stages already exists in the vault.

[[github-actions-basics|GitHub Actions Basics]], [[ci-testing-pipeline|CI Testing Pipeline]], [[cd-docker|CD with Docker]]

Artifact versioning discipline is semver applied to builds.

[[semantic-versioning|Semantic Versioning]]

GitOps inverts the deploy half of this model - pull instead of push.

[[gitops|GitOps]]

---

## Common Misconceptions

Misconception 1: "CI/CD is the tool (Jenkins/Actions)."
Reality: The practices are merge frequency, automated verification, and permanent deployability. A team merging monthly with a beautiful pipeline has expensive automation, not CI.

Misconception 2: "Continuous Deployment is Continuous Delivery done right."
Reality: They're different risk postures. Regulated environments legitimately choose Delivery - the engineering goal is making the human gate the *only* manual step, not removing it against policy.

Misconception 3: "Rollback is always available."
Reality: Rollback is a *designed* property: immutable prior artifacts, backward-compatible schema changes (expand-migrate-contract), and config versioning. Skip the design and your only option under fire is roll-forward.

---

## Interview Angle

Common question forms:
- "Explain CI vs Continuous Delivery vs Continuous Deployment."
- "How do you version and promote artifacts?"
- "Your deploy is bad - walk me through the rollback."

Answer frame:
Three-tier definition with the human-gate framing; place a bank in Delivery-with-gates and say why (change control, separation of duties). Artifacts: build once, tag immutably, promote the same bits; rollback = redeploy previous tag, *if* schemas were kept compatible - name expand/contract migrations to show you've done it. Tool comparisons: one sentence each, then pivot to practices over tools.

---

## Related Notes

- [[github-actions-basics|GitHub Actions Basics]]
- [[ci-testing-pipeline|CI Testing Pipeline]]
- [[cicd-design-questions|CI/CD Design Question Bank]]
- [[semantic-versioning|Semantic Versioning]]
- [[gitops|GitOps]]
- [[harness-concepts|Harness Concepts]]
