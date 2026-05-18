---
title: 18 - Aggregate Functions (COUNT, SUM, AVG, MIN, MAX)
description: Aggregate functions collapse multiple rows into a single scalar result, forming the foundation of every summary query in SQL.
tags: [sql, layer-9, aggregation, functions]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# Aggregate Functions (COUNT, SUM, AVG, MIN, MAX)

> Aggregate functions reduce a set of rows to a single value — understanding their NULL behavior and the COUNT(*) vs COUNT(col) distinction prevents entire classes of silent data errors.

---

## Quick Reference

**Core idea:**
- Aggregate functions operate on a set of rows and return one value per group (or one value for the whole table if no GROUP BY is present)
- COUNT(*) counts all rows including those with NULLs; COUNT(col) counts only non-NULL values in that column
- SUM and AVG silently ignore NULL values — they do not treat NULL as zero
- MIN and MAX work on numbers, dates, and text; on text they use collation order
- COUNT(DISTINCT col) counts unique non-NULL values
- The FILTER clause (PostgreSQL) enables conditional aggregation without CASE expressions

**Tricky points:**
- COUNT(*) and COUNT(1) are equivalent; COUNT(col) is not
- AVG(col) = SUM(col) / COUNT(col), not SUM(col) / COUNT(*) — NULLs shift the denominator
- A query with an aggregate but no GROUP BY collapses the entire result set to exactly one row
- MIN and MAX on text columns depend on the database collation, not alphabetical ASCII order
- Applying DISTINCT inside an aggregate (SUM(DISTINCT col)) is valid but rarely what you want

---

## What It Is

Think of aggregate functions the way you think of a spreadsheet's column formulas. When you have a spreadsheet with a thousand rows of sales data and you want a single cell showing the total revenue, you reach for SUM. When you need to know how many transactions occurred, you reach for COUNT. Aggregate functions in SQL perform exactly this kind of vertical collapse — they accept an entire column's worth of values (or a filtered subset of them) and produce one answer.

The five core aggregate functions divide neatly by what they measure. COUNT answers "how many?". SUM and AVG answer "how much in total?" and "what is the typical amount?". MIN and MAX answer "what are the extremes?". Despite their simplicity, each carries a specific rule about NULL values that changes the meaning of the result in ways that are easy to overlook.

NULL in SQL means the absence of a known value. It is not zero, not an empty string, not false. Every aggregate function except COUNT(*) skips NULL values when computing its result. This is deliberate — including an unknown value in a SUM would make the total unknown, so SQL simply excludes it. The consequence is that SUM, AVG, MIN, and MAX each act on the non-NULL subset of the column, and COUNT(*) is the only way to count every row regardless of what is in any particular column.

---

## How It Actually Works

When the database engine processes an aggregate function, it scans the rows in the current group (or the entire table if there is no GROUP BY), accumulates a running state, and emits the final result. For COUNT(*) the state is a simple integer that increments for every row encountered. For COUNT(col) the increment only happens when the column value is not NULL. For SUM the engine maintains a running total and adds each non-NULL value; NULLs are skipped silently.

```sql
-- COUNT(*) vs COUNT(col): the difference matters when col has NULLs
SELECT
    COUNT(*)          AS total_rows,          -- counts every row
    COUNT(email)      AS rows_with_email,     -- skips NULLs in email
    COUNT(DISTINCT email) AS unique_emails    -- unique non-NULL emails
FROM users;

-- AVG does NOT divide by COUNT(*): NULLs affect the denominator
SELECT
    SUM(score)              AS total_score,
    COUNT(score)            AS scored_count,   -- rows where score IS NOT NULL
    AVG(score)              AS avg_score,      -- = SUM(score)/COUNT(score)
    SUM(score) / COUNT(*)   AS naive_avg       -- WRONG if any score is NULL
FROM exam_results;
```

The FILTER clause in PostgreSQL allows conditional aggregation inline, without nesting CASE expressions inside the aggregate. It restricts which rows the aggregate sees, functioning as a per-aggregate WHERE clause.

```sql
-- Conditional aggregation with FILTER (PostgreSQL)
SELECT
    COUNT(*)                                      AS total_orders,
    COUNT(*) FILTER (WHERE status = 'completed')  AS completed_orders,
    SUM(amount) FILTER (WHERE status = 'completed') AS completed_revenue,
    AVG(amount) FILTER (WHERE region = 'EU')      AS eu_avg_amount
FROM orders;

-- Equivalent using CASE (works in all databases)
SELECT
    COUNT(*) AS total_orders,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) AS completed_orders,
    SUM(CASE WHEN status = 'completed' THEN amount END) AS completed_revenue
FROM orders;
```

MIN and MAX accept any orderable data type. On text columns the result depends on the collation in effect for the database or column. On date columns they return the earliest and latest dates. Neither function has special NULL behavior beyond the standard rule — NULLs are excluded from the comparison.

```sql
-- MIN and MAX across types
SELECT
    MIN(created_at) AS first_signup,
    MAX(created_at) AS latest_signup,
    MIN(username)   AS alphabetically_first,   -- collation-dependent
    MAX(price)      AS most_expensive
FROM products;
```

---

## How It Connects

Aggregate functions become far more powerful once paired with GROUP BY, which partitions rows into subgroups before the aggregate is applied. Without GROUP BY, every aggregate returns a single row for the whole table — which is sometimes exactly what is needed, but rarely the full picture.

Filtering on the results of aggregate functions cannot be done with WHERE; that is the job of the HAVING clause, which is evaluated after grouping and aggregation are complete.

Window functions extend the aggregation concept by computing aggregates across a window of rows without collapsing the result set, making it possible to compute running totals or partition-level counts while preserving every individual row.

[[group-by|GROUP BY]]
[[having-clause|HAVING Clause]]
[[window-functions|Window Functions]]

---

## Common Misconceptions

Misconception 1: "COUNT(*) is slower than COUNT(1) or COUNT(col) because it reads every column."
Reality: COUNT(*) does not instruct the engine to read every column's data. It is a syntactic form meaning "count rows." Modern query optimizers treat COUNT(*) and COUNT(1) identically, often using the smallest available index to count rows without reading column data at all.

Misconception 2: "AVG handles NULLs the same way SUM does — both just skip them."
Reality: Skipping NULLs in SUM is harmless because you are only summing known values. Skipping NULLs in AVG changes the denominator. If 3 out of 10 rows have a NULL score, AVG divides by 7, not 10. This produces a higher average than if the NULLs were treated as zero. Whether that is correct depends on the business definition — sometimes you want AVG(COALESCE(score, 0)) to treat NULLs as zero.

Misconception 3: "You can use an aggregate function directly in a WHERE clause."
Reality: WHERE is evaluated before aggregation occurs, so the aggregate result does not yet exist at that stage. The database engine will raise an error. Aggregate filters must be placed in HAVING, or the query must be restructured using a subquery or CTE.

---

## Why It Matters in Practice

Aggregate functions are in virtually every production query that produces reports, dashboards, or summary data. Revenue totals, user counts, average session durations, min/max timestamps — all of these require aggregation. Getting COUNT(*) vs COUNT(col) wrong produces subtly incorrect row counts when any nullable column is involved, a mistake that often goes undetected until a data audit surfaces the discrepancy.

The NULL behavior of SUM and AVG is particularly consequential in financial systems. If a payment amount column has unexpected NULLs due to a data import error, SUM silently underreports total revenue and AVG reports a higher-than-true average. Defensive queries use COUNT(*) alongside COUNT(amount) to detect NULL presence, and COALESCE to apply a known default when appropriate.

---

## What Breaks

**Scenario 1: NULL amounts inflate AVG.**
A sales table has 1,000 rows. A batch import leaves amount as NULL for 200 rows. AVG(amount) divides the sum of 800 values by 800, reporting a misleadingly high average. A monitoring query comparing COUNT(*) to COUNT(amount) would have flagged the discrepancy immediately.

```sql
-- Defensive check for NULL presence before trusting AVG
SELECT
    COUNT(*) AS total_rows,
    COUNT(amount) AS non_null_rows,
    COUNT(*) - COUNT(amount) AS null_count,
    AVG(amount) AS avg_ignoring_nulls,
    AVG(COALESCE(amount, 0)) AS avg_treating_null_as_zero
FROM sales;
```

**Scenario 2: Aggregate in WHERE crashes the query.**
A developer writes `WHERE COUNT(*) > 100` to filter high-volume accounts. The database raises a syntax error because the aggregate is evaluated after WHERE. The fix is to move the condition to HAVING or use a subquery.

```sql
-- Wrong
SELECT account_id FROM transactions WHERE COUNT(*) > 100 GROUP BY account_id;

-- Correct
SELECT account_id FROM transactions GROUP BY account_id HAVING COUNT(*) > 100;
```

**Scenario 3: COUNT(DISTINCT col) on a high-cardinality column is slow.**
COUNT(DISTINCT user_id) on a table with 500 million rows requires sorting or hashing the entire column to find unique values. On large tables this can be orders of magnitude slower than COUNT(*). For approximate counts, PostgreSQL's HyperLogLog extension or the approx_count_distinct function in analytical databases is the appropriate tool.

---

## Interview Angle

Common question forms:
- "What is the difference between COUNT(*) and COUNT(column)?"
- "How does AVG handle NULL values?"
- "Why can't I use an aggregate function in a WHERE clause?"

Answer frame:
Start with the fundamental rule: aggregate functions reduce multiple rows to one value and skip NULLs (except COUNT(*)). Explain that COUNT(*) counts rows unconditionally while COUNT(col) counts only non-NULL values in that column. For the WHERE question, explain the SQL logical execution order — WHERE runs before grouping, so the aggregate result does not exist yet; HAVING is the correct clause for post-aggregation filtering. Concrete examples with a small sample data set showing the difference when NULLs are present will distinguish a thorough answer from a shallow one.

---

## Related Notes

- [[group-by|GROUP BY]]
- [[having-clause|HAVING Clause]]
- [[window-functions|Window Functions]]
- [[select-basics|SELECT Basics]]
- [[where-clause|WHERE Clause]]
