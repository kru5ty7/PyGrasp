---
title: 10 - Kubernetes Pod Lifecycle
description: "Pods move through five phases (Pending, Running, Succeeded, Failed, Unknown) driven by container states and restart policies - init containers run to completion before app containers start, and the CRI abstraction makes Kubernetes runtime-agnostic."
tags: [kubernetes, k8s, pod-lifecycle, init-containers, cri, restart-policy, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-07
---

# Kubernetes Pod Lifecycle

> A pod's phase is a coarse summary of where it is in its lifecycle - the real detail lives in per-container states and conditions, which is why `kubectl describe` (not `get`) is the first debugging move.

---

## Quick Reference

**Core idea:**
- **Phases**: Pending (accepted, not all containers running - scheduling or image pull in progress), Running (bound to node, at least one container running), Succeeded (all containers exited 0, no restarts coming), Failed (all containers terminated, at least one non-zero), Unknown (node stopped reporting)
- **Container states** (finer-grained than pod phase): Waiting, Running, Terminated - each with a reason (`ContainerCreating`, `CrashLoopBackOff`, `OOMKilled`)
- **Restart policies**: `Always` (default; Deployments require it), `OnFailure` (Jobs), `Never` - applies per-pod to all its containers, enforced by the kubelet with exponential backoff
- **Init containers**: run sequentially to completion *before* app containers start - for waiting on dependencies, running migrations, fetching config
- **Multi-container pods**: sidecar pattern - a helper container (log shipper, proxy) sharing the pod's network namespace and volumes
- **CRI (Container Runtime Interface)**: the gRPC API between kubelet and the runtime (containerd, CRI-O) - Kubernetes never runs containers itself

**Tricky points:**
- A pod stuck in Pending was *accepted* but cannot be scheduled or started - check events for scheduling failures or image pull errors
- CrashLoopBackOff is not a phase - it is a container Waiting-state reason while the pod phase stays Running
- Init container failure blocks the whole pod; with `restartPolicy: Always` the init container is retried, so a never-succeeding init container looks like a startup hang
- "Docker was removed from Kubernetes" only meant the dockershim - images built by Docker run unchanged on containerd because both follow OCI standards

---

## What It Is

Pod phase answers "roughly where is this pod in its life," and only five answers exist: Pending, Running, Succeeded, Failed, Unknown. Anything more specific - why it is pending, which container keeps dying - lives in container states and pod conditions. This split matters practically: `kubectl get pods` shows a STATUS column that mixes phase with container-state reasons (`CrashLoopBackOff`, `Init:0/1`, `ImagePullBackOff`), which is more useful than the raw phase but can mislead - a pod "Running" with 0/1 READY is running and useless.

The restart policy decides what the kubelet does when a container exits. `Always` restarts regardless of exit code - correct for long-running services and required by Deployments. `OnFailure` restarts only non-zero exits - the natural fit for Jobs, where success means completion. `Never` leaves the container dead - the Job controller can still create replacement pods. Restarts happen in place (same pod, same node, same IP) with exponential backoff capped at five minutes; the RESTARTS column counts them.

Init containers extend the lifecycle at the front: each runs to completion in order before any app container starts. They carve setup work out of application images - wait for the database to accept connections, run schema migrations, fetch secrets into a shared volume - keeping the app image single-purpose. Sidecar containers extend the pod sideways: a second long-running container sharing localhost and volumes with the app (log shipping, TLS proxying, metric export).

Underneath all of this, the kubelet talks to a container runtime through CRI, a gRPC interface. containerd and CRI-O are the common implementations. Because the contract is CRI on one side and OCI image/runtime specs on the other, Kubernetes is runtime-agnostic - which is also why removing dockershim changed nothing about Docker-built images.

---

## How It Actually Works

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-init
spec:
  restartPolicy: Always
  initContainers:
    - name: wait-for-db
      image: busybox:1.36
      command: ["sh", "-c", "until nc -z db-service 5432; do sleep 2; done"]
  containers:
    - name: app
      image: myregistry/myapp:1.0
    - name: log-shipper          # sidecar: shares network + volumes with app
      image: fluent/fluent-bit:2.2
```

Debugging the lifecycle:

```bash
kubectl get pods                          # STATUS mixes phase + container reasons
kubectl describe pod my-pod               # per-container states, events, exit codes
kubectl logs my-pod -c wait-for-db        # logs of a specific (init) container
kubectl get pod my-pod -o jsonpath='{.status.phase}'
```

Reading `describe` output: `Last State: Terminated, Reason: OOMKilled, Exit Code: 137` tells you the previous run died to the memory limit; `State: Waiting, Reason: CrashLoopBackOff` tells you the kubelet is backing off before the next restart.

---

## How It Connects

The pod phases explain what the troubleshooting question bank debugs - CrashLoopBackOff, OOMKilled, and Pending are lifecycle states with specific causes.

[[kubernetes-operations-questions|Kubernetes Operations Question Bank]]

Deployments assume `restartPolicy: Always` and layer replica management on top of individual pod lifecycles.

[[kubernetes-deployments|Kubernetes Deployments]]

Probes hook into the Running phase - readiness gates traffic, liveness triggers restarts within the same lifecycle.

[[kubernetes-basics|Kubernetes Basics]]

---

## Common Misconceptions

Misconception 1: "CrashLoopBackOff is a pod phase."
Reality: It is a container Waiting-state *reason*. The pod phase remains Running (or Pending during first start). The kubelet is applying exponential backoff between restart attempts of a repeatedly-dying container.

Misconception 2: "Init containers run alongside the app."
Reality: Init containers run *sequentially, to completion, before* any app container starts. A sidecar runs alongside. Choosing wrong causes real bugs - a "wait for dependency" sidecar never gates app startup; a log-shipper init container exits and ships nothing.

Misconception 3: "Kubernetes needs Docker."
Reality: Kubernetes needs a CRI-compatible runtime. containerd (Docker's own extracted core) is the default almost everywhere. Docker-built OCI images run unchanged.

---

## Interview Angle

Common question forms:
- "Walk me through the lifecycle of a pod from `kubectl apply` to Running."
- "What's the difference between an init container and a sidecar?"
- "What does restartPolicy control, and what do Deployments require?"

Answer frame:
Phases are coarse (Pending → Running → Succeeded/Failed); container states carry the diagnostic detail. Init containers = sequential setup gates before app start; sidecars = concurrent helpers sharing network/volumes. Restart policy is per-pod, enforced by the kubelet in place with backoff - `Always` for services, `OnFailure` for Jobs. Mention CRI to show platform literacy: kubelet → CRI gRPC → containerd → OCI runtime.

---

## Related Notes

- [[kubernetes-basics|Kubernetes Basics]]
- [[kubernetes-deployments|Kubernetes Deployments]]
- [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [[docker-basics|Docker Basics]]
