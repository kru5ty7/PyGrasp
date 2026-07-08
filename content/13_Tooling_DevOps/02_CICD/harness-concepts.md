---
title: 09 - Harness Concepts
description: "Harness is a continuous-delivery platform where delegates (in-network worker agents) execute pipeline stages, OPA policies gate what pipelines may do, and continuous verification analyzes metrics/logs after deploy to automate the canary/blue-green rollback decision."
tags: [harness, ci-cd, delegates, opa, continuous-verification, canary, blue-green, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-07
---

# Harness Concepts

> Conceptual literacy note - the NAB JD names Harness twice. The mental model: Harness's control plane orchestrates, but *delegates* inside your network execute; policies gate pipelines as code; and its signature feature is automating the "is this deploy healthy?" judgment that GitHub Actions leaves to humans and scripts.

---

## Quick Reference

**Core idea:**
- **Pipelines → stages → steps**: same shape as any CD tool - a pipeline has stages (build, deploy-staging, deploy-prod), stages have steps; defined in UI or YAML, templatable org-wide
- **Delegates**: worker agents installed inside your infrastructure (typically as Kubernetes pods) that poll the Harness control plane for tasks and execute them locally - deploys, kubectl calls, artifact fetches
  - Why they exist: the SaaS control plane never needs inbound access or stored credentials for your clusters - the delegate connects *outbound* and uses in-cluster identity; the security model banks require
- **OPA policy gates**: Open Policy Agent (Rego) policies evaluated against pipeline/stage configuration at runtime - "prod deploys require an approval step," "only signed artifacts," "no deploy windows outside business hours"; non-compliant pipelines fail before acting
- **Continuous Verification (CV)**: after deploy, Harness pulls metrics/logs from your observability stack (Prometheus, CloudWatch, Datadog, ELK), compares the new version's behavior against baseline (ML-assisted), and **auto-rolls-back** on regression
- Canary and blue-green are first-class stage types: traffic-shift increments, verification between increments, rollback wiring - configuration, not scripting

**Tricky points:**
- Delegate ≈ self-hosted runner in GitHub Actions terms, but delegates are long-lived, identity-bearing, and *poll outbound* - no inbound firewall holes
- CV is only as good as the observability feeding it - no meaningful metrics, no meaningful verification ([[observability-questions|Observability Question Bank]])
- OPA here governs *pipelines* (the same engine that governs K8s admission and Terraform plans elsewhere - one policy language, three enforcement points)

**Mapping from GitHub Actions experience:**
- workflow YAML → pipeline/stage YAML; runner → delegate; marketplace action → step template
- environment protection rules → OPA policies (more expressive)
- "deploy then run smoke-test job, manually watch dashboards" → CV stage with automated baseline comparison and rollback

---

## What It Is

Harness positions itself where deployment risk lives - after the artifact exists. Its CI module is conventional; the differentiated pieces are the execution model (delegates), governance (OPA), and post-deploy judgment (Continuous Verification). Those three are what to be able to discuss.

The delegate model solves the problem every SaaS CD tool has at a bank: how does an external control plane deploy into a locked-down network without holding the keys? Harness's answer - an agent you install inside the boundary that polls outbound for work and executes with locally-scoped identity (a Kubernetes service account, an IAM role) - means no inbound connectivity, no cluster credentials stored in a vendor's SaaS, and per-environment delegates with per-environment permissions. It is the same architectural instinct as GitOps controllers pulling instead of pipelines pushing, arrived at from the vendor side.

OPA policy gates put pipeline governance in code. Rather than trusting teams to include the approval step or wiring checklists into wiki pages, platform teams write Rego policies the control plane evaluates whenever pipelines run or change: required approvals for prod, mandatory scan steps, artifact provenance rules, deployment windows. Pipelines violating policy don't run. The connective insight for interviews: this is the *third* appearance of the same pattern in the stack - policy-as-code gating Terraform plans (Sentinel/OPA), Kubernetes admission (Gatekeeper/Kyverno), and pipelines (Harness OPA). One idea, three enforcement points, all "compliance as platform capability."

Continuous Verification automates the judgment call that makes canaries actually work. A canary is only as good as the answer to "is the new version misbehaving?" - manually, that's an engineer staring at Grafana for twenty minutes. CV wires the pipeline to observability: define the health sources (Prometheus queries, log error patterns), and after each traffic increment Harness compares the canary population against the baseline population, flags regressions, and executes rollback without a human. That converts the strongest deployment-strategy answer ([[cicd-design-questions|CI/CD Design Question Bank]]) from "we watched health checks and rolled back" into a fully-automated loop - exactly the story the JD's "canary/blue-green verification" language points at.

---

## How It Actually Works

The shape of a Harness canary deployment (conceptually - YAML details vary):

```
Pipeline: my-api-prod
  Stage: Deploy (type: Deployment, strategy: Canary)
    Step: Canary Deployment      # 10% of pods on new version
    Step: Verify                 # CV: Prometheus error-rate + latency vs baseline, 10 min
    Step: Canary Deployment      # 50%
    Step: Verify
    Step: Rolling Update         # 100%
  Rollback: automatic on any Verify failure → previous artifact
Policy (OPA, evaluated on run):
  - deny if stage.type == "Deployment" && env == "prod" && !has_approval_step
  - deny if artifact.source not in approved_registries
```

Execution flow: pipeline triggers → control plane queues tasks → delegate (in your cluster, polling outbound) picks them up → executes kubectl/Helm operations with its service-account identity → streams results back → CV stage queries your metrics through the same delegate.

---

## How It Connects

The deployment strategies Harness automates are the question bank's canary/blue-green material.

[[cicd-design-questions|CI/CD Design Question Bank]]

CV consumes Prometheus-style metrics - observability as a deployment dependency.

[[observability-questions|Observability Question Bank]], [[prometheus-python|Prometheus with Python]]

OPA gating completes the policy-as-code triad with Sentinel and admission controllers.

[[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]], [[kubernetes-platform-extensions|Kubernetes Platform Extensions]]

Pull-based delegates share the credential philosophy of GitOps.

[[gitops|GitOps]]

---

## Common Misconceptions

Misconception 1: "Harness is Jenkins with a nicer UI."
Reality: The center of gravity differs - Jenkins is a general automation server you script; Harness is opinionated CD where verification, rollback, and governance are product features. The honest comparison is with Argo Rollouts + Gatekeeper + a pipeline tool, assembled.

Misconception 2: "The delegate is just a runner."
Reality: Runners execute arbitrary jobs; delegates are the *trust boundary* - outbound-only connectivity and locally-held identity are the reason a regulated org lets a SaaS orchestrate prod deploys at all.

Misconception 3: "Continuous Verification means running tests after deploy."
Reality: Smoke tests ask "does it respond?" CV asks "does its production behavior match baseline?" - statistical comparison of live metrics/logs between versions, which catches the regressions tests can't (latency drift, error-rate creep under real traffic).

---

## Interview Angle

Common question forms:
- "Have you used Harness?" (the honest-gap probe)
- "How would you automate the rollback decision for a canary?"
- "How do you govern what a hundred teams' pipelines are allowed to do?"

Answer frame:
Honesty first: concepts read, not production experience - then demonstrate the concepts unprompted. Delegates: outbound-polling in-network agents so credentials never leave the boundary. OPA: pipeline governance as code, third leg of the Sentinel/admission-controller pattern. CV: baseline-vs-canary metric comparison driving automated rollback - then bridge to the real story: "I built this loop manually with health checks and rollback on ECS/EKS; Harness productizes exactly that judgment."

---

## Related Notes

- [[cicd-overview|CI/CD Overview]]
- [[cicd-design-questions|CI/CD Design Question Bank]]
- [[gitops|GitOps]]
- [[observability-questions|Observability Question Bank]]
- [[kubernetes-platform-extensions|Kubernetes Platform Extensions]]
