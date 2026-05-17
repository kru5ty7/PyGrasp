---
title: 08 - Kubernetes Services
description: "A Kubernetes Service provides a stable network address and DNS name for a set of pods selected by label, abstracting away pod ephemerality — ClusterIP for internal access, NodePort for external host access, and LoadBalancer for cloud-provisioned external load balancers."
tags: [kubernetes, services, clusterip, nodeport, loadbalancer, service-discovery, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Kubernetes Services

> A Kubernetes Service solves the problem that pods are ephemeral and their IP addresses change — it provides a stable virtual IP and DNS name that routes traffic to the current healthy pods matching its label selector, acting as an internal load balancer.

---

## Quick Reference

**Core idea:**
- **ClusterIP**: stable internal IP, accessible only within the cluster — the default type
- **NodePort**: exposes the service on a static port on every node's external IP — useful for direct access in development or on-premise
- **LoadBalancer**: provisions an external cloud load balancer (AWS ELB, GCP Load Balancer) — the standard for external traffic in cloud environments
- Label selector connects Service to pods: `selector: {app: myapp}` matches pods labeled `app: myapp`
- Services create DNS entries: `my-service.my-namespace.svc.cluster.local`
- `kubectl get services` — list services and their cluster IPs and ports

**Tricky points:**
- A Service does not know about Deployments — it routes to pods directly via label matching; adding pods with matching labels routes them automatically
- The stable IP of a ClusterIP service is a virtual IP handled by kube-proxy's iptables/IPVS rules — no actual process listens on that IP; traffic is redirected at the kernel level
- NodePort allocates a port in the range 30000–32767 by default; not suitable as a permanent production exposure mechanism (use LoadBalancer or Ingress)
- `SessionAffinity: ClientIP` routes requests from the same client IP to the same pod — useful for stateful connections but can cause uneven load distribution
- An Ingress controller (nginx, traefik) in front of ClusterIP Services is the standard pattern for exposing multiple HTTP services with path-based routing and TLS termination

---

## What It Is

The core problem Services solve is one of ephemerality. Pods in Kubernetes have ephemeral IP addresses assigned when they are scheduled and released when they are terminated. When a rolling update replaces pods, the new pods have different IPs than the old ones. When a pod crashes and is rescheduled to a different node, its IP changes. If other services in the cluster were connecting to pods by IP address, every pod replacement would break those connections.

A Service provides a stable virtual IP (called a ClusterIP) and a DNS name that remains constant regardless of which pods are currently handling traffic. The kube-proxy component on each node watches the API server for Service and Endpoint changes and maintains iptables rules (or IPVS rules) that intercept traffic destined for the Service's virtual IP and redirect it to one of the currently healthy, ready pods. When pods are added, removed, or fail health checks, the endpoint list updates and iptables rules change — but the Service's virtual IP stays the same.

Service discovery within the cluster uses DNS. Kubernetes runs a DNS server (CoreDNS) that automatically creates DNS records for every Service. A Service named `database` in the `production` namespace is resolvable at `database.production.svc.cluster.local` from anywhere in the cluster. A pod in the same namespace can simply use `database:5432` as the connection string — the short name resolves to the full qualified name. This is the mechanism that makes Docker Compose's service name resolution feel familiar in Kubernetes: same concept, different implementation.

---

## How It Actually Works

**ClusterIP** (default — internal only):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: production
spec:
  selector:
    app: myapp              # Matches pods with this label
  ports:
    - name: http
      protocol: TCP
      port: 80              # Port the service listens on (cluster-internal)
      targetPort: 8000      # Port the pods listen on
  type: ClusterIP           # Default; internal only
```

**NodePort** (exposes on each node's IP):

```yaml
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8000
      nodePort: 30080       # Optional: specific port in range 30000-32767
  selector:
    app: myapp
```

Any node in the cluster at `NODE_IP:30080` now routes to the myapp pods.

**LoadBalancer** (cloud-provisioned external LB):

```yaml
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8000
  selector:
    app: myapp
```

On AWS, this provisions an ELB. On GKE, a Google Cloud Load Balancer. The `kubectl get service myapp` output shows the `EXTERNAL-IP` once provisioned. This is the standard for making a service accessible from the internet in cloud-managed Kubernetes.

**Endpoints**: A Service has an associated Endpoints resource that lists the pod IPs currently selected by the label selector. When a pod becomes ready (passes its readiness probe), it is added to Endpoints. When it fails or is terminating, it is removed. This is what makes the Service a dynamic router, not a static one.

```bash
kubectl get endpoints myapp       # See current pod IPs behind the service
kubectl describe service myapp    # Full service details including endpoints
```

**Ingress** is typically layered on top of ClusterIP Services:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp        # Routes to the ClusterIP service
                port:
                  number: 80
```

An Ingress controller (nginx-ingress, traefik) reads Ingress resources and configures the reverse proxy accordingly. This allows multiple services to share one external LoadBalancer IP with path-based or hostname-based routing, and centralizes TLS termination.

---

## How It Connects

Deployments define the pods; Services route traffic to them — every Deployment that handles network traffic needs a matching Service.

[[kubernetes-deployments|Kubernetes Deployments]]

For a complete Python application deployment, Services are combined with Deployments and ConfigMaps as shown in the Python-specific deployment guide.

[[kubernetes-python|Deploying Python Apps on Kubernetes]]

Docker Compose's service name resolution is analogous to Kubernetes Service DNS — both allow services to reference each other by name rather than IP.

[[docker-compose|Docker Compose]]

---

## Common Misconceptions

Misconception 1: "ClusterIP is a real IP with a process listening on it."
Reality: The ClusterIP is a virtual IP — no actual process binds to it. When a packet is destined for the ClusterIP, kube-proxy's iptables rules (or IPVS rules) intercept and redirect the packet to a real pod IP before it even leaves the node. The interception happens at the kernel network layer, not in userspace.

Misconception 2: "LoadBalancer Services are free."
Reality: Each LoadBalancer Service on a cloud provider provisions a cloud load balancer resource — on AWS, an ELB; on GCP, a Cloud Load Balancer. These cost money. A cluster with dozens of LoadBalancer services can accumulate significant cloud cost. The standard pattern is one LoadBalancer Service pointing to a single Ingress controller, with all routing handled inside the cluster by the Ingress controller. This minimizes cloud load balancer cost.

Misconception 3: "A pod's DNS name is its pod name."
Reality: Pods do not get predictable DNS names by default. Services get DNS names; pods' cluster-internal IP addresses change on restart. StatefulSets (for stateful applications) assign stable DNS names to individual pods (`pod-0.service.namespace.svc.cluster.local`), but for stateless applications behind Deployments, pod identity is irrelevant — traffic is load-balanced to any ready pod.

---

## Why It Matters in Practice

Services are the networking primitive that makes inter-service communication inside a Kubernetes cluster work reliably. Every database connection, every call to a downstream API, every health check from a monitoring system depends on Services providing stable addresses. Understanding how Services relate to pod labels and Endpoints explains why a service suddenly becomes unreachable after a deployment: if the new pods' labels do not match the Service selector, the Endpoints list is empty and traffic has nowhere to go.

The LoadBalancer vs NodePort vs ClusterIP choice has direct cost and security implications. In production, the Ingress pattern (one LoadBalancer, many ClusterIP services, one Ingress controller) is preferred over creating a LoadBalancer per service. This requires understanding the layering: external traffic → LoadBalancer → Ingress controller → ClusterIP service → pods.

---

## Interview Angle

Common question forms:
- "What is the difference between ClusterIP, NodePort, and LoadBalancer?"
- "How does service discovery work in Kubernetes?"

Answer frame:
Explain the hierarchy of exposure: ClusterIP (cluster-internal, stable virtual IP), NodePort (external via node IPs, development use), LoadBalancer (cloud-provisioned LB, production). Describe the ClusterIP as a virtual IP backed by kube-proxy iptables rules, not a real process. Explain DNS-based discovery: CoreDNS creates records for Services, allowing `service-name.namespace.svc.cluster.local` resolution. Mention the Ingress pattern as the production way to expose multiple HTTP services.

---

## Related Notes

- [[kubernetes-basics|Kubernetes Basics]]
- [[kubernetes-deployments|Kubernetes Deployments]]
- [[kubernetes-python|Deploying Python Apps on Kubernetes]]
