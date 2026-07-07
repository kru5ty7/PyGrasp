---
title: 01 - Terraform and IaC Question Bank
description: "Platform-engineering interview questions on Terraform and Infrastructure as Code - state management and locking, reusable module design, drift and unexpected destroys, import, workspaces, and policy-as-code - with answer frames and honest gap-probe handling."
tags: [terraform, iac, infrastructure-as-code, state, modules, policy-as-code, interview-prep, tooling, layer-9]
status: draft
difficulty: advanced
layer: 9
domain: tooling
created: 2026-07-06
---

# Terraform and IaC Question Bank

> Interview prep — Platform Engineering. The platform-team bar is higher than "I ran terraform apply": it is *authoring reusable modules other teams consume* — state management, versioning, drift handling, and policy-as-code. At a bank, "repeatable, auditable" IaC is the point: every change reviewable, every apply traceable.

---

## State

**Q: How does Terraform state work? Remote state, locking, failure modes of shared state.**

Answer frame: state is Terraform's record binding config to real resource IDs — without it Terraform cannot know what it manages. Local state does not scale past one person; remote state (e.g. S3 backend) with locking (DynamoDB, or S3 native locking) prevents two concurrent applies corrupting each other. Failure modes worth naming: stale/orphaned locks after a killed run (`terraform force-unlock` — carefully), state drifted from reality, secrets stored in state (state files must be treated as sensitive and access-controlled), and a lost state file (recoverable only by re-importing everything). Platform answer: state per team/environment with narrow IAM on the backend — blast-radius control, same instinct as [[iam-least-privilege|Principle of Least Privilege]].

---

## Module Design

**Q: Design a reusable module for other teams — inputs, outputs, versioning, examples.**

Answer frame: small variable surface with safe defaults (make the golden path the easy path), typed variables with validation, outputs that downstream modules actually need, an `examples/` directory that doubles as test fixture, semantic versioning with tagged releases so consumers pin versions ([[semantic-versioning|Semantic Versioning]]), and a documented upgrade path for breaking changes. The platform-scale question behind it: how do a hundred consuming teams upgrade when you ship a breaking change? (Answer: version pinning + deprecation window + announcements, never in-place mutation of a published version.)

---

## Drift and Surprises

**Q: `terraform plan` shows an unexpected destroy — what now? How do you handle drift?**

Answer frame: **stop — never apply an unexplained destroy.** Read the plan to find why: manual console change (drift), provider upgrade changing resource semantics, a rename Terraform sees as destroy-and-create (fix with `moved` blocks or `terraform state mv`). For drift: `terraform plan -refresh-only` to see reality vs state, then either codify the manual change or revert it. The auditable-infrastructure answer: drift should be detected continuously (scheduled plan in CI) and console access to managed resources should be read-only.

**Q: `terraform import`? Workspaces? When would you *not* use workspaces?**

Answer frame: `import` adopts an existing resource into state (you still write the matching config). Workspaces give multiple states from one config directory — fine for small variations, wrong for real environment separation: prod and dev should differ in backend, account, and permissions, which workspaces do not give you. Prefer separate root configurations (or separate state files/backends) per environment.

---

## Policy-as-Code and Auditability

**Q: How do you make infrastructure changes auditable and policy-compliant?**

Answer frame: everything through version-controlled code + PR review (no console changes), plan output attached to the change record, applies run by CI with a scoped role (not personal credentials), and policy-as-code gates — Sentinel (Terraform Enterprise) or OPA — rejecting non-compliant plans before apply (e.g. "no public S3 buckets", "all resources tagged"). This is compliance as a built-in platform capability rather than per-team burden — see [[pipeline-security-compliance|Pipeline Security and Compliance]] for the regulatory framing.

---

## Gap-Probes

- **"Used Terraform Enterprise/Cloud?"** — answer honestly; know the concepts (remote runs, private module registry, Sentinel policies) well enough to map them onto open-source Terraform experience.
- **"Written policy-as-code (Sentinel/OPA)?"** — if no, say no, then demonstrate you understand what it is for (pre-apply compliance gates) and bridge to related guardrail work you have done.
- **"Ansible experience?"** — if none, say so; know its position (configuration management of existing machines, agentless over SSH, procedural playbooks) vs Terraform's (declarative provisioning of infrastructure lifecycle), and that they compose rather than compete.

If your Terraform experience is application-team modules you maintained yourself, say that plainly and pivot to how fast you deepen — inflated module-registry claims collapse under the state-management follow-ups above.

---

## Related Notes

- [[iam-least-privilege|Principle of Least Privilege]]
- [[semantic-versioning|Semantic Versioning]]
- [[cicd-design-questions|CI/CD Design Question Bank]]
- [[pipeline-security-compliance|Pipeline Security and Compliance]]
- [[aws-platform-questions|AWS Platform Engineering Question Bank]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
