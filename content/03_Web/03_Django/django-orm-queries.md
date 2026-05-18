---
title: 07 - Django ORM Queries
description: "Django's QuerySet API provides a composable, lazy interface for filtering, annotating, aggregating, and optimizing database queries without writing raw SQL."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django ORM Queries

> The Django QuerySet API is a fluent interface where method chains build SQL queries incrementally, and understanding the difference between lazy evaluation, `select_related`, `Q` objects, and `F` expressions separates developers who fight the ORM from those who use it effectively.

---

## Quick Reference

**Core idea:**
- `filter()`, `exclude()`, `get()`, `all()` are the primary selection methods
- `values()` returns dicts; `values_list()` returns tuples; both avoid constructing model instances
- `annotate()` adds computed columns per-row; `aggregate()` computes a single value over the whole QuerySet
- `select_related()` uses SQL JOIN to prefetch ForeignKey/OneToOne in one query
- `prefetch_related()` issues a second query and joins in Python  -  for ManyToMany and reverse FK
- `Q()` objects enable `OR`, `AND`, and `NOT` in filters; `F()` objects reference database column values

**Tricky points:**
- `get()` raises `DoesNotExist` if zero results, `MultipleObjectsReturned` if more than one  -  always handle both
- `annotate()` is per-object; `aggregate()` collapses the QuerySet to a single dict  -  they are not interchangeable
- Chaining `select_related()` and `prefetch_related()` on the same QuerySet is valid and common
- `F()` expressions evaluate on the database side, making them safe for concurrent updates; a plain Python assignment is not

---

## What It Is

Django's QuerySet API is a domain-specific language embedded in Python. Just as SQL lets you express what data you want by composing clauses, Django's method chain lets you express the same intent in Python syntax that maps directly to those SQL clauses. The translation is one-to-one: `filter()` becomes `WHERE`, `exclude()` becomes `WHERE NOT`, `order_by()` becomes `ORDER BY`, `annotate()` becomes an expression in the `SELECT` list, and `aggregate()` becomes a single-row aggregate query. Because QuerySets are lazy, you can compose these methods across multiple lines or functions and the actual SQL is compiled only once when evaluation is triggered.

Field lookups are the double-underscore notation that makes `filter()` expressive without a separate query builder. `Article.objects.filter(title__icontains='django')` generates `WHERE LOWER(title) LIKE '%django%'`. `filter(created_at__gte=datetime.date(2024, 1, 1))` generates `WHERE created_at >= '2024-01-01'`. The double underscore also traverses related models: `filter(author__email__icontains='@example.com')` follows the `ForeignKey` from `Article` to `Author` and filters on the `Author.email` column  -  Django generates the JOIN automatically. This traversal can be chained across multiple relationships, and the lookup suffix (`exact`, `icontains`, `gte`, `in`, `isnull`) is always the final segment.

The `Q` and `F` objects are the escape hatches for cases that method chaining alone cannot express. `Q()` objects represent filter predicates that can be combined with `|` (OR), `&` (AND), and `~` (NOT), allowing filter logic that is impossible with plain `filter()` calls, which always AND their arguments. `F()` objects represent a reference to a column value on the database side  -  `Article.objects.update(view_count=F('view_count') + 1)` increments the counter in a single atomic SQL `UPDATE` statement without first reading the value into Python. Without `F()`, a read-then-write operation is susceptible to a race condition where two concurrent requests both read the same value and write the same incremented result, losing one increment.

---

## How It Actually Works

QuerySet evaluation triggers SQL compilation and execution. The compiled query is represented as a `django.db.models.sql.Query` object that accumulates `WHERE` clauses, `JOIN` tables, `SELECT` columns, and `ORDER BY` expressions as you chain methods. When evaluation is triggered, Django's SQL compiler for the active database backend traverses this `Query` object and produces a parameterized SQL string. Parameters are passed separately from the SQL string to the database adapter, which protects against SQL injection  -  the ORM never interpolates user-supplied values directly into the SQL string.

`select_related()` modifies the `Query` object to add `JOIN` clauses, and the SQL compiler adds the joined table's columns to the `SELECT` list. When the database returns rows, Django's model instantiation code splits the row into segments corresponding to each model and constructs both the main object and the related objects from a single row, storing the related objects on the instance's attribute cache. This means accessing `article.author` after `select_related('author')` does not hit the database  -  the `Author` instance is already attached. `prefetch_related()` works differently: it first executes the main query, collects the set of primary keys from the results, then executes a second query with `WHERE id IN (...)`, and finally uses Python to attach the prefetched objects to the correct instances in memory.

```python
from django.db.models import Q, F, Count, Avg

# OR query with Q objects
Article.objects.filter(Q(status='published') | Q(featured=True))

# NOT with Q
Article.objects.filter(~Q(author__is_banned=True))

# Annotation: add comment_count to each article
Article.objects.annotate(comment_count=Count('comments'))

# Aggregate: average views across all articles
from django.db.models import Avg
Article.objects.aggregate(avg_views=Avg('view_count'))
# -> {'avg_views': 1234.5}

# F() for safe atomic update
Article.objects.filter(pk=42).update(view_count=F('view_count') + 1)

# Solving N+1 with select_related (ForeignKey)
articles = Article.objects.select_related('author').filter(published=True)
for a in articles:
    print(a.author.name)  # no extra query

# Solving N+1 with prefetch_related (ManyToMany)
articles = Article.objects.prefetch_related('tags').filter(published=True)
```

---

## How It Connects

QuerySet queries operate on the model definitions established in the ORM foundation note  -  field types and relationships determine what lookups and traversals are valid.

[[django-orm|Django ORM]]

Views trigger QuerySet evaluation; the lazy evaluation model means that a view can receive a partially-built QuerySet from a helper or mixin and add its own filters without extra database cost.

[[django-views|Django Views]]

Understanding `select_related` and `prefetch_related` is essential context for the admin, which can silently generate N+1 queries when `list_display` references related fields.

[[django-admin|Django Admin]]

---

## Common Misconceptions

Misconception 1: "filter() returns a single object."
Reality: `filter()` always returns a QuerySet, even if only one object matches. To retrieve a single object, use `get()`, which returns the object directly but raises `DoesNotExist` if nothing matches and `MultipleObjectsReturned` if more than one matches. `filter().first()` is a common pattern when you want one object or `None` without risking an exception.

Misconception 2: "annotate() and aggregate() are the same  -  both add computed values."
Reality: `annotate()` adds a computed value to each object in the QuerySet (like adding a new column per row in SQL). `aggregate()` computes a single value over the entire QuerySet and returns a Python dictionary, consuming the QuerySet entirely. You cannot chain further `.filter()` or `.order_by()` calls after `aggregate()` because the QuerySet is gone.

Misconception 3: "F() objects are only useful for incrementing counters."
Reality: `F()` expressions are useful anywhere you need to reference the current database column value in an expression: comparing two columns on the same row (`filter(views__gt=F('likes'))`), performing arithmetic involving column values in bulk updates, or avoiding race conditions in any read-modify-write pattern. They evaluate on the database side in a single SQL statement, which is both more efficient and more correct than a Python round-trip.

---

## Why It Matters in Practice

QuerySet optimization is where most Django performance work happens. Applications that ignore `select_related` and `prefetch_related` routinely issue hundreds of queries per page in production, which becomes the primary bottleneck as data grows. The Django Debug Toolbar's SQL panel is the standard tool for visualizing query counts during development, and reducing N+1 queries with the appropriate prefetch strategy is often the single highest-impact optimization available without any schema changes.

`Q` and `F` objects matter for correctness as much as performance. Complex filter logic expressed with Python `or`/`and` keywords instead of `Q` objects does not work  -  Django filters are always ANDed together, and only `Q` objects enable OR semantics. `F` objects prevent race conditions in concurrent update scenarios that appear infrequently in development but cause data integrity issues in production under load.

---

## Interview Angle

Common question forms:
- "What is the N+1 query problem and how do you solve it in Django?"
- "What is the difference between annotate() and aggregate()?"
- "When would you use a Q object and when would you use an F object?"

Answer frame:
A strong answer describes N+1 as issuing one query for a list plus one query per object for a related attribute, and identifies `select_related()` (JOIN for ForeignKey/OneToOne) and `prefetch_related()` (separate query for ManyToMany/reverse FK) as the solutions. It distinguishes `annotate()` (per-row computation) from `aggregate()` (whole-queryset reduction). It explains `Q` as enabling OR/NOT filter logic and `F` as enabling atomic database-side arithmetic to prevent race conditions.

---

## Related Notes

- [[django-orm|Django ORM]]
- [[django-views|Django Views]]
- [[django-admin|Django Admin]]
- [[django-rest-framework|Django REST Framework]]
