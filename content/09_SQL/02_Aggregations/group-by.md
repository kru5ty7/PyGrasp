---
title: GROUP BY
description: GROUP BY partitions a query's rows into groups so that aggregate functions can produce one result per group instead of one result for the whole table.
tags: [sql, layer-9, grouping, aggregation]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# GROUP BY

> GROUP BY divides rows into buckets by the values of one or more columns — understanding the rule about which columns can appear in SELECT, and where GROUP BY sits in the logical execution order, is mandatory for writing correct aggregate queries.

---

## Quick Reference

**Core idea:**
- GROUP BY partitions the result of FROM and WHERE into groups, one group per unique combination of the grouping columns
- Every non-aggregate column in SELECT must appear in GROUP BY; aggregate functions can reference any column
- The logical execution order is FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
- Grouping on multiple columns creates one group per unique tuple of those column values
- NULL values in a grouping column form their own group — two NULL values are treated as equal for grouping purposes
- You can GROUP BY an expression, not just a bare column name

**Tricky points:**
- The SELECT rule is enforced by the parser in standard SQL; MySQL historically allowed violations of it (which produced non-deterministic results)
- NULL grouping behavior differs from NULL comparison behavior — NULLs are not equal under `=` but they are coalesced into one group under GROUP BY
- Column aliases defined in SELECT cannot be referenced in GROUP BY in most databases because SELECT is evaluated after GROUP BY
- GROUP BY without any aggregate function is equivalent to SELECT DISTINCT on those columns
- ORDER BY column position (ORDER BY 1, 2) refers to the SELECT list, not the GROUP BY list

---

## What It Is

Imagine a spreadsheet where every row represents a sale: the date, the salesperson's name, the region, and the amount. If you want to see total sales per region, you would visually group all the rows for each region together and then add up the amounts for each cluster. GROUP BY is SQL's mechanism for performing exactly this clustering before an aggregate function is applied.

The name "group by" is literal — the database takes the rows that survive the WHERE clause and arranges them into buckets, where every row in a bucket shares the same value (or combination of values) for the column or columns listed after GROUP BY. Once the buckets exist, aggregate functions like COUNT, SUM, AVG, MIN, and MAX are applied to each bucket separately, producing one output row per bucket. This is fundamentally different from applying an aggregate to the whole table, which produces a single row.

The rule that every non-aggregate column in SELECT must appear in GROUP BY exists because of what "one output row per group" means. If you group by region and ask for the salesperson's name in SELECT without aggregating it, the database cannot decide which of potentially many different names in that group to output — the result would be arbitrary. By requiring that non-aggregate columns be part of the grouping key, SQL guarantees that every such column has exactly one value per group and the output row is deterministic.

The logical execution order of SQL clauses is one of the most practically useful concepts in the language. GROUP BY sits after FROM and WHERE but before HAVING, SELECT, and ORDER BY. This means WHERE can only filter raw rows — it cannot reference aggregate results because the aggregates have not been computed yet. HAVING, which runs after GROUP BY, can filter by aggregate results. SELECT column aliases are defined during the SELECT phase, which runs after GROUP BY, so those aliases are not available for use in the GROUP BY clause itself in most database engines.

---

## How It Actually Works

The database engine first resolves the FROM clause (including any joins) to produce a working set of rows. If a WHERE clause is present, it filters that set. The remaining rows are then sorted or hashed by the GROUP BY column values to form groups. Each group is handed to the aggregate functions specified in SELECT, which compute their results for that group. The result of the entire query is one row per group.

```sql
-- Single-column grouping: one row per status
SELECT status, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY status;

-- Multi-column grouping: one row per (status, region) combination
SELECT status, region, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY status, region;

-- Grouping by expression: group by the year of a date
SELECT
    EXTRACT(YEAR FROM created_at) AS year,
    COUNT(*) AS signups
FROM users
GROUP BY EXTRACT(YEAR FROM created_at)
ORDER BY year;
```

NULL values in a grouping column deserve special attention. Under normal comparison rules, NULL = NULL evaluates to NULL (not TRUE), so two NULL values are never considered equal. GROUP BY overrides this — all rows where the grouping column is NULL are placed into a single group, as if NULLs were equal to each other for this one purpose.

```sql
-- Demonstrating NULL grouping
-- If region is NULL for some rows, those rows form one group labeled NULL
SELECT region, COUNT(*) AS count
FROM orders
GROUP BY region;
-- Output might be: EU → 40, US → 30, NULL → 15
```

GROUP BY without any aggregate function produces a list of unique value combinations, making it functionally equivalent to SELECT DISTINCT in most cases. The distinction matters for certain window function and subquery scenarios, but for everyday use they are interchangeable.

```sql
-- These two queries produce the same result
SELECT DISTINCT status FROM orders;
SELECT status FROM orders GROUP BY status;
```

---

## How It Connects

Aggregate functions are the primary reason GROUP BY exists — without something to aggregate per group, GROUP BY degenerates into a deduplication operation. Understanding what each aggregate function does with NULL values is essential to interpreting grouped results correctly.

HAVING is the clause that filters grouped results, stepping in where WHERE cannot. Once you understand that GROUP BY sits between WHERE and HAVING in the logical execution order, the purpose of HAVING becomes clear: it filters after the groups and aggregates have been computed.

Window functions provide an alternative to GROUP BY when you need aggregate-like values alongside individual row data. A window function can compute a group-level SUM without collapsing rows, which GROUP BY always does.

[[aggregate-functions|Aggregate Functions]]
[[having-clause|HAVING Clause]]
[[window-functions|Window Functions]]

---

## Common Misconceptions

Misconception 1: "I can put any column I want in SELECT as long as there's a GROUP BY somewhere in the query."
Reality: Every non-aggregate column in SELECT must be one of the grouping columns. If a column is not in the GROUP BY list and not wrapped in an aggregate, the query is illegal in standard SQL. MySQL's historical permissive mode allowed it, but returned a non-deterministic value — an arbitrary row's value from the group. PostgreSQL, SQL Server, and Oracle all enforce the rule strictly.

Misconception 2: "NULL values in a GROUP BY column are ignored or excluded from the result."
Reality: NULL values in a grouping column are not excluded — they form their own group. All rows where the grouping column is NULL will be aggregated together and appear as a NULL group in the output. If you want to exclude these rows, add a WHERE col IS NOT NULL clause before grouping.

Misconception 3: "WHERE and HAVING do the same thing — either can filter on aggregates."
Reality: WHERE runs before GROUP BY, so it operates on individual rows and has no access to aggregate values. Placing an aggregate condition in WHERE will produce a syntax error. HAVING runs after GROUP BY and can reference both group columns and aggregate results.

---

## Why It Matters in Practice

GROUP BY is the backbone of every summary query in production systems. Any dashboard showing metrics by category, time period, or status is built on GROUP BY. Analytics pipelines, billing systems, and monitoring queries all depend on correct grouping behavior.

The execution order rule has performance implications beyond correctness. Filtering with WHERE before GROUP BY reduces the number of rows the grouping step must process. A query that groups a million-row table and then applies HAVING to discard groups is doing more work than a query that uses WHERE to reduce the table to 100,000 rows before grouping. WHERE predicates that filter out large portions of the table should always be preferred over equivalent HAVING predicates.

---

## What Breaks

**Scenario 1: Non-grouped column in SELECT causes a parse error.**
A developer writes `SELECT user_id, email, COUNT(*) FROM orders GROUP BY user_id`. The query fails in PostgreSQL because email is not in GROUP BY and not aggregated. The fix is either to add email to GROUP BY or to use MIN(email) if only one representative value is needed.

```sql
-- Error: email is not grouped or aggregated
SELECT user_id, email, COUNT(*) FROM orders GROUP BY user_id;

-- Fix option 1: include email in GROUP BY
SELECT user_id, email, COUNT(*) FROM orders GROUP BY user_id, email;

-- Fix option 2: aggregate email if duplicates are acceptable
SELECT user_id, MIN(email) AS email, COUNT(*) FROM orders GROUP BY user_id;
```

**Scenario 2: Using a SELECT alias in GROUP BY fails.**
A developer writes `SELECT EXTRACT(YEAR FROM created_at) AS year, COUNT(*) FROM users GROUP BY year`. PostgreSQL and SQL Server reject this because GROUP BY is evaluated before SELECT, so the alias year does not yet exist. The expression must be repeated in GROUP BY.

```sql
-- Fails in most databases
SELECT EXTRACT(YEAR FROM created_at) AS year, COUNT(*) FROM users GROUP BY year;

-- Correct: repeat the expression
SELECT EXTRACT(YEAR FROM created_at) AS year, COUNT(*) FROM users
GROUP BY EXTRACT(YEAR FROM created_at);
```

**Scenario 3: Unexpected NULL group in output misleads reporting.**
A query groups orders by sales_region and sums revenue. Rows with a NULL region are aggregated into a NULL group. A reporting tool displays this as a blank row that looks like a grand total, causing confusion. Filtering with WHERE sales_region IS NOT NULL removes the NULL group, or COALESCE(sales_region, 'Unknown') labels it explicitly.

---

## Interview Angle

Common question forms:
- "Explain the SQL logical execution order."
- "What is the rule about which columns can appear in SELECT when using GROUP BY?"
- "What is the difference between WHERE and HAVING?"

Answer frame:
For execution order: recite FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY and explain one implication of each transition (WHERE can't see aggregates, GROUP BY must happen before HAVING, SELECT aliases aren't available in GROUP BY). For the SELECT rule: state that every non-aggregate column must be in GROUP BY because the database needs a single deterministic value per output row. For WHERE vs HAVING: frame it as a timing question — WHERE filters before groups exist, HAVING filters after groups are formed.

---

## Related Notes

- [[aggregate-functions|Aggregate Functions]]
- [[having-clause|HAVING Clause]]
- [[window-functions|Window Functions]]
- [[select-basics|SELECT Basics]]
- [[where-clause|WHERE Clause]]
