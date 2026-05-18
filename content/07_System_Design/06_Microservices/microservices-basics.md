---
title: 01 - Microservices Basics
description: "What microservices actually are  -  bounded contexts, service independence, the distributed system tax, and when the complexity is worth paying."
tags: [microservices, architecture, distributed-systems, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Microservices Basics

> Microservices solve the problem of independent deployability at the cost of distributed systems complexity  -  and whether that trade is worth it depends entirely on your team size, deployment frequency, and operational maturity.

---

## Quick Reference

**Core idea:**
- A microservice is an independently deployable unit of software with a single business capability
- Bounded context: each service owns its domain data and is the sole source of truth for it
- Services communicate over the network (HTTP, gRPC, message queues), not in-process
- The distributed system tax: network failures, latency, partial failures, and consistency challenges that do not exist in a monolith
- The primary benefit is independent deployment: teams can release, scale, and update services without coordinating

**Tricky points:**
- "Micro" does not mean small in lines of code  -  it means small in scope of responsibility
- Services that share a database are not truly independent  -  shared DB is the most common microservices antipattern
- Synchronous service-to-service calls create cascading failures unless circuit breakers protect them
- Distributed tracing is essential  -  requests spanning 5 services are nearly impossible to debug with per-service logs
- The monolith is not always the wrong answer  -  for small teams, a well-structured monolith is often faster and simpler

---

## What It Is

Think about a large retail organization. The organization has departments: purchasing, inventory, sales, accounting, HR. Each department has its own expertise, its own records, its own manager, and its own way of doing things. They interact by following defined processes  -  the sales department places purchase orders with purchasing; purchasing updates inventory; accounting reconciles receipts. Each department can change its internal processes without informing others, as long as it continues to fulfill its obligations.

Microservices organize software the same way. Instead of one large application that handles orders, inventory, users, payments, and shipping in a single codebase, each capability is a separate service. The order service manages orders. The inventory service tracks stock levels. The user service manages accounts. Each service has its own codebase, its own database, its own deployment pipeline, and its own team. They interact over well-defined APIs or event streams.

The core benefit is organizational and operational scalability. In a monolith, deploying a small change to the payment code requires deploying the entire application  -  including the order, user, and inventory code that did not change. If the deployment has a bug, it can affect all parts of the system. Any team that wants to deploy must coordinate with all other teams. As the organization grows, deployment frequency decreases and coupling increases. In a microservices architecture, the payments team deploys the payment service independently, at any time, without affecting or coordinating with other services.

Bounded context, borrowed from Domain-Driven Design, is the principle that defines service boundaries. A bounded context is a linguistic boundary: inside the service, terms have specific meanings; outside, they may mean different things or not exist. In the order service, an "order" has line items, totals, and states. In the shipping service, an "order" is just an ID and a delivery address. These are different representations of the same business concept, owned by different services. Each service is the sole authority for its version of its data  -  this is called "owning your data."

---

## How It Actually Works

Service independence requires that each service has its own database. Services that share a database are secretly tightly coupled: a schema change in the shared database requires coordinating changes across all services that use it, eliminating the independence that microservices are supposed to provide. Each service's database is an implementation detail, hidden behind the service's API.

Inter-service communication happens over the network. Services can call each other synchronously via HTTP REST or gRPC, or communicate asynchronously via message queues or event streams (Kafka, RabbitMQ). Synchronous calls are simpler to reason about but create tight availability coupling: if Service B is slow or down, Service A's requests that depend on B also fail or slow down. Asynchronous communication via events decouples availability  -  Service A publishes an event and continues; Service B processes it when it is ready.

The distributed system tax is the collection of problems that appear in distributed systems but not in monoliths. Network calls can fail, time out, or return corrupted data. A service may be partially available (some instances up, some down). Consistency across services requires careful design  -  data that was consistent in one database is now spread across multiple databases with eventual consistency. Debugging a request that spans five services requires correlated logs across all five, not just a stack trace in one process.

Deployment automation is a prerequisite, not an afterthought. Each service needs its own CI/CD pipeline, container image, deployment configuration, and environment management. Without this infrastructure, "independent deployment" is theoretical. In practice, microservices require significant investment in platform infrastructure (Kubernetes or equivalent container orchestration, service mesh, centralized logging, distributed tracing, service discovery) before the benefits materialize.

```python
# Two independent services communicating over HTTP
# Order Service: places orders and publishes events
import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

order_app = FastAPI()

class PlaceOrderRequest(BaseModel):
    user_id: str
    items: list[dict]

@order_app.post("/orders")
async def place_order(request: PlaceOrderRequest):
    # Call inventory service synchronously to check stock
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                "http://inventory-service/reserve",
                json={"items": request.items},
                timeout=5.0  # fail fast  -  do not block indefinitely
            )
            if response.status_code == 409:
                raise HTTPException(status_code=409, detail="Item out of stock")
        except httpx.TimeoutException:
            # Inventory service is slow  -  fail with a clear error
            raise HTTPException(status_code=503, detail="Inventory check unavailable")

    order = db.create_order(request.user_id, request.items)

    # Publish event for other services to react to
    event_bus.publish("OrderPlaced", {
        "order_id": order.id,
        "user_id": request.user_id,
        "items": request.items
    })
    return {"order_id": order.id, "status": "placed"}
```

Team structure follows service structure. Conway's Law states that the communication structure of an organization reflects in its software architecture. A team that owns the payments service designs the payments API independently, deploys independently, and is on-call for payments issues independently. The organizational benefit of microservices  -  smaller, more focused teams with clear ownership  -  is as important as the technical benefits.

---

## How It Connects

Service discovery is the mechanism by which one microservice finds the network address of another. This is a fundamental operational requirement in any non-trivial microservice deployment.

[[service-discovery|Service Discovery]]

When one service calls another synchronously and the downstream service fails, the circuit breaker prevents cascading failures that bring down the entire system.

[[circuit-breaker|Circuit Breaker]]

Long-running business processes that span multiple services require the Saga pattern to coordinate partial failures and rollbacks.

[[saga-pattern|Saga Pattern]]

---

## Common Misconceptions

Misconception 1: "Microservices are better than monoliths."
Reality: Microservices solve specific problems  -  independent deployment at scale, independent scaling, organizational separation for large teams. They introduce significant operational complexity (network failures, distributed tracing, eventual consistency, complex deployment infrastructure) that a monolith does not have. For small teams, a well-structured monolith with clear internal module boundaries is often faster to build, easier to debug, and simpler to operate. "Start with a monolith" is valid architectural advice.

Misconception 2: "Making services small (few hundred lines) is the goal."
Reality: Service size is not the defining characteristic. A microservice should own a cohesive business capability. Some capabilities are inherently complex and produce large codebases. The goal is alignment with a bounded context  -  the service has clear responsibilities, clear data ownership, and minimal dependencies on other services. A service that is small but depends heavily on five other services via synchronous calls is a poorly designed microservice.

Misconception 3: "Services can share a database if we are careful."
Reality: Shared databases eliminate service independence. Two services with access to the same database are effectively one service at the data layer. Schema changes require coordinating both services. One service's heavy queries slow the other's. Transactional consistency across both services' data is achievable (they're in the same database), but you have defeated the purpose of microservices.

---

## Why It Matters in Practice

Microservices are the dominant architectural pattern for large-scale Python backend systems. Understanding their trade-offs  -  not just their benefits  -  is essential for making good design decisions. The most common mistake is adopting microservices prematurely, before the team has the operational maturity (CI/CD, container orchestration, distributed tracing) to make them work. The second most common mistake is creating services that are too granular, resulting in many services each handling a tiny piece of business logic, with most request latency spent on inter-service calls.

The right time to extract a service from a monolith is when: the team boundaries are clear (the capability is owned by a specific team), the deployment needs differ (one part needs to scale independently), or the reliability needs differ (one part cannot be allowed to take down everything else). Extract with purpose, not fashion.

---

## Interview Angle

Common question forms:
- "What are microservices and when would you use them?"
- "What are the challenges of microservices compared to a monolith?"
- "How do services communicate in a microservices architecture?"

Answer frame:
Define microservices: independently deployable units with bounded contexts and their own data. Contrast with monolith: one codebase, one database, one deployment. Benefits: independent deployment, independent scaling, team alignment. Challenges: the distributed system tax (network failures, consistency, distributed tracing, operational complexity). Communication options: synchronous (HTTP/gRPC) vs asynchronous (events/queues). When to use: large teams, need for independent deployments, different scaling requirements. When not to use: small teams, early-stage products, insufficient operational infrastructure.

---

## Related Notes

- [[service-discovery|Service Discovery]]
- [[circuit-breaker|Circuit Breaker]]
- [[saga-pattern|Saga Pattern]]
- [[event-driven-architecture|Event-Driven Architecture]]
- [[api-gateway|API Gateway]]
