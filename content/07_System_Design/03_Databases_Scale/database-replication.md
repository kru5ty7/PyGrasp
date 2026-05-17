---
title: 01 - Database Replication
description: "How database replication copies data from a leader to followers — synchronous vs asynchronous, replication lag, and what can go wrong when replicas fall behind."
tags: [replication, database, consistency, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Database Replication

> Replication is how a database achieves high availability and read scalability — but replication lag is the hidden variable that can cause subtle data consistency bugs that only appear at scale.

---

## Quick Reference

**Core idea:**
- Replication copies every write from the leader (primary) to one or more followers (replicas)
- Synchronous replication: the leader waits for the follower to confirm the write before acknowledging the client
- Asynchronous replication: the leader acknowledges the client immediately; followers catch up in the background
- Replication lag: the delay between a write on the leader and its appearance on a follower
- Leader failure handling: promote a follower to leader, losing writes that have not yet replicated

**Tricky points:**
- Asynchronous replication is the default in most databases — there is always some lag, even if typically small
- A read from a replica may not reflect writes made seconds ago by the same user (read-your-writes violation)
- Semi-synchronous replication waits for at least one replica to confirm — a compromise
- Circular replication (multi-master with two-way replication) exists but creates conflict resolution challenges
- "Hot standby" vs "warm standby": hot standby accepts read queries; warm standby is a replica not available for queries

---

## What It Is

Think of a company with one accounting ledger. Every transaction gets written into this ledger. Now imagine the ledger is kept in a single filing cabinet in one office. If that office burns down, all the financial records are gone. The company decides to maintain two copies of the ledger: a primary in the main office (the leader) and an exact copy in a backup office (the replica). Every time a transaction is recorded in the main office, someone drives a copy to the backup office.

Two questions immediately arise. First, does the accountant wait for the driver to return with a confirmation before telling the customer their transaction is complete? That is synchronous replication — slow, but you never lose a transaction. Or does the accountant tell the customer "done!" the moment the main ledger is written, while the driver is still en route to the backup? That is asynchronous replication — fast, but if the main office burns down during the drive, the backup is incomplete.

Database replication is this exact mechanism, applied to database writes. The leader database processes all writes. It maintains a replication log — typically the same write-ahead log (WAL) used for crash recovery. Follower databases connect to the leader and stream this log, applying each write in the same order. The result is that followers maintain an eventually-consistent copy of the leader's data.

Replication serves two purposes. The first is high availability: if the leader fails, a follower can be promoted to leader. The system continues operating after a brief failover period rather than going offline until the primary is restored. The second is read scaling: follower databases can serve read queries, distributing the read load across multiple machines. For read-heavy workloads with a much larger read load than write load, this can be highly effective.

---

## How It Actually Works

Statement-based replication was an early approach: rather than replicating the binary log changes, the leader sends the SQL statements that caused them (INSERT, UPDATE, DELETE). Followers re-execute the statements. This is human-readable and useful for cross-version compatibility, but it fails for non-deterministic operations like `NOW()`, `RAND()`, or triggers that produce different results on different machines.

Row-based replication (the modern default in MySQL and PostgreSQL) replicates the actual data changes — which rows were inserted, which column values changed, which rows were deleted. This is deterministic: regardless of what triggered the change, the follower applies the exact same row mutations. The downside is larger log volume for write-heavy workloads (every changed row must be transmitted).

The Write-Ahead Log (WAL) is the same structure PostgreSQL uses for crash recovery — it contains a sequential record of every change at the byte level. PostgreSQL's streaming replication ships WAL segments directly to replicas. The replica applies them, maintaining byte-for-byte consistency with the leader. MySQL's binary log is similar but format-dependent (STATEMENT, ROW, or MIXED mode).

Replication lag is an inescapable reality of asynchronous replication. Network latency, replica CPU load, and write volume all contribute. In low-load scenarios, lag is typically milliseconds. Under heavy write load, replication lag can grow to seconds or minutes. Applications that read from replicas must account for this. The classic failure mode is a user who writes a record and immediately reads it back — routed to a replica that has not yet received the write, they see nothing, and believe their write was lost.

```python
import psycopg2

# Checking replication lag in PostgreSQL
def get_replication_lag_seconds(replica_conn):
    """Query a replica to check its lag behind the primary."""
    with replica_conn.cursor() as cur:
        cur.execute("""
            SELECT
                EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))
                AS replication_lag_seconds
        """)
        result = cur.fetchone()
        return result[0] if result else None

# Application-level read-your-writes: route to primary after writes
class DatabaseRouter:
    def __init__(self, primary_dsn: str, replica_dsn: str):
        self.primary = psycopg2.connect(primary_dsn)
        self.replica = psycopg2.connect(replica_dsn)
        self._use_primary = False

    def after_write(self):
        """Force reads to go to primary for this session."""
        self._use_primary = True

    def get_connection(self, require_fresh: bool = False):
        if require_fresh or self._use_primary:
            return self.primary
        return self.replica
```

Failover — promoting a replica to primary when the leader fails — introduces risk. In asynchronous replication, the promoted replica may not have received all writes from the failed primary. These writes are lost. The new primary accepts new writes on top of its partial state. If the old primary later recovers, it has writes the new primary does not, causing a "split brain" situation. Properly managed failover tools (like Patroni for PostgreSQL, or orchestrated by cloud-managed databases) detect this situation and prevent the old primary from accepting writes after recovery.

---

## How It Connects

Replication is the foundation of read scaling via read replicas. Understanding how replication lag affects reads from replicas is essential before routing queries to them.

[[read-replicas|Read Replicas]]

The guarantees that replication provides (or fails to provide) depend on whether it is synchronous or asynchronous. This maps directly onto the consistency models spectrum.

[[consistency-models|Consistency Models]]

The CAP theorem's "partition tolerance" dimension is realized when a replica is cut off from the leader. Understanding the theorem explains why the system must choose between consistency and availability in that scenario.

[[cap-theorem|CAP Theorem]]

---

## Common Misconceptions

Misconception 1: "My database replica is always up to date — reads from it are current."
Reality: Unless you are using synchronous replication (and paying its latency cost), your replica is always behind the primary by some amount — typically milliseconds under low load, potentially seconds or more under heavy load. Never assume a replica read reflects a write that just happened.

Misconception 2: "Promoting a replica to primary is safe and lossless."
Reality: With asynchronous replication, the promoted replica may have missed some writes from the failed primary. These writes are permanently lost. Some database systems (like PostgreSQL with synchronous_commit=remote_apply) can guarantee zero data loss, but only at the cost of write latency for every transaction.

Misconception 3: "More replicas means more write capacity."
Reality: Replication copies writes to replicas — it does not share the write load. Every write still goes to the leader (primary). More replicas increase read capacity. If your bottleneck is writes, replication does not help. You need database sharding or a different write architecture.

---

## Why It Matters in Practice

Replication lag is the source of a specific category of subtle bugs. A user creates an account, their browser immediately redirects to a profile page, and the profile page queries a read replica that has not yet received the new user record — 404 Not Found. The user reports the bug; it cannot be reproduced because by the time the engineer investigates, the replica has caught up. These timing-dependent bugs are notoriously difficult to debug without understanding replication.

The practical mitigation is to route writes and immediately-subsequent reads to the primary, and route all other reads to replicas. This is the "read-your-writes consistency" session guarantee. Implementing it requires tracking in the session layer which operations are "post-write" and routing accordingly.

---

## Interview Angle

Common question forms:
- "What is replication lag and how do you handle it in an application?"
- "What's the difference between synchronous and asynchronous replication?"
- "What happens when the primary database fails?"

Answer frame:
Define leader/follower replication. Explain synchronous (no lag, high write latency) vs asynchronous (lag, low write latency). Describe replication lag and the read-your-writes problem it creates. Explain failover: replica promotion, potential write loss with async. Describe the application-level solution: route post-write reads to primary. Close with the operational monitoring need: track replication lag as a key metric.

---

## Related Notes

- [[read-replicas|Read Replicas]]
- [[database-sharding|Database Sharding]]
- [[consistency-models|Consistency Models]]
- [[cap-theorem|CAP Theorem]]
