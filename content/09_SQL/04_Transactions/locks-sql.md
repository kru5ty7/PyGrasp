---
title: 35 - Locking in SQL
description: Locks coordinate concurrent access to shared data by controlling which operations on the same rows or tables can proceed simultaneously.
tags: [sql, layer-9, locks, concurrency, transactions]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# Locking in SQL

> Locks prevent concurrent transactions from conflicting on the same data. In PostgreSQL, MVCC means readers never need locks at all — but writers must still coordinate with each other, and schema changes require the most exclusive locks of all.

---

## Quick Reference

**Core idea:**
- Row-level locks are acquired by `SELECT FOR UPDATE` and implicitly by `UPDATE` / `DELETE`
- Table-level locks range from ACCESS SHARE (SELECT) to ACCESS EXCLUSIVE (ALTER TABLE)
- PostgreSQL's MVCC means read queries never block and never acquire row locks
- `SELECT FOR UPDATE` acquires a row lock that blocks other `SELECT FOR UPDATE` on the same rows
- `SELECT FOR SHARE` acquires a shared row lock — multiple sessions can hold it simultaneously, but UPDATE is blocked
- Advisory locks provide application-level mutual exclusion using arbitrary integer keys

**Tricky points:**
- In PostgreSQL, readers never block writers and writers never block readers — only writer-writer conflicts require row locks
- `NOWAIT` and `SKIP LOCKED` on `SELECT FOR UPDATE` change blocking behavior significantly
- `ALTER TABLE` acquires ACCESS EXCLUSIVE — the most restrictive table lock, which blocks all reads and writes
- Lock waits are not the same as deadlocks; most production "lock issues" are long waits, not deadlock cycles
- `pg_locks` and `pg_stat_activity` are the diagnostic entry points for lock contention

---

## What It Is

Think of database locks as the bathroom key in a shared office. When someone takes the key (acquires a lock), no one else can use the bathroom until they return it (release the lock). The difference between a shared lock and an exclusive lock is like the difference between a reading room and a bathroom: a reading room can have many people inside simultaneously (shared), but the bathroom is for one person at a time (exclusive). PostgreSQL's locking system is more nuanced than this analogy — it has multiple modes with different compatibility rules — but the fundamental concept is the same: a lock is a signal that says "I am using this, coordinate with me before accessing it."

The defining feature of PostgreSQL's approach to locking is that ordinary reads require no locks at all. When you run a `SELECT` statement, PostgreSQL does not ask any rows to step aside. Instead, it uses MVCC (Multi-Version Concurrency Control) to read from a snapshot of committed data. Each row has internal metadata recording which transaction created it and which transaction deleted or replaced it. A `SELECT` statement checks these fields against its snapshot timestamp and sees exactly the rows that were committed as of the snapshot point. Because readers use a separate mechanism (snapshots) from writers (heap modifications), they never contend with each other. This is why PostgreSQL handles high read concurrency so efficiently.

Row-level locking becomes necessary when you need to reserve a row for exclusive modification. The canonical use case is the read-modify-write pattern: you read a value, compute a new value based on it, and write the result back. If two transactions do this simultaneously without coordination, both read the same original value, compute conflicting updates, and both commit — producing an incorrect final state. `SELECT FOR UPDATE` solves this by acquiring an exclusive row lock at read time, so the second transaction to arrive must wait until the first has committed or rolled back before it can even read the row.

Table-level locks exist on a spectrum from extremely permissive to completely exclusive. At the permissive end, ACCESS SHARE is held by ordinary `SELECT` statements — thousands of reads can proceed simultaneously. At the exclusive end, ACCESS EXCLUSIVE is held by `ALTER TABLE`, `DROP TABLE`, and similar DDL operations. ACCESS EXCLUSIVE conflicts with all other lock modes, including ACCESS SHARE — which means while an `ALTER TABLE` is waiting to acquire its lock, all subsequent `SELECT` statements on that table queue behind it. This is the mechanism behind the notorious production incident where a zero-downtime schema migration blocks all reads and brings an application to a standstill.

Advisory locks occupy a special category. They are not tied to any specific row or table; they are arbitrary locks identified by integer keys that your application assigns meaning to. PostgreSQL stores and manages them like regular locks (they appear in `pg_locks`, they are released when the session ends), but the database has no knowledge of what they protect. They are a coordination primitive for the application layer, useful for ensuring that a background job does not run in two processes simultaneously, or that an expensive computation is not duplicated across concurrent requests.

---

## How It Actually Works

Row-level locking is invoked with `SELECT FOR UPDATE` or `SELECT FOR SHARE`. `FOR UPDATE` acquires an exclusive row lock: the row cannot be modified or locked by another transaction until this one releases it.

```sql
BEGIN;
-- Lock the row for this transaction exclusively
SELECT * FROM orders WHERE id = 101 FOR UPDATE;
-- Now safely read-modify-write without risk of concurrent interference
UPDATE orders SET status = 'processing' WHERE id = 101;
COMMIT;
-- Lock is released when the transaction commits
```

A second transaction that tries `SELECT FOR UPDATE` on the same row will block until the first transaction ends. If waiting is unacceptable, `NOWAIT` raises an error immediately instead of waiting:

```sql
BEGIN;
SELECT * FROM orders WHERE id = 101 FOR UPDATE NOWAIT;
-- If row is already locked: ERROR: could not obtain lock on row in relation "orders"
COMMIT;
```

`SKIP LOCKED` is useful for work queue patterns: instead of blocking or erroring, it skips rows that are already locked and returns the next available one.

```sql
BEGIN;
-- Claim one available job from the queue without blocking on locked rows
SELECT * FROM jobs WHERE status = 'pending' LIMIT 1 FOR UPDATE SKIP LOCKED;
-- Process the job, then update status
UPDATE jobs SET status = 'processing' WHERE id = <returned_id>;
COMMIT;
```

Table-level locks and their compatibility determine what can run concurrently. The key modes to know are:

- `ACCESS SHARE`: held by `SELECT`. Compatible with everything except ACCESS EXCLUSIVE.
- `ROW EXCLUSIVE`: held by `INSERT`, `UPDATE`, `DELETE`. Compatible with ACCESS SHARE and ROW SHARE, but not with SHARE, SHARE ROW EXCLUSIVE, EXCLUSIVE, or ACCESS EXCLUSIVE.
- `SHARE`: held by `CREATE INDEX` (without CONCURRENTLY). Blocks writes but allows reads.
- `ACCESS EXCLUSIVE`: held by `ALTER TABLE`, `DROP TABLE`, `VACUUM FULL`, `REINDEX`. Blocks everything.

```sql
-- Check what locks are currently held and what is waiting
SELECT
    pid,
    relation::regclass,
    mode,
    granted,
    query
FROM pg_locks
JOIN pg_stat_activity USING (pid)
WHERE relation IS NOT NULL
ORDER BY granted DESC, pid;
```

Advisory locks are taken and released explicitly:

```sql
-- Acquire an exclusive advisory lock using an application-defined integer key
SELECT pg_advisory_lock(12345);
-- ... critical section ...
SELECT pg_advisory_unlock(12345);

-- Or use a transaction-scoped advisory lock (auto-released at COMMIT/ROLLBACK)
SELECT pg_advisory_xact_lock(12345);
```

`pg_try_advisory_lock` returns a boolean instead of blocking, allowing non-blocking mutual exclusion:

```sql
-- Returns true if lock was acquired, false if another session holds it
SELECT pg_try_advisory_lock(12345);
```

---

## How It Connects

Locking and transactions are inseparable: every lock acquired within a transaction is held until the transaction ends. Understanding how transactions begin and commit is necessary for reasoning about lock duration and contention.

[[transactions|Transactions]]

Deadlocks occur when two transactions each hold a lock the other needs. Understanding the locking model is a prerequisite for understanding how deadlocks form and how to prevent them.

[[deadlocks-sql|SQL Deadlocks]]

The isolation level a transaction operates under determines how aggressively locks are used. SERIALIZABLE uses Serializable Snapshot Isolation, which adds conflict tracking beyond standard row locks. READ COMMITTED relies purely on MVCC for read isolation, with row locks only for explicit `SELECT FOR UPDATE`.

[[isolation-levels|Isolation Levels]]

---

## Common Misconceptions

Misconception 1: "SELECT acquires a lock on the rows it reads, so long SELECT queries block writes."
Reality: In PostgreSQL, ordinary `SELECT` statements acquire no row locks. They read from MVCC snapshots and never block writes. `SELECT FOR UPDATE` acquires row locks, but plain `SELECT` does not. This is a fundamental difference from some other databases (such as SQL Server with default settings) where read locks are common.

Misconception 2: "Adding an index with CREATE INDEX will not disrupt production reads."
Reality: `CREATE INDEX` (without `CONCURRENTLY`) acquires a `SHARE` lock on the table, which blocks all `INSERT`, `UPDATE`, and `DELETE` operations for the duration of index construction. On large tables this can take minutes. `CREATE INDEX CONCURRENTLY` avoids this by using a weaker lock, but it takes longer and has other constraints (it cannot run inside a transaction block).

Misconception 3: "If a transaction is waiting for a lock, it will wait indefinitely until the lock is available."
Reality: By default, PostgreSQL lock waits are indefinite — there is no timeout. A long wait can appear indistinguishable from a deadlock to application operators. Setting `lock_timeout` at the session or transaction level prevents indefinite waits by aborting the waiting query after the specified duration. This is a recommended production practice.

```sql
-- Abort if a lock cannot be acquired within 5 seconds
SET lock_timeout = '5s';
```

---

## Why It Matters in Practice

Lock contention is one of the most common sources of production database performance problems, and most of the time it is caused by application code that holds transactions open while doing non-database work. Every millisecond a transaction is open, the locks it holds are unavailable to other transactions. An API endpoint that opens a transaction, makes an HTTP call to a third-party service, and then commits is holding database locks for the duration of the HTTP call — potentially several seconds. Any other transaction that needs the same rows is queued for that entire time.

Schema migrations are the second major source of lock-related outages. An `ALTER TABLE` to add a column, add an index without `CONCURRENTLY`, or change a column type acquires `ACCESS EXCLUSIVE` and blocks all reads. If a long-running transaction is already open on the table, the `ALTER TABLE` itself must wait — and while it waits, all subsequent reads queue behind it. The practical solution is to always run schema changes with `lock_timeout` set, use `CREATE INDEX CONCURRENTLY` for index additions, and run migrations at low-traffic times for large tables.

---

## What Breaks

**Long transaction holds locks during external API calls.** A payment processing endpoint opens a transaction, inserts a pending payment record, calls the payment gateway API (which takes 2-4 seconds under load), then updates the record with the result. The row lock acquired by the `INSERT` and `UPDATE` is held for the full duration of the HTTP call. Other requests to modify the same payment records are queued for up to 4 seconds. Under load, the queue grows faster than it drains, causing cascading timeouts.

**ALTER TABLE blocks all reads when a long transaction is open.** A deployment script runs `ALTER TABLE orders ADD COLUMN archived BOOLEAN DEFAULT FALSE`. A background reporting job has an open transaction on the `orders` table that runs for 5 minutes. The `ALTER TABLE` waits for the reporting job to finish. Meanwhile, every `SELECT` on `orders` queues behind the `ALTER TABLE`. The application effectively stops serving any order data for 5 minutes.

```sql
-- Safe migration pattern: set a lock timeout to fail fast rather than queue
SET lock_timeout = '2s';
ALTER TABLE orders ADD COLUMN archived BOOLEAN DEFAULT FALSE;
-- If this fails due to lock timeout, retry during a lower-traffic window
-- rather than causing a queue cascade
```

**Missing SKIP LOCKED in a job queue causes worker starvation.** A job processing system runs multiple worker processes that all query `SELECT * FROM jobs WHERE status = 'pending' LIMIT 1 FOR UPDATE`. Without `SKIP LOCKED`, all workers contend on the same row. One acquires the lock; the others block. When the lock releases, they all race again for the next row. Throughput is serialized to a single worker despite multiple processes running. `FOR UPDATE SKIP LOCKED` allows each worker to claim a distinct row without blocking on locked ones.

---

## Interview Angle

Common question forms:
- "How does PostgreSQL avoid read locks?"
- "What is SELECT FOR UPDATE and when would you use it?"
- "Why can an ALTER TABLE bring down a production application?"

Answer frame:
Explain MVCC as the mechanism that eliminates read locks: readers use snapshots, so they never contend with writers. Describe `SELECT FOR UPDATE` as the tool for read-modify-write patterns: it acquires a row lock so no other transaction can modify the row between the read and the write. Explain table-level lock modes from ACCESS SHARE to ACCESS EXCLUSIVE, emphasizing that `ALTER TABLE` acquires ACCESS EXCLUSIVE and blocks all reads. Mention `NOWAIT` and `SKIP LOCKED` as tools for non-blocking lock acquisition. Describe `pg_locks` as the diagnostic view for investigating lock contention.

---

## Related Notes

- [[transactions|Transactions]]
- [[isolation-levels|Isolation Levels]]
- [[deadlocks-sql|SQL Deadlocks]]
- [[acid-properties|ACID Properties]]
