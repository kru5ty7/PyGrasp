---
title: 03 - API Gateway
description: "What an API gateway does  -  authentication, rate limiting, routing, SSL termination, request transformation  -  and why it is the right place to put cross-cutting concerns."
tags: [api-gateway, microservices, networking, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# API Gateway

> An API gateway is the single front door to your entire backend  -  and putting cross-cutting concerns there means individual services never need to implement them.

---

## Quick Reference

**Core idea:**
- An API gateway sits between clients and backend services, handling cross-cutting concerns
- Cross-cutting concerns: authentication/authorization, rate limiting, SSL termination, request routing, observability
- The gateway enforces policy once for all services rather than having each service implement it independently
- Request transformation: the gateway can modify request headers, translate protocols, or reshape payloads
- Backend for Frontend (BFF) pattern: a gateway tailored for a specific client type (mobile, web, partner)

**Tricky points:**
- An API gateway is not a microservices necessity  -  it becomes valuable when you have multiple services sharing a common entry point
- Putting too much business logic in the gateway creates a distributed monolith at the edge
- The gateway is a potential single point of failure  -  it needs high availability setup
- Rate limiting at the gateway is coarse-grained; fine-grained per-user limiting may still need service-level enforcement
- Gateway latency adds to every request  -  keeping it minimal is an operational priority

---

## What It Is

Imagine a large university campus. Every visitor  -  students, faculty, delivery drivers, maintenance workers  -  enters through a central reception building. At reception: IDs are checked, visitors are logged, packages are sorted by destination, certain areas are restricted (authorization), and everyone is directed to the right building. The university's buildings (services) do not need their own security checkpoints, reception staff, or visitor logs  -  all of that is handled centrally.

An API gateway is this reception building for a software system. It is the single entry point for all client requests. Clients  -  browser applications, mobile apps, partner integrations, IoT devices  -  send all their API requests to the gateway. The gateway handles common concerns and forwards the request to the appropriate backend service. Backend services focus on business logic, not on authentication, rate limiting, or SSL handling.

In a system without an API gateway, each microservice must independently implement authentication (verify JWT tokens), rate limiting, SSL termination, request logging, and health check endpoints. This is repetitive, error-prone, and creates consistency challenges: if the authentication logic has a bug, it must be fixed in every service separately. With an API gateway, these concerns are implemented once and applied to every request.

Authentication is one of the most important gateway responsibilities. The gateway verifies that every incoming request includes a valid credential  -  a JWT token, an API key, or an OAuth2 bearer token. It validates the credential's signature, expiry, and claims before the request reaches any backend service. Backend services receive pre-authenticated requests with a trusted header (e.g., `X-User-ID: 1234`) and do not need to re-verify credentials. This eliminates repeated auth logic across services and ensures a single point of credential enforcement.

---

## How It Actually Works

Rate limiting at the gateway enforces how many requests a client can make in a time window. The gateway tracks request counts per client identifier (typically the authenticated user ID or API key) in a shared cache (Redis). When a client exceeds its limit, the gateway returns `429 Too Many Requests` without forwarding the request to backend services. This protects backend services from abuse and overload without requiring any rate-limiting code in the services themselves.

Request routing is the gateway's forwarding logic. The gateway maintains a routing table: `GET /api/users/*` forwards to the user service, `POST /api/orders` forwards to the order service, `GET /api/products/*` forwards to the product service. Routing can be based on URL path, HTTP method, request headers, or even body content. The gateway can route to different service versions based on URL prefix (`/v1/*` vs `/v2/*`) or a custom header.

Request and response transformation allows the gateway to adapt between client expectations and service implementations. The gateway can add authentication headers (adding `X-User-ID` from the decoded JWT), translate between REST and gRPC (for clients that do not support gRPC), combine responses from multiple services into one (API composition or aggregation), or strip sensitive fields from responses before they reach clients.

```python
# AWS API Gateway equivalent using Python + Kong or custom FastAPI gateway
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.responses import JSONResponse
import httpx
import jwt
import redis
import time

app = FastAPI()
r = redis.Redis()

ROUTING_TABLE = {
    "/api/users": "http://user-service:8001",
    "/api/orders": "http://order-service:8002",
    "/api/products": "http://product-service:8003",
}
JWT_SECRET = "secret"  # in practice, use a proper key management system

def verify_jwt(request: Request) -> dict:
    """Extract and verify JWT  -  runs on every request."""
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = auth_header[7:]
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

def check_rate_limit(user_id: str, limit: int = 100, window: int = 60) -> None:
    """Token bucket rate limiter per user."""
    key = f"ratelimit:{user_id}:{int(time.time() // window)}"
    count = r.incr(key)
    r.expire(key, window)
    if count > limit:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded",
            headers={"Retry-After": str(window)}
        )

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def gateway_handler(path: str, request: Request):
    # 1. Authenticate
    claims = verify_jwt(request)
    user_id = claims["sub"]

    # 2. Rate limit
    check_rate_limit(user_id)

    # 3. Route to correct service
    upstream = None
    for prefix, service_url in ROUTING_TABLE.items():
        if f"/{path}".startswith(prefix):
            upstream = service_url + "/" + path[len(prefix.lstrip("/")):].lstrip("/")
            break

    if not upstream:
        raise HTTPException(status_code=404, detail="Route not found")

    # 4. Forward request with user context header
    async with httpx.AsyncClient() as client:
        headers = dict(request.headers)
        headers["X-User-ID"] = user_id  # inject authenticated user identity
        headers["X-Request-ID"] = request.headers.get("X-Request-ID", str(time.time()))

        response = await client.request(
            method=request.method,
            url=upstream,
            headers=headers,
            content=await request.body()
        )

    return JSONResponse(content=response.json(), status_code=response.status_code)
```

The Backend for Frontend (BFF) pattern extends the API gateway concept. Rather than one general-purpose gateway for all clients, each major client type has its own gateway: a mobile BFF, a web BFF, a partner API BFF. Each BFF is tailored to its client's needs: the mobile BFF might aggregate five service responses into one, reduce payload size, and expose a mobile-optimized API. The partner BFF might enforce stricter rate limits and provide a different authentication mechanism. This avoids the problem of one gateway trying to serve all clients and ending up optimizing for none.

---

## How It Connects

A reverse proxy and an API gateway overlap in function. A reverse proxy handles SSL termination and request forwarding; an API gateway adds authentication, rate limiting, and business-aware routing on top.

[[reverse-proxy|Reverse Proxy]]

The authentication logic at the gateway typically verifies tokens issued by a session-based or JWT-based auth system. Understanding the underlying auth mechanism helps design what the gateway verifies.

[[session-based-auth|Session-Based Authentication]]

In microservices, the API gateway is often the first component described in a system design  -  it defines how clients reach services.

[[microservices-basics|Microservices Basics]]

---

## Common Misconceptions

Misconception 1: "The API gateway should contain business logic."
Reality: The gateway is infrastructure  -  it should enforce policy and route requests, not make business decisions. If the gateway contains logic like "if the user has a premium account, route to this service," it has become a distributed monolith with logic spread between the gateway and services. Business logic belongs in services. The gateway enforces cross-cutting policies.

Misconception 2: "The API gateway makes my individual services stateless  -  I don't need to think about auth in services."
Reality: The gateway enforces authentication at the perimeter. If services communicate with each other (service-to-service calls), they may bypass the gateway. Service-to-service authentication (using mTLS or internal tokens) is still needed for security within the cluster. The gateway secures external traffic; internal traffic requires its own security model.

Misconception 3: "A single API gateway is always the right architecture."
Reality: A single gateway for all services is a single point of failure that handles 100% of production traffic. It must be highly available (multiple instances, redundant deployment). For large organizations with many independent teams, a single gateway can become a bottleneck for deployments and a source of cross-team coupling. Platform teams sometimes run multiple gateways organized by domain.

---

## Why It Matters in Practice

Without an API gateway, the alternative is duplicating auth, rate limiting, and logging code across every service, or making clients responsible for these concerns. Both are worse. Duplicated code diverges over time  -  one service updates the auth library, another does not. Client-side concerns (rate limiting, auth) belong in the server, not the client. The gateway is the right abstraction.

For Python microservices, managed API gateways (AWS API Gateway, Kong, Nginx Plus) handle most gateway concerns with configuration rather than code. Building a custom gateway is an option when requirements are unusual, but managed solutions cover the standard needs efficiently.

---

## Interview Angle

Common question forms:
- "What is an API gateway and what does it do?"
- "Where should authentication be enforced in a microservices system?"
- "What is the BFF pattern?"

Answer frame:
Define the gateway as the single entry point for external clients. List the six responsibilities: authentication, rate limiting, SSL termination, routing, request transformation, observability. Explain why centralizing these concerns is better than duplicating them per service. Describe the BFF pattern for different client types. Address the availability concern: the gateway itself must be highly available.

---

## Related Notes

- [[reverse-proxy|Reverse Proxy]]
- [[nginx-config|Nginx Configuration]]
- [[microservices-basics|Microservices Basics]]
- [[api-design-principles|API Design Principles]]
- [[api-versioning|API Versioning]]
