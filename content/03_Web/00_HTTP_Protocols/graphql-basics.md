---
title: 09 - GraphQL Basics
description: "GraphQL is a query language for APIs that lets clients request exactly the data they need from a single endpoint."
tags: [graphql, api, schema, queries, mutations, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# GraphQL Basics

> GraphQL replaces REST's fixed endpoint-per-resource model with a single endpoint and a typed schema, letting clients declare exactly what they need — a Python developer building client-driven APIs must understand both the power and the complexity this introduces.

---

## Quick Reference

**Core idea:**
- A schema written in SDL (Schema Definition Language) defines all types, queries, mutations, and subscriptions
- Clients send a query document specifying exactly which fields to return — no more, no less
- All requests go to one endpoint (typically `POST /graphql`) regardless of operation type
- Mutations are writes; subscriptions are long-lived streams (often over WebSockets)
- Resolvers are Python functions that fetch data for each field in the schema
- The N+1 problem — where resolving a list triggers one extra query per item — is solved by the DataLoader pattern

**Tricky points:**
- GraphQL `POST` requests are not idempotent by convention even for reads (queries), which complicates HTTP caching
- Deeply nested queries can create unexpectedly expensive database operations
- Error handling differs from REST: GraphQL returns HTTP 200 even when the response contains errors in the `errors` field
- Subscriptions require a stateful connection (WebSocket or SSE) and add server-side complexity
- Authorization logic in resolvers is easy to forget — field-level access control requires explicit implementation

---

## What It Is

Think of REST as ordering from a fixed menu at a restaurant: each dish (endpoint) comes with a predetermined set of ingredients, and if you only want the protein without the side dish, you still receive and pay for the full plate. You might also need to visit multiple stations (endpoints) to assemble a full meal. GraphQL is a made-to-order kitchen: you submit one written order describing exactly what you want, and the kitchen assembles it from whatever ingredients are available, delivering precisely what you asked for in a single trip.

Facebook developed GraphQL internally in 2012 and open-sourced it in 2015. The motivation was the mobile news feed: mobile clients had limited bandwidth and diverse views, and REST endpoints were either too specific (requiring many roundtrips) or too broad (transferring many fields the client never displayed). GraphQL's solution was to invert control. Instead of the server deciding what a response contains, the client declares its data requirements in a query document, and the server resolves only those fields.

The schema is the contract that makes this work. Written in SDL, it defines object types (e.g., `User`, `Post`), the fields each type exposes, and the root operation types: `Query` for reads, `Mutation` for writes, and `Subscription` for real-time events. Every field in the schema has a resolver — a function that knows how to fetch or compute that field's value. The GraphQL execution engine walks the query document, invokes the appropriate resolver for each field, and assembles the result into the shape the client requested.

---

## How It Actually Works

In Python, the three main libraries for building GraphQL APIs are Strawberry, Ariadne, and Graphene. Strawberry is the most modern: it uses Python type annotations and decorators to generate the SDL schema automatically, following a code-first approach. Ariadne is schema-first — you write SDL manually and then attach resolver functions. Graphene predates both and uses class-based type definitions; it is still widely used in Django projects via `graphene-django`. All three can be mounted as routes inside a FastAPI or Starlette application.

```python
import strawberry
from strawberry.fastapi import GraphQLRouter

@strawberry.type
class User:
    id: int
    name: str

@strawberry.type
class Query:
    @strawberry.field
    def user(self, id: int) -> User:
        return User(id=id, name="Alice")

schema = strawberry.Schema(query=Query)
router = GraphQLRouter(schema)
# app.include_router(router, prefix="/graphql")
```

The N+1 problem emerges when resolving a list type. If a query asks for ten posts and each post has an `author` field, a naive resolver fetches the author for each post individually — one query to get the posts, then ten queries to get their authors. The DataLoader pattern batches those ten author lookups into a single query. In Python, `strawberry-django` and `aiodataloader` provide DataLoader implementations. The loader accumulates all requested IDs during one execution tick, then fires a single batched database query and distributes results back to the waiting resolvers.

---

## How It Connects

GraphQL subscriptions deliver real-time events over a persistent connection, which in most Python implementations means a WebSocket transport layer underneath the GraphQL protocol.

[[websockets|WebSockets]]

GraphQL over HTTP uses the same request-response infrastructure as REST but makes different trade-offs in how endpoints are structured and how caching works.

[[rest|REST]]

FastAPI can host a GraphQL endpoint via `strawberry.fastapi.GraphQLRouter` or Ariadne's ASGI handler — integrating GraphQL into an existing FastAPI application is a common pattern.

[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "GraphQL always returns exactly the right data, so it's always more efficient than REST."
Reality: Efficiency depends on resolver implementation. A poorly written GraphQL service with N+1 resolver bugs will hit the database far more than a well-designed REST endpoint with eager loading. GraphQL shifts data-fetching responsibility to the client but does not automatically make the server efficient.

Misconception 2: "GraphQL eliminates the need for API versioning."
Reality: GraphQL schema evolution still requires careful backward compatibility. Removing or renaming fields is a breaking change. Deprecation markers (`@deprecated`) allow gradual migration, but version discipline is still necessary.

Misconception 3: "GraphQL is always better than REST for new projects."
Reality: GraphQL adds significant complexity: schema definition, resolver logic, DataLoader patterns, and different security surface areas. REST is often the right choice for public APIs where caching, simplicity, and tooling support matter more than client-driven flexibility.

---

## Why It Matters in Practice

GraphQL is valuable when the API serves many different client types (mobile, desktop, third-party) that each need different subsets of the same underlying data. It is also a natural fit for component-driven front-end architectures (React with Apollo or URQL) where each component declares its own data requirements. Python backend developers will encounter it most often in Django projects using `graphene-django` and increasingly in FastAPI projects using Strawberry.

Understanding the N+1 problem and the DataLoader solution is the single most important performance concern in any GraphQL backend. Interview questions about GraphQL almost always probe this issue, and production incidents in GraphQL services are disproportionately caused by it. Beyond that, knowing how to integrate a GraphQL endpoint into an ASGI application and how to handle authentication at the resolver level covers the majority of practical requirements.

---

## Interview Angle

Common question forms:
- "What is the N+1 problem in GraphQL and how do you solve it?"
- "How does GraphQL differ from REST in terms of data fetching?"
- "How would you add a GraphQL endpoint to a FastAPI application?"

Answer frame:
A strong answer explains the N+1 problem concretely (list of items, each with a related object resolved individually), then describes DataLoader batching as the solution. For the REST comparison, the answer should cover over-fetching, under-fetching, and the single-endpoint model while also acknowledging GraphQL's trade-offs in caching and complexity. For the FastAPI integration question, mentioning Strawberry's `GraphQLRouter` and the ASGI compatibility of the schema demonstrates practical knowledge.

---

## Related Notes

- [[rest|REST]]
- [[websockets|WebSockets]]
- [[fastapi|FastAPI]]
- [[http-basics|HTTP Basics]]
- [[grpc-basics|gRPC Basics]]
