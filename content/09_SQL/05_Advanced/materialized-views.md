---
title: 39 - Materialized Views
description: A materialized view is a view whose query results are physically stored on disk, enabling fast reads at the cost of data freshness.
tags: [sql, layer-9, views, materialized, performance]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Materialized Views

> A materialized view is a snapshot of a query's results saved to disk - it trades perfect freshness for dramatically faster reads on expensive aggregations.

---

## Quick Reference

**Core idea:**
- A materialized view stores the actual result rows, not just the query definition
- Results are stale until you explicitly refresh the view
- REFRESH MATERIALIZED VIEW reruns the query and replaces the stored data
- PostgreSQL supports REFRESH MATERIALIZED VIEW CONCURRENTLY to avoid a full table lock during refresh
- Indexes can be created on a materialized view just like on a regular table
- Primary use cases: dashboards, reporting queries, and pre-computed expensive aggregations

**Tricky points:**
- Data is stale between refreshes - the application must tolerate this
- CONCURRENTLY refresh requires a unique index on the materialized view
- Refreshing is a write-heavy operation; doing it too frequently can hurt write performance
- Dropping the underlying tables does not automatically invalidate or drop the materialized view
- Materialized views are not automatically updated by triggers or events in most databases

---

## What It Is

Imagine a newspaper's front page. The journalists go out, gather all the news, and at a fixed time each morning they print and distribute the paper. Readers get fast, instant access to the news - they do not wait for a reporter to go interview a source every time they want to read an article. But the newspaper is frozen at print time. Something that happened an hour after printing is not in that edition. A materialized view works exactly this way: the database runs the expensive query once, stores the result, and serves that stored result to every reader until someone explicitly triggers a reprint.

A regular view, by contrast, is like asking a journalist to go gather the story fresh every single time you ask. That gives you perfectly current information, but it is expensive. For data that changes rarely but is queried constantly - daily sales totals, monthly aggregates, dashboard KPI summaries - re-running the full aggregation on every page load is wasteful. The materialized view pre-computes the answer and lets the database serve it from disk at table-scan speed.

The key design decision when using a materialized view is the refresh strategy. You must decide how often to refresh and when it is acceptable for the data to be stale. A dashboard that shows yesterday's revenue can refresh once per day at midnight and serve stale-but-correct data throughout the day. A near-realtime leaderboard that updates every minute is a much harder problem and may not be suited to a materialized view at all. The right answer depends entirely on what the business can tolerate.

Materialized views also enable indexing. Because the results are stored as real rows on disk, you can create B-tree indexes, GIN indexes, or any other index type on the materialized view's columns. This is impossible with a regular view, which has no storage. The combination of pre-computed results and fast indexed lookups makes materialized views extremely powerful for read-heavy analytical workloads.

---

## How It Actually Works

When you issue CREATE MATERIALIZED VIEW monthly_revenue AS SELECT DATE_TRUNC('month', created_at) AS month, SUM(total) AS revenue FROM orders GROUP BY 1, PostgreSQL runs the SELECT immediately and stores the result rows in a dedicated physical relation - exactly like a regular table. The query definition is also stored in the catalog so it can be re-executed on demand.

At query time, SELECT * FROM monthly_revenue reads from that stored relation directly. The underlying orders table is not touched. The query is as fast as scanning a small pre-computed table, regardless of how large orders has grown. Any indexes you have created on monthly_revenue are used normally.

```sql
-- Create a materialized view for expensive aggregation
CREATE MATERIALIZED VIEW monthly_revenue AS
SELECT
    DATE_TRUNC('month', created_at) AS month,
    category,
    SUM(total_amount)               AS revenue,
    COUNT(*)                        AS order_count
FROM orders
GROUP BY 1, 2;

-- Create an index to speed up lookups by month
CREATE INDEX ON monthly_revenue (month);

-- Query is fast - reads stored rows, not raw orders
SELECT month, revenue
FROM monthly_revenue
WHERE month >= '2026-01-01'
ORDER BY month;
```

Refreshing replaces the stored data. The basic REFRESH MATERIALIZED VIEW monthly_revenue acquires an exclusive lock on the view, truncates it, re-runs the defining query, and inserts the new results. During this operation, queries against the view either block or fail depending on lock settings. For a view that takes 30 seconds to refresh, this is a 30-second outage on that view.

REFRESH MATERIALIZED VIEW CONCURRENTLY avoids the outage. It runs the query into a temporary table, computes the diff against the stored rows, and applies only inserts, updates, and deletes - leaving the existing rows readable throughout. This requires a unique index on the materialized view so the diff computation can identify which rows changed.

```sql
-- Required for CONCURRENTLY: unique index
CREATE UNIQUE INDEX ON monthly_revenue (month, category);

-- Refresh without blocking readers
REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_revenue;

-- Standard refresh (faster but locks out readers during refresh)
REFRESH MATERIALIZED VIEW monthly_revenue;
```

Scheduling refreshes is done outside PostgreSQL in most setups. Common patterns include a cron job that calls REFRESH, a PostgreSQL background worker, or a task queue job in the application (Celery, APScheduler). PostgreSQL does not have a built-in scheduler for automatic materialized view refresh.

---

## How It Connects

Materialized views solve the exact limitation that regular views leave open: expensive queries that are called frequently. Understanding when to reach for a materialized view versus a regular view comes from understanding how regular views work and why they cannot cache results.

The choice between a materialized view and an application-level cache (Redis, Memcached) is a real architectural decision. Materialized views keep the caching logic inside the database - no cache invalidation code, no serialization, queryable with full SQL including joins and filters. Application caches are faster, more flexible, and not limited to SQL's data model. The right choice depends on whether the consumer needs to filter and aggregate the cached data further.

[[views|Views]]
[[aggregate-functions|Aggregate Functions]]
[[sql-indexes|SQL Indexes]]
[[query-optimization|Query Optimization]]

---

## Common Misconceptions

Misconception 1: "A materialized view automatically updates when the underlying table changes."
Reality: In PostgreSQL, materialized views are never updated automatically. They remain frozen at the state they were last refreshed. An INSERT into the orders table does not update monthly_revenue. You must explicitly call REFRESH MATERIALIZED VIEW. Some databases (Oracle) support query rewrite or scheduled refresh, but PostgreSQL requires explicit refresh calls.

Misconception 2: "CONCURRENTLY refresh is always better than a standard refresh."
Reality: CONCURRENTLY is better for availability - it does not block readers. But it is slower and more write-intensive because it computes a row-level diff rather than truncating and reloading. For a view that takes 5 seconds to refresh and is queried infrequently, a standard refresh may be perfectly acceptable and faster overall. CONCURRENTLY also requires a unique index, which adds storage and maintenance overhead. Choose based on the actual freshness and availability requirements.

Misconception 3: "Materialized views replace the need for proper indexes on the base tables."
Reality: Materialized views are for read-heavy query patterns on aggregated or transformed data. They do not make the underlying tables faster for OLTP queries. A high-frequency lookup by user ID still needs an index on users.id. A materialized view and a base-table index solve completely different problems.

---

## Why It Matters in Practice

Analytics dashboards are the defining use case. A dashboard that shows total revenue by product category, broken down by week, requires scanning the entire orders and order_items table. On a table with tens of millions of rows, this can take seconds. Users cannot wait seconds for every page render. A materialized view that refreshes every hour brings that query from seconds to milliseconds, with the tradeoff that the dashboard shows data that is up to one hour old - a tradeoff almost every business dashboard can accept.

Materialized views also matter for multi-step analytical pipelines. Rather than running a chain of CTEs or subqueries on every request, you can materialize intermediate results. A view that pre-joins orders, customers, and products can be the base for a dozen downstream reports. This pattern reduces total database load, simplifies the downstream queries, and gives you a place to put indexes that benefit the entire pipeline.

---

## What Breaks

**Refresh contention on high-traffic views.** A materialized view is refreshed every 10 minutes via cron. The refresh takes 8 minutes to complete. At some point two refresh jobs overlap, both trying to acquire an exclusive lock. One blocks indefinitely; the cron table fills with stuck jobs; the application starts failing reads because the view is locked.

```sql
-- Use CONCURRENTLY to avoid blocking reads
-- But also ensure refresh jobs don't overlap by checking for locks first
SELECT pid, query, state FROM pg_stat_activity
WHERE query LIKE '%REFRESH MATERIALIZED VIEW%';
```

**Stale data causing incorrect business decisions.** A pricing engine reads from a materialized view of competitor prices that refreshes once per day. The refresh fails silently (the underlying data source returns an error). The pricing engine continues reading yesterday's prices. Materialized view refreshes must be monitored with alerting - a failed refresh is a silent data quality incident.

**Disk space explosion.** A materialized view pre-computes a large join with many columns for a reporting use case. The view holds 200 million rows. Nobody realized the underlying query had no LIMIT or useful filter. The materialized view takes 80 GB of disk. Unlike a regular view, there is no free lunch - stored data costs storage.

---

## Interview Angle

Common question forms:
- "What is the difference between a view and a materialized view?"
- "When would you use a materialized view instead of a regular view?"
- "How do you refresh a materialized view without blocking reads?"
- "What are the drawbacks of materialized views?"

Answer frame:
Establish the core difference first - regular view re-runs the query every time, materialized view stores the result. Then explain the tradeoff: speed vs. freshness. Give a concrete use case (dashboard, reporting). Address refresh strategies - standard vs. CONCURRENTLY - and the lock implications. Finish with the monitoring requirement: refreshes can fail silently and must be observed.

---

## Related Notes

- [[views|Views]]
- [[aggregate-functions|Aggregate Functions]]
- [[group-by|GROUP BY]]
- [[sql-indexes|SQL Indexes]]
- [[query-optimization|Query Optimization]]
