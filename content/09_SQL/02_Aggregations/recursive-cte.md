---
title: 24 - Recursive CTEs
description: Recursive CTEs extend the WITH clause with a self-referencing UNION ALL structure that enables SQL to traverse hierarchical and graph-structured data without application-level recursion.
tags: [sql, layer-9, cte, recursion, hierarchical]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# Recursive CTEs

> A recursive CTE is SQL's mechanism for expressing iterative traversal of hierarchical data - org charts, category trees, bill-of-materials, and date series - all within a single query.

---

## Quick Reference

**Core idea:**
- A recursive CTE consists of two parts joined by UNION ALL: the anchor member (base case, non-recursive) and the recursive member (references the CTE by name, produces the next level)
- The database executes the anchor member once, then iteratively executes the recursive member using the previous iteration's output as input, until the recursive member produces no new rows
- The final result is the UNION ALL of all iterations
- A depth limit or explicit termination condition in the WHERE clause prevents infinite loops
- PostgreSQL 14+ supports a CYCLE clause for detecting and stopping on cyclic data (graphs)
- RECURSIVE is a required keyword in standard SQL even for non-recursive CTEs that just use WITH - PostgreSQL and most databases require WITH RECURSIVE for any CTE that references itself

**Tricky points:**
- UNION ALL is required between anchor and recursive member - UNION (without ALL) would require deduplication on every iteration, which is extremely expensive and rarely what you want
- The recursive member must eventually produce zero rows or the query runs forever (or until a configured recursion limit is hit)
- The columns returned by the anchor member and recursive member must match in number and compatible types
- PostgreSQL has a max_recursive_iterations setting (default 100 by default in older versions - effectively uncapped in newer versions by default); SQL Server has OPTION (MAXRECURSION n)
- Recursive CTEs in most databases execute iteration by iteration using a queue-based or stack-based algorithm - this is not the same as functional recursion in application code

---

## What It Is

Think of a family tree. Every person has a parent (except the root ancestor), and every parent can have many children. If you want to find all descendants of a given ancestor - their children, their grandchildren, their great-grandchildren, and so on - you cannot write a flat JOIN because you do not know in advance how many generations exist. You would need to write one JOIN per generation, and the tree might be three levels deep or thirty. A recursive CTE is SQL's answer to this problem: a query that starts at the root, follows the parent-child relationship one level at a time, and keeps going until there is nothing left to follow.

The structure mirrors how recursion works in programming languages. There is a base case - the starting point, the root of the tree, the first element of the sequence. Then there is the recursive step - a query that takes the output of the previous iteration and applies the relationship one more time to produce the next level. The process repeats until the recursive step produces an empty result, at which point all iterations are combined and returned as the final output.

What makes recursive CTEs powerful is that they move computation that would otherwise require multiple round-trips to the database, or application-level recursive loops, entirely into the database layer. Fetching an org chart ten levels deep would require ten separate queries if done application-side, each with its own network latency and query overhead. A recursive CTE fetches all ten levels in a single statement, letting the database engine handle the iteration with access to indexes and execution plan optimization at every level.

The depth of useful problems solvable with recursive CTEs extends beyond trees and hierarchies. Generating a sequence of dates, numbers, or other values is a classical use case. Graph traversal - finding paths between nodes, detecting connected components - is another. Anywhere a problem involves "take this result and apply this step to it, and repeat" is a candidate for a recursive CTE.

---

## How It Actually Works

The standard recursive CTE syntax separates the anchor member from the recursive member with UNION ALL. The anchor member runs once and produces the starting rows. The recursive member is applied to those rows to produce the next set, then applied again to that set, and so on until it returns no rows.

```sql
-- Org chart: find all subordinates of a given manager
WITH RECURSIVE subordinates AS (
    -- Anchor member: start with the root manager
    SELECT employee_id, manager_id, name, 1 AS depth
    FROM employees
    WHERE employee_id = 5  -- the starting manager's ID

    UNION ALL

    -- Recursive member: join employees to the previous level's results
    SELECT e.employee_id, e.manager_id, e.name, s.depth + 1
    FROM employees e
    JOIN subordinates s ON e.manager_id = s.employee_id
)
SELECT employee_id, name, depth
FROM subordinates
ORDER BY depth, name;
```

Each iteration of the recursive member sees only the rows produced by the immediately preceding iteration, not the entire accumulated result. The database maintains a working table of the current iteration's rows and replaces it with the next iteration's output until that output is empty. The final result is the union of all iterations.

A depth counter is a good practice even when no theoretical cycle exists, because unexpected data quality issues (self-referencing rows, corrupted hierarchical data) can cause the recursion to run indefinitely.

```sql
-- Depth limit as a safety guard against runaway recursion
WITH RECURSIVE category_tree AS (
    SELECT category_id, parent_id, name, 0 AS depth, ARRAY[category_id] AS path
    FROM categories
    WHERE parent_id IS NULL  -- root categories

    UNION ALL

    SELECT c.category_id, c.parent_id, c.name, ct.depth + 1, ct.path || c.category_id
    FROM categories c
    JOIN category_tree ct ON c.parent_id = ct.category_id
    WHERE ct.depth < 10     -- prevent runaway recursion
      AND NOT c.category_id = ANY(ct.path)  -- cycle detection via path array
)
SELECT * FROM category_tree ORDER BY path;
```

Generating a series of dates or numbers is one of the most practical and common uses of recursive CTEs. PostgreSQL has generate_series() for this purpose, but other databases do not, and the recursive CTE approach is portable.

```sql
-- Generate all dates between two bounds (works in any SQL database)
WITH RECURSIVE date_series AS (
    SELECT DATE '2025-01-01' AS dt    -- anchor: starting date

    UNION ALL

    SELECT dt + INTERVAL '1 day'      -- recursive: advance one day
    FROM date_series
    WHERE dt < DATE '2025-12-31'      -- termination: stop at end date
)
SELECT dt FROM date_series;
```

PostgreSQL 14 introduced the CYCLE clause, which provides built-in cycle detection without manually maintaining a path array.

```sql
-- CYCLE clause in PostgreSQL 14+
WITH RECURSIVE graph_traversal AS (
    SELECT node_id, neighbor_id, 1 AS hops
    FROM edges
    WHERE node_id = 1

    UNION ALL

    SELECT e.node_id, e.neighbor_id, g.hops + 1
    FROM edges e
    JOIN graph_traversal g ON e.node_id = g.neighbor_id
)
CYCLE neighbor_id SET is_cycle TO true DEFAULT false
USING cycle_path
SELECT * FROM graph_traversal WHERE NOT is_cycle;
```

---

## How It Connects

Recursive CTEs are an extension of the regular CTE concept - the WITH clause syntax is shared, and the anchor member is just an ordinary CTE query. Understanding what a regular CTE does and how the WITH block works is the foundation for understanding the recursive variant.

The hierarchical data problems that recursive CTEs solve are also handled in some databases through proprietary syntax (Oracle's CONNECT BY, SQL Server's hierarchyid type). The recursive CTE approach is the standard SQL portable solution.

For extremely large hierarchies where performance matters at scale, application-side implementations using the adjacency list model with recursive CTE queries are often compared against closure table or nested set designs that trade write complexity for faster reads. Data warehousing scenarios frequently store pre-computed hierarchy paths to avoid recursive queries at query time.

[[cte|Common Table Expressions (CTEs)]]
[[subqueries|Subqueries]]
[[data-warehousing|Data Warehousing]]

---

## Common Misconceptions

Misconception 1: "A recursive CTE uses the full accumulated result in each iteration, so later iterations can 'see' earlier ones."
Reality: Each iteration of the recursive member operates only on the rows produced by the immediately preceding iteration, not on the full accumulated result set. This is the "working table" model - the database swaps in the new iteration's output and discards the previous iteration's working set. The full accumulated result is only assembled at the end by UNION ALL-ing all iterations together.

Misconception 2: "UNION can be used instead of UNION ALL in a recursive CTE to avoid duplicates."
Reality: UNION deduplicates by performing a sort or hash comparison on every row. In a recursive CTE, UNION would need to deduplicate the growing accumulated result against each new iteration, which is both expensive and semantically different from what most hierarchical queries need. Standard SQL does not permit UNION (only UNION ALL) in the recursive member for this reason. Deduplication, if needed, should be done in the final outer query.

Misconception 3: "Recursive CTEs are slow and should be replaced with application-side recursion for performance."
Reality: For moderate-depth hierarchies (up to tens of levels with reasonable row counts per level), recursive CTEs are typically faster than application-side recursion because they avoid multiple round-trips to the database, can use indexes at each join step, and avoid serialization overhead. Application-side recursion may outperform a recursive CTE only when the hierarchy is extremely deep, the data structure is a dense graph, or application-level caching can short-circuit repeated traversal.

---

## Why It Matters in Practice

Hierarchical data is ubiquitous in real applications. Every organization has an employee reporting structure. Every e-commerce platform has a product category tree. Every content management system has nested folders or sections. Recursive CTEs allow these structures to be queried without schema changes (closure tables, nested sets) or application-level loops, keeping the query logic in the database where it can be optimized and indexed.

The date and number series generation pattern is equally common in analytical SQL. Generating a complete calendar for a reporting period, filling gaps in time-series data by left-joining against a complete date series, and producing test data with sequential IDs - all of these use the recursive CTE series pattern. In databases without native generate_series() or equivalent, this pattern is essential.

---

## What Breaks

**Scenario 1: Missing termination condition causes an infinite loop.**
An org chart recursive CTE lacks a depth limit. A data import error introduced a row where employee A is the manager of employee B and employee B is the manager of employee A. The recursive member keeps producing rows indefinitely. PostgreSQL will eventually terminate with an error once a recursion limit is hit; some databases will run until connection timeout. The fix is a depth limit in the WHERE clause of the recursive member, or cycle detection via a path array or the CYCLE clause.

```sql
-- Missing termination: dangerous if data has cycles
WITH RECURSIVE report_chain AS (
    SELECT employee_id, manager_id FROM employees WHERE employee_id = 1
    UNION ALL
    SELECT e.employee_id, e.manager_id FROM employees e
    JOIN report_chain r ON e.manager_id = r.employee_id
    -- No depth limit!
)
SELECT * FROM report_chain;

-- Safe version with depth guard
WITH RECURSIVE report_chain AS (
    SELECT employee_id, manager_id, 1 AS depth FROM employees WHERE employee_id = 1
    UNION ALL
    SELECT e.employee_id, e.manager_id, r.depth + 1 FROM employees e
    JOIN report_chain r ON e.manager_id = r.employee_id
    WHERE r.depth < 50   -- prevents infinite loop
)
SELECT * FROM report_chain;
```

**Scenario 2: Column count mismatch between anchor and recursive member.**
The anchor member returns 3 columns and the recursive member returns 4. The database raises an error during parsing. The columns and their types must match exactly between the two members. Adding the extra column to the anchor member (using a literal or NULL cast to the appropriate type) resolves the issue.

**Scenario 3: Large hierarchy generates enormous intermediate result sets.**
A bill-of-materials tree has 15 levels with hundreds of components at each level. The recursive CTE produces hundreds of thousands of intermediate rows per iteration. Without proper indexing on the parent_id column (the join key in the recursive member), each iteration requires a full table scan. Adding an index on the parent_id column makes each iteration's join fast and prevents the query from timing out.

```sql
-- Ensure the join column in the recursive member is indexed
CREATE INDEX idx_employees_manager_id ON employees (manager_id);
```

---

## Interview Angle

Common question forms:
- "How would you query an org chart to find all subordinates of a given employee?"
- "Explain the structure of a recursive CTE."
- "What prevents a recursive CTE from running forever?"

Answer frame:
Explain the two-part structure: the anchor member (base case, the starting point) and the recursive member (references the CTE by name, joins to produce the next level), joined by UNION ALL. Describe the execution model - anchor runs once, recursive member runs iteratively using the previous iteration's output as input, stops when no new rows are produced. For the termination question: either the WHERE clause naturally runs out of matching rows (there are no more children), or an explicit depth limit in the recursive member's WHERE clause prevents runaway iteration. Cycle detection with a path array or the CYCLE clause handles graph data where true cycles may exist.

---

## Related Notes

- [[cte|Common Table Expressions (CTEs)]]
- [[subqueries|Subqueries]]
- [[correlated-subqueries|Correlated Subqueries]]
- [[data-warehousing|Data Warehousing]]
- [[sql-interview-patterns|SQL Interview Patterns]]
