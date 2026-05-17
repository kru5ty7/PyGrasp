---
title: 04 - ACID vs BASE
description: "ACID and BASE represent two different consistency philosophies for data systems — understanding when each applies is fundamental to choosing the right storage technology."
tags: [acid, base, consistency, transactions, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# ACID vs BASE

> ACID and BASE are not competing technologies — they are competing philosophies about what guarantees a data system should provide, and the right choice depends entirely on what your data means.

---

## Quick Reference

**Core idea:**
- ACID: Atomicity, Consistency, Isolation, Durability — the guarantees of relational databases
- BASE: Basically Available, Soft state, Eventual consistency — the approach of most distributed NoSQL stores
- ACID prioritizes correctness; BASE prioritizes availability and performance
- ACID transactions guarantee that a set of operations either all succeed or all fail
- BASE systems accept temporary inconsistency in exchange for higher availability and throughput

**Tricky points:**
- "Consistency" in ACID means constraint enforcement (foreign keys, schema rules), not the same as CAP consistency
- BASE is not a single protocol — it is a description of emergent behavior across many NoSQL systems
- ACID does not mean "no distribution" — distributed ACID (via 2PC or Paxos) is possible but expensive
- Eventually consistent does not mean "eventually correct" — conflicts still must be resolved somehow
- Some systems (Google Spanner, CockroachDB) offer distributed ACID, blurring the traditional divide

---

## What It Is

Think about a bank. When you transfer money from your savings account to your checking account, two things must happen: the savings account must decrease and the checking account must increase. If only one of those operations happens — power cut after the debit, network failure before the credit — you have lost money or created money from nothing. A bank cannot tolerate this. The bank's database must guarantee that either both operations happen together, or neither happens. It must guarantee that your balance constraints are enforced at every moment. It must guarantee that two simultaneous transfers do not interfere with each other. And it must guarantee that once a transfer is confirmed, it will not be forgotten, even if the server crashes a second later. These four guarantees together are ACID.

ACID stands for Atomicity (a transaction is all-or-nothing), Consistency (a transaction moves the database from one valid state to another, enforcing all rules and constraints), Isolation (concurrent transactions do not interfere with each other — each sees a clean view of the data), and Durability (once a transaction is committed, it persists even if the system crashes). These properties together make a database suitable for situations where correctness is non-negotiable: financial records, inventory counts, medical records, order management.

BASE takes the opposite philosophy, born from the observation that enforcing ACID properties across many distributed machines is expensive. BASE systems — the term was coined partly as a deliberate contrast to ACID — accept that perfect consistency is too costly to maintain at all times. "Basically Available" means the system responds to requests even if the data might be slightly stale. "Soft state" means the system's state can change over time even without new input, as consistency updates propagate. "Eventual consistency" means that if no new updates are made, all replicas will eventually converge to the same value. Cassandra, DynamoDB, CouchDB, and Riak are BASE systems.

The philosophical difference is about failure modes. ACID systems, when they cannot guarantee correctness, return an error. BASE systems, when they cannot guarantee freshness, return their best current answer. For a social media feed, returning a slightly outdated post count is acceptable. For a bank balance, it is not. The choice between ACID and BASE begins with asking: what is worse — stale data or no data?

---

## How It Actually Works

ACID databases achieve their guarantees through a combination of write-ahead logging, lock management, and multi-version concurrency control (MVCC). Atomicity is implemented by the write-ahead log: every operation is recorded to a log before it is applied; on crash recovery, uncommitted transactions are rolled back. Isolation is achieved through either locking (readers block writers, writers block readers) or MVCC (each transaction sees a snapshot of the data as of when the transaction started, allowing reads and writes to proceed concurrently without blocking). Durability is achieved by flushing the write-ahead log to persistent storage before acknowledging a commit.

The cost of these guarantees is real. Write-ahead logging adds I/O overhead. Locking or MVCC adds CPU and memory overhead. Distributed transactions across multiple database nodes — using two-phase commit — require round-trip coordination between nodes, adding latency and introducing the possibility of being stuck in a prepared state if the coordinator crashes. This is why, as data scales beyond a single machine, engineers often sacrifice some ACID guarantees in exchange for performance and availability.

BASE systems achieve availability and performance by abandoning cross-node coordination. A write to Cassandra is written to multiple replicas asynchronously. The client receives an acknowledgment as soon as a configurable number of replicas confirm the write (configurable quorum). If two clients write to the same key at nearly the same time and reach different replicas, the system has a conflict. Cassandra resolves this with last-write-wins using wall-clock timestamps. Other systems use vector clocks or application-level merge functions. The point is that conflict resolution is explicit and imperfect, whereas ACID isolation makes conflicts impossible by serializing transactions.

```python
# ACID: SQLAlchemy transaction — either both writes succeed or neither does
from sqlalchemy.orm import Session

def transfer_funds(session: Session, from_account: int, to_account: int, amount: float):
    with session.begin():  # transaction — atomic
        source = session.get(Account, from_account)
        target = session.get(Account, to_account)
        if source.balance < amount:
            raise ValueError("Insufficient funds")
        source.balance -= amount
        target.balance += amount
    # commit happens here; if anything raises, rollback is automatic

# BASE: Cassandra write — fire and forget, eventual consistency
from cassandra.cluster import Cluster

def record_event(user_id: str, event_type: str):
    cluster = Cluster()
    session = cluster.connect('analytics')
    session.execute(
        "INSERT INTO events (user_id, event_type, ts) VALUES (%s, %s, toTimestamp(now()))",
        (user_id, event_type)
    )
    # no transaction, no atomicity guarantee across tables
```

---

## How It Connects

The CAP theorem provides the theoretical foundation for why BASE exists: in a distributed system, you cannot have both perfect consistency and perfect availability during network partitions.

[[cap-theorem|CAP Theorem]]

The spectrum between ACID and BASE is not binary. Consistency models describe the range of guarantees available and when each is appropriate.

[[consistency-models|Consistency Models]]

When building a system, the choice between SQL (ACID) and NoSQL (BASE) databases is one of the most consequential architectural decisions.

[[sql-vs-nosql|SQL vs NoSQL]]

---

## Common Misconceptions

Misconception 1: "NoSQL databases don't have transactions, so they're risky for any important data."
Reality: Many modern NoSQL databases offer limited transaction support. MongoDB added multi-document transactions in version 4.0. DynamoDB offers transactional reads and writes within a single region. The question is not "transactions or not" but "what are the exact guarantees and at what cost."

Misconception 2: "ACID and BASE are about SQL vs NoSQL."
Reality: The divide is about consistency philosophy, not query language. CockroachDB and Google Spanner are distributed SQL databases with ACID guarantees. Redis, while often used as a cache, supports atomic operations via Lua scripts and transactions. A distributed system can implement ACID — it is just expensive.

Misconception 3: "Eventual consistency means data can be wrong forever."
Reality: "Eventually" in eventual consistency means that, absent new writes, all replicas will converge to the same value. In practice this usually happens within milliseconds to seconds. The window of inconsistency is bounded, and the final state is correct. What it does not guarantee is that any specific read during that window returns the most recent write.

---

## Why It Matters in Practice

Choosing ACID when you need BASE (or vice versa) causes one of two problems. Choosing ACID for a system that needs high availability at scale means you will face escalating complexity and cost to maintain consistency guarantees across many nodes — often via two-phase commit, which is notoriously slow and fragile. Choosing BASE for a system that requires correctness means you will have bugs that appear only under concurrent load, often in production, where two operations conflict and your resolution strategy produces wrong answers.

The most common real-world mistake is mixing ACID and BASE within the same logical transaction boundary. A developer writes a record to a relational database (ACID) and then publishes an event to Kafka (no transaction). If the Kafka publish fails, the database record exists but no downstream system knows about it. This is the dual-write problem, and it is solved by patterns like the transactional outbox, which keeps both within a single ACID transaction.

---

## Interview Angle

Common question forms:
- "What are ACID properties? Give an example of each."
- "When would you choose a NoSQL database over a relational database?"
- "What is eventual consistency and when is it acceptable?"

Answer frame:
Define each ACID property with a concrete example (money transfer is classic). Explain that ACID guarantees are expensive to distribute. Introduce BASE as the philosophy behind scaling distributed writes. Discuss specific trade-offs: last-write-wins conflict resolution in Cassandra, quorum consistency in DynamoDB. Conclude by mapping to use cases: ACID for anything financial or inventory-critical; BASE for analytics, activity feeds, social graphs.

---

## Related Notes

- [[cap-theorem|CAP Theorem]]
- [[consistency-models|Consistency Models]]
- [[sql-vs-nosql|SQL vs NoSQL]]
- [[database-replication|Database Replication]]
- [[sqlalchemy-core|SQLAlchemy Core]]
