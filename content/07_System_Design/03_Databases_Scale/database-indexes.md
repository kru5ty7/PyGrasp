---
title: 04 - Database Indexes
description: "How B-tree indexes work, when composite and covering indexes matter, and the write penalty that every index imposes."
tags: [indexes, database, performance, b-tree, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Database Indexes

> An index is a bet that you will read this column more than you write it — and knowing when that bet pays off, and when it costs you, is what separates a well-tuned database from one that is slow for mysterious reasons.

---

## Quick Reference

**Core idea:**
- A B-tree index stores column values in a sorted tree structure enabling O(log N) lookups instead of O(N) full scans
- A composite index covers multiple columns and is directional — column order matters
- A covering index includes all columns needed by a query, eliminating the need to look up the actual row
- Index selectivity: how many rows share a given index value — high selectivity (few rows per value) makes indexes more effective
- Every index adds overhead to INSERT/UPDATE/DELETE — the more indexes, the slower writes

**Tricky points:**
- A composite index on (a, b) can be used for queries filtering on `a` alone, but not on `b` alone
- Low-selectivity columns (e.g., boolean `is_active` on a 90% active table) often produce worse performance with an index than without
- `EXPLAIN ANALYZE` in PostgreSQL shows whether and how indexes are used for a specific query
- Indexes on high-write tables slow writes significantly — index maintenance happens on every write
- Partial indexes (index only rows matching a WHERE condition) can be more efficient for selective conditions

---

## What It Is

Think of a library's card catalog. Without the catalog, finding a specific book means walking every aisle and reading every spine — a linear scan. The card catalog organizes books by author name (or title or subject) in alphabetical order. Looking up "Morrison, Toni" in the catalog gives you the exact shelf location. You walk directly to the book. The catalog is an index.

In a database, an index is a separate data structure that maintains sorted references to rows in a table, allowing the database engine to find rows matching a condition without scanning every row. Without an index on `users.email`, finding a user by email means reading every row and checking. With an index, the database navigates the index tree and jumps directly to the relevant row (or confirms the row does not exist) in O(log N) time, where N is the number of rows.

The B-tree (Balanced Tree) is the most common index structure in relational databases. It stores index entries in sorted order in a balanced tree where every leaf node is the same distance from the root. This guarantees O(log N) lookups, range queries, and ordering. The root and interior nodes hold key values and pointers to child nodes. Leaf nodes hold the index key and a pointer (typically a row ID or primary key value) to the actual row in the heap (the unsorted table data). A range query like `WHERE created_at BETWEEN '2026-01-01' AND '2026-01-31'` traverses the tree to the first matching leaf and then follows the linked list of leaf nodes rightward to collect all matches.

Composite indexes index multiple columns together. An index on `(last_name, first_name)` stores entries sorted first by last name, then by first name within each last name group. This index efficiently answers queries like `WHERE last_name = 'Smith'` (use the first column) and `WHERE last_name = 'Smith' AND first_name = 'John'` (use both columns). It does not efficiently answer `WHERE first_name = 'John'` alone because entries are not sorted by first name globally — this would require scanning all leaf nodes.

---

## How It Actually Works

Index selectivity is the ratio of distinct values to total rows. An index on `user.country` in a US-dominated dataset where 80% of users have country='US' has low selectivity for that value. The database query planner may decide that scanning the entire table and filtering is faster than navigating the index (which points to 80% of the rows anyway). An index on `user.email`, where every email is unique, has perfect selectivity — the index points to exactly one row.

A covering index includes all columns that a query needs, eliminating the need to access the actual table rows after finding the index entry. If a query is `SELECT email, created_at FROM users WHERE last_name = 'Smith'` and the index is `(last_name, email, created_at)`, the database engine can answer the entire query from the index without touching the heap table. This is called an index-only scan and is significantly faster than a regular index scan (which requires a heap fetch for each matching row).

Write overhead is the unavoidable cost of indexes. Every `INSERT` adds a new entry to all indexes on the table. Every `DELETE` removes an entry from all indexes. Every `UPDATE` that modifies an indexed column removes the old entry and inserts a new one. On a table with 10 indexes, a single `INSERT` performs 10 index insertions plus the heap write. Tables with extremely high write rates (millions of inserts per second) may need to minimize indexes — sometimes to zero for staging or write-optimized tables.

```sql
-- Show query execution plan in PostgreSQL
EXPLAIN ANALYZE
SELECT id, email, created_at
FROM users
WHERE email = 'alice@example.com';
-- With no index: Seq Scan on users (cost=0.00..2341.00 rows=1 width=...)
-- With index: Index Scan using users_email_idx on users (cost=0.29..8.31 rows=1...)

-- Composite index: columns ordered by selectivity and query pattern
CREATE INDEX users_name_idx ON users (last_name, first_name);
-- Use: WHERE last_name = 'Smith'           → efficient (leftmost column)
-- Use: WHERE last_name = 'Smith' AND first_name = 'John' → efficient
-- Skip: WHERE first_name = 'John'          → full scan (not leftmost)

-- Covering index: include non-key columns for index-only scans
CREATE INDEX users_email_covering ON users (last_name) INCLUDE (email, created_at);
-- SELECT email, created_at WHERE last_name = 'Smith' hits only the index

-- Partial index: index only a subset of rows (great for status columns)
CREATE INDEX orders_pending_idx ON orders (created_at)
WHERE status = 'pending';
-- Tiny index, very effective for: WHERE status = 'pending' ORDER BY created_at

-- Check index usage statistics
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,         -- how many times this index was used
    idx_tup_read,     -- tuples read via this index
    idx_tup_fetch     -- actual heap fetches
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

Partial indexes are a powerful optimization for filtered queries. Instead of indexing every row, a partial index indexes only rows where a condition is true. An index on `orders.created_at WHERE status = 'pending'` contains only pending orders. If pending orders are 1% of total orders, this index is 100x smaller than a full index on `created_at`. The database can only use this partial index for queries that include `status = 'pending'` in the WHERE clause — but for those queries, it is dramatically faster.

Index maintenance during large batch operations (bulk inserts, migrations) is a common performance pitfall. If you need to load 10 million rows into a table, disabling non-essential indexes before the load and rebuilding them afterward is typically far faster than maintaining them during the load. PostgreSQL's `COPY` command and disabling triggers/constraints for bulk loads are standard practice for ETL operations.

---

## How It Connects

Indexes directly affect query cost, which in turn affects both the latency of individual queries and the total throughput the database can support. Understanding the latency-throughput relationship helps calibrate when index optimization is worth pursuing.

[[latency-vs-throughput|Latency vs Throughput]]

In read replica setups, replicas serve the same query patterns as the primary. Index design on the primary replicates automatically to replicas — there is no need to create indexes separately.

[[read-replicas|Read Replicas]]

When a database is sharded, each shard has its own index structures. Queries that must scatter across all shards are expensive regardless of indexing because the scatter overhead dominates.

[[database-sharding|Database Sharding]]

---

## Common Misconceptions

Misconception 1: "More indexes means faster queries."
Reality: More indexes means faster reads for the specific queries those indexes cover, but slower writes for every indexed column. A table with 20 indexes can have painfully slow INSERT performance. Indexes should be added to address observed slow queries, not preemptively. Review which indexes are actually used (`pg_stat_user_indexes`) and drop unused ones.

Misconception 2: "I should index every column I filter on."
Reality: Low-selectivity columns (boolean flags, status enums with few values) often make queries slower with an index because the database must read the index and then fetch most of the table rows anyway. The query planner may be smarter than you: it might choose a full table scan over an index scan. Always verify with `EXPLAIN ANALYZE`.

Misconception 3: "A composite index on (a, b) is the same as two separate indexes on a and b."
Reality: A composite index and two separate indexes have different capabilities. The composite index on (a, b) efficiently handles queries on a alone or both a and b together, but not b alone. Two separate indexes can be combined by the query planner using a bitmap index scan for queries filtering both a and b, but this is less efficient than a well-designed composite index. The composite index also maintains sorted order within each value of a, enabling `ORDER BY b WHERE a = x` to use index-only scans.

---

## Why It Matters in Practice

Index design is the single most impactful performance optimization available to a Python developer working with a relational database. Most slow query performance problems in production are index problems: missing indexes on frequently queried columns, unused indexes consuming write overhead, or wrong column order in composite indexes. Before considering any architectural change (adding replicas, moving to a faster database, sharding), analyzing and fixing index design is always the first step.

For Python developers using ORMs like SQLAlchemy or Django ORM, adding indexes in migrations is straightforward (`db.Index('email_idx', User.email)`), but understanding which queries benefit from which indexes requires reading `EXPLAIN ANALYZE` output and correlating it with slow query logs. Building this habit early prevents the accumulation of index debt.

---

## Interview Angle

Common question forms:
- "How do database indexes work? What data structure do they use?"
- "What is a composite index and what determines column order?"
- "What is the downside of indexes?"

Answer frame:
Explain B-tree: sorted tree, O(log N) lookup, range queries, linked leaf nodes. Explain the heap fetch: after the index lookup, the engine fetches the actual row. Explain covering index: no heap fetch needed if all required columns are in the index. Explain composite index: column order determines which prefix queries use it. Explain write overhead: every index adds overhead to every write on that table. Close with selectivity: low-selectivity indexes can be counterproductive.

---

## Related Notes

- [[database-replication|Database Replication]]
- [[database-sharding|Database Sharding]]
- [[sql-vs-nosql|SQL vs NoSQL]]
- [[latency-vs-throughput|Latency vs Throughput]]
- [[sqlalchemy-core|SQLAlchemy Core]]
