---
title: 38 - Views
description: A view is a named saved SELECT query that behaves like a table, letting you abstract complexity and control data exposure without duplicating data.
tags: [sql, layer-9, views, abstraction]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Views

> A view is a stored query masquerading as a table — it gives you a stable, named interface over complex SQL without ever touching the physical storage.

---

## Quick Reference

**Core idea:**
- A view is a named SELECT query saved in the database catalog
- Querying a view executes the underlying SELECT at that moment — no data is stored
- Views can simplify complex joins and subqueries behind a clean name
- Column names in a view can differ from the underlying table columns
- Simple single-table views can often be updated, inserted into, or deleted through
- Views can restrict column access, acting as a security boundary

**Tricky points:**
- Views do not cache results — every query against a view re-runs the underlying SQL
- Nesting views inside views compounds performance problems silently
- Updatable views have strict conditions that are easy to violate accidentally
- Dropping a table breaks dependent views without immediate warning at drop time
- A view used inside a JOIN is expanded inline — the planner sees the full subquery

---

## What It Is

Think of a view as a window cut into a wall. The window does not contain what you see through it — the room behind it does. Every time you look through the window, you see the current state of the room. If someone moves furniture, the next time you look the furniture is already moved. The window itself is just a frame, a fixed perspective. That is what a view is: a fixed frame through which you see live table data.

A view is created with CREATE VIEW and stores nothing but the SELECT statement itself. The database catalog records the view name and its defining query. When any session runs SELECT * FROM my_view, the database engine substitutes the view's definition inline and executes it as if the caller had typed the full query themselves. There is no separate storage, no copy of the rows, no cached result set. The view is purely syntactic sugar backed by a permanent record in the system catalog.

This design has two important consequences. First, views always return fresh data — they are immune to the staleness problems that plague caches. Second, they cost exactly as much to query as the underlying SQL costs to execute. A view wrapping a five-table join with a correlated subquery is exactly as expensive as running that query directly. The view abstraction is a developer convenience, not a performance optimization.

Beyond simplification, views serve as an access control mechanism. A database administrator can grant SELECT on a view while revoking SELECT on the underlying tables. Users of the view see exactly the columns the view exposes and nothing else. Sensitive columns — salaries, personal identifiers, internal codes — simply do not appear in the view definition, and users have no pathway to reach them through the view even if they know the column exists.

---

## How It Actually Works

When you issue CREATE VIEW employee_summary AS SELECT id, name, department FROM employees WHERE active = true, the database stores that SELECT verbatim (or as a parsed representation) in the system catalog table — in PostgreSQL this is pg_views. No rows are read or written at creation time. The view definition is validated syntactically and the referenced tables are confirmed to exist, but no data movement occurs.

At query time, the planner performs view expansion. SELECT * FROM employee_summary WHERE department = 'Engineering' becomes — after expansion — SELECT id, name, department FROM employees WHERE active = true AND department = 'Engineering'. The planner then optimizes this combined query holistically. It can push the WHERE clause inside the view, use indexes on the employees table, and produce the same execution plan it would produce if you had written the full query yourself. This is why views carry no inherent performance penalty relative to the query they encapsulate, but also why they carry no inherent benefit.

```sql
-- Create a view hiding complexity
CREATE VIEW active_orders AS
SELECT
    o.id,
    o.created_at,
    c.name AS customer_name,
    SUM(oi.quantity * oi.unit_price) AS total
FROM orders o
JOIN customers c ON c.id = o.customer_id
JOIN order_items oi ON oi.order_id = o.id
WHERE o.status != 'cancelled'
GROUP BY o.id, o.created_at, c.name;

-- Caller sees a simple interface
SELECT customer_name, total
FROM active_orders
WHERE total > 1000
ORDER BY total DESC;
```

Updatable views are a special case. PostgreSQL allows INSERT, UPDATE, and DELETE through a view if the view meets a strict set of conditions: it must reference exactly one table or updatable view, it must not use DISTINCT or GROUP BY or HAVING or LIMIT, it must not use set operations (UNION, INTERSECT, EXCEPT), and it must not use aggregate or window functions. When these conditions hold, modifications to the view are translated into modifications on the underlying table. When they do not hold, the view is read-only and attempts to modify it will fail with an error, unless a INSTEAD OF trigger has been defined to handle the modification manually.

```sql
-- Simple updatable view
CREATE VIEW public_employees AS
SELECT id, name, department FROM employees;

-- This works because the view is simple enough
UPDATE public_employees SET department = 'Engineering' WHERE id = 42;

-- Create a security-restricting view (only certain columns visible)
CREATE VIEW hr_safe_employees AS
SELECT id, name, department, hire_date FROM employees;
-- salary column is simply absent — no user of this view can access it
```

---

## How It Connects

Views sit on top of the SELECT and JOIN mechanics from earlier in this layer. Understanding how views are expanded inline explains why the query optimizer still has full freedom to apply index lookups and partition pruning through a view. A view is not a barrier to optimization — it is transparent to the planner.

The natural successor to a view is the materialized view, which solves the one problem views cannot: expensive queries that are run frequently and whose slight staleness is acceptable. When a view's underlying query is too slow to re-run on every request, a materialized view stores the results and trades freshness for speed.

[[select-basics|SELECT Basics]]
[[joins-overview|Joins Overview]]
[[materialized-views|Materialized Views]]
[[subqueries|Subqueries]]

---

## Common Misconceptions

Misconception 1: "Views store data, so querying them is faster than querying the raw tables."
Reality: A regular view stores no data whatsoever. It stores only the SQL text. Every query against a view re-executes the underlying SELECT from scratch. Querying a view on a large table with a complex join is no faster than writing that join yourself. For cached results, you need a materialized view or an explicit application-layer cache.

Misconception 2: "Updating a view always works the same as updating a table."
Reality: Most views are read-only. Updatable views require very specific conditions — single underlying table, no aggregation, no DISTINCT, no set operations. Violating any condition silently makes the view read-only, and DML operations fail at runtime. Production code that relies on updatable views must be thoroughly tested and the conditions must be documented, because a later ALTER VIEW that adds a GROUP BY will break all updates silently.

Misconception 3: "Dropping a view removes the underlying data."
Reality: Dropping a view removes only the view definition from the catalog. The underlying tables and their data are completely unaffected. Conversely, dropping an underlying table will break any views that reference it, but the views themselves persist in the catalog in a broken state until they are dropped or the table is recreated.

---

## Why It Matters in Practice

Views are the SQL equivalent of named functions in application code. They let teams agree on a canonical way to express a complex query, give it a stable name, and refer to it consistently across dozens of reports and application queries. Without views, the same five-table join appears copy-pasted in fifty places, and a schema change requires hunting down every copy. With a view, you change the view definition once.

In multi-role database architectures — where application users, reporting users, and admin users have different accounts — views are the primary mechanism for column-level access control. Granting SELECT on a carefully designed view is cleaner and more auditable than row-level security policies for simple use cases. The view itself documents exactly what is exposed and to whom, which makes security reviews straightforward.

---

## What Breaks

**Nested view performance collapse.** A reporting team builds view_a, then builds view_b on top of view_a, then view_c on top of view_b. Each adds a WHERE clause and a JOIN. By the time a dashboard query hits view_c, the planner is expanding three levels of subquery into a single monster query. The planner may not be able to push predicates through all layers efficiently, and what looked like a clean abstraction becomes an unexplained slow query.

```sql
-- Dangerous pattern: views on views on views
CREATE VIEW daily_sales AS
    SELECT date, SUM(amount) FROM orders GROUP BY date;

CREATE VIEW weekly_sales AS
    SELECT DATE_TRUNC('week', date) AS week, SUM(amount)
    FROM daily_sales  -- expands to a subquery; aggregation on aggregation
    GROUP BY 1;
-- The planner cannot always optimize through the inner GROUP BY
```

**Schema drift breaking views silently.** A developer adds a NOT NULL column to the orders table without updating the orders_summary view. The view still works because it does not reference the new column. Later, someone alters the view to add a * — or the view references a renamed column — and suddenly it fails at runtime. PostgreSQL will not proactively validate view definitions against underlying schema changes.

**Security bypass via view chaining.** A user with access to view_a (which hides salary) also has access to view_b (which joins employees back into the result set). If the DBA did not audit view_b carefully, the user may be able to see salary through the second view. Views are only as secure as the thought put into their definitions.

---

## Interview Angle

Common question forms:
- "What is a view and what is it used for?"
- "What is the difference between a view and a materialized view?"
- "Can you update data through a view?"
- "Do views improve query performance?"

Answer frame:
Lead with the definition — a named stored SELECT, no data stored. Then address performance: views do not cache, querying them is identical in cost to running the underlying query. Cover the two main use cases: abstraction over complex queries and column-level security. For updatable views, name the conditions briefly and note the risks. Close by contrasting with materialized views to show you understand the full picture.

---

## Related Notes

- [[materialized-views|Materialized Views]]
- [[subqueries|Subqueries]]
- [[joins-overview|Joins Overview]]
- [[select-basics|SELECT Basics]]
- [[sql-interview-patterns|SQL Interview Patterns]]
