---
title: 30 - Query Optimization
description: Query optimization is the practice of rewriting SQL and designing indexes so that queries execute faster without changing their results — a skill that separates developers who understand the database from those who only use it.
tags: [sql, layer-9, performance, optimization]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# Query Optimization

> Query optimization is the discipline of making SQL faster by understanding how the planner reads queries, which rewrites unlock better plans, and which patterns silently destroy index utility — skills that become mandatory as data volumes grow beyond what brute-force hardware can absorb.

---

## Quick Reference

**Core idea:**
- The query planner generates execution plans based on statistics — stale statistics produce bad plans; run ANALYZE
- Indexes on WHERE and JOIN columns are the highest-leverage single optimization
- Functions applied to indexed columns in WHERE clauses defeat the index — rewrite as range predicates
- Correlated subqueries re-execute for every outer row; rewrite them as JOINs where possible
- `EXISTS` short-circuits on the first match; `IN` with a large subquery may materialize the full subquery
- `SELECT *` forces the planner to fetch all columns including wide ones — always select only needed columns

**Tricky points:**
- `WHERE YEAR(created_at) = 2024` defeats an index on `created_at`; use a range predicate instead
- Implicit type coercions (e.g., filtering an integer column with a string literal) can defeat indexes in some databases
- CTEs are optimization fences in PostgreSQL versions before 12 — the planner cannot push predicates into them; use `NOT MATERIALIZED` or inline the CTE if optimization is needed
- OR conditions on different columns often prevent index usage — consider UNION ALL as an alternative
- The `LIMIT` clause can transform a full-table aggregation into an early-exit index scan when combined with ORDER BY

---

## What It Is

Think of a query as a set of directions from your house to a destination. There are dozens of routes — highways, local roads, shortcuts through neighborhoods. A bad GPS picks the route that looks shortest on the map without knowing that the highway is under construction. A good GPS checks current conditions and picks the route that is actually fastest today. Query optimization is the process of finding the route that is fastest given the actual data, the existing indexes, and the current statistics — and sometimes rebuilding the road (creating a new index or rewriting the query) to make an entirely better route available.

The database query planner is an automatic optimizer, but it works within constraints: it only knows what the statistics tables tell it about data distribution, and it can only choose among physical operations for the exact SQL it receives. When a developer writes a query that wraps an indexed column in a function, the planner cannot see through that transformation — the index is invisible to it. When a developer writes a correlated subquery, the planner may be forced to re-execute the inner query for every outer row because the SQL structure implies that dependency.

Manual query optimization is the practice of understanding these planner constraints and rewriting queries to give the planner better options. This is not about tricking the database — it is about writing SQL whose structure faithfully expresses the query's intent in a form the planner can exploit. The most powerful rewrites are often simple: change a function wrapping a column into a range condition, change an `IN` subquery into a `JOIN`, or pull a frequently-computed expression into a CTE that the planner can execute once.

The planner's input is not just the SQL text — it is also the table statistics gathered by ANALYZE. These statistics describe the distribution of values in each column: the number of distinct values, the most common values and their frequencies, a histogram of the value range. When statistics are stale (not updated since a large batch load, for instance), the planner's row count estimates are wrong, and it may choose entirely inappropriate join algorithms or scan strategies. Keeping statistics current is as important as writing good SQL.

---

## How It Actually Works

The single most impactful optimization technique is ensuring that the right indexes exist and that the WHERE clause predicates are written in a form the index can use. The canonical example is date filtering: wrapping a timestamp column in a function produces a predicate the planner cannot match to a B-tree index.

```sql
-- DEFEATS the index on created_at — function applied to column
SELECT * FROM orders WHERE YEAR(created_at) = 2024;      -- MySQL
SELECT * FROM orders WHERE DATE_TRUNC('year', created_at) = '2024-01-01';  -- PostgreSQL

-- USES the index — range predicate on the column directly
SELECT * FROM orders
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
```

Correlated subqueries are a frequent source of hidden N-per-row processing. The subquery references a column from the outer query, forcing the engine to re-execute it for each outer row.

```sql
-- Correlated subquery: inner SELECT runs once per order row
SELECT order_id, (
    SELECT name FROM customers WHERE id = o.customer_id
) AS customer_name
FROM orders o;

-- Rewrite as a JOIN: executes once, joined efficiently
SELECT o.order_id, c.name AS customer_name
FROM orders o
JOIN customers c ON o.customer_id = c.id;
```

`EXISTS` is preferable to `IN` when the subquery can return a large result set. `EXISTS` stops as soon as the first matching row is found; `IN` may materialize and sort the entire subquery result before the outer query starts.

```sql
-- IN: may materialize all active_users before the outer query runs
SELECT * FROM orders
WHERE customer_id IN (SELECT id FROM customers WHERE status = 'active');

-- EXISTS: short-circuits on first match per order row
SELECT * FROM orders o
WHERE EXISTS (
    SELECT 1 FROM customers c
    WHERE c.id = o.customer_id AND c.status = 'active'
);

-- For this pattern, a JOIN with DISTINCT is often the most planner-friendly form
SELECT DISTINCT o.*
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE c.status = 'active';
```

Selecting only the columns needed reduces the width of intermediate results. `SELECT *` on a table with JSON or TEXT columns can multiply the memory and I/O cost of a query significantly, and it prevents the planner from choosing an index-only scan.

```sql
-- SELECT * fetches every column, including wide ones (TEXT, JSONB, BYTEA)
SELECT * FROM products WHERE category_id = 5;

-- Select only what the application actually uses
SELECT product_id, name, price FROM products WHERE category_id = 5;
```

CTEs in PostgreSQL before version 12 are optimization fences: the planner materializes the CTE result and cannot push WHERE predicates into it or inline it into the surrounding query. This can dramatically change performance when the CTE produces many rows that are later filtered.

```sql
-- PostgreSQL < 12: this CTE is always materialized — the WHERE is applied after
WITH recent_orders AS (
    SELECT * FROM orders WHERE created_at >= NOW() - INTERVAL '30 days'
)
SELECT * FROM recent_orders WHERE user_id = 42;

-- PostgreSQL 12+: the planner can inline this by default
-- To force materialization (or avoid it), use the hint:
WITH recent_orders AS MATERIALIZED (...)
-- or
WITH recent_orders AS NOT MATERIALIZED (...)
```

OR conditions on different columns often prevent index usage because the planner cannot satisfy both OR branches with a single index scan. UNION ALL can be more efficient when each branch can use its own index.

```sql
-- OR on two different columns — planner may choose Seq Scan
SELECT * FROM users WHERE email = 'a@b.com' OR phone = '555-1234';

-- UNION ALL: each branch uses its own index
SELECT * FROM users WHERE email = 'a@b.com'
UNION ALL
SELECT * FROM users WHERE phone = '555-1234' AND email != 'a@b.com';
```

---

## How It Connects

Every optimization technique must be verified with EXPLAIN ANALYZE. Writing a rewrite and assuming it is faster is not optimization — it is guessing. The before-and-after EXPLAIN outputs are the evidence that a change worked (or did not).

[[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]

The correlated subquery pattern is a structural form of the N+1 problem: for each row in the outer query, additional work is performed. Understanding the N+1 problem in ORMs illuminates why correlated subqueries are expensive at the SQL level.

[[n-plus-one-problem|N+1 Problem]]

---

## Common Misconceptions

Misconception 1: "If the query returns the right results, the SQL is correct."
Reality: SQL is declarative — the same result set can be produced by many different query structures with wildly different execution costs. A query that returns correctly but takes 30 seconds instead of 30 milliseconds is incorrect for production use. Correctness includes performance.

Misconception 2: "Adding more indexes will eventually make all queries fast."
Reality: Every index slows all writes to the table. A table with 20 indexes on a write-heavy workload will have write performance that overwhelms any read benefit. Index design must be driven by the specific queries that are slow, not by attempting to pre-index every possible access pattern.

Misconception 3: "The database's query planner will always find the optimal plan."
Reality: The planner uses statistics-based cost estimation, not perfect knowledge. For complex queries with many joins, the planner evaluates a subset of possible plans (the search space grows exponentially with join count). Statistics can be stale or misleading for skewed distributions. Developer-supplied hints, rewritten query structure, and materialized CTEs are all legitimate tools to guide the planner when it makes poor choices.

---

## Why It Matters in Practice

Query performance is not a performance engineering concern — it is a correctness concern. A query that takes 45 seconds in production under load is a bug with user-visible consequences: timeouts, error pages, cascading resource exhaustion. Unlike application code bugs, slow queries often appear only at scale, meaning they pass all testing and only fail in production with real data volumes.

The patterns that cause slow queries are consistent: missing indexes, functions on indexed columns, correlated subqueries, SELECT *, and stale statistics. A developer who can identify these patterns on sight and knows the rewrite for each can prevent most performance regressions before they reach production. This knowledge compounds: once these patterns are internalized, writing fast SQL becomes a default habit rather than a post-hoc optimization task.

---

## What Breaks

**Function on indexed column causes full table scan at scale.** An application has run fine for two years. The orders table grows to 50 million rows. A reporting query that uses `WHERE YEAR(shipped_at) = 2024` has been running for months — it was tolerable at 5 million rows (2 seconds) but now takes 3 minutes. The fix is a one-line predicate rewrite.

```sql
-- Current slow query
SELECT COUNT(*) FROM orders WHERE YEAR(shipped_at) = 2024;

-- Rewritten to use the index on shipped_at
SELECT COUNT(*) FROM orders
WHERE shipped_at >= '2024-01-01' AND shipped_at < '2025-01-01';
```

**CTE optimization fence causes 10x regression after migration.** A team migrates from PostgreSQL 11 to PostgreSQL 12 and notes that a query that was fast in production is slower in the new environment. The query uses a CTE with a large intermediate result. In version 11, the CTE was materialized (optimization fence) — but the planner happened to make a good decision given the fenced result. In version 12, the CTE is inlined by default, and the planner makes a poor join order decision with the larger search space.

```sql
-- Pin the behavior by being explicit (PostgreSQL 12+)
WITH filtered AS MATERIALIZED (
    SELECT id FROM orders WHERE status = 'shipped' AND created_at >= '2024-01-01'
)
SELECT * FROM order_items WHERE order_id IN (SELECT id FROM filtered);
```

**Implicit type coercion defeats an index.** A developer queries an integer column with a string literal in an ORM. The ORM generates `WHERE user_id = '42'`. PostgreSQL coerces the string to integer and uses the index. MySQL in certain configurations cannot coerce in the indexed direction and falls back to a full scan. The query works but is slow.

```sql
-- Parameterized query with the wrong type in some ORMs
SELECT * FROM sessions WHERE user_id = '42';  -- string vs integer column

-- Fix: ensure the application passes the correct type
SELECT * FROM sessions WHERE user_id = 42;  -- integer literal
```

---

## Interview Angle

Common question forms:
- "How would you optimize a slow SQL query?"
- "Why does `WHERE YEAR(created_at) = 2024` perform poorly even with an index on created_at?"
- "When would you use EXISTS instead of IN?"

Answer frame:
Structure the answer as a process: (1) use EXPLAIN ANALYZE to understand the current plan, (2) identify the bottleneck — missing index, bad row estimate, expensive operation, (3) apply the relevant rewrite or index change, (4) verify with EXPLAIN ANALYZE. For the YEAR example: the index on `created_at` is sorted by the raw timestamp values, not by the year extracted from them; wrapping the column in a function removes it from the B-tree's sort order. The fix is a range predicate that queries the column directly. For EXISTS vs IN: EXISTS short-circuits on first match per outer row; IN may materialize the subquery result set fully before the outer query begins — EXISTS is preferable when the subquery can return many rows.

---

## Related Notes

- [[sql-indexes|SQL Indexes]]
- [[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]
- [[composite-indexes|Composite Indexes]]
- [[covering-indexes|Covering Indexes]]
- [[n-plus-one-problem|N+1 Problem]]
- [[correlated-subqueries|Correlated Subqueries]]
- [[cte|Common Table Expressions]]
