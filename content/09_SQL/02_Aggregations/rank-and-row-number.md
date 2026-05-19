---
title: 22 - RANK, DENSE_RANK, ROW_NUMBER
description: Three window functions that assign ordinal positions to rows within a partition, each with distinct tie-handling behavior that determines which one is appropriate for a given ranking problem.
tags: [sql, layer-9, window-functions, ranking]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# RANK, DENSE_RANK, ROW_NUMBER

> ROW_NUMBER, RANK, and DENSE_RANK all assign position numbers to rows within a partition, but they differ in what happens when rows tie - and that difference determines which one solves the classic "top N per group" interview problem correctly.

---

## Quick Reference

**Core idea:**
- ROW_NUMBER assigns a unique sequential integer to every row within the partition, starting at 1 - ties are broken arbitrarily (or deterministically if ORDER BY is fully unique)
- RANK assigns the same number to tied rows, then skips ranks to account for the tie (1, 1, 3, 4)
- DENSE_RANK assigns the same number to tied rows but does not skip the next rank (1, 1, 2, 3)
- All three require an ORDER BY inside OVER() to define what "rank" means
- PARTITION BY is optional but common - it resets the rank counter at the start of each partition
- The "top N per group" query pattern uses ROW_NUMBER with PARTITION BY and wraps the result in a CTE or subquery to filter rn <= N

**Tricky points:**
- ROW_NUMBER produces non-deterministic tie-breaking unless the ORDER BY column is unique - two rows with the same ORDER BY value can receive either number
- RANK and DENSE_RANK are deterministic for tied rows (tied rows always get the same rank) but differ in whether they leave gaps
- Using ROW_NUMBER without PARTITION BY assigns a rank over the entire result set, not per group
- The filter on the row number (WHERE rn = 1) cannot appear in the same query as the window function - it must be in an outer query
- NTILE(n) is a related function that divides rows into buckets, not individual ranks

---

## What It Is

Imagine a race with three runners who cross the finish line at exactly the same time. How do you assign their positions? One approach: arbitrarily assign them positions 1, 2, and 3 (ROW_NUMBER). Another: give them all position 1 and then call the next runner position 4, acknowledging that positions 2 and 3 are occupied (RANK). A third: give them all position 1 and then call the next runner position 2, treating the tie as occupying a single position slot (DENSE_RANK). All three approaches are valid - the right choice depends on what the ranking is being used for.

ROW_NUMBER is appropriate when you need a guaranteed unique identifier per row within a partition, regardless of ties. It is the standard choice for the "top N per group" query pattern precisely because it guarantees that exactly N rows will be returned per group - no more, no less. RANK is appropriate when you want rankings that reflect a meaningful gap (there is no second best because two people tied for first). DENSE_RANK is appropriate when you want compact rankings without gaps, often used for reporting where "rank 3" should mean "the third distinct performance level" regardless of how many people tied at levels 1 and 2.

All three functions share the same syntax structure - they are window functions that take no arguments but require an ORDER BY inside their OVER() clause. The PARTITION BY sub-clause resets the counter at the start of each new partition, which is what makes per-group ranking possible. Without PARTITION BY, the ranking continues across all rows in the result set as if there were one giant partition.

---

## How It Actually Works

The three functions differ only in their tie-handling logic. Given the same OVER() clause, ROW_NUMBER increments for every row regardless of value, RANK increments only when the ORDER BY value changes (and jumps to the correct position), and DENSE_RANK increments only when the ORDER BY value changes (but never jumps).

```sql
-- Side-by-side comparison with tied scores
SELECT
    student_name,
    score,
    ROW_NUMBER()  OVER (ORDER BY score DESC) AS row_num,
    RANK()        OVER (ORDER BY score DESC) AS rank,
    DENSE_RANK()  OVER (ORDER BY score DESC) AS dense_rank
FROM exam_results;

/*
student_name | score | row_num | rank | dense_rank
-------------|-------|---------|------|------------
Alice        |  95   |    1    |   1  |     1
Bob          |  95   |    2    |   1  |     1
Carol        |  88   |    3    |   3  |     2
Dave         |  88   |    4    |   3  |     2
Eve          |  75   |    5    |   5  |     3
*/
```

The canonical "top N per group" query uses ROW_NUMBER with PARTITION BY to assign per-group row numbers and then filters in an outer query. The filter cannot appear in the same level as the window function because window functions are evaluated after WHERE.

```sql
-- Top 3 orders per customer by amount (most expensive first)
WITH ranked_orders AS (
    SELECT
        order_id,
        customer_id,
        amount,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY amount DESC
        ) AS rn
    FROM orders
)
SELECT order_id, customer_id, amount
FROM ranked_orders
WHERE rn <= 3;
```

RANK is the right choice when you want to surface all tied rows at the same rank position. A leaderboard where tied players share a position naturally uses RANK. If you used ROW_NUMBER instead, one of the tied players would be arbitrarily assigned a higher position than the other, which is misleading for display purposes.

```sql
-- Leaderboard that correctly shows ties
WITH player_scores AS (
    SELECT
        player_id,
        SUM(points) AS total_points
    FROM game_results
    GROUP BY player_id
),
ranked_players AS (
    SELECT
        player_id,
        total_points,
        RANK() OVER (ORDER BY total_points DESC) AS position,
        DENSE_RANK() OVER (ORDER BY total_points DESC) AS dense_position
    FROM player_scores
)
SELECT * FROM ranked_players ORDER BY position;
```

DENSE_RANK is useful when the numeric rank has meaning for downstream consumers. If a business rule says "rank 1 gets a 10% bonus, rank 2 gets 5%, rank 3 gets 2%", then using RANK (which skips numbers after ties) would cause rank 3 to never exist if two people tied for position 1. DENSE_RANK ensures every rank level from 1 to N is represented.

---

## How It Connects

All three functions are window functions and require the same OVER() clause mechanics - PARTITION BY and ORDER BY. Understanding how the window is defined, what PARTITION BY does, and why window function results cannot be filtered in the same SELECT level is prerequisite knowledge from the window functions note.

The "top N per group" pattern, which is one of the most common SQL interview questions, is the primary practical application of ROW_NUMBER. It almost always appears in combination with a CTE that isolates the window function computation from the outer filtering query.

[[window-functions|Window Functions]]
[[cte|Common Table Expressions (CTEs)]]
[[group-by|GROUP BY]]

---

## Common Misconceptions

Misconception 1: "ROW_NUMBER is always correct for ranking because it gives unique, clean numbers."
Reality: ROW_NUMBER assigns unique numbers regardless of ties, which means tied rows receive different numbers based on arbitrary internal ordering. This is correct for the "top N per group" use case where you need exactly N rows. It is wrong for a leaderboard or any display context where tied items should share a rank - in those cases, RANK or DENSE_RANK is appropriate.

Misconception 2: "RANK and DENSE_RANK are the same - they both handle ties."
Reality: Both assign the same rank number to tied rows, but they differ in what comes after a tie. RANK skips the ranks that would have been occupied by the tied rows (after two people tie for rank 1, the next person is rank 3). DENSE_RANK does not skip (the next person is rank 2). RANK mirrors how sports standings and competition results are typically expressed. DENSE_RANK is better for categorical rank labels where gaps are confusing.

Misconception 3: "I can write WHERE rn = 1 in the same SELECT that defines the window function."
Reality: The window function is evaluated after WHERE in the logical execution order, so the rn column does not exist when WHERE is evaluated. The database will either raise an error or fail to find the column. The correct pattern is to compute the window function in a CTE or subquery and apply the WHERE filter at the outer level.

---

## Why It Matters in Practice

These three functions are the most commonly tested SQL window functions in technical interviews, and the "top N per group" query is arguably the single most common SQL interview question across the industry. Any backend developer working with relational databases will encounter the need to find the most recent record per user, the highest-value order per customer, or the top performers per team - all of which are instances of this one pattern.

In production systems, the choice between RANK, DENSE_RANK, and ROW_NUMBER directly affects the correctness of reports and dashboards. A customer loyalty tier system that uses RANK might produce fewer tier assignments than expected because of skipped ranks. An analytics report using ROW_NUMBER for display purposes might unfairly rank one of two equally performing products below the other.

---

## What Breaks

**Scenario 1: ROW_NUMBER produces inconsistent results on ties.**
A "show the latest login per user" query uses ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_at DESC). Two logins have identical login_at timestamps. Each time the query runs, either login might receive row_number = 1, producing a non-deterministic result. Adding a tiebreaker column (ORDER BY login_at DESC, login_id DESC) makes the ordering fully deterministic.

```sql
-- Non-deterministic with tied timestamps
ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_at DESC)

-- Deterministic: tiebreaker ensures unique ordering
ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_at DESC, login_id DESC)
```

**Scenario 2: RANK produces unexpected row counts in "top N" queries.**
A query selects `WHERE rank <= 3` to get the top 3 products per category. Two products tie for rank 1, so both receive rank 1. Rank 2 is skipped. Rank 3 exists and returns one product. The result has 3 rows for that category instead of the expected 3, but had three products tied for rank 3 the result would have 5 rows. Using ROW_NUMBER produces exactly 3 rows every time, while RANK can return more.

**Scenario 3: Missing PARTITION BY ranks across the entire table.**
A developer intends to rank customers per region and writes `ROW_NUMBER() OVER (ORDER BY total_spent DESC)` without PARTITION BY. The function assigns a single global rank across all customers from all regions. The "per region" ranking requires `ROW_NUMBER() OVER (PARTITION BY region ORDER BY total_spent DESC)`.

---

## Interview Angle

Common question forms:
- "What is the difference between RANK, DENSE_RANK, and ROW_NUMBER?"
- "Write a query to get the top 3 orders per customer."
- "Which ranking function would you use to build a leaderboard that shows tied positions correctly?"

Answer frame:
Start by explaining the tie-handling difference concisely: ROW_NUMBER always unique (breaks ties arbitrarily), RANK same number for ties but skips the next rank, DENSE_RANK same number for ties and does not skip. For the "top 3 per customer" question, write the CTE pattern: ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) in the inner query, then WHERE rn <= 3 in the outer query. For the leaderboard question, explain that ROW_NUMBER would arbitrarily separate tied players, RANK would correctly give them the same position but skip the next number, and DENSE_RANK would give them the same position with compact numbering - the right choice depends on whether gaps in the rank sequence matter to the display.

---

## Related Notes

- [[window-functions|Window Functions]]
- [[cte|Common Table Expressions (CTEs)]]
- [[group-by|GROUP BY]]
- [[aggregate-functions|Aggregate Functions]]
- [[sql-interview-patterns|SQL Interview Patterns]]
