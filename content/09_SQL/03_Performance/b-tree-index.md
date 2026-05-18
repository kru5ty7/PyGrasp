---
title: B-Tree Index Internals
description: The B-tree is the default index structure in PostgreSQL and MySQL — a self-balancing sorted tree that supports equality, range, and ordering operations in O(log n) time.
tags: [sql, layer-9, indexes, b-tree, internals]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# B-Tree Index Internals

> The B-tree index is the workhorse behind nearly every `CREATE INDEX` statement — knowing how its sorted, balanced structure determines which query patterns it can accelerate (and which it cannot) lets you make index decisions from first principles rather than guesswork.

---

## Quick Reference

**Core idea:**
- B-tree stands for Balanced tree — all leaf nodes sit at the same depth, guaranteeing O(log n) lookup regardless of which key is sought
- Internal (non-leaf) nodes hold separator keys that route traversal downward
- Leaf nodes hold the actual indexed key values and row pointers (TIDs in PostgreSQL, primary key refs in InnoDB)
- Leaf nodes are doubly linked, enabling efficient range scans without re-traversing from the root
- Supports: equality (`=`), range (`<`, `>`, `BETWEEN`), `ORDER BY`, and prefix matching (`LIKE 'foo%'`)
- Does NOT support: suffix/substring matching (`LIKE '%foo'`), case-insensitive equality without a functional index

**Tricky points:**
- `LIKE '%foo'` cannot use a B-tree because the sorted order of the index is based on the leading characters — the unknown prefix means every leaf could match
- UPDATE and DELETE in PostgreSQL leave dead index entries behind; VACUUM reclaims them
- The fill factor controls how full each index page is packed — a lower fill factor leaves room for in-place updates, reducing page splits
- A B-tree on a high-cardinality column may still be skipped if the query returns a large fraction of rows (planner prefers sequential scan)
- Index entries for NULL are stored in B-trees (PostgreSQL stores NULL at one end of the sort order); `IS NULL` can use a B-tree index

---

## What It Is

Imagine a library card catalogue organized by author surname. The catalogue is divided into alphabetical sections (A–D, E–H, etc.), and each section is itself subdivided. To find all books by "Morrison," you do not read every card — you navigate the alphabetical hierarchy until you land on the Morrison entries, then read forward until you pass them. A B-tree index works exactly like this catalogue: it keeps its entries in sorted order, arranged as a tree whose branching structure lets you reach any key in a predictable number of steps.

The "balanced" property is what makes the B-tree reliable at scale. In an unbalanced tree (like a naive binary search tree built from sequential inserts), the tree can degenerate into a linked list, making lookups O(n). The B-tree rebalances itself automatically as rows are inserted and deleted, ensuring that the root-to-leaf path length grows only logarithmically with the number of rows. A table with one billion rows has a B-tree that is only about 30 levels deep — each lookup touches at most 30 pages.

The doubly linked leaf layer is the feature that separates a B-tree from a structure suited only for point lookups. Once the tree traversal reaches the first matching leaf entry for a range query (say, all orders from January), the engine can scan forward along the leaf chain to collect all subsequent matching entries without returning to the root. This is why B-trees support range queries so efficiently and why they can serve an `ORDER BY` on an indexed column without a separate sort step.

---

## How It Actually Works

A B-tree index in PostgreSQL consists of pages (typically 8 KB each). The root page sits at the top; internal pages contain separator keys and child page pointers; leaf pages contain index entries. Each index entry at the leaf level stores the indexed column value(s) plus a TID (tuple identifier) — a physical address consisting of a block number and an offset within that block pointing to the heap row.

```sql
-- A standard B-tree index
CREATE INDEX idx_orders_created_at ON orders(created_at);

-- Equality lookup: O(log n) traversal to leaf, follow TID to heap
SELECT * FROM orders WHERE created_at = '2024-06-15';

-- Range scan: traverse to first matching leaf, scan forward along leaf chain
SELECT * FROM orders WHERE created_at BETWEEN '2024-06-01' AND '2024-06-30';

-- ORDER BY uses the existing sort order of the index — no extra Sort node
SELECT order_id, created_at FROM orders ORDER BY created_at DESC LIMIT 100;

-- Prefix LIKE: the sorted structure supports this because the prefix anchors the search
SELECT * FROM products WHERE sku LIKE 'ELEC%';

-- Suffix LIKE: CANNOT use the B-tree — leading characters are unknown
SELECT * FROM products WHERE sku LIKE '%ELEC';  -- sequential scan
```

When a row is updated in PostgreSQL, the old row version is not overwritten — a new row is written in the heap, and the old one is marked dead (MVCC). Both the old and new index entries exist in the B-tree until VACUUM removes the dead ones. This means a table with high UPDATE volume accumulates dead index entries that bloat the index, increase its depth, and slow traversal. VACUUM (or autovacuum) reclaims these pages.

```sql
-- Check index bloat and dead tuple accumulation
SELECT relname, n_dead_tup, n_live_tup, last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'orders';

-- Force a vacuum to reclaim dead index entries
VACUUM (ANALYZE) orders;

-- Rebuild the index completely (locks table) — eliminates all bloat
REINDEX INDEX idx_orders_created_at;

-- Rebuild without locking (PostgreSQL 12+)
REINDEX INDEX CONCURRENTLY idx_orders_created_at;
```

The fill factor (defaulting to 90 for B-trees) determines how full each page is packed during index creation. Leaving 10% of each page empty allows in-place updates: if a row is updated and the new index entry is close in sort order to the old one, the page has room for the new entry without a page split. A heavily-updated table can benefit from a lower fill factor (e.g., 70) to reduce write amplification from page splits.

```sql
-- Create an index with a custom fill factor to reduce page splits
CREATE INDEX idx_accounts_balance ON accounts(balance) WITH (fillfactor = 70);
```

---

## How It Connects

The B-tree is the physical implementation of what the general concept of SQL indexes describes. Understanding the tree structure explains the selectivity, range support, and write overhead properties that apply to any index discussion.

[[sql-indexes|SQL Indexes]]

Composite indexes are B-trees built on multiple columns. The sort order of the leaf nodes is determined by the first column, then the second — which is exactly why the left-prefix rule holds and why (b, c) queries cannot use an index built as (a, b, c).

[[composite-indexes|Composite Indexes]]

---

## Common Misconceptions

Misconception 1: "B-tree indexes work for any pattern in a LIKE expression."
Reality: B-trees are sorted by the leading characters of the indexed value. A prefix like `LIKE 'foo%'` anchors the search to a specific region of the sorted leaf layer. A suffix like `LIKE '%foo'` provides no anchor — every leaf entry might match — so the planner must either scan every index entry (equivalent to a table scan) or skip the index entirely. Full-text search or reverse-indexed columns are the correct tools for suffix matching.

Misconception 2: "An index on a frequently updated column is always harmful."
Reality: The write overhead of maintaining an index on an updated column must be weighed against the read benefit. An index on `updated_at` for a polling query that fetches recently changed rows may be heavily used and worth the update cost. The decision is quantitative, not categorical.

Misconception 3: "NULL values cannot be indexed or found via an index."
Reality: PostgreSQL stores NULL values in B-tree indexes (at the end of the sort order by default). A query `WHERE col IS NULL` can use a B-tree index on `col`. The standard SQL practice of partial indexes that exclude NULLs (`CREATE INDEX ... WHERE col IS NOT NULL`) is a space optimization, not a requirement.

---

## Why It Matters in Practice

Most production performance problems involving indexes are ultimately B-tree problems. Knowing that leaf nodes are linked makes it intuitive why range scans are fast. Knowing that the sort order is based on the leading column explains why composite index column order is so consequential. Knowing about dead tuple bloat explains why a table that ran VACUUM for the first time in months suddenly got faster — the index shrank.

Developers who understand B-tree internals can predict without running EXPLAIN whether a new query pattern will hit an index or not. They can explain to teammates why renaming a function wrapper around an indexed column broke a query plan, or why a LIKE query suddenly stopped using the index after a change to the search pattern. This predictive capability is the difference between debugging query plans reactively and designing them correctly upfront.

---

## What Breaks

**Page split cascade under sequential insert load.** When rows are inserted in monotonically increasing primary key order (e.g., auto-increment IDs), every insert goes to the rightmost leaf page. When that page fills, it splits, and the new right page is immediately filled by the next batch of inserts. Under very high insert throughput this causes a continuous cascade of page splits on the right edge of the tree. A fill factor below 100 can help, but the more common solution for time-series or event tables is partitioning.

```sql
-- Observe a growing index under insert load
SELECT pg_size_pretty(pg_relation_size('idx_events_event_id')) AS index_size;
-- Run after bulk insert and compare
```

**Index bloat after bulk deletes without VACUUM.** Deleting 80% of a large table's rows marks heap tuples and index entries as dead but does not reclaim space. The index retains its pre-delete size and depth, so subsequent reads traverse a much larger structure than necessary.

```sql
-- After a large DELETE
DELETE FROM audit_log WHERE created_at < NOW() - INTERVAL '1 year';

-- Index is still full-sized — run VACUUM to reclaim
VACUUM (ANALYZE, VERBOSE) audit_log;
```

**Functional index omission causes sequential scan.** A developer applies `DATE_TRUNC` to an indexed timestamp column in a WHERE clause. The B-tree is ordered by the raw timestamp values, not the truncated values, so the index cannot be used.

```sql
-- Breaks index usage
SELECT * FROM events WHERE DATE_TRUNC('day', created_at) = '2024-06-15';

-- Fix: functional index or rewrite the predicate as a range
SELECT * FROM events
WHERE created_at >= '2024-06-15' AND created_at < '2024-06-16';
```

---

## Interview Angle

Common question forms:
- "How does a B-tree index work internally?"
- "Why doesn't `LIKE '%foo'` use an index?"
- "What happens to a B-tree index when you delete many rows?"

Answer frame:
Describe the three-level structure: root routes traversal, internal nodes hold separators, leaf nodes hold (key, TID) pairs and are linked. Explain O(log n) lookup and how the linked leaf layer enables range scans. Address LIKE: the sorted order means a known prefix anchors the search position; an unknown prefix provides no anchor, so the entire index would need to be scanned — the planner skips it. For deletes: MVCC marks entries dead rather than removing them immediately; VACUUM reclaims the space, but until it runs the index retains its bloated size and traversal depth.

---

## Related Notes

- [[sql-indexes|SQL Indexes]]
- [[composite-indexes|Composite Indexes]]
- [[covering-indexes|Covering Indexes]]
- [[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]
- [[query-optimization|Query Optimization]]
