---
title: 07 - Kubernetes Deployments
description: "A Kubernetes Deployment manages ReplicaSets to maintain a desired number of running pod replicas, performs rolling updates without downtime by incrementally replacing pods, and supports rollback to any previous revision."
tags: [kubernetes, deployments, rolling-updates, replicaset, rollback, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Kubernetes Deployments

> A Kubernetes Deployment is the standard way to run a stateless application  -  it declares the desired number of replicas and the pod template, then continuously reconciles reality toward that declaration, managing rolling updates and rollbacks automatically.

---

## Quick Reference

**Core idea:**
- A Deployment manages ReplicaSets; a ReplicaSet manages Pods  -  Deployment is the high-level controller
- `kubectl apply -f deployment.yaml`  -  creates or updates a Deployment
- `kubectl rollout status deployment/my-app`  -  watch a rolling update in progress
- `kubectl rollout undo deployment/my-app`  -  roll back to the previous revision
- `kubectl scale deployment my-app --replicas=5`  -  scale to 5 replicas imperatively
- `kubectl set image deployment/my-app app=myimage:2.0`  -  trigger a rolling update to a new image

**Tricky points:**
- Deployments never delete old ReplicaSets  -  they scale them to 0 and keep them for rollback history; `revisionHistoryLimit` controls how many to keep (default 10)
- A rolling update is only considered complete when all new pods pass health checks  -  configuring liveness and readiness probes is essential for safe rollouts
- `maxUnavailable: 0` and `maxSurge: 1` means rolling update adds one new pod, waits for it to be ready, then removes one old pod  -  zero-downtime at the cost of briefly running n+1 pods
- Pod template changes trigger rolling updates; changes to metadata not in the template do not
- The Deployment controller is the third layer in a three-tier structure: Deployment -> ReplicaSet -> Pod

---

## What It Is

The Deployment controller is the answer to: "how does Kubernetes ensure my application keeps running?" A bare Pod, as noted in the Kubernetes Basics note, has no self-healing. A Deployment establishes a contract: "I want three replicas of this pod template to be running at all times." The Deployment controller continuously monitors this contract. If a pod crashes, the controller notices the pod count dropped below three and starts a replacement. If a node goes down, pods from that node are rescheduled on other nodes. The developer declared intent; the controller enforces it continuously.

The layered architecture  -  Deployment -> ReplicaSet -> Pod  -  serves a specific purpose. A Deployment manages multiple ReplicaSets over time. When a rolling update begins (because the pod template changed), the Deployment creates a new ReplicaSet with the updated template and gradually scales it up while scaling down the old ReplicaSet. At any point during the update, both the old and new ReplicaSets exist. When the update completes, the old ReplicaSet is scaled to zero but retained. If the update fails or causes problems, rolling back means scaling the old ReplicaSet back up and scaling the new one down. Kubernetes never destroys history; it manages multiple ReplicaSets simultaneously.

This model makes rolling updates not just a deployment strategy but a core safety mechanism. By default, Kubernetes updates pods incrementally  -  starting new pods with the new version, waiting for them to become ready, then terminating old pods. If the new pods fail to start or fail their health checks, the rolling update stops. Old pods continue serving traffic. The application remains available throughout the update, and failures are automatically contained.

---

## How It Actually Works

A Deployment manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
  labels:
    app: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp              # Must match template labels
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0       # Never reduce below desired count during update
      maxSurge: 1             # Allow 1 extra pod during update (4 total briefly)
  template:
    metadata:
      labels:
        app: myapp            # Must match selector
    spec:
      containers:
        - name: app
          image: myregistry/myapp:1.5
          ports:
            - containerPort: 8000
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 10
      terminationGracePeriodSeconds: 30
```

Rollout operations:

```bash
# Apply (create or update)
kubectl apply -f deployment.yaml

# Watch rolling update progress
kubectl rollout status deployment/myapp

# View rollout history
kubectl rollout history deployment/myapp

# Roll back to previous revision
kubectl rollout undo deployment/myapp

# Roll back to a specific revision
kubectl rollout undo deployment/myapp --to-revision=3

# Scale manually (overwrites replicas in manifest if not updated)
kubectl scale deployment myapp --replicas=5

# Trigger rolling update by updating image
kubectl set image deployment/myapp app=myregistry/myapp:1.6
```

**Readiness vs Liveness probes** serve different purposes and are both critical:

A readiness probe determines when a pod is ready to receive traffic. A pod that fails its readiness probe is removed from Service endpoints  -  traffic is not sent to it. During a rolling update, new pods must pass the readiness probe before old pods are terminated. This is the mechanism that prevents downtime.

A liveness probe determines whether a pod is alive and should continue running. A pod that fails its liveness probe is killed by the kubelet and replaced by a new pod (the ReplicaSet controller creates the replacement). This handles hung processes  -  cases where the container is running but not processing requests.

---

## How It Connects

Services route traffic to pods managed by Deployments  -  the label selector on a Service matches the same labels defined in the Deployment's pod template.

[[kubernetes-services|Kubernetes Services]]

For Python applications specifically, the readiness probe typically hits a `/health` or `/ready` endpoint that FastAPI or another framework exposes.

[[kubernetes-python|Deploying Python Apps on Kubernetes]]

The CD pipeline that pushes a new image to the registry then triggers the rolling update  -  typically with `kubectl set image` or by applying a new manifest version.

[[cd-docker|CD with Docker]]

---

## Common Misconceptions

Misconception 1: "Rolling updates always succeed  -  if I push a new image, Kubernetes handles the rest."
Reality: A rolling update succeeds only if the new pods pass health checks. If the new image has a startup bug, the pods fail their readiness probes, and Kubernetes halts the update  -  old pods continue serving traffic. But Kubernetes does not automatically roll back; it waits indefinitely. Automatic rollback requires a deployment tool like ArgoCD or Flux, or explicit monitoring and `kubectl rollout undo` in the pipeline.

Misconception 2: "Scaling up replicas requires changing the Deployment manifest."
Reality: `kubectl scale deployment myapp --replicas=5` imperatively changes the replica count without modifying the manifest file. However, the next time `kubectl apply -f deployment.yaml` is run with `replicas: 3` in the file, it will scale back to 3. For persistent scale changes, update the manifest. For temporary scaling (e.g., traffic surge), imperative scaling is fine.

Misconception 3: "The old ReplicaSet is deleted after a rolling update."
Reality: Old ReplicaSets are retained (scaled to 0) to enable rollback. `kubectl rollout undo` scales the old ReplicaSet back up. The `revisionHistoryLimit` field controls how many old ReplicaSets to keep  -  the default is 10. Old ReplicaSets accumulate over time in a cluster with many deployments; setting a smaller limit (e.g., 3) is a common cleanup practice.

---

## Why It Matters in Practice

Deployments are the fundamental building block for every production application running on Kubernetes. Understanding how rolling updates work  -  and how they can halt  -  is essential for diagnosing deployment failures. When a deployment is stuck ("Waiting for rollout to finish: 1 old replicas are pending termination"), the cause is almost always that new pods are not passing the readiness probe. The investigation starts with `kubectl describe pod NEW_POD_NAME` and `kubectl logs NEW_POD_NAME`.

Resource requests and limits (the `resources:` section) are not optional in production. Without requests, the Kubernetes scheduler has no information for bin-packing pods onto nodes and may overload nodes. Without limits, a buggy pod can consume all memory on a node and cause the node to OOM-kill other pods. Always set both.

---

## Interview Angle

Common question forms:
- "How do you deploy a new version of an application on Kubernetes without downtime?"
- "What is the difference between a Deployment and a ReplicaSet?"

Answer frame:
Explain the three-tier hierarchy (Deployment -> ReplicaSet -> Pod). Describe rolling updates: new ReplicaSet is scaled up while old is scaled down, gated by readiness probes. Explain that Deployments retain old ReplicaSets for rollback  -  `kubectl rollout undo` uses this. Discuss readiness vs liveness probes: readiness controls traffic routing, liveness controls container restart. Mention `maxUnavailable` and `maxSurge` for fine-tuning update behavior.

---

## Related Notes

- [[kubernetes-basics|Kubernetes Basics]]
- [[kubernetes-services|Kubernetes Services]]
- [[kubernetes-python|Deploying Python Apps on Kubernetes]]
