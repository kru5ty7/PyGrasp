---
title: 06 - CI/CD Design Question Bank
description: "Platform-engineering interview questions on CI/CD design - secure pipeline architecture, secrets handling, canary vs blue-green vs rolling deployments with automated rollback, and running a pipeline as a product consumed by hundreds of teams."
tags: [ci-cd, pipelines, canary, blue-green, secrets, deployment-strategies, interview-prep, tooling, layer-9]
status: draft
difficulty: advanced
layer: 9
domain: tooling
created: 2026-07-06
---

# CI/CD Design Question Bank

> Interview prep — Platform Engineering. The step up from application-team CI/CD to platform CI/CD: pipelines built *for your own app* vs pipelines built *as a product* for hundreds of teams — templates, golden paths, guardrails, and managed rollout of changes to the pipeline itself.

---

## Secure Pipeline Design

**Q: Design a secure CI/CD pipeline for a team that has none — stages, gates, secrets, artifact signing, rollback.**

Answer frame: stages in order — lint/static analysis → unit tests → SAST + dependency scanning → build image → image vulnerability scan → sign artifact → deploy to staging → integration/smoke tests → gated promotion to prod → post-deploy verification with automated rollback. Cross-cutting: least-privilege deploy roles per environment, immutable versioned artifacts (build once, promote the same artifact), and every promotion logged for audit. Build on [[github-actions-basics|GitHub Actions Basics]] and [[ci-testing-pipeline|CI Testing Pipeline]]; security detail in [[pipeline-security-compliance|Pipeline Security and Compliance]].

**Q: How do you prevent secrets leaking into pipelines and logs?**

Answer frame: secrets injected at runtime from a manager (SSM Parameter Store / Secrets Manager / Vault) — never in repo, image layers, or plaintext pipeline variables ([[secret-management|Secret Management]], [[secrets-in-python|Handling Secrets in Python]]). Platform-side controls: log masking, short-lived OIDC-federated credentials instead of long-lived keys, per-pipeline scoped roles, secret scanning as a pre-commit and CI gate, and rotation without pipeline redefinition.

---

## Deployment Strategies

**Q: Canary vs blue-green vs rolling — trade-offs, and automating the rollback decision.**

Answer frame:
- **Rolling**: replace instances gradually; cheap, no extra capacity, but mixed versions serve traffic and rollback is a re-roll ([[kubernetes-deployments|Kubernetes Deployments]]).
- **Blue-green**: full parallel environment, instant cutover and instant rollback; costs 2x capacity; watch for shared-state migrations that can't flip back.
- **Canary**: small traffic slice to the new version, watch error rate/latency against the baseline, promote or roll back on the numbers; most operationally demanding — it requires real observability ([[metrics-and-monitoring|Metrics and Monitoring]]).

Automated rollback = defining the health signal up front (error rate, latency percentile, business metric), a bake window, and a controller that reverts without a human when thresholds break. A concrete ECS/EKS canary + health-check-driven rollback story is the strongest form of this answer ([[ecs|ECS]], [[cd-docker|CD with Docker]]).

---

## Pipeline as a Product

**Q: Build *one* pipeline template consumed by hundreds of teams. How do you roll out a breaking change to it?**

Answer frame: treat the template as a versioned product — teams pin a major version; breaking changes ship as a new major with migration notes, a deprecation window, and telemetry on who is still on the old version. Golden path defaults with escape hatches; guardrails (required security stages) not overridable by consumers. Rollout: canary the template change itself on a few volunteer teams before fleet-wide default. This is the same discipline as module versioning in [[terraform-iac-questions|Terraform and IaC Question Bank]] — a templated DAG/pipeline generator you have actually shipped is the best bridge story.

**Q: Design ephemeral on-demand environments spun from a developer portal.**

Answer frame: portal/API request → provisioner (IaC) → isolated namespace-per-env (cheap, fast) or account-per-env (strong isolation) → seeded synthetic test data → smoke tests on spin-up → TTL-based teardown + cost controls → audit log of who spun what. Gate carefully what data an ephemeral env may touch — never production data without masking; policy checks before any production-like access ([[pipeline-security-compliance|Pipeline Security and Compliance]]).

---

## Gap-Probe

**Q: "Have you used Harness?"** — if the honest answer is no: say no, then show you've read the concepts — pipelines, delegates (in-cluster workers executing pipeline steps), OPA policy enforcement, and built-in canary/blue-green verification that automates the rollback decision — and map each onto what you've built in GitHub Actions ([[github-actions-python|GitHub Actions for Python]]).

---

## Related Notes

- [[github-actions-basics|GitHub Actions Basics]]
- [[ci-testing-pipeline|CI Testing Pipeline]]
- [[cd-docker|CD with Docker]]
- [[semantic-versioning|Semantic Versioning]]
- [[secret-management|Secret Management]]
- [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [[pipeline-security-compliance|Pipeline Security and Compliance]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
