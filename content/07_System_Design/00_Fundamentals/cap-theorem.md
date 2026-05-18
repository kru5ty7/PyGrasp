---
title: 03 - CAP Theorem
description: "A distributed system can only guarantee two of three properties  -  Consistency, Availability, and Partition Tolerance  -  and understanding this shapes every database and service design decision."
tags: [cap-theorem, consistency, availability, partition-tolerance, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# CAP Theorem

> The CAP theorem is not an abstract mathematical curiosity  -  it is the reason your distributed database sometimes returns stale data, and understanding it is what separates architecturally sound design from wishful thinking.

---

## Quick Reference

**Core idea:**
- CAP stands for Consistency, Availability, and Partition Tolerance
- In the presence of a network partition, you can have either Consistency or Availability, not both
- Partition tolerance is not optional in any real distributed system  -  networks do fail
- CP systems choose consistency over availability during partitions (e.g., HBase, Zookeeper, etcd)
- AP systems choose availability over consistency during partitions (e.g., Cassandra, DynamoDB, CouchDB)

**Tricky points:**
- "Consistency" in CAP means linearizability, not the C in ACID (which is about constraint enforcement)
- You do not "choose 2 of 3" in normal operation  -  all three hold when there is no partition
- The real choice is: what should the system do when a network partition occurs?
- CA systems (no partition tolerance) do not exist in practice  -  you cannot guarantee no network failures
- CAP is a simplification; PACELC extends it by also modeling latency tradeoffs under normal operation

---

## What It Is

Imagine you have two librarians working in two separate buildings, and they share a catalog of books. When a patron requests a book at one building, the librarian writes it down in the catalog. The two librarians are connected by a telephone to keep their catalogs synchronized. Now imagine the telephone line breaks. You have a choice to make. You can refuse to help any patron until the line is fixed  -  that way no one gets incorrect information about what is available (choosing consistency over availability). Or you can keep helping patrons as best you can, knowing that the two catalogs may be out of sync for a while (choosing availability over consistency). You cannot do both while the line is down.

This is the CAP theorem in miniature. In 2000, Eric Brewer proposed that a distributed data system cannot simultaneously guarantee all three of: Consistency (every read receives the most recent write or an error), Availability (every request receives a response, though it might not be the most recent write), and Partition Tolerance (the system continues operating despite network failures that split it into groups that cannot communicate). In 2002, Gilbert and Lynch proved this formally. The theorem has shaped distributed systems design ever since.

The critical word is "partition." A network partition is a failure where some nodes can communicate with each other but not with other nodes. In a real multi-server deployment, partitions happen: cables fail, switches malfunction, cloud availability zones become temporarily unreachable, packets are dropped. Since you cannot build a practical distributed system that is immune to all network failures, partition tolerance is effectively mandatory. Given that P is not optional, the real choice is: when a partition occurs, do you sacrifice C or A?

Consistency in the CAP sense means linearizability: if you write a value, any subsequent read  -  from any node in the system  -  must return that value. This is a strong guarantee. It means when a partition prevents two nodes from synchronizing, rather than let them return potentially stale data, the system must refuse to serve reads from the isolated node (or refuse writes that might conflict). Availability means every request gets a non-error response. These two goals conflict directly when nodes are cut off from each other.

---

## How It Actually Works

A CP system, when it detects a partition, chooses to become unavailable rather than return inconsistent data. ZooKeeper, for example, requires a quorum of nodes to agree before serving any read or write. If the cluster is split and one half cannot reach a quorum, that half stops serving requests entirely. This is the right choice for systems that store configuration, distributed locks, or leader election state  -  being wrong is worse than being unavailable. HBase and many relational databases with synchronous replication behave similarly.

An AP system, when it detects a partition, continues serving requests from all nodes even though those nodes may have diverged. Cassandra writes to any available replica and uses conflict resolution strategies (last-write-wins by default, or application-defined merge functions) to reconcile diverged state when the partition heals. DynamoDB similarly allows reads and writes on all partitions, with eventual consistency as the default. These systems are designed for situations where some staleness is acceptable  -  a shopping cart item might be lost during a failure window, which is better than the checkout page being completely unavailable.

The PACELC model (proposed by Daniel Abadi) extends CAP by observing that even without a partition, there is a tradeoff between latency and consistency. Getting consistent reads requires waiting for agreement across replicas, which takes time. Getting fast reads means potentially reading from a replica that has not yet received the latest write. This latency-consistency tradeoff applies in normal operation, not just during failures. Systems like Cassandra let you configure the consistency level per operation: a read with `QUORUM` consistency is slower but more consistent than a read with `ONE` consistency.

```python
# Example: Cassandra consistency level choice
from cassandra.cluster import Cluster
from cassandra import ConsistencyLevel
from cassandra.query import SimpleStatement

cluster = Cluster(['node1', 'node2', 'node3'])
session = cluster.connect('mykeyspace')

# Strong read: wait for majority of replicas to agree (CP-like behavior)
strong_read = SimpleStatement(
    "SELECT * FROM users WHERE id = %s",
    consistency_level=ConsistencyLevel.QUORUM
)

# Fast read: any single replica responds (AP behavior, may be stale)
fast_read = SimpleStatement(
    "SELECT * FROM users WHERE id = %s",
    consistency_level=ConsistencyLevel.ONE
)
```

---

## How It Connects

The CAP theorem describes what happens during network partitions, but in normal operation, relational databases provide stronger guarantees through ACID properties. Understanding the distinction between ACID consistency and CAP consistency is essential.

[[acid-vs-base|ACID vs BASE]]

CAP's consistency property is one extreme of a spectrum. Between linearizability and no consistency at all, there are intermediate models that are more practical for many use cases.

[[consistency-models|Consistency Models]]

The choice between CP and AP systems shapes which database you select for a given problem. SQL databases typically favor CP; most NoSQL databases favor AP.

[[sql-vs-nosql|SQL vs NoSQL]]

---

## Common Misconceptions

Misconception 1: "I can choose any two of the three CAP properties for my system."
Reality: You cannot build a distributed system without partition tolerance  -  network failures happen in production. The real choice is whether to sacrifice consistency or availability when a partition occurs. The "CA" option only exists in single-node or non-distributed systems.

Misconception 2: "The C in CAP is the same as the C in ACID."
Reality: They are completely different. CAP consistency means linearizability  -  the most recent write is always returned. ACID consistency means the database moves from one valid state to another, enforcing schema constraints and business rules. A database can be ACID-consistent but CAP-inconsistent (eventual consistency with ACID transactions locally, but stale reads across replicas).

Misconception 3: "AP systems are just broken CP systems."
Reality: AP systems are intentionally designed to prioritize uptime over perfect consistency. For many workloads  -  user activity feeds, product catalogs, recommendation systems  -  serving slightly stale data is far better than returning errors. The design is deliberate and appropriate for its use cases.

---

## Why It Matters in Practice

Choosing the wrong consistency model causes bugs that are hard to reproduce and hard to fix. A shopping cart backed by an AP store might lose items added during a partition window. A financial ledger backed by an AP store might double-count a transaction. Recognizing that your use case requires strong consistency (and choosing a CP store accordingly) prevents these classes of bugs.

Conversely, requiring strong consistency where it is not needed makes your system slower and less available than necessary. A product search feature does not need to reflect inventory changes within milliseconds. Using a strongly consistent database for that feature adds latency and potential unavailability for no business benefit. CAP literacy lets you make the right tradeoff consciously.

---

## Interview Angle

Common question forms:
- "Explain the CAP theorem and give an example of each type of system."
- "For this feature, would you use a CP or AP system? Why?"
- "What happens to your system during a network partition?"

Answer frame:
Define all three terms precisely, especially distinguishing CAP consistency from ACID consistency. Explain that P is mandatory in practice. Give concrete examples: ZooKeeper/etcd as CP (distributed locks, config); Cassandra/DynamoDB as AP (activity feeds, shopping carts). Then connect the choice to business requirements: how bad is inconsistency? How bad is unavailability? Use that answer to drive the CP vs AP decision.

---

## Related Notes

- [[acid-vs-base|ACID vs BASE]]
- [[consistency-models|Consistency Models]]
- [[database-replication|Database Replication]]
- [[scalability-basics|Scalability Basics]]
