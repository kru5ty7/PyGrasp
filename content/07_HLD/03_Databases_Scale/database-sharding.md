---
title: 02 - Database Sharding
description: "Horizontal partitioning of a database across multiple machines  -  shard key selection, hotspot problems, and why cross-shard queries are expensive."
tags: [sharding, partitioning, database, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Database Sharding

> Sharding is the last resort of the database scaling toolkit  -  it solves problems that nothing else can, but it introduces complexity that nothing else can avoid.

---

## Quick Reference

**Core idea:**
- Sharding splits a large table across multiple database servers (shards) based on a shard key
- Each shard holds a subset of rows; together, all shards hold all data
- The shard key determines which shard a given row lives on  -  choice of shard key is critical
- A hotspot occurs when a poor shard key causes most traffic to hit one shard
- Cross-shard queries (JOINs, aggregates across shards) are expensive or impossible to execute natively

**Tricky points:**
- Sharding is irreversible without significant migration work  -  choose shard key carefully upfront
- Resharding (redistributing data across a different number of shards) is extremely expensive
- Application code must be aware of sharding  -  queries must be routed to the right shard
- Foreign key constraints across shards cannot be enforced by the database
- "Logical shard" vs "physical shard": you can have more logical shards than physical machines, easing future resharding

---

## What It Is

Imagine a library where every book about science goes in Building A, every book about history in Building B, and every book about literature in Building C. This is horizontal partitioning  -  the data is divided across buildings by category. If most of the library's visitors want science books, Building A is overwhelmed while Buildings B and C are underutilized. The partition key (subject category) was a poor choice. If instead you partition by the first letter of the author's last name (A - H in one building, I - P in another, Q - Z in a third), the load is more evenly distributed  -  assuming author names follow a roughly uniform distribution.

Database sharding is horizontal partitioning across multiple database servers. Instead of one database instance holding the entire `users` table with 100 million rows, you have four shards each holding 25 million rows. A query for user ID 42,001,523 is routed to the shard responsible for that ID range, rather than scanning the full 100M row table. Write capacity is distributed  -  each shard's primary handles only its fraction of the write load. Storage capacity scales linearly with the number of shards.

The shard key is the column (or columns) used to determine which shard a row belongs to. The most common shard strategies are range-based (user IDs 1 - 25M on shard 1, 25M - 50M on shard 2) and hash-based (shard_number = hash(user_id) % num_shards). Range-based sharding enables range queries within a shard (get all users with IDs 1,000 - 2,000) but can create hot spots if recent IDs are accessed far more than old ones. Hash-based sharding distributes keys uniformly but makes range queries impossible without querying all shards.

Choosing the wrong shard key is one of the most consequential mistakes in system design. A shard key with low cardinality (for example, country code in a system with 80% US users) puts 80% of traffic on one shard. A shard key that is a monotonically increasing value (like a timestamp) causes all new writes to go to the "hot" shard for the current time range while older shards receive no writes. The ideal shard key has high cardinality, uniform distribution, and correlates with the most common access pattern.

---

## How It Actually Works

Application-level sharding requires every database query to be routed to the correct shard. This typically means a sharding library or a service layer that accepts queries with a shard key, computes the target shard, and forwards the query. The simplest implementation for a Python application is a dictionary mapping shard ID to database connection, with a function that computes the shard ID from the query's primary key.

Range-based sharding stores a routing table: ranges of shard key values mapped to shard server addresses. The routing table is consulted for every query. This enables resharding with minimal data movement (only the range boundary changes), but the routing table itself becomes a bottleneck and single point of failure if not carefully managed.

Hash-based sharding computes shard ID from the key: `shard_id = hash(key) % num_shards`. This is uniform and requires no routing table, but changing `num_shards` invalidates almost all routing decisions (the same problem consistent hashing was invented to solve). Using consistent hashing for shard routing allows adding or removing shards with minimal data movement.

```python
import hashlib
from typing import Any
import psycopg2

class ShardedDatabase:
    """Simple hash-based sharding router."""

    def __init__(self, shard_configs: list[dict]):
        self.num_shards = len(shard_configs)
        self.connections = [
            psycopg2.connect(**cfg) for cfg in shard_configs
        ]

    def _get_shard(self, shard_key: str) -> psycopg2.extensions.connection:
        shard_id = int(hashlib.md5(str(shard_key).encode()).hexdigest(), 16) % self.num_shards
        return self.connections[shard_id]

    def get_user(self, user_id: int) -> dict | None:
        conn = self._get_shard(user_id)
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
            return cur.fetchone()

    def create_user(self, user_id: int, data: dict) -> None:
        conn = self._get_shard(user_id)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO users (id, name, email) VALUES (%s, %s, %s)",
                (user_id, data['name'], data['email'])
            )
        conn.commit()

    def get_all_users(self) -> list:
        """Cross-shard query: must hit every shard."""
        all_users = []
        for conn in self.connections:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM users")
                all_users.extend(cur.fetchall())
        return all_users  # scatter-gather  -  expensive!
```

Cross-shard queries are the most painful consequence of sharding. A query like "find all users in this organization" requires querying all shards if the shard key is user ID, since organization members can be on any shard. The application must fan out the query to every shard, collect results, and merge them  -  a scatter-gather operation. For aggregation queries (COUNT, SUM, AVG across all users), each shard computes a partial result and the application combines them. For JOIN queries across tables on different shards, the application must perform the join in memory.

To minimize cross-shard queries, the shard key should match the most common query pattern. If 90% of queries are "get data for user X," sharding by user ID means 90% of queries hit exactly one shard. If you shard by geographic region instead, every query that does not filter by region becomes a cross-shard scatter. The shard key choice is a bet on which access patterns matter most.

---

## Visualizer

<iframe src="/static/visualizers/database-sharding.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="Database Sharding Visualizer"></iframe>

---

## How It Connects

Before sharding, the standard progression is: single database -> add read replicas -> add a caching layer -> optimize indexes -> then consider sharding. Read replicas handle most read scaling; sharding is for write scaling and storage.

[[read-replicas|Read Replicas]]

Consistent hashing solves the shard reassignment problem that arises when the number of shards changes. Understanding consistent hashing is a prerequisite for designing a reshardable system.

[[consistent-hashing|Consistent Hashing]]

The decision to shard often coincides with the decision to move to a NoSQL database, which is typically built with sharding in mind from the ground up. The SQL vs NoSQL trade-off conversation includes sharding capability as a key factor.

[[sql-vs-nosql|SQL vs NoSQL]]

---

## Common Misconceptions

Misconception 1: "I should shard my database now to prepare for future scale."
Reality: Sharding adds significant complexity to every database operation, every query, every migration, and every operational task. It is the last resort after caching, read replicas, vertical scaling, and query optimization have been exhausted. Sharding prematurely creates complexity that slows development without providing benefit. Instrument first, shard when the data proves it is necessary.

Misconception 2: "Once I shard, I can scale to any size."
Reality: Sharding helps with storage and write throughput, but cross-shard operations scale poorly. Some queries become physically impossible to express efficiently in a sharded system. Analytics workloads, complex reporting, and JOINs across entities with different shard keys degrade significantly. Many large-scale systems maintain a separate data warehouse (OLAP) for analytics to avoid running these queries on the sharded OLTP database.

Misconception 3: "Adding more shards is easy after the fact."
Reality: Changing the number of shards in a hash-based sharding scheme requires migrating approximately (N-1)/N of all data to new locations. For a 1 TB database adding one new shard (going from 4 to 5 shards), roughly 80% of the data must be moved. This is a major operation requiring careful planning, potential downtime, and significant I/O. Designing with logical shards (more logical shards than physical machines, with consistent hashing for mapping) makes this less painful.

---

## Why It Matters in Practice

Sharding is the right tool for databases that have exhausted all other scaling options and face specific bottlenecks: write throughput exceeding primary's capacity, or storage exceeding what a single machine can hold. For most Python web applications serving millions of users, a well-indexed PostgreSQL database with read replicas and a caching layer is sufficient. Sharding becomes relevant for systems with billions of rows, high write concurrency, or multi-petabyte datasets.

When designing a system that will likely need sharding eventually, the most important decision is choosing the right shard key early  -  even if you run on a single database initially. The shard key shapes the data model. Getting it right before you have millions of rows is far easier than migrating to a different shard key after.

---

## Interview Angle

Common question forms:
- "When would you shard a database, and what are the trade-offs?"
- "How do you choose a shard key?"
- "How do cross-shard queries work?"

Answer frame:
Define sharding as horizontal partitioning across multiple servers. Explain range vs hash sharding trade-offs. Describe shard key selection criteria: high cardinality, uniform distribution, matches primary access pattern. Explain cross-shard queries: scatter-gather, in-memory joins, why they are expensive. Describe the resharding challenge and consistent hashing as a mitigation. Emphasize that sharding is a last resort  -  enumerate all simpler approaches first.

---

## Related Notes

- [[database-replication|Database Replication]]
- [[read-replicas|Read Replicas]]
- [[consistent-hashing|Consistent Hashing]]
- [[sql-vs-nosql|SQL vs NoSQL]]
