---
title: ORDER BY, LIMIT, OFFSET
description: ORDER BY, LIMIT, and OFFSET control the order and size of a query's result set, but OFFSET-based pagination degrades severely on large tables and cursor-based pagination is almost always the better choice.
tags: [sql, layer-9, ordering, pagination]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# ORDER BY, LIMIT, OFFSET

> Sorting and limiting result sets are the last steps in SQL's execution order — but the way most developers implement pagination using OFFSET causes queries that get slower with every page turn.

---

## Quick Reference

**Core idea:**
- ORDER BY sorts the result set by one or more columns. ASC (ascending) is the default. DESC sorts largest to smallest.
- LIMIT caps the number of rows returned. Without LIMIT, the database returns all matching rows.
- OFFSET skips a number of rows before returning results. `LIMIT 10 OFFSET 20` skips the first 20 rows and returns rows 21–30.
- Sorting on multiple columns: the first column is the primary sort key; subsequent columns break ties.
- PostgreSQL supports `NULLS FIRST` and `NULLS LAST` in ORDER BY to control where NULL values appear in a sorted result.

**Tricky points:**
- Without ORDER BY, the database returns rows in an unspecified order. The order may appear consistent in small tables but is not guaranteed and can change at any time.
- OFFSET does not skip work. The database still reads and discards the skipped rows. OFFSET 10000 causes the database to process 10010 rows to return 10.
- Cursor-based pagination (using `WHERE id > last_seen_id ORDER BY id LIMIT n`) is faster than OFFSET for large datasets and is the production-grade pattern.
- Sorting NULL values: in PostgreSQL, NULL sorts last in ASC order and first in DESC order by default. This differs from some other databases.
- LIMIT without ORDER BY produces non-deterministic results. The "first" rows have no meaning without a defined sort order.

---

## What It Is

Imagine a librarian who retrieves books for you. Without any instruction, the librarian hands you books in whatever order they were shelved or retrieved — which might look consistent today but could change tomorrow when the shelves are reorganized. If you ask for "the ten newest books," the librarian must first sort all books by publication date, then hand you the top ten from that sorted stack. ORDER BY, LIMIT, and OFFSET are how you give those sorting and sizing instructions to the database.

ORDER BY specifies the columns by which the result set should be sorted, and the direction of the sort. `ORDER BY price_cents ASC` sorts rows from cheapest to most expensive. `ORDER BY created_at DESC` sorts rows from most recent to oldest. ASC (ascending) is the default and can be omitted, but writing it explicitly makes the intent clear. DESC must be written explicitly. If no ORDER BY is present, the database may return rows in any order. On a table with a sequential scan, rows might come back in insertion order — but this is an accident of implementation, not a guarantee. Any query in application code that depends on a specific order must include an ORDER BY.

Sorting on multiple columns is common and important. `ORDER BY last_name ASC, first_name ASC` sorts primarily by last name; when two rows have the same last name, they are sorted by first name within that group. You can mix directions: `ORDER BY status ASC, created_at DESC` sorts by status alphabetically, then within each status group, the most recent rows appear first. Each column in the ORDER BY list is called a sort key.

LIMIT sets a maximum number of rows to return. The database stops returning rows after the limit is reached. LIMIT is essential for any query that could return a large number of rows — pagination, sampling, "give me one example," and "get the top N" queries all use LIMIT.

OFFSET tells the database to skip a number of rows before it starts returning rows. `LIMIT 10 OFFSET 30` returns rows 31 through 40 from the sorted result set. This is the mechanism behind page-based pagination: page 1 is `LIMIT 10 OFFSET 0`, page 2 is `LIMIT 10 OFFSET 10`, page 3 is `LIMIT 10 OFFSET 20`. The formula is `OFFSET = (page_number - 1) * page_size`.

---

## How It Actually Works

ORDER BY runs late in the logical execution order — after FROM, WHERE, GROUP BY, HAVING, and SELECT. This is why ORDER BY can reference aliases defined in the SELECT clause. The sort operation itself, in PostgreSQL, may use a quicksort in memory if the result set fits within `work_mem`, or an external merge sort on disk (a temporary file) if the data exceeds that limit. Large sorts that spill to disk are significantly slower. Increasing `work_mem` for memory-intensive sort operations is a common tuning technique.

LIMIT and OFFSET are applied last, after all other processing. This means the database evaluates the full WHERE clause and computes the full sort, then discards the rows outside the LIMIT/OFFSET window. The critical consequence is that OFFSET does not reduce work proportionally. `LIMIT 10 OFFSET 1000` causes the database to process 1010 rows — it processes all 1000 rows to be skipped, then returns the next 10. At page 1000 (`OFFSET 9990`), the database processes 10000 rows per request. Query time grows linearly with page number. On a table with millions of rows and a large offset, this causes very slow page loads.

Cursor-based pagination solves this problem. Instead of skipping rows by count, you remember the last row you saw and filter from there. If the sort key is `id`, the first page is `ORDER BY id LIMIT 10`, and subsequent pages are `WHERE id > last_seen_id ORDER BY id LIMIT 10`. The `WHERE id > last_seen_id` condition can use the primary key index to jump directly to the right starting point in O(log n) time, regardless of how many pages have been retrieved. This approach requires that the sort key be unique and stable — which is true for primary keys and timestamps combined with IDs.

```sql
-- Basic ORDER BY: most recent users first
SELECT id, name, created_at
FROM users
ORDER BY created_at DESC;

-- Multiple sort keys: alphabetical by last name, then first name
SELECT id, last_name, first_name
FROM users
ORDER BY last_name ASC, first_name ASC;

-- NULLS LAST: put rows where email is NULL at the end of ascending order
SELECT id, name, email
FROM users
ORDER BY email ASC NULLS LAST;

-- LIMIT: return only the 5 most expensive products
SELECT id, name, price_cents
FROM products
ORDER BY price_cents DESC
LIMIT 5;

-- OFFSET-based pagination (page 3, 10 rows per page)
SELECT id, name, created_at
FROM products
ORDER BY created_at DESC
LIMIT 10 OFFSET 20;

-- Cursor-based pagination (better): get next 10 rows after last seen id
-- First page:
SELECT id, name, created_at
FROM orders
ORDER BY id ASC
LIMIT 10;

-- Subsequent pages: pass the last id seen from the previous page
SELECT id, name, created_at
FROM orders
WHERE id > 9876   -- 9876 is the id of the last row returned on the previous page
ORDER BY id ASC
LIMIT 10;
```

---

## How It Connects

ORDER BY runs after SELECT in the logical execution order, which means it can reference column aliases defined in SELECT. The select-basics note explains the execution order that makes this possible.

[[select-basics|SELECT Basics]]

Cursor-based pagination relies on a WHERE clause filtering on an indexed column (like id or created_at). The efficiency of this pattern depends entirely on having the right index. Understanding how indexes support range queries is essential for implementing pagination that stays fast as data grows.

[[sql-indexes|SQL Indexes]]

Window functions like RANK() and ROW_NUMBER() are an alternative approach to ranking and selecting top-N rows from groups, without LIMIT. They are more powerful but more complex.

[[window-functions|Window Functions]]

---

## Common Misconceptions

Misconception 1: "Without ORDER BY, the database returns rows in insertion order."
Reality: The database returns rows in whatever order the execution plan produces them. For a simple table scan, this often coincides with insertion order — but it is not guaranteed. The order can change after a VACUUM, a table rewrite, a parallel query, or a change in the execution plan. Any code that depends on a specific order without ORDER BY is a latent bug.

Misconception 2: "OFFSET pagination is standard and there is no performance issue."
Reality: OFFSET pagination works acceptably for small tables or the first few pages of large tables. At large page numbers (page 100, page 1000), query time grows linearly because the database must process all skipped rows before returning the page. For any user-facing pagination feature on a table that grows over time, cursor-based pagination is the correct approach.

Misconception 3: "NULLS FIRST and NULLS LAST are standard SQL features supported everywhere."
Reality: The `NULLS FIRST` / `NULLS LAST` syntax is part of the SQL standard and is supported in PostgreSQL. MySQL does not support this syntax directly. In MySQL, you work around it with `ORDER BY column IS NULL ASC, column ASC` (to put NULLs last). If your code uses `NULLS FIRST` / `NULLS LAST` and targets MySQL, it will fail.

---

## Why It Matters in Practice

Forgetting ORDER BY in a paginated query means users see different rows on the same page on different requests. A table under active write load changes order frequently. Page 2 without ORDER BY might return the same rows as page 1, or skip rows entirely, or return rows in a different sequence on every request. ORDER BY is not optional for pagination.

OFFSET-based pagination is one of the most common performance problems in web applications. An application that works beautifully in development — where tables have a few hundred rows — begins to show slow page loads in production once a table grows to hundreds of thousands of rows. The slow pages are the high-offset pages: page 500, page 1000, page 5000. Cursor-based pagination eliminates this entire class of problem.

---

## What Breaks

LIMIT without ORDER BY gives a non-deterministic result that varies between runs. In development the result looks stable because the table is small and mostly append-only. In production the "top N" result changes without explanation.

```sql
-- Looks like it returns the 10 "first" products, but there is no defined order
SELECT id, name FROM products LIMIT 10;
-- The database may return a different 10 on the next run.

-- Correct: always pair LIMIT with ORDER BY
SELECT id, name FROM products ORDER BY created_at ASC LIMIT 10;
```

OFFSET-based pagination at scale causes very slow queries that time out under load.

```sql
-- This works fine when the table has 1,000 rows
SELECT id, title FROM articles ORDER BY created_at DESC LIMIT 20 OFFSET 980;

-- On a table with 10 million rows, the same pattern at high offsets is very slow:
SELECT id, title FROM articles ORDER BY created_at DESC LIMIT 20 OFFSET 9999980;
-- The database must sort and skip 9,999,980 rows to return 20.

-- Cursor-based replacement: always fast regardless of position
SELECT id, title, created_at FROM articles
WHERE created_at < '2024-01-15 10:00:00'  -- last seen timestamp from previous page
ORDER BY created_at DESC
LIMIT 20;
```

---

## Interview Angle

Common question forms:
- "What is the problem with OFFSET-based pagination?"
- "How would you implement cursor-based pagination?"
- "Where does ORDER BY run in the logical execution order?"
- "How do NULL values sort in PostgreSQL?"

Answer frame:
Explain that LIMIT and OFFSET run last in the logical execution order. Describe the OFFSET performance problem: the database must read and discard all skipped rows, so cost grows linearly with page number. Explain cursor-based pagination: record the last seen sort key value, then use `WHERE sort_key > last_value` on subsequent requests. Mention that this requires the sort key to be unique and indexed. For NULLs, state the PostgreSQL defaults (NULL last for ASC, NULL first for DESC) and mention `NULLS FIRST` / `NULLS LAST` syntax.

---

## Related Notes

- [[select-basics|SELECT Basics]]
- [[sql-indexes|SQL Indexes]]
- [[window-functions|Window Functions]]
- [[where-clause|WHERE Clause]]
- [[query-optimization|Query Optimization]]
