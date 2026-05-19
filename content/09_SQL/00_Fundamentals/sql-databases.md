---
title: 02 - SQL Databases (PostgreSQL, MySQL, SQLite)
description: PostgreSQL, MySQL, and SQLite are the three most common SQL databases in Python development, and choosing the wrong one for a project creates problems that are expensive to fix later.
tags: [sql, layer-9, fundamentals, postgresql, mysql, sqlite]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# SQL Databases (PostgreSQL, MySQL, SQLite)

> The relational model organizes data into tables with strict rules about how tables relate to each other, and every SQL database is an implementation of that model - but not all implementations are equal.

---

## Quick Reference

**Core idea:**
- A relational database stores data in tables. A table has named columns with defined types and zero or more rows.
- PostgreSQL is feature-rich, ACID-compliant, and the preferred database for Python production applications.
- MySQL has wide hosting support and a large legacy codebase, but its defaults have historically been less strict than PostgreSQL's.
- SQLite is a file-based database with no server process, ideal for development, testing, and embedded use.
- A primary key uniquely identifies each row in a table. A foreign key references a primary key in another table.
- The relational model was described by Edgar Codd in 1970. Its core ideas - tables, keys, joins - have not changed.

**Tricky points:**
- SQLite has very permissive typing. It accepts any value in any column unless you enforce constraints explicitly.
- MySQL's default storage engine changed from MyISAM (no transactions) to InnoDB (transactions) at version 5.5. Old MySQL code may have run without transactions without anyone noticing.
- PostgreSQL and MySQL handle empty strings differently in some contexts. PostgreSQL treats `''` and `NULL` as completely different; older MySQL versions could silently convert one to the other in certain configurations.
- SQLite does not enforce foreign key constraints by default. You must run `PRAGMA foreign_keys = ON` in each connection.
- Running integration tests against SQLite when production uses PostgreSQL can hide bugs, because SQLite is more permissive.

---

## What It Is

Imagine a spreadsheet application. A single spreadsheet file contains multiple sheets. Each sheet has columns with headers and rows of data. Relationships between sheets are managed manually - you copy an ID from one sheet and paste it into another. The relational model is that spreadsheet idea made precise, enforced by software, and scaled to millions of rows. A relational database management system (RDBMS) is the software that enforces those rules and answers queries about the data.

In a relational database, data lives in tables. Each table represents one kind of thing - users, orders, products. Each column in the table represents one attribute of that thing, and the column has a defined data type (integer, text, date, and so on). Each row represents one instance. A primary key is a column (or combination of columns) whose value is unique for every row in the table - it is the identifier for that row. A foreign key is a column in one table whose value must match a primary key in another table. Foreign keys are how tables relate to each other: an `orders` table with a `user_id` foreign key column that references `users.id` is saying "every order belongs to a user that exists."

PostgreSQL, MySQL, and SQLite are all RDBMS products. They all store data in tables, all speak SQL (with dialect differences), and all enforce primary key uniqueness. But they differ significantly in features, defaults, and intended use cases. PostgreSQL was designed from the start to be standards-compliant and feature-complete. It supports full ACID transactions, a rich type system (arrays, JSONB, ranges, custom types), advanced indexing, and concurrent reads and writes with minimal locking. MySQL was designed for web applications that needed speed, and it sacrificed some correctness for performance in its early versions. SQLite is not a client-server database at all - it is a C library that stores the entire database in a single file on disk. There is no server process, no network connection, and no concurrent writes.

---

## How It Actually Works

PostgreSQL uses a process-per-connection model. Each client connection spawns a backend process on the server. The shared memory between these processes holds the buffer cache (pages read from disk), the write-ahead log (WAL) buffer, and lock tables. When you run a query, the backend process parses and plans it, then executes the plan by reading pages from the buffer cache (fetching from disk if not cached) and writing results back to the client. Writes go to the WAL first - this is what makes crash recovery safe. The WAL records every change before the change is applied to the data files. If the server crashes mid-write, the WAL replay restores the database to a consistent state on restart.

MySQL in its modern form uses InnoDB as the storage engine. InnoDB also uses a write-ahead log and supports ACID transactions. One notable architectural difference is that MySQL separates the SQL layer from the storage engine layer, which is why pluggable storage engines (InnoDB, MyISAM, Memory) exist. PostgreSQL does not have this separation. SQLite uses a single-writer model with file locking. Only one writer can modify the database file at a time, which is why SQLite is unsuitable for applications with concurrent writes. SQLite's WAL mode improves read concurrency (multiple readers can run while one writer writes), but the single-writer limit remains.

```sql
-- PostgreSQL: create a users table and an orders table with a foreign key
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    total_cents INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Query across tables using a join
SELECT u.email, o.id AS order_id, o.total_cents
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE u.email = 'alice@example.com';
```

---

## How It Connects

Every table needs a primary key to uniquely identify rows, and foreign keys to relate tables. The full rules for how constraints like PRIMARY KEY, FOREIGN KEY, UNIQUE, and NOT NULL work are covered in the constraints note.

[[constraints|Constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK)]]

The data you store in each column must have a defined type. Choosing the wrong type leads to incorrect comparisons, wasted storage, and subtle bugs. PostgreSQL has a richer type system than MySQL or SQLite.

[[data-types|SQL Data Types]]

DDL statements (CREATE TABLE, ALTER TABLE, DROP TABLE) are the mechanism for building and changing the structure described in this note. Understanding DDL is the next step after understanding the relational model.

[[ddl|DDL - CREATE, ALTER, DROP]]

---

## Common Misconceptions

Misconception 1: "SQLite is a toy database and should only be used for learning."
Reality: SQLite is used in production in billions of devices - every iOS app, every Android app, every browser uses SQLite internally. It is the right choice for embedded applications, mobile apps, and single-user desktop software. It is the wrong choice for a multi-user web application with concurrent writes.

Misconception 2: "PostgreSQL and MySQL are interchangeable. SQL is SQL."
Reality: The SQL dialects differ in meaningful ways. PostgreSQL uses `SERIAL` or `BIGSERIAL` for auto-incrementing primary keys; MySQL uses `AUTO_INCREMENT`. String concatenation uses `||` in PostgreSQL and `CONCAT()` in MySQL. Case sensitivity of string comparisons, behavior of NULL in indexes, and support for advanced features (window functions, CTEs, JSONB) all differ. Code written for one will often require changes to run on the other.

Misconception 3: "Using a more powerful database is always better."
Reality: SQLite is the correct choice for tests and local development because it requires zero infrastructure. Starting a full PostgreSQL server for unit tests adds seconds to every test run and complexity to CI setup. The trade-off is that SQLite's permissiveness can hide bugs - which is why integration tests should always run against the same database engine as production.

---

## Why It Matters in Practice

Choosing the wrong database for a project is a costly mistake. A team that builds on SQLite for a web application and then needs to scale to concurrent users faces a rewrite. A team that runs tests against SQLite but runs production on PostgreSQL will encounter bugs in production that never appeared in tests - bugs caused by the PostgreSQL type system rejecting values that SQLite silently accepted.

Understanding the relational model - tables, primary keys, foreign keys - is foundational to everything else in SQL. Every SQL concept from joins to indexes to transactions is built on top of this model. A developer who understands why foreign keys exist (to prevent orphaned rows and enforce referential integrity) writes schemas that do not allow corrupt data. A developer who skips foreign keys to "keep things simple" ends up writing application-level checks that inevitably have race conditions.

---

## What Breaks

If you use SQLite for development and PostgreSQL for production, and you insert an empty string into a column that production PostgreSQL has a CHECK constraint on, the test passes silently but the production insert fails. This class of bug is hard to catch before deployment.

```sql
-- This works in SQLite but may fail in PostgreSQL if types are strict
-- SQLite allows storing text in a column declared as INTEGER
INSERT INTO users (id, email) VALUES ('not-a-number', 'test@example.com');
-- PostgreSQL: ERROR: invalid input syntax for type integer: "not-a-number"
```

If you forget to enable foreign keys in SQLite, you can insert rows that reference non-existent parent rows. The database accepts them silently. When you later run the same schema on PostgreSQL with foreign keys enforced, inserts that worked in development fail in production.

```sql
-- SQLite: foreign keys are OFF by default
-- This insert succeeds even though user_id 9999 does not exist
INSERT INTO orders (user_id, total_cents) VALUES (9999, 1000);

-- Enable enforcement first:
PRAGMA foreign_keys = ON;
-- Now the same insert raises: FOREIGN KEY constraint failed
```

---

## Interview Angle

Common question forms:
- "What is a relational database?"
- "What is the difference between PostgreSQL and MySQL?"
- "When would you use SQLite?"
- "What is a primary key? What is a foreign key?"

Answer frame:
Define the relational model: tables, rows, columns, primary keys, foreign keys. Explain what a primary key guarantees (uniqueness, not null). Explain what a foreign key enforces (referential integrity - you cannot reference a row that does not exist). Then contrast the three databases: PostgreSQL for production backends, MySQL for legacy or high-compatibility environments, SQLite for embedded and test use. Mention the SQLite foreign key gotcha if the interviewer is technical.

---

## Related Notes

- [[constraints|Constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK)]]
- [[data-types|SQL Data Types]]
- [[ddl|DDL - CREATE, ALTER, DROP]]
- [[what-is-sql|What is SQL]]
- [[acid-properties|ACID Properties]]
