---
title: 42 - Table Partitioning
description: Table partitioning divides a large table into smaller physical pieces while presenting a single logical table to queries, enabling partition pruning and fast data lifecycle management.
tags: [sql, layer-9, partitioning, performance, scaling]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# Table Partitioning

> Table partitioning is how databases handle tables that have grown beyond the point where a single physical file is efficient - it splits the storage while keeping the query interface unified.

---

## Quick Reference

**Core idea:**
- Partitioning divides a single logical table into multiple physical child tables (partitions)
- Queries still use the parent table name - the planner routes to the right partitions automatically
- Range partitioning (by date) is the most common pattern for time-series and event data
- List partitioning separates rows by category or region values
- Hash partitioning distributes rows evenly by hashing a column - useful for uniform distribution
- Partition pruning: the planner skips partitions whose data cannot satisfy the query's WHERE clause

**Tricky points:**
- Indexes must be created on each partition individually (in PostgreSQL declarative partitioning, they can be created on the parent and propagate)
- Foreign keys from other tables pointing at a partitioned table have limitations
- The partition key must be included in any UNIQUE or PRIMARY KEY constraint
- Data must be inserted into the correct partition - rows that do not match any partition are rejected (unless a DEFAULT partition exists)
- Dropping a partition is O(1) and instant; DELETE of the same rows is O(n) and slow

---

## What It Is

Imagine a very large filing cabinet with thousands of folders, all in a single drawer. Finding anything requires searching the entire drawer. Now imagine replacing that one drawer with twelve drawers, one per month. Finding January invoices means opening only the January drawer - the other eleven do not need to be touched. Adding March's invoices goes directly into the March drawer. When you are done with last year, you pull out the entire drawer labeled "last year" and throw it away in one motion, rather than removing every folder one by one. That is partitioning: the same logical set of records, physically organized into separate storage units that can be accessed, maintained, and discarded independently.

A partitioned table in PostgreSQL looks, to the application, exactly like a normal table. You INSERT into it, SELECT from it, and JOIN against it using the same table name. The difference is entirely internal: the database engine routes each row to the appropriate physical partition based on the partition key and the partitioning strategy. The application does not need to know the partitions exist. The benefit appears in query planning and data management operations.

Partition pruning is the core performance benefit. When you query SELECT * FROM events WHERE created_at >= '2026-04-01' AND created_at < '2026-05-01', the query planner knows that this date range can only be satisfied by the April partition. It skips every other partition entirely, producing the equivalent of querying a small table rather than the full multi-year table. This works because the planner evaluates the WHERE clause against the partition boundaries before executing the query. Without partitioning, a query like this requires a sequential scan of the entire table, even if it only needs 1% of the rows and there is no useful index.

Data lifecycle management is the other major benefit. Time-series data accumulates without bound - log tables, event tables, audit tables. Without partitioning, deleting old data requires DELETE statements that acquire row locks, generate write-ahead log volume, and slow down the table. With monthly partitions, dropping last year's data is DROP TABLE events_2025_01 (or equivalently, ALTER TABLE events DETACH PARTITION events_2025_01 followed by DROP TABLE). This is a metadata operation: O(1), instant, no table scan, no row locks on the live partitions.

---

## How It Actually Works

PostgreSQL uses declarative partitioning (introduced in PostgreSQL 10) to define partitioned tables. You declare the parent table with PARTITION BY, then create child partitions that inherit the definition and specify their range, list, or hash bounds.

```sql
-- Create a range-partitioned table for time-series events
CREATE TABLE events (
    id          BIGSERIAL,
    user_id     INT NOT NULL,
    event_type  TEXT NOT NULL,
    payload     JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Create monthly partitions
CREATE TABLE events_2026_04
    PARTITION OF events
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

CREATE TABLE events_2026_05
    PARTITION OF events
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

-- A default partition catches rows that don't match any other partition
CREATE TABLE events_default
    PARTITION OF events
    DEFAULT;

-- Indexes can be created on the parent - they propagate to all partitions
CREATE INDEX ON events (user_id);
CREATE INDEX ON events (created_at);
```

Insert routing is automatic. An INSERT INTO events (..., created_at) VALUES (..., '2026-04-15') lands in events_2026_04. An INSERT with a date of '2026-05-20' lands in events_2026_05. A date with no matching partition lands in events_default if it exists, or raises an error if it does not.

List partitioning is used when the partition key is categorical:

```sql
CREATE TABLE orders (
    id          BIGSERIAL,
    region      TEXT NOT NULL,
    amount      NUMERIC NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL
) PARTITION BY LIST (region);

CREATE TABLE orders_us    PARTITION OF orders FOR VALUES IN ('US');
CREATE TABLE orders_eu    PARTITION OF orders FOR VALUES IN ('DE', 'FR', 'NL', 'UK');
CREATE TABLE orders_apac  PARTITION OF orders FOR VALUES IN ('JP', 'AU', 'SG');
```

Hash partitioning distributes rows based on a hash of the key, producing roughly equal partition sizes even when the key has no natural ordering or grouping:

```sql
CREATE TABLE sessions (
    id         UUID NOT NULL,
    user_id    INT NOT NULL,
    data       JSONB
) PARTITION BY HASH (user_id);

-- 4 hash partitions, modulus=4, remainders 0-3
CREATE TABLE sessions_0 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE sessions_1 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE sessions_2 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE sessions_3 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 3);
```

Partition maintenance for time-series data follows a rolling window pattern. Each month, a new partition is added for the upcoming month, and the oldest partition is detached and dropped:

```sql
-- Add next month's partition (run before the month starts)
CREATE TABLE events_2026_06
    PARTITION OF events
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- Detach and drop old partition (instant, no table lock on live partitions)
ALTER TABLE events DETACH PARTITION events_2025_04;
DROP TABLE events_2025_04;
```

---

## How It Connects

Partitioning works alongside indexes, not instead of them. A GIN index on the payload JSONB column of events is created per-partition and used within that partition's queries. Partition pruning reduces which partitions are scanned; indexes reduce how much of each scanned partition is read. The two mechanisms stack.

Query optimization through EXPLAIN ANALYZE shows exactly which partitions were scanned and which were pruned. Understanding the EXPLAIN output is the primary diagnostic tool for validating that partition pruning is working correctly and that partition boundaries are aligned with actual query patterns.

[[sql-indexes|SQL Indexes]]
[[explain-analyze|EXPLAIN ANALYZE]]
[[query-optimization|Query Optimization]]
[[b-tree-index|B-Tree Index]]

---

## Common Misconceptions

Misconception 1: "Partitioning is a substitute for indexes."
Reality: Partitioning and indexing solve different problems. Partition pruning eliminates entire partitions from consideration when the WHERE clause includes the partition key. Indexes speed up lookups within a partition. A query on a partitioned table that does not filter on the partition key will scan every partition - potentially slower than a single-table index scan on an unpartitioned table. Partitioning does not replace indexes; it complements them.

Misconception 2: "Partitioning automatically makes all queries faster."
Reality: Partition pruning only helps when the query's WHERE clause filters on the partition key with a constant or parameter that the planner can evaluate at plan time. A query like WHERE user_id = 42 on a table partitioned by created_at provides no pruning benefit - the planner must scan all partitions. Partitioning improves performance primarily for queries and operations that align with the partition key.

Misconception 3: "You can add a DEFAULT partition later without consequences."
Reality: Adding a DEFAULT partition to an existing partitioned table that already has data requires a full table scan to route existing rows into the correct new partition. On large tables this is a slow operation. The DEFAULT partition should be planned from the beginning if there is any chance of out-of-range values appearing.

---

## Why It Matters in Practice

Event tables, audit logs, time-series metrics, and activity feeds are the canonical partitioning candidates. These tables grow without bound because rows are never updated or deleted in normal operation - they only accumulate. Without partitioning, a two-year-old events table can reach hundreds of millions of rows, at which point full-table queries become untenable and even index scans slow down due to index bloat and cache pressure. Partitioning by month or week keeps each partition small enough to fit in memory, keeps indexes small and cache-friendly, and enables instant data expiration.

Large SaaS applications also use range or hash partitioning to distribute write load. A single hot table receiving millions of inserts per hour can become a write bottleneck. Hash partitioning across multiple physical partitions (especially if those partitions are placed on different tablespaces on different disks) distributes the write I/O, reducing contention.

---

## What Breaks

**Missing partition causing insert failure.** A cron job creates next month's partition at 11 PM on the last day of each month. The cron job fails silently because of a permissions issue. On the first day of the new month, all inserts with the new month's timestamp fail with "no partition of relation matches the row." The application's insert operations begin throwing errors in production.

```sql
-- Always validate the next partition exists before the month boundary
SELECT COUNT(*) FROM pg_class
WHERE relname = 'events_2026_06'
  AND relkind = 'r';
```

**Query plan regression after adding partitions.** A table starts with 2 partitions and the planner's statistics are calibrated for that. After 24 monthly partitions are created, the planner's decision-making changes. Queries that previously used an index on a small table now trigger partition-scan plans that are suboptimal. pg_stat_user_tables and EXPLAIN output must be reviewed after significant partition count changes.

**Forgetting to propagate constraints.** A new NOT NULL constraint is added to the parent table. Partitions created before that constraint was added do not inherit it. Data inserted directly into old partitions (bypassing the parent) can violate the constraint that the application assumes is enforced.

---

## Interview Angle

Common question forms:
- "What is table partitioning and why would you use it?"
- "What is partition pruning?"
- "How do you drop old data efficiently from a partitioned table?"
- "What are the limitations of partitioning?"

Answer frame:
Start with the concept - physical subdivision of a single logical table. Explain partition pruning as the query performance mechanism: the planner skips partitions whose bounds cannot satisfy the WHERE clause. Give the date/time partitioning use case as the canonical example. Then explain the data lifecycle benefit: DROP TABLE on a partition vs DELETE on rows. Address the partition key restriction for unique constraints and the foreign key limitations. Show that you understand partitioning is a complement to indexes, not a replacement.

---

## Related Notes

- [[sql-indexes|SQL Indexes]]
- [[explain-analyze|EXPLAIN ANALYZE]]
- [[query-optimization|Query Optimization]]
- [[b-tree-index|B-Tree Index]]
- [[covering-indexes|Covering Indexes]]
