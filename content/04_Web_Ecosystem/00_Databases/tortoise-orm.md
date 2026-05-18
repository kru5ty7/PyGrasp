---
title: 09 - Tortoise ORM
description: "Tortoise ORM is a Django-inspired async ORM for Python that integrates with asyncio and FastAPI, offering a simpler model-definition syntax than SQLAlchemy at the cost of fewer advanced features."
tags: [tortoise-orm, async, orm, fastapi, aerich, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Tortoise ORM

> Tortoise ORM brings Django's model-definition syntax into the asyncio world — models declare fields as class attributes, queries read like Django ORM calls, and the library handles async database communication transparently.

---

## Quick Reference

**Core idea:**
- Models extend `tortoise.models.Model`; fields are declared as class attributes using `tortoise.fields.*`
- `Model.create(**kwargs)` inserts and returns an instance; `Model.filter(**kwargs).all()` queries asynchronously
- `Tortoise.init()` registers models and connections at startup; `register_tortoise()` integrates with FastAPI
- `prefetch_related('field_name')` eagerly loads related models, avoiding the async version of the N+1 problem
- Aerich is Tortoise's migration CLI (equivalent to Alembic for SQLAlchemy)

**Tricky points:**
- All query methods are coroutines — `await User.filter(active=True).all()` not `User.filter(...).all()`
- `ForeignKeyField` and `ManyToManyField` produce async-aware relation accessors — use `await user.posts.all()` not `user.posts`
- `Tortoise.init()` must be awaited before any model operations — calling model methods before initialization raises `ConfigurationError`
- Unlike Django, Tortoise does not auto-generate migrations — you must run `aerich migrate` explicitly
- `register_tortoise()` with `generate_schemas=True` is only for development — it silently runs `CREATE TABLE IF NOT EXISTS` on startup, unsuitable for production

---

## What It Is

Django developers migrating to async Python frameworks encounter an immediate friction point: Django's ORM is deeply synchronous. Every `User.objects.filter(...)` call blocks. The asyncio event loop cannot be safely interrupted for a synchronous database call without running it in a thread pool, which adds complexity and negates the performance benefits of async. Tortoise ORM was created specifically to solve this problem by providing an ORM that speaks asyncio natively while feeling familiar to Django developers.

The model definition syntax is deliberately close to Django's. Fields are class attributes: `CharField(max_length=255)`, `IntField()`, `DatetimeField(auto_now=True)`, `ForeignKeyField('models.Author', related_name='posts')`. Developers who know Django models can read Tortoise models without learning an entirely new vocabulary. This makes Tortoise a natural choice for teams transitioning from Django to a fully async stack — perhaps moving to FastAPI for a new service — where retaining the familiar model pattern reduces cognitive load.

The trade-off compared to SQLAlchemy is expressiveness. SQLAlchemy has been developed for over fifteen years, has a sophisticated Core expression layer, handles highly complex queries through its ORM, and has deep integration with dozens of tools in the Python ecosystem. Tortoise is simpler and younger. For greenfield async projects with straightforward data models, the simplicity is a feature — less to learn, fewer moving parts. For projects that need advanced query features, custom SQL dialects, or the full Alembic migration ecosystem, SQLAlchemy async is the better choice.

---

## How It Actually Works

A minimal Tortoise model looks nearly identical to its Django counterpart. The key difference is that every method that touches the database is a coroutine.

```python
from tortoise import fields
from tortoise.models import Model

class User(Model):
    id = fields.IntField(pk=True)
    username = fields.CharField(max_length=50, unique=True)
    email = fields.CharField(max_length=255)
    created_at = fields.DatetimeField(auto_now_add=True)
    posts: fields.ReverseRelation["Post"]

class Post(Model):
    id = fields.IntField(pk=True)
    title = fields.CharField(max_length=255)
    author = fields.ForeignKeyField("models.User", related_name="posts")
```

The `register_tortoise()` helper from `tortoise.contrib.fastapi` wires the ORM lifecycle into FastAPI's startup and shutdown events, so the application initializes the connection pool on startup and closes it on shutdown.

```python
from fastapi import FastAPI
from tortoise.contrib.fastapi import register_tortoise

app = FastAPI()

register_tortoise(
    app,
    db_url="postgres://user:pass@localhost/mydb",
    modules={"models": ["myapp.models"]},
    generate_schemas=False,  # False in production — use aerich migrations
    add_exception_handlers=True,
)
```

CRUD operations are direct async calls on the model class. Related objects use async accessors.

```python
# Create
user = await User.create(username="alice", email="alice@example.com")

# Query with filter
active_users = await User.filter(is_active=True).all()

# Related objects — prefetch to avoid N+1
users = await User.all().prefetch_related("posts")
for user in users:
    for post in user.posts:  # no await here — already prefetched
        print(post.title)

# Update
await User.filter(id=user.id).update(email="new@example.com")

# Delete
await User.filter(id=user.id).delete()
```

---

## How It Connects

Tortoise serves the same role as SQLAlchemy ORM in an async project — mapping Python classes to database rows. The two share the N+1 problem and solve it the same way, with different method names.

[[sqlalchemy-orm|SQLAlchemy ORM]]

asyncpg is one of the database drivers Tortoise uses under the hood for PostgreSQL — understanding the driver layer helps when debugging connection errors.

[[asyncpg|asyncpg]]

---

## Common Misconceptions

Misconception 1: "Tortoise ORM and SQLAlchemy async are interchangeable — pick either one."
Reality: The two have very different levels of maturity, ecosystem size, and feature depth. SQLAlchemy has Alembic for migrations, deep support for complex queries, and broad third-party tooling. Tortoise has Aerich and a simpler API. For complex data models or production systems requiring fine-grained migration control, SQLAlchemy async is the safer choice. Tortoise shines for smaller projects where Django-familiar syntax accelerates development.

Misconception 2: "Using `generate_schemas=True` in production is fine if the schema hasn't changed."
Reality: `generate_schemas=True` calls `CREATE TABLE IF NOT EXISTS` at every application startup. It cannot apply schema changes — only create missing tables. In production, schema changes must go through Aerich migrations so that alterations (adding a column, changing constraints) are applied deterministically and reversibly.

---

## Why It Matters in Practice

Tortoise ORM occupies a useful niche: it is the right tool when a team knows Django, is building a new async service, and wants to minimize the learning surface. Knowing it exists and understanding its trade-offs relative to SQLAlchemy async prevents spending days trying to force a Django ORM pattern into a FastAPI application or, conversely, adopting all of SQLAlchemy's complexity for a simple microservice.

---

## Interview Angle

Common question forms:
- "What async ORMs are available for Python?"
- "How does Tortoise ORM compare to SQLAlchemy for a FastAPI project?"

Answer frame:
Tortoise ORM is a Django-inspired async ORM — familiar model syntax, async-native query API, integrates with FastAPI via `register_tortoise()`. It is simpler than SQLAlchemy async and suits greenfield projects. SQLAlchemy async is more powerful, more mature, and has better migration tooling through Alembic. Tortoise uses Aerich. The N+1 problem applies to both and is solved with `prefetch_related()` in Tortoise, or `selectinload()`/`joinedload()` in SQLAlchemy.

---

## Related Notes

- [[sqlalchemy-orm|SQLAlchemy ORM]]
- [[sqlalchemy-async|SQLAlchemy Async]]
- [[asyncpg|asyncpg]]
- [[async-await|Async/Await]]
- [[fastapi|FastAPI]]
