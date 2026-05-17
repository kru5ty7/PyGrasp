---
title: HTTP Methods
description: "HTTP methods (verbs) define the intended action on a resource — GET retrieves, POST creates, PUT/PATCH updates, DELETE removes; idempotency (repeating has same result) and safety (no side effects) are key properties distinguishing them."
tags: [http, GET, POST, PUT, PATCH, DELETE, idempotency, safe-methods, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# HTTP Methods

> HTTP methods (verbs) define the intended action on a resource — GET retrieves, POST creates, PUT/PATCH updates, DELETE removes; idempotency (repeating has same result) and safety (no side effects) are key properties distinguishing them.

---

## Quick Reference

**Core idea:**
- `GET` — retrieve a resource; safe + idempotent; no request body; response is cacheable
- `POST` — create a resource or trigger an action; not safe, not idempotent; has request body
- `PUT` — replace a resource entirely; not safe, idempotent; has request body
- `PATCH` — partially update a resource; not safe, not necessarily idempotent; has request body
- `DELETE` — remove a resource; not safe, idempotent
- `HEAD` — like GET but response has no body; used to check existence or metadata
- `OPTIONS` — returns allowed methods for a resource; used in CORS preflight

**Tricky points:**
- Idempotency means "same result if called once or N times" — `DELETE /user/1` is idempotent (first call deletes, subsequent calls return 404, but the state is the same: user is gone)
- `POST` is not idempotent — two identical `POST /orders` requests may create two separate orders
- `PUT` replaces the entire resource; `PATCH` modifies only the specified fields — sending `PUT` with a partial body means the unspecified fields become null/missing
- Safety means "no server-side state change" — `GET` and `HEAD` must not mutate data; this is a semantic contract, not enforced by HTTP
- Request body in GET: technically allowed by HTTP spec but widely unsupported by proxies/servers; do not rely on it

---

## What It Is

HTTP methods are the vocabulary of the web's request-response protocol. They encode intent: "I want to read this" (GET), "I want to create this" (POST), "I want to destroy this" (DELETE). These semantics allow proxies, caches, and clients to make decisions without inspecting the payload — a proxy can cache a GET response; it cannot cache a POST.

Safety and idempotency are formal properties defined in RFC 9110:
- **Safe**: the method does not change server state. GET, HEAD, OPTIONS.
- **Idempotent**: calling it once has the same effect as calling it N times. GET, HEAD, PUT, DELETE, OPTIONS.

These properties affect how clients handle failures — if a GET times out, retry freely. If a POST times out, retrying may create duplicates (use idempotency keys).

---

## How It Actually Works

REST API conventions:
```
GET    /users          → list all users
GET    /users/42       → get user 42
POST   /users          → create a new user (body contains user data)
PUT    /users/42       → replace user 42 entirely (body contains full user)
PATCH  /users/42       → update user 42 partially (body contains changed fields only)
DELETE /users/42       → delete user 42
```

PUT vs PATCH example — a user `{"id": 42, "name": "Alice", "email": "a@b.com"}`:

```http
PUT /users/42
{"name": "Alice Smith"}
```
Result: `{"id": 42, "name": "Alice Smith"}` — `email` is gone (replaced entirely).

```http
PATCH /users/42
{"name": "Alice Smith"}
```
Result: `{"id": 42, "name": "Alice Smith", "email": "a@b.com"}` — only `name` changed.

Idempotency key for POST (prevents duplicates on retry):
```http
POST /orders
Idempotency-Key: a8f3-4c12-b9e7
{"item": "widget", "qty": 1}
```
Server checks if `a8f3-4c12-b9e7` was seen before — if yes, returns the original response instead of creating a new order.

---

## How It Connects

HTTP methods are the foundation of REST API design — REST uses them to express CRUD operations on resources.
[[rest|REST]]

FastAPI route decorators (`@app.get`, `@app.post`, `@app.put`, etc.) map directly to HTTP methods.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "POST is for creating, PUT is for updating."
Reality: POST is for "non-idempotent action," which is usually creation but doesn't have to be. PUT is for "replace this resource at this URI" — it can create the resource if it doesn't exist (upsert). The distinction is idempotency, not create-vs-update.

Misconception 2: "GET requests can't have a body."
Reality: RFC 9110 does not prohibit GET bodies, but many clients, servers, and proxies discard or reject them. In practice, GET parameters go in the query string, not the body.

---

## Why It Matters in Practice

API design decisions driven by method semantics:
- Use `GET` for read operations — browsers and CDNs cache GET responses automatically.
- Use `POST` for operations that create resources or have side effects (sending an email, charging a card).
- Use `DELETE` for resource removal — clients can safely retry on network failure.
- Use `PATCH` over `PUT` in most update scenarios to avoid accidentally nulling out fields.
- Use `OPTIONS` responses to communicate allowed methods (and for CORS preflight handling).

---

## Interview Angle

Common question forms:
- "What is the difference between PUT and PATCH?"
- "What does idempotent mean?"

Answer frame: **Idempotent** means repeating the call has the same effect — PUT, DELETE, GET are idempotent; POST is not. **PUT replaces the full resource**; PATCH updates specific fields. **Safe** methods (GET, HEAD) don't change server state and are freely cacheable/retryable. POST is neither safe nor idempotent — use idempotency keys when retrying POST on failure.

---

## Related Notes

- [[http-basics|HTTP Basics]]
- [[rest|REST]]
- [[http-status-codes|HTTP Status Codes]]
- [[fastapi|FastAPI]]
