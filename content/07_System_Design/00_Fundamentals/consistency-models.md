---
title: 05 - Consistency Models
description: "The spectrum of consistency guarantees in distributed systems — from linearizability to eventual consistency — and when each model is appropriate."
tags: [consistency, linearizability, eventual-consistency, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Consistency Models

> Consistency is not a binary property — it is a spectrum, and knowing precisely where on that spectrum your system sits determines what bugs are possible and what guarantees you can make to users.

---

## Quick Reference

**Core idea:**
- Strong consistency (linearizability): every read returns the most recent write, globally
- Sequential consistency: operations appear in some global order, but not necessarily real-time
- Causal consistency: operations that are causally related appear in the correct order to all nodes
- Read-your-writes: you always see your own writes, but others might not
- Eventual consistency: all replicas converge to the same value if no new writes occur

**Tricky points:**
- "Consistent" means different things in ACID, CAP, and the consistency model hierarchy — always clarify
- Read-your-writes is much weaker than strong consistency but solves most user-visible inconsistency
- Causal consistency is often the sweet spot — stronger than eventual, cheaper than linearizable
- Eventual consistency says nothing about how long "eventually" takes
- Most databases let you tune consistency level per operation, not just per cluster

---

## What It Is

Imagine a group of five friends who all keep diaries. One friend writes down "Alice got promoted" in her diary. The question of consistency is: when can each other friend read that entry in their own copy? Under strong consistency, the moment Alice writes it, all friends instantly see it in their copies — as if there is only one diary shared among all of them. Under eventual consistency, each friend's diary will eventually contain the entry, but some might not see it for minutes, hours, or days. Between those two extremes, there are more nuanced models that preserve specific relationships between events without guaranteeing global freshness.

Strong consistency, also called linearizability, is the strongest model. It guarantees that once a write completes, any subsequent read — from any node — returns that value. The system behaves as if there is one copy of the data, even if it is physically replicated across ten data centers. This is what you get from a single-node relational database and from distributed databases that pay the cost of consensus (like Spanner or etcd). The cost is latency: every read must coordinate across replicas or go to a single authoritative node.

Sequential consistency is slightly weaker: all operations appear to have happened in some total order, and each client's operations appear in program order. However, that total order does not need to match real time. Client A might write "X=1" and client B might read "X=0" moments later — as long as all clients see the same ordering of operations. This model appears in certain memory consistency models for CPUs and some distributed systems.

Causal consistency tracks which operations causally depend on others. If you post a comment in response to a post, readers must see the original post before they see the reply — because the reply causally depends on the post. But two causally unrelated writes can appear in different orders to different clients. Causal consistency is valuable for social networks and collaborative editing, where logical ordering matters but global synchronization does not. MongoDB's causally consistent sessions implement this.

Read-your-writes is one of the most practically important weak guarantees: a client always sees the effect of its own previous writes. This eliminates the most jarring user experience — submitting a form and then seeing the page refresh without your data. It does not guarantee other clients see your write quickly. This can be implemented by routing a user's reads to the same replica they wrote to, or by passing a write timestamp that the read endpoint must respect.

Eventual consistency is the weakest useful model: if no new writes occur, all replicas will eventually converge to the same value. It says nothing about how long this takes, nothing about the order in which other clients see updates, and nothing about what you see between the write and the convergence. This is the model of most caches, DNS propagation, and basic replicated datastores.

---

## How It Actually Works

The consistency model is determined by how a system coordinates between replicas. Linearizability requires that every read touches a quorum of replicas (or a single primary) to ensure it sees the latest write. In Raft and Paxos-based systems, a write is not acknowledged until a majority of replicas have recorded it, and reads go through the same leader that processed the write. This adds at least one network round-trip to every operation.

Causal consistency is typically implemented using vector clocks or version vectors. Each write carries a vector clock that encodes which prior writes it depends on. When a replica receives a read or write, it checks whether all causally prior writes have already been applied. If not, it waits. This requires metadata to be carried with each operation but avoids the full coordination cost of linearizability.

Eventual consistency requires no coordination at all — writes can be accepted by any replica and propagated asynchronously. The complexity is pushed to conflict resolution: when two replicas have different values for the same key, which one wins? Last-write-wins (using timestamps) is simple but can silently lose updates if two writes happen within the clock's resolution. Conflict-free replicated data types (CRDTs) are data structures designed so that any two replicas can always be merged without conflicts, making eventual consistency usable for more complex state.

```python
# Simulating read-your-writes in Redis with a write token
import redis
import uuid

r = redis.Redis()

def write_user_profile(user_id: str, data: dict) -> str:
    """Write profile and return a write token for read-your-writes."""
    write_token = str(uuid.uuid4())
    pipe = r.pipeline()
    pipe.hset(f"user:{user_id}", mapping=data)
    pipe.set(f"write_token:{user_id}", write_token, ex=30)  # 30s expiry
    pipe.execute()
    return write_token

def read_user_profile(user_id: str, write_token: str = None) -> dict:
    """Read profile, verifying we can see the specific write if token given."""
    if write_token:
        current_token = r.get(f"write_token:{user_id}")
        if current_token and current_token.decode() != write_token:
            # Route to primary replica or retry
            pass
    return r.hgetall(f"user:{user_id}")
```

---

## How It Connects

The CAP theorem is what makes consistency tradeoffs unavoidable in distributed systems. Consistency models describe the available options within that constraint.

[[cap-theorem|CAP Theorem]]

ACID and BASE represent two ends of the consistency spectrum. Understanding the full model hierarchy places them in context.

[[acid-vs-base|ACID vs BASE]]

In caching systems, the consistency model determines how stale cached data can be. Cache invalidation is essentially a consistency problem.

[[cache-invalidation|Cache Invalidation]]

---

## Common Misconceptions

Misconception 1: "My system is either consistent or eventually consistent — there's nothing in between."
Reality: There are at least five widely-recognized consistency models between linearizability and pure eventual consistency. Many databases let you choose per-operation. Causal consistency and read-your-writes are commonly available middle grounds that solve most practical user-facing issues without the full cost of linearizability.

Misconception 2: "Eventual consistency means my data could be wrong."
Reality: Eventual consistency means all replicas will converge to the correct value. It does not mean the value is wrong — it means different readers may see different versions of the truth during the convergence window. The final state is accurate; the transient state is uncertain.

Misconception 3: "Strong consistency is always better if I can afford it."
Reality: Strong consistency adds latency to every operation, reduces availability during partitions, and makes cross-region deployments much more expensive. For many read-heavy workloads, causal consistency or read-your-writes provides excellent user experience at a fraction of the cost.

---

## Why It Matters in Practice

The consistency model choice determines what classes of bugs are possible. With eventual consistency, a user can add an item to their cart, immediately refresh, and not see the item — this is a read-your-writes violation. With causal consistency without global ordering, User A's reply to User B's post might appear before the post itself to a third user. Understanding which anomalies your chosen model allows helps you write defensive code — for example, idempotent handlers that can safely process the same event twice, or UI patterns that show pending state while a write propagates.

The most expensive mistakes happen when engineers assume a stronger consistency model than the system actually provides. A developer who assumes all reads to a Cassandra cluster reflect the most recent write will build incorrect logic. The first time two concurrent writes create a conflict that resolves in the wrong direction, data is silently lost. Explicit documentation of the assumed consistency model — and testing that assumption against the actual database's behavior — is essential.

---

## Interview Angle

Common question forms:
- "What is the difference between strong consistency and eventual consistency?"
- "How would you explain read-your-writes consistency to a non-technical stakeholder?"
- "When would you accept eventual consistency in a system design?"

Answer frame:
Walk through the spectrum from linearizability to eventual consistency with one concrete example for each model. Explain what anomalies each model permits. Then map to use cases: financial systems need linearizability; social feeds can accept eventual consistency; user dashboards benefit from read-your-writes. Finish by noting that most systems let you configure consistency per operation, so the design decision is granular, not system-wide.

---

## Related Notes

- [[cap-theorem|CAP Theorem]]
- [[acid-vs-base|ACID vs BASE]]
- [[database-replication|Database Replication]]
- [[cache-invalidation|Cache Invalidation]]
- [[caching-strategies|Caching Strategies]]
