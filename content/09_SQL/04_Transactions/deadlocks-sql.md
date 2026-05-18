---
title: SQL Deadlocks
description: A deadlock occurs when two transactions each hold a lock the other needs, creating a cycle that neither can break without external intervention.
tags: [sql, layer-9, deadlocks, locks, transactions]
status: draft
difficulty: advanced
layer: 9
domain: sql
created: 2026-05-18
---

# SQL Deadlocks

> A deadlock occurs when two transactions each hold a lock the other needs — both wait forever unless the database intervenes. PostgreSQL detects deadlocks automatically and kills one transaction, but the real work is writing code that prevents them from forming.

---

## Quick Reference

**Core idea:**
- A deadlock requires a cycle: A waits for B's lock, B waits for A's lock
- PostgreSQL detects deadlocks and aborts one transaction with error code 40P01
- The killed transaction receives `ERROR: deadlock detected` and must be retried by the application
- Prevention: always acquire locks in a consistent order across all transactions
- Most "deadlock" complaints in production are actually long-held lock waits, not true deadlocks
- `pg_locks` joined with `pg_stat_activity` reveals both waits and deadlock candidates

**Tricky points:**
- PostgreSQL's deadlock detection runs periodically (controlled by `deadlock_timeout`, default 1 second) — a deadlock is only detected after at least that long
- The database chooses the "victim" heuristically — usually the transaction that has done less work
- `lock_timeout` and `statement_timeout` prevent long waits but do not prevent deadlocks
- Row update order in a single `UPDATE ... WHERE` with multiple rows is not guaranteed — this can cause deadlocks between seemingly unrelated transactions
- Deadlocks are not a sign that the database is broken; they are a sign that the application acquires locks in inconsistent order

---

## What It Is

A deadlock is the classic resource-cycle problem. Imagine two people standing in a narrow hallway, each carrying something large. Person A needs to move forward but person B is blocking the path. Person B needs to move forward but person A is blocking. Neither can move because moving requires the other to move first. They wait indefinitely. A database deadlock is the same situation with locks instead of bodies: Transaction A holds a lock on row 1 and is waiting for a lock on row 2. Transaction B holds a lock on row 2 and is waiting for a lock on row 1. Neither transaction can proceed because it is waiting for a lock that the other transaction holds.

The critical insight about deadlocks is that they are entirely self-inflicted by the application's locking order. No database bug or hardware failure causes a deadlock. A deadlock happens because two transactions acquire locks on the same set of resources but in different sequences. If every transaction in the entire application always acquired locks in the same order — say, always in ascending order of row ID — a deadlock cycle could never form, because no transaction would ever hold a lock on a higher-numbered row while waiting for a lower-numbered row that another transaction holds.

PostgreSQL handles deadlocks automatically through its deadlock detection algorithm. The database periodically checks for lock wait cycles. When a transaction has been waiting for a lock longer than the `deadlock_timeout` setting (default: 1 second), PostgreSQL inspects the lock dependency graph to determine whether a cycle exists. If it finds one, it selects one transaction as the "victim" and aborts it with error code 40P01 and the message `deadlock detected`. The aborted transaction releases all its locks, which allows the other transaction to proceed. The victim transaction's work is entirely rolled back, and the application is responsible for catching the error and retrying the transaction.

The distinction between a deadlock and a long lock wait is important in practice, because operators often conflate them. A long lock wait occurs when Transaction A is waiting for a lock held by Transaction B, but Transaction B is not waiting for any lock A holds. There is no cycle; B is simply taking a long time to finish. This is not a deadlock — it is contention. The wait will eventually resolve when B commits or rolls back. Deadlocks are cyclic and permanent; lock waits are linear and temporary. The `pg_locks` view distinguishes them: if every waiting transaction forms a cycle back to itself through the dependency graph, it is a deadlock. If there are waiters but no cycle, it is contention.

---

## How It Actually Works

The classic deadlock scenario involves two transactions acquiring the same rows in opposite order.

```sql
-- Transaction A
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;  -- locks row 1
-- Transaction B runs here
UPDATE accounts SET balance = balance + 100 WHERE id = 2;  -- waits for row 2

-- Transaction B
BEGIN;
UPDATE accounts SET balance = balance - 200 WHERE id = 2;  -- locks row 2
UPDATE accounts SET balance = balance + 200 WHERE id = 1;  -- waits for row 1
-- DEADLOCK: A holds 1 and waits for 2; B holds 2 and waits for 1
-- PostgreSQL detects the cycle and aborts one of them with 40P01
```

PostgreSQL's deadlock error is specific and catchable. In Python with psycopg2:

```python
import psycopg2

try:
    cursor.execute("UPDATE accounts SET balance = balance - 100 WHERE id = 1")
    cursor.execute("UPDATE accounts SET balance = balance + 100 WHERE id = 2")
    conn.commit()
except psycopg2.errors.DeadlockDetected:  # error code 40P01
    conn.rollback()
    # retry the entire transaction
```

The prevention strategy is consistent lock ordering. If every transaction that touches both accounts always updates the lower-ID account first, the deadlock cycle cannot form.

```sql
-- Safe pattern: always acquire locks in ascending row ID order
BEGIN;
-- Determine which account has the lower ID and update it first
UPDATE accounts SET balance = balance - 100 WHERE id = LEAST(1, 2);
UPDATE accounts SET balance = balance + 100 WHERE id = GREATEST(1, 2);
COMMIT;
```

For cases where the order is determined dynamically (such as updating rows from a query result), `SELECT FOR UPDATE` with an `ORDER BY` clause locks rows in a predictable sequence:

```sql
BEGIN;
-- Lock all affected rows in a consistent order before updating
SELECT id FROM accounts WHERE id IN (1, 2) ORDER BY id FOR UPDATE;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

Implicit deadlocks from `UPDATE ... WHERE` can occur when multiple transactions update overlapping sets of rows. PostgreSQL does not guarantee the order in which rows are locked by a multi-row update. Two transactions that update partially overlapping sets of rows can deadlock even if the application code never explicitly mentions lock ordering.

```sql
-- Session A: updates rows 1, 2, 3 (internal lock order unspecified)
UPDATE orders SET status = 'shipped' WHERE status = 'pending' AND region = 'west';

-- Session B: updates rows 2, 3, 4 (internal lock order unspecified)
UPDATE orders SET status = 'cancelled' WHERE status = 'pending' AND region = 'central';
-- These two UPDATE statements can deadlock on the overlapping rows (2, 3)
```

The `pg_locks` view is the primary diagnostic tool for investigating both deadlocks and lock waits.

```sql
-- Find transactions that are waiting for locks
SELECT
    waiting.pid AS waiting_pid,
    waiting_activity.query AS waiting_query,
    blocking.pid AS blocking_pid,
    blocking_activity.query AS blocking_query,
    waiting.relation::regclass AS locked_table,
    waiting.mode AS requested_mode
FROM pg_locks AS waiting
JOIN pg_stat_activity AS waiting_activity ON waiting.pid = waiting_activity.pid
JOIN pg_locks AS blocking ON (
    waiting.relation = blocking.relation
    AND waiting.locktype = blocking.locktype
    AND blocking.granted = true
    AND waiting.granted = false
)
JOIN pg_stat_activity AS blocking_activity ON blocking.pid = blocking_activity.pid;
```

The `deadlock_timeout` setting controls how long PostgreSQL waits before running the deadlock detection algorithm. Lowering it (for example, to `500ms`) causes faster deadlock detection at the cost of slightly more CPU overhead from more frequent cycle checks.

---

## How It Connects

Deadlocks are a direct consequence of how transactions acquire and hold locks. Understanding the locking model — row-level locks, table-level locks, and MVCC — is the prerequisite for understanding why and when deadlock cycles form.

[[locks-sql|Locking in SQL]]

Deadlocks only occur inside transactions, because locks are held for the duration of the transaction. Short transactions reduce the window in which deadlocks can form, and understanding the transaction lifecycle is essential for reasoning about lock duration.

[[transactions|Transactions]]

Savepoints provide a mechanism to recover from a failed statement within a transaction without rolling back all the work. When a deadlock victim error (40P01) is raised inside a transaction, ROLLBACK TO SAVEPOINT allows selective retry of just the failed portion rather than the entire unit.

[[savepoints|Savepoints]]

---

## Common Misconceptions

Misconception 1: "The database should prevent deadlocks automatically — if I'm getting deadlocks, something is wrong with PostgreSQL."
Reality: PostgreSQL detects and resolves deadlocks automatically by aborting a victim transaction. Preventing deadlocks from forming is the application's responsibility, accomplished by ensuring consistent lock acquisition order. PostgreSQL cannot prevent a deadlock without knowing the application's intended semantics; it can only detect cycles after they have formed.

Misconception 2: "My application is getting lock errors — it must be a deadlock."
Reality: Most lock-related errors in production are lock waits that exceed a timeout (`lock_timeout` or `statement_timeout`), not true deadlocks. A deadlock requires a cycle in the lock dependency graph. A lock wait timeout occurs when one transaction simply cannot acquire a lock within the allowed time because another transaction is taking too long. The error messages are different: deadlocks produce error code 40P01, while lock timeouts produce 55P03.

Misconception 3: "Setting a low deadlock_timeout will make my application more stable by catching deadlocks faster."
Reality: A lower `deadlock_timeout` means the deadlock detection algorithm runs more frequently, which adds CPU overhead. More importantly, it changes the balance between "treating a slow lock wait as a potential deadlock" versus waiting for it to resolve naturally. Lowering it too much can cause false-positive deadlock detections on lock waits that would have resolved on their own. The default of 1 second is appropriate for most workloads.

Misconception 4: "I can prevent all deadlocks by using SELECT FOR UPDATE."
Reality: `SELECT FOR UPDATE` is a tool for acquiring row locks explicitly, which helps with consistent lock ordering when you use it carefully. But incorrect use of `SELECT FOR UPDATE` can itself cause deadlocks if different transactions acquire `FOR UPDATE` locks on the same rows in different orders. Using `SELECT FOR UPDATE` does not automatically prevent deadlocks — it requires applying the consistent lock ordering strategy.

---

## Why It Matters in Practice

Deadlocks are inevitable in any sufficiently complex application with concurrent write paths. They are not a sign of a bug that needs to be fixed once and forgotten — they are a class of failure mode that must be handled structurally. The application must catch 40P01 errors wherever multi-row write transactions occur and implement retry logic with backoff. Any code path that modifies multiple rows in a single transaction is a potential deadlock candidate.

The consistent lock ordering strategy is the most effective prevention measure, but it requires discipline across the entire codebase. In large teams, a new developer adding a feature that modifies two tables in a different order from existing code can introduce deadlocks that only manifest under concurrent load. Code review checklists and automated testing with concurrent sessions are the practical tools for catching this before it reaches production.

---

## What Breaks

**Classic deadlock from reverse lock acquisition order.** Two order processing jobs run concurrently. Job 1 updates order 100 then order 200. Job 2 updates order 200 then order 100. Under any concurrent execution, both jobs can each complete their first update and then deadlock on the second. PostgreSQL aborts one; if the application does not catch 40P01 and retry, the aborted job's work is lost and the operation fails permanently.

```sql
-- Job 1                                      -- Job 2
BEGIN;                                         BEGIN;
UPDATE orders SET status='done' WHERE id=100;  UPDATE orders SET status='done' WHERE id=200;
-- blocked waiting for id=200 --              -- blocked waiting for id=100 --
-- DEADLOCK -- PostgreSQL aborts one transaction
```

**Deadlock from implicit ordering in batch UPDATE.** A status-update job runs `UPDATE jobs SET status = 'done' WHERE id IN (5, 8, 12)` while a retry job runs `UPDATE jobs SET status = 'pending' WHERE id IN (8, 12, 15)`. The two queries share rows 8 and 12. The internal row scan order is not guaranteed to be the same for both queries. They can lock the shared rows in opposite orders and deadlock. The fix is to add `ORDER BY id` to the `WHERE` clause logic, but since `UPDATE` does not support `ORDER BY`, the standard approach is a CTE that selects the rows in order with `FOR UPDATE`:

```sql
WITH locked AS (
    SELECT id FROM jobs WHERE id IN (5, 8, 12) ORDER BY id FOR UPDATE
)
UPDATE jobs SET status = 'done' FROM locked WHERE jobs.id = locked.id;
```

**No retry logic causes permanent failure.** A payment service uses a transaction to update two account rows. Under load, deadlocks occur once every few hundred requests. The application does not catch 40P01 — it propagates as an unhandled 500 error. Payments randomly fail for a small percentage of users with no automatic recovery. The fix is a retry loop that catches 40P01 specifically and re-executes the transaction from `BEGIN`.

---

## Interview Angle

Common question forms:
- "What is a deadlock and how does PostgreSQL handle it?"
- "How do you prevent deadlocks in application code?"
- "What is the difference between a deadlock and a lock timeout?"

Answer frame:
Define a deadlock as a cycle in the lock dependency graph — A waits for B's lock, B waits for A's lock. Explain that PostgreSQL detects deadlocks after `deadlock_timeout` elapses and aborts the victim with error 40P01. The application must catch this error and retry the transaction. Explain the prevention strategy: always acquire locks in a consistent order (typically ascending row ID or alphabetical table order). Distinguish deadlocks (cycle, permanent) from lock waits (linear, temporary, resolved by the holder committing). Describe `pg_locks` as the diagnostic tool. Give the classic two-account transfer example to make the cycle concrete.

---

## Related Notes

- [[locks-sql|Locking in SQL]]
- [[transactions|Transactions]]
- [[isolation-levels|Isolation Levels]]
- [[savepoints|Savepoints]]
