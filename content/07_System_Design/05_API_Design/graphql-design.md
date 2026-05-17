---
title: 04 - GraphQL Design
description: "GraphQL's N+1 problem, the DataLoader pattern that solves it, schema design principles, and when GraphQL is the right choice over REST."
tags: [graphql, n+1-problem, dataloader, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# GraphQL Design

> GraphQL's biggest promise — fetch exactly what you need in one request — comes with a hidden cost: without DataLoader, you create the N+1 problem, fetching one thing N+1 times instead of 2.

---

## Quick Reference

**Core idea:**
- GraphQL lets clients specify exactly which fields they want, reducing over-fetching and under-fetching
- A single GraphQL query can replace multiple REST requests (e.g., user + their orders + each order's items)
- The N+1 problem: resolving a list of N items and then querying the database once per item = N+1 queries
- DataLoader batches multiple individual lookups into a single database query, solving N+1
- GraphQL subscriptions enable real-time updates via WebSocket connections

**Tricky points:**
- N+1 is the most common GraphQL performance problem and the one most developers miss at first
- Deep nesting of queries can be legitimately expensive — query complexity limits prevent abuse
- Schema design is crucial: the schema is the API contract; changes must be backward compatible
- GraphQL does not automatically improve performance — it eliminates round trips but does not optimize server-side resolution
- Introspection (the ability to query the schema itself) should be disabled in production for security

---

## What It Is

Imagine shopping at a grocery store where you are not allowed to pick individual items — you must order full product categories. "I want vegetables" gets you every vegetable. "I want dairy" gets you every dairy product, including things you do not need. You make multiple trips to get everything you want, carrying extra items you did not need. This is REST over-fetching and under-fetching.

Now imagine a store where you give the cashier a precise list: "2 apples, 1 liter of milk, a specific brand of pasta." The cashier assembles exactly that order. You make one trip and carry only what you need. This is GraphQL.

GraphQL is a query language and runtime for APIs, developed by Facebook in 2012 and open-sourced in 2015. Instead of multiple fixed REST endpoints each returning a fixed shape of data, GraphQL exposes a single endpoint. Clients send queries describing exactly the data they need, and the server returns exactly that data — nothing more, nothing less.

In a REST API, getting a user's profile, their recent orders, and the items in each order requires three separate HTTP requests: GET `/users/123`, GET `/users/123/orders`, GET `/orders/456/items`. In GraphQL, a single query fetches all of this:

```graphql
query {
  user(id: "123") {
    name
    email
    orders(limit: 5) {
      id
      total
      items {
        product { name }
        quantity
      }
    }
  }
}
```

This is exactly what mobile apps need: one round trip to fetch the entire data graph for a screen. REST's need for multiple requests is particularly costly on mobile networks where each request adds 100–300ms of latency.

---

## How It Actually Works

GraphQL's execution model involves resolvers — functions that fetch data for each field. The `user` field has a resolver that fetches a user from the database. The `orders` field on a user has a resolver that fetches orders for that user. The `items` field on an order has a resolver that fetches items.

The N+1 problem emerges when resolving lists. If a query asks for 10 users and each user's most recent order, the execution is: 1 query to fetch 10 users, then 1 query per user to fetch their order = 11 queries total (1+N). For 100 users, it is 101 queries. This kills performance and database throughput. The N+1 problem is not unique to GraphQL — it appears in any ORM that lazily loads associations — but GraphQL's nested query model makes it particularly easy to create accidentally.

DataLoader is the standard solution. It is a batching and caching utility that collects all individual lookups that happen within a single GraphQL resolution cycle and executes them as a single batch query. When the 10 user resolvers each call `orderLoader.load(userId)`, DataLoader collects all 10 user IDs and executes one query: `SELECT * FROM orders WHERE user_id IN (1, 2, ..., 10)`. Instead of 1+N queries, you get 2 queries total.

```python
from strawberry.dataloader import DataLoader
import strawberry
from typing import Optional

# DataLoader for batching order lookups
async def load_orders_by_user_ids(user_ids: list[str]) -> list[list[dict]]:
    """Called once per request with all requested user IDs."""
    orders = await db.execute(
        "SELECT * FROM orders WHERE user_id = ANY($1)",
        user_ids
    )
    # Group orders by user_id
    orders_by_user = {uid: [] for uid in user_ids}
    for order in orders:
        orders_by_user[order['user_id']].append(order)
    return [orders_by_user[uid] for uid in user_ids]

# GraphQL schema with Strawberry (Python GraphQL library)
@strawberry.type
class Order:
    id: str
    total: float

@strawberry.type
class User:
    id: str
    name: str
    email: str

    @strawberry.field
    async def orders(self, info: strawberry.types.Info) -> list[Order]:
        # Uses DataLoader: collects this lookup with others in the same request
        orders = await info.context["order_loader"].load(self.id)
        return [Order(id=o["id"], total=o["total"]) for o in orders]

@strawberry.type
class Query:
    @strawberry.field
    async def users(self, limit: int = 10) -> list[User]:
        users = await db.execute("SELECT * FROM users LIMIT $1", limit)
        return [User(id=u["id"], name=u["name"], email=u["email"]) for u in users]

schema = strawberry.Schema(query=Query)

# Creating a per-request DataLoader instance
async def get_context(request):
    return {
        "order_loader": DataLoader(load_fn=load_orders_by_user_ids)
    }
```

Query complexity limiting prevents clients from submitting arbitrarily deep or expensive queries. A query that nests 10 levels deep (users → orders → items → products → reviews → authors → ...) could trigger thousands of database queries. GraphQL servers can calculate query complexity before executing and reject queries above a threshold. Maximum query depth limiting is a simpler heuristic that refuses queries nested more than N levels.

Schema design for GraphQL follows different principles than REST URL design. The schema defines types and the relationships between them. Types should model the domain, not the database schema. Connections (paginated lists) should follow the Relay specification: a `edges` wrapper with `cursor` and `node` fields, plus `pageInfo` with `hasNextPage` and `endCursor`. Mutations follow a pattern of one mutation per action with a specific input type and a specific return type.

---

## How It Connects

GraphQL solves the same N+1 problem that ORM lazy loading creates. The solutions differ (DataLoader vs eager loading with JOIN), but the root cause is the same.

[[database-indexes|Database Indexes]]

For systems where real-time updates are needed, GraphQL subscriptions use WebSockets to push updates to subscribed clients. This is the same underlying technology as WebSocket-based real-time features.

[[websockets|WebSockets]]

Comparing GraphQL to gRPC helps clarify when each is appropriate: GraphQL for flexible client-driven queries, gRPC for efficient service-to-service communication.

[[grpc-design|gRPC Design]]

---

## Common Misconceptions

Misconception 1: "GraphQL is always faster than REST because it reduces round trips."
Reality: GraphQL reduces client-to-server round trips by combining multiple requests into one. But if the server's resolvers have N+1 problems, the server-to-database round trips multiply. GraphQL can be significantly slower than REST if DataLoader is not used. The round-trip reduction only helps end-to-end latency if the server-side resolution is efficient.

Misconception 2: "GraphQL's flexible queries mean I don't need to design the schema carefully."
Reality: The schema is the API contract. Every field, type, and relationship in the schema is a commitment to clients. Poorly designed schemas with non-intuitive naming, inconsistent patterns, or wrong abstraction levels make the API hard to use even with GraphQL's flexibility. Schema design requires as much thought as REST URL design.

Misconception 3: "GraphQL introspection should always be enabled so clients can discover the schema."
Reality: Introspection reveals your entire API surface area — all types, fields, queries, and mutations. This is useful during development but provides a reconnaissance tool for attackers in production. Disable introspection in production environments and provide schema documentation through other means (generated API docs, separate schema registry).

---

## Why It Matters in Practice

GraphQL is particularly well-suited for applications with complex data requirements and multiple client types — the canonical example is a product like GitHub or Shopify, which powers diverse clients (web, mobile, partner integrations) that each need different data shapes from the same underlying data. The GraphQL schema becomes a self-documenting, strongly-typed contract that all clients can query against.

The N+1 problem is the most critical operational issue to solve before putting GraphQL into production. Without DataLoader, a list of 100 users with resolved orders generates 101 database queries. With DataLoader, it generates 2. This difference is the difference between acceptable and unacceptable performance at any meaningful scale.

---

## Interview Angle

Common question forms:
- "What is the N+1 problem in GraphQL and how do you solve it?"
- "When would you use GraphQL instead of REST?"
- "What are GraphQL subscriptions?"

Answer frame:
Describe GraphQL: single endpoint, client-specified fields, one round trip for complex data needs. Define N+1: resolver called once per list item results in N+1 database queries. Explain DataLoader: collects all lookups in a resolution cycle, executes as one batched query. Describe query complexity limits as a protection against expensive queries. When to use GraphQL: diverse clients needing different data shapes, complex nested data, mobile with network constraints. When REST is fine: simple CRUD, server-driven API where over-fetching is not a concern.

---

## Related Notes

- [[api-design-principles|API Design Principles]]
- [[grpc-design|gRPC Design]]
- [[rest|REST]]
- [[graphql-basics|GraphQL Basics]]
- [[websockets|WebSockets]]
