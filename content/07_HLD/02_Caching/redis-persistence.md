---
title: 06 - Redis Persistence
description: "RDB snapshots vs AOF append-only file  -  the two persistence mechanisms Redis offers, their durability guarantees, and when to use each."
tags: [redis, persistence, durability, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Redis Persistence

> Redis is an in-memory store  -  without persistence configured, a crash loses all data. Understanding RDB and AOF is what separates a Redis deployment that is a cache from one that is a durable data store.

---

## Quick Reference

**Core idea:**
- RDB (Redis Database): periodic point-in-time snapshots of the entire dataset written to disk
- AOF (Append-Only File): every write command is logged to disk before or after execution
- RDB is compact and fast to restore, but can lose up to the last snapshot interval of data
- AOF provides finer-grained durability (up to 1 second of data loss with `fsync every second`)
- AOF rewrite compacts the log file by replacing the command history with the current minimal set of SET commands

**Tricky points:**
- The default Redis config has RDB enabled but with large snapshot intervals  -  not suitable for durability
- `appendfsync always` (fsync after every write) gives strong durability but reduces throughput dramatically
- AOF file grows until rewrite  -  a high-write workload without AOF rewrite configured can fill disks
- RDB snapshots use fork()  -  on a large dataset, fork() itself can pause Redis for milliseconds to seconds
- Using both RDB + AOF (recommended for data stores) combines fast restore (RDB) with recent data recovery (AOF)

---

## What It Is

Picture two methods for backing up your work on a document. The first method: every hour, save a complete copy of the document as a ZIP file. If your computer crashes at 2:55 PM and your last ZIP was at 2:00 PM, you lose 55 minutes of work. Restore is fast  -  decompress the ZIP. This is RDB.

The second method: keep a running log of every keystroke and edit you make, in order. If your computer crashes, replay the log from the beginning to reconstruct exactly the document state at the moment of crash. Nothing is lost, but restoring takes longer (you replay every edit). This is AOF.

Redis is an in-memory database. Its speed comes entirely from the fact that all data lives in RAM. The downside is that RAM is volatile: when the power goes out or the process crashes, everything in RAM is gone. Without persistence, Redis is a pure cache  -  data that can be regenerated from another source (a database, an upstream API). With persistence, Redis can serve as a durable store for data that matters.

RDB persistence works by periodically forking the Redis process and having the forked child write a snapshot of the entire dataset to a `.rdb` file on disk. The parent continues serving requests normally. The fork operation uses copy-on-write semantics: the child gets a read-only view of memory at the moment of the fork. Pages modified by the parent after the fork are copied, leaving the child's snapshot unchanged. When the child finishes writing, the old `.rdb` file is replaced atomically. On startup, Redis loads the `.rdb` file to restore the dataset.

AOF persistence logs every write command in a text format to an append-only file. When a write is received, Redis writes the command to the AOF buffer. The `appendfsync` configuration determines when the buffer is flushed to disk: `always` (flush after every command  -  maximum durability, minimum throughput), `everysec` (flush once per second  -  at most 1 second of data loss, good throughput), or `no` (let the OS decide  -  fast, but up to several seconds of potential loss). On restart, Redis replays the AOF file from start to finish to reconstruct the dataset.

---

## How It Actually Works

The RDB fork operation is Redis's most significant latency concern under persistence. On Linux, `fork()` is cheap (milliseconds) for small datasets but can take hundreds of milliseconds or more for datasets of tens of gigabytes. During this brief period, the Redis parent process is blocked. In production, this appears as a latency spike visible in the P99 latency metrics. Mitigation options include: using a replica to perform saves instead of the primary, reducing RDB save frequency, or using a system with transparent huge pages disabled (which makes copy-on-write cheaper).

AOF file growth is the most common operational surprise. In a high-write workload, the AOF file records every command. After a key is SET 10,000 times, the AOF contains 10,000 SET commands but only the last one matters. AOF rewrite compacts the file by re-examining the current in-memory dataset and writing the minimum set of commands needed to reproduce it  -  one SET per key. This is triggered automatically when the AOF grows beyond a configured multiple of its last size, or manually via `BGREWRITEAOF`. Rewrite also uses a background process and copy-on-write, but it rebuilds the file rather than just appending.

Using both RDB and AOF together is the recommended approach for data stores. On restart, Redis prefers the AOF (more recent data) if available. If the AOF is corrupted, Redis falls back to the RDB. The RDB provides a fast-loading baseline, while the AOF captures everything since the last snapshot.

```python
# Checking persistence configuration programmatically
import redis

r = redis.Redis()
info = r.info('persistence')

print(f"RDB enabled: {info['rdb_changes_since_last_save']} changes since last save")
print(f"Last save: {info['rdb_last_save_time']}")
print(f"AOF enabled: {info['aof_enabled']}")
print(f"AOF filename: {info.get('aof_filename', 'N/A')}")
print(f"AOF fsync: {info.get('aof_current_rewrite_time_sec', 'N/A')}")

# Trigger a manual background save
r.bgsave()   # RDB snapshot in background
r.bgrewriteaof()  # AOF rewrite in background
```

Redis also offers a "no persistence" mode for pure caches  -  `save ""` disables RDB, `appendonly no` disables AOF. In this configuration, Redis is the fastest it can be: no forking, no disk writes, no file management. This is appropriate when Redis is used purely as a cache in front of a durable database.

For Redis as a session store or distributed lock store, `appendfsync everysec` provides a good durability/performance balance. For Redis as a primary data store (replacing a database), `appendfsync always` is safer but slower. Understanding your tolerance for data loss determines the right configuration.

---

## How It Connects

Persistence configuration directly affects whether Redis can be used as a primary store or only as a cache layer. The caching strategy  -  whether Redis is a write-through cache or a cache-aside cache  -  determines how much you depend on Redis's own durability.

[[caching-strategies|Caching Strategies]]

In a Redis Cluster deployment, each primary shard has its own persistence configuration. Replicas can serve reads and provide durability, but each primary's persistence is independent.

[[redis-clustering|Redis Clustering]]

The ACID vs BASE distinction is directly relevant: Redis with AOF `everysec` is BASE (at most 1 second of data loss), not ACID (no transaction rollback). Applications using Redis as a primary store must design accordingly.

[[acid-vs-base|ACID vs BASE]]

---

## Common Misconceptions

Misconception 1: "Redis automatically persists my data  -  I don't need to configure anything."
Reality: The default Redis configuration has `save 3600 1` (save if at least 1 key changed in 3600 seconds), `save 300 100`, and `save 60 10000`. AOF is disabled by default. This means data modified since the last automatic RDB snapshot is lost on crash. For any data that matters, persistence must be explicitly configured.

Misconception 2: "AOF with appendfsync always is the safest option and I should always use it."
Reality: `appendfsync always` guarantees that every write is fsynced to disk before Redis acknowledges it. This provides excellent durability but can reduce throughput by a factor of 10 - 50x for write-heavy workloads because every write waits for a disk fsync. For most use cases, `everysec` (at most 1 second of loss) provides an excellent durability/throughput balance.

Misconception 3: "RDB snapshots are instantaneous and do not affect Redis performance."
Reality: The `fork()` call for RDB snapshots can take milliseconds to seconds for large datasets. On systems with transparent huge pages enabled, copy-on-write is more expensive. During a fork, the Redis parent is briefly blocked. In production, monitor for latency spikes that correlate with scheduled RDB saves and consider whether the snapshot interval is appropriate for your memory size and latency requirements.

---

## Why It Matters in Practice

The most common Redis persistence mistake in production is treating Redis as a durable store without configuring persistence. A server restart  -  planned or unplanned  -  during a deployment, hardware failure, or OOM kill  -  empties the cache entirely. If the application depends on data in Redis that cannot be regenerated (user sessions, distributed locks, counters), this causes production incidents.

The second most common mistake is using Redis as a pure cache (no persistence needed) but leaving default RDB saves enabled, which cause unnecessary fork-related latency spikes. For a pure cache, disabling all persistence removes this overhead entirely and makes Redis marginally faster.

---

## Interview Angle

Common question forms:
- "What are the persistence options in Redis and when would you use each?"
- "How much data can you lose in a Redis crash with default settings?"
- "What is AOF rewrite and why is it needed?"

Answer frame:
Describe RDB: periodic snapshots, fast restore, data loss up to snapshot interval. Describe AOF: command log, durability controlled by fsync policy (always / everysec / no). Explain when to use each: RDB for pure cache or fast restore priority; AOF for durability priority; both for production data stores. Explain AOF rewrite: the file grows without bound without it. Address the fork() latency concern for large datasets.

---

## Related Notes

- [[redis-architecture|Redis Architecture]]
- [[redis-clustering|Redis Clustering]]
- [[caching-strategies|Caching Strategies]]
- [[acid-vs-base|ACID vs BASE]]
