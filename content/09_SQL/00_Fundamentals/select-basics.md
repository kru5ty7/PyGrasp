---
title: 05 - SELECT Basics
description: The SELECT statement is the primary tool for reading data from a database, and understanding its logical execution order — which differs from its written order — is the key to writing correct queries.
tags: [sql, layer-9, select, querying]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# SELECT Basics

> SELECT is the foundation of every read operation in SQL, and the gap between how you write it and how the database executes it is the source of most beginner confusion.

---

## Quick Reference

**Core idea:**
- SELECT retrieves rows from one or more tables. The result is a new table, called a result set.
- The logical execution order is: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT.
- The written order is: SELECT → FROM → WHERE → GROUP BY → HAVING → ORDER BY → LIMIT.
- SELECT * returns all columns. Naming columns explicitly is almost always better.
- Column aliases defined with AS in the SELECT clause are not available in the WHERE clause because WHERE is evaluated before SELECT.
- DISTINCT removes duplicate rows from the result set. It compares all selected columns.

**Tricky points:**
- You cannot use a column alias from SELECT in the WHERE clause. WHERE runs before SELECT. You can use aliases in ORDER BY.
- SELECT * adds fragility to code: if a column is added or removed, behavior changes silently.
- DISTINCT operates on the full row, not on individual columns. `SELECT DISTINCT a, b` returns unique (a, b) pairs, not unique values of a alone.
- Computed columns (expressions) in SELECT are evaluated per row. They can reference any column from the FROM clause but not other aliases in the same SELECT.
- NULL values in selected columns remain NULL. No expression converts NULL to a value unless you explicitly handle it with COALESCE or CASE.

---

## What It Is

Think of SELECT like filling out a report request form at a records office. The form has sections: "Which files?" (FROM), "Only include records where..." (WHERE), "Group them by..." (GROUP BY), "I want to see these specific fields..." (SELECT), "Sort by..." (ORDER BY). The clerk processes your request in a logical order that makes sense for retrieval — they find the filing cabinets first, filter the folders, then extract the specific fields you asked for. The order you filled out the form does not match the order they process it. SQL is the same way.

SELECT is the statement used to read data from a database. It does not modify any data. The result is a transient table — a result set — that exists only for the duration of the query and is returned to the client. A basic SELECT has a minimum of two parts: the list of columns to return, and the table to read from. The keyword `FROM` introduces the table source.

Column selection is the first decision in a SELECT statement. Writing the column names explicitly — `SELECT id, name, email FROM users` — is called a column list. It makes the query's intent clear and protects against schema changes. Writing `SELECT *` returns every column in the table. This is convenient in ad-hoc queries at a terminal, but it is a liability in application code: if a column is added to the table, `SELECT *` returns it without warning, potentially exposing sensitive data or breaking code that unpacks rows positionally.

Column aliases give a column in the result set a different name. The `AS` keyword introduces an alias: `SELECT price_cents / 100.0 AS price_dollars FROM products`. This is purely a presentation rename — the alias exists only in the result set. You can use aliases in ORDER BY because ORDER BY runs after SELECT. You cannot use them in WHERE because WHERE runs before SELECT and the alias does not exist yet at that point.

DISTINCT is a modifier placed after SELECT that removes duplicate rows from the result set. It compares every column in the SELECT list. If two rows have identical values in all selected columns, only one is returned. DISTINCT applies after all joins and filters have been processed, so it operates on the final set of rows about to be returned.

---

## How It Actually Works

The SQL engine does not process a SELECT statement in the order it is written. The logical execution order is the sequence in which the engine conceptually evaluates each clause to produce the result. First, FROM is processed: the engine identifies the source table (or tables, if there are joins) and produces a working set of rows. Second, WHERE filters that working set, removing rows that do not match the condition. Third, GROUP BY groups the remaining rows by the specified columns (if any). Fourth, HAVING filters the groups (if any). Fifth, SELECT determines which columns to include and evaluates any expressions or aliases. Sixth, ORDER BY sorts the result. Seventh, LIMIT and OFFSET restrict the number of rows returned.

This order matters because it determines what is visible to each clause. SELECT is evaluated fifth, so column aliases defined in SELECT are not yet defined when WHERE runs (step two) or when GROUP BY runs (step three). The database engine will refuse a query that uses a SELECT alias in a WHERE clause. However, aliases are available to ORDER BY because ORDER BY runs after SELECT. Knowing this order also explains why aggregate functions like COUNT and SUM must appear in SELECT or HAVING, not in WHERE — aggregate functions run after grouping, and WHERE runs before grouping.

Physically, the database engine may rewrite the query for performance. The optimizer might push a WHERE filter down into an index scan so that fewer rows are ever read, rather than reading all rows and then filtering. The logical execution order describes what the query means, not necessarily how the hardware executes it.

```sql
-- Basic SELECT: columns and table
SELECT id, name, email
FROM users;

-- SELECT *: returns all columns (convenient but fragile in application code)
SELECT *
FROM users;

-- Column alias with AS
SELECT
    id,
    price_cents / 100.0 AS price_dollars,
    name AS product_name
FROM products;

-- DISTINCT: return unique values of status
SELECT DISTINCT status
FROM orders;

-- DISTINCT on multiple columns: unique (user_id, status) pairs
SELECT DISTINCT user_id, status
FROM orders;

-- Computed column using a CASE expression
SELECT
    id,
    name,
    CASE
        WHEN price_cents < 1000 THEN 'budget'
        WHEN price_cents < 5000 THEN 'mid-range'
        ELSE 'premium'
    END AS price_tier
FROM products;

-- WHERE runs before SELECT: this query is INVALID in SQL
-- SELECT price_cents / 100.0 AS price_dollars
-- FROM products
-- WHERE price_dollars > 50;   -- ERROR: price_dollars not yet defined

-- Correct version: repeat the expression, or use a subquery
SELECT price_cents / 100.0 AS price_dollars
FROM products
WHERE price_cents > 5000;
```

---

## How It Connects

The WHERE clause is the filtering step of SELECT. Understanding SELECT execution order makes it clear why WHERE cannot see SELECT aliases, and understanding WHERE's own logic — NULL comparisons, AND/OR precedence — is the next step in writing correct queries.

[[where-clause|WHERE Clause]]

ORDER BY and LIMIT control the order and size of the result set. They run after SELECT in the logical execution order, which is why they can reference SELECT aliases. LIMIT's interaction with large offsets is a significant performance concern.

[[ordering-and-limiting|ORDER BY, LIMIT, OFFSET]]

Aggregate functions like COUNT, SUM, and AVG operate on groups of rows rather than individual rows. They are used in the SELECT clause and require GROUP BY to specify how rows are grouped. Understanding SELECT basics is the prerequisite for understanding aggregation.

[[aggregate-functions|Aggregate Functions]]

---

## Common Misconceptions

Misconception 1: "SELECT * is fine in application code as long as you only use the columns you need."
Reality: SELECT * retrieves every column from the database server and sends them all over the network to the application. Even if the application ignores most columns, the database still reads them from disk and the network still transmits them. On tables with many columns or large text/JSONB fields, SELECT * can be significantly slower than selecting only the needed columns. Beyond performance, SELECT * hides which columns the code depends on, making refactoring and schema changes dangerous.

Misconception 2: "I can use a column alias I defined in SELECT anywhere else in the query."
Reality: Aliases defined in the SELECT clause are only available in ORDER BY. They are not available in WHERE, GROUP BY (in PostgreSQL — some databases allow this as an extension), or HAVING. The logical execution order of SQL means SELECT runs late, after WHERE and GROUP BY have already processed their clauses. Reuse the full expression instead of the alias in WHERE and GROUP BY.

Misconception 3: "DISTINCT is a free operation that just deduplicates output."
Reality: DISTINCT requires the database to sort or hash all rows to identify duplicates. On large result sets, DISTINCT can be expensive. It also silently expands scope: if you write `SELECT DISTINCT customer_id FROM orders`, you get unique customer IDs. But if you later add a second column — `SELECT DISTINCT customer_id, status FROM orders` — you now get unique (customer_id, status) pairs, which is a much larger set. The behavior change can be subtle and produce unexpected row counts.

---

## Why It Matters in Practice

Understanding logical execution order changes how you debug queries. When a query returns an error like "column X does not exist," and the column is an alias you defined in SELECT, the execution order tells you why: the clause that is complaining runs before SELECT. The fix is always to use the original expression rather than the alias, or to wrap the whole query in a subquery so the alias exists in the outer scope.

Writing explicit column lists rather than SELECT * is one of the highest-leverage habits in SQL. It documents intent, prevents accidental exposure of sensitive columns (password hashes, tokens), reduces network overhead, and makes queries survive schema changes gracefully. Applications that use SELECT * tend to break in subtle ways as schemas evolve.

---

## What Breaks

Using a SELECT alias in a WHERE clause causes an error in PostgreSQL and most other databases. This is a common mistake when a developer writes the SELECT clause first (as they think), forgets the execution order, and then tries to filter on the alias.

```sql
-- FAILS: cannot reference alias 'discounted_price' in WHERE
SELECT price_cents * 0.9 AS discounted_price
FROM products
WHERE discounted_price < 1000;
-- ERROR: column "discounted_price" does not exist

-- CORRECT: repeat the expression in WHERE
SELECT price_cents * 0.9 AS discounted_price
FROM products
WHERE price_cents * 0.9 < 1000;

-- OR: use a subquery / CTE so the alias is available in the outer WHERE
WITH priced AS (
    SELECT id, price_cents * 0.9 AS discounted_price
    FROM products
)
SELECT * FROM priced WHERE discounted_price < 1000;
```

A SELECT * query that works perfectly for months can start returning wrong results or breaking JSON serialization in application code the moment a DBA adds a new column to the table. The application code may assume a fixed column order or a specific number of columns, and SELECT * changes the contract without any warning.

---

## Interview Angle

Common question forms:
- "What is the logical execution order of a SELECT statement?"
- "Can you use a SELECT alias in the WHERE clause? Why or why not?"
- "What is the difference between WHERE and HAVING?"

Answer frame:
State the logical execution order: FROM, WHERE, GROUP BY, HAVING, SELECT, ORDER BY, LIMIT. Use the execution order to explain why WHERE cannot see SELECT aliases. Contrast WHERE (filters rows before grouping) with HAVING (filters groups after grouping). If pushed further, mention DISTINCT's performance cost and the fragility of SELECT *.

---

## Related Notes

- [[where-clause|WHERE Clause]]
- [[ordering-and-limiting|ORDER BY, LIMIT, OFFSET]]
- [[aggregate-functions|Aggregate Functions]]
- [[group-by|GROUP BY]]
- [[what-is-sql|What is SQL]]
