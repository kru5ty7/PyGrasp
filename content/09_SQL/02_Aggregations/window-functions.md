---
title: 21 - Window Functions
description: Window functions compute aggregate-like values across a defined set of rows relative to the current row without collapsing the result set, enabling running totals, rankings, and moving averages in a single query.
tags: [sql, layer-9, window-functions, analytics]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# Window Functions

> Window functions give every row a view of its neighbors — they compute values across related rows without eliminating any row from the result, solving an entire category of problems that previously required self-joins or correlated subqueries.

---

## Quick Reference

**Core idea:**
- A window function computes its value for each row based on a set of rows defined by the OVER() clause — the "window"
- PARTITION BY divides rows into independent partitions (like GROUP BY but without collapsing rows)
- ORDER BY inside OVER() sets the ordering within each partition and implicitly defines a running frame
- Frame clauses (ROWS BETWEEN, RANGE BETWEEN) explicitly control which rows are included in the window for each current row
- Window functions are evaluated after WHERE, GROUP BY, and HAVING, but before ORDER BY and LIMIT
- Common window functions: SUM, AVG, COUNT, MIN, MAX (aggregate variants), RANK, DENSE_RANK, ROW_NUMBER, LAG, LEAD, NTILE, PERCENT_RANK

**Tricky points:**
- Window functions cannot appear in WHERE or HAVING because they are evaluated after those clauses; wrap the query in a CTE or subquery to filter on window function results
- An empty OVER() clause (no PARTITION BY, no ORDER BY) means the window is the entire result set
- ORDER BY inside OVER() with no explicit frame defaults to RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW — this is not the same as ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW when there are ties
- PARTITION BY and GROUP BY can coexist in the same query — they operate independently
- Window functions do not filter rows; all rows remain in the output

---

## What It Is

Picture a long train. Each passenger in each seat can look out the window and see the carriages ahead and behind them. The view each passenger has is relative to their own position — the passenger in seat 5 has a different set of visible carriages than the passenger in seat 20. Crucially, no passengers are removed from the train just because someone looked out a window. Window functions in SQL work exactly this way. Each row in the result gets to "look at" a defined neighborhood of rows and compute a value based on what it sees. The rows themselves are never collapsed or removed.

This is the fundamental difference from GROUP BY aggregation. GROUP BY destroys the individual row identity — you get one row per group, period. Window functions preserve every row and attach an extra computed column to each one. A SUM(amount) OVER (PARTITION BY customer_id ORDER BY created_at) gives you a running total of each customer's spending that grows row by row through their order history, while still showing you each individual order.

The OVER() clause is what transforms an otherwise ordinary aggregate function (or a dedicated window function like RANK or LAG) into a window function. Everything that matters about how the window is defined lives inside that OVER() clause: the PARTITION BY sub-clause that splits rows into independent groups, the ORDER BY sub-clause that determines the ordering within each partition, and the optional frame clause that specifies exactly which rows around the current row are included in the window calculation.

Before window functions existed in SQL, achieving running totals or per-group rankings required either self-joins (joining a table back to itself to count how many rows precede the current one) or correlated subqueries (a subquery in the SELECT list that re-executes for every row). Both approaches are orders of magnitude slower than a window function on large tables and far harder to read. Window functions replaced both patterns and are now the idiomatic SQL solution for any problem that requires awareness of row order or neighborhood.

---

## How It Actually Works

The OVER() clause is parsed into three optional components: PARTITION BY, ORDER BY, and the frame specification. If PARTITION BY is present, rows are divided into independent partitions and the window function resets for each partition. If ORDER BY is present within OVER(), the window has a meaningful sequence within each partition. The frame clause then defines the precise bounds of the window relative to the current row.

```sql
-- Running total of amount per customer, ordered by date
SELECT
    order_id,
    customer_id,
    amount,
    created_at,
    SUM(amount) OVER (
        PARTITION BY customer_id
        ORDER BY created_at
    ) AS running_total
FROM orders;
```

When ORDER BY is present inside OVER() with no explicit frame clause, most databases default to `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. The RANGE frame mode includes all rows with the same ORDER BY value as the current row in the "current" position. This can cause surprising behavior with ties: two rows with the same date both get a running total that already includes the other's amount. Using `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` instead processes rows physically one by one, which is usually the intended behavior for running totals.

```sql
-- Explicit frame to avoid tie ambiguity in running total
SELECT
    order_id,
    amount,
    SUM(amount) OVER (
        ORDER BY created_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM orders;

-- Moving 7-day average (window: 3 preceding rows and 3 following rows)
SELECT
    sale_date,
    daily_revenue,
    AVG(daily_revenue) OVER (
        ORDER BY sale_date
        ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING
    ) AS moving_avg_7day
FROM daily_sales;
```

LAG and LEAD are window functions that access a different row's value relative to the current row — LAG looks backward, LEAD looks forward. Both accept an optional offset (default 1) and a default value for when the offset goes out of bounds.

```sql
-- Compare each day's revenue to the previous day
SELECT
    sale_date,
    daily_revenue,
    LAG(daily_revenue, 1, 0) OVER (ORDER BY sale_date) AS prev_day_revenue,
    daily_revenue - LAG(daily_revenue, 1, 0) OVER (ORDER BY sale_date) AS day_over_day_change
FROM daily_sales;
```

NTILE(n) divides the rows within a partition into n roughly equal buckets and assigns each row a bucket number, which is useful for percentile breakdowns.

```sql
-- Divide customers into four quartiles by total spend
SELECT
    customer_id,
    total_spent,
    NTILE(4) OVER (ORDER BY total_spent) AS quartile
FROM (
    SELECT customer_id, SUM(amount) AS total_spent FROM orders GROUP BY customer_id
) AS customer_totals;
```

Because window functions are evaluated after WHERE, GROUP BY, and HAVING, they cannot be filtered directly. The standard solution is to wrap the query in a CTE or subquery and filter in the outer query.

```sql
-- Filter on a window function result using a CTE
WITH ranked_orders AS (
    SELECT
        order_id,
        customer_id,
        amount,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
)
SELECT order_id, customer_id, amount
FROM ranked_orders
WHERE rn = 1;    -- top order per customer by amount
```

---

## How It Connects

Window functions are built on the same aggregation concepts as GROUP BY queries. Functions like SUM, AVG, COUNT, MIN, and MAX behave the same way inside OVER() as they do with GROUP BY — the difference is that the result is returned per row rather than per group. Understanding how those aggregate functions handle NULLs is just as important in the window context.

RANK, DENSE_RANK, and ROW_NUMBER are specialized window functions for assigning ordinal positions within a partition. They share the OVER() clause syntax but have specific tie-handling behaviors that are important to know independently.

CTEs are frequently paired with window functions. Computing a window function in a CTE and then filtering in the outer query is the standard pattern for any query that needs to filter on a window function result, because the window function cannot appear in WHERE or HAVING directly.

[[rank-and-row-number|RANK, DENSE_RANK, ROW_NUMBER]]
[[cte|Common Table Expressions (CTEs)]]
[[aggregate-functions|Aggregate Functions]]
[[group-by|GROUP BY]]

---

## Common Misconceptions

Misconception 1: "PARTITION BY in a window function is just another way to write GROUP BY."
Reality: PARTITION BY divides rows into partitions so the window function resets per partition, but it does not collapse rows. The query still returns every row. GROUP BY collapses rows so the output has one row per group. They serve entirely different purposes and can coexist in the same query.

Misconception 2: "I can use a window function result directly in a WHERE clause."
Reality: Window functions are evaluated after WHERE and HAVING in the logical execution order. At the time WHERE is evaluated, the window function values do not yet exist. The result is a syntax or semantic error. The correct approach is to compute the window function in a CTE or subquery and apply the filter in the outer query's WHERE clause.

Misconception 3: "ORDER BY inside OVER() is the same as the query-level ORDER BY."
Reality: ORDER BY inside OVER() controls the order of rows within each window partition for purposes of frame calculation. It has no effect on the order of rows returned by the query. The query-level ORDER BY controls the output row order. Both can coexist and can specify different columns.

Misconception 4: "An empty OVER() clause means the function applies to nothing."
Reality: An empty OVER() — written as just OVER() — means the window is the entire result set, with no partitioning and no ordering. SUM(amount) OVER () returns the grand total of all amounts for every row, not zero rows.

---

## Why It Matters in Practice

Window functions are the single most powerful addition to SQL that most developers learn too late. Any query involving running totals, per-group rankings, percentile assignments, period-over-period comparisons, or first/last values within a group can be written as a single clean window function query. The alternatives — self-joins and correlated subqueries — are not just harder to read; they are dramatically slower because they force repeated full or partial table scans.

In analytical and reporting contexts, window functions are indispensable. A query that computes each customer's lifetime value as a running total, flags each customer's most recent order, assigns percentile rankings to products by revenue, and computes week-over-week growth — all in a single query — is straightforward with window functions and nearly unwritable in a maintainable form without them.

---

## What Breaks

**Scenario 1: Frame default causes wrong running total on ties.**
A running total over a date column uses the default RANGE frame. Two orders on the same date both receive a running total that includes both amounts, as if both orders were already complete when either is processed. This inflates intermediate totals. Switching to ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW processes rows one at a time and produces the correct monotonically increasing total.

```sql
-- Potentially wrong with tied dates
SELECT order_id, SUM(amount) OVER (ORDER BY created_at) AS running_total FROM orders;

-- Correct: explicit ROWS frame
SELECT order_id, SUM(amount) OVER (ORDER BY created_at ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total FROM orders;
```

**Scenario 2: Filtering on window function result fails.**
A developer tries `WHERE ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at) = 1` directly in a query. The database raises an error because the window function has not been computed when WHERE is evaluated. Wrapping the window function in a CTE solves the problem.

**Scenario 3: Large partition with unbounded frame causes memory pressure.**
A window function with `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` over an unpartitioned 100-million-row table requires the database to buffer the entire table in memory. Proper PARTITION BY clauses reduce the maximum partition size the database must hold at once and are essential for window functions on large tables.

---

## Interview Angle

Common question forms:
- "What is a window function and how is it different from GROUP BY?"
- "Explain the OVER() clause and its components."
- "How would you compute a running total in SQL?"
- "Why can't you filter on a window function in a WHERE clause?"

Answer frame:
Open with the key distinction: window functions compute across a set of rows without collapsing them, unlike GROUP BY which eliminates individual row identity. Explain the OVER() clause by its three components: PARTITION BY (resets the window per partition), ORDER BY (orders rows within the partition for frame calculation), and the optional frame specification (ROWS or RANGE bounds). For the running total question, write the SUM with ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW. For the WHERE question, explain execution order — window functions run after WHERE, so filter by wrapping in a CTE.

---

## Related Notes

- [[rank-and-row-number|RANK, DENSE_RANK, ROW_NUMBER]]
- [[cte|Common Table Expressions (CTEs)]]
- [[aggregate-functions|Aggregate Functions]]
- [[group-by|GROUP BY]]
- [[having-clause|HAVING Clause]]
