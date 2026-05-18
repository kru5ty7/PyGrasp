---
title: 03 - Read Replicas
description: "How read replicas scale read-heavy workloads by directing queries to followers, and the replication lag pitfalls that come with this approach."
tags: [read-replicas, replication, database, scaling, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Read Replicas

> Read replicas are the single highest-leverage database scaling technique for read-heavy applications  -  but routing reads to a replica without understanding lag semantics produces correctness bugs that only appear in production.

---

## Quick Reference

**Core idea:**
- Read replicas receive all writes from the primary and serve read queries
- They scale read throughput by distributing queries across multiple servers
- The primary handles all writes; replicas are read-only
- Replication lag means replicas may serve slightly stale data
- Use cases: analytics queries, reporting, dashboard aggregations, full-text search

**Tricky points:**
- Never route a write to a replica  -  it is read-only and the query will fail
- A user who writes a record and immediately reads it back may get stale data from a lagging replica
- Long-running analytics queries on a replica delay replication by locking the replica's query thread
- Connection pooling for replicas must handle failover  -  if a replica dies, queries should fall back to primary
- "Replica lag" and "replica delay" are the same thing  -  how far behind the primary the replica is

---

## What It Is

Think about a popular book in a public library. Only one copy exists, and hundreds of people want to read it simultaneously. The library cannot lend the book to multiple people at once. The solution: make several photocopies (with permission). Now ten readers can read simultaneously. When the original is updated (a new edition), the library must update all the photocopies. This takes time. In the interim, some readers have the old text. This is read replica logic.

A read replica is a database server that has a complete, continuously-updated copy of the primary database and accepts read queries. In a standard setup, the primary database receives all writes. Those writes are streamed to replicas via replication. Replicas apply the writes and become available for reads. Application code (or the connection pool layer) routes `SELECT` queries to replicas and `INSERT/UPDATE/DELETE` queries to the primary.

Read-heavy applications benefit enormously from this pattern. Web applications typically read far more than they write  -  a user browsing a product catalog triggers dozens of read queries and perhaps one write (an order). By routing reads to a replica, you remove that read load from the primary entirely. The primary's CPU and I/O are freed for writes and for the replication data stream to replicas. Read capacity scales linearly: two replicas means twice the read throughput, three means three times. Adding replicas is an operational operation  -  no code changes required, no downtime.

The most common use case for dedicated read replicas (beyond serving application reads) is analytics. Analytics queries  -  "how many orders were placed this week, broken down by region, product category, and hour?"  -  involve scanning large amounts of data, aggregating, and filtering. These queries are expensive: they hold locks, consume large amounts of I/O, and can run for minutes or hours. Running them on the primary blocks other queries. A dedicated analytics replica serves these queries without impacting application performance. The replica may lag by minutes or hours under heavy analytic load, but for reporting purposes, data that is a few minutes stale is acceptable.

---

## How It Actually Works

Setting up a read replica in PostgreSQL requires configuring streaming replication. The primary server generates a WAL (Write-Ahead Log) stream. The replica connects to the primary's replication port, receives the WAL stream, and applies it. The replica runs in "hot standby" mode, which means it accepts read queries while applying replication data. These two activities  -  applying replication writes and serving read queries  -  compete for the same CPU and I/O resources on the replica.

Application-level read-routing can be implemented directly in the connection pool configuration. Libraries like SQLAlchemy support read/write splitting via `engine.execution_options(postgresql_readonly=True)`. In Python frameworks, some teams implement a custom database middleware layer that intercepts queries and routes them based on the query type (DDL/DML to primary, SELECT to replica). Others use connection-level abstractions.

```python
from sqlalchemy import create_engine, text, event
from sqlalchemy.orm import sessionmaker

# Two database engines: one for writes, one for reads
primary_engine = create_engine("postgresql://user:pass@primary-host/db")
replica_engine = create_engine("postgresql://user:pass@replica-host/db")

# Read-only session bound to replica
ReadSession = sessionmaker(bind=replica_engine)
WriteSession = sessionmaker(bind=primary_engine)

class UserRepository:
    def get_user(self, user_id: int, require_fresh: bool = False) -> dict | None:
        """
        Use replica for most reads; use primary for reads that must be fresh
        (e.g., immediately after a write in the same request).
        """
        engine = primary_engine if require_fresh else replica_engine
        with engine.connect() as conn:
            result = conn.execute(
                text("SELECT * FROM users WHERE id = :id"),
                {"id": user_id}
            )
            row = result.fetchone()
            return dict(row._mapping) if row else None

    def create_user(self, data: dict) -> int:
        """Always write to primary."""
        with primary_engine.connect() as conn:
            result = conn.execute(
                text("INSERT INTO users (name, email) VALUES (:name, :email) RETURNING id"),
                data
            )
            conn.commit()
            return result.fetchone()[0]

# Application pattern: after write, read from primary
def register_user(data: dict) -> dict:
    repo = UserRepository()
    user_id = repo.create_user(data)
    # Read back from primary to return current state (avoid replica lag)
    user = repo.get_user(user_id, require_fresh=True)
    return user
```

Replica lag monitoring is essential for any system using read replicas. PostgreSQL exposes lag in seconds via `pg_stat_replication` on the primary and `pg_last_xact_replay_timestamp()` on the replica. Setting up alerting on lag above a threshold (say, 30 seconds) prevents the system from silently serving data that is minutes stale during a heavy load or network issue. Most cloud database services (AWS RDS, GCP Cloud SQL) expose replica lag as a CloudWatch/Cloud Monitoring metric.

Long-running analytics queries on a replica can cause "replication lag amplification." When the replica is executing a heavy query, it may not be able to apply incoming WAL as quickly, causing lag to grow. When the query finishes, the replica catches up. For very heavy analytics workloads, a separate read replica dedicated exclusively to analytics (never receiving application read traffic) prevents this problem from affecting the application replica.

---

## How It Connects

Read replicas are built on top of database replication. Understanding how the replication log is streamed and applied is foundational to understanding why lag exists and how large it can grow.

[[database-replication|Database Replication]]

Before routing all reads to a replica, consider whether a cache can absorb the read load entirely. A cache hit is faster than any database read, primary or replica.

[[caching-basics|Caching Basics]]

For analytics queries that regularly scan large amounts of historical data, a dedicated analytics database or data warehouse is more appropriate than a replica  -  it avoids competing with the OLTP workload entirely.

[[data-warehousing|Data Warehousing]]

---

## Common Misconceptions

Misconception 1: "I can scale writes by adding more read replicas."
Reality: Read replicas only scale reads. All writes still go to the primary. If the primary is the write bottleneck (CPU, IOPS, or write throughput), adding replicas does nothing for it. Write scaling requires either vertical scaling of the primary, database sharding, or a write-optimized distributed database.

Misconception 2: "My read replica is in sync with the primary within milliseconds  -  I can always trust it."
Reality: Under normal conditions with light load, lag is typically under 100ms. But under heavy write load, replica catch-up takes longer. During the seconds or minutes it takes for a replica to catch up after a burst of writes, reads from the replica are stale by that amount. A system that loads the replica's current lag before routing a query can make smarter routing decisions.

Misconception 3: "Read replicas provide high availability  -  if the primary dies, I can use a replica."
Reality: Read replicas do provide a path to availability after the primary fails, but not instantly or automatically in most setups. Promoting a replica to primary requires an explicit action (or an orchestration tool like Patroni/Orchestrator to do it automatically). During the promotion window (10 - 60 seconds typically), writes are unavailable. A standby replica configured specifically for failover is different from a read-scaling replica, though the same machine can serve both roles.

---

## Why It Matters in Practice

For Python web applications using Django or FastAPI with SQLAlchemy, adding read replicas is often the single change that extends a database's useful life by months or years. A primary that was struggling at 5,000 read queries per second can have that load offloaded to two replicas, leaving the primary free for writes and achieving 15,000 total read QPS.

The practical gotcha is always the read-your-writes problem: a user submits a form (write to primary), their browser makes an immediate follow-up request that reads the data they just submitted (routed to a lagging replica), and they see old data or nothing at all. The fix is simple but requires discipline: after a write, force the immediately following read to go to the primary. This should be implemented in the data access layer, not scattered through application controllers.

---

## Interview Angle

Common question forms:
- "How would you scale a read-heavy database?"
- "What is the difference between a read replica and a standby database?"
- "What is the read-your-writes problem and how do you solve it?"

Answer frame:
Explain read replicas: all writes to primary, reads distributed across replicas, scales read throughput linearly. Describe replication lag: the delay between write and replica visibility, typically small but variable. Explain the read-your-writes problem: write to primary, read from lagging replica, see stale data. The fix: route post-write reads to primary. Distinguish read replica (for scale) from standby (for failover)  -  though both use the same technology. Close with monitoring: lag as a key metric.

---

## Related Notes

- [[database-replication|Database Replication]]
- [[database-sharding|Database Sharding]]
- [[caching-basics|Caching Basics]]
- [[data-warehousing|Data Warehousing]]
- [[sqlalchemy-core|SQLAlchemy Core]]
