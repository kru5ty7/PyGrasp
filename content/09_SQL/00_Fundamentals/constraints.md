---
title: Constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK)
description: Database constraints are the enforcement layer for data integrity rules, and pushing those rules into the database rather than relying solely on application code is the only way to guarantee they hold under all conditions.
tags: [sql, layer-9, constraints, schema, integrity]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# Constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK)

> Constraints are promises the database keeps on your behalf — they enforce data rules at the storage layer, where no application bug, race condition, or manual SQL edit can bypass them.

---

## Quick Reference

**Core idea:**
- A constraint is a rule attached to a column or table that the database enforces on every write operation.
- PRIMARY KEY: each row has a unique, non-null identifier. Most databases create a unique B-tree index for the primary key automatically.
- FOREIGN KEY: a column value must match an existing value in the referenced table's primary key (or unique key). Enforces referential integrity.
- UNIQUE: no two rows may have the same value in the constrained column(s). NULL values are treated specially.
- NOT NULL: the column must have a value on every row. NULL is rejected at insert or update time.
- CHECK: an arbitrary boolean expression must evaluate to TRUE for every row that is inserted or updated.

**Tricky points:**
- In PostgreSQL and the SQL standard, a UNIQUE constraint allows multiple NULL values. NULL is not equal to NULL, so two NULL values do not violate uniqueness. This surprises most developers.
- ON DELETE CASCADE on a foreign key automatically deletes child rows when the parent row is deleted. This can cause unexpected mass deletions.
- Adding a NOT NULL constraint to an existing column with no default causes a table rewrite in older PostgreSQL (pre-11) because every row must be updated.
- CHECK constraints that call non-deterministic functions (like `now()` or `random()`) are allowed syntactically but behave incorrectly when rows are loaded from pg_dump, because the constraint is re-evaluated at load time.
- A PRIMARY KEY constraint is the combination of a UNIQUE constraint and a NOT NULL constraint. You cannot have a null primary key value.

---

## What It Is

Think of database constraints like the rules printed on a form. A government form might say: "Social Security Number is required (not blank)," "Date of birth must be in the past," "State must be a valid two-letter code." These rules are printed on the form itself — anyone filling out the form sees them, and any clerk processing the form checks them. You cannot submit the form with a future birth date just because the clerk was new and forgot to check. The rule is built into the document. Database constraints work the same way: the rule is built into the schema, not into any one application or script.

A constraint is a rule attached to a column or table that the database evaluates on every INSERT and UPDATE. If the new data violates the constraint, the database rejects the operation with an error — the data is never written. This is fundamentally different from validation logic in application code. Application code can have bugs. Application code can be bypassed by a direct SQL connection, a migration script, or a data import. Application code on two different servers can disagree about the rules. Constraints cannot be bypassed by any of these means.

The PRIMARY KEY constraint designates one column (or combination of columns) as the unique identifier for each row in the table. PRIMARY KEY implies both UNIQUE (no two rows can have the same value) and NOT NULL (the key column cannot be empty). Every table should have a primary key. Without one, there is no reliable way to identify, update, or delete a specific row. Most databases automatically create a unique index on the primary key column, which also makes primary-key lookups fast.

A FOREIGN KEY constraint declares that the values in one column must match existing values in another table's primary key (or unique key). This is how the relational model enforces referential integrity. If an `orders` table has a `user_id` column with a FOREIGN KEY referencing `users(id)`, the database will refuse to insert an order with a `user_id` that does not exist in the users table. It will also refuse to delete a user who has existing orders, unless the FOREIGN KEY is defined with `ON DELETE CASCADE` (which automatically deletes the child rows) or `ON DELETE SET NULL` (which sets the foreign key column to NULL). Without these rules, orphaned rows — orders with no valid user — would accumulate silently.

UNIQUE ensures no two rows share the same value in the constrained column(s). It is commonly used for email addresses, usernames, and natural keys that must be globally unique across the table. A UNIQUE constraint automatically creates an index, which also speeds up lookups on that column. A UNIQUE constraint on multiple columns creates a composite uniqueness rule: the combination of values must be unique, but each individual value may repeat.

NOT NULL is the simplest constraint. It says the column must have a value in every row — the database will not accept NULL for that column. This prevents the class of bugs where application code forgets to set a field and stores NULL silently, leading to null pointer exceptions later when the data is read.

CHECK constraints enforce arbitrary domain rules using a boolean expression. `CHECK (age >= 18)` ensures the column is never less than 18. `CHECK (status IN ('pending', 'active', 'cancelled'))` ensures the column holds only one of three defined values. `CHECK (end_date > start_date)` enforces a relationship between two columns in the same row.

---

## How It Actually Works

Constraint checking in PostgreSQL happens at the end of each statement, not during the individual row writes (unless the constraint is deferred). When you insert a row, PostgreSQL writes the row, then checks all constraints on that table. If any constraint is violated, the write is rolled back. For UNIQUE and FOREIGN KEY constraints, this check involves an index lookup — PostgreSQL uses the automatically created index to verify uniqueness or the existence of the referenced row.

Deferred constraints are an advanced feature. A deferred constraint is checked at transaction commit rather than at statement end. This is useful when you need to insert rows in a circular dependency (A references B, B references A) within one transaction. Declaring the constraint `DEFERRABLE INITIALLY DEFERRED` allows the constraint to be temporarily violated during the transaction, with the check deferred until commit.

The index created by a PRIMARY KEY or UNIQUE constraint is a B-tree index by default. This is both a correctness mechanism (the index finds duplicates efficiently) and a performance benefit (queries that filter or join on the constrained column use the index). Creating a UNIQUE constraint is equivalent to creating a UNIQUE INDEX — either approach produces the same result.

Foreign key constraint checks require the database to verify, on every insert into the child table, that the referenced value exists in the parent table, and on every delete from the parent table, that no child rows reference the deleted row. Without indexes on the foreign key column in the child table, the parent-delete check requires a full scan of the child table. PostgreSQL does not automatically create an index on foreign key columns — you must create it manually, and you should always do so.

```sql
-- PRIMARY KEY: single column
CREATE TABLE users (
    id    BIGSERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE
);

-- PRIMARY KEY: composite (rare but valid)
CREATE TABLE user_roles (
    user_id BIGINT NOT NULL REFERENCES users(id),
    role    TEXT NOT NULL,
    PRIMARY KEY (user_id, role)
);

-- FOREIGN KEY with ON DELETE behavior options
CREATE TABLE orders (
    id      BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    -- ON DELETE RESTRICT: refuse to delete user if they have orders
    -- ON DELETE CASCADE: delete orders automatically when user is deleted
    -- ON DELETE SET NULL: set user_id to NULL when user is deleted
    total_cents INTEGER NOT NULL CHECK (total_cents >= 0)
);

-- UNIQUE constraint (also creates an index)
CREATE TABLE products (
    id  BIGSERIAL PRIMARY KEY,
    sku TEXT NOT NULL UNIQUE
);

-- UNIQUE on multiple columns: (user_id, product_id) pair must be unique
CREATE TABLE wishlist_items (
    user_id    BIGINT NOT NULL REFERENCES users(id),
    product_id BIGINT NOT NULL REFERENCES products(id),
    UNIQUE (user_id, product_id)
);

-- NOT NULL
CREATE TABLE sessions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    BIGINT NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- CHECK constraints
CREATE TABLE events (
    id         BIGSERIAL PRIMARY KEY,
    name       TEXT NOT NULL,
    starts_at  TIMESTAMPTZ NOT NULL,
    ends_at    TIMESTAMPTZ NOT NULL,
    status     TEXT NOT NULL CHECK (status IN ('draft', 'published', 'cancelled')),
    capacity   INTEGER CHECK (capacity > 0),
    CONSTRAINT ends_after_starts CHECK (ends_at > starts_at)
);

-- Always create an index on foreign key columns in child tables
CREATE INDEX ON orders (user_id);
```

---

## How It Connects

Constraints are declared as part of DDL. CREATE TABLE includes constraint definitions inline, and ALTER TABLE can add or drop constraints. The DDL note covers the mechanics of writing and modifying these definitions.

[[ddl|DDL — CREATE, ALTER, DROP]]

PRIMARY KEY and UNIQUE constraints automatically create indexes. Understanding what kind of index is created, what its structure is, and how it supports queries helps you understand why these constraints provide both integrity and performance.

[[sql-indexes|SQL Indexes]]

The difference between enforcing rules in the database versus the application layer is closely related to transaction isolation. Constraints are checked at statement or transaction commit time, which means they work correctly even when multiple concurrent writes happen simultaneously.

[[transactions|Transactions]]

---

## Common Misconceptions

Misconception 1: "UNIQUE allows only one NULL because NULL = NULL is true and would be a duplicate."
Reality: In PostgreSQL and the SQL standard, UNIQUE allows multiple NULL values in the same column. The reasoning is that NULL represents an unknown value. Two unknowns cannot be determined to be equal. Therefore, inserting two rows with NULL in a UNIQUE column does not violate the constraint. MySQL (in some modes) deviates from this and only allows one NULL per UNIQUE column.

Misconception 2: "Validating data in the application layer is sufficient. I do not need database constraints."
Reality: Application-layer validation fails in several real scenarios: direct database access by a DBA or data team, bulk imports or migrations that bypass the application, bugs in one code path that another code path does not have, and race conditions between concurrent requests that both pass the application check but together violate the rule. Database constraints are enforced atomically at the storage layer and cannot be bypassed by any of these. The correct approach uses both: application validation for user feedback, database constraints as the authoritative safety net.

Misconception 3: "ON DELETE CASCADE is safe because it keeps the database consistent."
Reality: ON DELETE CASCADE keeps the database consistent in the sense that no orphaned rows exist. But it can cause unexpected mass deletions. Deleting a user cascades to their orders, which cascades to order items, which cascades to shipment records, and so on through the whole dependency chain — instantly and permanently. In a database where several tables have CASCADE rules, a single DELETE at the top of the hierarchy can remove thousands of rows across many tables. ON DELETE RESTRICT (which refuses the delete if child rows exist) is the safer default.

---

## Why It Matters in Practice

Data integrity problems are among the most expensive bugs to fix in production systems. Once corrupt data enters the database — orphaned foreign keys, NULL values in columns that should never be null, duplicate records in a column that should be unique — the cleanup is a laborious, error-prone manual process. Constraints prevent these problems at the point of insertion, before corrupt data ever reaches the database.

The constraint versus application-layer debate comes up regularly in code reviews. Application code that duplicates constraint logic adds maintenance burden: when a rule changes, it must be changed in both places. Database constraints are the authoritative source of truth for data integrity. Application code handles user experience (showing friendly error messages, pre-validation before attempting a write). The two layers have complementary roles, not competing ones.

---

## What Breaks

Missing a NOT NULL constraint on a column that should always have a value allows NULL to silently enter the database. Application code that later assumes the column is always populated will encounter null pointer errors in production that never appeared in development, because test data was always populated correctly.

```sql
-- Column declared without NOT NULL
CREATE TABLE invoices (
    id         BIGSERIAL PRIMARY KEY,
    due_date   DATE  -- nullable by accident
);

-- An import script inserts a row without due_date
INSERT INTO invoices DEFAULT VALUES;
-- Succeeds silently. due_date is NULL.

-- Later, application code does:
-- invoice.due_date.strftime('%Y-%m-%d')  -- AttributeError: NoneType has no attribute strftime
```

A missing index on a foreign key column causes parent-table deletes to do a full sequential scan of the child table. On a large child table, deleting one parent row can take minutes.

```sql
-- orders.user_id references users(id) but has no index
-- Deleting one user requires scanning all orders to find any that reference them
DELETE FROM users WHERE id = 42;
-- On a table with 10 million orders, this takes a full scan.

-- Fix: always add this after creating the foreign key:
CREATE INDEX ON orders (user_id);
```

---

## Interview Angle

Common question forms:
- "What is referential integrity and how do foreign keys enforce it?"
- "What is the difference between UNIQUE and PRIMARY KEY?"
- "Why does UNIQUE allow multiple NULLs?"
- "Should data validation live in the database or the application?"

Answer frame:
Define referential integrity: foreign keys ensure that child rows only reference parent rows that actually exist. Distinguish PRIMARY KEY from UNIQUE: PRIMARY KEY adds the NOT NULL requirement and there can only be one per table; UNIQUE allows NULLs and a table can have multiple UNIQUE constraints. Explain the NULL behavior in UNIQUE (unknown != unknown, so multiple NULLs are allowed). For the database vs application question: both layers have a role — database constraints are the authoritative safety net, application validation provides user feedback.

---

## Related Notes

- [[ddl|DDL — CREATE, ALTER, DROP]]
- [[sql-indexes|SQL Indexes]]
- [[transactions|Transactions]]
- [[sql-databases|SQL Databases (PostgreSQL, MySQL, SQLite)]]
- [[data-types|SQL Data Types]]
