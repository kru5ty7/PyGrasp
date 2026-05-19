---
title: 37 - Savepoints
description: A savepoint is a named marker within an open transaction that allows partial rollback without aborting the entire transaction.
tags: [sql, layer-9, transactions, savepoints]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Savepoints

> A savepoint is a named point within an open transaction to which you can roll back without discarding everything the transaction has done so far. They make it possible to recover from errors selectively inside a single transaction.

---

## Quick Reference

**Core idea:**
- `SAVEPOINT name` marks a rollback point within an open transaction
- `ROLLBACK TO SAVEPOINT name` undoes all work since the savepoint but keeps the transaction open
- `RELEASE SAVEPOINT name` discards the savepoint without rolling back (similar to confirming the sub-operation)
- After any error in PostgreSQL, the transaction is in an aborted state - `ROLLBACK TO SAVEPOINT` is the only way to recover without abandoning the whole transaction
- SQLAlchemy uses savepoints internally to implement nested transactions via `session.begin_nested()`
- Savepoints are not a substitute for proper error handling - overuse leads to complex, hard-to-reason-about transaction logic

**Tricky points:**
- Rolling back to a savepoint does not release the savepoint - you can roll back to it multiple times
- `RELEASE SAVEPOINT` does not commit anything; it only removes the savepoint marker
- PostgreSQL's aborted transaction state after an error cannot be escaped by issuing new SQL - only `ROLLBACK` or `ROLLBACK TO SAVEPOINT` resets the state
- Multiple savepoints can exist simultaneously, and they are ordered - rolling back to an earlier savepoint discards all savepoints created after it
- Savepoints interact with sequences the same way transactions do: sequence advances within a rolled-back savepoint are not reversed

---

## What It Is

Think of a savepoint as a quicksave in a video game. You are in the middle of a long dungeon run (a transaction). Before attempting a risky fight (an operation that might fail), you hit quicksave (create a savepoint). If you die (the operation fails), you reload from the quicksave (rollback to savepoint) rather than restarting from the beginning of the dungeon (aborting the whole transaction). Your progress up to the quicksave is preserved, and you continue from there. Unlike a video game, you can have multiple quicksaves at different points in the dungeon, and you can reload to any earlier one - though reloading to an earlier save discards the later ones.

The fundamental problem savepoints solve is PostgreSQL's strict error state behavior. Once any statement inside a transaction raises an error, PostgreSQL marks the entire transaction as aborted. It will reject every subsequent command with the message `current transaction is aborted, commands ignored until end of transaction block`. The only way out is `ROLLBACK` to abort the entire transaction, or `ROLLBACK TO SAVEPOINT` to reset to a named earlier point. Without savepoints, a single bad row in a batch insert means rolling back the entire batch.

The classic use case is a batch operation where individual rows may fail due to constraint violations, but you want to commit as many rows as possible rather than aborting everything. For each row in the batch, you create a savepoint before attempting the insert. If the insert fails, you roll back to the savepoint (clearing the error state and discarding only the failed insert) and continue to the next row. If the insert succeeds, you release the savepoint and move on. At the end, you commit, and only the successful rows are persisted.

ORMs use savepoints to implement nested transactions in languages that do not have first-class support for sub-transactions in SQL. When SQLAlchemy's `session.begin_nested()` is called inside an active transaction, SQLAlchemy issues a `SAVEPOINT` under the hood. Committing the nested context issues `RELEASE SAVEPOINT`. Rolling back the nested context issues `ROLLBACK TO SAVEPOINT`. This gives application code a composable, nestable transaction abstraction that maps directly to PostgreSQL's savepoint mechanism, allowing library code and application code to each manage their own rollback scope without needing to coordinate which one owns the outermost `BEGIN`.

---

## How It Actually Works

The three savepoint commands are straightforward. `SAVEPOINT` creates the marker, `ROLLBACK TO SAVEPOINT` rewinds to it, and `RELEASE SAVEPOINT` removes it.

```sql
BEGIN;

INSERT INTO orders (id, customer_id, total) VALUES (1001, 42, 99.99);

SAVEPOINT after_first_insert;

INSERT INTO orders (id, customer_id, total) VALUES (1002, 99, 49.99);

-- Suppose this insert fails due to a constraint violation.
-- PostgreSQL enters aborted state.

ROLLBACK TO SAVEPOINT after_first_insert;
-- Transaction is now alive again. The failed insert is gone.
-- The first insert (id=1001) is still present.

INSERT INTO orders (id, customer_id, total) VALUES (1003, 77, 29.99);

COMMIT;
-- Only rows 1001 and 1003 are committed.
```

The batch insert pattern with per-row savepoints looks like this:

```sql
BEGIN;

SAVEPOINT batch_start;

INSERT INTO products (sku, name, price) VALUES ('ABC-1', 'Widget A', 9.99);
RELEASE SAVEPOINT batch_start;  -- success: discard savepoint, keep insert

SAVEPOINT batch_start;

INSERT INTO products (sku, name, price) VALUES ('ABC-1', 'Widget B', 14.99);
-- ERROR: duplicate key value violates unique constraint

ROLLBACK TO SAVEPOINT batch_start;  -- discard the failed insert, stay in transaction
RELEASE SAVEPOINT batch_start;

SAVEPOINT batch_start;

INSERT INTO products (sku, name, price) VALUES ('ABC-3', 'Widget C', 19.99);
RELEASE SAVEPOINT batch_start;  -- success

COMMIT;
-- Only 'ABC-1' (Widget A) and 'ABC-3' (Widget C) are inserted.
```

In Python with psycopg2, the savepoint pattern for a batch with error tolerance:

```python
conn = psycopg2.connect(dsn)
cursor = conn.cursor()

rows = [
    ('ABC-1', 'Widget A', 9.99),
    ('ABC-1', 'Widget B', 14.99),  # will fail: duplicate SKU
    ('ABC-3', 'Widget C', 19.99),
]

for sku, name, price in rows:
    try:
        cursor.execute("SAVEPOINT row_insert")
        cursor.execute(
            "INSERT INTO products (sku, name, price) VALUES (%s, %s, %s)",
            (sku, name, price)
        )
        cursor.execute("RELEASE SAVEPOINT row_insert")
    except psycopg2.errors.UniqueViolation:
        cursor.execute("ROLLBACK TO SAVEPOINT row_insert")
        # log the skipped row, continue

conn.commit()
```

SQLAlchemy's `begin_nested()` maps directly to this mechanism:

```python
from sqlalchemy.orm import Session

with Session(engine) as session:
    with session.begin():
        session.add(Order(id=1001, total=99.99))

        with session.begin_nested():  # issues SAVEPOINT
            try:
                session.add(Order(id=1001, total=49.99))  # will fail: duplicate PK
                # SQLAlchemy issues RELEASE SAVEPOINT on success
            except Exception:
                # SQLAlchemy issues ROLLBACK TO SAVEPOINT on exception
                pass

        session.add(Order(id=1003, total=29.99))
        # outer begin() issues COMMIT: only 1001 and 1003 are inserted
```

Multiple savepoints can coexist in a single transaction:

```sql
BEGIN;
SAVEPOINT sp1;
INSERT INTO log (msg) VALUES ('step 1');

SAVEPOINT sp2;
INSERT INTO log (msg) VALUES ('step 2');

SAVEPOINT sp3;
INSERT INTO log (msg) VALUES ('step 3');

ROLLBACK TO SAVEPOINT sp2;
-- 'step 3' is undone, sp3 is discarded
-- 'step 2' is also undone (rolled back past sp2)
-- 'step 1' remains

COMMIT;
-- Only 'step 1' is committed
```

---

## How It Connects

Savepoints exist within transactions and depend entirely on the transaction lifecycle. A savepoint cannot exist outside a `BEGIN` / `COMMIT` block, and releasing or rolling back all savepoints does not commit the transaction.

[[transactions|Transactions]]

PostgreSQL's aborted transaction state - the reason savepoints are necessary for error recovery within a transaction - is a consequence of how PostgreSQL enforces the atomicity and consistency properties. Understanding why PostgreSQL enters this state requires understanding ACID.

[[acid-properties|ACID Properties]]

SQLAlchemy uses savepoints as the implementation mechanism for nested transactions via `session.begin_nested()`. Understanding the mapping between ORM-level nested session management and SQL-level savepoints is essential for debugging ORM transaction behavior in async Python code.

[[sqlalchemy-async|SQLAlchemy Async]]

---

## Common Misconceptions

Misconception 1: "RELEASE SAVEPOINT commits the work done since the savepoint."
Reality: `RELEASE SAVEPOINT` removes the savepoint marker and makes it impossible to roll back to that point, but it does not commit anything. All the work done since the savepoint (and before it) remains part of the outer transaction and is only committed when the outer `COMMIT` is issued. `RELEASE SAVEPOINT` is simply cleanup - it says "I no longer need the ability to roll back to here."

Misconception 2: "After ROLLBACK TO SAVEPOINT, the savepoint no longer exists and I cannot use it again."
Reality: `ROLLBACK TO SAVEPOINT` rewinds the transaction to the savepoint but keeps the savepoint itself intact. You can roll back to the same savepoint multiple times. If you want to remove it after rolling back to it, you must explicitly `RELEASE SAVEPOINT` it.

Misconception 3: "Savepoints allow me to partially commit a transaction - some changes are visible while others are not."
Reality: No changes within a transaction are visible to other sessions until the outer `COMMIT` is issued. Savepoints only control the rollback scope within the transaction. From the outside, the transaction is invisible until it commits completely. There is no mechanism to make partial changes visible without committing the entire transaction.

---

## Why It Matters in Practice

Savepoints become essential in two scenarios that are common in production systems. The first is bulk data loading: when inserting thousands of rows from an external source (CSV import, API sync, ETL pipeline), individual rows may fail due to constraint violations, duplicate keys, or data type mismatches. Without savepoints, the first bad row aborts the entire load. With savepoints, bad rows are logged and skipped, and the good rows are committed. This makes bulk operations tolerant of dirty input data without requiring pre-cleaning.

The second scenario is ORM-based application code where library functions and application code each manage their own transaction scope. Without savepoints, a library function that needs transactional behavior must either create its own connection (inefficient) or trust that the caller's transaction will be managed correctly. With savepoints, library code can use `session.begin_nested()` to get rollback isolation without needing to own the outer transaction. This compositional property is why every mature ORM implements savepoints as the foundation for nested transaction support.

---

## What Breaks

**Forgetting to handle PostgreSQL's aborted transaction state.** An application issues three inserts inside a transaction. The second insert fails on a unique constraint. The application catches the exception and logs it, then attempts the third insert. PostgreSQL rejects the third insert with `InFailedSqlTransaction`. The application does not check for this error and calls `commit()`. PostgreSQL rolls back the entire transaction because it was in an aborted state. None of the three inserts are committed, including the first one that succeeded. The fix is `ROLLBACK TO SAVEPOINT` around each insert to clear the error state.

```sql
BEGIN;
INSERT INTO items (id, name) VALUES (1, 'Alpha');  -- OK
INSERT INTO items (id, name) VALUES (1, 'Beta');   -- ERROR: duplicate key
-- Transaction is now in aborted state
INSERT INTO items (id, name) VALUES (2, 'Gamma');  -- Silently ignored (or error)
COMMIT;  -- Rolls back everything, including the first insert
```

**Savepoint name collisions in ORM-generated SQL.** An application uses a loop to process records, each in a `session.begin_nested()` block. SQLAlchemy generates savepoint names like `sa_savepoint_1`, `sa_savepoint_2`, etc. A manually placed `SAVEPOINT sa_savepoint_1` in raw SQL inside the loop collides with the ORM-generated name on the second iteration. The `ROLLBACK TO SAVEPOINT` issued by SQLAlchemy rolls back farther than intended. The fix is to never manually name savepoints with the same naming convention the ORM uses, or to avoid mixing raw savepoint SQL with ORM-managed nested transactions.

**Using savepoints to mask errors that should abort the transaction.** An application wraps every statement in a savepoint and silently rolls back on any error, logging it and continuing. A critical INSERT fails due to a foreign key constraint - the referenced parent record does not exist. The application logs the error, continues, and commits the dependent child records that reference a non-existent parent. If the foreign key check is deferred or if the constraint was added later, the data corruption is silent. Savepoints should be used for expected, recoverable failures (duplicate rows in a bulk load), not as a blanket error suppressor that hides bugs.

---

## Interview Angle

Common question forms:
- "What is a savepoint and when would you use one?"
- "How does PostgreSQL handle an error inside a transaction, and how do you recover without rolling back everything?"
- "How do ORMs implement nested transactions?"

Answer frame:
Define a savepoint as a named rollback point within an open transaction. Explain PostgreSQL's aborted transaction state: after any error, the transaction is in an aborted state and rejects all commands until `ROLLBACK` or `ROLLBACK TO SAVEPOINT`. Describe the batch insert use case: wrap each insert in a savepoint, roll back on failure, continue for the next row. Explain that `ROLLBACK TO SAVEPOINT` keeps the transaction alive and the savepoint intact. Connect to SQLAlchemy's `begin_nested()` as the ORM abstraction over savepoints. Clarify that `RELEASE SAVEPOINT` removes the marker but does not commit, and that `COMMIT` is still required at the outer transaction level.

---

## Related Notes

- [[transactions|Transactions]]
- [[acid-properties|ACID Properties]]
- [[deadlocks-sql|SQL Deadlocks]]
- [[sqlalchemy-async|SQLAlchemy Async]]
