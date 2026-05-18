---
title: EXPLAIN and EXPLAIN ANALYZE
description: EXPLAIN shows the query execution plan the planner chose; EXPLAIN ANALYZE runs the query and reveals both estimated and actual costs, making it the essential tool for diagnosing slow queries.
tags: [sql, layer-9, performance, query-planning, explain]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# EXPLAIN and EXPLAIN ANALYZE

> EXPLAIN is the database's window into its own decision-making — it shows precisely which operations the planner chose, in which order, at what estimated cost, and (with ANALYZE) what actually happened at runtime, making it indispensable for any performance investigation.

---

## Quick Reference

**Core idea:**
- `EXPLAIN` displays the execution plan without running the query — safe for expensive queries
- `EXPLAIN ANALYZE` runs the query and augments the plan with actual row counts, actual timing, and loop counts
- Plan nodes are read bottom-up: the innermost (deepest) node executes first and feeds results upward
- Cost format: `(startup_cost..total_cost)` — startup is cost to produce first row, total is cost for all rows
- Row estimates vs actual rows: large discrepancies indicate stale statistics or complex predicates the planner cannot model well
- `EXPLAIN (ANALYZE, BUFFERS)` adds I/O statistics: shared/local hits and reads per node

**Tricky points:**
- EXPLAIN ANALYZE actually executes the query — do not use it on a destructive DML statement without wrapping in a transaction you roll back
- Cost units are arbitrary (not milliseconds) — they only have meaning relative to other nodes in the same plan
- A node with high cost and low actual rows is often a sign the index was skipped; a node with low estimated rows and high actual rows signals bad statistics
- "Rows Removed by Filter" is shown separately from matching rows — a high filter removal count often indicates a missing index
- Hash Join and Merge Join have different trade-offs: Hash Join has high startup cost but scales well; Merge Join requires sorted input but is efficient for large, sorted datasets

---

## What It Is

Think of EXPLAIN as asking a contractor to describe in detail how they plan to renovate a kitchen before they begin — you get the full scope of work, the sequence of tasks, and their time estimates. EXPLAIN ANALYZE is asking the same contractor to renovate the kitchen with a stopwatch running and then hand you a report comparing the original plan against what actually took how long. The contractor's plan might have assumed the cabinets would take two hours; if they actually took six, that discrepancy is where you investigate.

The query planner is the component in the database engine that receives a SQL statement and decides the physical execution strategy: which indexes to use, which join algorithm to apply, in what order to access tables. The planner does not know the right answer in advance — it estimates costs based on table statistics (row counts, value distributions, page counts) and a set of configurable cost parameters. These estimates are educated guesses, and they can be wrong.

EXPLAIN makes those guesses visible. It shows the tree of plan nodes — each node representing one physical operation — along with the planner's estimated startup cost, total cost, row count, and row width. Reading this tree lets you see whether the planner chose a sequential scan when you expected an index scan, whether it estimated 1 row when the actual result is 50,000, and whether it chose a nested loop join for two large tables when a hash join would be far more appropriate.

EXPLAIN ANALYZE closes the loop by actually running the query. It attaches the real execution time and real row count to each plan node. Discrepancies between estimated and actual rows are the primary signal that statistics are stale or that the planner is making incorrect assumptions, both of which require specific remedies.

---

## How It Actually Works

A plan tree is read from the bottom up. The deepest (most indented) node executes first and produces rows that feed the node above it. The root node is the final operation whose output is returned to the client.

```sql
-- Basic EXPLAIN — no query execution
EXPLAIN SELECT * FROM orders WHERE user_id = 42;

-- EXPLAIN ANALYZE — runs the query, shows actual vs estimated
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 42;

-- Full diagnostic form
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o.order_id, c.name
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.created_at >= '2024-01-01';

-- JSON format — useful for programmatic parsing or GUI tools
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM orders WHERE user_id = 42;
```

The cost notation `(startup_cost..total_cost)` appears on every node. The startup cost is the work required before the first row can be returned (e.g., a Sort node must process all input rows before returning any output). The total cost is the estimated work to return all rows. These numbers are in arbitrary planner cost units — they are only meaningful relative to each other within the same plan.

```
-- Sample EXPLAIN output for a query using an index
Index Scan using idx_orders_user_id on orders  (cost=0.43..8.45 rows=3 width=72)
                                               (actual time=0.018..0.021 rows=3 loops=1)
  Index Cond: (user_id = 42)

-- Sample output for a query missing an index
Seq Scan on orders  (cost=0.00..95420.00 rows=1 width=72)
                    (actual time=1823.441..1823.442 rows=1 loops=1)
  Filter: (user_id = 42)
  Rows Removed by Filter: 4999999
```

Key plan nodes and what they mean:

- **Seq Scan**: reads the entire table sequentially. Expected for small tables or queries returning most rows. A problem when the table is large and the query is selective.
- **Index Scan**: traverses the B-tree and fetches heap rows for each match. Random I/O per row.
- **Index Only Scan**: traverses the B-tree and returns data from the index leaf without heap access.
- **Bitmap Index Scan + Bitmap Heap Scan**: collects all matching TIDs first, sorts them, then fetches heap pages in order — converts random I/O to sequential I/O for moderate result sets.
- **Nested Loop**: for each row in the outer relation, performs a lookup in the inner relation. Efficient when the inner side has an index and the outer side is small.
- **Hash Join**: builds a hash table from the smaller relation, then probes it with each row of the larger relation. High startup cost, good for large unsorted inputs.
- **Merge Join**: requires both inputs to be sorted on the join key. Efficient when both sides are already sorted (e.g., from indexes).
- **Sort**: materializes and sorts its input. A Sort node with a large `rows` estimate is a candidate for an index that provides pre-sorted output.
- **Aggregate / HashAggregate**: computes aggregate functions. HashAggregate builds a hash table; a plain Aggregate streams sorted input.

```sql
-- EXPLAIN ANALYZE showing a bad row estimate — stats need refreshing
EXPLAIN ANALYZE
SELECT * FROM events WHERE event_type = 'purchase' AND user_id = 101;

-- Example bad output:
-- Seq Scan on events  (cost=0.00..48300.00 rows=1 width=240)
--                     (actual time=0.212..3841.110 rows=92847 loops=1)
-- "rows=1" estimated, 92847 actual — planner underestimated heavily

-- Fix: update statistics so the planner gets better estimates
ANALYZE events;
```

The BUFFERS option adds I/O data to each node: "shared hit" (pages served from the buffer cache), "shared read" (pages fetched from disk). A node with high "shared read" and slow actual time is doing physical disk I/O — a candidate for caching or index improvement.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT SUM(amount) FROM payments WHERE account_id = 500;

-- Output excerpt:
-- Aggregate  (actual time=143.822..143.822 rows=1 loops=1)
--   Buffers: shared hit=12 read=1840
--   ->  Index Scan using idx_payments_account on payments
--         Buffers: shared hit=12 read=1840
-- 1840 pages read from disk — an index on (account_id, amount) could eliminate the heap reads
```

---

## How It Connects

EXPLAIN ANALYZE is the primary tool for verifying that composite and covering indexes are working as intended. The plan will show "Index Scan," "Index Only Scan," or "Seq Scan," and the cost/row numbers reveal whether the planner is reasoning correctly about the data.

[[composite-indexes|Composite Indexes]]

Query optimization decisions — choosing between a correlated subquery and a JOIN, avoiding functions on indexed columns, selecting needed columns — must be validated with EXPLAIN ANALYZE to confirm the plan improved. Theory about what should be faster must be verified against actual execution.

[[query-optimization|Query Optimization]]

---

## Common Misconceptions

Misconception 1: "EXPLAIN ANALYZE is safe to run on any query."
Reality: EXPLAIN ANALYZE executes the query in full. Running it on a DELETE, UPDATE, or INSERT modifies the data. To safely analyze a write statement, wrap it in a transaction and roll back: `BEGIN; EXPLAIN ANALYZE DELETE ...; ROLLBACK;`. The data change is reversed but the execution statistics are still captured.

Misconception 2: "If EXPLAIN shows low cost, the query is fast."
Reality: Cost units are the planner's internal currency, not milliseconds. They are calibrated to disk I/O assumptions (random_page_cost, seq_page_cost) that may not match the actual storage hardware. Two queries with similar planner costs may have very different actual runtimes depending on data distribution, caching effects, and lock contention. Only EXPLAIN ANALYZE with actual timings reveals true performance.

Misconception 3: "A sequential scan in the plan always means a missing index."
Reality: The planner chooses a sequential scan when it estimates the scan is cheaper than an index scan. For queries that return a large fraction of a table's rows, or for small tables where index overhead outweighs the benefit, a sequential scan is genuinely the right choice. The right question is whether the estimated row count matches the actual row count — a large gap indicates a statistics problem, not necessarily an index gap.

---

## Why It Matters in Practice

No performance investigation should begin with guessing. EXPLAIN ANALYZE provides the ground truth of what the database is actually doing. Every discussion of adding an index, rewriting a query, or changing a join type should start and end with EXPLAIN ANALYZE — start to understand the current plan, end to confirm the change had the intended effect.

The discrepancy between estimated and actual row counts is the single most actionable signal in EXPLAIN output. When the planner estimates 1 row and the query returns 50,000, the cost of downstream operations (sorts, joins, aggregates) is severely underestimated, and the planner may have chosen entirely wrong algorithms. Running ANALYZE on the table refreshes the statistics histogram that the planner uses for its estimates, and is often the first fix for plans that look wrong.

---

## What Breaks

**Destructive query run unintentionally with EXPLAIN ANALYZE.** A developer copies a DELETE statement from a bug report and adds EXPLAIN ANALYZE to "check the plan" without wrapping it in a transaction. The DELETE executes and removes production data.

```sql
-- Safe pattern for EXPLAIN ANALYZE on write statements
BEGIN;
EXPLAIN ANALYZE
DELETE FROM audit_log WHERE created_at < '2023-01-01';
-- Read the plan output
ROLLBACK;  -- data is restored
```

**Plan regression after a statistics update.** After running ANALYZE on a large table, the planner now has accurate row counts. A previously fast query used a nested loop join because the planner thought the inner table was small (stale statistics underestimated rows). With accurate statistics, the planner chooses a hash join — which requires more memory. If `work_mem` is insufficient, the hash join spills to disk and is slower than the old nested loop.

```sql
-- Identify which join type is now chosen
EXPLAIN (ANALYZE, BUFFERS) SELECT ... FROM large_table JOIN other_table ...;

-- If hash join is spilling to disk:
-- Look for "Batches: X" where X > 1 in the Hash node
-- Increase work_mem for this session if needed
SET work_mem = '256MB';
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;  -- re-check
```

**High Rows Removed by Filter indicating a missing index.** The Seq Scan node shows "Rows Removed by Filter: 4,800,000" while returning 3 rows. The filter is applying the WHERE clause row-by-row across the full table — a strong signal that an index on the filter column would reduce this to a direct lookup.

```sql
EXPLAIN ANALYZE SELECT * FROM events WHERE session_id = 'abc123';
-- Seq Scan on events ... rows=3 ...
--   Filter: (session_id = 'abc123')
--   Rows Removed by Filter: 4800000

-- Fix:
CREATE INDEX idx_events_session_id ON events(session_id);
```

---

## Interview Angle

Common question forms:
- "How do you diagnose a slow query in PostgreSQL?"
- "What is the difference between EXPLAIN and EXPLAIN ANALYZE?"
- "What does it mean when estimated rows and actual rows differ greatly in EXPLAIN output?"

Answer frame:
Start with the distinction: EXPLAIN shows the plan without executing; EXPLAIN ANALYZE executes and adds actual stats. Describe how to read a plan: bottom-up, each node's cost and row estimate, the key node types (Seq Scan, Index Scan, Index Only Scan, join types). Focus on the estimated-vs-actual row count discrepancy as the primary diagnostic signal — a large gap means stale statistics, which `ANALYZE` fixes. Mention the BUFFERS option for identifying disk I/O bottlenecks. Close with the safety note: EXPLAIN ANALYZE on write statements executes the write, so always wrap in a transaction and roll back.

---

## Related Notes

- [[sql-indexes|SQL Indexes]]
- [[composite-indexes|Composite Indexes]]
- [[covering-indexes|Covering Indexes]]
- [[query-optimization|Query Optimization]]
- [[b-tree-index|B-Tree Index Internals]]
