---
title: 14 - Kubernetes Autoscaling and Resource Management
description: "Requests reserve capacity for scheduling, limits enforce ceilings at runtime - and three autoscalers act on different axes: HPA adds pods on metrics, VPA resizes pod requests, Cluster Autoscaler adds nodes when pods can't schedule."
tags: [kubernetes, k8s, autoscaling, hpa, vpa, cluster-autoscaler, requests, limits, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-07
---

# Kubernetes Autoscaling and Resource Management

> Three autoscalers, three axes: HPA changes *how many* pods, VPA changes *how big* each pod is, Cluster Autoscaler changes *how many nodes* exist. They compose into the platform answer for "what happens when load spikes."

---

## Quick Reference

**Core idea:**
- **Requests**: what the scheduler reserves - a pod schedules only onto a node with that much unallocated; billing/capacity math runs on requests, not usage
- **Limits**: runtime ceiling - CPU over limit is *throttled*, memory over limit is *OOMKilled* (the asymmetry interviewers probe)
- **QoS classes** (eviction order under node pressure): BestEffort (no requests/limits, evicted first) → Burstable → Guaranteed (requests == limits, evicted last)
- **HPA**: scales replica count on metrics - CPU/memory utilization *relative to requests*, or custom/external metrics (requests-per-second, queue depth)
- **VPA**: recommends/sets per-pod requests from observed usage - right-sizing; historically restarts pods to apply
- **Cluster Autoscaler / Karpenter**: watches *unschedulable (Pending) pods* and adds nodes; removes underutilized ones
- Full chain: load ↑ → HPA adds pods → pods Pending (no room) → Cluster Autoscaler adds nodes → pods schedule

**Tricky points:**
- HPA percentage targets are relative to *requests* - wrong requests make "70% CPU" meaningless
- HPA needs metrics-server (or an adapter for custom metrics); no metrics = no scaling
- Don't run HPA and VPA on CPU/memory for the same workload - they fight
- Cluster Autoscaler triggers on Pending pods, not node utilization - a full-but-schedulable cluster won't grow
- No memory limit on a shared cluster = one leaking pod can trigger node-level OOM kills of *other* pods

---

## What It Is

Requests and limits are the contract between a workload and the cluster. The request is a scheduling-time reservation: the scheduler subtracts requests (not actual usage) from node capacity, which is why systematic over-requesting wastes real money at platform scale and under-requesting causes noisy-neighbor incidents. The limit is a runtime cap enforced by the kernel via cgroups - and the enforcement differs by resource: CPU is compressible, so exceeding it means throttling (latency); memory is not, so exceeding it means the OOM killer (a dead container with exit code 137). That asymmetry drives the common production guidance: always set memory limits; be deliberate (and sometimes generous) with CPU limits, because aggressive CPU limits cause mysterious latency through throttling.

The Horizontal Pod Autoscaler is a control loop comparing a target metric against observed values across a Deployment's pods and adjusting `replicas` between a min and max. CPU utilization targets are the default but the platform-grade setups scale on what actually correlates with load - requests per second, queue backlog - via custom/external metrics. Scaling out is fast; scaling in is deliberately damped (stabilization windows) to avoid flapping.

The Vertical Pod Autoscaler solves a different problem: nobody knows the right requests up front. VPA observes actual usage and recommends (or applies) per-container requests. Even used in recommendation-only mode, it's the practical right-sizing tool.

The Cluster Autoscaler completes the chain at the node level. It watches for Pending pods that failed scheduling for lack of capacity, and grows the node group (on EKS: an Auto Scaling Group; Karpenter provisions instances directly and bin-packs smarter). It also consolidates: draining and removing underutilized nodes. The three together are the answer to "walk me through what happens when traffic 10x's."

---

## How It Actually Works

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: api-hpa }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: api }
  minReplicas: 3
  maxReplicas: 30
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 70 }   # 70% of *requests*
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300     # damp flapping
```

```bash
kubectl top pods                  # live usage (needs metrics-server)
kubectl get hpa                   # current/target metric, replica count
kubectl describe hpa api-hpa      # events: why it scaled or refused to
```

Sizing workflow: set requests from observed p95 usage (VPA recommendations or `kubectl top` over time), memory limit modestly above request, then let HPA handle load variance horizontally.

---

## How It Connects

Requests are a scheduling input - the filter step of node selection.

[[kubernetes-scheduling|Kubernetes Scheduling]]

OOMKilled debugging and the "what happens without limits" question live in the operations bank.

[[kubernetes-operations-questions|Kubernetes Operations Question Bank]]

Cluster Autoscaler on EKS drives EC2 Auto Scaling Groups - the AWS layer underneath.

[[ec2-auto-scaling|EC2 Auto Scaling Groups]]

HPA on custom metrics consumes the Prometheus pipeline - autoscaling is observability with actuators.

[[observability-questions|Observability Question Bank]], [[prometheus-python|Prometheus with Python]]

---

## Common Misconceptions

Misconception 1: "Exceeding a limit kills the container, whichever resource it is."
Reality: Only memory kills (OOMKilled). CPU over limit is throttled - the pod stays alive but gets slow, which is harder to spot than a crash.

Misconception 2: "The scheduler places pods based on actual node utilization."
Reality: On *requests*. A node running idle pods with fat requests is "full" to the scheduler. This is why right-sizing requests is a cost lever, and why Cluster Autoscaler (requests-driven) can grow a cluster that monitoring says is idle.

Misconception 3: "HPA handles any spike."
Reality: HPA reacts on a metrics delay, new pods need image pull + startup + readiness, and if nodes are full, the Cluster Autoscaler's node boot time (minutes) is in the path. Absorbing real spikes needs headroom (min replicas) or overprovisioning, not just an HPA object.

---

## Interview Angle

Common question forms:
- "Requests vs limits - and what happens when each is exceeded?"
- "How does HPA decide to scale? What's needed for custom metrics?"
- "Walk through scaling from 10 to 10,000 req/s - every layer."

Answer frame:
Requests = scheduling reservation, limits = runtime ceiling, throttle-vs-OOMKill asymmetry, QoS eviction order. HPA as a control loop on metrics-relative-to-requests, custom metrics for real load signals, damped scale-down. Then the full chain: HPA → Pending pods → Cluster Autoscaler → nodes - plus the honest latency caveat (node boot minutes) and what covers it (headroom). For the 10-to-10,000 design question, add the non-K8s layers: load balancer, connection pooling, database read scaling, and observability to know where it breaks first.

---

## Related Notes

- [[kubernetes-scheduling|Kubernetes Scheduling]]
- [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [[ec2-auto-scaling|EC2 Auto Scaling Groups]]
- [[metrics-and-monitoring|Metrics and Monitoring]]
