---
title: 12 - LEFT and RIGHT JOIN
description: LEFT JOIN returns all rows from the left table plus matched rows from the right, filling unmatched right-side columns with NULL — making it the essential tool for finding optional or missing relationships.
tags: [sql, layer-9, joins, outer-join]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# LEFT and RIGHT JOIN

> LEFT JOIN is how you ask "give me everything on this side, and attach whatever exists on the other side" — the NULLs in the result are not errors; they are data, telling you which relationships are absent.

---

## Quick Reference

**Core idea:**
- LEFT JOIN returns every row from the left table, regardless of whether a match exists in the right table
- Unmatched right-table columns in the output are filled with NULL
- RIGHT JOIN is the exact mirror — all rows from the right table, NULLs for unmatched left columns
- `WHERE right_table.id IS NULL` after a LEFT JOIN finds rows in the left table with no match — the "anti-join" pattern
- Both are "outer joins" — the OUTER keyword is optional: `LEFT OUTER JOIN` and `LEFT JOIN` are identical

**Tricky points:**
- Filtering on a right-table column in the WHERE clause effectively converts a LEFT JOIN back into an INNER JOIN — use the IS NULL check carefully
- RIGHT JOIN is almost never needed — swapping table order and using LEFT JOIN is clearer
- A LEFT JOIN on a one-to-many relationship still multiplies rows; a customer with 5 orders appears 5 times, not once
- Aggregating after a LEFT JOIN requires distinguishing NULL (no match) from a real zero — `COUNT(o.id)` vs `COUNT(*)` matters
- The ON clause filter and the WHERE clause filter have different semantics for outer joins

---

## What It Is

Think of a university's roster system. The registrar has a list of every enrolled student. The exam office has a list of every student who submitted a final exam paper. An administrator wants to see all enrolled students and, next to each name, the exam score if a paper was submitted. Students who did not submit are still listed — their score column is simply blank. Students who submitted have their score filled in. An INNER JOIN would silently drop the non-submitters. A LEFT JOIN keeps them all, with a blank (NULL) where the score would be.

LEFT JOIN is classified as an outer join because it preserves rows from one side even when the join condition finds no match on the other side. The "outer" rows — those without a matching partner — are padded with NULL values for every column from the right table. This NULL-padding is not an error condition; it is the deliberate result, and it is precisely what makes LEFT JOIN useful. The NULLs identify gaps: customers who have never purchased, users with no profile photo, products that have never been ordered.

The directionality of LEFT vs RIGHT refers to which table is fully preserved. In `FROM A LEFT JOIN B ON ...`, table A is fully preserved. Every row in A appears in the output. Rows in B appear only when they match an A row. In `FROM A RIGHT JOIN B ON ...`, table B is fully preserved and A rows appear only when matched. Because you can always achieve a RIGHT JOIN result by swapping table order and using LEFT JOIN, RIGHT JOIN adds no expressive power — it is mostly a readability choice that tends to produce harder-to-follow queries. The practical convention in nearly all codebases is to use LEFT JOIN exclusively and place the "preserved" table first in the FROM clause.

Understanding where NULL values come from in a LEFT JOIN result is critical for writing correct WHERE clauses. When you add a filter on a column from the right table — for example, `WHERE orders.status = 'shipped'` after a LEFT JOIN to orders — you are filtering on a column that is NULL for unmatched customers. The condition `NULL = 'shipped'` evaluates to NULL (not TRUE), so those rows are discarded, and the query behaves identically to an INNER JOIN. This is a common, silent bug.

---

## How It Actually Works

The query engine executes a LEFT JOIN by first performing what is essentially an INNER JOIN, collecting all matched pairs. It then takes any left-table rows that produced no matches and adds them to the output with NULL-padded right-table columns. This second step — the preservation pass — is what distinguishes outer joins from inner joins and is why outer joins cannot be trivially reordered by the planner as freely as inner joins.

The semantic difference between ON clause conditions and WHERE clause conditions is especially important for outer joins. Conditions placed in the ON clause are evaluated during the join itself and determine which right-table rows are considered a "match." Conditions placed in the WHERE clause are evaluated after the join has produced its full output, including NULL-padded rows. For an INNER JOIN, this distinction does not change the final result because any row eliminated by WHERE would have been eliminated by ON and vice versa. For a LEFT JOIN, the distinction is significant: a condition in ON can limit which right-table rows appear, while still preserving all left-table rows (unmatched ones become NULL-padded). The same condition in WHERE eliminates any NULL-padded row entirely.

```sql
-- Basic LEFT JOIN: all customers, with order info where it exists
SELECT
    c.id            AS customer_id,
    c.name,
    o.id            AS order_id,
    o.total_amount
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id;
-- Customers with no orders appear with NULL in order_id and total_amount

-- Anti-join: customers who have NEVER placed an order
SELECT c.id, c.name
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
WHERE o.id IS NULL;

-- Counting orders per customer, including customers with zero orders
SELECT
    c.id,
    c.name,
    COUNT(o.id) AS order_count   -- COUNT(o.id) counts non-NULL values only, so 0 for unmatched
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
GROUP BY c.id, c.name;

-- ON clause filter vs WHERE clause filter: different semantics
-- This preserves all customers; only shows 2026 orders for those who have them
SELECT c.name, o.id, o.created_at
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id AND o.created_at >= '2026-01-01';

-- This REMOVES customers with no 2026 orders — converts to INNER JOIN behavior
SELECT c.name, o.id, o.created_at
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
WHERE o.created_at >= '2026-01-01';   -- filters out NULLs → no unmatched customers

-- RIGHT JOIN (avoid — swap tables and use LEFT JOIN instead)
SELECT c.name, o.id
FROM orders o
RIGHT JOIN customers c ON o.customer_id = c.id;
-- Identical result to: FROM customers c LEFT JOIN orders o ON ...
```

When performing aggregations after a LEFT JOIN, the choice between `COUNT(*)` and `COUNT(column)` matters significantly. `COUNT(*)` counts every row, including the NULL-padded rows for unmatched left-table entries, producing 1 for every customer regardless of whether they have orders. `COUNT(o.id)` counts only rows where `o.id` is non-NULL — which is 0 for customers with no orders. This is the correct behavior when you want a zero count for absent relationships rather than a misleading 1.

---

## How It Connects

LEFT JOIN builds directly on the foundation of joins and the INNER JOIN concept. The key conceptual leap is understanding that the output is no longer a clean set of matched pairs — it includes deliberately incomplete rows where the right side is NULL. This shapes how you must write WHERE, GROUP BY, and aggregation logic afterward.

LEFT JOIN is also one half of the FULL OUTER JOIN pattern. Understanding LEFT JOIN is a prerequisite for understanding how the UNION-based MySQL workaround for FULL OUTER JOIN works.

[[joins-overview|Joins Overview]] — the full family of join types and the Venn diagram mental model.

[[inner-join|INNER JOIN]] — what LEFT JOIN excludes that INNER JOIN also excludes, and what it preserves that INNER JOIN drops.

[[full-outer-join|FULL OUTER JOIN]] — extends the outer-join concept to preserve rows from both sides simultaneously.

[[where-clause|WHERE Clause]] — the ON-vs-WHERE distinction for outer joins is one of the most common sources of silent bugs.

---

## Common Misconceptions

Misconception 1: "Adding a WHERE filter on a right-table column after a LEFT JOIN is fine — it just filters the results."
Reality: A WHERE filter on a right-table column eliminates all NULL-padded rows because `NULL = 'anything'` evaluates to NULL (falsy). This silently converts the LEFT JOIN into an INNER JOIN. If you want to filter right-table rows without eliminating unmatched left-table rows, the filter must be in the ON clause, not the WHERE clause.

Misconception 2: "RIGHT JOIN gives you different results than LEFT JOIN — it's a genuinely different operation."
Reality: RIGHT JOIN and LEFT JOIN are mirror images. Any query using RIGHT JOIN can be rewritten as a LEFT JOIN by swapping the table order. The only thing that changes is which table is listed first in the FROM clause. Because RIGHT JOIN produces harder-to-read queries by convention, most teams prohibit it in their SQL style guides.

Misconception 3: "A LEFT JOIN always returns one row per left-table row."
Reality: If the right table has multiple rows matching one left-table row, the left-table row is duplicated — once per match. A customer with 5 orders appears 5 times after a LEFT JOIN to orders, just as they would with an INNER JOIN. The only rows that appear exactly once are those with no match on the right side, which appear once with NULLs.

---

## Why It Matters in Practice

LEFT JOIN is one of the most practically important SQL constructs because real-world data is full of optional relationships. Users may or may not have a billing address. Products may or may not have been reviewed. Employees may or may not have a manager. Any query that needs to present a full list of something while optionally attaching related data uses LEFT JOIN.

The anti-join pattern — `LEFT JOIN ... WHERE right_table.pk IS NULL` — is also a critical tool for data auditing and cleanup. Finding records that are missing required links, identifying orphaned rows after a partial migration, confirming that a bulk delete removed all expected child records: these all use the same pattern. The alternative `NOT IN` subquery works but is brittle with NULLs (if the subquery returns any NULL, the entire `NOT IN` returns false). The alternative `NOT EXISTS` correlated subquery is semantically cleaner but often slower. The LEFT JOIN anti-join pattern is the most reliable and typically the most efficient of the three options.

---

## What Breaks

**WHERE filter converts LEFT JOIN to INNER JOIN silently.** This is the most common LEFT JOIN mistake and produces no error — just wrong results.

```sql
-- BROKEN: intended to get all employees and their department name if assigned
-- WHERE filters eliminate employees with no department (department_id IS NULL becomes WHERE NULL = 'Engineering')
SELECT e.name, d.name AS department
FROM employees e
LEFT JOIN departments d ON e.department_id = d.id
WHERE d.name = 'Engineering';   -- eliminates all NULL-padded rows

-- FIXED: filter inside ON clause to preserve unassigned employees
SELECT e.name, d.name AS department
FROM employees e
LEFT JOIN departments d ON e.department_id = d.id AND d.name = 'Engineering';
```

**COUNT(*) gives wrong zero-counts.** When counting related rows using a LEFT JOIN, using COUNT(*) instead of COUNT(right_table.pk) inflates the count for unmatched rows from 0 to 1.

```sql
-- BROKEN: customers with no orders show count = 1 instead of 0
SELECT c.name, COUNT(*) AS order_count
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
GROUP BY c.name;

-- FIXED: COUNT on the right-table's non-nullable column
SELECT c.name, COUNT(o.id) AS order_count
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
GROUP BY c.name;
```

**NULL foreign keys on the left table match nothing.** If the left table itself has NULLs in the join column, those rows still appear in the output — but with NULL-padded right-table columns, indistinguishable from rows that genuinely have no match. This can hide data quality issues.

---

## Interview Angle

Common question forms:
- "What is the difference between INNER JOIN and LEFT JOIN?"
- "How would you find all customers who have never placed an order?"
- "Why does adding a WHERE clause on a right-table column after a LEFT JOIN behave like an INNER JOIN?"

Answer frame:
For the INNER vs LEFT question: INNER JOIN returns only matched rows, LEFT JOIN returns all rows from the left table with NULLs for unmatched right-table columns. Give a concrete example. For finding customers with no orders: describe the LEFT JOIN anti-join pattern — LEFT JOIN orders ON ..., WHERE orders.id IS NULL — and explain why it works. For the WHERE clause question: explain that WHERE is evaluated after the join, and `NULL = value` is always NULL (falsy), so rows with NULL right-table values are removed — effectively undoing the LEFT JOIN's preservation of unmatched rows.

---

## Related Notes

- [[joins-overview|Joins Overview]]
- [[inner-join|INNER JOIN]]
- [[full-outer-join|FULL OUTER JOIN]]
- [[where-clause|WHERE Clause]]
- [[aggregate-functions|Aggregate Functions]]
- [[subqueries|Subqueries]]
