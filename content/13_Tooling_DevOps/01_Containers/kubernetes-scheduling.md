---
title: 11 - Kubernetes Scheduling
description: "Taints and tolerations let nodes repel pods, node affinity lets pods choose nodes, and pod affinity/anti-affinity controls placement relative to other pods - together they are the vocabulary for every 'why did this pod land there' question."
tags: [kubernetes, k8s, scheduling, taints, tolerations, affinity, anti-affinity, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-07
---

# Kubernetes Scheduling

> The scheduler filters nodes that *can* run a pod, then scores the survivors - taints are the node saying "not unless invited," affinity is the pod saying "I want to be here (or away from there)."

---

## Quick Reference

**Core idea:**
- **Taints** (on nodes) repel pods; **tolerations** (on pods) permit - not force - scheduling onto tainted nodes
- Taint effects: `NoSchedule` (hard block), `PreferNoSchedule` (soft), `NoExecute` (also evicts already-running pods without the toleration)
- **Node affinity**: pod chooses nodes by label - `requiredDuringSchedulingIgnoredDuringExecution` (hard) vs `preferredDuringSchedulingIgnoredDuringExecution` (soft)
- **Pod affinity/anti-affinity**: placement relative to *other pods* by label, within a `topologyKey` (node, zone) - anti-affinity spreads replicas, affinity co-locates chatty services
- `nodeSelector` is the simple ancestor of node affinity - exact label match only
- Control plane nodes are tainted by default - that's why workloads don't land there

**Tricky points:**
- A toleration does not attract a pod to a tainted node - it only removes the barrier; pairing taint + node affinity is how you get dedicated nodes
- `IgnoredDuringExecution` means already-running pods stay put when labels change - only `NoExecute` taints evict
- Required pod anti-affinity on small clusters causes Pending pods - three replicas with node-level anti-affinity need three nodes
- Pod affinity is expensive for the scheduler at scale; prefer `topologySpreadConstraints` for plain even spreading

---

## What It Is

The scheduler answers one question per pod: which node? It first filters out nodes that fail hard requirements - insufficient CPU/memory against requests, untolerated taints, unsatisfied required affinity, missing volumes - then scores the remaining nodes with soft preferences and picks the best. Every scheduling knob is a way to influence one of those two steps.

Taints and tolerations implement "nodes repel pods unless explicitly tolerated." A taint is key=value plus effect on the node; only pods carrying a matching toleration pass the filter. This is how you reserve GPU nodes for GPU workloads, keep workloads off control plane nodes, and drain nodes (`NoExecute` evicts). The critical asymmetry: tolerations permit, they don't attract. A GPU-tolerating pod can still land on a regular node - to *dedicate* nodes you combine a taint (keep others out) with node affinity (pull the right pods in).

Node affinity generalizes `nodeSelector`: match expressions over node labels (`instance-type in [m5.large, m5.xlarge]`, `zone != ap-south-1a`), in hard (`required...`) or soft (`preferred...`) form. Pod affinity and anti-affinity move the reference point from node labels to *pods already running there*: "put me near pods labeled app=cache" (affinity - latency) or "keep me away from pods labeled like me" (anti-affinity - spreading replicas across nodes or zones for failure isolation). The `topologyKey` defines what "near" means: same node (`kubernetes.io/hostname`), same zone (`topology.kubernetes.io/zone`).

---

## How It Actually Works

```bash
# Taint a node; remove with trailing '-'
kubectl taint nodes gpu-node-1 workload=gpu:NoSchedule
kubectl taint nodes gpu-node-1 workload=gpu:NoSchedule-
```

```yaml
# Dedicated GPU nodes = taint (repel others) + toleration + node affinity (attract these)
spec:
  tolerations:
    - key: workload
      operator: Equal
      value: gpu
      effect: NoSchedule
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-type
                operator: In
                values: [gpu]
    podAntiAffinity:            # spread my replicas across nodes
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values: [my-api]
          topologyKey: kubernetes.io/hostname
```

Debugging placement: `kubectl describe pod` on a Pending pod lists exactly which predicates failed per node ("3 node(s) had untolerated taint", "2 node(s) didn't match pod anti-affinity rules").

---

## How It Connects

Scheduling failures surface as Pending pods - the third leg of the troubleshooting triad.

[[kubernetes-pod-lifecycle|Kubernetes Pod Lifecycle]], [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]

Resource requests are the other scheduling input - the filter step subtracts requests, not actual usage.

[[kubernetes-autoscaling|Kubernetes Autoscaling and Resource Management]]

Anti-affinity across zones is the Kubernetes half of the multi-AZ resilience story from AWS networking design.

[[aws-platform-questions|AWS Platform Engineering Question Bank]]

---

## Common Misconceptions

Misconception 1: "Adding a toleration puts the pod on the tainted node."
Reality: Toleration only removes the repulsion; the pod may still schedule anywhere else. Dedication requires taint + affinity together.

Misconception 2: "Affinity keeps applying after scheduling."
Reality: `IgnoredDuringExecution` - the rule is evaluated at scheduling time only. Relabeling a node does not move running pods. Only `NoExecute` taints evict running pods.

Misconception 3: "Anti-affinity is the way to spread replicas evenly."
Reality: Required anti-affinity is all-or-nothing (unschedulable when nodes run out) and costly to evaluate. `topologySpreadConstraints` with `maxSkew` handles even distribution more gracefully.

---

## Interview Angle

Common question forms:
- "How do you dedicate a set of nodes to one team/workload?"
- "How do you make sure replicas don't end up on the same node/zone?"
- "A pod is Pending with free capacity in the cluster - why?"

Answer frame:
Explain filter-then-score. Dedicated nodes: taint to repel + toleration and node affinity to attract. Spreading: pod anti-affinity on `topologyKey` (or topology spread constraints), noting the hard-vs-soft trade-off. Pending with capacity: untolerated taints, unsatisfiable affinity, or requests exceeding any single node's free space - `kubectl describe pod` names the failed predicate per node.

---

## Related Notes

- [[kubernetes-basics|Kubernetes Basics]]
- [[kubernetes-pod-lifecycle|Kubernetes Pod Lifecycle]]
- [[kubernetes-autoscaling|Kubernetes Autoscaling and Resource Management]]
- [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
