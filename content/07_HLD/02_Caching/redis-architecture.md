---
title: 04 - Redis Architecture
description: "How Redis achieves its speed through a single-threaded event loop and I/O multiplexing  -  and what that architecture means for how you use it."
tags: [redis, architecture, caching, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Redis Architecture

> Redis is fast not because it is magic, but because of a specific set of architectural decisions  -  understanding them explains both its performance and its limitations.

---

## Quick Reference

**Core idea:**
- Redis runs a single-threaded event loop that handles all client commands sequentially
- Operations are atomic by design  -  the single thread means no concurrent modification
- All data lives in memory; persistence is optional and asynchronous by default
- I/O multiplexing (epoll/kqueue) allows one thread to handle thousands of concurrent connections
- Redis 6.0+ uses I/O threads for network reads/writes but keeps command execution single-threaded

**Tricky points:**
- "Single-threaded" means command execution is serial  -  a slow command (O(n) KEYS scan) blocks all others
- Redis is not limited by CPU for most workloads  -  it is limited by network bandwidth and memory
- The event loop does not parallelize: two simultaneous writes are serialized, not interleaved
- MULTI/EXEC transactions are atomic at the command level but do not support rollback
- Redis is not a durable store by default  -  if the server crashes without persistence, all data is lost

---

## What It Is

Imagine a very fast, very organized cashier at a grocery store. There is only one cashier  -  but this cashier moves so quickly that the line moves faster than a multi-cashier system with coordination overhead. Each customer presents their groceries, the cashier processes them instantly, and the next customer steps up. Because only one customer is served at a time, there is never a dispute about who owns a particular item or whose total is being rung up. The speed comes from the simplicity of having exactly one actor doing the work.

Redis (Remote Dictionary Server) is an in-memory data store built on this philosophy. It runs a single event loop in a single thread. Every client command  -  a GET, a SET, an LPUSH, a ZADD  -  executes sequentially in this loop. No command is executed concurrently with another. This sounds like a limitation, but it is the source of Redis's most important property: every operation is atomic. There are no races, no locks, no transactions needed for most operations. "Increment this counter" is atomic. "Add this element to a set" is atomic. "Get and set this key" can be made atomic with Lua scripts.

The speed comes from several factors. First, all data is in RAM. A memory access takes roughly 100 nanoseconds; a disk access takes roughly 100 microseconds to 10 milliseconds depending on the storage type. Serving data from memory is orders of magnitude faster than from disk. Second, the data structures Redis implements (hash tables, skip lists, ziplist-compressed structures for small collections) are highly optimized for in-memory operation. Third, the event loop eliminates context-switching overhead: there are no thread context switches, no lock acquisitions, no scheduler interventions during command processing.

I/O multiplexing via epoll (Linux), kqueue (macOS), or IOCP (Windows) allows Redis's single thread to manage thousands of client connections simultaneously without blocking. When a client sends a command, the kernel notifies Redis via the multiplexer that data is available to read. Redis reads the command, executes it, writes the response, and moves to the next ready client. Clients waiting for I/O do not consume CPU  -  they exist only as file descriptors in the kernel's event queue. This is the same architecture as Nginx and Node.js.

---

## How It Actually Works

Redis's memory management is built around a global hash table (the keyspace). Every key maps to a value object. The value object has a type (string, list, set, hash, sorted set, etc.) and an encoding that can vary depending on the size of the value. Small hashes are stored as a ziplist (a compact linear byte array) for memory efficiency. Large hashes use a proper hash table. Redis automatically upgrades the encoding when thresholds are exceeded. This is transparent to the user but important for memory planning.

The event loop processes commands in phases. The multiplexer notifies Redis of ready file descriptors. Redis iterates over ready descriptors, reads available data into a buffer, parses complete commands from the buffer, executes each command against the in-memory keyspace, and writes responses. A complete cycle of this loop runs typically thousands of times per second. The single-threaded nature means that if one command takes a long time (for example, `KEYS *` on a keyspace with 10 million keys, which is O(N)), all other clients block for the duration of that command.

Redis 6.0 introduced multi-threaded I/O for network operations: separate threads handle reading data from sockets and writing responses, while command execution remains single-threaded. This allows Redis to saturate network bandwidth on multi-core machines, which was a previous bottleneck. The command execution serialization guarantee is preserved.

```python
import redis
import time

r = redis.Redis(host='localhost', port=6379, decode_responses=True)

# All operations are atomic at the single-command level
r.set('counter', 0)
r.incr('counter')        # atomic: increment by 1
r.incrby('counter', 5)   # atomic: increment by 5
print(r.get('counter'))  # "6"

# MULTI/EXEC pipeline: all commands queued, then executed atomically as a block
# No command from another client can interleave within the EXEC block
with r.pipeline() as pipe:
    pipe.multi()
    pipe.hset('user:1', 'balance', 100)
    pipe.hset('user:2', 'balance', 50)
    pipe.execute()  # both writes happen atomically

# Lua script: arbitrary logic executed atomically
# This is how Redis implements complex atomic operations
lua_script = """
local current = redis.call('GET', KEYS[1])
if tonumber(current) >= tonumber(ARGV[1]) then
    redis.call('DECRBY', KEYS[1], ARGV[1])
    return 1  -- success
end
return 0  -- insufficient balance
"""
deduct_balance = r.register_script(lua_script)
result = deduct_balance(keys=['user:balance:42'], args=[10])
print(f"Deduction {'succeeded' if result else 'failed (insufficient balance)'}")
```

The single-threaded execution model has a direct implication for Lua scripts: a Lua script executed in Redis runs to completion atomically, with no other commands executing concurrently. This makes Lua scripts the mechanism for implementing custom atomic operations that require more than one Redis command  -  such as "check a condition and, if true, perform an action." This is far more efficient than optimistic locking in the client.

Pipeline pipelining sends multiple commands to Redis without waiting for each response, then collects all responses at the end. This reduces round-trip overhead from N round-trips to 1. Pipelining does not guarantee atomicity  -  other clients can interleave commands between the pipelined commands. For atomic multi-command operations, use MULTI/EXEC or a Lua script.

---

## Visualizer

<iframe src="/static/visualizers/redis-architecture.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="Redis Architecture Visualizer"></iframe>

---

## How It Connects

Redis's single-threaded architecture makes it an ideal distributed lock and counter store. These use cases exploit the atomicity of individual commands.

[[redis-data-structures|Redis Data Structures]]

The default Redis configuration stores nothing to disk  -  if the server restarts, all data is lost. Persistence modes (RDB and AOF) change this behavior with different tradeoffs.

[[redis-persistence|Redis Persistence]]

A single Redis instance has a finite capacity. When data exceeds what one machine can hold, Redis Cluster shards the data across multiple primaries.

[[redis-clustering|Redis Clustering]]

---

## Common Misconceptions

Misconception 1: "Redis is multi-threaded in version 6+, so the old rules don't apply."
Reality: Redis 6+ uses I/O threads for network reads/writes but command execution remains single-threaded. The atomicity guarantees are unchanged. The practical implication is that Redis 6+ can saturate multi-gigabit NICs that were a bottleneck on single-threaded I/O, but the single-execution-thread model for command processing is preserved.

Misconception 2: "Redis MULTI/EXEC transactions support rollback."
Reality: Redis MULTI/EXEC transactions execute all queued commands atomically (no interleaving from other clients), but they do not support rollback. If one command in the EXEC block fails (e.g., calling INCR on a string value), Redis continues executing the remaining commands. There is no way to roll back commands that already succeeded within the block. For true transactional semantics, use Lua scripts.

Misconception 3: "Redis is a database and can replace my relational database."
Reality: Redis is an in-memory data store, not a general-purpose database. It lacks SQL query capabilities, foreign key constraints, complex joins, and the durability guarantees of a relational database (by default). It is the right tool for caching, session storage, rate limiting, leaderboards, and real-time pub/sub  -  not for relational data with complex query patterns.

---

## Why It Matters in Practice

Understanding Redis's architecture prevents entire classes of bugs. The single-threaded model means that a single slow command (KEYS *, SMEMBERS on a huge set, SORT on a large list) blocks every other client for the duration. In production, this causes latency spikes that appear unrelated to the slow command because all clients experience them. Knowing this, you use SCAN instead of KEYS, cap collection sizes, and avoid O(N) operations on large collections.

The in-memory-first model means Redis is not safe as the only store for critical data unless persistence is configured correctly. Many engineers assume Redis persists data durably. The default configuration does not. Designing a system that relies on Redis for non-reproducible state  -  order IDs, payment records  -  without understanding persistence modes is a reliability risk.

---

## Interview Angle

Common question forms:
- "How does Redis achieve such high throughput with a single thread?"
- "What is I/O multiplexing and how does Redis use it?"
- "What are the limitations of Redis's single-threaded model?"

Answer frame:
Explain that Redis's speed comes from memory access (not disk), efficient data structures, and eliminating locking overhead via single-threaded execution. Explain I/O multiplexing: one thread can manage thousands of connections by using epoll to receive notifications when sockets are ready. Describe the atomicity guarantee as a consequence of single-threaded execution. Explain the limitation: O(N) operations block all clients. Mention Lua scripts as the mechanism for custom atomic operations.

---

## Related Notes

- [[redis-data-structures|Redis Data Structures]]
- [[redis-persistence|Redis Persistence]]
- [[redis-clustering|Redis Clustering]]
- [[caching-basics|Caching Basics]]
- [[redis-python|Redis with Python]]
