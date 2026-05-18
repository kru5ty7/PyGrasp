---
title: DDL — CREATE, ALTER, DROP
description: DDL statements define the structure of a database rather than its data, and running them incorrectly in production can destroy schema history or lock tables for minutes.
tags: [sql, layer-9, ddl, schema]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# DDL — CREATE, ALTER, DROP

> DDL is how you build and reshape the containers that hold data — and unlike DML, most DDL changes are immediate, structural, and difficult to reverse without a migration strategy.

---

## Quick Reference

**Core idea:**
- DDL stands for Data Definition Language. DDL statements change the structure (schema) of the database, not the data inside it.
- The three main DDL statements are CREATE (define new objects), ALTER (modify existing objects), and DROP (delete objects permanently).
- DDL applies to tables, indexes, views, sequences, schemas (namespaces), and other database objects.
- In PostgreSQL, DDL runs inside a transaction by default, which means CREATE TABLE and ALTER TABLE can be rolled back.
- Schema migrations are versioned DDL scripts that evolve the database structure over time without destroying data.

**Tricky points:**
- DROP TABLE deletes the table and all its data permanently. In PostgreSQL, `DROP TABLE IF EXISTS` prevents an error if the table does not exist, but it does not protect data.
- ALTER TABLE operations that rewrite rows (such as adding a column without a default in older PostgreSQL, or changing a column type) can lock the table and block reads and writes for minutes on large tables.
- In PostgreSQL, DDL is transactional — you can roll back a CREATE TABLE. In MySQL, DDL implicitly commits any open transaction before running.
- Column renaming via ALTER TABLE can silently break views, functions, and application code that reference the old column name.
- `TRUNCATE` is often grouped with DDL. It removes all rows like DELETE but uses a faster path and resets sequences. It is not filtered (no WHERE clause).

---

## What It Is

Think of DDL as the architecture work that happens before a building is occupied. Architects draw blueprints, builders construct walls, electricians run wiring. None of this involves the people who will eventually live or work in the building. DDL is that same preparatory work in a database. You define the tables (rooms), columns (what goes in each room), types (what kind of objects are allowed), and constraints (rules about what is permitted). Only after this structure exists can you put data in.

DDL stands for Data Definition Language. It is one of two broad categories of SQL statements — the other being DML (Data Manipulation Language), which works with the data itself. DDL defines the containers; DML fills them. The three DDL statements you will use constantly are CREATE, ALTER, and DROP. CREATE TABLE builds a new table. ALTER TABLE modifies an existing table — adding columns, removing columns, renaming columns, or changing column types. DROP TABLE removes the table entirely, along with every row it contains.

DDL also applies beyond tables. CREATE INDEX builds an index on a table. CREATE VIEW defines a stored query. CREATE SEQUENCE defines an auto-incrementing number generator. CREATE SCHEMA creates a namespace that holds a group of tables. DROP and ALTER work on all of these objects as well. The principle is the same across all of them: you are changing the structure of the database, not the data.

A schema migration is a versioned, ordered set of DDL statements that describes how the database structure should change over time. Rather than running DDL manually against production, teams write migration files (numbered scripts or timestamped files) that a migration tool (such as Alembic for Python) applies in order. This approach gives you a history of every structural change, the ability to apply the same changes to every environment, and a path to roll back if something goes wrong.

---

## How It Actually Works

When PostgreSQL parses a CREATE TABLE statement, it writes a row into the system catalog — specifically into `pg_class` (which records tables, indexes, and views) and `pg_attribute` (which records columns). The table does not yet have any data pages on disk. The first row inserted allocates the first page. This is why creating a table is fast even if you declare dozens of columns.

ALTER TABLE is more complex. Adding a new column with a NOT NULL constraint and no default requires rewriting every row in the table, because each row must now include a value for the new column. On a table with millions of rows, this can take minutes and holds an exclusive lock that blocks all reads and writes. PostgreSQL 11 added the ability to add a column with a non-volatile default value without rewriting rows — the default is stored in the catalog and applied at read time. For older PostgreSQL versions, the standard pattern is to add the column as nullable first, backfill the values in batches, then add the NOT NULL constraint.

DROP TABLE with the `CASCADE` option drops not only the table but also all objects that depend on it — foreign keys from other tables, views that reference it, and so on. Without CASCADE, PostgreSQL refuses to drop a table that is still referenced by other objects.

```sql
-- Create a table with columns, types, and constraints
CREATE TABLE products (
    id          BIGSERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
    sku         TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add a column (safe in PostgreSQL 11+: adds column without rewrite)
ALTER TABLE products
    ADD COLUMN description TEXT;

-- Add a column that is NOT NULL — requires a default to avoid rewrite
ALTER TABLE products
    ADD COLUMN active BOOLEAN NOT NULL DEFAULT true;

-- Rename a column
ALTER TABLE products
    RENAME COLUMN sku TO product_code;

-- Drop a column (data is gone immediately)
ALTER TABLE products
    DROP COLUMN description;

-- Drop the table entirely
DROP TABLE products;

-- Drop only if it exists (no error if absent)
DROP TABLE IF EXISTS products;
```

---

## How It Connects

DDL defines the schema, but DML is what puts data into that schema. Understanding how INSERT, UPDATE, and DELETE interact with the structure DDL creates is the next step.

[[dml|DML — INSERT, UPDATE, DELETE]]

Every column defined in CREATE TABLE needs a data type. Choosing types incorrectly at schema creation time is hard to fix later without a migration, because changing a column type can require rewriting all existing data.

[[data-types|SQL Data Types]]

Constraints are the part of DDL that enforce data integrity rules. PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, and CHECK are all declared inside CREATE TABLE or added via ALTER TABLE.

[[constraints|Constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK)]]

Alembic is the standard Python tool for managing DDL as versioned migrations. Understanding DDL directly makes Alembic migrations readable and debuggable.

[[alembic|Alembic]]

---

## Common Misconceptions

Misconception 1: "DDL changes are always fast because they just change metadata."
Reality: Some DDL changes are metadata-only (adding a nullable column in modern PostgreSQL, renaming a table). Others require rewriting every row in the table (changing a column's type, adding a NOT NULL column without a default on older PostgreSQL). On a table with tens of millions of rows, a rewriting ALTER TABLE can take ten or twenty minutes and blocks all traffic to that table during that time.

Misconception 2: "You can always roll back DDL with a DROP."
Reality: DROP TABLE removes all data permanently. If you DROP a table and there is no backup, the data is gone. In PostgreSQL, DDL runs inside a transaction, so you can roll back a CREATE TABLE if you have not yet committed. But once you commit a DROP, or once you run it in MySQL (which auto-commits DDL), there is no rollback at the SQL level.

Misconception 3: "Renaming a column is a safe, low-risk operation."
Reality: Renaming a column is a metadata change that completes quickly, but it silently breaks every view, function, trigger, and piece of application code that references the old column name by string. ORM models, raw SQL strings in application code, and analytics queries can all fail after a column rename. Safe column renaming requires a multi-step migration: add the new column, copy data, update all references, then drop the old column.

---

## Why It Matters in Practice

Most production outages involving schema changes happen because a developer ran an ALTER TABLE that locked a large table without knowing it would block reads. Understanding which DDL operations are safe to run online and which require maintenance windows is essential for operating a production database.

Schema migrations that are tracked in version control and applied by tooling are not bureaucracy — they are the only way to keep development, staging, and production databases in sync. A database schema that has been edited manually in production, without a recorded migration, is effectively undocumented and unreputable. If the server dies and you rebuild from scratch, you have no record of the current schema.

---

## What Breaks

Running a blocking ALTER TABLE on a high-traffic table can cause a full application outage. PostgreSQL queues subsequent operations behind the ALTER TABLE lock. If the ALTER TABLE takes five minutes, every query issued during those five minutes waits in a queue. Connection pools fill up. Application timeouts cascade. The site appears to be down even though the database server is healthy.

```sql
-- DANGEROUS on a large table: PostgreSQL rewrites every row and holds a lock
ALTER TABLE events
    ALTER COLUMN metadata TYPE JSONB USING metadata::JSONB;

-- Safer pattern: add a new column, backfill, then swap
ALTER TABLE events ADD COLUMN metadata_new JSONB;
UPDATE events SET metadata_new = metadata::JSONB WHERE metadata IS NOT NULL;
-- Then, in a later migration, rename and drop the old column
```

Running DROP TABLE without first confirming the table name can destroy the wrong table. The command `DROP TABLE IF EXISTS user;` looks reasonable but `user` is a PostgreSQL reserved word. The session-level confusion can lead to dropping a table with a similar name if the identifier resolution behaves unexpectedly. Always quote identifiers to be precise: `DROP TABLE IF EXISTS "users";`

---

## Interview Angle

Common question forms:
- "What is the difference between DDL and DML?"
- "What risks are there in running ALTER TABLE in production?"
- "How do you safely rename a column in a production database?"

Answer frame:
Define DDL as structural changes (schema) versus DML as data changes. Name the three DDL statements and what each does. Explain the locking risk of ALTER TABLE and which operations cause row rewrites. Walk through the safe multi-step migration pattern for risky changes. Mention that PostgreSQL DDL is transactional (can be rolled back) while MySQL DDL auto-commits.

---

## Related Notes

- [[dml|DML — INSERT, UPDATE, DELETE]]
- [[data-types|SQL Data Types]]
- [[constraints|Constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK)]]
- [[alembic|Alembic]]
- [[what-is-sql|What is SQL]]
