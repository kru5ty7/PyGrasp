---
title: 05 - SQL vs NoSQL
description: "When to choose a relational database and when to choose NoSQL  -  schema flexibility, query power, ACID vs eventual consistency, and what the choice actually costs."
tags: [sql, nosql, database, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# SQL vs NoSQL

> The SQL vs NoSQL question is not a technology preference debate  -  it is a data model and consistency requirement question, and the wrong choice creates architectural debt that takes years to undo.

---

## Quick Reference

**Core idea:**
- SQL databases: fixed schema, relational model, JOIN support, ACID transactions, strong consistency
- NoSQL databases: flexible schema, various data models (document, key-value, wide-column, graph), eventual consistency by default
- The core SQL advantage is JOINs  -  data normalization and complex queries across related tables
- The core NoSQL advantage is schema flexibility, horizontal scaling, and native JSON document support
- "NoSQL" is not one thing  -  key-value, document, wide-column, and graph stores have different strengths

**Tricky points:**
- Denormalization (NoSQL's typical pattern) speeds reads but makes writes more complex and creates update anomalies
- Many modern NoSQL stores (MongoDB 4+, DynamoDB) offer limited transaction support  -  the line has blurred
- NoSQL is not inherently faster  -  the performance difference depends on the access pattern and query shape
- Schema migration in NoSQL is "just as hard" as in SQL  -  it is just done in application code instead of DDL
- The biggest practical difference is often tooling and developer familiarity, not database capabilities

---

## What It Is

Imagine two filing systems. The first is a structured office with labeled folders in labeled drawers in labeled cabinets. Every document goes in the right folder according to strict rules. Finding all documents related to a specific client is easy  -  you look in the "Clients" cabinet, find the "Smith, John" folder, and get every document about that client. The rules prevent duplicate or inconsistent filing. But adding a new document category means updating all the rules first. This is a relational SQL database.

The second filing system is a series of bins. Each bin has a label, and you put whatever you want in the bin. Different items in the bin can have different information recorded on them. Finding all items with a specific attribute requires checking every bin that might have items matching that attribute. Adding a new attribute to some items requires no reorganization  -  you just write it on those items going forward. This is closer to a document store like MongoDB.

Relational databases (PostgreSQL, MySQL, SQLite, SQL Server, Oracle) organize data into tables with fixed schemas. Every row in a table has the same columns. Related data in different tables is linked via foreign keys. JOIN operations combine related rows from multiple tables at query time. This normalization eliminates data duplication: a customer's address is stored once and referenced by many orders, not duplicated into each order row. The schema enforces data integrity at the database level  -  a foreign key constraint prevents an order from referencing a non-existent customer.

NoSQL databases cover four quite different models. Document stores (MongoDB, CouchDB, Firestore) store JSON-like documents with flexible schemas  -  different documents in the same collection can have different fields. Key-value stores (Redis, DynamoDB in its simplest use) store arbitrary values by key. Wide-column stores (Cassandra, HBase) organize data as rows with a dynamic number of columns  -  optimized for time-series and event data. Graph databases (Neo4j, Amazon Neptune) model relationships as first-class data structures, enabling efficient traversal of deeply connected data.

---

## How It Actually Works

The SQL advantage is expressive querying. A single SQL query can join five tables, filter on conditions across all of them, aggregate values, and return a shaped result. This declarative power enables complex reporting and ad-hoc analysis without application-level loops. ORM frameworks like SQLAlchemy translate Python objects into this query language. Normalized schemas ensure that updating a customer's address in one place is immediately reflected everywhere that customer is referenced.

Denormalization is the NoSQL alternative to joins. Instead of storing product information in a `products` table and referencing it from the `orders` table, a MongoDB document store might embed the product's name and price directly in the order document. This means reading an order requires only one document fetch  -  no join. But updating the product's name requires finding every order document that contains that product and updating each one. For read-heavy workloads where the product name changes rarely, this is excellent. For data that changes frequently and is embedded in millions of documents, update anomalies become a maintenance nightmare.

```python
# SQL: normalized schema  -  each piece of data stored once
# customer name lives in customers table; order references it via FK
SELECT o.id, o.total, c.name, c.email
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.created_at > '2026-01-01'

# NoSQL (MongoDB): denormalized document  -  customer data embedded in order
{
    "_id": "order_12345",
    "total": 89.99,
    "created_at": "2026-02-14T10:30:00Z",
    "customer": {
        "name": "Alice Smith",       # duplicated in every order
        "email": "alice@example.com" # must update all orders if email changes
    },
    "items": [
        {"product_name": "Widget A", "price": 29.99, "qty": 3}
    ]
}

# Mongo query: simple, no join needed
db.orders.find({"created_at": {"$gt": datetime(2026, 1, 1)}})
```

The ACID vs eventual consistency difference is the most operationally significant. SQL databases (by default) provide full ACID guarantees: a transfer between two accounts is atomic, consistent, isolated, and durable. NoSQL databases (by default) provide eventual consistency: a write to one node propagates to others over time. For applications where correctness is critical  -  financial transactions, inventory management, medical records  -  the eventual consistency of most NoSQL stores requires careful compensating application logic. For applications where availability and write throughput matter more than perfect consistency  -  social feeds, analytics events, user activity logs  -  eventual consistency is a reasonable tradeoff.

Schema migration is often cited as a SQL disadvantage. Adding a column or changing a data type requires a migration script and, for large tables, can lock the table during the migration. NoSQL databases appear to escape this: a document can have new fields without any migration. In practice, schema changes in NoSQL are "hidden in application code"  -  every piece of code that reads a document must handle both old-format documents (without the new field) and new-format documents (with it). This is not simpler than a migration; it is a migration spread across application code and time.

---

## Visualizer

<iframe src="/static/visualizers/sql-vs-nosql.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="SQL vs NoSQL Visualizer"></iframe>

---

## How It Connects

The consistency guarantees of SQL vs NoSQL connect directly to the ACID vs BASE distinction. SQL databases are ACID; most NoSQL databases are BASE.

[[acid-vs-base|ACID vs BASE]]

The decision of when to scale horizontally (where NoSQL typically excels) versus vertically (where well-tuned SQL can get surprisingly far) connects to the fundamental scaling strategies.

[[horizontal-vs-vertical-scaling|Horizontal vs Vertical Scaling]]

When a SQL database's read load exceeds what the primary can handle, read replicas provide SQL-equivalent scalability without the NoSQL consistency tradeoffs.

[[read-replicas|Read Replicas]]

---

## Common Misconceptions

Misconception 1: "NoSQL scales better than SQL."
Reality: The ease of horizontal scaling differs by specific database, not category. Google Spanner is SQL and scales globally. A single PostgreSQL instance with good indexes and a few read replicas handles tens of thousands of requests per second for most applications. The scalability ceiling of SQL is much higher than commonly believed. NoSQL databases designed for sharding (Cassandra, DynamoDB) do make horizontal scaling easier, but this comes with consistency tradeoffs.

Misconception 2: "NoSQL is faster because it avoids joins."
Reality: Avoiding joins at query time means the join work was either pushed to write time (denormalization) or to application code (application-level joins). Denormalization can improve read speed for specific access patterns at the cost of write complexity. For access patterns that match the denormalized schema, NoSQL can be faster. For access patterns that do not match, it can be much slower.

Misconception 3: "MongoDB's flexible schema means I don't need to think about data modeling."
Reality: Schema design matters as much in MongoDB as in PostgreSQL  -  arguably more. A poorly designed document schema with heavy nesting, frequent cross-reference needs, or large embedded arrays creates query and indexing problems. "Schema on read" (NoSQL) just moves the schema from the database constraint to application validation. Without discipline, you end up with undocumented, inconsistent documents that are impossible to query reliably.

---

## Why It Matters in Practice

The SQL vs NoSQL decision should be driven by three questions: What are my access patterns? What consistency do I need? How much do I value tooling and developer familiarity? For most web applications with relational data (users have orders, orders have products, products have categories), SQL is the right choice: JOINs are natural, ACID transactions prevent correctness bugs, and mature tooling (PostgreSQL, SQLAlchemy, Django ORM) makes development fast. For specific use cases  -  social graphs, time-series metrics, document stores for heterogeneous content, high-write distributed systems  -  specialized NoSQL stores may be better fits.

The worst outcome is choosing NoSQL because it feels more modern, and then spending months implementing application-level joins, consistency checks, and schema migrations that a SQL database would have provided for free.

---

## Interview Angle

Common question forms:
- "When would you choose MongoDB over PostgreSQL for a new service?"
- "What are the trade-offs of NoSQL vs SQL?"
- "How do you handle a relationship between two entities in a document database?"

Answer frame:
Describe SQL strengths: JOINs, ACID, mature tooling, schema enforcement. Describe NoSQL strengths: schema flexibility, native document model, horizontal scaling story. Frame the choice around access patterns: if queries always access data by the document's natural key and rarely need cross-document joins, a document store is efficient. If queries frequently cross-reference related entities, SQL is simpler. Acknowledge the consistency tradeoff: eventual consistency vs ACID. Give concrete examples: e-commerce orders (SQL), user activity events (document or time-series), social graph (graph DB).

---

## Related Notes

- [[acid-vs-base|ACID vs BASE]]
- [[database-sharding|Database Sharding]]
- [[database-replication|Database Replication]]
- [[cap-theorem|CAP Theorem]]
- [[sqlalchemy-core|SQLAlchemy Core]]
