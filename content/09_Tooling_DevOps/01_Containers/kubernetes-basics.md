---
title: 06 - Kubernetes Basics
description: "Kubernetes is a container orchestration system that manages clusters of machines running containerized applications, continuously reconciling actual state toward declared desired state through control loops running in the control plane."
tags: [kubernetes, k8s, orchestration, pods, control-plane, cluster, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Kubernetes Basics

> Kubernetes is not a container runner — it is a control system that continuously monitors the actual state of a cluster and drives it toward a declared desired state, using a set of controllers each responsible for reconciling one type of resource.

---

## Quick Reference

**Core idea:**
- **Cluster**: one or more machines (nodes) managed together as a unit
- **Node**: a machine (VM or physical) in the cluster; either a control plane node or a worker node
- **Pod**: the smallest deployable unit — one or more containers sharing network and storage
- **Control plane**: the brain — API server, etcd, scheduler, controller manager
- **kubectl**: the CLI for interacting with the Kubernetes API server
- `kubectl get pods`, `kubectl describe pod NAME`, `kubectl logs POD_NAME` — the core observation commands

**Tricky points:**
- Pods are ephemeral — they are killed and replaced by higher-level controllers (Deployments); never treat a pod as permanent
- Each pod gets its own cluster-internal IP, but IPs change when pods are replaced — Services provide stable addresses
- The control plane does not run application workloads on control plane nodes by default (taint prevents scheduling)
- `kubectl apply -f manifest.yaml` is idempotent — it reconciles the current state to match the manifest; `kubectl create -f` fails if the resource already exists
- Kubernetes does not build images — it pulls from a registry; images must be pushed before a Deployment references them

---

## What It Is

Kubernetes is best understood through its central philosophy: desired state vs actual state. A developer tells Kubernetes what should be running — "I want three replicas of this container" — and Kubernetes makes it happen. If one replica crashes, Kubernetes notices the discrepancy between the desired state (three replicas) and the actual state (two running) and starts a new one. If a node fails, Kubernetes reschedules the pods that were on that node to other nodes. The developer never manually starts, stops, or restarts containers — they declare intent and Kubernetes continuously enforces it.

This reconciliation model is implemented through control loops. Each control loop watches the actual state of some resources and takes actions to move toward the desired state. The Deployment controller watches Deployment resources and creates or deletes ReplicaSets to match the desired replica count. The ReplicaSet controller watches ReplicaSets and creates or deletes Pods. The scheduler watches Pods with no assigned node and assigns them to nodes. The kubelet on each worker node watches its assigned pods and starts or stops containers accordingly. All of these loops run independently and continuously — there is no central command telling them all what to do in sequence.

The cluster is divided into two roles. The control plane is the brain: it runs the API server (all cluster operations go through this), etcd (a distributed key-value store that is the authoritative source of cluster state), the scheduler (assigns pods to nodes), and the controller manager (runs all the control loops). Worker nodes are the muscle: they run the kubelet (receives pod specs from the API server and ensures the containers are running), the container runtime (containerd, which actually pulls images and runs containers), and kube-proxy (manages network rules for service routing).

---

## How It Actually Works

The API server is the single entry point for all cluster operations. `kubectl` is a client that formats requests and sends them to the API server. `kubectl get pods` queries the API server for the current pod resources. `kubectl apply -f deployment.yaml` sends the manifest to the API server, which stores it in etcd and notifies the relevant controllers.

The basic kubectl workflow:

```bash
# Cluster information
kubectl cluster-info
kubectl get nodes               # List all nodes and their status
kubectl get nodes -o wide       # Include IP addresses and OS info

# Working with pods
kubectl get pods                # Pods in the default namespace
kubectl get pods -n kube-system # Pods in the kube-system namespace
kubectl get pods --all-namespaces

# Inspect a specific pod
kubectl describe pod my-pod-7d4f8b-xk2pl
kubectl logs my-pod-7d4f8b-xk2pl
kubectl logs my-pod-7d4f8b-xk2pl -f           # Follow/stream logs
kubectl logs my-pod-7d4f8b-xk2pl -c container  # Specific container in multi-container pod

# Run a command inside a pod
kubectl exec -it my-pod-7d4f8b-xk2pl -- bash
kubectl exec -it my-pod-7d4f8b-xk2pl -- sh    # If bash is not available

# Apply/delete resources
kubectl apply -f manifest.yaml
kubectl delete -f manifest.yaml
kubectl delete pod my-pod-7d4f8b-xk2pl
```

A Pod manifest is the most basic resource:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-python-pod
  labels:
    app: my-python
spec:
  containers:
    - name: app
      image: myregistry/myapp:1.0
      ports:
        - containerPort: 8000
      resources:
        requests:
          cpu: "100m"        # 0.1 CPU cores
          memory: "128Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
```

Namespaces provide logical partitioning within a cluster. Resources in different namespaces are isolated from each other by default (Services in namespace A are not accessible from namespace B without explicit configuration). The `kube-system` namespace contains control plane components. Application teams typically get their own namespaces.

---

## How It Connects

Kubernetes runs containers — Docker (or containerd) is the container runtime. Understanding what a container is (namespaces + cgroups) is prerequisite to understanding what Kubernetes is scheduling and managing.

[[docker-basics|Docker Basics]]

Deployments are the standard way to run application pods in Kubernetes, building on the pod concept with replica management and rolling updates.

[[kubernetes-deployments|Kubernetes Deployments]]

Services provide stable network addresses for sets of pods — the complement to Deployments for making applications accessible.

[[kubernetes-services|Kubernetes Services]]

---

## Common Misconceptions

Misconception 1: "Kubernetes is just Docker but for clusters."
Reality: Docker runs containers on a single machine. Kubernetes is a control system that manages the desired state of an application across many machines. Kubernetes is not a container runtime — it delegates actual container execution to containerd (or another runtime). The concepts are layered: containers → Docker/containerd → Kubernetes.

Misconception 2: "A Pod is like a container."
Reality: A Pod is a group of one or more containers that share a network namespace and optional shared volumes. Containers within a pod communicate via `localhost` because they are in the same network namespace. Most pods run one container, but the sidecar pattern (logging agent, proxy) uses multi-container pods. The pod is the unit of scheduling — all containers in a pod run on the same node.

Misconception 3: "I should write Pods directly in production."
Reality: Bare Pods are not self-healing. If a pod crashes, nothing restarts it — the pod stays dead. In production, pods are always managed by higher-level controllers: Deployments (for stateless apps), StatefulSets (for stateful apps), DaemonSets (one pod per node). These controllers watch their pods and restart them when they fail.

---

## Why It Matters in Practice

Kubernetes solves the operational problems that emerge at scale: what happens when a node goes down, how to roll out updates without downtime, how to scale application replicas based on load, and how to manage configuration and secrets across many running instances. These are not relevant for a single-server deployment, but become critical when running hundreds of containers across a fleet.

For Python developers specifically, Kubernetes provides the deployment target that CI/CD pipelines aim at. Understanding the basic concepts — cluster, node, pod, control plane — is prerequisite to writing deployment manifests, understanding why a service is unreachable, or reading error messages from `kubectl`.

---

## Interview Angle

Common question forms:
- "What is Kubernetes and how does it work?"
- "What is the difference between a Pod and a container?"

Answer frame:
The key insight to lead with: Kubernetes is a desired-state control system, not a container runner. Explain the control loop model — controllers continuously reconcile actual state toward desired state. Distinguish control plane (API server, etcd, scheduler, controller manager) from worker nodes (kubelet, container runtime). Define Pod as the unit of scheduling, which may contain multiple containers. Explain why bare Pods are not used in production — they have no self-healing; Deployments manage pods.

---

## Related Notes

- [[docker-basics|Docker Basics]]
- [[kubernetes-deployments|Kubernetes Deployments]]
- [[kubernetes-services|Kubernetes Services]]
- [[kubernetes-python|Deploying Python Apps on Kubernetes]]
