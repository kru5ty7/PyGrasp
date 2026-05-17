---
title: ORM Basics
description: "An ORM (Object-Relational Mapper) maps Python classes to database tables and instances to rows — SQL queries are expressed as Python method calls; reduces SQL boilerplate but adds abstraction overhead; SQLAlchemy is Python's dominant ORM."
tags: [orm, object-relational-mapper, sqlalchemy, models, tables, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# ORM Basics

> An ORM (Object-Relational Mapper) maps Python classes to database tables and instances to rows — SQL queries are expressed as Python method calls; reduces SQL boilerplate but adds abstraction overhead; SQLAlchemy is Python's dominant ORM.

---

## Quick Reference

**Core idea:**
- **Model class** → database table; **model instance** → database row; **class attribute** → column
- ORM translates Python expressions to SQL: `db.query(User).filter(User.age > 18)` → `SELECT * FROM users WHERE age > 18`
- **Unit of Work**: accumulate changes in memory (add, update, delete), then flush to DB in a single transaction with `session.commit()`
- **Identity Map**: within a session, loading the same row twice returns the same Python object
- SQLAlchemy is the standard Python ORM — two APIs: Core (SQL expression layer) and ORM (declarative models)

**Tricky points:**
- `session.query()` (legacy) vs `select()` (modern SQLAlchemy 2.0 style) — both work; prefer the 2.0 style for new code
- Lazy loading: accessing a relationship (`user.posts`) issues a new SQL query — this causes N+1 queries if done in a loop; use `joinedload` or `selectinload` to eager-load
- `session.flush()` sends SQL to the DB but doesn't commit the transaction — rows are visible within the same session but not to other sessions
- `session.expire_on_commit=True` (default) — after commit, all attributes become expired and are re-fetched on next access; fine for web apps (new request = new session)
- ORM models are not Pydantic models — you need to convert: `UserResponse.model_validate(db_user)` or `UserResponse.from_orm(db_user)`

---

## What It Is

Without an ORM, every database operation is raw SQL strings: error-prone, hard to refactor, and tied to a specific database. An ORM lets you define your data model in Python and express queries as Python code. The ORM generates the SQL, handles type conversions, and manages the connection lifecycle.

The trade-off: ORMs hide complexity but add abstraction. Simple queries are much cleaner with an ORM; complex queries (window functions, CTEs, multi-table joins with aggregations) often require dropping to raw SQL.

---

## How It Actually Works

SQLAlchemy 2.0 style model definition:
```python
from sqlalchemy import create_engine, String, Integer, ForeignKey
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

class Base(DeclarativeBase):
    pass

class User(Base):
    __tablename__ = "users"
    
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True)
    name: Mapped[str] = mapped_column(String(100))
    posts: Mapped[list["Post"]] = relationship(back_populates="author")

class Post(Base):
    __tablename__ = "posts"
    
    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(255))
    author_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    author: Mapped["User"] = relationship(back_populates="posts")
```

CRUD operations:
```python
from sqlalchemy.orm import Session
from sqlalchemy import select

# Create
user = User(email="alice@example.com", name="Alice")
session.add(user)
session.commit()
session.refresh(user)  # loads generated id

# Read
stmt = select(User).where(User.email == "alice@example.com")
user = session.scalars(stmt).first()

# Update
user.name = "Alice Smith"
session.commit()

# Delete
session.delete(user)
session.commit()
```

N+1 problem and solution:
```python
# BAD: N+1 queries (1 for users, N for each user's posts)
users = session.scalars(select(User)).all()
for user in users:
    print(user.posts)  # each access = new SQL query

# GOOD: eager load with selectinload
from sqlalchemy.orm import selectinload
stmt = select(User).options(selectinload(User.posts))
users = session.scalars(stmt).all()
for user in users:
    print(user.posts)  # no additional queries
```

---

## How It Connects

SQLAlchemy Core and ORM are the two layers of Python's most complete database toolkit — ORM builds on Core.
[[sqlalchemy-core|SQLAlchemy Core]]

In FastAPI, the ORM session is a per-request resource managed by a `yield` dependency.
[[database-sessions|Database Sessions in FastAPI]]

---

## Common Misconceptions

Misconception 1: "ORM queries are always slower than raw SQL."
Reality: For simple queries, ORM overhead is negligible. For complex queries, poorly written ORM code (N+1, unnecessary joins) can be slower than hand-written SQL. Well-written ORM code is comparable — and the ORM's automatic parameterization prevents SQL injection.

Misconception 2: "An ORM model and a Pydantic model are the same."
Reality: SQLAlchemy ORM models are Python classes that map to database tables — they use SQLAlchemy's descriptor system for attribute access and lazy loading. Pydantic models are pure data validation/serialization containers. They have different bases, different behaviors, and must be explicitly converted between them.

---

## Why It Matters in Practice

ORMs are standard for web backends because:
- Automatic SQL injection prevention (parameterized queries by default)
- Schema migrations can be expressed as Python model changes (Alembic)
- Database-agnostic code (switch from SQLite to PostgreSQL by changing the connection URL)
- Type safety with modern `Mapped[]` annotations (IDEs understand the types)

---

## Interview Angle

Common question forms:
- "What is an ORM?"
- "What is the N+1 query problem?"

Answer frame: ORM maps Python classes to DB tables — model instance = row, query methods = SQL. **N+1 problem**: loading a list of users then accessing `.posts` on each runs 1+N queries; fix with `selectinload`/`joinedload` (eager loading). Trade-off: ORMs simplify simple queries and prevent SQL injection; complex queries sometimes need raw SQL. SQLAlchemy = dominant Python ORM; 2.0 style uses `Mapped[]` type annotations.

---

## Related Notes

- [[sqlalchemy-core|SQLAlchemy Core]]
- [[sqlalchemy-async|SQLAlchemy Async]]
- [[database-sessions|Database Sessions in FastAPI]]
- [[alembic|Alembic Migrations]]
