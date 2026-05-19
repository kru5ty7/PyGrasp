---
title: 06 - WHERE Clause
description: The WHERE clause filters rows from a query's source before any other processing, and its NULL-handling and operator-precedence rules are the source of some of SQL's most persistent bugs.
tags: [sql, layer-9, filtering, where]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# WHERE Clause

> WHERE is how you tell the database which rows to include in a result or modify with DML - and the way SQL handles NULL in comparisons is almost universally misunderstood until it causes a production bug.

---

## Quick Reference

**Core idea:**
- WHERE filters rows in SELECT, UPDATE, and DELETE. Only rows for which the WHERE expression evaluates to TRUE are included.
- Comparison operators: `=`, `<>` (or `!=`), `<`, `>`, `<=`, `>=`.
- Logical operators: AND, OR, NOT. AND has higher precedence than OR. Use parentheses to control grouping.
- NULL is not a value. Comparing NULL with `=` always returns NULL (not false, not true). Use `IS NULL` and `IS NOT NULL`.
- IN tests whether a value matches any value in a list. BETWEEN tests for an inclusive range. LIKE tests for pattern matches using `%` and `_`.

**Tricky points:**
- `WHERE column = NULL` never matches any row. It evaluates to NULL (unknown), not FALSE. Use `WHERE column IS NULL`.
- NOT IN with a NULL in the list returns no rows at all, because the comparison `value = NULL` evaluates to NULL for every row.
- `WHERE a = 1 OR b = 2 AND c = 3` is parsed as `WHERE a = 1 OR (b = 2 AND c = 3)` because AND binds more tightly than OR. This is a very common logic bug.
- LIKE is case-sensitive in PostgreSQL. Use ILIKE for case-insensitive matching. LIKE is case-insensitive by default in MySQL.
- `WHERE LOWER(column) = 'value'` prevents index usage on the column. Use a functional index or ILIKE instead.

---

## What It Is

Imagine a bouncer at a club entrance with a clipboard of rules. The rules might say "guests must be over 21 AND have a reservation" or "VIP members OR guests on the early list may enter." The bouncer checks each person against the rules and either lets them in or turns them away. The bouncer does not change the people; they just decide who gets through the door. The WHERE clause is that bouncer for your data.

WHERE appears in SELECT, UPDATE, and DELETE statements. It takes an expression that can evaluate to TRUE, FALSE, or NULL for each row in the source table. Only rows where the expression evaluates to TRUE pass through. Rows where the expression evaluates to FALSE or NULL are excluded. This three-valued logic - TRUE, FALSE, and NULL (unknown) - is one of the most important and most misunderstood aspects of SQL.

The simplest WHERE expressions use comparison operators. `WHERE age > 18` keeps rows where the age column's value is greater than 18. `WHERE status = 'active'` keeps rows where status equals the string 'active'. `WHERE id <> 42` keeps all rows except the one where id is 42. These operators work exactly as you would expect for non-NULL values.

Multiple conditions are combined with AND and OR. AND requires both conditions to be TRUE for a row to pass. OR requires at least one condition to be TRUE. NOT inverts a condition. AND has higher operator precedence than OR, which means without parentheses, `a OR b AND c` is interpreted as `a OR (b AND c)`. This is a constant source of logic bugs. When combining AND and OR, always use parentheses to make the grouping explicit, even when you believe the precedence is what you want.

NULL requires special handling. NULL represents an unknown or missing value. Comparing NULL to anything - even another NULL - with a regular comparison operator produces NULL, not TRUE or FALSE. The expression `NULL = NULL` evaluates to NULL. The expression `NULL = 1` evaluates to NULL. Since WHERE requires TRUE to include a row, any expression that produces NULL causes the row to be excluded. To test whether a value is NULL, use `IS NULL` or `IS NOT NULL`. These are the only operators that correctly identify NULL.

---

## How It Actually Works

The database engine evaluates the WHERE expression for each candidate row produced by the FROM clause. The evaluation is short-circuit in most databases: for AND, if the left side evaluates to FALSE, the right side is not evaluated (the result is already FALSE). For OR, if the left side evaluates to TRUE, the right side is not evaluated. This means expressions with side effects (rare in SQL) may or may not be evaluated depending on their position.

WHERE predicates interact heavily with indexes. When the WHERE clause contains a condition on an indexed column - such as `WHERE user_id = 42` - the optimizer can use the index to locate matching rows directly rather than scanning the entire table. This is called an index seek or index scan. When the WHERE clause wraps a column in a function - such as `WHERE LOWER(email) = 'alice@example.com'` - the optimizer cannot use an ordinary index on the email column, because the index stores the original values, not the function results. In PostgreSQL, you can create a functional index that stores `LOWER(email)` to support this pattern.

The LIKE operator performs pattern matching. The `%` wildcard matches any sequence of characters (including zero characters). The `_` wildcard matches any single character. `LIKE 'A%'` matches any string starting with A. `LIKE '%son'` matches any string ending with son. A leading wildcard - `LIKE '%smith%'` - prevents index usage because the matching range is unknown. For full-text search needs, PostgreSQL provides dedicated full-text search features.

```sql
-- Basic comparison
SELECT * FROM users WHERE active = true;

-- NOT EQUAL
SELECT * FROM orders WHERE status <> 'cancelled';

-- AND with explicit parentheses (good habit)
SELECT * FROM orders
WHERE (status = 'pending' OR status = 'processing')
  AND total_cents > 10000;

-- IS NULL: find rows with missing email
SELECT id, name FROM users WHERE email IS NULL;

-- IS NOT NULL
SELECT id, name FROM users WHERE email IS NOT NULL;

-- IN: equivalent to multiple OR conditions, but cleaner
SELECT * FROM orders WHERE status IN ('pending', 'processing', 'shipped');

-- NOT IN: DANGER if the list contains NULL
-- The following returns NO rows if any status value is NULL in the table,
-- because NULL comparisons return NULL (not FALSE)
SELECT * FROM orders WHERE status NOT IN ('cancelled', NULL);
-- Safe version: always exclude NULLs explicitly
SELECT * FROM orders WHERE status NOT IN ('cancelled') AND status IS NOT NULL;

-- BETWEEN: inclusive on both ends
SELECT * FROM orders WHERE total_cents BETWEEN 1000 AND 5000;

-- LIKE: pattern match
SELECT * FROM users WHERE name LIKE 'A%';    -- starts with A
SELECT * FROM users WHERE name LIKE '_ob';   -- 3 chars ending in 'ob'

-- ILIKE: case-insensitive (PostgreSQL only)
SELECT * FROM users WHERE email ILIKE '%@gmail.com';

-- Functional index workaround: avoid wrapping indexed column in a function
-- Bad (prevents index usage on email):
SELECT * FROM users WHERE LOWER(email) = 'alice@example.com';
-- Good (use ILIKE which can use an index with a pg_trgm or citext setup):
SELECT * FROM users WHERE email ILIKE 'alice@example.com';
```

---

## How It Connects

WHERE is evaluated in the second step of SQL's logical execution order - after FROM but before SELECT, GROUP BY, and aggregation. The select-basics note explains why this ordering matters and why SELECT aliases are unavailable in WHERE.

[[select-basics|SELECT Basics]]

WHERE filtering affects how the optimizer uses indexes. A WHERE condition on an indexed column can make a query hundreds of times faster. Understanding the relationship between WHERE predicates and indexes is the foundation of query optimization.

[[sql-indexes|SQL Indexes]]

HAVING is a second filtering clause that looks similar to WHERE but runs after grouping and aggregation. WHERE cannot filter on aggregate results (like COUNT or SUM). HAVING can.

[[having-clause|HAVING Clause]]

---

## Common Misconceptions

Misconception 1: "I can check for NULL with `WHERE column = NULL`."
Reality: The expression `column = NULL` evaluates to NULL (unknown) for every row, even the rows where column is NULL. Because NULL is not TRUE, no rows ever pass the filter. The correct syntax is `WHERE column IS NULL`. This is one of SQL's most frequently encountered gotchas and is responsible for countless "why does my query return no rows?" debugging sessions.

Misconception 2: "NOT IN with a list safely excludes all the listed values."
Reality: If the list passed to NOT IN contains even one NULL, the entire NOT IN expression evaluates to NULL for every row, and the WHERE clause returns no rows at all. This happens because `value = NULL` is always NULL, and `NOT NULL` is also NULL. If you use NOT IN with a subquery, and that subquery returns any NULL, your outer query returns empty. Always pair NOT IN with an explicit `AND column IS NOT NULL`, or use NOT EXISTS instead.

Misconception 3: "AND and OR are evaluated left to right."
Reality: AND has higher precedence than OR, regardless of left-to-right order. The expression `WHERE a = 1 OR b = 2 AND c = 3` means `WHERE a = 1 OR (b = 2 AND c = 3)`. If you intended `WHERE (a = 1 OR b = 2) AND c = 3`, the query returns different rows. Use parentheses whenever you mix AND and OR.

---

## Why It Matters in Practice

The NULL comparison mistake is one of the most common production bugs in SQL-heavy applications. A developer writes a query to find all users without an email address, uses `WHERE email = NULL`, gets zero results, and concludes no such users exist. The data is actually full of NULL email rows. The developer proceeds to write a migration that assumes the column is always populated, and the migration fails in production.

Understanding that WHERE is the primary mechanism for index utilization fundamentally changes how you design queries. A WHERE clause with a non-sargable predicate (a predicate that cannot use an index, like a function wrapping an indexed column) turns a ten-millisecond indexed lookup into a ten-second sequential table scan on a large table. Learning to recognize non-sargable predicates and rewrite them is one of the highest-value SQL performance skills.

---

## What Breaks

The NOT IN with NULL issue is a silent correctness failure - the query runs without error but returns wrong results.

```sql
-- Suppose the 'deleted_user_ids' subquery returns: (1, 2, NULL)
SELECT id, name FROM users
WHERE id NOT IN (SELECT deleted_user_id FROM deletions);
-- If deleted_user_id has any NULL row, this returns ZERO rows.
-- Because: 5 IN (1, 2, NULL) = NULL, and NOT NULL = NULL, not TRUE.

-- Correct version using NOT EXISTS:
SELECT id, name FROM users u
WHERE NOT EXISTS (
    SELECT 1 FROM deletions d WHERE d.deleted_user_id = u.id
);
```

A LIKE pattern with a leading wildcard causes a full sequential scan, even on a column with a btree index. On a large table, this means a query that is fast on small datasets degrades severely in production once the table grows.

```sql
-- This cannot use a standard btree index on 'name':
SELECT * FROM users WHERE name LIKE '%smith%';
-- The optimizer must scan every row to find a match anywhere in the string.
-- Solution: use PostgreSQL full-text search or a trigram index (pg_trgm extension).
```

---

## Interview Angle

Common question forms:
- "Why does `WHERE column = NULL` not work?"
- "What is the difference between WHERE and HAVING?"
- "What is a sargable predicate?"
- "What happens with NOT IN if the subquery returns NULL?"

Answer frame:
Explain three-valued logic (TRUE, FALSE, NULL) in SQL. Describe why `= NULL` produces NULL rather than TRUE or FALSE, and why `IS NULL` is required. Explain AND/OR precedence and the need for parentheses. For sargable predicates, explain that wrapping an indexed column in a function defeats index usage. For NOT IN and NULL, walk through the logic chain: `value IN (..., NULL)` evaluates `value = NULL` which is NULL; NOT NULL is also NULL; WHERE requires TRUE; therefore no rows pass.

---

## Related Notes

- [[select-basics|SELECT Basics]]
- [[sql-indexes|SQL Indexes]]
- [[having-clause|HAVING Clause]]
- [[dml|DML - INSERT, UPDATE, DELETE]]
- [[full-text-search|Full-Text Search]]
