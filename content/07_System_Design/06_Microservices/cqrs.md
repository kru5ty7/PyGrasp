---
title: 05 - CQRS
description: "Command Query Responsibility Segregation  -  separating the write model from the read model to optimize each independently, and the eventual consistency this requires."
tags: [cqrs, read-model, write-model, projections, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# CQRS

> CQRS is the recognition that reading data and writing data are fundamentally different operations with different requirements  -  separating them allows each to be optimized independently without compromising the other.

---

## Quick Reference

**Core idea:**
- Commands: operations that change state (create, update, delete)  -  write model
- Queries: operations that read state  -  read model
- CQRS separates the write model (normalized, optimized for consistency) from the read model (denormalized, optimized for queries)
- Projections: the read model is built by processing events or changes from the write model
- Eventual consistency: the read model is updated asynchronously  -  it is slightly behind the write model

**Tricky points:**
- CQRS does not require event sourcing, but they are commonly combined
- The read model can be a separate database, a cache, or a search index  -  optimized for its query patterns
- "Command" in CQRS means a write operation, not the same as a command in the command pattern
- Eventual consistency between read and write models means post-write reads may briefly see stale state
- CQRS adds complexity  -  it is only worth it when read and write optimizations genuinely conflict

---

## What It Is

Think about a library. The process of acquiring and cataloging a new book (the write operation) requires careful data quality checks: is the ISBN correct? Is the classification right? Are there duplicates? It is slow and rigorous. The process of finding books to borrow (the read operation) needs to be fast: show me all mystery novels with available copies, sorted by rating. The systems that serve these two operations are completely different. The acquisitions database is normalized and carefully validated. The discovery catalog is denormalized, indexed for full-text search, and sorted in dozens of ways. Using the acquisitions database directly for discovery would be slow; using the discovery catalog for acquisitions would compromise data quality.

This is CQRS (Command Query Responsibility Segregation) in a real-world form. The principle is that the data model optimized for writing is not the same data model optimized for reading. In a typical relational database, you normalize data to avoid redundancy (write model) and then query with JOINs (read model). For complex reads with many JOINs, poor performance, and complex query logic, this compromise serves neither purpose well.

CQRS separates the two responsibilities. Commands (write operations) go to the write side, which enforces business rules, maintains invariants, and stores data in a normalized, consistent form. Queries (read operations) go to the read side, which maintains one or more denormalized, pre-aggregated projections of the data optimized for specific query patterns. The projections are updated when the write side changes  -  either synchronously (for simple cases) or asynchronously (for complex or distributed cases).

A projection is a materialized view of the write model's data, shaped for a specific query. If the write model stores orders and customers in separate normalized tables, a projection for "customer order history" might denormalize both into a single document per customer, containing all their orders with embedded product names and prices. This projection is fast to query because no JOINs are needed at read time  -  the JOIN was done when the projection was built.

---

## How It Actually Works

The write model receives commands through a command handler. The command handler validates the command, applies business rules, and updates the write database. After a successful write, it publishes an event (or returns an updated aggregate) that the projection updater can use to keep the read model in sync.

The projection updater subscribes to changes in the write model  -  either by consuming domain events from an event bus, or by polling the write database for changes. For each change, it updates the relevant projections. A single write event may trigger updates to multiple projections if different query patterns use different views of the same data.

```python
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Optional

app = FastAPI()

# --- Write side ---
class CreateOrderCommand(BaseModel):
    user_id: str
    items: list[dict]

class UpdateOrderStatusCommand(BaseModel):
    order_id: str
    new_status: str

@app.post("/commands/create-order")
async def create_order(cmd: CreateOrderCommand):
    """Command handler: applies business rules, persists to write DB, emits event."""
    # Business rule: validate items in stock
    for item in cmd.items:
        if not inventory.check_stock(item["product_id"], item["quantity"]):
            return {"error": "insufficient_stock"}

    order = write_db.create_order(cmd.user_id, cmd.items)

    # Emit event for projection updates
    event_bus.publish("OrderCreated", {
        "order_id": order.id,
        "user_id": cmd.user_id,
        "items": cmd.items,
        "total": order.total,
        "status": "pending",
        "created_at": order.created_at.isoformat()
    })
    return {"order_id": order.id}

# --- Read side ---
class OrderSummary(BaseModel):
    order_id: str
    total: float
    status: str
    item_count: int
    created_at: str

class UserOrderHistory(BaseModel):
    user_id: str
    orders: list[OrderSummary]
    total_spent: float
    order_count: int

@app.get("/queries/users/{user_id}/orders", response_model=UserOrderHistory)
async def get_user_order_history(user_id: str):
    """Query handler: reads from the denormalized read model  -  no JOINs needed."""
    # The read model is a pre-built projection, not the normalized write DB
    history = read_db.get_user_order_history(user_id)  # fast single-document lookup
    return history

# --- Projection updater (runs asynchronously) ---
async def update_order_projections(event: dict):
    """Update all relevant read models when an order is created or changed."""
    if event["event_type"] == "OrderCreated":
        order_id = event["order_id"]
        user_id = event["user_id"]

        # Update user order history projection
        history = read_db.get_user_order_history(user_id) or {"orders": [], "total_spent": 0}
        history["orders"].insert(0, {
            "order_id": order_id,
            "total": event["total"],
            "status": event["status"],
            "item_count": len(event["items"]),
            "created_at": event["created_at"]
        })
        history["total_spent"] += event["total"]
        history["order_count"] = len(history["orders"])
        read_db.save_user_order_history(user_id, history)

        # Update product sales projection
        for item in event["items"]:
            read_db.increment_product_sales(item["product_id"], item["quantity"])
```

CQRS without event sourcing is valid and common. The write side is a standard relational database with normalized tables. The read side is a set of projections  -  other database tables, Redis hashes, Elasticsearch documents  -  that are updated in response to write events. The separation is architectural, not technology-driven.

CQRS with event sourcing is the more powerful combination. The write side stores events rather than current state. Projections are built entirely from event replay. Adding a new projection means replaying the event log from the beginning to build it. This gives tremendous flexibility for analytics and reporting, at the cost of more complex infrastructure.

---

## How It Connects

CQRS and event sourcing are commonly combined. Event sourcing provides the immutable event log; CQRS provides the projection mechanism for efficient reads.

[[event-sourcing|Event Sourcing]]

The Saga pattern produces events that update CQRS read models, providing real-time visibility into the saga's progress.

[[saga-pattern|Saga Pattern]]

CQRS's read model can be a search index (Elasticsearch), a cache (Redis), or a data warehouse  -  choosing the right read store depends on the query patterns.

[[data-warehousing|Data Warehousing]]

---

## Common Misconceptions

Misconception 1: "CQRS requires a separate database for reads and writes."
Reality: CQRS can be implemented within a single database by creating separate views or materialized views for read operations. The separation is logical (different models, different optimization goals) and can be physical (separate stores) or not. Start with logical separation; add physical separation if the performance requirements demand it.

Misconception 2: "CQRS means I cannot query the write model directly."
Reality: CQRS is an optimization pattern, not a prohibition. For simple reads where the write model's structure is sufficient and performance is acceptable, querying the write model directly is fine. CQRS is valuable when specific read operations are significantly more complex or have different performance requirements than the write model can efficiently serve.

Misconception 3: "The read model is always more complex than the write model."
Reality: The read model is often simpler  -  it is a denormalized, flat view of data that answers specific questions. The write model is where complexity lives: business rules, invariants, consistency guarantees. The read model trades consistency and normalization for query simplicity and speed.

---

## Why It Matters in Practice

CQRS is most valuable when the system has a few write operations and many diverse read operations with different shapes and performance requirements. A social network has a few write operations (post, follow, like) and enormous read diversity (timeline, notifications, friend suggestions, trending topics). Serving all these from the same normalized write model would require dozens of complex queries. CQRS allows each read pattern to have its own optimized projection.

For Python developers, CQRS often appears as: write to a PostgreSQL write model, update projections in Redis (for fast counts and recent activity) and Elasticsearch (for full-text search), and serve read queries from the appropriate projection. The event-driven update of projections is implemented via Kafka consumer or a database change listener.

---

## Interview Angle

Common question forms:
- "What is CQRS and when would you use it?"
- "How does a read model stay in sync with the write model?"
- "What is the relationship between CQRS and event sourcing?"

Answer frame:
Define CQRS: separate the write model (normalized, consistency-optimized) from the read model (denormalized, query-optimized). Explain projections: materialized views built from write model changes. Describe the eventual consistency: read model is updated asynchronously, slightly behind. Discuss when to use: diverse read patterns that the write model cannot serve efficiently. Distinguish from event sourcing: CQRS is about read/write separation; event sourcing is about write model storage. They combine well but are independent.

---

## Related Notes

- [[event-sourcing|Event Sourcing]]
- [[saga-pattern|Saga Pattern]]
- [[event-driven-architecture|Event-Driven Architecture]]
- [[microservices-basics|Microservices Basics]]
