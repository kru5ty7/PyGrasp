---
title: Covering Indexes
description: A covering index contains every column a query needs, allowing the database to answer the query entirely from the index without touching the actual table rows.
tags: [sql, layer-9, indexes, covering, performance]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# Covering Indexes

> A covering index eliminates the most expensive part of an indexed lookup — the trip back to the heap row — by storing all the columns a query needs directly in the index, enabling an "index-only scan" that can be orders of magnitude faster than a regular index scan.

---

## Quick Reference

**Core idea:**
- A covering index contains all columns referenced by a query (in WHERE, SELECT, JOIN, ORDER BY)
- The database can satisfy the query from the index alone — no heap access required
- In PostgreSQL this is called an "index-only scan"; in MySQL it is called a "covering index scan"
- PostgreSQL 11+ supports `INCLUDE` columns: extra columns stored in leaf nodes but not part of the sort key
- An `INCLUDE` column cannot be used in WHERE, ORDER BY, or JOIN — it exists only to avoid a heap fetch

**Tricky points:**
- Index-only scans in PostgreSQL still require checking the visibility map; if the table is not vacuumed regularly, the scan degrades to a regular index scan
- Columns in the `INCLUDE` list do not affect the sort order of the index and cannot narrow the search — they are payload, not key
- Including a wide column (e.g., TEXT) in an index bloats the index significantly — the savings from avoiding a heap fetch must outweigh the increased index size
- EXPLAIN output shows "Index Only Scan" only if the visibility map confirms all pages are all-visible; otherwise it shows "Index Scan" even with a covering index

---

## What It Is

Imagine a library catalogue that not only tells you which shelf a book is on but also prints the book's abstract right on the catalogue card. For most research questions — "what is this book about?" — you never need to leave the catalogue desk. You get your answer directly from the card. Only when you need the full text do you walk to the shelf. A covering index is that enriched catalogue card: it stores enough information to answer the query completely, sparing the database the trip to the actual data pages.

In a standard indexed lookup, the database performs two reads. First it traverses the B-tree index to find the matching index entries. Then — for every matching entry — it follows the row pointer back to the heap (the actual table storage) to fetch the columns that are not in the index. That second read is a random I/O: the rows matching an index scan are scattered across the table, so each heap fetch may hit a different disk page. On a busy table with millions of rows, this random I/O is often the dominant cost of the query.

A covering index collapses these two reads into one. Because every column the query needs is already in the index, the engine reads the index, collects the data, and returns — no heap visits at all. The I/O pattern changes from random (one page fetch per row) to sequential (scanning the index's sorted leaf pages from start to end of the matching range). This difference in I/O pattern is why covering indexes sometimes produce dramatic speedups even when the query already uses an index.

---

## How It Actually Works

Prior to PostgreSQL 11, the only way to create a covering index was to include all needed columns as part of the index key. This worked but had a side effect: every column added to the key changed the sort order of the index, potentially making it unusable for other query patterns or widening the B-tree search space unnecessarily.

PostgreSQL 11 introduced the `INCLUDE` clause, which adds columns to the leaf nodes of the index without making them part of the sort key. This means the index can be tuned for its primary WHERE/ORDER BY purpose while also carrying extra payload columns to prevent heap fetches.

```sql
-- Without INCLUDE: the full index key includes order_total
-- This works but order_total affects the sort order (usually unwanted)
CREATE INDEX idx_orders_user_date_v1 ON orders(user_id, created_at, order_total);

-- With INCLUDE: user_id and created_at form the key; order_total is payload only
CREATE INDEX idx_orders_user_date ON orders(user_id, created_at) INCLUDE (order_total);

-- This query is now served by index-only scan: no heap access
SELECT order_total FROM orders
WHERE user_id = 42 AND created_at >= '2024-01-01';
```

To verify that an index-only scan is happening, use EXPLAIN ANALYZE. The plan node must show "Index Only Scan" and the "Heap Fetches" line must be zero (or low). If "Heap Fetches" is high, the visibility map has unvacuumed pages — the engine falls back to heap access for those pages.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_total FROM orders
WHERE user_id = 42 AND created_at >= '2024-01-01';

-- Good output:
-- Index Only Scan using idx_orders_user_date on orders
--   Index Cond: ((user_id = 42) AND (created_at >= '2024-01-01'))
--   Heap Fetches: 0
--   Buffers: shared hit=12

-- Bad output (visibility map stale):
-- Index Only Scan using idx_orders_user_date on orders
--   Heap Fetches: 4821   <-- falling back to heap for unvacuumed pages
```

The visibility map is a per-table bitmap maintained by PostgreSQL. Each bit indicates whether all tuples on a given heap page are visible to all transactions (i.e., no dead tuples, no in-progress transactions affecting visibility). Only pages marked "all-visible" can skip heap access during an index-only scan. VACUUM sets these bits; autovacuum sets them on its schedule. A table with autovacuum disabled or severely delayed will have few all-visible pages, and index-only scans will silently degrade.

```sql
-- Check visibility map coverage for a table
SELECT relname,
       pg_size_pretty(pg_relation_size(oid)) AS heap_size,
       pg_size_pretty(pg_relation_size(oid, 'vm')) AS vm_size,
       n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'orders';

-- Run VACUUM to update the visibility map
VACUUM orders;
```

---

## How It Connects

Understanding what a covering index is requires understanding what it avoids: the heap fetch that follows a normal index scan. The B-tree leaf structure stores TIDs (row pointers) precisely because the index cannot normally contain all table columns — covering indexes change this assumption for specific queries.

[[b-tree-index|B-Tree Index Internals]]

EXPLAIN ANALYZE is the primary diagnostic tool for confirming that an index-only scan is active and that heap fetches are near zero. The BUFFERS option shows actual I/O, making the heap-access reduction quantifiable.

[[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]

---

## Common Misconceptions

Misconception 1: "If my query uses an index, it is already as fast as possible."
Reality: A regular index scan still performs one heap fetch per matching row. On a query returning thousands of rows, these random heap accesses can dominate the execution time. A covering index eliminates the heap fetches entirely, which is why "Index Only Scan" can be dramatically faster than "Index Scan" even when both use the same index key columns.

Misconception 2: "The INCLUDE columns in a covering index can be used in WHERE clauses."
Reality: INCLUDE columns are stored only in the leaf nodes and are not part of the B-tree's sort key. The planner cannot use them to narrow the search range during tree traversal. They exist solely as payload to avoid a heap fetch once the qualifying rows have already been identified by the key columns. Attempting to filter on an INCLUDE column will cause the planner to either ignore the index or apply the filter as a residual after the index scan.

Misconception 3: "An index-only scan is always faster than a regular index scan."
Reality: If the visibility map is stale (many unvacuumed pages), PostgreSQL falls back to heap access for those pages — potentially performing more work than a plain index scan because it checks the visibility map first and then fetches from the heap anyway. An index-only scan is a reliable optimization only on tables with active autovacuum or explicit VACUUM maintenance.

---

## Why It Matters in Practice

Covering indexes are the highest-efficiency index optimization available for read-heavy queries. A dashboard query that runs thousands of times per minute, fetching a handful of columns per user per time period, can transition from thousands of random I/O operations to a tight sequential index scan — the difference between saturating a disk and barely touching it.

The `INCLUDE` clause in PostgreSQL 11+ made covering indexes practical to design without compromising the index's primary sort-key purpose. Before this feature, adding a wide column to the index key would change the sort order and potentially break other query plans that relied on the same index. With INCLUDE, the optimization is targeted: the index key remains what the planner needs for navigation, and the included columns are purely a performance optimization for specific queries.

---

## What Breaks

**Covering index degraded by missing VACUUM.** A table with high UPDATE activity and autovacuum lagging accumulates many non-all-visible pages. The index-only scan falls back to heap access for each of those pages, eliminating the performance benefit. The EXPLAIN output shows "Heap Fetches" in the thousands despite an index-only scan node.

```sql
-- Diagnose: high heap fetches despite index-only scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT amount FROM payments WHERE account_id = 500 AND paid_at >= '2024-01-01';
-- If Heap Fetches >> 0, run:
VACUUM (ANALYZE) payments;
-- Re-run EXPLAIN to confirm Heap Fetches drops to near 0
```

**Wide INCLUDE column bloats the index beyond usefulness.** A developer adds a `description TEXT` column to a covering index to avoid a join. The description values average 2 KB each. The index becomes larger than the table itself, consuming more buffer pool space and slowing the very scans it was meant to accelerate.

```sql
-- Problematic: TEXT column included in index
CREATE INDEX idx_products_sku ON products(sku) INCLUDE (description);

-- Better: if description is needed, join to a narrow table or cache it in the application
-- The covering index optimization is only cost-effective for narrow columns (IDs, timestamps, numbers)
```

**INCLUDE column confused with key column in query.** A developer tries to filter on an INCLUDE column expecting index-narrowing behavior, but the planner ignores the index for that predicate and applies a sequential scan.

```sql
CREATE INDEX idx_orders_user ON orders(user_id) INCLUDE (status);

-- status is an INCLUDE column — the planner cannot use it to narrow the index scan
-- This query may still use the index for user_id but filters status from heap rows
SELECT * FROM orders WHERE user_id = 42 AND status = 'pending';

-- If status filtering is frequent, add it to the key, not INCLUDE
CREATE INDEX idx_orders_user_status ON orders(user_id, status);
```

---

## Interview Angle

Common question forms:
- "What is a covering index and when would you use one?"
- "What is the difference between putting a column in the index key vs using INCLUDE?"
- "What is an index-only scan and what can cause it to degrade?"

Answer frame:
Define the heap fetch problem: a regular index scan reads the index then makes a random I/O back to the heap for each matching row. A covering index stores all needed columns in the index, eliminating the heap fetch entirely — this is an index-only scan. Explain INCLUDE: key columns determine the B-tree sort order and support WHERE/ORDER BY filtering; INCLUDE columns are leaf-level payload that cannot be filtered on but prevent heap access for SELECT. Address degradation: the visibility map must mark pages as all-visible for index-only scans to skip the heap; stale vacuuming causes fallback heap fetches, visible in "Heap Fetches" in EXPLAIN ANALYZE output.

---

## Related Notes

- [[sql-indexes|SQL Indexes]]
- [[b-tree-index|B-Tree Index Internals]]
- [[composite-indexes|Composite Indexes]]
- [[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]
- [[query-optimization|Query Optimization]]
