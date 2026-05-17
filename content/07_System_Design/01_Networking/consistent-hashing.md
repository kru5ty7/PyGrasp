---
title: 07 - Consistent Hashing
description: "A hashing technique that minimizes the number of keys remapped when nodes are added or removed from a distributed system — the foundation of distributed caches and load balancers."
tags: [consistent-hashing, distributed-systems, caching, networking, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Consistent Hashing

> Consistent hashing solves a fundamental problem in distributed systems: how to distribute keys across nodes such that adding or removing a node disrupts as little of the existing distribution as possible.

---

## Quick Reference

**Core idea:**
- Both nodes and keys are mapped to positions on a hash ring (a circle with 2^32 positions)
- A key is served by the first node clockwise from its position on the ring
- When a node is added, only keys between the new node and the previous node on the ring are remapped
- When a node is removed, only its keys move to the next node clockwise — all others are unchanged
- Virtual nodes (vnodes): each physical node is placed at multiple ring positions to improve distribution

**Tricky points:**
- Without virtual nodes, an uneven distribution of nodes on the ring means some nodes handle much more load than others
- The number of virtual nodes per server controls the smoothness of distribution (typically 100–300)
- Consistent hashing does not help if keys are not uniformly distributed — a hot key still causes a hotspot
- For load balancing, the "key" is typically the client IP or session ID, not a cache key
- Adding virtual nodes without increasing physical capacity just changes load distribution, not total capacity

---

## What It Is

Imagine you manage a ring of post boxes numbered 1 to 360 (like degrees in a circle). You have four mail carriers, each responsible for delivering mail from their post box onwards until the next carrier's post box. If post boxes 1–90 belong to Carrier A, 91–180 to Carrier B, 181–270 to Carrier C, and 271–360 to Carrier D — and each piece of mail is assigned a number from 1 to 360 based on the address — then each carrier handles roughly a quarter of the mail. Now if Carrier B quits, their mail (boxes 91–180) goes to Carrier C. The other carriers are unaffected. If you hire a new Carrier E and assign them boxes 61–90, only mail that was going to Carrier A in that range needs to be rerouted. Every other carrier is unaffected. This is consistent hashing.

The problem it solves starts with naive hashing: `server_index = hash(key) % num_servers`. This works perfectly when the number of servers is fixed. But when a server is added or removed, `num_servers` changes, and nearly every key remaps to a different server. For a distributed cache with a million keys, adding a server invalidates almost all of them, causing a thundering herd of cache misses as every request goes to the origin simultaneously. For a session routing system, it routes every user to a different server, breaking their sessions. This is catastrophic in production.

Consistent hashing maps both servers and keys to positions on an abstract ring. The ring has positions from 0 to 2^32 - 1 (using a 32-bit hash). A server's position is determined by hashing its identifier (typically its IP address or hostname). A key's position is determined by hashing the key. The rule for assignment is simple and elegant: a key is served by the first server encountered when traveling clockwise from the key's position on the ring.

When a new server is added, it occupies a position on the ring. The only keys that change assignment are those between the new server and the previous server (counterclockwise). All other keys are unaffected — they still point to the same server as before. When a server is removed, its keys move to the next server clockwise. Only those keys are remapped. For a cluster of N servers, adding or removing one server remaps approximately 1/N of the total keys, compared to nearly all keys with naive modulo hashing.

---

## How It Actually Works

The pure consistent hash ring has an uneven distribution problem. If servers happen to land at positions 10%, 11%, 12%, and 90% of the ring, the server at 12% handles 78% of the key space (from 12% to 90%), while the other three split the remaining 22%. This imbalance is addressed through virtual nodes: each physical server is placed at multiple positions on the ring, typically 100–300 positions per server. The name of each virtual node (e.g., `server1:vnode:0`, `server1:vnode:1`, ...) is hashed to place it on the ring.

With 150 virtual nodes per server and a cluster of 10 servers, you have 1,500 points on the ring, and the key space is divided roughly evenly among servers. Adding a new server means its 150 virtual nodes are inserted at 150 different positions, each "stealing" a small slice of keys from the adjacent server. The total redistribution is still approximately 1/N of all keys, but it comes from all existing servers proportionally rather than just the one neighbor.

```python
import hashlib
from bisect import bisect_left, insort
from collections import defaultdict

class ConsistentHashRing:
    def __init__(self, vnodes: int = 150):
        self.vnodes = vnodes
        self.ring: list[int] = []            # sorted list of hash positions
        self.position_to_node: dict[int, str] = {}

    def add_node(self, node: str) -> None:
        for i in range(self.vnodes):
            pos = self._hash(f"{node}#{i}")
            insort(self.ring, pos)
            self.position_to_node[pos] = node

    def remove_node(self, node: str) -> None:
        for i in range(self.vnodes):
            pos = self._hash(f"{node}#{i}")
            self.ring.remove(pos)
            del self.position_to_node[pos]

    def get_node(self, key: str) -> str:
        if not self.ring:
            raise ValueError("Ring is empty")
        pos = self._hash(key)
        # Find the first ring position >= hash(key); wrap around if needed
        idx = bisect_left(self.ring, pos) % len(self.ring)
        return self.position_to_node[self.ring[idx]]

    def _hash(self, s: str) -> int:
        return int(hashlib.sha256(s.encode()).hexdigest(), 16)

# Demonstrate minimal remapping on node addition
ring = ConsistentHashRing(vnodes=150)
ring.add_node("cache-1")
ring.add_node("cache-2")
ring.add_node("cache-3")

keys = [f"user:{i}" for i in range(10000)]
before = {k: ring.get_node(k) for k in keys}

ring.add_node("cache-4")  # add a new node
after = {k: ring.get_node(k) for k in keys}

remapped = sum(1 for k in keys if before[k] != after[k])
print(f"Remapped: {remapped}/10000 ({remapped/100:.1f}%)")
# Expect ~25% (1/4 of keys) to remap — not ~75% as with modulo hashing
```

Real-world systems that use consistent hashing include Amazon DynamoDB, Apache Cassandra, Redis Cluster (though it uses a slightly different "hash slot" mechanism), Memcached client libraries, and Nginx's `ip_hash` upstream directive in its advanced forms. Cassandra's virtual node mechanism is configurable per node — allowing more powerful nodes to take more virtual node positions and thus a larger share of the data.

---

## How It Connects

Consistent hashing is applied in Redis Cluster, which divides the key space into 16,384 hash slots and assigns ranges of slots to nodes. While not a ring, the concept of minimizing remapping when cluster topology changes is the same.

[[redis-clustering|Redis Clustering]]

Load balancing algorithms use consistent hashing for client-to-server routing, ensuring the same client always reaches the same backend server without explicit session state in the load balancer.

[[load-balancing-algorithms|Load Balancing Algorithms]]

Database sharding faces the same remapping problem: when a new shard is added, how many records need to move? Consistent hashing principles inform shard placement strategies.

[[database-sharding|Database Sharding]]

---

## Common Misconceptions

Misconception 1: "Consistent hashing guarantees even load distribution."
Reality: Consistent hashing guarantees that when nodes are added or removed, the minimum number of keys are remapped. It does not guarantee even distribution of those keys. Without virtual nodes, distribution can be very uneven. With virtual nodes and a good hash function, distribution approaches evenness, but specific key distributions (e.g., all keys being numeric IDs with similar values) can still create imbalances.

Misconception 2: "Consistent hashing eliminates the need for cache invalidation when scaling."
Reality: When a new node is added, the keys that map to it were previously handled by a neighboring node — where they were cached. The new node does not have those keys cached yet. Those requests must go to the origin for the first time, causing cache misses. Consistent hashing minimizes how many keys this happens for (1/N instead of all of them), but it does not eliminate cache misses entirely during scaling.

Misconception 3: "Virtual nodes are just a workaround for a flawed algorithm."
Reality: Virtual nodes are an intentional and essential part of consistent hashing as deployed in practice. They solve the uneven distribution problem and also make it easier to weight nodes differently: a server with twice the capacity can be given twice as many virtual nodes, receiving approximately twice the load.

---

## Why It Matters in Practice

Any distributed system that maps keys to nodes — caches, sharded databases, session routers — faces the reshuffling problem that consistent hashing solves. Without it, every cluster resize operation (adding capacity for growth, removing a failed node) causes a mass cache miss event or a mass session rerouting event. With consistent hashing, these events are proportional to the fraction of nodes changed, not the total.

For Python engineers building distributed systems, the practical application is most often in cache client configuration. When connecting to a Memcached cluster with multiple nodes, the client library must use consistent hashing to determine which node holds each key. If the client uses simple modulo hashing and a node is added, the cache miss rate spikes briefly. Understanding this is important for capacity planning: adding cache nodes should be done gradually and during low-traffic periods.

---

## Interview Angle

Common question forms:
- "What problem does consistent hashing solve?"
- "How would you design the key distribution in a distributed cache with N nodes?"
- "What are virtual nodes and why are they needed?"

Answer frame:
Start with the naive modulo hashing problem: adding one node remaps ~N/(N+1) keys, causing a cache miss spike. Introduce the hash ring: servers and keys on the same ring, clockwise assignment rule. Show that adding a node remaps only ~1/N keys. Introduce virtual nodes as the solution to uneven distribution. Explain the tradeoff: more vnodes means smoother distribution but more memory for the ring data structure and more iterations during add/remove.

---

## Related Notes

- [[load-balancing-algorithms|Load Balancing Algorithms]]
- [[redis-clustering|Redis Clustering]]
- [[database-sharding|Database Sharding]]
- [[caching-basics|Caching Basics]]
