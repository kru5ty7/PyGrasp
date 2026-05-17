---
title: 07 - Strangler Fig Pattern
description: "How to incrementally migrate a monolith to microservices by routing new functionality to new services while the old system is gradually replaced."
tags: [strangler-fig, migration, microservices, refactoring, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Strangler Fig Pattern

> The strangler fig pattern is how you migrate a monolith to microservices without a "big bang" rewrite — you grow the new system around the old one, routing specific capabilities to it until the old system can be deleted.

---

## Quick Reference

**Core idea:**
- Named after the strangler fig tree, which grows around a host tree and eventually replaces it
- Route a subset of requests to a new service while the monolith continues handling everything else
- Gradually expand what the new service handles until the monolith is no longer needed
- The routing layer (proxy or facade) is the mechanism that controls the transition
- The anti-corruption layer translates between the old system's model and the new service's model

**Tricky points:**
- The routing layer must handle both the new and old system simultaneously — it must not break existing behavior
- Data migration is the hardest part: the new service needs its own data store, potentially populated from the monolith
- The old system and new service may have different data models for the same concept — the anti-corruption layer bridges this
- "Feature flags" enable gradual rollout: send 1% of traffic to the new service, then 10%, then 100%
- Big bang rewrites almost always fail — the strangler fig is the pragmatic alternative

---

## What It Is

A strangler fig is a tropical plant that germinates in the canopy of a tree, grows downward, and eventually wraps around the host tree. Over years, the fig grows into a full tree in its own right. The host tree may die and rot away inside the fig — the fig's structure supporting itself without the original tree. The fig did not destroy the host suddenly. It grew around it slowly, taking over its structural role incrementally.

Martin Fowler described the strangler fig pattern in 2004 as a way to incrementally replace a legacy system. Instead of stopping all development, writing a new system from scratch, and then switching over — the "big bang" rewrite that almost always fails — you build new functionality as separate services alongside the legacy system. Traffic is gradually routed to the new services. The legacy system is "strangled" — its responsibilities shrink until it can be decommissioned.

The strangler fig pattern is the answer to one of the most common questions in software engineering: "We have a large, difficult-to-change monolith. How do we break it into microservices without shutting down the business for six months?" The answer is: you do not switch all at once. You identify the first capability to extract — typically one with well-defined boundaries and high business value — extract it as a new service, route the relevant traffic there, and then move to the next.

The routing layer is the mechanism that makes the migration transparent to clients. A reverse proxy or API gateway sits in front of both the monolith and the new services. Based on URL paths, request headers, or feature flags, it routes specific requests to the new service and everything else to the monolith. Clients do not change their behavior — the routing layer is invisible to them. Initially, 100% of traffic goes to the monolith. As extraction proceeds, more and more requests go to new services.

---

## How It Actually Works

The sequence for extracting one capability:

1. Define the boundary. Identify a bounded context: a set of related features that can be clearly owned by one service. User authentication, payment processing, and order management are examples of clear boundaries. User "authentication + profile + preferences + notifications" is too broad and should be split.

2. Build the new service. Implement the extracted capability as a standalone service with its own API. Do not share the monolith's database — the new service gets its own data store.

3. Populate the new service's data. This is the hardest step. Options: dual-write (write to both old and new stores during a transition period), bulk migration (copy existing data from the monolith's database to the new service's database, then keep in sync), or event-based sync (use CDC to stream changes from the monolith's database to the new service).

4. Set up the routing layer. Configure the proxy to route requests for the extracted capability to the new service. Start with 0% of traffic, use feature flags to gradually increase (1%, 10%, 50%, 100%).

5. Monitor and validate. Compare behavior between old and new (shadow traffic — send to both, compare responses). Fix discrepancies.

6. Decommission the old code. Once 100% of traffic uses the new service and the new service is stable, remove the corresponding code and database tables from the monolith.

```python
# Nginx routing layer: strangler fig proxy configuration
# At migration start: all /auth/* traffic to monolith
# At migration end: all /auth/* traffic to new auth service

# nginx.conf during migration
"""
upstream monolith {
    server monolith-service:8000;
}

upstream auth_service {
    server auth-service:8001;
}

# Feature flag via header (set by A/B testing middleware upstream)
map $http_x_use_new_auth $auth_backend {
    default monolith;    # 90% of traffic still goes to monolith
    "true" auth_service; # 10% goes to new auth service (feature flag)
}

server {
    listen 80;

    location /api/auth/ {
        proxy_pass http://$auth_backend;  # dynamic routing
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
    }

    location / {
        proxy_pass http://monolith;  # everything else still goes to monolith
    }
}
"""

# Anti-corruption layer: translate between old and new data models
class AuthServiceAdapter:
    """
    The new auth service uses JWT tokens.
    The monolith uses session cookies.
    This adapter translates between the two during dual-running period.
    """

    def __init__(self, new_auth_service_url: str, monolith_url: str):
        self.new_auth = new_auth_service_url
        self.monolith = monolith_url

    async def login(self, email: str, password: str, use_new_auth: bool) -> dict:
        if use_new_auth:
            # New service: returns JWT
            response = await httpx.post(f"{self.new_auth}/auth/login", json={
                "email": email, "password": password
            })
            new_response = response.json()
            # Translate new format to format clients expect
            return {
                "token": new_response["access_token"],
                "user_id": new_response["sub"],
                "expires_at": new_response["exp"]
            }
        else:
            # Old monolith: returns session ID
            response = await httpx.post(f"{self.monolith}/login", data={
                "email": email, "password": password
            })
            old_response = response.json()
            # Translate old format to format clients expect
            return {
                "token": old_response["session_id"],  # mapping
                "user_id": old_response["userId"],    # name difference
                "expires_at": None  # monolith uses session TTL, not explicit expiry
            }
```

Shadow traffic is a validation technique used during the migration. While routing real traffic to the old system, a copy of each request is also sent to the new service. Responses from both are compared. Discrepancies indicate bugs in the new service. Shadow traffic allows validating the new service's behavior against real production traffic without any user impact.

The anti-corruption layer (ACL) is a translation layer between the old system's data model and the new service's model. The same concept — say, a "customer" in the monolith — may be called "user" in the new service, have different fields, or use different ID formats. The ACL translates between them, preventing the old system's conceptual model from "corrupting" the new service's clean domain model.

---

## How It Connects

The strangler fig pattern is the practical path to microservices for most teams. Understanding microservices basics provides the destination; strangler fig provides the journey.

[[microservices-basics|Microservices Basics]]

Service discovery enables the routing layer to find the new service's location dynamically, as it may scale independently from the monolith.

[[service-discovery|Service Discovery]]

During the dual-running period, the outbox pattern helps synchronize data between the monolith's database and the new service's database.

[[outbox-pattern|Outbox Pattern]]

---

## Common Misconceptions

Misconception 1: "You should extract microservices domain by domain, bottom-up."
Reality: The extraction order should be driven by business value and clear boundaries, not technical structure. Extract the capabilities that need to scale independently, have frequent deployment needs, or have clear domain boundaries — regardless of where they are in the architecture. "Bottom-up" extraction of infrastructure layers before business logic often produces no business benefit.

Misconception 2: "The strangler fig is a temporary pattern — once you've migrated, you can delete the proxy."
Reality: The routing layer (API gateway or reverse proxy) remains a permanent part of the architecture. It routes traffic to all services. The monolith eventually becomes one or zero services, but the routing infrastructure continues to serve the microservices that replaced it.

Misconception 3: "Big bang rewrites are faster than the strangler fig approach."
Reality: Big bang rewrites almost always take longer than estimated, often fail, and frequently produce a new system with different (not fewer) problems. The strangler fig approach delivers value incrementally — the first extracted service is in production after weeks, not months. Each service validates the migration approach before committing the entire system to it.

---

## Why It Matters in Practice

The strangler fig pattern is the realistic approach to architectural evolution. Most non-trivial software organizations have legacy systems that cannot be replaced overnight. The pattern gives engineers a systematic, low-risk path for modernization: extract the highest-value service first, learn from it, refine the approach, and continue. Each extraction improves the team's capability for the next one.

For Python engineers, the most common manifestation is a Django monolith being gradually replaced with FastAPI microservices. The routing layer is typically Nginx or an API gateway. The first extractions are usually high-traffic, clear-boundary services like user authentication or product search.

---

## Interview Angle

Common question forms:
- "How would you migrate a monolith to microservices?"
- "What is the strangler fig pattern?"
- "What are the risks of a big bang rewrite?"

Answer frame:
Define the strangler fig: incremental migration where the new system grows around the old. Describe the four steps: identify boundary, build new service, populate data, route traffic gradually. Explain the routing layer as the control point. Discuss shadow traffic for validation. Explain the anti-corruption layer for model translation. Contrast with big bang rewrite: slower to start, faster to value, lower risk. List the challenges: data migration, dual-running consistency, finding the right boundary.

---

## Related Notes

- [[microservices-basics|Microservices Basics]]
- [[service-discovery|Service Discovery]]
- [[api-gateway|API Gateway]]
- [[outbox-pattern|Outbox Pattern]]
