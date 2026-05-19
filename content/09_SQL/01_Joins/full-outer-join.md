---
title: 13 - FULL OUTER JOIN
description: FULL OUTER JOIN returns all rows from both tables, filling NULLs where no match exists on either side - making it the tool for data reconciliation when you need to see everything from both sources simultaneously.
tags: [sql, layer-9, joins, outer-join]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# FULL OUTER JOIN

> FULL OUTER JOIN is the reconciliation join - it shows you what both sides have, what they share, and what each side has that the other does not, all in a single result set.

---

## Quick Reference

**Core idea:**
- FULL OUTER JOIN returns all rows from both the left and right table
- Where a left-table row has no match in the right, right-table columns are NULL
- Where a right-table row has no match in the left, left-table columns are NULL
- Rows that match on both sides appear once with complete data from both tables
- MySQL does not support FULL OUTER JOIN natively - use UNION of LEFT JOIN and RIGHT JOIN as a workaround

**Tricky points:**
- The result set can be much larger than either source table alone
- Filtering out the matched rows (WHERE left.id IS NULL OR right.id IS NULL) gives you the "symmetric difference" - rows in either table but not both
- Performance can be significant: the engine must track unmatched rows from both sides
- NULL appears in the result both from unmatched rows and from genuinely NULL column values - these are indistinguishable without additional context
- FULL OUTER JOIN is not the same as a CROSS JOIN - it still joins on a condition, it just preserves unmatched rows from both sides

---

## What It Is

Picture two bookkeepers at the end of a quarter, each maintaining their own ledger of transactions. One ledger is the bank statement. The other is the company's internal accounts. The auditor's job is to produce a reconciliation report: every transaction that appears in both ledgers (matched, shown side by side), every transaction in the bank statement but missing from the internal accounts (a gap to investigate), and every transaction in the internal accounts but missing from the bank statement (another gap). The auditor does not discard transactions that only appear in one ledger - that would defeat the entire purpose. A FULL OUTER JOIN is the SQL equivalent of that reconciliation: it puts both sides on the table, matched or not.

FULL OUTER JOIN combines the behaviors of LEFT JOIN and RIGHT JOIN simultaneously. Every row from the left table appears in the output - matched rows bring along their right-table data, unmatched rows get NULL-padded right-table columns. Every row from the right table also appears - matched rows are already accounted for in the output, but unmatched right-table rows are added with NULL-padded left-table columns. The matched rows appear once, not twice. The final result contains every piece of data from both tables, organized into a unified structure where NULLs indicate the absence of a corresponding record on one side.

This join type is genuinely uncommon in day-to-day application code. Most application queries need data that must exist in a consistent relationship - a user and their profile, a product and its category. For those queries, INNER JOIN or LEFT JOIN is appropriate. FULL OUTER JOIN becomes relevant in three specific scenarios: comparing two versions of a dataset to find what changed, synchronizing data between two systems (finding what is in one but not the other), and performing data migration validation. In each case, the goal is to see the complete picture from both sides at once.

The symmetric difference pattern - finding rows that exist in one table but not the other - is a particularly useful specialization. By taking a FULL OUTER JOIN and then filtering to rows where either the left primary key IS NULL or the right primary key IS NULL, you get only the unmatched rows. Rows that appear in both tables (the intersection) are excluded. This is the exact query you run when verifying that a data migration preserved all rows correctly, or that two systems are in sync.

---

## How It Actually Works

In PostgreSQL, FULL OUTER JOIN is a first-class syntax supported natively. The planner implements it by performing a hash join or merge join that tracks unmatched rows from both sides during the join phase. Once all matching pairs have been emitted, any rows from the left side that produced no matches are emitted with NULLs for right-table columns, and then any rows from the right side that produced no matches are emitted with NULLs for left-table columns. The total output size is: (number of matched pairs) + (unmatched left rows) + (unmatched right rows).

MySQL has no native FULL OUTER JOIN syntax. The standard workaround uses UNION to combine a LEFT JOIN with a RIGHT JOIN, deduplicating the matched rows by excluding the right-only rows from the second query using `WHERE left_table.id IS NULL`.

```sql
-- PostgreSQL: native FULL OUTER JOIN
SELECT
    a.id    AS left_id,
    a.name  AS left_name,
    b.id    AS right_id,
    b.name  AS right_name
FROM table_a a
FULL OUTER JOIN table_b b ON a.key = b.key;

-- Finding rows that are ONLY in table_a (no match in table_b)
SELECT a.id, a.name
FROM table_a a
FULL OUTER JOIN table_b b ON a.key = b.key
WHERE b.key IS NULL;

-- Finding rows that are ONLY in table_b (no match in table_a)
SELECT b.id, b.name
FROM table_a a
FULL OUTER JOIN table_b b ON a.key = b.key
WHERE a.key IS NULL;

-- Symmetric difference: rows in either table but NOT in both
SELECT
    COALESCE(a.id, b.id) AS id,
    a.name AS source_a_name,
    b.name AS source_b_name
FROM table_a a
FULL OUTER JOIN table_b b ON a.id = b.id
WHERE a.id IS NULL OR b.id IS NULL;

-- MySQL workaround: UNION of LEFT and RIGHT JOINs
SELECT a.id AS left_id, a.name AS left_name, b.id AS right_id, b.name AS right_name
FROM table_a a
LEFT JOIN table_b b ON a.id = b.id
UNION
SELECT a.id, a.name, b.id, b.name
FROM table_a a
RIGHT JOIN table_b b ON a.id = b.id
WHERE a.id IS NULL;
-- The WHERE a.id IS NULL in the second query excludes rows already returned by the LEFT JOIN
```

The COALESCE function is frequently paired with FULL OUTER JOIN to produce a single identifier column. Because a matched row has both `a.id` and `b.id` populated (and equal), while unmatched rows have one of them as NULL, `COALESCE(a.id, b.id)` gives you the non-NULL value regardless of which side it came from - a unified key for the reconciliation report.

Performance for FULL OUTER JOIN is generally comparable to a hash-based LEFT JOIN, but the additional bookkeeping for the right side's unmatched rows adds cost. On large tables, the result set can be enormous: if Table A has 1 million rows and Table B has 800,000 rows with only 500,000 shared between them, the output has 500,000 matched rows + 500,000 A-only rows + 300,000 B-only rows = 1.3 million rows. Streaming this to an application or performing aggregations on it requires planning for that volume.

---

## How It Connects

FULL OUTER JOIN is the most inclusive join type - it subsumes both LEFT JOIN and RIGHT JOIN. Understanding it requires a solid grasp of what NULL values in join results mean, which is grounded in the LEFT JOIN note.

The reconciliation use case for FULL OUTER JOIN closely parallels the use of set operations. The symmetric difference query (rows in A but not B, or in B but not A) could alternatively be expressed using NOT EXISTS or EXCEPT/MINUS, each with different performance characteristics.

[[left-right-join|LEFT and RIGHT JOIN]] - the building blocks that FULL OUTER JOIN combines; understanding NULL-padded rows is a prerequisite.

[[joins-overview|Joins Overview]] - the full family of join types and when each is appropriate.

[[subqueries|Subqueries]] - the NOT EXISTS alternative to outer join anti-join patterns, relevant for comparison when FULL OUTER JOIN semantics are overkill.

---

## Common Misconceptions

Misconception 1: "FULL OUTER JOIN returns the Cartesian product - all rows from A times all rows from B."
Reality: FULL OUTER JOIN still evaluates a join condition. It only produces extra rows compared to INNER JOIN by preserving unmatched rows from both sides with NULLs. It does not pair every row from A with every row from B. That is a CROSS JOIN, which is an entirely different operation.

Misconception 2: "MySQL supports FULL OUTER JOIN."
Reality: MySQL does not have native FULL OUTER JOIN syntax. Attempting to write it produces a syntax error. The workaround is to UNION a LEFT JOIN with a RIGHT JOIN (filtering the RIGHT JOIN to only unmatched rows to avoid duplicating matched rows). PostgreSQL, SQL Server, and Oracle all support it natively.

Misconception 3: "FULL OUTER JOIN is needed whenever I want to compare two tables."
Reality: Most comparisons need only a LEFT JOIN (or NOT EXISTS) to find rows in A missing from B. FULL OUTER JOIN is only necessary when you want to find discrepancies in both directions simultaneously in a single query. Using it when a LEFT JOIN suffices adds unnecessary complexity and potential performance overhead.

---

## Why It Matters in Practice

FULL OUTER JOIN is the canonical SQL tool for data reconciliation - comparing records from two sources to identify discrepancies. This comes up frequently in data engineering: comparing an application's database to a data warehouse after a sync, verifying a migration preserved all rows, comparing two ETL pipeline outputs. Writing this comparison correctly with FULL OUTER JOIN is faster and more readable than the alternative of running two separate LEFT JOIN queries and combining the results in application code.

The MySQL limitation is a real practical concern. Teams working on MySQL-based systems who need FULL OUTER JOIN semantics must use the UNION workaround, which is verbose. This is a frequent interview topic for MySQL-specific roles and a common gotcha in cross-database compatibility work.

---

## What Breaks

**The MySQL UNION workaround includes duplicates if the WHERE clause is omitted.** The second query in the UNION (the RIGHT JOIN) must include `WHERE left_table.id IS NULL` to exclude rows that already appeared in the LEFT JOIN result. Without this filter, matched rows appear twice in the output.

```sql
-- BROKEN MySQL workaround - matched rows duplicated
SELECT a.id, b.id FROM a LEFT JOIN b ON a.id = b.id
UNION ALL  -- or UNION without filtering the second query
SELECT a.id, b.id FROM a RIGHT JOIN b ON a.id = b.id;
-- Matched rows appear twice

-- FIXED
SELECT a.id, b.id FROM a LEFT JOIN b ON a.id = b.id
UNION
SELECT a.id, b.id FROM a RIGHT JOIN b ON a.id = b.id
WHERE a.id IS NULL;
```

**Filtering on non-NULL columns in WHERE eliminates outer rows.** As with LEFT JOIN, placing a filter on a column from either table in the WHERE clause removes NULL-padded rows for that table, converting the FULL OUTER JOIN behavior to INNER JOIN behavior for that side.

```sql
-- BROKEN: filtering by status removes unmatched rows entirely
SELECT a.id, b.id
FROM table_a a
FULL OUTER JOIN table_b b ON a.id = b.id
WHERE b.status = 'active';   -- drops all rows where b is NULL (left-side-only rows disappear)

-- FIXED: move the filter into ON to preserve outer rows
SELECT a.id, b.id
FROM table_a a
FULL OUTER JOIN table_b b ON a.id = b.id AND b.status = 'active';
```

**Large result sets from nearly disjoint tables.** If two large tables share very few matching keys, a FULL OUTER JOIN returns nearly the sum of both tables' row counts. This is easy to miss in development against small datasets but can produce multi-gigabyte result sets in production.

---

## Interview Angle

Common question forms:
- "What is FULL OUTER JOIN and when would you use it?"
- "How do you simulate FULL OUTER JOIN in MySQL?"
- "How would you find rows that exist in Table A but not Table B, and also rows in Table B but not Table A, in a single query?"

Answer frame:
Define FULL OUTER JOIN as the join that preserves all rows from both tables, adding NULLs where no match exists on either side. Give the data reconciliation use case as the primary motivating example. For the MySQL simulation question, describe the UNION of LEFT JOIN and RIGHT JOIN with the `WHERE left.id IS NULL` filter on the second query. For the symmetric difference question, show FULL OUTER JOIN with `WHERE a.id IS NULL OR b.id IS NULL` - and mention the COALESCE pattern for producing a unified key column.

---

## Related Notes

- [[joins-overview|Joins Overview]]
- [[left-right-join|LEFT and RIGHT JOIN]]
- [[inner-join|INNER JOIN]]
- [[subqueries|Subqueries]]
- [[where-clause|WHERE Clause]]
