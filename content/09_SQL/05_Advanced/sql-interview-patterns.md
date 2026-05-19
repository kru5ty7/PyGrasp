---
title: 45 - SQL Interview Patterns
description: The canonical SQL interview problem patterns and the query structure to solve each one.
tags: [sql, layer-9, interviews, patterns, window-functions, cte]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# SQL Interview Patterns

> SQL interviews recycle seven patterns endlessly - learn the pattern, not the problem, and any variation becomes recognisable on sight.

---

## Quick Reference

**Core idea:**
- Most SQL interview questions are variations of seven canonical patterns
- Each pattern has a reusable query skeleton that adapts to the specific schema
- Window functions solve the majority of intermediate-to-hard patterns
- CTEs make multi-step patterns readable and debuggable
- The "find records with no match" pattern trips up even experienced developers

**Tricky points:**
- NOT IN with a subquery that can return NULLs silently returns no rows - use NOT EXISTS instead
- "Top N per group" requires ROW_NUMBER() inside a subquery or CTE; you cannot filter on a window function in the same SELECT
- RANK() vs ROW_NUMBER() for top-N gives different results when there are ties - know which one the question wants
- "Running total" with SUM() OVER (ORDER BY ...) uses a default frame that can surprise you with RANGE semantics on duplicate values
- COUNT(*) counts all rows; COUNT(col) skips NULLs - the distinction matters for pattern 1

---

## What It Is

Imagine a chef who memorises a hundred recipes. When a customer asks for "something with chicken and lemon", the chef does not invent from scratch - they recognise it as a variation of the roast chicken template, adjust for the lemon, and execute. SQL interviews work the same way. The problems look unique but they are almost always variations of a small set of structural patterns. A developer who knows the patterns can parse any variation in seconds; a developer who tries to reason from first principles under interview pressure is at a serious disadvantage.

The seven patterns cover the questions that appear in the vast majority of SQL interview rounds - from junior backend roles to senior data engineering positions. The patterns are: find duplicates, rank or top-N globally, top-N per group, running aggregates, find records with no match, self-referential hierarchy traversal, and gaps and islands in sequences or time series. Each pattern has a definitive query shape built on the same SQL features you have already studied - GROUP BY, window functions, CTEs, JOINs, and subqueries.

The goal of this note is not to teach you SQL features - you have seven previous sections for that. The goal is to hand you the skeleton for each pattern so that when an interviewer says "find the second highest salary in each department", you instantly recognise it as the top-N-per-group pattern, slot in the schema, and write the query without hesitation.

---

## How It Actually Works

**Pattern 1 - Find duplicates**

Find rows where a value appears more than once. The skeleton: GROUP BY the column of interest, then filter with HAVING COUNT(*) > 1.

```sql
-- Find all email addresses registered more than once
SELECT email, COUNT(*) AS occurrences
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- Find the full rows for those duplicates
SELECT *
FROM users
WHERE email IN (
    SELECT email
    FROM users
    GROUP BY email
    HAVING COUNT(*) > 1
);
```

---

**Pattern 2 - Nth highest value (global)**

Find the second, third, or Nth highest value across the whole table. The skeleton: ROW_NUMBER() or DENSE_RANK() over the full set, wrap in a CTE, filter on the rank.

```sql
-- Second highest salary (any department)
WITH ranked AS (
    SELECT
        employee_id,
        name,
        salary,
        DENSE_RANK() OVER (ORDER BY salary DESC) AS rnk
    FROM employees
)
SELECT employee_id, name, salary
FROM ranked
WHERE rnk = 2;
```

Use DENSE_RANK() when ties should share a rank (1, 1, 2, 3). Use ROW_NUMBER() when you want exactly one row regardless of ties.

---

**Pattern 3 - Top N per group**

Find the top N records within each category (e.g. top 3 earners per department). This is the most common advanced pattern. The skeleton: ROW_NUMBER() OVER (PARTITION BY group ORDER BY value DESC), wrap in CTE, filter on row_number <= N.

```sql
-- Top 3 earners per department
WITH ranked AS (
    SELECT
        employee_id,
        name,
        department_id,
        salary,
        ROW_NUMBER() OVER (
            PARTITION BY department_id
            ORDER BY salary DESC
        ) AS rn
    FROM employees
)
SELECT employee_id, name, department_id, salary
FROM ranked
WHERE rn <= 3;
```

You cannot put the WHERE rn <= 3 in the same SELECT as the window function - the window function is computed after WHERE. The CTE wrapper is required.

---

**Pattern 4 - Running aggregates**

Compute a cumulative sum, running average, or rolling window. The skeleton: SUM() or AVG() with OVER (ORDER BY ...) and optionally a frame clause.

```sql
-- Running total of daily revenue
SELECT
    sale_date,
    revenue,
    SUM(revenue) OVER (ORDER BY sale_date) AS running_total,
    AVG(revenue) OVER (
        ORDER BY sale_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7day_avg
FROM daily_sales
ORDER BY sale_date;
```

The default frame for ORDER BY is RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW. On dates with duplicate values this can include more rows than you expect - use ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW for strict row counting.

---

**Pattern 5 - Find records with no match**

Find rows in table A that have no corresponding row in table B. Three equivalent approaches with different safety profiles.

```sql
-- Customers who have never placed an order

-- Approach 1: LEFT JOIN anti-join (most readable)
SELECT c.customer_id, c.name
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.customer_id IS NULL;

-- Approach 2: NOT EXISTS (safest - handles NULLs correctly)
SELECT customer_id, name
FROM customers c
WHERE NOT EXISTS (
    SELECT 1 FROM orders o
    WHERE o.customer_id = c.customer_id
);

-- Approach 3: NOT IN (DANGEROUS if orders.customer_id can be NULL)
-- If any row in orders has customer_id = NULL, this returns zero rows
SELECT customer_id, name
FROM customers
WHERE customer_id NOT IN (SELECT customer_id FROM orders);
```

Prefer NOT EXISTS or the LEFT JOIN approach. NOT IN is a trap when the subquery can return NULL.

---

**Pattern 6 - Hierarchical traversal**

Walk a parent-child relationship stored in the same table (org charts, category trees). The skeleton: recursive CTE with anchor (root nodes) and recursive member (children).

```sql
-- All reports under a given manager (full org subtree)
WITH RECURSIVE org AS (
    -- Anchor: the starting employee
    SELECT employee_id, name, manager_id, 0 AS depth
    FROM employees
    WHERE employee_id = 5   -- start node

    UNION ALL

    -- Recursive: find direct reports of the current level
    SELECT e.employee_id, e.name, e.manager_id, org.depth + 1
    FROM employees e
    INNER JOIN org ON e.manager_id = org.employee_id
)
SELECT employee_id, name, depth
FROM org
ORDER BY depth, name;
```

Add a depth limit (WHERE depth < 20) or use the PostgreSQL 14 CYCLE clause to guard against circular references.

---

**Pattern 7 - Gaps and islands**

Identify consecutive sequences (islands) and breaks in the sequence (gaps). Classic use case: find periods of continuous user activity, or find missing IDs in a sequence.

```sql
-- Find gaps in a sequential order_id column
SELECT
    prev_id + 1   AS gap_start,
    curr_id - 1   AS gap_end,
    curr_id - prev_id - 1 AS gap_size
FROM (
    SELECT
        order_id AS curr_id,
        LAG(order_id) OVER (ORDER BY order_id) AS prev_id
    FROM orders
) t
WHERE curr_id - prev_id > 1;

-- Find islands of consecutive login days per user
WITH numbered AS (
    SELECT
        user_id,
        login_date,
        login_date - INTERVAL '1 day' * ROW_NUMBER() OVER (
            PARTITION BY user_id ORDER BY login_date
        ) AS island_key
    FROM (SELECT DISTINCT user_id, login_date FROM logins) t
)
SELECT
    user_id,
    MIN(login_date) AS streak_start,
    MAX(login_date) AS streak_end,
    COUNT(*)        AS streak_length
FROM numbered
GROUP BY user_id, island_key
ORDER BY user_id, streak_start;
```

The islands pattern relies on the fact that subtracting a row number from a date produces the same value for all consecutive dates - any gap breaks the sequence and produces a different constant.

---

## How It Connects

The top-N-per-group and running aggregate patterns both depend on window functions. Understanding the OVER clause, PARTITION BY, and frame semantics is essential before these patterns feel natural.

[[window-functions|Window Functions]]

The hierarchical traversal pattern requires recursive CTEs. The anchor-plus-recursive structure and the CYCLE clause are covered in detail there.

[[recursive-cte|Recursive CTEs]]

The anti-join pattern (find records with no match) connects directly to the NULL handling behaviour of NOT IN. Understanding three-valued logic and why NULL = NULL is always unknown makes the NOT EXISTS preference obvious.

[[subqueries|Subqueries]]

The duplicate-finding pattern uses GROUP BY and HAVING, which are the post-aggregation filtering tools.

[[having-clause|HAVING Clause]]

---

## Common Misconceptions

Misconception 1: "NOT IN is equivalent to NOT EXISTS."
Reality: NOT IN and NOT EXISTS produce the same result only when the subquery column is guaranteed NOT NULL. If any row in the subquery returns NULL, NOT IN returns no rows at all - because NULL is unknown, and x NOT IN (..., NULL, ...) evaluates to unknown for every x. NOT EXISTS short-circuits on a match and never returns NULL, making it safe in all cases.

Misconception 2: "I can filter on a window function result in the same WHERE clause."
Reality: Window functions are computed after WHERE and GROUP BY but before the final SELECT output. You cannot write WHERE row_number <= 3 in the same query body that defines row_number. The standard fix is to define the window function in a CTE or subquery and then filter on it in an outer query.

Misconception 3: "RANK() and ROW_NUMBER() are interchangeable for top-N queries."
Reality: ROW_NUMBER() assigns unique sequential numbers regardless of ties - if two employees have the same salary, one gets rank 1 and the other gets rank 2 arbitrarily. RANK() assigns the same number to ties and skips the next rank (1, 1, 3). DENSE_RANK() assigns the same number to ties without skipping (1, 1, 2). For "top 1 per group" queries, the choice only matters when ties exist - and which function is correct depends entirely on the business requirement.

---

## Why It Matters in Practice

These seven patterns cover the majority of ad-hoc analytics queries, data quality checks, and business reporting queries that appear in day-to-day backend and data engineering work - not just interviews. A developer who recognises the top-N-per-group shape can write a clean window function query in two minutes rather than spending thirty minutes reasoning through a nested subquery approach. The gap-and-islands pattern solves session analysis, fraud detection, and availability monitoring - it appears constantly in analytics work.

Knowing the patterns also makes code review faster. When you see a correlated subquery in production code, you can immediately identify whether it is a poorly-written top-N or anti-join pattern and propose the window function or LEFT JOIN rewrite.

---

## What Breaks

**NOT IN with a nullable subquery returns zero rows silently.** A query like `SELECT * FROM customers WHERE id NOT IN (SELECT customer_id FROM orders)` returns no rows if even one order has a NULL customer_id. This does not error - it silently returns an empty result. In production, this means a report that should list unmatched customers returns nothing, and without careful testing the bug goes unnoticed.

```sql
-- Reproducing the trap
CREATE TABLE orders (id INT, customer_id INT);
INSERT INTO orders VALUES (1, 10), (2, NULL);  -- one null

-- Returns zero rows - NOT IN with NULL poisons the set
SELECT * FROM customers WHERE customer_id NOT IN (
    SELECT customer_id FROM orders
);

-- Fix: use NOT EXISTS
SELECT * FROM customers c WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id
);
```

**Missing CTE wrapper for window function filtering causes a syntax error.** Placing `WHERE row_number <= 3` in the same SELECT that computes `ROW_NUMBER() OVER (...)` raises an error. The fix is always to move the window function to a CTE and filter in the outer SELECT.

---

## Interview Angle

Common question forms:
- "Find the second highest salary in the employees table."
- "Find the top 3 earners in each department."
- "Write a query to find all customers who have never placed an order."
- "Find all duplicate email addresses in the users table."
- "Calculate a 7-day rolling average of daily revenue."
- "Find the longest consecutive login streak for each user."

Answer frame:
Identify which of the seven patterns the question maps to. State the pattern name aloud ("this is a top-N-per-group pattern"). Write the CTE skeleton with the window function or anti-join, then fill in the column names from the given schema. Call out any edge cases - ties in rankings, NULL handling in anti-joins, frame semantics in running aggregates. For recursive questions, mention cycle detection. Keep the solution readable: name CTEs descriptively, avoid deeply nested subqueries.

---

## Related Notes

- [[window-functions|Window Functions]]
- [[rank-and-row-number|RANK, DENSE_RANK, ROW_NUMBER]]
- [[cte|Common Table Expressions (CTEs)]]
- [[recursive-cte|Recursive CTEs]]
- [[subqueries|Subqueries]]
- [[correlated-subqueries|Correlated Subqueries]]
- [[having-clause|HAVING Clause]]
- [[group-by|GROUP BY]]
