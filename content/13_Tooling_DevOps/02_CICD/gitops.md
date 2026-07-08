---
title: 08 - GitOps
description: "GitOps makes git the single source of truth for deployed state - a controller (ArgoCD, Flux) running in the cluster continuously pulls and reconciles reality to match the repo, replacing push-based deploy steps with declarative sync."
tags: [gitops, argocd, flux, pull-based, reconciliation, ci-cd, kubernetes, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-07
---

# GitOps

> GitOps applies the Kubernetes reconciliation model to deployment itself: desired state lives in git, a controller in the cluster continuously drives actual state toward it. Deploying becomes merging a pull request; drift becomes a detected condition, not a mystery.

---

## Quick Reference

**Core idea:**
- **The model**: a git repo holds the declarative desired state (manifests/Helm values); an in-cluster controller watches the repo and reconciles the cluster to match - continuously, not just on deploy events
- **Pull vs push**: traditional CI/CD *pushes* (pipeline runs `kubectl apply`/`helm upgrade` with cluster credentials); GitOps *pulls* (the cluster fetches its own desired state - no external system holds cluster write access)
- **ArgoCD**: the dominant implementation - `Application` CRD maps repo path → cluster/namespace; UI for sync status/diff/history; app-of-apps pattern for fleets
- **Flux**: the CNCF alternative - same model, more toolkit-style (source/kustomize/helm controllers), no default UI
- **Repo layout**: app code repo (CI builds images) separate from *config repo* (image tags + env overlays); CI's last step is a commit to the config repo, not a deploy
- **Rollback** = `git revert` - the controller converges the cluster back; every deploy is a commit with author, review, and timestamp - a built-in audit log

**Tricky points:**
- CI still exists - GitOps replaces the *deploy* step, not build/test; the pipeline's output becomes a git commit ("bump image to v1.4.3")
- Manual `kubectl` changes get flagged (or auto-reverted) as drift - by design; console cowboys and GitOps don't coexist
- Secrets can't sit plaintext in the config repo - pair with sealed-secrets, SOPS, or External Secrets Operator
- Sync is eventually consistent - a merged PR deploys when the controller syncs (seconds to minutes), which changes how you think about "deploy finished"

**The trade-off, honestly:**
- Pull wins: cluster credentials never leave the cluster (big win at a bank); drift detection; audit-by-git; disaster recovery = point controller at repo
- Push wins: simpler mental model; imperative steps (migrations, smoke tests, canary analysis) fit naturally in a pipeline; no extra controller to run - orchestrating those around GitOps needs extra machinery (hooks, Argo Rollouts)

---

## What It Is

Traditional deployment treats the pipeline as the actor: after tests pass, a job authenticates to the cluster and applies changes. That works, but it scatters cluster write-credentials across CI systems, leaves no continuously-verified record of what *should* be running, and drifts silently the moment anyone hotfixes with `kubectl edit`.

GitOps inverts the direction. The config repo declares what every environment should run - manifests, Helm values, image tags, per-env overlays. In the cluster, ArgoCD or Flux polls that repo and reconciles: compute diff between declared and actual, apply the difference, repeat forever. The consequences fall out mechanically. Deployment = PR merge (reviewed, attributed, timestamped - an audit trail regulators recognize). Rollback = revert commit. Drift = detected within one sync interval and either alerted or auto-corrected. Cluster credentials = never exported anywhere, because nothing outside the cluster deploys *into* it - the security property that makes GitOps the platform-engineering default answer, especially in banks.

The CI pipeline doesn't disappear; it gets a cleaner boundary. Code repo CI does what it always did - test, build, scan, push the image - but its final act is a commit to the config repo bumping the image tag. The controller takes it from there. This separation (app repo / config repo) also cleanly separates *who* may change code vs who may promote to prod: config-repo branch protection is the deployment approval gate.

ArgoCD is what you'll most likely meet: applications are CRDs ([[kubernetes-platform-extensions|Kubernetes Platform Extensions]]) pointing a repo path at a destination namespace, a UI shows sync state and live-vs-desired diffs, and the app-of-apps pattern lets a platform team declare a whole fleet of team applications as - naturally - more git-tracked resources. Flux does the same job as a set of composable controllers, favored where UI-less automation is preferred. For progressive delivery (canary analysis, automated rollback), both pair with Argo Rollouts or Flagger, which close the gap push-pipelines fill with imperative verify steps.

---

## How It Actually Works

```yaml
# ArgoCD Application: "this repo path defines prod/my-api"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: my-api-prod, namespace: argocd }
spec:
  source:
    repoURL: https://github.com/org/platform-config
    path: apps/my-api/overlays/prod
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: my-api
  syncPolicy:
    automated: { prune: true, selfHeal: true }   # auto-sync + revert manual drift
```

The full flow:

```
code repo: push → CI: test, build image v1.4.3, scan, push to registry
                → CI commits "bump my-api to v1.4.3" to config repo (staging overlay)
config repo: PR staging→prod overlay, reviewed, merged
cluster: ArgoCD detects new desired state → sync → health checks → Synced/Healthy
rollback: git revert on config repo → controller converges back
```

`selfHeal: true` is the strictness dial: with it on, a manual `kubectl scale` is reverted within the sync window - the repo is not *a* source of truth but *the* source.

---

## How It Connects

GitOps assumes the CI foundations - artifact discipline especially - and replaces the deploy stage.

[[cicd-overview|CI/CD Overview]], [[cicd-design-questions|CI/CD Design Question Bank]]

The controller-reconciliation mechanics are pure Kubernetes; ArgoCD is CRDs + a controller.

[[kubernetes-basics|Kubernetes Basics]], [[kubernetes-platform-extensions|Kubernetes Platform Extensions]]

Git-as-audit-log and no-exported-credentials are compliance properties.

[[pipeline-security-compliance|Pipeline Security and Compliance]]

---

## Common Misconceptions

Misconception 1: "GitOps replaces CI/CD."
Reality: It replaces the deploy leg. Build/test/scan pipelines remain; their output changes from "apply to cluster" to "commit to config repo."

Misconception 2: "We keep manifests in git, so we do GitOps."
Reality: Without a reconciling controller, that's version-controlled push deployment - fine, but it has none of the properties (drift correction, pull-based credentials, continuous convergence) that define GitOps.

Misconception 3: "Pull-based is strictly better."
Reality: Push pipelines express imperative sequences (migrate → deploy → smoke test → shift traffic) naturally; GitOps needs hooks/Rollouts/Flagger for the same choreography, and adds a controller to operate. The honest answer is a trade-off, chosen pull-ward as fleet size and credential-security requirements grow.

---

## Interview Angle

Common question forms:
- "What is GitOps and what problem do ArgoCD/Flux solve?"
- "Pull vs push deployment - actual trade-offs?"
- "How does rollback work in a GitOps setup?"

Answer frame:
Define by the two properties: git as sole source of truth + in-cluster continuous reconciliation. Name the wins in platform terms - credentials never leave the cluster, drift is detected, every change is a reviewed commit (audit for free) - then give the honest costs (imperative steps need extra machinery, eventual consistency, one more controller to run). Rollback = git revert + convergence, with the same schema-compatibility caveat as any rollback.

---

## Related Notes

- [[cicd-overview|CI/CD Overview]]
- [[cicd-design-questions|CI/CD Design Question Bank]]
- [[kubernetes-platform-extensions|Kubernetes Platform Extensions]]
- [[pipeline-security-compliance|Pipeline Security and Compliance]]
- [[harness-concepts|Harness Concepts]]
