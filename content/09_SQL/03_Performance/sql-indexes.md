---
title: 25 - SQL Indexes
description: An index is a separate data structure the database maintains to speed up row lookups, trading write overhead for read performance.
tags: [sql, layer-9, indexes, performance]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# SQL Indexes

> An index is a purpose-built lookup structure that lets the database skip a full table scan and jump directly to matching rows - understanding when to create one (and when not to) separates fast queries from slow ones.

---

## Quick Reference

**Core idea:**
- Without an index, the database reads every row in the table (sequential scan)
- An index stores a sorted, compact copy of one or more columns plus a pointer to the full row
- B-tree is the default index type - handles equality, range, and ORDER BY
- Hash indexes handle equality only and are rarely preferred over B-tree
- GIN indexes handle arrays, JSONB keys, and full-text search
- Every write (INSERT, UPDATE, DELETE) must update all applicable indexes

**Tricky points:**
- Low-cardinality columns (e.g., a boolean) make poor index candidates - the planner may ignore the index entirely
- Indexes consume disk space and memory (they are cached in the buffer pool)
- An index on a column wrapped in a function (e.g., `LOWER(email)`) will not be used by `WHERE email = 'foo'` - the function defeats the index
- Index selectivity determines usefulness: an index on `status` with two possible values is far less useful than one on `user_id` with millions of distinct values

---

## What It Is

Think of a book's back-of-book index. When you want to find every page that mentions "transactions," you do not read the entire book from page one. Instead you flip to the index, find the entry for "transactions," and get a list of page numbers. The database index works identically: it is a separate, sorted structure that maps column values to row locations, so the engine can go directly to the right pages on disk.

Without an index, the database performs a sequential scan - it reads every block of the table from start to finish to find rows that match a WHERE clause. For a table with ten rows this is irrelevant. For a table with ten million rows, a sequential scan may read hundreds of megabytes of data from disk just to return three rows.

When an index exists on the column being filtered, the database instead traverses the index structure (almost always a B-tree), arrives at the matching entries in O(log n) steps, and follows the row pointers back to the actual table storage (called the heap). The number of disk pages touched drops from millions to a handful.

Indexes are not free. Every INSERT adds a new entry to every index on that table. Every DELETE removes entries. Every UPDATE that modifies an indexed column must remove the old entry and insert a new one. A table with ten indexes on it writes to eleven places for every row insertion. For write-heavy workloads this overhead is measurable and sometimes dominates.

---

## How It Actually Works

The database maintains each index as a separate on-disk structure that is kept in sync with the table. In PostgreSQL and MySQL, the default index type is the B-tree. The B-tree stores index entries in sorted order across a tree of pages. Internal nodes contain separator keys that guide traversal; leaf nodes contain the actual indexed values plus a pointer (called a TID in PostgreSQL, or a primary key reference in InnoDB) to the corresponding heap row.

```sql
-- Create a basic B-tree index on a single column
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- This query can now use the index instead of scanning all rows
SELECT * FROM orders WHERE user_id = 42;

-- Create a Hash index (equality only, no range support)
CREATE INDEX idx_sessions_token ON sessions USING HASH (token);

-- GIN index for JSONB and array containment queries
CREATE INDEX idx_products_tags ON products USING GIN (tags);
-- Used by: WHERE tags @> ARRAY['electronics']

-- GIN index for full-text search
CREATE INDEX idx_articles_fts ON articles USING GIN (to_tsvector('english', body));
```

Index selectivity is the ratio of distinct values to total rows. An index on a column with two distinct values (say `is_active` with TRUE and FALSE) would still need to read roughly half the table after using the index - the planner often decides a sequential scan is cheaper because it avoids the overhead of index traversal and random I/O. An index on `user_id` in an orders table, where nearly every value is unique, is highly selective and extremely valuable.

```sql
-- Low selectivity - index may be ignored
CREATE INDEX idx_users_is_active ON users(is_active);  -- only 2 values

-- High selectivity - index will be used consistently
CREATE INDEX idx_users_email ON users(email);  -- nearly all distinct

-- Check index usage and scans in PostgreSQL
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

---

## How It Connects

The B-tree index is the default implementation behind almost every `CREATE INDEX` statement, and understanding its internal structure explains why certain query patterns (range queries, ORDER BY) benefit from indexes while others (suffix LIKE) do not.

[[b-tree-index|B-Tree Index Internals]]

Composite indexes extend the single-column case by covering multiple columns in a defined order. The left-prefix rule governs which queries can use the index, and getting the column order wrong is a common source of missed optimizations.

[[composite-indexes|Composite Indexes]]

---

## Common Misconceptions

Misconception 1: "Adding an index always makes queries faster."
Reality: Indexes impose write overhead and consume memory. A low-selectivity index (like a boolean column) may be ignored by the planner entirely. An index on a rarely-queried column wastes space and slows every INSERT/UPDATE/DELETE on the table without delivering measurable read benefits.

Misconception 2: "The database will automatically use an index if one exists."
Reality: The query planner chooses whether to use an index based on cost estimates derived from table statistics. If the planner estimates that a sequential scan is cheaper (e.g., the query returns most of the table, or table statistics are stale), it will skip the index entirely. Running `ANALYZE` to refresh statistics can change the plan.

Misconception 3: "Indexes only help with WHERE clauses."
Reality: Indexes also accelerate ORDER BY (avoiding a sort step), JOIN conditions (the planner can use an index on the join column), GROUP BY (in some cases), and DISTINCT. A covering index can eliminate table access entirely for certain queries.

---

## Why It Matters in Practice

The presence or absence of the right index is the single most common explanation for the difference between a query that returns in 2 milliseconds and one that runs for 45 seconds. Application developers who treat indexing as a database administrator concern rather than a development concern will ship slow code. Understanding index selectivity, write overhead, and how the planner makes its decision turns indexing from a mystery into a deliberate design choice.

Production databases accumulate table growth over time. A query that was fast at launch with 10,000 rows may become unacceptable at 10 million rows if the access pattern relies on a sequential scan. Indexes must be planned alongside the schema and revisited as data volume grows. Monitoring index usage statistics and identifying unused indexes is as important as adding new ones.

---

## What Breaks

**Sequential scan on a large table due to missing index.** A reporting query filters orders by `customer_id` on a table with 50 million rows and no index on that column. The query takes over a minute. Adding `CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id)` (CONCURRENTLY avoids locking writes) drops it to milliseconds.

```sql
-- Before index: sequential scan, 60+ seconds
SELECT * FROM orders WHERE customer_id = 9001;

-- After:
CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);
-- Same query: index scan, <5ms
```

**Index defeated by a function in WHERE.** A developer writes a case-insensitive search by wrapping the column in `LOWER()`. The index on `email` is not used because the planner cannot apply it to `LOWER(email)`.

```sql
-- Does NOT use the index on email
SELECT * FROM users WHERE LOWER(email) = 'alice@example.com';

-- Fix: create a functional index
CREATE INDEX idx_users_email_lower ON users(LOWER(email));

-- Now this query uses the index
SELECT * FROM users WHERE LOWER(email) = 'alice@example.com';
```

**Index bloat after heavy updates.** In PostgreSQL, UPDATE creates a new row version and marks the old one dead - both the table and the index retain dead entries until VACUUM runs. A table that is updated millions of times per day without regular autovacuum can accumulate massive index bloat, slowing both reads and writes.

---

## Interview Angle

Common question forms:
- "What is a database index and how does it work?"
- "When would you not add an index?"
- "What is index selectivity?"

Answer frame:
Start with the sequential scan problem - without an index the database reads every row. Explain that an index is a sorted auxiliary structure (typically a B-tree) that lets the engine jump to matching rows in O(log n) steps. Mention the write overhead tradeoff. Demonstrate selectivity judgment: a boolean column has low selectivity and the planner may reject the index; a unique identifier has high selectivity and delivers maximum benefit. Close with the write overhead point: every index slows writes, so indexes must be justified by their read benefit.

---

## Related Notes

- [[b-tree-index|B-Tree Index Internals]]
- [[composite-indexes|Composite Indexes]]
- [[covering-indexes|Covering Indexes]]
- [[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]
- [[query-optimization|Query Optimization]]
