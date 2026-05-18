---
title: ACID Properties
description: ACID is the four-property contract that defines what a reliable database transaction must guarantee — atomicity, consistency, isolation, and durability.
tags: [sql, layer-9, acid, transactions, consistency]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# ACID Properties

> ACID is the set of four guarantees — Atomicity, Consistency, Isolation, Durability — that define what a reliable database transaction must provide. Understanding each property tells you exactly what the database is protecting you from and what it cannot protect you from.

---

## Quick Reference

**Core idea:**
- Atomicity: all operations in a transaction succeed together or none take effect
- Consistency: a transaction moves the database from one valid state to another; constraints are never violated mid-transaction
- Isolation: concurrent transactions do not see each other's intermediate states
- Durability: once a transaction commits, the data survives crashes, restarts, and power loss
- PostgreSQL implements ACID using Write-Ahead Logging (WAL), MVCC, and constraint enforcement
- Strict ACID requires coordination mechanisms (locks, fsync) that cost performance

**Tricky points:**
- Consistency in ACID refers to database-level constraint enforcement, not application-level correctness — the database cannot know if your business logic is wrong
- Isolation is not binary; the standard defines four levels with different tradeoffs
- Durability requires `fsync` to be enabled — disabling it for performance trades durability for speed
- The C in ACID is often said to be the weakest property because it is partially delegated to the application

---

## What It Is

Think of ACID as the four promises a bank vault makes. The vault either takes all your cash in one sealed operation or none of it (atomicity). It only accepts deposits in valid denominations — counterfeit bills are rejected before the vault door closes (consistency). Your transaction with the vault is invisible to other customers until the door closes (isolation). Once the door closes and you have your receipt, the bank cannot later claim your deposit was lost (durability). These four promises together make the vault trustworthy. A database without ACID guarantees is a vault that might lose your money, accept invalid deposits, let other customers see your cash mid-transaction, or forget your deposit after a power outage.

Atomicity is the most intuitive property. A transaction is indivisible — it either commits completely or rolls back completely. There is no such thing as a half-committed transaction. The bank transfer example demonstrates this: debiting one account and crediting another must be a single atomic operation. If the debit succeeds but the credit fails, atomicity ensures the debit is also undone. PostgreSQL implements atomicity through its transaction log: every change is recorded in the Write-Ahead Log before being applied, and a rollback replays the log in reverse to undo the changes.

Consistency is subtler. It does not mean that the data is correct in a business sense — the database cannot know whether your business rules are sound. Consistency means that the database's own integrity constraints are enforced across the transaction boundary. Foreign keys, unique constraints, check constraints, and not-null constraints must all be satisfied at the moment of commit. A transaction that would leave the database in a state that violates any of these constraints is rejected entirely. Deferred constraints in PostgreSQL allow violations to exist mid-transaction as long as they are resolved by commit time.

Isolation defines how concurrent transactions interact with each other. A fully isolated set of transactions behaves as if they ran one after another in serial order, even if they actually ran simultaneously. In practice, full serialization is expensive, so databases offer weaker isolation levels that permit specific anomalies in exchange for better concurrency. The default in PostgreSQL is READ COMMITTED, which prevents dirty reads but allows non-repeatable reads. PostgreSQL's implementation of isolation uses Multi-Version Concurrency Control (MVCC): rather than locking rows for reads, the database maintains multiple versions of each row so that readers see a consistent snapshot without blocking writers.

Durability means that once you receive a commit confirmation, that data is permanent. It will survive a crash, a restart, or a power failure. PostgreSQL achieves durability by writing transaction records to the Write-Ahead Log and flushing the log to durable storage using `fsync` before acknowledging the commit to the client. The WAL ensures that even if the server crashes immediately after the commit acknowledgment, the data can be recovered during startup by replaying the WAL. Disabling `fsync` (a configuration option sometimes used in test environments or bulk-load scenarios) breaks durability: the database may acknowledge a commit that has not yet reached disk, and a crash can lose data.

---

## How It Actually Works

PostgreSQL's implementation of each ACID property is concrete and traceable. Understanding the mechanisms helps diagnose failures and tune configuration.

Atomicity is implemented via the transaction log and rollback segments. Every write operation is first recorded in the Write-Ahead Log at `pg_wal`. If a transaction rolls back, PostgreSQL uses the information in the WAL to undo changes. The WAL also enables crash recovery: on startup after a crash, PostgreSQL replays WAL records to restore the database to the last consistent committed state. This is why `ROLLBACK` in PostgreSQL is fast for many workloads — the actual heap pages may not have been written yet, and the rollback simply marks the transaction as aborted in the transaction status table (`pg_clog` / `pg_xact`).

```sql
-- Atomicity: both updates either commit together or both roll back
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- Only here does PostgreSQL write to WAL and confirm durability
```

Consistency enforcement happens at constraint check time. By default, PostgreSQL checks constraints immediately (per statement). Deferred constraints are only checked at `COMMIT`. This allows patterns like temporarily violating a foreign key within a transaction before restoring it.

```sql
-- Deferred constraints allow circular references to be resolved within a transaction
BEGIN;
SET CONSTRAINTS fk_parent DEFERRED;
INSERT INTO nodes (id, parent_id) VALUES (1, 2);  -- parent 2 does not exist yet
INSERT INTO nodes (id, parent_id) VALUES (2, 1);  -- now parent 1 exists
COMMIT;  -- constraint checked here — both nodes exist, so it passes
```

MVCC implements isolation without read locks. Every row has system columns `xmin` (the transaction ID that created it) and `xmax` (the transaction ID that deleted or updated it). When a transaction reads a row, it checks whether the row's `xmin` and `xmax` values indicate the row was committed and visible at the transaction's snapshot time. Writers create new row versions rather than modifying in place, so readers always see a consistent point-in-time snapshot without blocking.

```sql
-- READ COMMITTED: each statement sees data committed before the statement began
BEGIN;
SELECT balance FROM accounts WHERE id = 1;  -- sees snapshot at statement start
-- Another transaction commits a change to account 1 here
SELECT balance FROM accounts WHERE id = 1;  -- sees the new committed value
COMMIT;
```

Durability is controlled by the `synchronous_commit` configuration. The default (`on`) requires WAL to be flushed to disk before the commit is confirmed. Setting it to `off` improves write throughput but creates a window where a crash can lose the last few milliseconds of committed transactions. This is a deliberate tradeoff available for high-throughput, low-criticality workloads.

---

## How It Connects

ACID properties are the formal specification of what transactions guarantee. Every other concept in the concurrency section of SQL — isolation levels, locks, MVCC, savepoints — is either an implementation of one of the four properties or a tradeoff against them.

[[transactions|Transactions]]

The C in ACID (consistency) is sometimes contrasted with the BASE model used in distributed systems, which relaxes consistency in favor of availability and partition tolerance. Understanding ACID precisely is a prerequisite for reasoning about when BASE is an acceptable alternative.

[[acid-vs-base|ACID vs BASE]]

The isolation property in ACID is implemented through specific isolation levels. Choosing the right level requires understanding which anomalies each level prevents and which it permits.

[[isolation-levels|Isolation Levels]]

---

## Common Misconceptions

Misconception 1: "ACID guarantees that the data in my database is correct."
Reality: ACID guarantees that the database's structural constraints are enforced and that transactions execute reliably. It does not guarantee business logic correctness. A transaction that charges a customer the wrong amount, assigns an order to the wrong user, or calculates an incorrect total can commit successfully and satisfy all four ACID properties. Correctness of business logic is the application's responsibility.

Misconception 2: "Isolation means concurrent transactions never interfere with each other."
Reality: Full isolation (SERIALIZABLE) does prevent all interference, but it is not the default. PostgreSQL's default isolation level (READ COMMITTED) allows non-repeatable reads: a query run twice within the same transaction can return different results if another transaction committed between the two reads. Isolation is a spectrum, and weaker levels are explicitly designed to allow specific types of interference in exchange for better performance.

Misconception 3: "Durability is always guaranteed as long as the transaction committed successfully."
Reality: Durability depends on the `synchronous_commit` setting and, for replicated setups, whether standby servers have confirmed receipt of the WAL. In asynchronous replication, a committed transaction on the primary can be lost if the primary crashes before the WAL reaches any standby. The commit confirmation means the primary has written to disk, but it does not mean the data has been replicated.

---

## Why It Matters in Practice

ACID properties are the reason relational databases are the default choice for financial, healthcare, and order management systems. When money changes hands, when medical records are updated, or when inventory is decremented and an order is created simultaneously, the application needs the guarantee that partial writes cannot exist. ACID provides that guarantee at the database level so the application does not have to implement its own compensation logic.

The tradeoffs matter as much as the properties themselves. Every ACID guarantee costs something: atomicity requires rollback logging, consistency requires constraint checking at commit, isolation requires either locks or MVCC overhead, and durability requires `fsync`. Systems that process millions of writes per second — analytics pipelines, event ingestion systems, caches — often relax one or more of these guarantees deliberately, trading reliability for throughput. Knowing what each property costs is what allows you to make that tradeoff consciously rather than accidentally.

---

## What Breaks

**Disabling fsync for performance in production.** A team sets `fsync = off` in `postgresql.conf` to improve bulk insert throughput on a development-like staging environment. The configuration is copied to production. A power failure during a peak write period corrupts the data directory. PostgreSQL starts but reports inconsistent data because WAL records that were acknowledged as committed were never written to disk. The database must be restored from backup.

```sql
-- Detect fsync setting
SHOW fsync;  -- Should return 'on' in production; 'off' means durability is broken
```

**Relying on ACID consistency to enforce business rules the database does not know about.** An application deducts from an account balance, which passes the database-level check constraint (`balance >= 0`). However, the application has a business rule that accounts with a "frozen" status cannot be debited. The database has no such constraint. A transaction debits a frozen account, satisfies all ACID properties (no constraints are violated), and commits successfully. ACID consistency did not protect the application because the business rule was never encoded as a database constraint.

**Assuming READ COMMITTED isolation means a transaction sees a stable view of data.** A reporting job reads a summary total at the start of a transaction, then reads the individual rows that make up that total in a second query. Between the two queries, another transaction commits additional rows. The second query returns more rows than existed when the total was calculated. The numbers do not reconcile. This is a non-repeatable read, which READ COMMITTED explicitly permits. The fix is to use REPEATABLE READ or SERIALIZABLE for queries that require a consistent snapshot across multiple statements.

---

## Interview Angle

Common question forms:
- "What does ACID stand for and what does each letter mean?"
- "How does PostgreSQL implement durability?"
- "What is the difference between consistency in ACID and consistency in CAP theorem?"

Answer frame:
Define each property precisely. For atomicity: all-or-nothing, implemented via WAL and rollback. For consistency: constraint enforcement at commit, not application correctness. For isolation: controlled by isolation level, implemented via MVCC in PostgreSQL; the default (READ COMMITTED) allows non-repeatable reads. For durability: WAL flushed to disk via fsync before commit acknowledgment. Distinguish ACID consistency (structural constraint enforcement) from CAP consistency (all nodes see the same data). Mention that the properties have costs: strict ACID requires coordination that limits throughput, which is why NoSQL and BASE systems exist.

---

## Related Notes

- [[transactions|Transactions]]
- [[isolation-levels|Isolation Levels]]
- [[locks-sql|Locking in SQL]]
- [[acid-vs-base|ACID vs BASE]]
- [[savepoints|Savepoints]]
