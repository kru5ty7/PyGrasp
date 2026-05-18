---
title: 03 - SQLAlchemy ORM
description: "SQLAlchemy ORM maps Python classes to database tables using a declarative model system and manages object state through a Session that implements the unit-of-work pattern."
tags: [sqlalchemy, orm, session, relationships, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# SQLAlchemy ORM

> SQLAlchemy ORM translates Python class definitions and method calls into SQL  -  the Session tracks every object you touch and flushes all changes in one coordinated transaction, making it the standard persistence layer for Python web applications.

---

## Quick Reference

**Core idea:**
- `DeclarativeBase` (SQLAlchemy 2.0) replaces the legacy `declarative_base()` factory
- `Mapped[T]` type annotation + `mapped_column()` defines columns with full IDE type inference
- `Session` is the unit-of-work container: `session.add()`, `session.commit()`, `session.refresh()`
- `relationship()` links models; `back_populates` keeps both sides synchronized
- ORM queries in 2.0 style: `session.execute(select(User).where(User.active == True))`
- `session.scalars()` returns model instances directly; `session.execute()` returns `Row` objects

**Tricky points:**
- `lazy='select'` (default) triggers a new query when you access a relationship  -  inside a loop this creates the N+1 problem
- `session.expire_on_commit=True` by default means every attribute re-fetches from DB after commit unless you call `session.refresh(obj)`
- `relationship()` requires `back_populates` on both sides to keep the in-memory graph consistent  -  `backref` is the older single-side shorthand, avoid it in new code
- `session.flush()` writes SQL without committing  -  rows exist in the transaction but are invisible to other sessions until `commit()`
- Identity map means `session.get(User, 1)` called twice returns the same Python object  -  mutation on one reference is visible on the other

---

## What It Is

Think of the SQLAlchemy ORM as a live translation layer between your Python object graph and the rows inside a relational database. When you create a `User` object and call `session.add(user)`, nothing hits the database yet. The session collects your intention. When you call `session.commit()`, the session inspects every object it has been tracking, computes a minimal set of INSERT, UPDATE, and DELETE statements, sends them in the correct dependency order, and then marks the transaction complete. The database sees one coherent burst of changes rather than a stream of individual statements.

This is the unit-of-work pattern. It is what separates an ORM from a thin wrapper around raw SQL. The ORM understands that deleting a parent row before its child rows exist violates foreign key constraints, so it handles ordering automatically. It understands that updating an object you have not actually changed is wasteful, so it tracks the original state of every attribute (the "snapshot") and only generates UPDATE statements for attributes that differ.

The identity map is the other foundational concept. Within a single session, every database row has exactly one Python representative. If you load user ID 42 and then issue another query that also returns user ID 42, you get the same Python object back. This consistency guarantee eliminates a whole class of subtle bugs where two parts of your code hold separate copies of the same row and diverge.

---

## How It Actually Works

Model definition in SQLAlchemy 2.0 uses `DeclarativeBase` as the base class and `Mapped[T]` annotations to define columns with full static type support. The `mapped_column()` call carries constraint metadata while the annotation carries the Python type, so type checkers and IDEs understand that `user.email` is a `str` and `user.id` is an `int`.

```python
from sqlalchemy import String, ForeignKey
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

class Base(DeclarativeBase):
    pass

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True)
    posts: Mapped[list["Post"]] = relationship(back_populates="author", lazy="select")

class Post(Base):
    __tablename__ = "posts"
    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(255))
    author_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    author: Mapped["User"] = relationship(back_populates="posts")
```

Querying in 2.0 style uses `select()` as a statement builder passed to the session. The session executes the statement and returns results through `scalars()` (for ORM objects) or `execute()` (for raw rows). The N+1 problem occurs when lazy-loaded relationships are accessed inside a loop  -  each attribute access triggers a new SELECT. The fix is explicit eager loading with `selectinload()` (runs a second IN query for all related objects at once) or `joinedload()` (joins the related table in the original query).

```python
from sqlalchemy import select
from sqlalchemy.orm import selectinload

# N+1 problem
users = session.scalars(select(User)).all()
for user in users:
    print(user.posts)  # each line issues a SELECT  -  N extra queries

# Fix: selectinload fetches all posts in one extra query
stmt = select(User).options(selectinload(User.posts))
users = session.scalars(stmt).all()
for user in users:
    print(user.posts)  # no additional queries
```

The `lazy` parameter on `relationship()` determines the loading strategy: `'select'` is lazy (query on access), `'joined'` is always joined, `'subquery'` uses a correlated subquery, and `'dynamic'` returns a query object (deprecated in 2.0  -  use `write_only` instead for append-only collections).

---

## How It Connects

The ORM builds on SQLAlchemy Core  -  every ORM query is ultimately compiled down to a Core SQL expression and then to a dialect-specific string. Understanding Core helps when ORM queries become too complex.

[[sqlalchemy-core|SQLAlchemy Core]]

The async variant of the ORM wraps the same Session concept but requires `AsyncSession` and `create_async_engine`, changing blocking calls to `await session.execute(...)`.

[[sqlalchemy-async|SQLAlchemy Async]]

Database sessions in FastAPI are managed as `yield` dependencies so a session is opened per request and committed or rolled back when the response completes.

[[database-sessions|Database Sessions in FastAPI]]

---

## Common Misconceptions

Misconception 1: "I can use `session.query(User)` or `select(User)` interchangeably  -  they do the same thing."
Reality: `session.query()` is the legacy 1.x API. It still works in SQLAlchemy 2.x but is considered soft-deprecated. The 2.0 style uses `select(User)` passed to `session.execute()` or `session.scalars()`. The legacy API cannot be used with the async session at all  -  `AsyncSession` only accepts `execute(select(...))`.

Misconception 2: "Setting `lazy='joined'` on all relationships improves performance."
Reality: Joined loading fetches related objects by adding a JOIN to every query  -  even when you do not need the related data. For objects with many relationships this creates wide cartesian-product queries that are slower than separate selects. `selectinload` is usually the better default eager strategy because it runs one bounded IN query rather than multiplying rows.

---

## Why It Matters in Practice

The ORM is the layer where most application bugs live  -  either from N+1 queries discovered only under production load, or from session lifecycle mismanagement (using an expired session outside a request context, or sharing a session across threads). Understanding what the session tracks, when it flushes, and how relationships load is not optional knowledge for a Python backend developer. It is the difference between an application that works in tests and one that works under real traffic.

---

## Interview Angle

Common question forms:
- "Explain the unit-of-work pattern in SQLAlchemy."
- "What is the N+1 query problem and how do you fix it?"
- "What is the difference between `session.flush()` and `session.commit()`?"

Answer frame:
The unit-of-work pattern means the session accumulates changes in memory and sends them to the database in one coordinated batch on commit  -  it resolves dependency ordering automatically. The N+1 problem occurs when a lazy-loaded relationship is accessed in a loop: one query for the parent objects plus N queries for each child collection. The fix is `selectinload()` or `joinedload()` to fetch all related data upfront. `flush()` writes SQL to the DB within the open transaction  -  other sessions cannot see the rows until `commit()`.

---

## Related Notes

- [[orm-basics|ORM Basics]]
- [[sqlalchemy-core|SQLAlchemy Core]]
- [[sqlalchemy-async|SQLAlchemy Async]]
- [[database-sessions|Database Sessions in FastAPI]]
- [[alembic|Alembic Migrations]]
