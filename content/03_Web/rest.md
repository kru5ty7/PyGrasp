---
title: REST
description: "REST (Representational State Transfer) is an architectural style for distributed systems — its constraints include statelessness, uniform interface (HTTP methods + resource URLs), client-server separation, and optional caching; a RESTful API maps CRUD operations to HTTP methods on resource-oriented URLs."
tags: [rest, restful, stateless, resource, CRUD, HTTP-methods, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# REST

> REST (Representational State Transfer) is an architectural style for distributed systems — its constraints include statelessness, uniform interface (HTTP methods + resource URLs), client-server separation, and optional caching; a RESTful API maps CRUD operations to HTTP methods on resource-oriented URLs.

---

## Quick Reference

**Core idea:**
- **Resource-oriented**: every entity is a resource with a URL (`/users/42`, `/orders/99/items`)
- **HTTP methods map to CRUD**: GET → read, POST → create, PUT/PATCH → update, DELETE → delete
- **Stateless**: each request contains all context needed; server stores no session state between requests
- **Representations**: resources can be represented in different formats (JSON, XML) via `Content-Type`/`Accept` negotiation
- **Uniform interface**: consistent URL patterns and method semantics across the API

**Tricky points:**
- REST is an architectural style (6 constraints), not a protocol or standard — "RESTful" is informal; nothing enforces compliance
- Stateless does NOT mean the server has no state — it means no client session state is stored server-side; the database is server state, not session state
- "HATEOAS" (Hypermedia As The Engine Of Application State) is the most neglected REST constraint — responses include links to related actions; almost no real-world APIs implement it fully
- Nested resources (e.g., `/users/42/posts`) are acceptable for strong containment; avoid going deeper than 2 levels
- Actions that don't map cleanly to CRUD (e.g., "send email", "process payment") are often shoehorned as POST on a sub-resource: `POST /invoices/99/send`

---

## What It Is

REST is a set of constraints for designing distributed hypermedia systems, described by Roy Fielding in his 2000 dissertation. It emerged as a formalization of what made the web scale — stateless connections, cacheable responses, a uniform interface. Applied to web APIs, it means designing around resources (nouns, not verbs) with a consistent URL structure and using HTTP methods to express the operation.

The practical benefit: predictability. A developer looking at a REST API can infer `/users/42` means "user with ID 42" and `DELETE /users/42` means "delete that user" without reading documentation. This convention reduces cognitive load and enables tooling (like Swagger/OpenAPI) to describe APIs generically.

---

## How It Actually Works

Resource URL patterns:

```
Collection:     /users               (many)
Item:           /users/42            (one)
Sub-collection: /users/42/posts      (user's posts)
Sub-item:       /users/42/posts/7    (specific post)
```

Full CRUD mapping:
```
GET    /users          → 200 [users list]
POST   /users          → 201 {new user}, Location: /users/43
GET    /users/42       → 200 {user}
PUT    /users/42       → 200 {updated user}
PATCH  /users/42       → 200 {updated user}
DELETE /users/42       → 204 (no content)
GET    /users/999      → 404 Not Found
```

What NOT to do (verb in URL — not RESTful):
```
POST /createUser        ← wrong; use POST /users
GET  /getUserById?id=42 ← wrong; use GET /users/42
POST /deleteUser/42     ← wrong; use DELETE /users/42
```

FastAPI REST structure:
```python
from fastapi import FastAPI, HTTPException

app = FastAPI()

@app.get("/users")
async def list_users(): ...

@app.post("/users", status_code=201)
async def create_user(user: UserCreate): ...

@app.get("/users/{user_id}")
async def get_user(user_id: int): ...

@app.patch("/users/{user_id}")
async def update_user(user_id: int, update: UserUpdate): ...

@app.delete("/users/{user_id}", status_code=204)
async def delete_user(user_id: int): ...
```

---

## How It Connects

REST uses HTTP methods to express operations — understanding what each method means (safety, idempotency) is prerequisite.
[[http-methods|HTTP Methods]]

FastAPI is built for building RESTful APIs — its route decorators directly implement REST conventions.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "Any JSON API over HTTP is RESTful."
Reality: REST has specific constraints. An API that uses `POST /getUser` (verb in URL) or maintains client session state server-side violates REST constraints. Most real-world APIs are "REST-like" or "REST-inspired" but not fully RESTful.

Misconception 2: "REST requires JSON."
Reality: REST is format-agnostic. The `Accept` and `Content-Type` headers negotiate the representation format. REST APIs can serve XML, MessagePack, or any other format. JSON is the current convention, not a requirement.

---

## Why It Matters in Practice

REST conventions make APIs predictable and enable tooling:
- OpenAPI/Swagger generates docs automatically from RESTful endpoints
- HTTP clients (Postman, httpx) work naturally with resource URLs
- CDNs cache GET responses on resource URLs automatically
- Rate limiting can be applied per resource (`/users/*` throttled separately from `/orders/*`)

Non-REST patterns to know: **RPC-style** (gRPC, tRPC) sends commands (`getUser`, `createOrder`) — better for internal microservices. **GraphQL** sends queries — better for complex data graphs with many client variations.

---

## Interview Angle

Common question forms:
- "What is REST? What are its constraints?"
- "How do you design a REST API for a blog?"

Answer frame: REST = resource-oriented URLs + HTTP method semantics + stateless requests. Six constraints: stateless, client-server, cacheable, uniform interface, layered system, optional code-on-demand. Practical: nouns in URLs, HTTP verbs for operations, status codes to signal outcomes. Blog: `GET/POST /posts`, `GET/PUT/DELETE /posts/{id}`, `GET/POST /posts/{id}/comments`.

---

## Related Notes

- [[http-methods|HTTP Methods]]
- [[http-status-codes|HTTP Status Codes]]
- [[fastapi|FastAPI]]
- [[openapi|OpenAPI]]
