---
title: N+1 Problem
description: The N+1 problem occurs when code fetches N rows and then issues one additional database query per row, producing N+1 round-trips instead of one — a pattern that is invisible in development and catastrophic at production scale.
tags: [sql, layer-9, performance, orm, queries]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# N+1 Problem

> The N+1 problem is a performance antipattern where application code trades one efficient query for N+1 inefficient ones — it emerges naturally from ORM lazy loading and is undetectable without query logging, making it one of the most common causes of production database overload.

---

## Quick Reference

**Core idea:**
- The pattern: fetch N rows (query 1), then fetch a related record for each row (queries 2 through N+1)
- Result: 101 queries to display 100 orders with their customers, instead of 1 JOIN
- ORMs cause this by default through lazy loading — related objects are fetched on access, not on initial query
- Each query incurs a full round-trip: network latency + query parsing + execution + result transfer
- At N=1000, this is 1001 queries; at N=10000, it is 10001 queries — latency compounds multiplicatively

**Tricky points:**
- The N+1 pattern is invisible during development (small N means acceptable total time) and appears only in production (large N reveals the true cost)
- Lazy loading in ORMs is the default — it requires an explicit opt-in (eager loading) to avoid
- Detecting N+1 requires query logging or a profiling tool — reading the application code alone does not reveal it
- Batch loading (IN query) is the correct fix when JOIN would produce duplicated rows (many-to-many)
- "Eager loading" and "preloading" are ORM terminology for the solution, but the underlying SQL is either a JOIN or an IN query

---

## What It Is

Imagine you are a librarian who needs to compile a list of 100 books and the name of each book's author. A sensible approach is to pull the list of books and the author information in one pass — the library catalogue can give you both in a single lookup. An N+1 approach would be: first get the list of 100 books, then for each book, walk to the author filing cabinet and look up that author individually. You have made 101 trips instead of 1. Each trip to the filing cabinet takes a fixed amount of time regardless of how quick the actual lookup is — and that fixed cost multiplied by 100 is where the performance disappears.

Database round-trips work the same way. Even a query that executes in under a millisecond incurs overhead: the TCP network round-trip (even on localhost), the query parsing step, the planner check, and the result serialization. When an application issues 1,000 queries of 1 ms each, the cumulative overhead often adds 200–500 ms of pure round-trip cost on top of the query execution time — turning what should be a 10 ms response into a 500 ms response.

ORM frameworks enable N+1 almost by default through a feature called lazy loading. When you fetch a list of `Order` objects, the ORM does not automatically fetch each order's associated `Customer` object. Instead, it waits until the code actually accesses `order.customer` — then issues a query at that moment. This feels natural and works correctly. The problem is that in a loop over 100 orders, each `order.customer` access triggers a separate query. The ORM has been designed to be convenient, and that convenience produces silent N+1 problems.

---

## How It Actually Works

The N+1 pattern in its simplest form is a fetch-then-loop structure. The application fetches a list, then inside a loop, accesses a related object that triggers additional queries.

```python
# Python / SQLAlchemy ORM — lazy loading (default)
orders = session.query(Order).filter(Order.status == 'shipped').all()
# SQL: SELECT * FROM orders WHERE status = 'shipped'
# Returns 100 Order objects

for order in orders:
    print(order.customer.name)
    # SQL: SELECT * FROM customers WHERE id = <order.customer_id>
    # This fires ONCE PER ORDER — 100 additional queries

# Total: 101 queries
```

The equivalent raw SQL pattern demonstrates the problem clearly:

```sql
-- Query 1: fetch the orders
SELECT id, customer_id, total FROM orders WHERE status = 'shipped';
-- Returns 100 rows

-- Queries 2–101 (one per row, issued by application code):
SELECT id, name FROM customers WHERE id = 1;
SELECT id, name FROM customers WHERE id = 2;
SELECT id, name FROM customers WHERE id = 7;
-- ... 97 more identical queries with different customer_id values
```

The correct solution is to load both the orders and their customers in a single operation. There are two approaches: a JOIN query and a batch IN query.

The JOIN approach fetches everything in one round-trip. It is correct when the relationship is many-to-one (each order has one customer) and there is no risk of row duplication.

```sql
-- One query replaces 101
SELECT o.id, o.total, c.name AS customer_name
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.status = 'shipped';
```

```python
# SQLAlchemy eager loading via joined load
from sqlalchemy.orm import joinedload

orders = (
    session.query(Order)
    .options(joinedload(Order.customer))
    .filter(Order.status == 'shipped')
    .all()
)
# SQL: SELECT orders.*, customers.* FROM orders
#      JOIN customers ON orders.customer_id = customers.id
#      WHERE orders.status = 'shipped'
# Total: 1 query
```

The batch IN approach is correct for one-to-many or many-to-many relationships where a JOIN would produce duplicate rows. The ORM fetches the parent objects first, collects their IDs, then issues one IN query to fetch all related objects.

```sql
-- Fetch orders (query 1)
SELECT id, customer_id, total FROM orders WHERE status = 'shipped';
-- Returns IDs: [1, 2, 3, ..., 100]

-- Fetch all customers in one query (query 2)
SELECT id, name FROM customers WHERE id IN (1, 2, 3, ..., 100);

-- Total: 2 queries regardless of N
```

```python
# Django ORM — select_related (JOIN) vs prefetch_related (IN query)

# select_related: SQL JOIN — for ForeignKey / OneToOne
orders = Order.objects.filter(status='shipped').select_related('customer')

# prefetch_related: SQL IN query — for ManyToMany or reverse ForeignKey
orders = Order.objects.filter(status='shipped').prefetch_related('items')
```

Detection is as important as the fix. N+1 problems are invisible in code review because the queries are generated by the ORM at runtime. The reliable detection methods are:

```python
# SQLAlchemy: enable echo to log all queries to stdout
engine = create_engine("postgresql://...", echo=True)

# Django: Django Debug Toolbar — shows query count and SQL in the browser
# Production detection: check the slow query log for bursts of identical queries
# at slightly different WHERE clause values

# PostgreSQL: pg_stat_statements to identify repeated identical queries
SELECT query, calls, total_exec_time, mean_exec_time
FROM pg_stat_statements
WHERE query LIKE '%SELECT%customers%WHERE id%'
ORDER BY calls DESC;
```

---

## How It Connects

The N+1 problem is a structural form of the correlated subquery antipattern: for each row in a result, the application performs additional database work. Understanding correlated subqueries at the SQL level illuminates why the ORM lazy loading pattern is expensive.

[[correlated-subqueries|Correlated Subqueries]]

Query optimization covers the general principle of minimizing round-trips and ensuring the database does the joining and filtering rather than the application. The N+1 fix (eager loading) is a specific application of the general principle: push set-based work into the database.

[[query-optimization|Query Optimization]]

---

## Common Misconceptions

Misconception 1: "N+1 only happens with ORMs."
Reality: N+1 is a pattern that can occur in any application code that issues queries inside loops — including raw SQL via application-level iteration. An application that fetches IDs from one table and then issues individual queries for each ID in a loop has the N+1 problem regardless of whether an ORM is involved. ORMs make it easier to fall into the pattern through lazy loading, but the pattern is architectural, not ORM-specific.

Misconception 2: "The fix is always to use a JOIN."
Reality: JOINs can produce row duplication in one-to-many and many-to-many relationships. Fetching 100 orders, each with 5 line items, via a JOIN returns 500 rows — the application must de-duplicate them. The batch IN query (fetch orders, then IN query for items) returns 100 + however many items there are, with no duplication. The right fix depends on the cardinality of the relationship.

Misconception 3: "Eager loading is always better than lazy loading."
Reality: Eager loading fetches related objects whether or not they are used. If only 20% of requests actually access the related data, eager loading causes unnecessary joins and data transfer for the 80% that do not. Lazy loading is the correct default when related data is accessed infrequently; eager loading is the correct choice when related data is reliably needed. The N+1 fix is context-dependent — it requires knowing the access pattern.

---

## Why It Matters in Practice

The N+1 problem is disproportionately impactful because it scales with the number of rows returned. A page that displays 20 items is fast in development. The same page displaying 500 items in production issues 501 queries. A database that handles 500 queries per second comfortably may saturate when a single slow page view consumes 500 of those slots. The connection pool exhausts, queued requests time out, and the application appears to go down — all because of a missing `joinedload` call.

The operational signature of an N+1 problem is distinctive and once recognized is easy to confirm: a burst of nearly identical queries with slightly different parameter values, all arriving within a narrow time window, all from the same application endpoint. Query logging and pg_stat_statements make this pattern visible. The fix — adding eager loading or rewriting to a JOIN — typically takes minutes once the problem is correctly identified. The challenge is identifying it without the right tooling.

---

## What Breaks

**Product listing page saturates the database under load.** A product listing API returns 200 products per page. The endpoint fetches products, then in the serializer, accesses `product.category.name` for each product — triggering 200 category queries. Under load with 50 concurrent requests, the page issues 10,000 category queries per second. The category table is small (100 rows) and each query is fast, but the connection pool (max 20 connections) is saturated by query volume alone.

```python
# Broken pattern
products = Product.objects.filter(active=True)[:200]
# Each product.category.name triggers SELECT * FROM categories WHERE id = X

# Fix
products = Product.objects.filter(active=True).select_related('category')[:200]
# One JOIN query replaces 201 queries
```

**Admin report runs correctly but takes 45 seconds.** A one-off admin script processes each user and fetches their most recent order. The script works for the developer (100 users in the dev database) but times out in production (50,000 users). The fix is to rewrite the inner query as a single subquery JOIN.

```sql
-- N+1 in application code (pseudocode)
users = SELECT id FROM users;  -- 50,000 rows
for user in users:
    last_order = SELECT * FROM orders WHERE user_id = user.id ORDER BY created_at DESC LIMIT 1;
-- 50,001 queries total

-- Single query using DISTINCT ON (PostgreSQL)
SELECT DISTINCT ON (user_id) user_id, order_id, created_at, total
FROM orders
ORDER BY user_id, created_at DESC;
-- 1 query — returns each user's most recent order
```

**N+1 hidden inside a template.** A Django template iterates over a queryset and accesses a related field that was not prefetched. The view developer and template developer are different people; neither sees the full picture. The query count is only visible in Django Debug Toolbar.

```python
# View (no prefetch)
context['events'] = Event.objects.filter(date=today)

# Template
{% for event in events %}
    {{ event.venue.name }}  {# triggers SELECT * FROM venues WHERE id = X per event #}
{% endfor %}

# Fix in view
context['events'] = Event.objects.filter(date=today).select_related('venue')
```

---

## Interview Angle

Common question forms:
- "What is the N+1 problem?"
- "How does lazy loading cause N+1 issues in ORMs?"
- "How would you detect and fix an N+1 problem in a Django or SQLAlchemy application?"

Answer frame:
Define the pattern concretely: one query fetches N rows, then N additional queries fetch related data — totaling N+1 round-trips. Explain why ORMs cause it: lazy loading defers the related-object query until the attribute is accessed, and when that access happens inside a loop, it fires once per iteration. Give the raw SQL picture (101 identical SELECT statements with different WHERE values). Describe the two fixes: JOIN via `joinedload`/`select_related` for to-one relationships, and batch IN via `subqueryload`/`prefetch_related` for to-many. Describe detection: `echo=True` in SQLAlchemy, Django Debug Toolbar, query logging, or `pg_stat_statements` for the burst pattern in production.

---

## Related Notes

- [[query-optimization|Query Optimization]]
- [[correlated-subqueries|Correlated Subqueries]]
- [[joins-overview|Joins Overview]]
- [[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]
- [[sqlalchemy-orm|SQLAlchemy ORM]]
