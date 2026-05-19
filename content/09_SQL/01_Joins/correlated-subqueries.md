---
title: 17 - Correlated Subqueries
description: A correlated subquery references a column from the outer query and must re-execute for every row the outer query processes, making it O(n×m) and a common source of severe performance problems on large tables.
tags: [sql, layer-9, subqueries, performance]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# Correlated Subqueries

> A correlated subquery is a query that asks a new question for every row it examines - which means it can be the most expressive tool in SQL and, on large tables, the most expensive one.

---

## Quick Reference

**Core idea:**
- A correlated subquery references at least one column from the outer query in its WHERE clause
- Because of this reference, it cannot be evaluated once and cached - it must re-run for each row of the outer query
- Time complexity is O(n × m): n outer rows × m inner table rows scanned per execution
- The canonical example: employees who earn more than the average salary of their specific department
- Rewriting as a JOIN against a pre-aggregated subquery or using a window function eliminates the per-row re-execution

**Tricky points:**
- The correlated subquery may not look expensive in development against small tables - it becomes catastrophic only as table size grows
- EXISTS and NOT EXISTS always use a correlated subquery internally - but they short-circuit on the first match, making them faster than IN in many cases
- The query planner in PostgreSQL and SQL Server may automatically rewrite a correlated subquery as a JOIN - but this is not guaranteed, especially for complex patterns
- Scalar correlated subqueries in the SELECT list are executed once per output row - 100,000 rows means 100,000 subquery executions
- NOT EXISTS is generally safe with NULLs; correlated NOT IN has the same NULL trap as regular NOT IN

---

## What It Is

Imagine a manager at a company who needs to identify every employee earning above the average salary for their own department. The manager cannot simply compute one company-wide average and compare - the threshold changes department by department. For each employee, they must go to their department's record, compute that department's specific average, and then compare. For the engineering department, the benchmark is the engineering average. For sales, it is the sales average. For each of 500 employees, a separate department-specific calculation is needed. A correlated subquery is SQL performing exactly this per-row calculation - for each row in the outer query, the inner query runs fresh, using a value from the current outer row as part of its filter.

The word "correlated" refers to the dependency between the inner and outer queries. In a non-correlated subquery, the inner query has no reference to the outer query - it can be evaluated in isolation, once, before the outer query even begins. In a correlated subquery, the inner query contains a reference to the outer query's current row (typically written as `outer_alias.column`), creating a tight coupling. The engine must evaluate the inner query repeatedly - once for each row that the outer query produces as candidates - because each evaluation requires a different input value.

This structure makes correlated subqueries the most powerful but also potentially the most expensive form of subquery. The power comes from the ability to perform row-specific calculations that depend on the context of each outer row. The cost comes from the multiplicative execution model: if the outer query produces 10,000 rows and the inner query scans 50,000 rows each time, the total work is 500 million row evaluations. On large production tables, this pattern is often the root cause of queries that run for minutes or hours when they should run in seconds.

Understanding when a subquery is correlated versus non-correlated is a diagnostic skill. Any subquery that references a column prefixed with the outer query's table alias is correlated. Any subquery that contains only references to its own tables and constants is non-correlated and safe from the per-row evaluation problem.

---

## How It Actually Works

At the execution level, the database engine handles a correlated subquery by embedding it in the iteration loop of the outer query. For each candidate row from the outer query, the values of the referenced outer columns are substituted into the inner query's WHERE clause, and the inner query is executed. This is sometimes called a nested loop evaluation - the outer query drives an outer loop, and the inner query is the inner loop body.

Some query planners are capable of decorrelating certain correlated subqueries automatically. PostgreSQL, for instance, will often rewrite a correlated EXISTS or a correlated scalar subquery as a hash join when the pattern is recognizable. This is called "decorrelation" or "unnesting," and when it works, it eliminates the per-row execution overhead entirely. However, decorrelation is not guaranteed - it depends on the query structure, the presence of aggregation, the data types involved, and the planner's cost estimates. Complex correlated patterns frequently defeat the decorrelation logic, and the developer cannot rely on the planner to save them.

```sql
-- Canonical example: employees earning above their department's average
-- Correlated: the subquery re-runs for every row in the outer query
SELECT e.name, e.salary, e.department_id
FROM employees e
WHERE e.salary > (
    SELECT AVG(e2.salary)
    FROM employees e2
    WHERE e2.department_id = e.department_id  -- correlation: references outer 'e'
);
-- If employees has 100,000 rows across 20 departments,
-- the AVG subquery runs 100,000 times (once per employee row evaluated)

-- Rewrite 1: JOIN against pre-aggregated subquery - runs the AVG once per department
SELECT e.name, e.salary, e.department_id
FROM employees e
JOIN (
    SELECT department_id, AVG(salary) AS dept_avg
    FROM employees
    GROUP BY department_id
) AS dept_stats ON e.department_id = dept_stats.department_id
WHERE e.salary > dept_stats.dept_avg;
-- AVG runs exactly 20 times (once per department), then joined to all 100,000 employees

-- Rewrite 2: window function - computes per-department average inline, one table scan
SELECT name, salary, department_id
FROM (
    SELECT
        name,
        salary,
        department_id,
        AVG(salary) OVER (PARTITION BY department_id) AS dept_avg
    FROM employees
) AS enriched
WHERE salary > dept_avg;

-- Correlated EXISTS: find employees who have submitted at least one expense report
SELECT e.name
FROM employees e
WHERE EXISTS (
    SELECT 1
    FROM expense_reports er
    WHERE er.employee_id = e.id   -- correlation
);
-- EXISTS short-circuits on the first match - much faster than IN for large tables
-- Modern planners frequently rewrite this as a semi-join

-- Correlated scalar subquery in SELECT: most dangerous form
SELECT
    e.name,
    e.salary,
    (
        SELECT AVG(e2.salary)
        FROM employees e2
        WHERE e2.department_id = e.department_id  -- correlation
    ) AS dept_avg
FROM employees e;
-- This executes the AVG subquery once per row in the final output
-- 100,000 output rows = 100,000 AVG executions
-- Rewrite: use a window function AVG(salary) OVER (PARTITION BY department_id) instead

-- When correlated subqueries are unavoidable: checking most-recent related record
SELECT e.name, e.department_id, latest_review.review_date
FROM employees e
JOIN (
    SELECT DISTINCT ON (employee_id) employee_id, review_date
    FROM performance_reviews
    ORDER BY employee_id, review_date DESC
) AS latest_review ON latest_review.employee_id = e.id;
-- PostgreSQL DISTINCT ON avoids correlated subquery for "latest per group" pattern
```

The EXISTS form of correlated subquery deserves special attention. `WHERE EXISTS (SELECT 1 FROM ... WHERE outer.col = inner.col)` is correlated - the inner query references the outer. But EXISTS is evaluated as a semi-join: the engine checks whether at least one matching row exists and stops immediately when it finds the first one. It does not enumerate all matches. This early-exit behavior makes EXISTS substantially faster than `IN (subquery)` in cases where many rows match - IN must collect all matching values into a set, while EXISTS stops at the first.

---

## How It Connects

Correlated subqueries extend the non-correlated subquery concept with per-row execution semantics. They are the most performance-sensitive SQL pattern, and rewriting them correctly is one of the highest-value SQL optimization skills. The two primary rewrites - JOINs with pre-aggregated subqueries, and window functions - each have their own notes with full detail.

The correlated subquery in SELECT is essentially a manual, SQL-level version of the N+1 problem that ORMs create at the application level. Both patterns involve issuing a separate query for each row in a result set.

[[subqueries|Subqueries]] - the non-correlated baseline; read this first to understand the structural difference between correlated and non-correlated forms.

[[window-functions|Window Functions]] - the most powerful and efficient rewrite for correlated aggregate scalar subqueries; AVG/SUM/RANK OVER (PARTITION BY ...) replaces the per-row correlated pattern.

[[n-plus-one-problem|N+1 Problem]] - the application-level equivalent of the correlated subquery problem; understanding both reinforces the general pattern of "per-row re-querying."

[[explain-analyze|EXPLAIN ANALYZE]] - the diagnostic tool for confirming whether a query is executing a correlated subquery and measuring the actual cost.

---

## Common Misconceptions

Misconception 1: "EXISTS always means a correlated subquery."
Reality: EXISTS can be used with both correlated and non-correlated subqueries. `WHERE EXISTS (SELECT 1 FROM some_table WHERE condition_on_outer.col = inner.col)` is correlated. `WHERE EXISTS (SELECT 1 FROM config WHERE feature_flag = 'enabled')` is non-correlated and evaluated once. The presence of EXISTS does not determine correlation - the presence of an outer-query column reference does.

Misconception 2: "The database engine always detects and optimizes correlated subqueries."
Reality: Modern planners can decorrelate certain patterns - particularly simple correlated EXISTS and scalar aggregates - but decorrelation has limits. Complex patterns with GROUP BY, DISTINCT, or multiple levels of correlation defeat most planners' decorrelation logic. You cannot rely on the engine to fix an inefficient correlated pattern; you must rewrite it explicitly.

Misconception 3: "Rewriting a correlated subquery as a JOIN always produces the same result."
Reality: The JOIN rewrite changes semantics for rows that have no match in the inner table. A correlated scalar subquery that returns NULL when there is no match (because `AVG` of zero rows is NULL) behaves differently from a JOIN that excludes those rows entirely. Use a LEFT JOIN when the outer rows with no inner matches must be preserved, and use COALESCE to handle the NULLs in the joined result.

---

## Why It Matters in Practice

Correlated subqueries are one of the most common root causes of slow queries in production databases. They are especially insidious because they work perfectly - and fast - on small datasets in development, then suddenly become unusable as data volumes grow. A query that processes 100 rows with one correlated subquery execution each takes 100 subquery evaluations. The same query on a table that has grown to 1 million rows takes 1 million subquery evaluations. The slowdown is linear with table size at best, and potentially worse if the inner table also grows.

The rewriting skill - recognizing a correlated subquery and transforming it into a JOIN-with-aggregation or a window function - is one of the most directly impactful SQL optimizations. It converts O(n × m) queries into O(n + m) or better. In real-world scenarios, this is the difference between a report that times out and one that runs in under a second. Knowing both the window function rewrite (for aggregation patterns) and the derived-table JOIN rewrite (for existence-checking patterns) covers the vast majority of correlated subquery cases encountered in practice.

---

## What Breaks

**Correlated scalar subquery returns multiple rows.** A correlated scalar subquery must return exactly zero or one row per outer row. If it returns more than one, the query fails at runtime with a "subquery returned more than one row" error. This is hard to detect in testing if the test data happens to have only one match per outer row.

```sql
-- BROKEN: if an employee is in multiple departments (data anomaly), this fails
SELECT e.name,
    (SELECT dept.name FROM departments dept WHERE dept.id = e.department_id) AS dept_name
FROM employees e;
-- If department_id constraint is missing and duplicates exist, runtime error

-- FIXED: add LIMIT 1 (accept the ambiguity) or fix the data model
(SELECT dept.name FROM departments dept WHERE dept.id = e.department_id LIMIT 1)
```

**Correlated subquery inside a view runs once per outer query row.** A view that contains a correlated subquery is re-evaluated for every row of any query that selects from that view. This is a common performance trap where the view appears to be a static table but is actually executing expensive subqueries on every use.

```sql
-- View with correlated subquery - looks innocent, runs expensively
CREATE VIEW employee_dept_avg AS
SELECT
    e.id,
    e.name,
    e.salary,
    (SELECT AVG(e2.salary) FROM employees e2 WHERE e2.department_id = e.department_id) AS dept_avg
FROM employees e;

-- Every query against this view re-executes the correlated AVG
SELECT * FROM employee_dept_avg WHERE dept_avg > 80000;
-- Fix: rewrite the view using a window function
```

**NOT IN with correlated NULLs returns zero rows.** The NULL trap applies to correlated NOT IN as well. If the inner query can return NULL values, `NOT IN` gives no results rather than the expected filtered set.

```sql
-- BROKEN: if any employee has no manager (manager_id IS NULL), returns zero rows
SELECT e.name
FROM employees e
WHERE e.id NOT IN (
    SELECT manager_id FROM employees WHERE manager_id IS NOT NULL AND department_id = e.department_id
);
-- The correlated filter helps but does not fully eliminate the NULL risk

-- SAFE: always prefer NOT EXISTS for exclusion patterns
SELECT e.name
FROM employees e
WHERE NOT EXISTS (
    SELECT 1 FROM employees sub
    WHERE sub.manager_id = e.id AND sub.department_id = e.department_id
);
```

---

## Interview Angle

Common question forms:
- "What is a correlated subquery and why can it be slow?"
- "How would you rewrite a correlated subquery for performance?"
- "Write a query to find all employees who earn more than the average salary of their department."

Answer frame:
Define correlated subquery precisely: it references a column from the outer query, so it must re-execute once per outer-query row. Give the time complexity: O(n × m). For the performance rewrite, describe two paths: (1) move the aggregation into a derived table joined back to the main query, so the aggregate runs once per group instead of once per row; (2) use a window function with PARTITION BY to compute the same aggregation in a single pass. For the canonical employee/department example, write the correlated version first, then show the window function rewrite. This demonstrates both the problem and the solution clearly.

---

## Related Notes

- [[subqueries|Subqueries]]
- [[window-functions|Window Functions]]
- [[n-plus-one-problem|N+1 Problem]]
- [[explain-analyze|EXPLAIN ANALYZE]]
- [[joins-overview|Joins Overview]]
- [[aggregate-functions|Aggregate Functions]]
- [[cte|CTEs]]
