---
title: 02 - Caching Strategies
description: "Cache-aside, write-through, write-behind, and read-through  -  the four patterns that define how a cache stays synchronized with its backing store."
tags: [caching, cache-aside, write-through, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Caching Strategies

> Choosing the wrong caching strategy leads to stale reads, write amplification, or consistency bugs  -  the four main patterns each make a different tradeoff between simplicity, consistency, and performance.

---

## Quick Reference

**Core idea:**
- Cache-aside (lazy loading): the application checks cache first; on miss, loads from DB and populates cache
- Read-through: the cache itself fetches from DB on miss, transparent to the application
- Write-through: every write goes to cache and DB synchronously; cache always current
- Write-behind (write-back): writes go to cache immediately; DB is updated asynchronously
- Each strategy makes different tradeoffs between read performance, write performance, and consistency

**Tricky points:**
- Cache-aside is the most common and most flexible  -  but the application bears full responsibility for population
- Write-through doubles write latency (cache + DB must both succeed) but ensures consistency
- Write-behind has excellent write performance but risks data loss if the cache fails before writing to DB
- Read-through and write-through require the cache to understand the underlying data schema
- No single strategy is universally best  -  the choice depends on read/write ratio and consistency requirements

---

## What It Is

Think of a student studying for an exam. Their bookshelf (the database) has all the answers, but looking everything up takes time. They keep a notepad (the cache) with frequently referenced facts. How do they manage the notepad?

Strategy one: they do not pre-populate the notepad. When they need a fact, they check the notepad. If it is there (cache hit), they use it. If not (cache miss), they look it up from the bookshelf, write it on the notepad, and use it. The notepad fills up lazily with whatever they actually look up. This is cache-aside.

Strategy two: whenever they learn something new and write it in a notebook (update the database), they also write it on the notepad simultaneously. The notepad always reflects the latest state of their notebook. This is write-through.

Strategy three: they write new facts on the notepad first (fast, immediate acknowledgment), and separately, later in the day, they copy the notepad into the notebook. This is write-behind. The risk: if the notepad is lost before copying, the notebook never gets the update.

Each approach has a different risk profile and performance characteristic. The right choice depends on how important it is that the notepad is always accurate, how often facts change, and how often they are read.

In software, these patterns determine how a cache (typically Redis) stays synchronized with the backing store (typically a relational or document database). The four canonical strategies are cache-aside, read-through, write-through, and write-behind. Most production systems use cache-aside for reads and write-through or explicit invalidation for writes, but understanding all four enables informed architectural choices.

Cache-aside is the most common pattern. The application is responsible for cache management. On a read, the application first queries the cache. On a hit, it returns the cached value. On a miss, it queries the database, stores the result in the cache with a TTL, and returns it. On a write, the application writes to the database and either updates the cache with the new value or deletes the cache entry (forcing the next read to be a miss and repopulate from DB). Cache-aside is flexible  -  the application has full control  -  but it couples cache management logic to every part of the codebase that reads or writes the cached data.

---

## How It Actually Works

Write-through maintains cache-database consistency by writing to both on every update. When a record is updated, the application writes to the cache and the database in the same operation (or in sequence within the same request). The next read from the cache gets the updated value. The downside is latency: the write is not acknowledged until both the cache write and the database write succeed. This doubles the latency for write operations and adds two points of failure. Write-through is appropriate when reads far outnumber writes and cache consistency is critical.

Write-behind (also called write-back) inverts the priority: writes go to the cache immediately and are acknowledged as soon as the cache write succeeds. The database update happens asynchronously  -  after a small delay, in a background job, or when the cache entry is evicted. This gives excellent write latency (just a fast cache write) but introduces a window during which the cache and database are inconsistent. If the cache fails before writing to the database, the update is lost. Write-behind is appropriate for high-write workloads where occasional data loss is acceptable  -  analytics counters, user activity logs, real-time leaderboards.

Read-through and write-through are often provided by specialized cache libraries (like NCache or certain Redis client frameworks) that sit between the application and the database, handling cache miss logic transparently. The application simply calls `cache.get(key)` and the framework handles the miss by querying the database. This simplifies application code at the cost of requiring the cache layer to understand data schemas and query logic.

```python
import redis
import json
from typing import Optional

r = redis.Redis()

# Cache-aside pattern  -  explicit, application-managed
def get_user(user_id: int) -> Optional[dict]:
    cache_key = f"user:{user_id}"
    
    # Step 1: check cache
    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)  # cache HIT
    
    # Step 2: cache miss  -  fetch from database
    user = db.query("SELECT * FROM users WHERE id = %s", user_id)
    if user is None:
        return None
    
    # Step 3: populate cache with TTL
    r.setex(cache_key, 300, json.dumps(user))  # 5-minute TTL
    return user

def update_user(user_id: int, data: dict) -> None:
    # Write-through: update DB first, then invalidate cache
    db.execute("UPDATE users SET ... WHERE id = %s", user_id)
    r.delete(f"user:{user_id}")  # invalidate; next read will repopulate

    # Alternative write-through: update cache with new value instead of deleting
    # r.setex(f"user:{user_id}", 300, json.dumps({**existing_user, **data}))
    # Risk: race condition if DB update and cache update are not atomic

# Write-behind pattern  -  for high-write, loss-tolerant data
def increment_page_view(page_id: str) -> None:
    r.incr(f"pageviews:{page_id}")  # fast, in-memory increment
    r.expire(f"pageviews:{page_id}", 3600)  # flush to DB via background job

# Background job that syncs Redis counters to DB
def flush_page_views():
    for key in r.scan_iter("pageviews:*"):
        page_id = key.decode().split(":")[1]
        count = r.getdel(key)  # atomic get and delete
        if count:
            db.execute(
                "UPDATE pages SET view_count = view_count + %s WHERE id = %s",
                int(count), page_id
            )
```

The cache-aside write strategy has two variants. The simpler variant is to delete the cache entry on write, forcing the next read to be a miss and repopulate from the database. This is always safe: the worst case is a cache miss and a database read. The more aggressive variant is to update the cache entry directly with the new value, avoiding the miss. This is faster but introduces a race condition: two concurrent writers might both update the cache and the database in different orders, leaving the cache holding a stale value. For most use cases, delete-on-write is preferred.

---

## Visualizer

<iframe src="/static/visualizers/caching-strategies.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="Caching Strategies Visualizer"></iframe>

---

## How It Connects

All caching strategies must eventually deal with the question of when cached data becomes invalid and must be removed or refreshed. Cache invalidation is the mechanism; the strategy determines when invalidation is triggered.

[[cache-invalidation|Cache Invalidation]]

The choice of caching strategy is inseparable from the consistency guarantees your system needs. A write-behind cache has weaker consistency than write-through; understanding the full consistency model spectrum helps calibrate the decision.

[[consistency-models|Consistency Models]]

In Redis, the specific data structure you use (string, hash, sorted set) affects how efficiently you can implement each caching strategy, especially for partial updates.

[[redis-data-structures|Redis Data Structures]]

---

## Common Misconceptions

Misconception 1: "Cache-aside is inferior to write-through because it can return stale data."
Reality: Cache-aside with TTL-based expiration gives bounded staleness  -  the cache entry is at most TTL seconds old. Write-through does eliminate staleness on writes, but it adds write latency and double write points of failure. For most applications, bounded TTL staleness is an acceptable tradeoff for the simplicity of cache-aside.

Misconception 2: "Write-behind is dangerous and should never be used."
Reality: Write-behind is appropriate for specific use cases where high write throughput and acceptable data loss are both present  -  click counting, view counters, real-time leaderboards, telemetry. The key is acknowledging the risk and designing accordingly: use write-behind for data where losing a few seconds of updates is acceptable, not for financial transactions.

Misconception 3: "I should always update the cache when I write to the database, not delete the entry."
Reality: Updating the cache on write introduces race conditions under concurrent updates. Two writers may write to the database in one order and to the cache in another order, leaving the cache inconsistent. Deleting the cache entry on write is always safe: it forces a cache miss and a fresh database read, which correctly reflects the latest state. The performance cost of one extra cache miss per write is usually worth the correctness guarantee.

---

## Why It Matters in Practice

Cache bugs are some of the hardest to reproduce and debug because they depend on timing: whether a cache entry was warm or cold, whether an invalidation had propagated, whether two requests happened to run concurrently. A cache strategy chosen carelessly produces intermittent correctness bugs  -  a user sees their old profile picture for five minutes after updating it, or a price changes in the database but customers see the old price for an hour. Getting the strategy right from the start prevents these issues.

For Python applications, cache-aside is the most practical pattern because it requires no special framework support  -  just Redis and explicit get/set/delete calls. The discipline is consistency in how every read and every write interacts with the cache, which is easier to enforce through a service layer or repository pattern than through ad hoc Redis calls scattered through application code.

---

## Interview Angle

Common question forms:
- "What is cache-aside and how does it compare to write-through?"
- "When would you use write-behind caching?"
- "How do you keep the cache consistent with the database?"

Answer frame:
Define each pattern concisely. Explain that cache-aside is the default choice: simple, flexible, application-controlled. Write-through is appropriate when reads dominate and consistency is paramount. Write-behind is a performance optimization with data loss risk. Discuss the two write variants of cache-aside: delete-on-write (safe, one miss) vs update-on-write (faster, race condition risk). Connect to consistency requirements.

---

## Related Notes

- [[caching-basics|Caching Basics]]
- [[cache-invalidation|Cache Invalidation]]
- [[redis-architecture|Redis Architecture]]
- [[redis-data-structures|Redis Data Structures]]
