---
title: 07 - Redis Clustering
description: "How Redis Cluster shards data across multiple nodes using hash slots, handles failover, and what this means for multi-key operations."
tags: [redis, clustering, sharding, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Redis Clustering

> Redis Cluster is how you scale Redis beyond a single machine — but it introduces constraints on multi-key operations and requires understanding hash slots to use correctly.

---

## Quick Reference

**Core idea:**
- Redis Cluster divides the keyspace into 16,384 hash slots
- Each primary node is responsible for a range of slots (e.g., 0–5460 for node 1)
- A key's slot is determined by: `CRC16(key) % 16384`
- Each primary has one or more replicas for fault tolerance; failover is automatic
- Multi-key commands (MSET, MGET, SINTER) require all keys to be in the same slot — use hash tags to enforce this

**Tricky points:**
- 16,384 slots is a fixed constant — not configurable; enough for clusters up to ~1,000 nodes
- Hash tags `{tag}key` force all keys with the same tag to the same slot, enabling multi-key operations
- A client talking to the wrong node gets a MOVED redirect — properly configured clients handle this transparently
- Cluster topology changes (resharding, failover) take time — clients should handle MOVED/ASK redirects
- Redis Cluster does not support cross-slot transactions — MULTI/EXEC with keys in different slots will fail

---

## What It Is

Think of a library with an enormous number of books spread across five buildings. Each building holds books whose titles start with a certain range of letters (A–F in building 1, G–M in building 2, and so on). When you need a book, you go to the building responsible for that letter range. If building 3 is closed for maintenance, books in that range become temporarily unavailable — but the other buildings continue normally. When building 3 reopens, you can retrieve your books again. Meanwhile, if a building is overwhelmed with requests, you can split its letter range and assign half to a new sixth building.

Redis Cluster works similarly. The keyspace is divided into 16,384 "hash slots." Each primary node owns a contiguous range of slots. To find which node holds a key, the client computes `CRC16(key) % 16384`. This gives a slot number, and the client knows (from a cached cluster map) which node owns that slot. The request goes directly to the right node.

The fixed number 16,384 was chosen deliberately. It is large enough to distribute across thousands of nodes (each node needs at least a few slots to be useful), small enough that the cluster topology map fits in a heartbeat gossip message (16,384 bits = 2 KB), and simple enough that slot assignment is deterministic. Every Redis node knows the full slot map and can redirect clients to the correct node.

Failover is automatic. Each primary node has one or more replica nodes that receive the same writes asynchronously. If a primary becomes unreachable (detected by a quorum of other nodes in the cluster), one of its replicas is promoted to primary. The cluster marks the new primary as responsible for the same hash slots. This election and promotion typically takes 10–30 seconds. During this window, the affected slot range is unavailable. Writes targeting those slots fail with a CLUSTERDOWN error.

---

## How It Actually Works

Slot assignment is the core mechanism. A key's slot is computed from the key name (or from a hash tag within the key name). Hash tags allow you to override the default slot computation by extracting just the tagged portion for hashing. If a key contains `{...}`, the CRC16 is computed only over the content inside the braces, not the full key name. This means `{user:1001}.profile`, `{user:1001}.settings`, and `{user:1001}.feed` all hash to the same slot — they can be used in multi-key operations together.

When a client sends a command to the wrong node (either because the client's slot map is stale or because the key does not exist in the local cluster cache), the node responds with a MOVED redirect: `MOVED 7638 192.168.1.3:6379`. This tells the client that slot 7638 lives on node 192.168.1.3. A well-behaved cluster client updates its internal slot map and retries the command on the correct node. A naive implementation would return the MOVED error to the application. Modern Redis client libraries (redis-py, Jedis, Lettuce) handle MOVED transparently.

Resharding — moving slots from one node to another — is done online without downtime. The command `redis-cli --cluster reshard` begins migrating keys from one node's slot range to another. During migration, a key might be in the process of moving. If a client requests a key that is being migrated, the source node responds with ASK, directing the client to the destination node for this request only. The client sends an ASKING command followed by the original command to the destination node. Unlike MOVED, ASK does not cause the client to update its slot map permanently.

```python
from redis.cluster import RedisCluster, ClusterNode

# Connect to Redis Cluster — client auto-discovers topology
startup_nodes = [
    ClusterNode("redis-node-1", 6379),
    ClusterNode("redis-node-2", 6379),
]
cluster = RedisCluster(startup_nodes=startup_nodes, decode_responses=True)

# Basic operations — client routes to correct node automatically
cluster.set("user:1001", "alice")
value = cluster.get("user:1001")

# Hash tag: ensure related keys go to the same slot for multi-key ops
cluster.set("{user:1001}.profile", '{"name": "Alice"}')
cluster.set("{user:1001}.settings", '{"theme": "dark"}')
cluster.set("{user:1001}.feed", "post1,post2,post3")

# Multi-key operation works because all keys share the {user:1001} hash tag
# Without hash tags, this would fail with CROSSSLOT error
results = cluster.mget(
    "{user:1001}.profile",
    "{user:1001}.settings",
    "{user:1001}.feed"
)

# Transaction on cluster: only works if all keys are in the same slot
pipe = cluster.pipeline()
pipe.incr("{counter:pageviews}")
pipe.incr("{counter:sessions}")  # same slot as above due to {counter:} tag
results = pipe.execute()
```

Cluster mode fundamentally changes the deployment and operational model. Instead of one primary and optionally a replica, you have typically 3–6 primary nodes each with 1–2 replicas. The minimum cluster size is 3 primaries (to form a quorum for failover elections). A cluster with 3 primaries and 3 replicas (6 nodes total) distributes all 16,384 slots across the 3 primaries, roughly 5,461 slots each.

---

## How It Connects

Consistent hashing and hash slots solve the same problem — key distribution with minimal remapping — using different approaches. Redis Cluster uses a fixed slot count (simpler to reason about) rather than a ring (which requires the virtual nodes trick).

[[consistent-hashing|Consistent Hashing]]

Cluster failover requires a quorum of nodes to agree on promoting a replica. Understanding how distributed consensus works in failure scenarios provides the background for why failover takes 10–30 seconds.

[[cap-theorem|CAP Theorem]]

Redis Cluster persists data at the individual node level — each primary's RDB and AOF configuration is independent.

[[redis-persistence|Redis Persistence]]

---

## Common Misconceptions

Misconception 1: "Redis Cluster handles all my multi-key operations automatically."
Reality: Redis Cluster only executes multi-key operations (MGET, MSET, KEYS, SCAN, SINTER, SUNION) when all keys are in the same hash slot. If keys are in different slots, the command returns a CROSSSLOT error. Hash tags are the solution — use them for keys that participate in multi-key operations.

Misconception 2: "Cluster mode makes Redis immediately scale horizontally."
Reality: A Redis Cluster distributes storage across nodes (each node holds a fraction of total data). It does not automatically increase throughput proportionally — each write still goes to one primary plus its replicas. For read scaling, configure replicas and enable read-from-replica. For write scaling, more primary nodes help only if keys are distributed evenly — hot key problems still create single-shard bottlenecks.

Misconception 3: "Failover in Redis Cluster is instant."
Reality: Failover requires the cluster to detect a node failure (heartbeat timeout, typically 5–15 seconds), other nodes to vote on which replica should be promoted (a few seconds), and the new primary to announce itself (gossip propagation). End-to-end, this takes 10–30 seconds in typical configurations. During this window, the affected slots are unavailable.

---

## Why It Matters in Practice

Redis Cluster changes how you must design your data model. Keys that need to be used together in multi-key operations must share a hash tag. Keys that should be evenly distributed must not all share the same hash tag (or they will all land on one slot and one node). This is a design constraint that must be understood before writing application code, not discovered after deployment.

The MOVED redirect handling — transparent in modern clients, catastrophic in naive ones — is a production gotcha. If your application uses a raw Redis client that does not handle MOVED, it will return errors to users whenever a node is added, removed, or resharded. Always use a cluster-aware Redis client library in production.

---

## Interview Angle

Common question forms:
- "How does Redis Cluster distribute data?"
- "What are hash slots and hash tags in Redis Cluster?"
- "What happens during a Redis Cluster failover?"

Answer frame:
Explain 16,384 hash slots, CRC16 computation for slot assignment, and how nodes own slot ranges. Explain MOVED redirects: the client might contact the wrong node; the response tells it the right node. Explain hash tags: the `{tag}` syntax ensures keys with the same tag land on the same slot. Walk through failover: heartbeat timeout, quorum vote, replica promotion, 10–30 second window. Explain the constraint: cross-slot operations are forbidden without hash tags.

---

## Related Notes

- [[redis-architecture|Redis Architecture]]
- [[redis-persistence|Redis Persistence]]
- [[redis-data-structures|Redis Data Structures]]
- [[consistent-hashing|Consistent Hashing]]
- [[database-sharding|Database Sharding]]
