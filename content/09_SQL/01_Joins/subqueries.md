---
title: 16 - Subqueries
description: A subquery is a SELECT statement nested inside another SQL statement, enabling modular query composition and expressive filtering that a flat query cannot achieve.
tags: [sql, layer-9, subqueries]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Subqueries

> A subquery is a query within a query — it lets you build complex results from simpler parts, but its performance depends critically on whether the inner query runs once or once per row.

---

## Quick Reference

**Core idea:**
- A subquery is a SELECT statement enclosed in parentheses, nested inside another SQL statement
- Scalar subquery: returns a single value (one row, one column); usable anywhere an expression is valid
- Row subquery: returns a single row of multiple columns
- Table subquery (derived table): returns multiple rows and columns; used in FROM as a virtual table
- Non-correlated subqueries are evaluated once; correlated subqueries are evaluated once per row of the outer query

**Tricky points:**
- `IN (subquery)` fails silently and returns wrong results if the subquery returns any NULL values — use `EXISTS` or handle NULLs explicitly
- A subquery in SELECT that returns more than one row causes a runtime error — scalar subqueries must return exactly 0 or 1 row
- Derived tables (subquery in FROM) must have an alias in most databases — omitting the alias causes a syntax error
- CTEs are often more readable than deeply nested subqueries and are always preferable for queries used by others
- The query planner may or may not materialize a subquery result — the actual execution strategy depends on the engine and the query structure

---

## What It Is

Consider how a researcher works. They do not write a single massive report in one pass. They gather preliminary data, extract a summary from that data, and then use that summary as input to the next phase of analysis. A subquery works the same way: the inner query is evaluated first (or per-row, for correlated variants), producing an intermediate result that the outer query then uses. The outer query does not need to know how the inner result was produced — it treats the subquery's output as a simple value, list, or table.

Subqueries exist because SQL is a declarative language built on the concept of set operations. The result of any SELECT statement is a set (technically a multiset, since SQL allows duplicates). Because a set of rows is first-class in SQL, you can use a SELECT result anywhere you would use a table or a value. This composability is what makes subqueries powerful: you can filter by the result of a calculation, join to a computed set, or retrieve a single scalar value from a related computation, all within a single query sent to the database.

The three structural forms of subqueries cover distinct use cases. A scalar subquery — `(SELECT MAX(salary) FROM employees)` — returns a single value and can appear in a SELECT list, a WHERE condition, or a HAVING clause anywhere a literal value could go. A table subquery in the FROM clause — sometimes called a derived table or inline view — is treated as if it were a real table. It must have an alias, and the outer query can select from it, filter it, and join it to other tables. A subquery in a WHERE clause using IN, NOT IN, EXISTS, or NOT EXISTS checks whether rows from the outer query satisfy a membership condition defined by the inner query.

The distinction between correlated and non-correlated subqueries is the most important performance consideration. A non-correlated subquery does not reference any column from the outer query. It can be evaluated once, its result cached, and that single result used for every row of the outer query. A correlated subquery references at least one column from the outer query — it must be re-evaluated for each row the outer query processes. This re-evaluation is what makes correlated subqueries potentially expensive on large tables. The correlated subquery is covered in depth in its own dedicated note.

---

## How It Actually Works

The query engine evaluates subqueries as part of its overall execution plan. For a non-correlated subquery — one that has no reference to the outer query — the engine typically evaluates the inner query first, materializes the result (stores it temporarily), and then uses that result in the outer query. The planner may inline the subquery into a join or apply other transformations, but the logical behavior is "evaluate once, use the result everywhere."

For subqueries used with IN, the engine builds the result of the inner query as a set and then checks each outer-query row against that set. This is semantically a membership test. Internally, the optimizer often rewrites an `IN (subquery)` as a semi-join — a join that returns only one row from the outer table per match, without requiring explicit deduplication. This semi-join optimization is why `IN (subquery)` and `EXISTS (subquery)` often produce the same execution plan in modern databases like PostgreSQL.

```sql
-- Scalar subquery: single value used in a WHERE condition
SELECT name, salary
FROM employees
WHERE salary > (SELECT AVG(salary) FROM employees);

-- Scalar subquery in SELECT list: attach a computed value to each row
SELECT
    department_id,
    name,
    salary,
    (SELECT AVG(salary) FROM employees) AS company_avg   -- evaluated once
FROM employees;

-- Derived table (subquery in FROM): compute aggregates, then filter or join
SELECT dept_stats.department_id, dept_stats.avg_salary
FROM (
    SELECT department_id, AVG(salary) AS avg_salary
    FROM employees
    GROUP BY department_id
) AS dept_stats
WHERE dept_stats.avg_salary > 80000;

-- IN subquery: employees in high-budget departments
SELECT name, department_id
FROM employees
WHERE department_id IN (
    SELECT id
    FROM departments
    WHERE budget > 1000000
);

-- NOT IN subquery: employees NOT in high-budget departments
-- WARNING: if the subquery returns any NULL, NOT IN returns no rows
SELECT name
FROM employees
WHERE department_id NOT IN (
    SELECT id
    FROM departments
    WHERE budget > 1000000
    -- Add: AND id IS NOT NULL — to avoid the NULL trap
);

-- EXISTS: employees who have submitted at least one expense report
SELECT e.name
FROM employees e
WHERE EXISTS (
    SELECT 1
    FROM expense_reports er
    WHERE er.employee_id = e.id
);
-- EXISTS is preferred over IN for large subquery result sets

-- NOT EXISTS: employees with no expense reports (safer than NOT IN with NULLs)
SELECT e.name
FROM employees e
WHERE NOT EXISTS (
    SELECT 1
    FROM expense_reports er
    WHERE er.employee_id = e.id
);
```

Subqueries in FROM clauses must always have an alias. The alias gives the outer query a name to reference when selecting columns from the derived table. Without the alias, most databases raise a syntax error. The column names available from a derived table are those produced by the inner SELECT — you can use column aliases in the inner query to control what names appear in the outer scope.

CTEs (WITH clauses) are an alternative to subqueries in FROM that often produce equivalent query plans but significantly improve readability. A deeply nested set of subqueries in FROM can be refactored into a sequence of named CTEs, each building on the previous, with the final SELECT reading from the last CTE. The logical structure becomes linear and easy to follow rather than nested and difficult to parse. The performance is typically identical, though some engines do not materialize CTEs by default and treat them as inline subqueries.

---

## How It Connects

Subqueries are a fundamental composability mechanism in SQL. They connect directly to the SELECT basics — the result of any SELECT is itself a first-class relation — and to filtering with WHERE. The EXISTS form of subquery connects to the concept of correlated subqueries, which extends the non-correlated subquery concept to per-row evaluation.

CTEs are the modern, more readable way to express the same logic as subqueries in FROM. Understanding both forms is necessary because subqueries appear in legacy code and in queries where CTE overhead is a concern.

[[select-basics|SELECT Basics]] — the foundation; any SELECT result can be nested as a subquery.

[[where-clause|WHERE Clause]] — IN, NOT IN, EXISTS, and NOT EXISTS are all WHERE clause constructs that use subqueries.

[[correlated-subqueries|Correlated Subqueries]] — the per-row subquery evaluation that makes some subquery patterns expensive and how to rewrite them.

[[cte|CTEs]] — the readable alternative to complex subqueries in FROM; covers when to use CTEs vs subqueries.

---

## Common Misconceptions

Misconception 1: "NOT IN (subquery) safely finds rows with no match."
Reality: If the subquery returns even a single NULL value, `NOT IN` returns no rows at all — not because no match was found, but because `x NOT IN (..., NULL, ...)` evaluates to NULL (unknown) for every value of x. This is one of the most dangerous silent bugs in SQL. `NOT EXISTS` is the safe alternative, as it handles NULLs correctly and is semantically clearer.

Misconception 2: "A subquery is always slower than a JOIN."
Reality: Modern query planners frequently rewrite subqueries as joins internally. An `IN (subquery)` is often transformed into a semi-join by the optimizer, producing the same execution plan as an equivalent INNER JOIN. Whether a subquery or a join is faster depends on the query, the indexes available, and the planner's cost estimates — not on which syntax form you chose.

Misconception 3: "Subqueries in the SELECT list are evaluated once."
Reality: A scalar subquery in the SELECT list that references columns from the outer query (a correlated scalar subquery) is evaluated once per row. Only a non-correlated scalar subquery — one that references no outer columns — is evaluated once and cached. `(SELECT AVG(salary) FROM employees)` is evaluated once. `(SELECT MAX(salary) FROM employees WHERE department_id = e.department_id)` is evaluated once per row.

---

## Why It Matters in Practice

Subqueries are unavoidable in real SQL work. They appear in reporting queries (compute a denominator once and use it across multiple rows), in data quality checks (find rows in one table not in another), in conditional aggregation (filter the outer result by aggregated values from a subquery), and in any situation where the data needed for a filter must itself be derived from a query. A developer who writes only flat queries is limited in the problems they can solve.

The NULL trap in NOT IN is a concrete, high-stakes issue. A developer who writes `WHERE id NOT IN (SELECT manager_id FROM employees)` expecting to find all non-managers will get zero results if any employee has a NULL manager_id — which is almost always the case for the root of the org chart. This query silently returns nothing, with no error, no warning, and no indication of the problem. Understanding this trap and knowing to use NOT EXISTS instead is a direct safety concern for any code that makes decisions based on set membership.

---

## What Breaks

**NOT IN with NULLs returns zero rows.** The most dangerous and silent subquery bug.

```sql
-- Table: employees with manager_id, where CEO has manager_id = NULL
-- BROKEN: returns zero rows because NULL is in the manager_id set
SELECT name FROM employees
WHERE id NOT IN (SELECT manager_id FROM employees);

-- FIXED: exclude NULLs from the subquery
SELECT name FROM employees
WHERE id NOT IN (SELECT manager_id FROM employees WHERE manager_id IS NOT NULL);

-- BETTER: use NOT EXISTS (correct by design with NULLs)
SELECT e.name FROM employees e
WHERE NOT EXISTS (
    SELECT 1 FROM employees m WHERE m.manager_id = e.id
);
```

**Scalar subquery returning multiple rows causes a runtime error.** If a subquery intended to return a single value returns more than one row, the query fails with a "subquery returned more than one row" error.

```sql
-- BROKEN: if a department has multiple employees named 'Alice'
SELECT name, salary FROM employees
WHERE salary = (SELECT salary FROM employees WHERE name = 'Alice');
-- Error if Alice appears more than once

-- FIXED: use aggregate or limit to ensure scalar result
WHERE salary = (SELECT MAX(salary) FROM employees WHERE name = 'Alice')
```

**Derived table without alias causes syntax error.** Every subquery used in FROM must be given an alias.

```sql
-- BROKEN in most databases
SELECT * FROM (SELECT id, name FROM employees WHERE active = true);
-- ERROR: subquery in FROM must have an alias

-- FIXED
SELECT * FROM (SELECT id, name FROM employees WHERE active = true) AS active_employees;
```

---

## Interview Angle

Common question forms:
- "What is the difference between a subquery and a JOIN?"
- "Why is NOT IN dangerous with NULLs? What should you use instead?"
- "What is a derived table / inline view?"

Answer frame:
For subquery vs JOIN: both can express similar logic; the planner often produces the same plan; subqueries are sometimes more readable for complex intermediate computations; JOINs are often clearer for straightforward relationship traversal. For the NULL question: explain that `x NOT IN (..., NULL)` evaluates to NULL because SQL cannot confirm x is not equal to an unknown value — so every row's membership is uncertain and the result is empty. The fix is `NOT EXISTS` or filtering NULLs from the subquery. For derived tables: a subquery in FROM that acts as a virtual table, must have an alias, and can be queried by the outer SELECT like any real table.

---

## Related Notes

- [[select-basics|SELECT Basics]]
- [[where-clause|WHERE Clause]]
- [[correlated-subqueries|Correlated Subqueries]]
- [[cte|CTEs]]
- [[joins-overview|Joins Overview]]
- [[aggregate-functions|Aggregate Functions]]
- [[having-clause|HAVING Clause]]
