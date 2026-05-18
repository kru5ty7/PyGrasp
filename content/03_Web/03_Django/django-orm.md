---
title: 06 - Django ORM
description: "Django's ORM maps Python model classes to database tables and translates Python method chains into SQL, handling schema creation through migrations."
tags: [django, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Django ORM

> Django's ORM lets you define your database schema in Python, generate it automatically, and query it with method chains that compile to SQL — without writing a single SQL statement for the vast majority of application code.

---

## Quick Reference

**Core idea:**
- Every `models.Model` subclass maps to one database table; each field maps to one column
- Field types: `CharField`, `TextField`, `IntegerField`, `DateField`, `BooleanField`, `ForeignKey`, `ManyToManyField`, `OneToOneField`
- `Meta` inner class controls `db_table`, `ordering`, `verbose_name`, `verbose_name_plural`, `indexes`
- `ForeignKey(RelatedModel, on_delete=CASCADE)` is mandatory; `on_delete` options include `CASCADE`, `PROTECT`, `SET_NULL`, `DO_NOTHING`
- QuerySets are lazy: `Article.objects.filter(published=True)` builds a SQL query but does not execute it until iterated or evaluated
- `objects` is the default Manager; custom managers let you encapsulate reusable query logic

**Tricky points:**
- `on_delete=CASCADE` deletes the child record when the parent is deleted; `PROTECT` raises an error; `SET_NULL` requires `null=True` on the field
- `null=True` and `blank=True` are different: `null` is the database column constraint; `blank` is form validation
- `ManyToManyField` creates a join table automatically; adding `through=IntermediaryModel` gives you control over extra columns on that table
- A QuerySet is not a list — iterating it twice hits the database twice unless you call `list()` or `cache` it first

---

## What It Is

An ORM — Object-Relational Mapper — is a translation layer that speaks both Python and SQL. Think of it as a professional interpreter at a United Nations conference: the Python developer speaks Python, the database speaks SQL, and the ORM translates each side's statements into terms the other side understands. The developer writes `Article.objects.filter(author=user).order_by('-created_at')` in Python; the ORM produces `SELECT * FROM blog_article WHERE author_id = 42 ORDER BY created_at DESC` in SQL; the database returns rows; the ORM converts those rows back into `Article` Python objects. The developer never has to know whether the database is PostgreSQL, MySQL, or SQLite.

Model fields are the vocabulary of this translation. `CharField(max_length=200)` maps to `VARCHAR(200)` in the schema. `IntegerField` maps to `INTEGER`. `ForeignKey` maps to a column containing the primary key of the referenced table, plus a database-level foreign key constraint. `ManyToManyField` is the only abstraction that does not correspond to a single column — it creates a separate join table that maps pairs of primary keys between the two related tables. `OneToOneField` is a `ForeignKey` with a unique constraint, used for extending a model without inheritance, most commonly seen in the `UserProfile` pattern.

The `Meta` class inside a model is where table-level metadata lives. `db_table = 'my_custom_name'` overrides the default naming convention (which would be `appname_modelname`). `ordering = ['-created_at']` sets the default sort for all QuerySet operations on that model. `indexes = [models.Index(fields=['slug'])]` adds a database index for a frequently-queried column. `unique_together` and its modern replacement `constraints = [UniqueConstraint(fields=[...])]` add composite unique constraints. None of these change the Python interface — they only affect the generated SQL and the database schema.

---

## How It Actually Works

QuerySets are lazy because building a query and executing it are two separate operations. Every time you chain a filter, exclude, annotate, or order call, Django adds clauses to an internal `Query` object without touching the database. The query executes only when the QuerySet is evaluated: iteration (`for obj in qs`), slicing (`qs[0:10]`), conversion (`list(qs)`), boolean testing (`if qs.exists()`), or direct evaluation (`qs.get(...)`). This laziness means you can build queries incrementally across multiple code paths — passing a QuerySet to a helper function that adds more filters is perfectly efficient because the SQL is compiled only once at the evaluation point.

Under the hood, Django's ORM compiles a QuerySet into an AST-like `Query` object, which the database backend's `SQLCompiler` then translates into a SQL string. The `connections` dictionary holds one database connection per configured database alias. Django opens connections on demand and closes them at the end of the request (or according to `CONN_MAX_AGE`). When using PostgreSQL, Django uses psycopg2 or psycopg3 as the database adapter; for MySQL, it uses mysqlclient. The ORM is backend-agnostic at the Python level, but each backend's compiler handles dialect differences — for example, `LIMIT/OFFSET` syntax differs between PostgreSQL and MySQL, and the ORM handles this transparently.

```python
from django.db import models

class Author(models.Model):
    name = models.CharField(max_length=200)
    email = models.EmailField(unique=True)

    class Meta:
        ordering = ['name']
        verbose_name_plural = 'authors'

class Article(models.Model):
    title = models.CharField(max_length=300)
    body = models.TextField()
    author = models.ForeignKey(Author, on_delete=models.CASCADE, related_name='articles')
    tags = models.ManyToManyField('Tag', blank=True)
    published = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [models.Index(fields=['published', 'created_at'])]
```

---

## How It Connects

The ORM schema is the source of truth for migrations — every change to a model definition generates a migration file that alters the database schema.

[[django-migrations|Django Migrations]]

QuerySet methods for filtering, annotating, and aggregating are a separate topic that builds on the model definitions here.

[[django-orm-queries|Django ORM Queries]]

The admin interface reads the ORM model definitions to auto-generate CRUD forms and list views.

[[django-admin|Django Admin]]

---

## Common Misconceptions

Misconception 1: "null=True and blank=True mean the same thing."
Reality: `null=True` tells Django to store `NULL` in the database column when no value is provided. `blank=True` tells Django's form validation layer (including the admin and `ModelForm`) to allow an empty value. A `CharField(null=True, blank=True)` allows both empty strings and `NULL` in the database, but the Django convention for text fields is `blank=True` only, using empty string for "no value." `null=True` is primarily used on non-text fields like `DateField`, `IntegerField`, and `ForeignKey`.

Misconception 2: "A QuerySet is a list of model objects."
Reality: A QuerySet is a lazy object that represents a SQL query. It behaves like a list when iterated, but it does not fetch from the database until evaluated. Calling `len()` on a QuerySet evaluates it; calling `count()` uses `SELECT COUNT(*)` and does not load objects. Iterating a QuerySet twice issues two SQL queries. Caching the QuerySet as `list(qs)` or assigning it to a variable after evaluation avoids the second query.

Misconception 3: "ForeignKey automatically means the related object is loaded with the parent."
Reality: ForeignKey creates a deferred attribute. Accessing `article.author` for the first time issues a separate `SELECT` query. If you iterate over 100 articles and access `article.author` on each, you issue 101 queries — 1 for the articles list, 100 for the authors. This is the N+1 problem, solved by `select_related('author')` which uses a SQL `JOIN`.

---

## Why It Matters in Practice

The ORM is the centerpiece of almost every Django application. Getting model design right — choosing appropriate field types, setting correct `on_delete` behaviors, adding indexes on frequently-queried columns, and keeping business logic in model methods rather than views — determines whether the application remains performant and maintainable as data grows. A poorly designed model (missing indexes on `ForeignKey` columns, incorrect `on_delete` choices, over-normalized or under-normalized relationships) tends to cause problems that are expensive to fix after the application is in production.

Understanding QuerySet laziness also has direct performance implications. Code that iterates a QuerySet once and caches the result is efficient; code that builds a QuerySet in a loop, evaluating it on each iteration, is exponentially expensive. The mental model of "a QuerySet is a recipe for a SQL query, not the query results" is the key to writing Django code that stays fast at scale.

---

## Interview Angle

Common question forms:
- "What is the difference between null=True and blank=True in a Django model?"
- "What is a lazy QuerySet and why does it matter?"
- "What is the N+1 problem and how does select_related() solve it?"

Answer frame:
A strong answer distinguishes `null` (database constraint) from `blank` (form validation), explains QuerySet laziness as deferred SQL execution that enables incremental query building, and identifies the N+1 problem as issuing one query per object in a loop, solved by `select_related()` (JOIN for ForeignKey/OneToOne) or `prefetch_related()` (separate query + Python join for ManyToMany). Bonus points for mentioning that `count()` is more efficient than `len()` for counting records.

---

## Related Notes

- [[django-migrations|Django Migrations]]
- [[django-orm-queries|Django ORM Queries]]
- [[django-admin|Django Admin]]
- [[django-project-structure|Django Project Structure]]
- [[orm-basics|ORM Basics]]
