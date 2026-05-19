---
title: 20 - HAVING Clause
description: HAVING filters groups after aggregation, filling the role WHERE cannot play when the filter condition references an aggregate result.
tags: [sql, layer-9, filtering, aggregation]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# HAVING Clause

> HAVING is the post-aggregation filter - it is the only place in a standard SQL query where an aggregate function can appear as a filter condition, and misplacing aggregate filters in WHERE is one of the most common beginner errors in SQL.

---

## Quick Reference

**Core idea:**
- HAVING filters groups produced by GROUP BY, just as WHERE filters rows produced by FROM
- Aggregate functions (COUNT, SUM, AVG, etc.) are valid in HAVING because aggregation has already completed by the time HAVING runs
- WHERE is evaluated before GROUP BY; HAVING is evaluated after GROUP BY
- A query can use HAVING without GROUP BY - it then filters the single aggregate row that would result from the whole table
- HAVING can reference both grouping column values and aggregate results in the same condition
- Conditions that do not involve aggregates should be placed in WHERE for performance, not HAVING

**Tricky points:**
- Placing a non-aggregate filter in HAVING instead of WHERE is legal but inefficient - HAVING runs after grouping, so the database processes more rows than necessary
- Some databases allow using SELECT aliases in HAVING; most do not because HAVING runs before SELECT in the logical order
- HAVING without GROUP BY is valid - it applies to the implicit single group that covers the whole table
- Multiple HAVING conditions can be combined with AND and OR, like WHERE
- HAVING can be the sole cause of an empty result set if all groups are filtered out

---

## What It Is

Think about how a librarian organizes returned books. First, books are sorted into shelves by category (GROUP BY). Then the librarian applies the filter: "only keep categories with more than ten books" (HAVING). The filter is applied to the shelves after they have been assembled - it would be impossible to apply it before, because the count per category does not exist until the sorting is done. WHERE is the filter applied to individual books before sorting them into categories. HAVING is the filter applied to entire shelves after the sorting is complete.

This timing distinction is not arbitrary - it reflects how a relational database physically processes a query. The engine must accumulate all the rows in a group and compute the aggregate before it can evaluate whether that group satisfies a condition like COUNT(*) > 10. There is no way for WHERE to do this work, because WHERE fires row by row before groups exist.

The practical rule is straightforward: if a filter condition references an aggregate function, it belongs in HAVING. If a filter condition references raw column values (regardless of whether the query also has a GROUP BY), it belongs in WHERE. Following this rule not only keeps queries syntactically correct - it also ensures the database can push row-level filters down to the earliest possible stage in execution, which is often the difference between a millisecond query and a multi-second one.

---

## How It Actually Works

The SQL logical execution order for a query with both WHERE and HAVING is: FROM, JOIN, WHERE, GROUP BY, aggregation, HAVING, SELECT, ORDER BY. WHERE evaluates before grouping; by the time HAVING evaluates, every group exists and every aggregate value has been computed. HAVING then discards groups whose conditions evaluate to false, and SELECT formats the surviving groups into output rows.

```sql
-- Classic use: keep only categories with more than 5 orders
SELECT category, COUNT(*) AS order_count
FROM orders
GROUP BY category
HAVING COUNT(*) > 5;

-- HAVING on a sum: keep only customers who spent more than $1000 total
SELECT customer_id, SUM(amount) AS total_spent
FROM orders
GROUP BY customer_id
HAVING SUM(amount) > 1000
ORDER BY total_spent DESC;
```

Because HAVING runs after GROUP BY, it has access to both the grouping column values and the computed aggregates. A HAVING clause can combine both in the same expression.

```sql
-- HAVING filtering on both a group column and an aggregate
SELECT region, COUNT(*) AS order_count, AVG(amount) AS avg_amount
FROM orders
WHERE created_at >= '2025-01-01'       -- pre-group filter: reduces rows first
GROUP BY region
HAVING COUNT(*) > 100                  -- post-group filter: keeps busy regions
   AND AVG(amount) > 50;              -- and regions with a meaningful average
```

The performance distinction between WHERE and HAVING matters most on large tables. WHERE reduces the working set before grouping; HAVING reduces the output after grouping. Filtering 900,000 rows out of a million-row table in WHERE means the grouping step processes only 100,000 rows. Filtering the same rows in HAVING means the grouping step processes all one million rows and then discards most of the resulting groups.

```sql
-- Inefficient: HAVING filters a non-aggregate condition
SELECT region, COUNT(*) FROM orders
GROUP BY region
HAVING region = 'EU';          -- groups all regions, then discards all but EU

-- Efficient: WHERE filters the non-aggregate condition first
SELECT region, COUNT(*) FROM orders
WHERE region = 'EU'            -- only EU rows reach the GROUP BY step
GROUP BY region;
```

HAVING without GROUP BY is a valid edge case. Without GROUP BY the entire table is treated as one group. HAVING then filters that single group.

```sql
-- HAVING without GROUP BY: effectively a guard on the whole table's aggregate
SELECT SUM(amount) AS total
FROM orders
HAVING SUM(amount) > 1000000;
-- Returns the total only if it exceeds the threshold; returns no rows otherwise
```

---

## How It Connects

HAVING cannot exist in isolation from aggregation - it is only meaningful in the context of GROUP BY or a whole-table aggregate. Understanding what GROUP BY does and how aggregate functions behave with NULL values is prerequisite knowledge for using HAVING correctly.

WHERE and HAVING are complementary, not competing. A well-written aggregate query uses WHERE to reduce the working set and HAVING to filter on computed aggregate results. Knowing when each applies comes down to whether the condition references a raw column or a computed aggregate.

Window functions provide a different approach to filtering aggregate-like conditions. A window function computed in a CTE or subquery can be referenced in an outer WHERE clause, which sometimes produces cleaner or more readable queries than HAVING.

[[group-by|GROUP BY]]
[[aggregate-functions|Aggregate Functions]]
[[where-clause|WHERE Clause]]
[[window-functions|Window Functions]]

---

## Common Misconceptions

Misconception 1: "I can use a WHERE clause with an aggregate function if I just write it correctly."
Reality: No syntactic arrangement makes an aggregate function valid in a WHERE clause. WHERE is evaluated before GROUP BY and aggregation, so no aggregate value exists at the time WHERE runs. The database engine will raise an error. Aggregate conditions must be in HAVING or in an outer query that wraps the aggregation.

Misconception 2: "HAVING is just a stricter or fancier version of WHERE - they do the same thing."
Reality: They operate at completely different stages of query execution and on completely different things. WHERE operates on individual rows before groups are formed. HAVING operates on entire groups after aggregation. A condition like `amount > 100` in WHERE removes individual rows where amount is below the threshold; the same condition in HAVING would not make semantic sense because HAVING expects group-level quantities.

Misconception 3: "Moving a filter from WHERE to HAVING makes no functional difference, only a style difference."
Reality: Moving a non-aggregate filter condition from WHERE to HAVING is a correctness-preserving but performance-degrading transformation. The query returns the same rows, but the database does more work because it groups all rows before discarding the unwanted ones. On large tables this can turn a fast query into a slow one.

---

## Why It Matters in Practice

HAVING appears in nearly every analytical query that surfaces a subset of groups above or below a threshold. Queries like "show me all customers who placed more than 10 orders" or "which products have an average review score below 3.0" cannot be written without HAVING. These patterns are fundamental to business reporting, anomaly detection, and data quality checks.

The WHERE vs HAVING performance distinction becomes significant at scale. An analytics database scanning hundreds of millions of rows benefits enormously from WHERE predicates that reduce the scan early. A developer who habitually puts all filters in HAVING - because it avoids the mental overhead of remembering the execution order - will produce queries that are needlessly slow on any table larger than a few thousand rows.

---

## What Breaks

**Scenario 1: Aggregate condition in WHERE causes a syntax error.**
A developer writes `WHERE COUNT(*) > 5` expecting it to filter groups. The database raises an error because COUNT(*) cannot be evaluated before grouping occurs. Moving the condition to HAVING fixes the query.

```sql
-- Broken: aggregate in WHERE
SELECT category, COUNT(*) FROM orders
WHERE COUNT(*) > 5
GROUP BY category;
-- ERROR: aggregate functions are not allowed in WHERE

-- Fixed: aggregate in HAVING
SELECT category, COUNT(*) FROM orders
GROUP BY category
HAVING COUNT(*) > 5;
```

**Scenario 2: Non-aggregate HAVING condition degrades performance.**
A query to find EU orders groups the entire orders table by region and then applies HAVING region = 'EU'. On a table with 50 million rows across 20 regions, this groups all 50 million rows before discarding 19 of the 20 groups. Moving the condition to WHERE reduces the scan to EU rows only, cutting work by roughly 95%.

```sql
-- Slow on large tables
SELECT region, SUM(amount) FROM orders GROUP BY region HAVING region = 'EU';

-- Fast: WHERE filters before grouping
SELECT region, SUM(amount) FROM orders WHERE region = 'EU' GROUP BY region;
```

**Scenario 3: HAVING filters out all groups and returns an empty result.**
A developer is debugging a report that should return all active products and accidentally writes `HAVING COUNT(*) > 10000`. All product groups have fewer than 10,000 rows, so HAVING eliminates every group and the query returns zero rows. The developer inspects the WHERE clause looking for the problem, never considering HAVING. This scenario is a common source of "my query returns nothing" confusion.

---

## Interview Angle

Common question forms:
- "What is the difference between WHERE and HAVING?"
- "Why can't you use an aggregate function in a WHERE clause?"
- "Which should you prefer for performance on a non-aggregate condition: WHERE or HAVING?"

Answer frame:
Lead with the execution order: WHERE runs before grouping, HAVING runs after grouping. This explains why aggregates are invalid in WHERE (they don't exist yet) and why HAVING can reference them (they've already been computed). For the performance question, explain that non-aggregate conditions in HAVING force the database to process and group all rows before filtering - WHERE filters reduce the working set before grouping, making HAVING only the appropriate place for conditions that genuinely require an aggregate result. Finishing with a concrete example showing the WHERE version of a filter running faster than the HAVING version demonstrates practical understanding.

---

## Related Notes

- [[group-by|GROUP BY]]
- [[aggregate-functions|Aggregate Functions]]
- [[where-clause|WHERE Clause]]
- [[window-functions|Window Functions]]
- [[select-basics|SELECT Basics]]
