---
title: DML — INSERT, UPDATE, DELETE
description: DML statements change the data inside a database's tables, and every one of them can cause irreversible data loss if used without care or proper transaction management.
tags: [sql, layer-9, dml, mutations]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# DML — INSERT, UPDATE, DELETE

> DML is how data enters, changes, and leaves a database — and every DML statement that runs without a WHERE clause or outside a transaction is a production incident waiting to happen.

---

## Quick Reference

**Core idea:**
- DML stands for Data Manipulation Language. DML statements modify data inside tables rather than the table structure itself.
- The three core DML statements are INSERT (add new rows), UPDATE (modify existing rows), and DELETE (remove rows).
- UPDATE and DELETE without a WHERE clause affect every row in the table. This is valid SQL and the database will not warn you.
- PostgreSQL supports a RETURNING clause on all three statements, which returns the affected rows as a result set.
- DML runs inside transactions. Changes are not visible to other sessions until the transaction commits.

**Tricky points:**
- UPDATE and DELETE with no WHERE clause silently operate on all rows. There is no confirmation prompt.
- INSERT with a column list prevents accidents if columns are added to the table later. `INSERT INTO t VALUES (...)` breaks when a new column is added.
- ON CONFLICT (upsert) in PostgreSQL lets INSERT either ignore or update a row when a unique constraint is violated.
- DML triggers row-level locks on the affected rows. Long-running DML statements can block other writers on the same rows.
- RETURNING does not exist in MySQL or SQLite (SQLite added a limited version in 3.35.0). Code relying on RETURNING is PostgreSQL-specific.

---

## What It Is

Imagine a filing cabinet full of folders. DDL is the act of building the cabinet — choosing the number of drawers, labeling them, deciding what kinds of documents go where. DML is everything that happens once the cabinet exists: filing new documents (INSERT), updating the information on existing documents (UPDATE), and throwing documents away (DELETE). The cabinet's structure does not change. Only the contents do.

DML stands for Data Manipulation Language. It covers the statements that interact with data rather than schema. INSERT adds one or more new rows to a table. UPDATE modifies columns of existing rows. DELETE removes rows. Every operation that changes what data is stored in the database is DML. Queries that only read data (SELECT) are sometimes grouped separately as DQL (Data Query Language), though in practice most people refer to SELECT as part of DML as well.

INSERT requires at minimum the table name and the values to insert. Best practice is to always provide a column list explicitly, so the INSERT is not dependent on column order. When you write `INSERT INTO products (name, price_cents) VALUES ('Widget', 999)`, the statement is clear about what goes where, and it continues to work correctly if someone adds a new column to the table. When you write `INSERT INTO products VALUES (DEFAULT, 'Widget', 999, now())`, the statement breaks the moment someone adds a column or reorders them.

UPDATE modifies columns of rows that match a WHERE clause. The WHERE clause is what restricts the update to specific rows. Without a WHERE clause, the UPDATE applies to every row in the table. DELETE works the same way: with a WHERE clause it removes matching rows; without one it removes all rows. The database performs these operations eagerly and completely. There is no undo at the SQL level once a transaction commits.

---

## How It Actually Works

When PostgreSQL processes an INSERT, it acquires a row-level lock on the new row (or rather, on the page it will occupy), writes the new row data to a heap page (the table's storage file), and records the change in the WAL (Write-Ahead Log) for crash recovery. The new row is marked as visible only to the current transaction until the transaction commits. This is part of PostgreSQL's MVCC (Multi-Version Concurrency Control) model — each transaction sees a consistent snapshot of the database and is not affected by uncommitted changes from other transactions.

UPDATE in PostgreSQL does not modify a row in place. Instead, it inserts a new version of the row and marks the old version as dead. The old version remains on disk until VACUUM reclaims it. This is also MVCC: if another transaction holds a snapshot from before your UPDATE, it still reads the old version. The dead tuples left by UPDATE accumulate over time and can cause table bloat if VACUUM does not run frequently enough. DELETE works similarly: rows are marked as dead rather than physically removed.

The RETURNING clause, unique to PostgreSQL (and now partially supported in SQLite), makes INSERT, UPDATE, and DELETE return a result set of the affected rows. This is extremely useful for retrieving auto-generated values (like a sequence-generated ID) without a separate SELECT query, and for getting the final state of updated rows in a single round trip.

```sql
-- INSERT with column list (preferred)
INSERT INTO users (name, email, created_at)
VALUES ('Alice', 'alice@example.com', now());

-- INSERT multiple rows in one statement
INSERT INTO users (name, email, created_at)
VALUES
    ('Bob',   'bob@example.com',   now()),
    ('Carol', 'carol@example.com', now());

-- INSERT with RETURNING to get the generated id
INSERT INTO users (name, email, created_at)
VALUES ('Dave', 'dave@example.com', now())
RETURNING id, created_at;

-- Upsert: insert or update on conflict
INSERT INTO user_scores (user_id, score)
VALUES (42, 100)
ON CONFLICT (user_id) DO UPDATE
    SET score = EXCLUDED.score;

-- UPDATE with WHERE clause (always include WHERE unless you mean all rows)
UPDATE users
SET email = 'alice@new.com'
WHERE id = 1;

-- UPDATE with RETURNING
UPDATE users
SET last_login = now()
WHERE id = 1
RETURNING id, last_login;

-- DELETE with WHERE clause
DELETE FROM sessions
WHERE expires_at < now();

-- DELETE with RETURNING
DELETE FROM tasks
WHERE id = 99
RETURNING id, title;
```

---

## How It Connects

DML changes are only safe when wrapped in transactions. A transaction groups multiple DML statements into an atomic unit — either all succeed or all roll back. Without transactions, a partial failure (for example, money debited but not credited) leaves the database in a corrupt state.

[[transactions|Transactions]]

The WHERE clause is what restricts UPDATE and DELETE to specific rows. Understanding how the WHERE clause works — comparison operators, NULL handling, AND/OR logic — is essential for writing safe DML.

[[where-clause|WHERE Clause]]

DDL defines the table structure that DML operates on. Changes to the schema via ALTER TABLE (adding or removing columns) can silently break DML statements that assume a particular column order.

[[ddl|DDL — CREATE, ALTER, DROP]]

---

## Common Misconceptions

Misconception 1: "The database will ask me to confirm before running a dangerous UPDATE or DELETE."
Reality: The database does not prompt for confirmation. `DELETE FROM orders;` runs immediately and removes every row. In MySQL with autocommit (the default), the deletion commits instantly. In PostgreSQL inside an explicit transaction, you can roll back, but only if you have not yet committed. There is no warning dialog, no "are you sure?" prompt from the SQL engine itself.

Misconception 2: "I can get the inserted row's ID with a SELECT after the INSERT."
Reality: A separate SELECT after an INSERT introduces a race condition in concurrent systems: another INSERT could run between your INSERT and your SELECT, and `SELECT MAX(id)` would return the wrong row. The correct approach in PostgreSQL is the RETURNING clause: `INSERT INTO users ... RETURNING id`. In MySQL, `LAST_INSERT_ID()` returns the ID for the most recent INSERT in the same connection, which is session-local and safe from race conditions.

Misconception 3: "DELETE removes the row from disk immediately."
Reality: In PostgreSQL's MVCC model, DELETE marks the row as dead (invisible to new transactions) but does not physically remove it from disk. The space is reclaimed by VACUUM, which runs periodically in the background (autovacuum) or can be triggered manually. A table from which millions of rows were recently deleted may show the same size on disk as before the DELETE until VACUUM runs.

---

## Why It Matters in Practice

The most common category of production database incident is accidental mass data modification. An UPDATE without a WHERE clause that runs against production wipes the email addresses of every user. A DELETE that was meant to target one record removes ten thousand records because a copy-paste error dropped the WHERE clause. These are not hypothetical — they happen regularly at real companies. The only defenses are: use transactions so you can roll back, preview the affected rows with a SELECT using the same WHERE clause before running the UPDATE or DELETE, and connect to production databases with a role that has the minimum permissions necessary.

Understanding RETURNING changes how you write application code. Without it, inserting a row and then needing its generated ID requires two round trips to the database. With RETURNING, one query gives you both the confirmation that the insert succeeded and the values the database generated. This is not a minor optimization — in a web handler that inserts a row and immediately redirects to a URL containing the new ID, the RETURNING approach is both faster and race-condition-free.

---

## What Breaks

Forgetting the WHERE clause in UPDATE or DELETE is the most dangerous mistake in DML. The SQL standard allows it, and the database engine will comply. If autocommit is on (as it is by default in most database clients and MySQL), there is no transaction to roll back.

```sql
-- Intended: deactivate one specific user
UPDATE users SET active = false WHERE id = 42;

-- Accidental: deactivates ALL users (WHERE was forgotten)
UPDATE users SET active = false;
```

Using INSERT without a column list breaks silently when the table schema changes. A migration that adds a new column in the middle of the column order causes the VALUES to map to the wrong columns.

```sql
-- This breaks if a new column is added before price_cents in the schema
INSERT INTO products VALUES (DEFAULT, 'Widget', 999);

-- This is always correct regardless of column additions
INSERT INTO products (name, price_cents) VALUES ('Widget', 999);
```

Relying on RETURNING in application code and then running the application against MySQL will produce errors, because MySQL does not support RETURNING. This is a common issue when an application is developed against PostgreSQL but tested against MySQL for some reason, or when a library abstraction does not handle the difference transparently.

---

## Interview Angle

Common question forms:
- "What is DML? Name the three main statements."
- "What happens if you run UPDATE without a WHERE clause?"
- "How do you get the ID of a row you just inserted?"
- "What is an upsert and how do you do it in PostgreSQL?"

Answer frame:
Define DML as data manipulation (not structure). Name INSERT, UPDATE, DELETE. Explain the WHERE clause requirement for safe UPDATE and DELETE. Describe RETURNING for getting generated values. Explain ON CONFLICT for upsert. If the interviewer asks about safety, mention wrapping DML in transactions and previewing changes with SELECT first.

---

## Related Notes

- [[transactions|Transactions]]
- [[where-clause|WHERE Clause]]
- [[ddl|DDL — CREATE, ALTER, DROP]]
- [[select-basics|SELECT Basics]]
- [[acid-properties|ACID Properties]]
