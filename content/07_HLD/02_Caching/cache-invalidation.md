---
title: 03 - Cache Invalidation
description: "How and when to remove or update stale cached data  -  TTL-based, event-driven, and explicit invalidation strategies, plus the cache stampede problem."
tags: [cache-invalidation, caching, consistency, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Cache Invalidation

> Phil Karlton famously said there are only two hard things in computer science: cache invalidation and naming things. The difficulty is real  -  get it wrong and you have silent correctness bugs that appear only in production under load.

---

## Quick Reference

**Core idea:**
- Cache invalidation is the process of removing or marking stale cached data
- TTL-based invalidation: every entry expires after a fixed time, regardless of whether it changed
- Event-driven invalidation: the cache is explicitly cleared when the underlying data changes
- Cache stampede (thundering herd): many simultaneous cache misses for the same key overwhelm the origin
- Write-on-invalidate: delete the cache key on database write so the next read repopulates correctly

**Tricky points:**
- There is no universally correct TTL  -  it depends on how often data changes and how stale is acceptable
- Event-driven invalidation requires the write path to know which cache keys to invalidate  -  complex at scale
- Cache stampede is most dangerous for popular entries with identical TTL that expire simultaneously
- "Stale-while-revalidate" serves the old value while refreshing in the background  -  reduces stampede risk
- CDC (Change Data Capture) can drive invalidation without coupling the write path to the cache

---

## What It Is

Imagine you print a map of your city and laminate it for convenience. The map is accurate on the day you print it. Over time, streets change, new buildings appear, and old ones are demolished. Your laminated map is now wrong in some places, but you do not know which places or how wrong. If you throw away the map and print a new one every day (TTL-based invalidation), you always have a reasonably fresh map. If you subscribe to a city planning newsletter and replace only the affected sections when changes are announced (event-driven invalidation), you have a more accurate map with less waste. But subscribing to every possible change and correctly identifying which map sections to update is complex.

Cache invalidation is exactly this problem applied to data systems. A cached value is accurate at the moment it is written to the cache. Every subsequent write to the underlying data store makes the cached value potentially stale. Invalidation is the mechanism that keeps cached values from being served past the point where they are dangerously outdated.

TTL-based invalidation is the simplest approach: every cache entry is given an expiry time when it is stored. After that time, the entry is removed (or marked as needing revalidation). The TTL value encodes your tolerance for staleness. A TTL of 60 seconds means cache entries are at most 60 seconds old. A TTL of 24 hours means they could be up to 24 hours stale. TTL-based invalidation requires no coordination between the write path and the cache  -  every entry simply expires. Its weakness is the stampede: if many popular entries share the same TTL and they all expire at the same moment (for example, because a cache was completely cleared and repopulated at a specific time), requests for all of them will miss simultaneously and overwhelm the origin.

Event-driven invalidation is more precise: when a piece of data is written to the database, the write path also explicitly deletes or updates the corresponding cache key. The cache entry is only invalid after a write actually occurs. For data that changes rarely, this keeps the cache hot and correct. The challenge is correctness: the write path must know exactly which cache keys correspond to the data being written. For simple key-value patterns, this is straightforward. For data accessed via complex queries or aggregated views, knowing which cache keys to invalidate requires tracking dependencies  -  a non-trivial engineering problem.

---

## How It Actually Works

The cache stampede (also known as thundering herd or dog-piling) deserves careful treatment because it is a common failure mode in production systems. When a high-traffic cache entry expires, many requests arrive at nearly the same time. Each finds the entry missing. Each independently queries the database. Each gets the result. Each writes it back to the cache. The result is that the database receives a spike of identical queries simultaneously  -  precisely when the cache was supposed to be protecting it.

The key-level mutex is one mitigation: before querying the database for a cache miss, the first thread to detect the miss acquires a distributed lock on that cache key. Other threads finding the miss check if the lock is held and, if so, wait briefly and retry the cache lookup. The lock-holder fetches from the database and populates the cache. Others then find a warm cache. Redis supports this with `SET key value NX EX` (set if not exists, with expiry) as a distributed lock primitive.

Probabilistic early expiration (also called "jitter" or "PER  -  Probabilistic Early Revalidation") works differently: instead of waiting for the TTL to expire, the system begins probabilistically refreshing the entry slightly before it expires. The probability of refreshing increases as the entry approaches its TTL. This spreads the refresh work over time rather than creating a cliff edge at expiry. Netflix uses this approach in their caching layer.

Stale-while-revalidate is an HTTP Cache-Control directive (and a Redis pattern) that serves the stale cached value immediately and triggers a background refresh. The user gets a response instantly (even if slightly stale), and the cache is updated in the background. This is appropriate for data where a momentarily stale value is far better than the latency of a synchronous refresh.

```python
import redis
import json
import threading
import time

r = redis.Redis()

def get_user_with_mutex(user_id: int) -> dict:
    """Cache-aside with mutex to prevent stampede."""
    cache_key = f"user:{user_id}"
    lock_key = f"lock:user:{user_id}"
    
    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)
    
    # Try to acquire lock (NX = only set if not exists, EX = expire in 10s)
    acquired = r.set(lock_key, "1", nx=True, ex=10)
    if acquired:
        try:
            # We got the lock  -  fetch from DB and populate
            user = db.get_user(user_id)
            r.setex(cache_key, 300, json.dumps(user))
            return user
        finally:
            r.delete(lock_key)
    else:
        # Another thread is refreshing  -  wait and retry
        time.sleep(0.05)  # 50ms backoff
        cached = r.get(cache_key)
        if cached:
            return json.loads(cached)
        # Fallback: query DB without cache (lock may have expired)
        return db.get_user(user_id)

def invalidate_user_cache(user_id: int) -> None:
    """Call this whenever the user record is updated."""
    r.delete(f"user:{user_id}")
    # Also invalidate any derived cache keys
    r.delete(f"user_profile:{user_id}")
    r.delete(f"user_permissions:{user_id}")
```

Change Data Capture (CDC) decouples the write path from cache invalidation. Instead of adding invalidation calls to every write operation, a CDC tool (like Debezium for MySQL/PostgreSQL) reads the database's binary replication log and emits change events. A consumer of these events performs the cache invalidation. This approach is powerful because it works for all writes  -  including writes from other services, batch jobs, and manual database updates  -  not just writes through the application code.

---

## Visualizer

<iframe src="/static/visualizers/cache-invalidation.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="Cache Invalidation Visualizer"></iframe>

---

## How It Connects

Cache invalidation is the hardest part of the broader cache strategy problem. The write strategy determines when invalidation should happen; invalidation determines how.

[[caching-strategies|Caching Strategies]]

The outbox pattern and Change Data Capture are closely related: CDC reads the database log to drive downstream actions, including cache invalidation. The same tools that power event-driven architectures power event-driven invalidation.

[[outbox-pattern|Outbox Pattern]]

CDNs face the same invalidation challenge at a global scale: after a deployment that changes static assets, CDN caches must be purged before users see the new content.

[[cdn|CDN]]

---

## Common Misconceptions

Misconception 1: "Setting a short TTL solves all cache invalidation problems."
Reality: A short TTL reduces the staleness window but does not eliminate it and introduces other problems. Very short TTLs (under 1 second) effectively disable caching for that key. TTLs of 1 - 10 seconds still allow brief windows of stale data and increase database load significantly. Short TTLs also do not help with the cache stampede problem  -  they make it worse, since more frequent expiry means more frequent stampedes.

Misconception 2: "Deleting a cache key is the safest invalidation strategy."
Reality: Deleting is safe from a correctness standpoint (the next read gets fresh data), but it can cause stampedes if the deleted key is popular. For high-traffic keys, prefer updating the cache value atomically on write rather than deleting, or use a short TTL combined with background refresh.

Misconception 3: "CDC-based invalidation is immediate."
Reality: CDC reads from the replication log, which has a lag. The consumer processes events asynchronously. Between the write completing and the invalidation event being processed, the cache is stale. This window is typically small (milliseconds to seconds) but not zero. For strongly-consistent use cases, CDC-based invalidation may not be appropriate.

---

## Why It Matters in Practice

Cache invalidation failures are among the most insidious bugs in production systems. They do not crash the application  -  they silently return wrong data. A user updates their email address, but for the next five minutes, your system (and potentially dependent systems) still associates them with the old address. A product's price changes, but your checkout flow quotes customers the old price. These bugs are hard to reproduce (they require specific timing conditions), hard to detect (no exception is thrown), and potentially serious (financial impact, user trust).

The practical discipline is: every time you add a cache key, document its TTL and invalidation conditions. Write the invalidation logic in the same commit as the caching logic  -  not as an afterthought. Test invalidation explicitly: write a test that writes data, populates the cache, updates the data, verifies the cache is invalidated, and verifies the next read returns fresh data.

---

## Interview Angle

Common question forms:
- "What is a cache stampede and how do you prevent it?"
- "How do you keep a cache consistent with the database?"
- "Explain the trade-off between TTL-based and event-driven invalidation."

Answer frame:
Define cache invalidation. Explain TTL (simple, bounded staleness, stampede risk) vs event-driven (precise, coupling between write path and cache). Explain the stampede: what it is, when it occurs, why it is dangerous. Walk through three mitigations: mutex/lock, probabilistic early refresh, stale-while-revalidate. Mention CDC as a decoupled event-driven approach. Close with the practical advice: document TTL and invalidation conditions for every cache key.

---

## Related Notes

- [[caching-basics|Caching Basics]]
- [[caching-strategies|Caching Strategies]]
- [[redis-architecture|Redis Architecture]]
- [[outbox-pattern|Outbox Pattern]]
