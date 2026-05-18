---
title: 10 - Redis with Python
description: "redis-py is the standard Python client for Redis, providing synchronous and async interfaces to Redis's in-memory data structures  -  caching, distributed locks, queues, and pub/sub are its primary use cases in web applications."
tags: [redis, redis-py, caching, pub-sub, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Redis with Python

> Redis is a fast in-memory data structure server  -  redis-py gives Python applications access to its rich set of data types for caching, rate limiting, distributed coordination, and messaging patterns.

---

## Quick Reference

**Core idea:**
- `Redis(host, port, db, decode_responses=True)` creates a client; `r.get(key)` / `r.set(key, value, ex=ttl)` for basic cache operations
- redis-py maintains a built-in `ConnectionPool`  -  the client is safe to share globally across an application
- `redis.asyncio.Redis` offers the same API with awaitable methods for async applications
- Data structure commands: `lpush/rpop` (list as queue), `sadd/smembers` (set), `zadd/zrange` (sorted set), `hset/hgetall` (hash)
- Distributed lock pattern: `SET key value NX PX milliseconds`  -  atomic set-if-not-exists with expiry

**Tricky points:**
- `decode_responses=True` decodes byte strings to Python `str` automatically  -  without it, all values come back as `bytes`
- TTL is not automatically renewed on read  -  a cache entry expires at its set time regardless of access patterns; you must explicitly call `r.expire(key, seconds)` to extend it
- `r.delete(key)` is a no-op on nonexistent keys  -  it does not raise an error; check the return value (number of keys deleted) if you need to detect missing keys
- Pub/sub consumers block the connection  -  the subscriber connection cannot be used for other commands while listening; use a separate connection
- Redis Cluster requires `RedisCluster` client, not the standard `Redis` client  -  key hash slots must be planned to avoid cross-slot operations in multi-key commands

---

## What It Is

Think of Redis as a giant, shared, in-memory Python dictionary that every process in your distributed application can read and write simultaneously, with built-in support for expiry, atomic operations, and a dozen specialized data structures. A regular Python dictionary lives in one process and dies when the process exits. Redis lives outside all processes, persists through restarts (if configured), and is accessible to every application instance in your cluster.

This property makes Redis invaluable for tasks that inherently require cross-process coordination. A web application running ten worker processes cannot share session data, rate-limit counters, or cached query results through in-process memory  -  each worker has its own memory space. Redis provides the shared layer. The cache-aside pattern is its most common use: before issuing an expensive database query, check Redis first; if the value is present and not expired, return it; otherwise run the query, store the result in Redis with a TTL, and return it. Subsequent requests served by any worker process find the cached value.

Redis is also fast enough to serve as the primary store for ephemeral data. A sorted set with timestamps as scores makes a natural sliding-window rate limiter. A list with `lpush` and `rpop` is a FIFO queue. A hash stores all fields of an object under a single key. None of these require the write-and-commit cycle of a relational database, and all operations are guaranteed atomic at the single-command level.

---

## How It Actually Works

The basic redis-py interface is intentionally close to Python's built-in dict. Commands map almost directly to Redis commands.

```python
import redis

r = redis.Redis(host="localhost", port=6379, db=0, decode_responses=True)

# String: cache with TTL
r.set("user:42:name", "Alice", ex=3600)   # expires in 1 hour
name = r.get("user:42:name")              # "Alice" or None if expired

# Hash: store all user fields under one key
r.hset("user:42", mapping={"name": "Alice", "email": "alice@example.com"})
user = r.hgetall("user:42")               # {"name": "Alice", "email": "..."}

# List: simple task queue
r.lpush("tasks", "task_id_1", "task_id_2")
task = r.rpop("tasks")                    # FIFO: pops oldest item

# Sorted set: leaderboard or scheduled jobs
r.zadd("leaderboard", {"alice": 1500, "bob": 1200})
top = r.zrange("leaderboard", 0, 9, withscores=True, rev=True)  # top 10

# Set: unique visitors
r.sadd("visitors:2026-05-18", "user:42", "user:91")
count = r.scard("visitors:2026-05-18")   # cardinality
```

The async client in `redis.asyncio` has an identical API with `await` prefixes.

```python
import redis.asyncio as aioredis

r = aioredis.Redis(host="localhost", port=6379, decode_responses=True)
await r.set("key", "value", ex=60)
value = await r.get("key")
```

The distributed lock pattern uses `SET NX PX` atomically  -  set the key only if it does not exist (`NX`), with a millisecond expiry (`PX`). The expiry ensures the lock is released even if the holder crashes.

```python
import uuid

lock_value = str(uuid.uuid4())
acquired = r.set("lock:resource", lock_value, nx=True, px=5000)  # 5 second TTL

if acquired:
    try:
        # critical section
        pass
    finally:
        # Delete only if we still own the lock  -  atomic check-and-delete via Lua
        lua = "if redis.call('get',KEYS[1]) == ARGV[1] then return redis.call('del',KEYS[1]) else return 0 end"
        r.eval(lua, 1, "lock:resource", lock_value)
```

---

## How It Connects

Redis is the most common broker and result backend for Celery  -  tasks are serialized into Redis lists and results stored as Redis keys.

[[celery|Celery]]

Rate limiting with Redis stores per-key counters with TTLs to implement fixed-window or sliding-window algorithms for API protection.

[[rate-limiting|Rate Limiting]]

---

## Common Misconceptions

Misconception 1: "Redis data persists automatically like a database."
Reality: By default, Redis persistence depends on configuration. RDB snapshots save data periodically; AOF logging appends every write command. Neither is on by default in all configurations, and neither provides transactional durability comparable to a relational database. Redis is best treated as a cache that can survive restarts with some data loss risk, not as a system of record.

Misconception 2: "Creating a new `redis.Redis()` connection per request is fine."
Reality: `redis.Redis()` uses an internal `ConnectionPool` by default  -  the same pool is reused if you share the client instance. Creating a new client per request does not reuse connections effectively and can exhaust file descriptors. The correct pattern is to create one client at application startup and share it as a module-level singleton or dependency.

---

## Why It Matters in Practice

Redis is present in nearly every production Python web stack  -  as a cache, as the Celery broker, as a session store, or as a rate-limit counter. Knowing the redis-py API, understanding TTL semantics, and being aware of the connection pool behavior makes the difference between a reliable integration and one that silently fails under load or leaks connections over time.

---

## Interview Angle

Common question forms:
- "How do you implement a distributed lock with Redis?"
- "What Redis data structures would you use for a rate limiter?"
- "How does the cache-aside pattern work?"

Answer frame:
Distributed lock: `SET key value NX PX ttl` atomically  -  set only if absent, with expiry to survive crashes. Release with a Lua script that checks ownership before deleting. Rate limiter: `INCR key` with `EXPIRE` for fixed-window; sorted set with timestamps for sliding-window. Cache-aside: check Redis first, on miss query the DB, write to Redis with TTL, return value. Connection pool: share one `Redis` client instance across the application  -  it pools connections internally.

---

## Related Notes

- [[celery|Celery]]
- [[rate-limiting|Rate Limiting]]
- [[session-based-auth|Session-Based Authentication]]
- [[async-await|Async/Await]]
