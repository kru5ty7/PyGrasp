---
title: 32 - Transactions
description: A transaction groups multiple SQL operations into a single all-or-nothing unit of work, guaranteeing that partial failures leave no trace.
tags: [sql, layer-9, transactions, acid]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Transactions

> A transaction is a sequence of SQL operations that execute as a single unit — either every operation succeeds and the changes are committed, or every operation is rolled back as if nothing happened. Without transactions, partial failures corrupt your data silently.

---

## Quick Reference

**Core idea:**
- A transaction begins with `BEGIN` and ends with either `COMMIT` or `ROLLBACK`
- All changes inside a transaction are invisible to other sessions until `COMMIT`
- `ROLLBACK` undoes every change made since `BEGIN`
- Autocommit mode wraps each statement in its own transaction automatically
- Savepoints allow partial rollback within a transaction without aborting the whole unit
- Long-running transactions hold locks and delay replication, so they should be kept short

**Tricky points:**
- DDL statements (`ALTER TABLE`, `CREATE INDEX`) inside a transaction are rolled back if the transaction fails — PostgreSQL supports transactional DDL, MySQL does not
- In autocommit mode, a single `DELETE FROM orders` with no `WHERE` clause commits immediately and is unrecoverable
- PostgreSQL enters an error state after any failed statement inside a transaction — you must `ROLLBACK` before issuing new commands
- Nested transactions are not natively supported, but savepoints provide equivalent behavior

---

## What It Is

Think of a transaction as a sealed envelope. You write everything you want to send inside the envelope before you seal it. While the envelope is open, no one else can read what is inside. Only when you seal it (commit) does the contents become visible to the rest of the world. If you change your mind before sealing, you tear up the envelope and nothing was ever sent. The database works exactly this way: your writes are invisible until commit, and rollback makes them vanish entirely.

The canonical illustration is a bank transfer. Alice wants to send Bob $100. This requires two operations: deduct $100 from Alice's account and add $100 to Bob's account. If the deduction succeeds but the credit fails — say, the server crashes between the two statements — Alice has lost $100 and Bob received nothing. The database is now in an impossible state: money has disappeared. A transaction prevents this by ensuring both operations succeed together or neither takes effect.

Without transactions, every multi-step write is a potential corruption waiting to happen. Web applications routinely perform several related inserts and updates that must all succeed together: creating an order, decrementing inventory, charging the customer, and sending a confirmation. If any step fails mid-sequence, the partial state left behind can trigger downstream errors that are far harder to diagnose than the original failure. Transactions make the error surface clean and predictable.

Transactions also define a visibility boundary for other concurrent sessions. While your transaction is open, no other session sees your uncommitted changes. This means you can read your own writes within the transaction, make decisions based on what you have written, and then commit — all without other sessions observing an intermediate state. This property is isolation, and it is one of the four guarantees that make up ACID.

---

## How It Actually Works

The simplest explicit transaction uses three keywords. `BEGIN` opens the transaction, your statements follow, and `COMMIT` or `ROLLBACK` closes it.

```sql
BEGIN;

UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;

COMMIT;
```

If the second `UPDATE` fails for any reason, issuing `ROLLBACK` instead of `COMMIT` restores both accounts to their original state. Nothing in between ever happened.

PostgreSQL operates in autocommit mode by default when using `psql` or most drivers. In autocommit mode, each statement is automatically wrapped in its own `BEGIN` and `COMMIT`. This is convenient for single statements but dangerous for multi-step operations. The following pattern is a production accident waiting to happen when executed in autocommit mode:

```sql
-- In autocommit mode, each line commits independently.
-- A crash between them leaves the database in a broken state.
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
```

Implicit transactions exist in some database drivers: the driver opens a transaction automatically when you execute the first statement and does not commit until you explicitly call `connection.commit()`. Python's `psycopg2` works this way by default. This means that if you forget to call `commit()`, every insert you made in that session is silently discarded when the connection closes.

PostgreSQL's error state behavior is an important operational detail. Once any statement inside a transaction produces an error, PostgreSQL marks the transaction as aborted and rejects every subsequent command with `ERROR: current transaction is aborted, commands ignored until end of transaction block`. The only valid commands at that point are `ROLLBACK` or `ROLLBACK TO SAVEPOINT`. This protects against the subtle bug of continuing to issue statements after a failure, believing they are taking effect.

Long-running transactions cause two classes of production problems. First, they hold row locks acquired by `SELECT FOR UPDATE` or `UPDATE` statements, which blocks other transactions that need the same rows. Second, in PostgreSQL's replication model, long-running transactions on the primary can cause replication slots to retain WAL files indefinitely, eventually filling the disk. The practical rule is that transactions should be as short as possible: open late, close early.

---

## How It Connects

Understanding transactions is the foundation for everything in the concurrency and reliability section of SQL. The four guarantees that transactions provide are formalized as ACID properties — atomicity, consistency, isolation, and durability — each of which has specific implementation mechanisms in PostgreSQL.

[[acid-properties|ACID Properties]]

The strength of isolation a transaction provides is controlled by the isolation level. PostgreSQL's default (READ COMMITTED) is appropriate for most workloads, but financial systems typically require SERIALIZABLE.

[[isolation-levels|Isolation Levels]]

When multiple transactions run concurrently and need the same rows, the database must coordinate access through a locking mechanism. Understanding how locks interact with transactions is essential for diagnosing contention and deadlocks.

[[locks-sql|Locking in SQL]]

---

## Common Misconceptions

Misconception 1: "Autocommit is safe because the database handles committing automatically."
Reality: Autocommit commits each statement individually. Any multi-step operation — a transfer, an order creation, a status update that must stay in sync with a log entry — is not atomic under autocommit. A failure between statements leaves the database in a partial state that is impossible to distinguish from a valid state without domain knowledge.

Misconception 2: "Rolling back a transaction undoes everything, including things like sequence increments and external side effects."
Reality: `ROLLBACK` undoes data changes within the transaction, but sequences in PostgreSQL advance without being rolled back. If your transaction increments a sequence (via `SERIAL` or `NEXTVAL`) and then rolls back, the sequence value is not reclaimed. More critically, `ROLLBACK` cannot undo external side effects: emails sent, API calls made, or files written during the transaction are not reversed by a database rollback.

Misconception 3: "A transaction that finishes without an explicit COMMIT or ROLLBACK is safely committed."
Reality: An implicit or explicit connection close without a `COMMIT` rolls back the transaction. In PostgreSQL, an open transaction that loses its connection is automatically rolled back. In some ORM configurations, forgetting to call `commit()` silently discards hours of writes.

---

## Why It Matters in Practice

Every application that writes to a relational database depends on transactions, whether the developer is aware of it or not. Order management, financial ledgers, inventory systems, and user account operations all involve multiple related writes that must succeed together. The moment you have two or more statements that must be atomic, you need an explicit transaction.

The failure cases that transactions prevent are among the most damaging in production: partial writes that create inconsistent data, double-charges on payment failures, and inventory counts that drift out of sync with order records. These bugs often do not manifest immediately — the data looks correct until a report runs or a reconciliation check fails weeks later. Wrapping multi-step writes in explicit transactions is one of the cheapest reliability improvements available to any application developer.

---

## What Breaks

**Bank transfer without a transaction.** A payment service runs two updates in autocommit mode. The debit succeeds. The credit fails due to a database constraint on the recipient's account. The sender loses money and the recipient receives nothing. There is no way to automatically detect or repair this inconsistency after the fact.

```sql
-- Dangerous: each statement is its own transaction in autocommit mode
UPDATE accounts SET balance = balance - 500 WHERE user_id = 42;
-- Server crash here leaves balance deducted with no credit applied
UPDATE accounts SET balance = balance + 500 WHERE user_id = 99;
```

**Continuing after a failed statement.** A transaction attempts an insert that violates a unique constraint. The application catches the exception, logs it, and continues with more inserts inside the same transaction, assuming they succeed. PostgreSQL has aborted the transaction and is ignoring all subsequent statements silently (or raising `InFailedSqlTransaction`). The application commits and finds no rows were inserted.

```sql
BEGIN;
INSERT INTO orders (id, total) VALUES (1001, 99.99);  -- Succeeds
INSERT INTO orders (id, total) VALUES (1001, 49.99);  -- Fails: duplicate key
-- PostgreSQL is now in aborted state; this INSERT is silently ignored
INSERT INTO orders (id, total) VALUES (1002, 29.99);
COMMIT;  -- Commits nothing
```

**Long-running transaction blocking a schema migration.** A background job opens a transaction to process a large batch of rows and leaves it open for thirty minutes. A deployment script runs `ALTER TABLE` to add a column, which requires an `ACCESS EXCLUSIVE` lock. The `ALTER TABLE` waits behind the open transaction. All subsequent `SELECT` statements on that table queue behind the `ALTER TABLE`, causing a full application stall until either the background transaction commits or times out.

---

## Interview Angle

Common question forms:
- "Why do we need transactions? Can you walk me through a concrete example?"
- "What happens if a transaction is never committed or rolled back?"
- "What is the difference between implicit and explicit transactions?"

Answer frame:
Start with the bank transfer example to establish why atomicity matters. Define BEGIN, COMMIT, and ROLLBACK. Explain autocommit mode and its risks. Mention that PostgreSQL enters an error state after any failed statement, requiring ROLLBACK before proceeding. Discuss long-running transactions and their impact on locking and replication. Connect to ACID properties and isolation levels as the formal specification of what transactions guarantee.

---

## Related Notes

- [[acid-properties|ACID Properties]]
- [[isolation-levels|Isolation Levels]]
- [[locks-sql|Locking in SQL]]
- [[savepoints|Savepoints]]
- [[deadlocks-sql|SQL Deadlocks]]
