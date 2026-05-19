---
title: 03 - Load Balancing Algorithms
description: "The algorithms a load balancer uses to select the next server  -  round robin, least connections, IP hash, and weighted variants  -  and when each is the right choice."
tags: [load-balancing, algorithms, networking, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Load Balancing Algorithms

> The choice of load balancing algorithm is the difference between a perfectly distributed fleet and a situation where one server handles 80% of traffic while three sit mostly idle.

---

## Quick Reference

**Core idea:**
- Round robin: distribute requests in a fixed cycle (1, 2, 3, 1, 2, 3...)
- Weighted round robin: same cycle but servers get requests proportional to their weight
- Least connections: send to the server with the fewest active connections right now
- IP hash: hash the client IP to always send a client to the same server
- Random: pick a server at random  -  surprisingly effective for large, homogeneous pools

**Tricky points:**
- Round robin is only fair when all requests have the same cost  -  they rarely do
- Least connections requires the LB to track state across all connections  -  adds overhead
- IP hash for sticky routing breaks if the server pool size changes (all hash assignments shift)
- Consistent hashing solves the IP hash problem by minimizing reshuffling when nodes join or leave
- Weighted algorithms require knowing server capacity in advance  -  hard to keep accurate

---

## What It Is

Imagine you manage a call center with ten agents. Some agents are fast, some slow. Some callers have simple questions, some need 30 minutes. How do you route incoming calls so no agent is overwhelmed and no agent sits idle? If you assign calls in strict rotation (round robin), fast agents finish quickly and wait while slow agents are still on long calls. If you assign calls to whoever just finished (least connections / "idle first"), the fastest agents do the most work, which is fair in terms of throughput but may not match caller needs. If you remember which agent helped a caller before and always route them back to the same person, that is IP hash or sticky sessions  -  consistent, but not load-balanced.

Load balancing algorithms are the decision functions that answer "which server should handle this request?" The choice depends on the nature of your workload. Are requests homogeneous (similar cost)? Are servers homogeneous (similar capacity)? Does it matter if a client always reaches the same server? Does the LB have visibility into current server load? These questions determine which algorithm is optimal.

Round robin is the simplest: requests are distributed to servers in sequence. Request 1 goes to Server A, Request 2 to Server B, Request 3 to Server C, Request 4 back to Server A. This is perfectly fair if every request takes the same time and every server has the same capacity. In practice, requests vary enormously  -  a database query might take 1ms and a file upload might take 5 seconds. Round robin does not account for this. A server that happens to receive several expensive requests in a row becomes overloaded while other servers sit underutilized.

Weighted round robin extends round robin by assigning each server a weight. A server with weight 3 receives three requests for every one request that goes to a weight-1 server. This is appropriate when servers have different capacities: a newer, larger instance can be given more weight. But weights are configured manually, which means you need to know the relative capacity of each server in advance and update weights when server configurations change.

Least connections dynamically routes each new request to the server with the fewest active connections at that moment. This naturally handles heterogeneous request costs: a server that has accumulated many long-running requests will receive fewer new ones. The load balancer must track the current connection count for every server, which adds state and overhead. Least connections is generally the best choice for workloads with highly variable request duration, such as API servers handling both lightweight reads and expensive writes.

IP hash (or IP-based sticky sessions) computes a hash of the client's IP address and uses it to select a server. The same client IP always hashes to the same server. This provides a primitive form of session affinity without cookies. Its weakness is that if the server pool size changes (a server is added or removed), the hash distribution shifts and most clients are remapped to different servers. This is the same problem that consistent hashing was designed to solve.

---

## How It Actually Works

Round robin is stateless from the load balancer's perspective  -  it maintains only a counter that cycles. This makes it trivially scalable and adds essentially no latency. In Nginx, `upstream { server ...; server ...; }` with no additional directives defaults to round robin.

Least connections requires the LB to atomically increment and decrement a connection counter for each server. In a multi-threaded LB, this requires a lock or atomic operations. At very high connection rates, this contention can add measurable latency. A practical optimization is "power of two choices": the LB randomly selects two servers and picks the one with fewer connections. This approximates least connections with O(1) work and no global state lock, and has been shown empirically to be nearly as effective as perfect least-connections scheduling.

Consistent hashing solves the reshuffling problem inherent in IP hash. Instead of mapping clients directly to servers, both clients and servers are placed on a hash ring. A client is served by the first server clockwise from its position on the ring. When a server is added or removed, only the clients between the removed server and the previous server on the ring are remapped. For a pool of N servers, adding or removing one server remaps approximately 1/N of clients, not all of them. Virtual nodes (placing each physical server at multiple points on the ring) smooth out uneven distribution.

```python
import hashlib
from sortedcontainers import SortedList

class ConsistentHashRing:
    """Minimal consistent hash ring for load balancing."""

    def __init__(self, virtual_nodes: int = 150):
        self.virtual_nodes = virtual_nodes
        self.ring: SortedList = SortedList()
        self.nodes: dict[int, str] = {}

    def add_server(self, server: str):
        for i in range(self.virtual_nodes):
            key = self._hash(f"{server}:vnode:{i}")
            self.ring.add(key)
            self.nodes[key] = server

    def remove_server(self, server: str):
        for i in range(self.virtual_nodes):
            key = self._hash(f"{server}:vnode:{i}")
            self.ring.remove(key)
            del self.nodes[key]

    def get_server(self, client_key: str) -> str:
        if not self.ring:
            raise RuntimeError("No servers in ring")
        h = self._hash(client_key)
        idx = self.ring.bisect_left(h) % len(self.ring)
        return self.nodes[self.ring[idx]]

    def _hash(self, key: str) -> int:
        return int(hashlib.md5(key.encode()).hexdigest(), 16)
```

Random selection  -  picking a server completely at random on each request  -  is underrated. For large, homogeneous pools with short-lived requests, random performs nearly as well as least-connections without any state tracking overhead. Netflix's Eureka service discovery originally used random selection for client-side load balancing.

---

## Visualizer

<iframe src="/static/visualizers/load-balancing-algorithms.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="Load Balancing Algorithms Visualizer"></iframe>

---

## How It Connects

Consistent hashing is so important for distributed systems that it warrants its own deep exploration beyond just its role in load balancing algorithms.

[[consistent-hashing|Consistent Hashing]]

The algorithm choice is configured in the load balancer's upstream block. Nginx exposes round robin (default), ip_hash, and least_conn as directives.

[[nginx-config|Nginx Configuration]]

In distributed caching, the same hashing problem appears: which cache node holds a given key? Cache systems use the same consistent hashing logic to minimize cache misses when nodes are added or removed.

[[redis-clustering|Redis Clustering]]

---

## Common Misconceptions

Misconception 1: "Round robin is good enough for most applications."
Reality: Round robin is fine when requests are homogeneous and servers are identical. In practice, most applications have a mix of cheap reads and expensive writes. Under round robin, a server that receives a batch of expensive requests becomes significantly more loaded than others, causing inconsistent P99 latency. Least connections or a power-of-two-choices approach handles this better.

Misconception 2: "IP hash provides real session persistence."
Reality: IP hash provides weak persistence. If the user is behind a NAT or a proxy (which is extremely common  -  cellular networks, corporate networks, cloud egress), many users share the same source IP. This concentrates load on a single server rather than distributing it. IP hash is almost never the right choice for session affinity; use a cookie-based sticky session instead, or better yet, make the application stateless.

Misconception 3: "Adding a server to a round-robin pool immediately spreads load."
Reality: Round robin distributes new requests evenly, but existing long-running connections are not redistributed. If your application uses persistent HTTP connections (keep-alive), many existing connections may remain on old servers for a long time after a new server is added. This effect is less pronounced with shorter-lived requests.

---

## Why It Matters in Practice

The wrong algorithm causes hot spots  -  individual servers that receive far more load than others  -  which leads to uneven latency, premature autoscaling triggers, and single-server failures that should not occur. A well-chosen algorithm, combined with proper health checks, makes the fleet behave as a uniform resource pool.

For Python applications using async servers (Uvicorn/FastAPI), the request cost varies significantly depending on what the request does. A simple health check completes in under a millisecond. A request that calls three external services and queries the database takes hundreds of milliseconds. Least connections is more appropriate than round robin in this context, because it naturally routes new connections to the servers that finished their previous requests fastest.

---

## Interview Angle

Common question forms:
- "What are the different load balancing algorithms? When would you use each?"
- "How does consistent hashing improve on standard hash-based routing?"
- "What is the power of two choices, and why is it effective?"

Answer frame:
Walk through round robin (simple, homogeneous loads), weighted round robin (different capacity servers), least connections (heterogeneous request costs), and IP hash (primitive stickiness). Explain consistent hashing as a solution to the instability of IP hash when pool size changes. Mention power-of-two-choices as a practical approximation of least-connections. Tie algorithm choice to workload characteristics: request cost variance and server homogeneity.

---

## Related Notes

- [[load-balancing|Load Balancing]]
- [[consistent-hashing|Consistent Hashing]]
- [[nginx-config|Nginx Configuration]]
- [[caching-basics|Caching Basics]]
