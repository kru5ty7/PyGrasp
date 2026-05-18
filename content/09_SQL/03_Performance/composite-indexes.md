---
title: 27 - Composite Indexes
description: A composite index covers multiple columns in a defined order, and that order determines exactly which query patterns the index can serve — getting it wrong means the index is silently ignored.
tags: [sql, layer-9, indexes, composite, performance]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Composite Indexes

> A composite index is a single B-tree built on multiple columns in a specific order — the left-prefix rule governs which queries can use it, and choosing the wrong column order is one of the most common and invisible performance mistakes in database design.

---

## Quick Reference

**Core idea:**
- A composite index on `(a, b, c)` sorts rows first by `a`, then by `b` within each `a` value, then by `c` within each `(a, b)` pair
- The left-prefix rule: the index is usable for queries on `(a)`, `(a, b)`, or `(a, b, c)` — but NOT for `(b)` or `(c)` alone, or `(b, c)` without `a`
- Column order is a design decision, not a detail — it must match the actual query patterns
- A single composite index can replace multiple single-column indexes for multi-column filters
- Index on `(user_id, created_at)` serves per-user time-range queries efficiently with one structure

**Tricky points:**
- If `a` is in the WHERE clause but as a range (`a > 5`), the index can still filter on `a` but cannot use the sorted `b` column to skip rows — the range breaks the chain
- Adding indexes on every column combination is not the answer — each index slows writes and consumes memory
- The most selective column and the most commonly queried leading column are often not the same — a deliberate tradeoff must be made
- Order in a composite index is independent of ASC/DESC — that is a separate concern handled by the index sort direction

---

## What It Is

Think of a phone book. It sorts entries first by last name, then by first name within each last name. This makes looking up "Johnson, Alice" trivial: navigate to the J section, then within it find Alice. But if you want to find everyone named "Alice" without knowing their last name, the phone book is useless — you must read every page. The phone book is indexed on `(last_name, first_name)`, and the left-prefix rule says you must start your search from the left column.

A composite index in a relational database is the same structure: a B-tree sorted first by the leftmost column, then by the second column within identical values of the first, and so on. The sorted order at each level is what enables fast lookup. If you skip the leftmost column in your query predicate, the database has no way to navigate to a specific region of the tree — it would have to scan every leaf entry, which is no better than a full table scan.

The practical consequence is that you cannot create one composite index and expect it to cover all possible query patterns on those columns. Each distinct leading-column combination requires either its own index or careful query redesign. A table queried both by `(user_id, status)` and by `(status)` alone may need two separate indexes — one composite `(user_id, status)` and one single-column `(status)`.

The tradeoff between selectivity and query frequency is a real design decision. Placing the most selective column first maximizes how many rows the index eliminates on the first filter step. But if most queries filter only by the second column, a leading column that is never used alone means those queries cannot use the index at all. The right choice depends on which queries actually run in production and how often.

---

## How It Actually Works

When the database builds a composite index, it sorts the indexed rows by the first column, then breaks ties using the second column, and so on. Internally this means the leaf nodes of the B-tree are ordered by the tuple `(col1_value, col2_value, col3_value, ...)`. A query that provides a value for the first column can navigate to the correct subtree immediately. A query that skips the first column cannot use this sorted order at all.

```sql
-- Create a composite index on (user_id, created_at)
CREATE INDEX idx_orders_user_created ON orders(user_id, created_at);

-- USES the index: leading column (user_id) is in WHERE
SELECT * FROM orders WHERE user_id = 42;

-- USES the index: both columns present — most selective
SELECT * FROM orders WHERE user_id = 42 AND created_at >= '2024-01-01';

-- USES the index: ORDER BY on the second column works because user_id equality
-- collapses the first sort dimension, leaving created_at sorted
SELECT * FROM orders WHERE user_id = 42 ORDER BY created_at DESC;

-- Does NOT use the index: skips the leading column
SELECT * FROM orders WHERE created_at >= '2024-01-01';

-- Does Not use the index for created_at filtering: range on user_id breaks the chain
-- (the index can filter user_id > 100 but cannot then use created_at ordering)
SELECT * FROM orders WHERE user_id > 100 AND created_at >= '2024-01-01';
```

When the leading column appears only in a range predicate (not an equality), the index can still narrow the search to a range of entries, but it cannot use the second column's sorted order to skip rows within that range. The equality-then-range pattern `(user_id = 42 AND created_at >= ...)` is efficient. The range-then-range pattern `(user_id > 100 AND created_at >= ...)` only exploits the first column's range.

```sql
-- Bad: two single-column indexes on a table queried with both columns
CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);

-- The planner must choose one index and filter residually, or use a bitmap index scan
-- Better: one composite index for the most common combined query
CREATE INDEX idx_orders_user_status ON orders(user_id, status);

-- Query that benefits directly from the composite
SELECT * FROM orders WHERE user_id = 42 AND status = 'pending';

-- Adding a second index for status-only queries (left-prefix skipped)
CREATE INDEX idx_orders_status ON orders(status);
SELECT * FROM orders WHERE status = 'failed';
```

Composite indexes can also serve `ORDER BY` when the sort columns match the index key in order. If an index exists on `(user_id, created_at)` and the query filters on `user_id = X` and orders by `created_at`, the planner can read the index entries for that user in sorted created_at order without a separate sort step.

```sql
-- This query benefits from (user_id, created_at) — no Sort node in EXPLAIN
SELECT order_id, total FROM orders
WHERE user_id = 42
ORDER BY created_at DESC
LIMIT 20;
```

---

## How It Connects

The physical mechanism that makes composite indexes work is the B-tree's sorted leaf structure. Every property of composite index behavior — the left-prefix rule, range predicate break — follows directly from how B-trees maintain sort order across multiple key columns.

[[b-tree-index|B-Tree Index Internals]]

EXPLAIN ANALYZE is the tool for verifying whether a composite index is being used as intended. The plan node will show "Index Scan" or "Index Only Scan" using the index name; if the wrong plan appears, the EXPLAIN output reveals whether the index is being skipped entirely or used only partially.

[[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]

---

## Common Misconceptions

Misconception 1: "If I have an index on (a, b, c), I don't need any other indexes on this table for those columns."
Reality: The index on (a, b, c) cannot serve queries that filter only on `b`, `c`, or `(b, c)` — the left-prefix rule requires `a` to be present. Queries that start with any other column require separate indexes. Blindly relying on a composite index while omitting single-column indexes leads to silent sequential scans.

Misconception 2: "More columns in a composite index always means better performance."
Reality: Each additional column in a composite index adds to the size of every index entry, increasing disk and memory usage. A six-column composite index may be no faster than a two-column index for the actual queries being run, while consuming considerably more space and imposing higher write overhead. Index design should be query-driven, not column-exhaustive.

Misconception 3: "Column order in a composite index only matters for equality queries."
Reality: Column order affects range queries, ORDER BY resolution, and which queries can use the index at all. An equality predicate on the leading column followed by a range on the second column is efficiently served by the index. Reversing those columns means the range predicate on the now-leading column breaks the chain for the second column entirely.

---

## Why It Matters in Practice

Composite indexes are the solution for the most common class of real-world query — one that filters by a primary entity (user, account, product) and then applies a secondary filter (date range, status, category). Without a well-designed composite index, these queries degrade into sequential scans as data grows, or force the planner to choose between two imperfect single-column indexes.

A composite index is also a form of documentation of access patterns. The presence of `(tenant_id, created_at)` on an events table communicates clearly that the system is expected to query events per tenant in time order. New developers working on the codebase can read the indexes to understand how the data is intended to be accessed — and add new indexes when new access patterns emerge rather than assuming the existing structure covers them.

---

## What Breaks

**Left-prefix skipped in a high-traffic query.** An application queries orders by `status = 'pending'` to find work items for a processing queue. The composite index `(user_id, status)` exists, but the status-only query skips the leading column and triggers a full sequential scan on a 20-million-row table.

```sql
-- Composite index cannot help this query
CREATE INDEX idx_orders_user_status ON orders(user_id, status);

-- Sequential scan because user_id is missing
SELECT * FROM orders WHERE status = 'pending' LIMIT 100;

-- Fix: add a dedicated index for this access pattern
CREATE INDEX idx_orders_status ON orders(status) WHERE status = 'pending';
```

**Range predicate on the leading column prevents second-column filtering.** A developer expects the index to filter both `created_at` and `user_id` efficiently. The index is `(created_at, user_id)`. Because the query uses a range on `created_at` (the leading column), the database can only narrow to the date range and then must scan all those rows to apply the `user_id` filter.

```sql
-- Index: (created_at, user_id) — range on leading column
CREATE INDEX idx_orders_date_user ON orders(created_at, user_id);

-- Range on created_at: index helps with date range, but user_id filter applied as residual
SELECT * FROM orders
WHERE created_at >= '2024-01-01' AND created_at < '2024-02-01'
AND user_id = 42;

-- Better index for this pattern: (user_id, created_at) — equality first, range second
CREATE INDEX idx_orders_user_date ON orders(user_id, created_at);
```

---

## Interview Angle

Common question forms:
- "Explain the left-prefix rule for composite indexes."
- "How would you index a table for queries that always filter by user_id and sometimes also filter by date?"
- "Why can't a composite index on (a, b) be used for a query that only filters on b?"

Answer frame:
Describe the physical sort order: the B-tree leaf entries are sorted first by `a`, then by `b` within each `a` value. Without a known `a` value, the `b` values are scattered across the entire index in no predictable order — every leaf would need to be examined. For the user_id + date pattern: a composite index `(user_id, created_at)` serves both user_id-only queries and user_id + date range queries. For date-only or cross-user queries a separate index on `created_at` is needed. Close with the cost point: each additional index has write overhead, so justify each one against its actual query benefit.

---

## Related Notes

- [[sql-indexes|SQL Indexes]]
- [[b-tree-index|B-Tree Index Internals]]
- [[covering-indexes|Covering Indexes]]
- [[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]
