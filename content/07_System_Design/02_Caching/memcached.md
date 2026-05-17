---
title: 08 - Memcached
description: "Memcached is a pure, multi-threaded distributed cache with no persistence and minimal features — and its simplicity is exactly what makes it the right choice in specific scenarios."
tags: [memcached, caching, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Memcached

> Memcached does one thing exceptionally well: store and retrieve arbitrary blobs by key, at very high throughput, across multiple threads — and understanding when that simplicity beats Redis's richness is the point.

---

## Quick Reference

**Core idea:**
- Memcached is a pure cache — no persistence, no replication, no native data structures beyond key-value
- Multi-threaded: uses all available CPU cores, unlike Redis's single-threaded command execution
- Protocol is simple: GET, SET, DELETE, INCR — nothing else
- Memory allocation uses a slab allocator, which eliminates fragmentation but can waste memory
- No built-in clustering — clients handle sharding (typically using consistent hashing)

**Tricky points:**
- Memcached will silently evict data under memory pressure with LRU — eviction is expected behavior
- There is no way to list keys, persist data, or run server-side logic — strictly cache operations
- Client-side sharding means clients must know the cluster topology — adding nodes does not auto-rebalance
- Memcached's multi-threaded model means operations on the same key from different threads are not atomic
- Comparing Memcached to Redis: Redis is a data structure server; Memcached is a distributed hash table

---

## What It Is

Think of a classroom with students who need access to textbooks. The school library has every book (the database), but checking out a book takes a trip across campus. Instead, the teacher keeps a small shelf of the most-used books in the classroom (the cache). When a student needs a book, they check the classroom shelf first. If it is there, great — immediate access. If not, they go to the library, borrow it, and put it on the shelf for others. When the shelf is full, the least-recently-used book goes back to make room. The shelf is Memcached: simple, shared, ephemeral, and fast.

Memcached was created in 2003 by Brad Fitzpatrick at LiveJournal. Its design philosophy is radical simplicity. It stores arbitrary byte values associated with string keys. It does not support complex data structures, server-side scripting, persistence, replication, or transactions. What it does do is store and retrieve data very fast, using all available CPU cores, with extremely low latency. For the specific use case of caching database query results and rendered HTML fragments, Memcached is one of the most efficient tools available.

The critical architectural difference from Redis is threading. Redis uses a single thread for command execution, which ensures atomic operations but limits throughput to one CPU core (plus I/O threads in Redis 6+). Memcached uses a thread-per-connection model with a fixed thread pool. Multiple client requests are processed simultaneously by different threads. This makes Memcached more efficient at saturating multiple CPU cores under high read concurrency. A Memcached instance on an 8-core machine can genuinely utilize all 8 cores for cache operations.

The tradeoff is the absence of atomicity guarantees. Two threads handling two simultaneous INCR operations on the same key might interfere with each other without compare-and-swap (CAS). Memcached provides CAS (Check-And-Set) as an atomic compare-and-swap: you provide the CAS token you received with the previous GET, and the SET succeeds only if the value has not changed since you read it. This is optimistic locking — correct but with retry logic required.

---

## How It Actually Works

Memcached's memory allocator is a slab allocator. Rather than using malloc/free for each key-value pair (which causes memory fragmentation over time), Memcached pre-allocates memory in "slabs" of fixed sizes, grouped into "slab classes." A 64-byte value goes into the slab class for values up to 64 bytes. A 1,024-byte value goes into the slab class for values up to 1,024 bytes. When a slab class is full, Memcached evicts the LRU item from that class to make room.

This design has a practical implication: if most of your cached values are exactly 100 bytes and a few are 900 bytes, the 100-byte slab classes may fill up and start evicting while the 900-byte classes have unused space. Memory is not fungible across slab classes. Real-world Memcached deployments sometimes encounter this "slab imbalance" under workloads with bimodal value size distributions.

Clustering in Memcached is entirely client-side. The Memcached server has no knowledge of other Memcached servers. There is no cluster membership, no slot assignment, no automatic failover. The client library maintains a list of servers and uses consistent hashing to determine which server holds each key. If a server is added, the client library must be reconfigured. If a server fails, the keys it held become cache misses — requests fall through to the database until those keys are regenerated from other servers.

```python
from pymemcache.client.hash import HashClient
from pymemcache.client.base import Client

# Consistent hashing client — distributes keys across multiple servers
client = HashClient([
    ('memcached-1', 11211),
    ('memcached-2', 11211),
    ('memcached-3', 11211),
])

# Basic cache-aside operations
def get_user(user_id: int) -> dict | None:
    key = f"user:{user_id}"
    cached = client.get(key)
    if cached is not None:
        import json
        return json.loads(cached)

    user = db.get_user(user_id)
    if user:
        import json
        client.set(key, json.dumps(user), expire=300)  # 5 min TTL
    return user

# CAS (Compare-And-Set) for safe concurrent updates
def safe_increment_counter(key: str) -> int:
    for _ in range(10):  # retry up to 10 times
        value, cas_token = client.gets(key)
        new_value = (int(value or 0)) + 1
        if client.cas(key, str(new_value), cas_token, expire=3600):
            return new_value
    raise RuntimeError("CAS retry limit exceeded")

# Multi-get: fetch multiple keys in one round trip (major Memcached optimization)
def get_users_bulk(user_ids: list[int]) -> dict[int, dict]:
    keys = {f"user:{uid}": uid for uid in user_ids}
    results = client.get_many(list(keys.keys()))
    
    users = {}
    missing_ids = []
    for key, uid in keys.items():
        if key in results:
            users[uid] = json.loads(results[key])
        else:
            missing_ids.append(uid)
    
    # Fetch missing from DB
    if missing_ids:
        db_users = db.get_users_bulk(missing_ids)
        for uid, user in db_users.items():
            users[uid] = user
            client.set(f"user:{uid}", json.dumps(user), expire=300)
    
    return users
```

Multi-get (fetching multiple keys in a single request) is a particularly important Memcached optimization. Instead of N round trips to fetch N cached values, `get_many` fetches all N in a single pipelined request. This is critical for page rendering that needs to fetch many individual cached objects — user profiles, article metadata, comment counts. The reduction in round trips from N to 1 is a significant latency improvement for read-heavy applications.

---

## How It Connects

Memcached and Redis serve overlapping but not identical use cases. The comparison between them should be grounded in concrete requirements about data structure needs, persistence, and threading model.

[[redis-architecture|Redis Architecture]]

The same caching strategies — cache-aside, TTL-based invalidation — apply equally to Memcached. The implementation differs (no native sorted sets or lists, no Lua scripts) but the pattern is the same.

[[caching-strategies|Caching Strategies]]

Memcached's client-side sharding uses the same consistent hashing principles that Redis Cluster uses server-side, but the client implements it rather than the server.

[[consistent-hashing|Consistent Hashing]]

---

## Common Misconceptions

Misconception 1: "Redis has made Memcached obsolete — I should always choose Redis."
Reality: Memcached has genuine advantages in specific scenarios. Its multi-threaded architecture performs better than Redis at pure key-value get/set workloads on multi-core machines. Its slab allocator produces less memory fragmentation for homogeneous value sizes. For very high-throughput simple caching with no need for persistence, data structures, or server-side scripting, Memcached is still a valid and competitive choice. Major sites (Facebook historically) still use Memcached at massive scale.

Misconception 2: "Memcached is reliable because it has multiple servers."
Reality: Memcached has no native high availability. If a Memcached server fails, the keys it holds become cache misses. Those misses fall through to the database, which may or may not be able to handle the sudden increase in load. There is no replica that promotes, no automatic failover, no data recovery. Memcached is assumed to be a volatile cache where data loss is acceptable. Applications must handle this.

Misconception 3: "Memcached's lack of data structures is a limitation that makes it less useful."
Reality: The absence of complex data structures is a deliberate design choice, not a limitation. By supporting only simple key-value operations, Memcached's implementation can be maximally optimized for that one operation. If your caching use case does not require sorted sets, pub/sub, or Lua scripts, the simpler tool is often the faster and more stable tool.

---

## Why It Matters in Practice

Memcached is the clearer tool when the requirements are: pure caching, high read concurrency on multi-core hardware, homogeneous value sizes, no persistence needed, no complex data structure operations, no server-side logic. In this scenario, Memcached's multi-threaded model and slab allocator outperform Redis's single-threaded model. Most Python applications use Redis because of its versatility — sessions, queues, pub/sub, leaderboards. But when caching is the exclusive use case and throughput is the primary concern, Memcached is worth considering.

The practical Python ecosystem leans strongly toward Redis — the redis-py library is mature, well-documented, and covers far more features. Memcached's pymemcache library is capable but less discussed. For new Python projects, Redis is the default choice; Memcached becomes relevant when performance benchmarking reveals Redis's single-threaded execution as the actual bottleneck.

---

## Interview Angle

Common question forms:
- "When would you choose Memcached over Redis?"
- "What are the limitations of Memcached compared to Redis?"
- "How does Memcached's threading model differ from Redis?"

Answer frame:
Describe Memcached as a pure, multi-threaded cache with no persistence, no data structures, and client-side sharding. Compare to Redis: Redis is a data structure server with optional persistence, single-threaded execution, and server-side clustering. Choose Memcached when: pure high-throughput caching, multi-core utilization is important, no persistence needed, no complex server-side operations needed. Choose Redis when: you need data structures, pub/sub, persistence, server-side scripting, or a single tool that handles caching plus other use cases.

---

## Related Notes

- [[redis-architecture|Redis Architecture]]
- [[redis-data-structures|Redis Data Structures]]
- [[caching-basics|Caching Basics]]
- [[caching-strategies|Caching Strategies]]
- [[consistent-hashing|Consistent Hashing]]
