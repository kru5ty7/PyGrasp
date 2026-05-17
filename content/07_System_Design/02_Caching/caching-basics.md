---
title: 01 - Caching Basics
description: "How caches work, where they live in a system, and the fundamental trade-offs of hit rate, eviction, and data freshness."
tags: [caching, performance, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Caching Basics

> A cache is a bet: you are betting that storing a result now will save more time than it costs to store and manage it — and understanding when that bet pays off is the skill.

---

## Quick Reference

**Core idea:**
- A cache stores results of expensive operations so future requests can be served faster
- Cache hit: the requested value is in the cache; cache miss: it must be fetched from the source
- Hit rate = hits / (hits + misses) — even a 90% hit rate means 10% of requests still hit the slow path
- Eviction policies (LRU, LFU, TTL) determine what is removed when the cache is full
- Caches exist at many levels: CPU L1/L2/L3, OS page cache, in-process, distributed (Redis), CDN edge

**Tricky points:**
- Caching stale data is a silent correctness bug — always think about when cache contents become wrong
- Higher hit rate is not always achievable: some data is accessed uniformly (no hot keys) and caching adds overhead with no benefit
- In-process caches do not synchronize across multiple application instances — each server has its own copy
- A cache stampede (thundering herd) occurs when many simultaneous requests all miss the cache at the same time
- Warming a cache takes time — cold start means initial high miss rate and potentially overloaded origin

---

## What It Is

Imagine a librarian who is asked the same question many times per day: "What is the current price of gold?" The honest answer requires checking a Reuters terminal, which takes two minutes. On the first query of the day, the librarian checks. On the second query ten minutes later, the librarian checks again. After fifty queries, the librarian thinks: the price changes only once an hour, so checking every minute is wasteful. Now the librarian writes down the price on a sticky note and checks if the note is recent before consulting Reuters. The sticky note is a cache. The price on the note is the cached value. The note's age determines whether to trust it or refresh it.

In software, a cache is a storage layer that holds the results of expensive computations or slow data fetches, making future requests for the same data faster. The canonical examples are: caching database query results in Redis (avoiding a 50ms database call), caching rendered HTML in memory (avoiding template rendering), caching third-party API responses (avoiding external network calls), or caching computed values in a dictionary (avoiding recalculation). The common thread is that the cached data was expensive to produce and is cheap to store.

The fundamental metrics of a cache are hit rate and miss rate. A cache hit occurs when a request finds its data in the cache. A cache miss occurs when the data is not in the cache and must be fetched from the backing source. Hit rate is the fraction of requests that are hits. A hit rate of 95% means 95 out of 100 requests are served instantly from the cache, and only 5 go to the slower source. But that 5% still goes to origin — so under high load, even a 95% cache hit rate means significant origin load. The goal is not 100% hit rate (caching everything forever) but the highest hit rate achievable for the data that is actually hot (frequently accessed).

Eviction is what happens when the cache is full and a new item needs to be stored. The cache must remove something to make room. The eviction policy determines which item to remove. LRU (Least Recently Used) removes the item that was accessed least recently — the assumption is that items not accessed recently are unlikely to be accessed soon. LFU (Least Frequently Used) removes the item accessed fewest times — useful when some items are permanently popular and others are accessed in bursts. TTL (Time-To-Live) removes items after a fixed time, regardless of access pattern — useful when data has a known validity period.

---

## How It Actually Works

Caches exist at multiple levels in any real system, each with different characteristics. The CPU L1 cache is a few kilobytes, stored on the chip, and has access time of ~1 nanosecond. L2 is a few megabytes at ~10ns. L3 is tens of megabytes at ~40ns. These are managed by hardware and invisible to application code. The OS page cache holds recently-accessed disk pages in RAM — reading a file twice at the OS level reads it from disk once and from memory once. For Python applications, the OS page cache means that database files and log files accessed repeatedly are served from RAM, not disk.

In-process caches live in the application server's own memory space. Python's `functools.lru_cache` is an in-process cache: decorated function results are stored in a dictionary inside the process. They are fast (dictionary lookup is O(1)), require no network round-trip, and are automatically invalidated when the process restarts. The critical limitation is that in-process caches do not share state between processes or servers. If you run ten application server instances, each has its own cache. A cache miss on one instance means a database call even if nine other instances have a warm cache for that key.

Distributed caches like Redis store cached data in a separate process (or cluster), accessible over the network. All application instances share the same cache. A write from any instance is visible to all others. The tradeoff is latency: a Redis cache hit takes ~1ms (a local network call) versus microseconds for in-process. For data that changes across instances and must be consistent — user sessions, feature flags, rate limit counters — distributed caches are necessary. For per-request computed values that do not change between instances, in-process caching is faster.

```python
import functools
import time

# In-process cache: fast but not shared across processes
@functools.lru_cache(maxsize=1000)
def get_exchange_rate(currency: str) -> float:
    """Expensive: hits an external API."""
    response = requests.get(f"https://api.forex.example.com/rate/{currency}")
    return response.json()['rate']

# Problem: lru_cache caches forever — stale after the rate changes
# Better: use a TTL-aware cache

import redis
import json

r = redis.Redis()

def get_exchange_rate_with_ttl(currency: str, ttl_seconds: int = 300) -> float:
    cache_key = f"exchange_rate:{currency}"
    cached = r.get(cache_key)
    if cached:
        return float(cached)  # cache hit

    # cache miss — fetch from API
    response = requests.get(f"https://api.forex.example.com/rate/{currency}")
    rate = response.json()['rate']
    r.setex(cache_key, ttl_seconds, rate)  # store with TTL
    return rate
```

The cache stampede (also called thundering herd or dog-piling) is a failure mode that occurs when a popular cache entry expires and many requests simultaneously try to refresh it. Each request finds a cache miss, each independently calls the origin, and the origin receives a burst of simultaneous requests — potentially overwhelming it. The cache was supposed to protect the origin, but its expiry caused a spike. Mitigations include: probabilistic early expiration (refresh slightly before TTL expires with increasing probability as expiry approaches), mutex locks (only one request refreshes at a time; others wait), and background refresh (a separate process proactively refreshes hot entries before they expire).

---

## How It Connects

Different caching strategies determine when data is loaded into the cache, when it is written back, and who is responsible for keeping cache and database in sync. Choosing the wrong strategy causes stale reads or write performance problems.

[[caching-strategies|Caching Strategies]]

Cache invalidation — how and when to remove stale entries — is widely considered the hardest problem in caching. It encompasses TTL-based, event-driven, and explicit invalidation approaches.

[[cache-invalidation|Cache Invalidation]]

Redis is the most commonly used distributed cache in Python applications, and its specific architecture explains why it is so fast despite being a separate network service.

[[redis-architecture|Redis Architecture]]

---

## Common Misconceptions

Misconception 1: "Caching everything improves performance."
Reality: Caching has overhead: memory cost, serialization cost, and cache management cost. Data that is accessed exactly once is cached and then evicted — the cache provided no benefit and added work. Caching is effective when the same data is requested many times. Profiling access patterns before adding caching is worthwhile.

Misconception 2: "A high cache hit rate means the cache is working perfectly."
Reality: A high hit rate at the cache layer does not mean the origin is protected. If your traffic is 100,000 requests per second and your hit rate is 95%, you still have 5,000 requests per second hitting origin. Whether origin can handle 5,000 RPS is a separate question. Hit rate is a relative metric; absolute origin load is what matters for capacity.

Misconception 3: "Cache TTL determines how stale my data can be."
Reality: TTL sets an upper bound on staleness. Data can become stale the moment after a write to the database, regardless of TTL. If you write a new value to the database but the cache still holds the old value, the cache is stale from that instant until the TTL expires or an explicit invalidation occurs. TTL-based freshness is a best-effort guarantee, not an exact one.

---

## Why It Matters in Practice

Caching is one of the highest-leverage optimizations available. A cache hit that serves data from Redis in 1ms instead of the database's 50ms is a 50x speedup for that call. In aggregate, this translates to lower server costs, better user experience, and higher throughput. Systems that do not cache effectively either have very expensive infrastructure or have poor response times.

The risks are also real. A cache that returns stale data for financial balances or inventory counts causes business-level correctness bugs. A cache stampede at peak traffic — caused by all popular cache entries having the same TTL and expiring simultaneously — can take down the origin. Understanding caching means understanding both when to use it and how to invalidate it correctly.

---

## Interview Angle

Common question forms:
- "How would you use caching to scale this read-heavy service?"
- "What is a cache stampede and how do you prevent it?"
- "When would you use an in-process cache vs a distributed cache?"

Answer frame:
Define cache hit/miss and hit rate. Explain the levels of caching (in-process for single-server speed, distributed for cross-instance consistency). Describe LRU, LFU, and TTL eviction policies. Explain the cache stampede problem and at least two mitigations (mutex, probabilistic refresh). Distinguish in-process from distributed caching and their tradeoffs. Close with when not to cache: low-hit-rate access patterns and correctness-sensitive data.

---

## Related Notes

- [[caching-strategies|Caching Strategies]]
- [[cache-invalidation|Cache Invalidation]]
- [[redis-architecture|Redis Architecture]]
- [[cdn|CDN]]
- [[latency-vs-throughput|Latency vs Throughput]]
