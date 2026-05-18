---
title: Common Table Expressions (CTEs)
description: A CTE is a named temporary result set defined with the WITH clause that makes complex queries readable by breaking them into clearly labeled steps.
tags: [sql, layer-9, cte, readability]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Common Table Expressions (CTEs)

> A CTE names a subquery at the top of the query so the rest of the query can reference it like a table — the primary value is readability and maintainability, not performance.

---

## Quick Reference

**Core idea:**
- A CTE is introduced with WITH cte_name AS (SELECT ...) and can be referenced by name in the subsequent query
- Multiple CTEs can be chained in one WITH block, separated by commas; each CTE can reference the ones defined before it
- CTEs are logically equivalent to inline subqueries in most databases — the optimizer treats them the same
- PostgreSQL 12+ inlines CTEs by default; earlier versions materialized them (computed once and stored), which could help or hurt performance
- The MATERIALIZED and NOT MATERIALIZED keywords in PostgreSQL allow explicit control over this behavior
- Recursive CTEs use a different structure (UNION ALL) and are covered separately

**Tricky points:**
- CTEs are not inherently faster than subqueries — any perceived performance difference in modern PostgreSQL is due to inlining behavior, not the CTE itself
- A CTE defined in a WITH block cannot be referenced outside the single statement it belongs to — it is not a view or a temporary table
- In PostgreSQL pre-12, CTEs were always materialized (optimization fences) — this could prevent the optimizer from pushing WHERE predicates into the CTE, causing full scans
- The same CTE can be referenced multiple times in the same query; whether the database re-executes or caches the result depends on the MATERIALIZED setting
- CTEs cannot be indexed or have statistics; for large intermediate results that are reused, a temporary table with an index may outperform a CTE

---

## What It Is

Writing a complex SQL query without CTEs is like writing a long legal document as a single unbroken paragraph. Every clause refers back to earlier clauses, every condition depends on something defined three hundred words earlier, and following the logic requires reading the whole thing several times. CTEs are the paragraph breaks and section headings of SQL — they let you name each step of a multi-stage query, define it once at the top, and refer to it by name in later steps.

The WITH keyword introduces the CTE block. Each CTE is a named SELECT statement enclosed in parentheses. After all CTEs are defined, the final SELECT (or INSERT, UPDATE, DELETE) statement references them as if they were ordinary tables. The CTE definitions exist only for the duration of that one statement — they are not stored anywhere and are not visible to other queries.

The most important thing to understand about CTEs is what they are not. They are not a performance optimization tool in most modern databases. A CTE in PostgreSQL 12 or later is inlined by the optimizer, meaning it is treated identically to an equivalent inline subquery — the execution plan will be the same. CTEs are a readability and maintainability tool. They let developers decompose a query into named, understandable steps, which makes the query easier to read, review, test, and modify.

---

## How It Actually Works

The syntax for a single CTE is straightforward. The WITH keyword opens the block, the CTE is named and defined, and then the main query references it.

```sql
-- Single CTE: name the intermediate result, then query it
WITH high_value_customers AS (
    SELECT customer_id, SUM(amount) AS total_spent
    FROM orders
    GROUP BY customer_id
    HAVING SUM(amount) > 1000
)
SELECT c.name, h.total_spent
FROM customers c
JOIN high_value_customers h ON c.id = h.customer_id
ORDER BY h.total_spent DESC;
```

Multiple CTEs are defined in a single WITH block, separated by commas. Each CTE can reference previously defined CTEs in the same block, enabling a step-by-step decomposition of a complex query.

```sql
-- Chaining CTEs: each builds on the previous
WITH
-- Step 1: aggregate orders per customer
customer_totals AS (
    SELECT customer_id, SUM(amount) AS total_spent, COUNT(*) AS order_count
    FROM orders
    WHERE created_at >= '2025-01-01'
    GROUP BY customer_id
),
-- Step 2: rank customers by total spent
ranked_customers AS (
    SELECT
        customer_id,
        total_spent,
        order_count,
        RANK() OVER (ORDER BY total_spent DESC) AS spending_rank
    FROM customer_totals
),
-- Step 3: keep only the top 10
top_customers AS (
    SELECT * FROM ranked_customers WHERE spending_rank <= 10
)
-- Final query: join back to get customer names
SELECT cu.name, tc.total_spent, tc.order_count, tc.spending_rank
FROM top_customers tc
JOIN customers cu ON tc.customer_id = cu.id
ORDER BY tc.spending_rank;
```

The CTE is also the standard wrapper for window function results that need to be filtered. Window functions cannot appear in WHERE, so the CTE computes the window function in the inner query and the outer query applies the filter.

```sql
-- CTE as a window function wrapper (very common pattern)
WITH ranked AS (
    SELECT
        product_id,
        category,
        revenue,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC) AS rn
    FROM products
)
SELECT product_id, category, revenue
FROM ranked
WHERE rn = 1;
```

In PostgreSQL, the MATERIALIZED keyword forces the CTE to be computed once and stored as an intermediate result, regardless of the inlining default. This is useful when the CTE is expensive to compute and is referenced multiple times in the same query — materializing it avoids redundant re-computation. NOT MATERIALIZED forces inlining, allowing the optimizer to push predicates through the CTE boundary.

```sql
-- Force materialization in PostgreSQL when the CTE is referenced twice
WITH MATERIALIZED expensive_aggregation AS (
    SELECT region, AVG(amount) AS avg_amount
    FROM orders
    GROUP BY region
)
SELECT o.order_id, o.amount, ea.avg_amount
FROM orders o
JOIN expensive_aggregation ea ON o.region = ea.region
WHERE o.amount > ea.avg_amount;
```

---

## How It Connects

CTEs are frequently used alongside window functions because the window function results must be computed before they can be filtered. The CTE provides a clean boundary between the window computation layer and the filtering layer.

Recursive CTEs extend the WITH syntax with a UNION ALL structure that enables self-referencing queries, allowing SQL to traverse hierarchical data. The recursive variant shares the WITH keyword but operates on a fundamentally different execution model.

Subqueries are the alternative to CTEs and are semantically equivalent in most cases. The practical difference is readability: a query with three levels of nested subqueries is harder to follow than the same logic written as three named CTEs. For single-use, simple cases, an inline subquery is fine; for complex multi-step logic, CTEs are the idiomatic choice.

[[window-functions|Window Functions]]
[[recursive-cte|Recursive CTEs]]
[[subqueries|Subqueries]]
[[rank-and-row-number|RANK, DENSE_RANK, ROW_NUMBER]]

---

## Common Misconceptions

Misconception 1: "CTEs are faster than subqueries because the result is computed once and cached."
Reality: In PostgreSQL 12 and later, CTEs are inlined by default and treated identically to subqueries by the query optimizer. There is no caching benefit unless MATERIALIZED is explicitly specified. In earlier PostgreSQL versions, CTEs were always materialized, which sometimes helped (reuse) and sometimes hurt (optimization fences that prevented predicate pushdown). In most databases, a CTE and its equivalent subquery produce the same execution plan.

Misconception 2: "A CTE defined in a WITH block can be reused across multiple queries in the same session."
Reality: A CTE exists only for the single statement it is defined in. Once that statement finishes, the CTE is gone. For a result set that needs to persist across multiple queries, use a temporary table or a view. A materialized view is appropriate if the result needs to be precomputed and queried repeatedly without re-executing the underlying logic each time.

Misconception 3: "Using a CTE makes my query run in the order I wrote the steps."
Reality: SQL is a declarative language. The database optimizer decides the execution order based on statistics, indexes, and join costs — not the order in which CTEs are written. Writing `WITH step1 AS (...), step2 AS (...)` does not guarantee step1 executes before step2. The optimizer may reorder operations, inline CTEs, or execute parts of the query in parallel.

---

## Why It Matters in Practice

CTEs are a fundamental productivity and maintainability tool in production SQL development. Large analytical queries that would otherwise be deeply nested subquery towers become understandable step-by-step computations when written with CTEs. Code reviews for SQL are far easier when each CTE has a descriptive name that explains what it computes.

The window function wrapping pattern (CTE to compute, outer query to filter) appears constantly in production queries for ranking, deduplication, and selecting representative rows per group. Any developer writing non-trivial SQL will use this pattern repeatedly, and understanding that it requires a CTE (or subquery) rather than a direct WHERE filter on the window function is a critical baseline skill.

---

## What Breaks

**Scenario 1: Pre-PostgreSQL-12 CTE acts as an optimization fence.**
In PostgreSQL 11 and earlier, a CTE with a WHERE filter in the outer query cannot have that filter pushed into the CTE. A CTE that scans a 50-million-row table returns all 50 million rows to the outer query, which then filters. Writing the same logic as an inline subquery would allow the optimizer to push the WHERE predicate into the subquery's scan. Upgrading to PostgreSQL 12 or explicitly using NOT MATERIALIZED restores the optimizer's ability to inline the CTE.

**Scenario 2: CTE referenced multiple times causes repeated computation.**
In PostgreSQL 12+, a non-materialized CTE that is referenced twice in the same query is executed twice. If the CTE involves an expensive aggregation over millions of rows, this doubles the computation. Using WITH MATERIALIZED forces the result to be stored and reused, halving the cost.

```sql
-- This CTE is executed twice without MATERIALIZED in PostgreSQL 12+
WITH summary AS (SELECT region, SUM(amount) AS total FROM orders GROUP BY region)
SELECT * FROM summary WHERE total > 1000
UNION ALL
SELECT * FROM summary WHERE total <= 1000;

-- Force single execution
WITH MATERIALIZED summary AS (SELECT region, SUM(amount) AS total FROM orders GROUP BY region)
SELECT * FROM summary WHERE total > 1000
UNION ALL
SELECT * FROM summary WHERE total <= 1000;
```

**Scenario 3: Using a CTE where a temporary table with an index is needed.**
A CTE that produces an intermediate result of 10 million rows, which is then joined back to another large table, cannot be indexed. The join must scan the entire CTE output. A temporary table populated by INSERT ... SELECT and equipped with an index on the join column can make the subsequent join dramatically faster. CTEs are the right tool for readability; temporary tables are the right tool when the intermediate result needs an index.

---

## Interview Angle

Common question forms:
- "What is a CTE and when would you use one instead of a subquery?"
- "Are CTEs faster than subqueries?"
- "How do you filter on a window function result?"

Answer frame:
For the CTE vs subquery question: they are functionally equivalent in most modern databases, and the choice is primarily about readability. CTEs name intermediate steps, making complex queries easier to understand and maintain. For the performance question: CTEs are not inherently faster; in PostgreSQL 12+ they are inlined by default and produce the same plan as subqueries. The MATERIALIZED keyword enables explicit caching for CTEs used multiple times. For the window function filter question: window functions run after WHERE, so their results cannot be filtered in the same SELECT level — the standard solution is to compute the window function in a CTE and filter in the outer query with WHERE.

---

## Related Notes

- [[window-functions|Window Functions]]
- [[recursive-cte|Recursive CTEs]]
- [[subqueries|Subqueries]]
- [[rank-and-row-number|RANK, DENSE_RANK, ROW_NUMBER]]
- [[materialized-views|Materialized Views]]
