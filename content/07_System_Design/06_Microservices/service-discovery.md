---
title: 02 - Service Discovery
description: "How services find each other in a dynamic microservices environment — client-side vs server-side discovery, and tools like Consul, etcd, and Kubernetes DNS."
tags: [service-discovery, microservices, networking, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Service Discovery

> When services scale up and down dynamically, hardcoded IP addresses break immediately — service discovery is the directory system that lets services find each other even as the infrastructure changes beneath them.

---

## Quick Reference

**Core idea:**
- Service discovery allows services to find the network locations of other services dynamically
- Service registry: a database of healthy service instances and their addresses (Consul, etcd, Eureka, Kubernetes DNS)
- Self-registration: services register themselves with the registry on startup and deregister on shutdown
- Third-party registration: an orchestrator (Kubernetes) manages registration based on container state
- Client-side vs server-side discovery: client looks up registry directly, or a load balancer does it on the client's behalf

**Tricky points:**
- A service registry must itself be highly available — it is a dependency of every service in the system
- Health checks are critical: the registry must know which instances are actually healthy, not just running
- Stale registry entries (instances that died without deregistering) cause request failures until health checks detect them
- DNS-based service discovery (Kubernetes) is simple but may have TTL-related stale address issues
- In Kubernetes, a Service object provides stable DNS + load balancing without client-side discovery logic

---

## What It Is

Imagine you work in a large office building where employees change desks frequently. When you need to talk to the HR team, you do not have their desk numbers memorized — the building changes too often. Instead, there is a building directory at the reception desk: look up "HR" and find the current desk numbers. When HR moves to a new floor, they update the directory. When a new HR person joins, their desk is added. When someone leaves, their entry is removed. You always consult the directory rather than remembering specific locations.

Service discovery is this building directory for microservices. In a dynamic infrastructure — containers spinning up and down, auto-scaling groups adjusting, deployments replacing old instances with new ones — hardcoded IP addresses and ports are useless. Services need a way to find each other by name and get a current, valid address.

A service registry is a database of currently-available service instances, their addresses, and their health status. When a service starts, it registers itself: "I am the user-service, running at 10.0.1.42:8080, and I am healthy." When it shuts down, it deregisters. Clients look up the registry to find a current address before making a call.

Client-side service discovery: the calling service queries the registry directly, receives a list of healthy instances, and picks one using a load balancing algorithm. The client is responsible for load balancing and registry integration. Netflix's Eureka and client-side Ribbon are examples of this pattern. The advantage is that each service has direct visibility into what is available and can implement smart load balancing (e.g., avoid instances in the same availability zone). The disadvantage is that every service must include registry client logic and load balancing logic.

Server-side service discovery: the calling service makes a request to a stable name or address (e.g., `http://user-service`). A load balancer or service mesh in the infrastructure layer resolves that name to a healthy instance and forwards the request. The calling service has no knowledge of the registry or load balancing. Kubernetes Services implement this: a Service provides a stable DNS name and virtual IP; kube-proxy handles the routing to one of the healthy pods behind the Service.

---

## How It Actually Works

Kubernetes is the dominant service discovery mechanism for containerized microservices. In Kubernetes, a Service object creates a stable DNS entry (`user-service.default.svc.cluster.local` or just `user-service` within the same namespace) and a virtual IP. kube-proxy configures iptables or ipvs rules on every node to forward traffic to that virtual IP to one of the Service's healthy Endpoints (pods that match the Service's selector and are passing readiness probes). Services do not need to query a registry — they call `http://user-service` and Kubernetes handles the rest.

Consul is a service registry for environments where Kubernetes is not available or for multi-datacenter service discovery. Services register with the Consul agent running on their host, providing their service name, address, port, and health check configuration. Consul performs health checks (HTTP, TCP, or custom script) at configured intervals. Clients query Consul via DNS or HTTP API to get a list of healthy instances. Consul also supports service mesh features (connect, intentions) for mTLS between services.

etcd is a strongly-consistent distributed key-value store used as the backing store for Kubernetes itself and by other systems (like CoreDNS). Services can write their registration records to etcd keys with TTLs; the TTL ensures stale records expire. Tools like etcd-based discovery in Kubernetes build on top of this. etcd's strong consistency means reads always reflect the latest writes, which is important for service discovery where stale data means failed connections.

```python
# Client-side service discovery pattern with Consul
import consul
import random
import httpx

class ServiceDiscovery:
    def __init__(self):
        self.consul_client = consul.Consul(host='consul', port=8500)
        self._cache = {}  # simple in-process cache

    def get_service_url(self, service_name: str) -> str:
        """Get the URL of a healthy instance of the named service."""
        index, services = self.consul_client.health.service(
            service_name,
            passing=True  # only return healthy instances
        )
        if not services:
            raise RuntimeError(f"No healthy instances of '{service_name}' available")

        # Simple random selection (real systems use consistent hashing or round-robin)
        instance = random.choice(services)
        address = instance['Service']['Address']
        port = instance['Service']['Port']
        return f"http://{address}:{port}"

discovery = ServiceDiscovery()

async def call_user_service(user_id: str) -> dict:
    """Call user service with dynamic service discovery."""
    url = discovery.get_service_url('user-service')
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{url}/users/{user_id}", timeout=5.0)
        response.raise_for_status()
        return response.json()

# Kubernetes: service discovery is transparent — just use the service name
# No client-side code needed — Kubernetes DNS resolves the name automatically
async def call_user_service_k8s(user_id: str) -> dict:
    async with httpx.AsyncClient() as client:
        # 'user-service' resolves to the K8s Service virtual IP automatically
        response = await client.get(
            f"http://user-service/users/{user_id}",
            timeout=5.0
        )
        return response.json()
```

Health checks are the mechanism that keeps the registry accurate. A service instance may be "running" (the process is alive) but not "healthy" (it cannot process requests — perhaps a dependency is down or it is in the middle of initialization). Health checks must distinguish between these states. In Kubernetes, readiness probes serve this role: an instance is only included in the Service's endpoint pool when its readiness probe returns success. Liveness probes determine if the container should be restarted. Startup probes handle slow-starting applications. Together, they ensure that traffic only reaches instances that can actually handle it.

---

## How It Connects

Service discovery is what makes independent deployability practical. When a service is redeployed at a new address, the registry reflects the change and other services pick it up via discovery.

[[microservices-basics|Microservices Basics]]

A circuit breaker at the caller side can mark specific downstream service instances as unavailable when they fail repeatedly, working in conjunction with the service registry's health checks.

[[circuit-breaker|Circuit Breaker]]

API gateways perform server-side service discovery: the gateway resolves service names to backend addresses on behalf of external clients.

[[api-gateway|API Gateway]]

---

## Common Misconceptions

Misconception 1: "DNS is not real service discovery — I need a proper service registry."
Reality: DNS-based service discovery (Kubernetes Services, Consul DNS) is a valid and widely-used form of service discovery. It provides load balancing and health-check integration. Its limitation is DNS TTL — stale cached addresses may persist briefly after an instance becomes unhealthy. For most use cases, DNS-based discovery is sufficient and much simpler to operate than client-side registry integration.

Misconception 2: "Service discovery solves the connection failure problem."
Reality: Service discovery tells you which instances are currently healthy. It does not prevent connection failures — a service can become unhealthy between a health check and your connection attempt. Callers must still implement retries, timeouts, and circuit breakers. Service discovery reduces the frequency of connection failures by keeping the address list current; it does not eliminate them.

Misconception 3: "With Kubernetes, I don't need to think about service discovery."
Reality: Kubernetes Services handle basic service discovery transparently. But for more complex scenarios — cross-cluster communication, multi-region service discovery, service-to-service authentication — additional tooling (service mesh like Istio or Linkerd, Consul federation) is still needed. Kubernetes simplifies intra-cluster discovery; it does not solve all service communication problems.

---

## Why It Matters in Practice

Service discovery is infrastructure that every microservices system needs but teams often overlook until services start failing to connect. In Kubernetes deployments, it is handled automatically by the Service object — developers rarely think about it. In non-Kubernetes deployments or for cross-cluster communication, it requires explicit design and tooling.

The operational discipline is health check configuration. A health check endpoint (`/health` or `/readiness`) that checks actual application health (database connection, downstream dependency availability) — not just "the process is running" — is essential. A health check that always returns 200 provides false availability signals to the registry, sending traffic to instances that cannot serve it correctly.

---

## Interview Angle

Common question forms:
- "How do services find each other in a microservices architecture?"
- "What is the difference between client-side and server-side service discovery?"
- "How does Kubernetes handle service discovery?"

Answer frame:
Explain the problem: services at dynamic IPs cannot use hardcoded addresses. Describe the service registry: database of healthy instances, health checks keep it accurate. Describe client-side discovery: client queries registry, load balances itself (Eureka/Ribbon). Describe server-side discovery: client calls stable name, infrastructure routes (Kubernetes Services). Explain Kubernetes specifically: Service = stable DNS name + virtual IP, kube-proxy handles routing to healthy pods, readiness probes determine inclusion.

---

## Related Notes

- [[microservices-basics|Microservices Basics]]
- [[circuit-breaker|Circuit Breaker]]
- [[api-gateway|API Gateway]]
- [[load-balancing|Load Balancing]]
