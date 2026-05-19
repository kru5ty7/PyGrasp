---
title: 05 - Redis Data Structures
description: "The seven core Redis data structures  -  string, list, set, sorted set, hash, bitmap, and stream  -  and the specific use cases each is designed for."
tags: [redis, data-structures, caching, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Redis Data Structures

> Redis is not a simple key-value store  -  its native data structures let you perform operations that would require multiple round trips in a generic store, and choosing the right structure often eliminates the need for complex application logic.

---

## Quick Reference

**Core idea:**
- String: bytes with atomic operations  -  counters, simple cache, sessions
- List: ordered sequence of strings  -  queues, activity feeds, recent items
- Set: unordered collection of unique strings  -  tags, unique visitors, membership
- Sorted Set (ZSet): set with a float score  -  leaderboards, rate limiting windows, time-series
- Hash: field-value map  -  user objects, partial updates without fetching the whole object
- Bitmap: bit array on a string  -  feature flags, daily active user tracking
- Stream: append-only log with consumer groups  -  event log, message queue with consumer groups

**Tricky points:**
- List is not a stack-safe queue for concurrent consumers  -  use a sorted set or stream instead
- Sorted sets score is a float64, which loses precision for large integers  -  be careful with timestamps
- EXPIRE sets TTL on the entire key, not individual hash fields  -  cannot expire individual hash fields separately
- Bitmaps are just strings with bit operations  -  BITCOUNT scales with the string length, not set bits
- A sorted set with score=timestamp efficiently implements sliding window rate limiting

---

## What It Is

Most key-value stores give you one type of value: a blob of bytes. You can store anything you want in that blob, but to do anything useful  -  find the highest score, check membership, add to a queue  -  you fetch the blob, deserialize it in application code, mutate it, serialize it, and write it back. This means multiple round trips, application-side logic for operations the server could do atomically, and no server-side atomicity guarantees.

Redis is different because it stores typed, structured values and exposes native operations on those structures. When you need a leaderboard, you do not build one from scratch  -  you use a sorted set, which natively supports "get top N elements by score" in O(log N) time. When you need a rate limiter, you use a sorted set with timestamps as scores and let Redis handle the sliding window arithmetic. The server does the work, atomically, without round trips.

The string type is Redis's most fundamental. "String" is a misnomer  -  it holds arbitrary bytes up to 512 MB. It has atomic increment/decrement operations (INCR, INCRBY, INCRBYFLOAT) that make it perfect for counters. It stores cached JSON, session tokens, or simple flags. The SET command accepts NX (only set if key does not exist) and EX (expiry in seconds) flags, making it a complete distributed lock primitive with a single command.

The list type stores an ordered sequence of strings. Elements can be pushed to or popped from either end in O(1). RPUSH appends to the right; LPOP removes from the left  -  this is a FIFO queue. LPUSH to the left and LPOP from the left is a stack. LRANGE retrieves a range of elements, making it suitable for activity feeds where you want the last N items. BLPOP is a blocking pop  -  it waits until an element is available, making Redis lists a primitive for simple task queues. However, lists do not support multiple consumers reliably  -  two consumers calling BLPOP compete, and one may starve.

---

## How It Actually Works

The set type stores an unordered collection of unique strings. SADD adds a member; SREM removes one; SISMEMBER checks membership in O(1). Set operations  -  union (SUNION), intersection (SINTER), difference (SDIFF)  -  are native commands. Sets are ideal for tracking unique items: unique visitors to a page, the set of tags on an article, or the set of users who have completed an action. The "unique" guarantee is native  -  adding a duplicate is silently ignored.

The sorted set (ZSet) is arguably Redis's most powerful structure. Every member has an associated float score. Members are stored in sorted order by score, with O(log N) insertion and score-based range queries. ZADD adds a member with a score. ZRANGE retrieves members by position. ZRANGEBYSCORE retrieves members by score range. ZRANK returns the position of a member. ZREVRANK returns the position from the end. This makes sorted sets perfect for leaderboards, priority queues, and sliding window rate limiters.

The hash type stores a field-value map on a single key. HSET sets one or more fields. HGET retrieves a single field. HMGET retrieves multiple fields. HGETALL retrieves all fields and values. Hashes are ideal for storing objects: `user:1001` might have fields `name`, `email`, `created_at`. You can fetch or update individual fields without deserializing the entire object. Memory-wise, Redis compresses small hashes (fewer than 128 fields, values under 64 bytes) into a ziplist, using significantly less memory than storing the same data as individual string keys.

```python
import redis
import time

r = redis.Redis(decode_responses=True)

# --- String: distributed counter ---
r.set('page_views:homepage', 0)
r.incr('page_views:homepage')  # atomic increment
views = int(r.get('page_views:homepage'))

# --- List: recent activity feed ---
user_id = "user:1001"
r.lpush(f"feed:{user_id}", "Liked post #5", "Commented on post #3")
r.ltrim(f"feed:{user_id}", 0, 99)   # keep only the latest 100 items
recent = r.lrange(f"feed:{user_id}", 0, 9)  # get latest 10

# --- Set: unique page visitors ---
r.sadd("visitors:2026-05-18", "user:1001", "user:1002", "user:1001")  # dupe ignored
r.sadd("visitors:2026-05-17", "user:1001", "user:1003")
returning = r.sinter("visitors:2026-05-18", "visitors:2026-05-17")  # set intersection

# --- Sorted Set: leaderboard + sliding window rate limiter ---
r.zadd("leaderboard", {"alice": 1500, "bob": 1200, "carol": 1800})
top3 = r.zrevrange("leaderboard", 0, 2, withscores=True)

# Rate limiter: allow 10 requests per 60 seconds per user
def check_rate_limit(user_id: str, limit: int = 10, window: int = 60) -> bool:
    key = f"ratelimit:{user_id}"
    now = time.time()
    pipe = r.pipeline()
    pipe.zremrangebyscore(key, 0, now - window)  # remove old entries
    pipe.zadd(key, {str(now): now})              # add current timestamp
    pipe.zcard(key)                              # count entries in window
    pipe.expire(key, window)
    _, _, count, _ = pipe.execute()
    return count <= limit

# --- Hash: user object with partial update ---
r.hset("user:1001", mapping={"name": "Alice", "email": "alice@example.com", "plan": "free"})
r.hset("user:1001", "plan", "premium")  # update single field without fetching whole object
email = r.hget("user:1001", "email")

# --- Bitmap: daily active users ---
# bit position = user_id; SET bit = user was active today
r.setbit("dau:2026-05-18", 1001, 1)  # user 1001 was active
r.setbit("dau:2026-05-18", 1002, 1)  # user 1002 was active
total_active = r.bitcount("dau:2026-05-18")  # count of set bits
```

The bitmap type uses bit-level operations on string values. SETBIT sets a specific bit position; GETBIT reads it; BITCOUNT counts set bits. Bitmaps are exceptionally memory-efficient for tracking boolean state across large numeric ranges. Tracking which of one million users were active today requires 125 KB (1,000,000 bits / 8 bits per byte), compared to megabytes for storing user IDs as strings. BITOP (bitwise AND, OR, XOR) enables operations like "users active on both Monday and Tuesday."

The stream type (Redis 5.0+) is an append-only log with consumer group semantics. XADD appends an entry with an auto-generated or specified ID and arbitrary field-value pairs. Consumer groups allow multiple consumers to divide the stream  -  each consumer in a group receives a different subset of messages, and Redis tracks which messages have been acknowledged. This is Redis's native message queue mechanism, similar to Kafka but without Kafka's partition-level scalability.

---

## Visualizer

<iframe src="/static/visualizers/redis-data-structures.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="Redis Data Structures Visualizer"></iframe>

---

## How It Connects

The sorted set rate limiter pattern shown above requires atomic execution across multiple commands. Redis's single-threaded event loop ensures pipeline atomicity, but the combined ZREMRANGEBYSCORE + ZADD + ZCARD could also be a Lua script for absolute atomicity.

[[redis-architecture|Redis Architecture]]

For data that outlives a single Redis instance or that requires durability, understanding how Redis persists data  -  and what is lost on crash  -  is critical to deciding which data lives in Redis vs a relational database.

[[redis-persistence|Redis Persistence]]

In a clustered deployment, Redis distributes keys across slots, which affects how multi-key operations (like SINTER, set intersection) work  -  both keys must be on the same node.

[[redis-clustering|Redis Clustering]]

---

## Common Misconceptions

Misconception 1: "I should use strings with JSON for everything since it's simplest."
Reality: Storing a user object as a JSON string requires fetching, deserializing, mutating, serializing, and re-storing the entire object to update one field. A Redis hash lets you update a single field with HSET and read a single field with HGET, saving serialization overhead and enabling partial reads. For objects with many fields that are updated independently, hashes are far more efficient.

Misconception 2: "Lists are a good general-purpose message queue."
Reality: Redis lists work fine for single-consumer queues. For multiple consumers, two consumers calling BLPOP compete non-deterministically. Lists also have no acknowledgment mechanism  -  a consumer that crashes after popping an item loses that item permanently. Redis Streams with consumer groups provide delivery guarantees and multi-consumer semantics. For production queue workloads, use streams or a dedicated queue system.

Misconception 3: "EXPIRE on a hash key expires individual fields over time."
Reality: EXPIRE applies to the entire key. When the TTL fires, the entire hash is deleted. There is no per-field TTL in Redis (outside of specialized Modules). If you need some fields to expire independently, store them as separate keys with individual TTLs, not as hash fields.

---

## Why It Matters in Practice

Choosing the right Redis data structure can eliminate entire categories of application code. A leaderboard that would require a sorted list maintained by the application becomes a two-line sorted set operation. A unique visitor counter that would require deduplication logic becomes a set with SADD. A sliding window rate limiter becomes a sorted set with timestamps. The structures are not just performance optimizations  -  they shift where the logic lives, making it simpler and more reliable.

Memory is the primary constraint in Redis. Choosing inappropriate structures wastes memory and reduces how much data you can store per instance. Small hashes stored as individual keys use significantly more memory than hashes stored as Redis hash types (due to key overhead). The ziplist encoding for small collections is automatic but has size thresholds  -  exceeding them causes encoding upgrades that increase memory usage.

---

## Interview Angle

Common question forms:
- "How would you implement a leaderboard using Redis?"
- "Design a rate limiter using Redis."
- "When would you use a Redis hash vs a Redis string?"

Answer frame:
For leaderboard: sorted set with ZADD, ZREVRANGE, ZRANK  -  explains score semantics and O(log N) operations. For rate limiter: sliding window with sorted set (timestamps as scores), pipeline of ZREMRANGEBYSCORE + ZADD + ZCARD + EXPIRE. For hash vs string: hash for structured objects where you need field-level reads/writes; string for simple values, counters, and binary data. Always tie the choice to the access pattern.

---

## Related Notes

- [[redis-architecture|Redis Architecture]]
- [[redis-persistence|Redis Persistence]]
- [[redis-clustering|Redis Clustering]]
- [[caching-strategies|Caching Strategies]]
- [[redis-python|Redis with Python]]
