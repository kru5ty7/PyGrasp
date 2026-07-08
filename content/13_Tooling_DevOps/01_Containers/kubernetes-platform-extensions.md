---
title: 16 - Kubernetes Platform Extensions
description: "CRDs extend the Kubernetes API with new resource types, Operators pair CRDs with controllers that encode operational knowledge, admission controllers enforce policy on every API request - plus managed-vs-self-managed trade-offs, network policies, and pod security."
tags: [kubernetes, k8s, crds, operators, admission-controllers, network-policies, eks, pod-security, tooling, layer-9]
status: draft
difficulty: advanced
layer: 9
domain: tooling
created: 2026-07-07
---

# Kubernetes Platform Extensions

> Kubernetes is less a container platform than a platform *for building platforms*: CRDs add nouns, controllers add reconciliation verbs, admission webhooks add law. Every serious internal developer platform is built from these three primitives.

---

## Quick Reference

**Core idea:**
- **CRD (Custom Resource Definition)**: registers a new resource type with the API server - after which `kubectl get prometheus` works like `kubectl get pods`, with storage in etcd and RBAC for free
- **Operator**: a CRD + custom controller that reconciles it - encoding human operational knowledge (provisioning, failover, backups, upgrades) as software; e.g. Prometheus Operator, database operators
- **Admission controllers**: intercept API requests after authn/authz, before etcd - **validating** webhooks reject ("no `:latest` tags"), **mutating** webhooks modify (inject sidecars, default resource limits); OPA Gatekeeper/Kyverno build policy engines on this
- **Managed (EKS/GKE/AKS) vs self-managed**: provider runs the control plane (etcd, API server, upgrades, HA); you still own everything from worker nodes up - "managed" ≠ "no operations"
- **NetworkPolicy**: default is all pods can talk to all pods; policies whitelist ingress/egress per pod selector - enforcement requires a supporting CNI
- **Pod Security Standards**: privileged / baseline / restricted profiles enforced per namespace - no root, no privilege escalation, no host mounts

**Tricky points:**
- A CRD without a controller is inert data - the controller's reconcile loop is what makes the resource *do* anything
- Admission webhooks sit in the API request path - a slow/down webhook can block all deployments (failure policy matters)
- NetworkPolicies are additive whitelists: once any policy selects a pod, everything not explicitly allowed is denied
- On EKS, the control plane is AWS's problem but node upgrades, addon compatibility, IRSA, and CNI limits are still yours

---

## What It Is

CRDs answer "how does the API itself get extended." Registering a CRD teaches the API server a new resource type - schema, validation, versions - and instantly inherits the machinery: etcd persistence, `kubectl` verbs, RBAC scoping, watch semantics. This is why the ecosystem converged on Kubernetes as a control plane for *everything*: cert-manager's `Certificate`, Argo's `Application`, Crossplane's cloud resources are all CRDs.

Operators complete the pattern. The reconciliation model - watch desired state, drive actual state toward it - is generic, so a custom controller can reconcile custom resources exactly the way the Deployment controller reconciles Deployments. An operator for PostgreSQL watches `PostgresCluster` objects and *does what a DBA would do*: provision replicas, configure replication, take backups, orchestrate failover, run version upgrades. That's the honest definition of the pattern: operational runbooks compiled into a control loop. For a platform team, operators are how "give every squad a database/monitoring stack/cert automation" becomes self-service.

Admission controllers are where the API server enforces policy on every request. After authentication and authorization but before persistence, the request passes through mutating webhooks (which may change it - inject a sidecar, add default limits, attach labels) then validating webhooks (which may reject it - disallow `:latest`, require non-root, enforce mandatory labels). This is the enforcement point for "compliant by default": teams don't opt into guardrails; the API server applies them. OPA Gatekeeper and Kyverno are the standard policy engines built on this hook - the same policy-as-code idea as Sentinel for Terraform, one layer down.

The managed-vs-self-managed question is really about which operational layers you shed. EKS runs the control plane - etcd durability, API server HA, control-plane upgrades - which removes the hardest 20%. Still yours: worker node lifecycle and AMI updates, cluster version upgrades (and API deprecations breaking your manifests), CNI/addon compatibility, RBAC and IAM integration, cost. Self-managing (kubeadm on EC2) is justified mainly by unusual compliance or topology requirements; the platform-interview answer is "managed control plane, because the differentiating work is above it."

NetworkPolicies and Pod Security Standards are the in-cluster security baseline. Default Kubernetes networking is flat - any pod can reach any pod, across namespaces. Policies invert that per selected pod: define allowed ingress/egress by namespace/pod selectors and ports, and everything else drops - contingent on a CNI that enforces (Calico, Cilium; the base AWS VPC CNI needs help). Pod Security Standards close the container escape hatches at admission: the `restricted` profile refuses privileged containers, root users, host network/filesystem access.

---

## How It Actually Works

```yaml
# NetworkPolicy: api pods accept traffic only from frontend, only on 8000
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: api-ingress, namespace: prod }
spec:
  podSelector: { matchLabels: { app: api } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: frontend } }
      ports:
        - { protocol: TCP, port: 8000 }
```

```bash
kubectl get crds                                  # what the API has been taught
kubectl api-resources | grep -v true              # non-namespaced + custom resources
kubectl label ns prod pod-security.kubernetes.io/enforce=restricted
```

The Prometheus Operator as the worked example: install it, and `ServiceMonitor` CRDs appear; teams declare "scrape my service" as a resource next to their Deployment; the operator rewrites Prometheus configuration automatically. Monitoring onboarding becomes a 10-line YAML file - the self-service pattern in miniature.

---

## How It Connects

Operators are the reconciliation model from the basics note, generalized to custom resources.

[[kubernetes-basics|Kubernetes Basics]]

Admission-webhook policy enforcement is the cluster-level sibling of pipeline policy gates.

[[pipeline-security-compliance|Pipeline Security and Compliance]], [[terraform-iac-questions|Terraform and IaC Question Bank]]

The Prometheus Operator/ServiceMonitor flow feeds the observability stack.

[[observability-questions|Observability Question Bank]], [[prometheus-python|Prometheus with Python]]

EKS-specifics (IRSA, VPC CNI) live in the AWS bank.

[[aws-platform-questions|AWS Platform Engineering Question Bank]]

---

## Common Misconceptions

Misconception 1: "Creating a CRD gives you new behavior."
Reality: A CRD is schema. Until a controller reconciles those objects, they're inert rows in etcd. Operator = CRD + controller.

Misconception 2: "EKS means AWS operates our Kubernetes."
Reality: AWS operates the *control plane*. Node upgrades, deprecated API migrations, addon compatibility, security posture, and cost remain the platform team's job - which is precisely the job the JD describes.

Misconception 3: "We have network segmentation because we use namespaces."
Reality: Namespaces are a naming/RBAC boundary, not a network boundary. Without NetworkPolicies (and an enforcing CNI), cross-namespace pod traffic flows freely.

---

## Interview Angle

Common question forms:
- "What's an Operator and when would you build one?"
- "How would you enforce 'no container runs as root' across 100 teams?"
- "EKS vs running your own cluster - what do you still own?"

Answer frame:
Operator = operational knowledge as a reconcile loop over CRDs; build one when a resource has a *runbook* (databases, stateful systems), consume existing ones otherwise. Fleet-wide enforcement = admission control (Pod Security Standards or Gatekeeper/Kyverno policy), not per-team code review - compliance by default at the API server. EKS: control plane shed, everything node-up retained - enumerate it to show you've operated, not just consumed.

---

## Related Notes

- [[kubernetes-basics|Kubernetes Basics]]
- [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [[pipeline-security-compliance|Pipeline Security and Compliance]]
- [[aws-platform-questions|AWS Platform Engineering Question Bank]]
- [[ecr|ECR (Elastic Container Registry)]]
