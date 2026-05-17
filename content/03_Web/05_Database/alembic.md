---
title: 04 - Alembic Migrations
description: "Alembic is a database migration tool for SQLAlchemy — it generates versioned migration scripts (`upgrade`/`downgrade`) from model changes; `alembic revision --autogenerate` diffs your models against the current schema; migrations track the schema evolution over time."
tags: [alembic, migrations, schema, upgrade, downgrade, autogenerate, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Alembic Migrations

> Alembic is a database migration tool for SQLAlchemy — it generates versioned migration scripts (`upgrade`/`downgrade`) from model changes; `alembic revision --autogenerate` diffs your models against the current schema; migrations track the schema evolution over time.

---

## Quick Reference

**Core idea:**
- `alembic init alembic` — initialize; creates `alembic/` directory + `alembic.ini`
- `alembic revision --autogenerate -m "add users table"` — generate migration from model diff
- `alembic upgrade head` — apply all pending migrations
- `alembic downgrade -1` — roll back the last migration
- `alembic current` — show current applied revision; `alembic history` — list all revisions

**Tricky points:**
- `--autogenerate` compares SQLAlchemy metadata (your models) against the live DB — it requires a live DB connection; run against a dev DB, not production directly
- Autogenerate does NOT detect: renamed tables/columns (it sees drop+create), check constraints (on some DBs), stored procedures, or custom types — review every generated migration before applying
- `alembic_version` table in the DB tracks the current revision — never manually edit this table
- Migration scripts are Python files — you can add data migrations (INSERT, UPDATE) inside `upgrade()` alongside schema changes
- Order of operations: add NOT NULL columns with defaults first, then apply `NOT NULL` constraint in a separate step — otherwise existing rows violate the constraint

---

## What It Is

When you change a SQLAlchemy model (add a column, rename a table), the Python object changes but the database schema doesn't. Alembic bridges this: it compares your models to the current database schema, generates a migration script with the necessary `ALTER TABLE` / `CREATE TABLE` statements, and applies them.

Each migration has a revision ID and references its predecessor — they form a linear chain. This ensures migrations are applied in the correct order across environments (dev, staging, prod).

---

## How It Actually Works

Setup (`alembic/env.py`):
```python
from myapp.models import Base  # import all models so metadata is populated
from myapp.database import DATABASE_URL

config.set_main_option("sqlalchemy.url", DATABASE_URL)

def run_migrations_online():
    engine = engine_from_config(config.get_section(config.config_ini_section))
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=Base.metadata)
        with context.begin_transaction():
            context.run_migrations()
```

Workflow:
```bash
# 1. Modify a SQLAlchemy model (add column, new table, etc.)

# 2. Generate migration:
alembic revision --autogenerate -m "add email_verified column to users"
# Creates: alembic/versions/20260517_abc123_add_email_verified_column_to_users.py

# 3. Review the generated script:
# upgrade(): should add the column
# downgrade(): should remove it

# 4. Apply:
alembic upgrade head
```

Generated migration script:
```python
def upgrade() -> None:
    op.add_column("users", sa.Column("email_verified", sa.Boolean(), nullable=False, server_default="false"))

def downgrade() -> None:
    op.drop_column("users", "email_verified")
```

Adding a NOT NULL column to an existing table safely:
```python
def upgrade() -> None:
    # Step 1: add as nullable
    op.add_column("users", sa.Column("display_name", sa.String(100), nullable=True))
    
    # Step 2: backfill existing rows
    op.execute("UPDATE users SET display_name = name WHERE display_name IS NULL")
    
    # Step 3: make NOT NULL
    op.alter_column("users", "display_name", nullable=False)
```

---

## How It Connects

Alembic works with SQLAlchemy models — it reads `Base.metadata` to understand the target schema.
[[sqlalchemy-core|SQLAlchemy Core]]

In CI/CD pipelines, `alembic upgrade head` is run as part of deployment to apply pending migrations before the new app version starts.
[[orm-basics|ORM Basics]]

---

## Common Misconceptions

Misconception 1: "`--autogenerate` creates perfect migration scripts."
Reality: Autogenerate catches column additions/removals and table creation/drops. It misses renamed objects (generates drop+add instead), check constraints on some databases, custom types, and index changes on some backends. Always review and test the generated script.

Misconception 2: "You can apply migrations directly on the production database."
Reality: Always test migrations on a staging environment first. Add a NOT NULL column with a server default (not just `nullable=False`) to avoid locking issues on large tables. Some migrations (adding an index on a huge table) require special handling (`CONCURRENTLY` in PostgreSQL) to avoid locking reads.

---

## Why It Matters in Practice

Migration discipline:
- Every model change = a new migration — never modify the database schema manually
- Migrations committed to version control alongside the code change
- `alembic upgrade head` in deployment scripts — automated, repeatable schema application
- `downgrade()` in every migration — ability to roll back if a deployment fails

Zero-downtime migration pattern for large tables:
```
Deployment N:   add new nullable column (no locking)
Run backfill:   UPDATE in batches (minimal locking)
Deployment N+1: enforce NOT NULL + add index CONCURRENTLY
```

---

## Interview Angle

Common question forms:
- "How do you handle database schema changes in Python?"
- "What is a migration?"

Answer frame: Alembic tracks schema evolution as versioned scripts. `alembic revision --autogenerate` diffs models vs DB → generates upgrade/downgrade script. `alembic upgrade head` applies all pending migrations. Each migration has a revision ID forming a chain. Always review autogenerated scripts — they miss renames and custom constraints. For large tables, add nullable columns first, backfill, then add NOT NULL constraint.

---

## Related Notes

- [[sqlalchemy-core|SQLAlchemy Core]]
- [[orm-basics|ORM Basics]]
- [[database-sessions|Database Sessions in FastAPI]]
