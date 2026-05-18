---
title: 34 - Isolation Levels
description: Isolation levels define which concurrency anomalies a transaction is protected from and which it permits, trading correctness guarantees for throughput.
tags: [sql, layer-9, isolation, transactions, concurrency]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# Isolation Levels

> Isolation levels define how concurrent transactions interact with each other. Choosing the right level means knowing which anomalies your application can tolerate and which it cannot — the wrong choice produces silent data corruption, and the right choice costs exactly as much coordination as necessary.

---

## Quick Reference

**Core idea:**
- Four standard levels: READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE
- PostgreSQL does not implement READ UNCOMMITTED — it is treated as READ COMMITTED
- READ COMMITTED is PostgreSQL's default: each statement sees only committed data as of statement start
- REPEATABLE READ: each statement sees a snapshot taken at transaction start — same query always returns the same rows
- SERIALIZABLE: full isolation, transactions appear to execute one at a time
- The phenomena levels prevent: dirty reads, non-repeatable reads, phantom reads, serialization anomalies
- PostgreSQL implements isolation via MVCC — readers never block writers

**Tricky points:**
- READ COMMITTED does not mean a transaction sees a stable view of data — each statement gets a fresh snapshot
- REPEATABLE READ in PostgreSQL prevents phantom reads (stronger than the SQL standard requires)
- SERIALIZABLE uses Serializable Snapshot Isolation (SSI), not traditional locking — it detects conflicts and aborts one transaction rather than blocking
- Raising the isolation level can cause serialization failures (error 40001) that the application must retry
- Most applications need READ COMMITTED; financial double-entry or inventory reservation typically needs SERIALIZABLE

---

## What It Is

Isolation levels are the volume knob on database concurrency. Turn it all the way down (READ UNCOMMITTED) and transactions can see each other's uncommitted writes — maximum throughput, zero safety. Turn it all the way up (SERIALIZABLE) and the database guarantees that concurrent transactions produce results identical to some sequential ordering of those transactions — full safety, maximum coordination overhead. The levels in between are carefully defined stopping points that prevent specific categories of anomalies while permitting others. The SQL standard names four levels and three anomalies; choosing a level means choosing which anomalies you are willing to accept.

The three classic anomalies are defined by what a transaction can observe about other concurrent transactions. A dirty read occurs when Transaction A reads data written but not yet committed by Transaction B. If Transaction B later rolls back, Transaction A has made decisions based on data that never existed. A non-repeatable read occurs when Transaction A reads a row, Transaction B commits an update to that row, and Transaction A reads the same row again and gets a different value. A phantom read occurs when Transaction A queries a range of rows, Transaction B inserts a new row that matches that range and commits, and Transaction A re-queries the range and finds a new row that was not there before. Each successive anomaly requires more coordination to prevent.

PostgreSQL's implementation differs from the SQL standard in one important way: it treats READ UNCOMMITTED as READ COMMITTED because its MVCC architecture makes dirty reads structurally impossible. MVCC (Multi-Version Concurrency Control) maintains multiple historical versions of each row. Every transaction reads a snapshot of the database as it existed at a specific point in time. Since MVCC readers always read from snapshots of committed data, there is no mechanism for a reader to see an uncommitted write from another transaction. This means PostgreSQL's weakest isolation level still prevents dirty reads.

At READ COMMITTED, the snapshot point is per statement: each SQL statement in the transaction sees all data that was committed before that statement began. This is correct and safe for most single-statement operations, but it means that within a long transaction, two identical `SELECT` statements can return different results if another transaction committed changes between them. The transaction does not see a frozen view of the world; it sees the world as it was at the moment each individual statement ran.

At REPEATABLE READ, the snapshot point is per transaction: the snapshot is taken when the first statement of the transaction runs, and every subsequent statement in that transaction sees the same snapshot. A row read once will return the same value every time it is read within the transaction, regardless of what other transactions commit in the meantime. PostgreSQL's implementation of REPEATABLE READ also prevents phantom reads — a stronger guarantee than the SQL standard requires at this level — because MVCC snapshots capture the entire state of the database at transaction start, including which rows exist.

SERIALIZABLE is the strongest level. It guarantees that the outcome of concurrent transactions is equivalent to some serial execution order. PostgreSQL implements this using Serializable Snapshot Isolation (SSI), a technique that tracks read/write dependencies between concurrent transactions. When SSI detects a dependency cycle that would produce a non-serializable outcome, it aborts one of the transactions with error code 40001 (`ERROR: could not serialize access due to concurrent update`). The aborted transaction must be retried by the application. SSI is notably less blocking than the traditional approach of acquiring predicate locks for every read, which makes PostgreSQL's SERIALIZABLE practical for many real workloads.

---

## How It Actually Works

Setting the isolation level applies to the current transaction. The default level is READ COMMITTED and applies unless explicitly changed.

```sql
-- Set isolation level for the current transaction
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- or
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- or
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

You can also set the session default:

```sql
SET default_transaction_isolation = 'repeatable read';
```

The following example demonstrates the non-repeatable read that READ COMMITTED permits. Two queries run in the same transaction. Between them, another session commits an update.

```sql
-- Session 1 (READ COMMITTED, the default)
BEGIN;
SELECT balance FROM accounts WHERE id = 1;
-- Returns: 1000

-- Session 2 (commits while Session 1 is open)
BEGIN;
UPDATE accounts SET balance = 900 WHERE id = 1;
COMMIT;

-- Session 1 continues — sees the NEW committed value
SELECT balance FROM accounts WHERE id = 1;
-- Returns: 900 (not 1000)
COMMIT;
```

With REPEATABLE READ, Session 1 would return 1000 for both queries because its snapshot was taken at transaction start and does not change.

The phantom read scenario illustrates why REPEATABLE READ is useful for reporting. Without it, a report that queries data in multiple steps can produce internally inconsistent results.

```sql
-- Session 1 (REPEATABLE READ)
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT COUNT(*) FROM orders WHERE status = 'pending';  -- Returns 50
-- Session 2 inserts a new pending order and commits here
SELECT SUM(total) FROM orders WHERE status = 'pending';
-- Still sees 50 orders — the new one is not visible because snapshot was taken at BEGIN
COMMIT;
```

SERIALIZABLE transactions that conflict are aborted with error 40001. The application must handle this:

```sql
-- This pattern is required for SERIALIZABLE workloads
-- Retry loop pseudocode (in Python):
-- while True:
--     try:
--         BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
--         ... business logic ...
--         COMMIT;
--         break
--     except SerializationFailure:
--         ROLLBACK;
--         continue
```

A practical example where SERIALIZABLE is necessary: a double-entry bookkeeping system that reads an account balance to decide whether a debit is permitted, then writes the debit. Under READ COMMITTED, two concurrent transactions can both read the same balance, both decide the debit is allowed, and both commit — resulting in an overdraft. Under SERIALIZABLE, SSI detects the read/write dependency cycle and aborts one transaction.

```sql
-- SERIALIZABLE prevents the concurrent overdraft problem
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT balance FROM accounts WHERE id = 1;  -- 100
-- Concurrent session also reads 100 and is about to debit 80
-- SERIALIZABLE: one of these transactions will be aborted with 40001
UPDATE accounts SET balance = balance - 80 WHERE id = 1;
COMMIT;
```

---

## How It Connects

Isolation levels are one of the four ACID properties (the I). Understanding what each level protects and costs requires knowing the full ACID contract first.

[[acid-properties|ACID Properties]]

The mechanics of how PostgreSQL enforces isolation — MVCC, row versioning, snapshot timestamps — are the same mechanisms that make locking in PostgreSQL unique compared to other databases. MVCC means that in PostgreSQL, readers never block writers and writers never block readers, unlike lock-based isolation in other systems.

[[locks-sql|Locking in SQL]]

Applications that use ORMs like SQLAlchemy often set isolation levels at the connection or session level. Understanding the mapping between SQLAlchemy's isolation configuration and PostgreSQL's behavior is essential for async database code.

[[sqlalchemy-async|SQLAlchemy Async]]

---

## Common Misconceptions

Misconception 1: "READ COMMITTED means my transaction sees a consistent snapshot of the database."
Reality: READ COMMITTED means each statement sees a snapshot taken at statement start, not transaction start. A long transaction running multiple queries at READ COMMITTED will see different versions of the data as other transactions commit between its statements. For a consistent view across multiple statements, REPEATABLE READ is required.

Misconception 2: "REPEATABLE READ only prevents repeatable reads, not phantoms — I need SERIALIZABLE to prevent phantom rows from appearing."
Reality: The SQL standard says REPEATABLE READ can still allow phantom reads, but PostgreSQL's MVCC implementation prevents phantoms at REPEATABLE READ as well. A transaction at REPEATABLE READ in PostgreSQL sees a snapshot of the entire database taken at transaction start, including which rows exist, so new rows inserted by other transactions are invisible for the duration of the transaction.

Misconception 3: "SERIALIZABLE is too expensive to use in production."
Reality: PostgreSQL's Serializable Snapshot Isolation is considerably more efficient than the older predicate-locking approach used in some other databases. It adds overhead compared to READ COMMITTED, but for workloads that genuinely require serializable correctness (financial transfers, inventory reservation), the alternative is application-level retry logic or distributed locks, both of which are more complex and potentially slower. The key operational requirement is that applications must handle 40001 serialization failure errors and retry transactions.

Misconception 4: "Choosing a higher isolation level always prevents bugs — I should just use SERIALIZABLE everywhere."
Reality: Higher isolation levels cause more transaction aborts and require application-level retry logic. A system that uses SERIALIZABLE everywhere but does not implement retry logic will fail with 40001 errors under concurrency. The correct approach is to use the lowest isolation level that is safe for each specific workload.

---

## Why It Matters in Practice

For most CRUD web applications — user registrations, content management, settings updates — READ COMMITTED is sufficient. Each operation is a single statement or a short transaction that does not depend on a stable view of data across multiple reads. The default PostgreSQL isolation level handles these workloads correctly without any explicit configuration.

The choice becomes critical in two categories of application. First, any system that reads a value, makes a decision based on it, and writes a new value (read-modify-write) is vulnerable to race conditions under READ COMMITTED if two transactions do this concurrently. Inventory reservation, balance checks before debits, and unique username assignment all have this shape. SERIALIZABLE or explicit row locking with `SELECT FOR UPDATE` is required. Second, any reporting or auditing transaction that must see a consistent snapshot across multiple queries needs at minimum REPEATABLE READ, otherwise the report can reflect a mix of before and after states from concurrent transactions.

---

## What Breaks

**Oversell in an inventory system under READ COMMITTED.** Two concurrent orders both check available stock, both see 1 unit available, both proceed to create an order and decrement the stock. Both transactions commit. The stock goes to -1. The correct fix is either `SELECT FOR UPDATE` on the stock row (serializes access at the row level) or SERIALIZABLE isolation with retry logic.

```sql
-- Session 1 and Session 2 both run this concurrently under READ COMMITTED:
BEGIN;
SELECT quantity FROM inventory WHERE product_id = 42;  -- Both see: 1
-- Both decide quantity > 0, proceed to place order
UPDATE inventory SET quantity = quantity - 1 WHERE product_id = 42;
COMMIT;
-- Both commit: quantity ends at -1
```

**Report totals that do not reconcile.** An end-of-day report runs two queries in the same READ COMMITTED transaction: first summing debits, then summing credits. A batch of new transactions commits between the two queries. The debit sum includes some transactions the credit sum does not. The balance appears out of sync by exactly the amount of the new batch. Running the report at REPEATABLE READ gives each query the same snapshot, making the totals internally consistent.

**Infinite retry loop from unhandled serialization failures.** An application upgrades to SERIALIZABLE isolation to fix a race condition. Under load, transactions begin receiving 40001 errors. The application does not handle this error, so it propagates as an unhandled exception. The calling service retries the entire HTTP request, which creates a new database connection but still fails with 40001 because the underlying contention has not changed. The correct fix is to implement a retry loop within the database transaction itself, specifically catching error code 40001 and retrying the transaction from `BEGIN`.

---

## Interview Angle

Common question forms:
- "What are the four SQL isolation levels and what anomalies does each prevent?"
- "What is the difference between REPEATABLE READ and SERIALIZABLE?"
- "How does PostgreSQL implement isolation without traditional read locks?"

Answer frame:
Name all four levels and the three anomalies (dirty read, non-repeatable read, phantom read). Explain that PostgreSQL does not support READ UNCOMMITTED. Describe READ COMMITTED as the default (per-statement snapshot). Explain REPEATABLE READ as per-transaction snapshot, noting that PostgreSQL also prevents phantoms at this level. Explain SERIALIZABLE as full serial equivalence using SSI, and that it requires application retry logic for 40001 errors. Explain that PostgreSQL uses MVCC so readers never block writers at any isolation level. Give the inventory or financial example to show when you need something above READ COMMITTED.

---

## Related Notes

- [[acid-properties|ACID Properties]]
- [[transactions|Transactions]]
- [[locks-sql|Locking in SQL]]
- [[deadlocks-sql|SQL Deadlocks]]
- [[savepoints|Savepoints]]
