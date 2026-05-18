---
title: 41 - Triggers
description: A trigger is a database callback that fires automatically when a specified event occurs on a table, enabling automatic auditing, validation, and derived data maintenance.
tags: [sql, layer-9, triggers, automation]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Triggers

> A trigger is the database's event listener — it fires silently and automatically when data changes, which makes it powerful and dangerous in equal measure.

---

## Quick Reference

**Core idea:**
- A trigger fires automatically on INSERT, UPDATE, DELETE, or TRUNCATE events on a table
- BEFORE triggers fire before the operation and can modify or cancel the row change
- AFTER triggers fire after the operation; the change has already been committed to the table
- Row-level triggers fire once per affected row; statement-level triggers fire once per SQL statement
- In PostgreSQL, triggers call a trigger function — the logic lives in a separate CREATE FUNCTION
- Common uses: audit logging, automatic timestamps, derived column maintenance, cross-table consistency

**Tricky points:**
- Triggers are invisible to application developers reading application code
- A trigger that fails raises an exception and rolls back the triggering statement
- BEFORE triggers can inspect and modify NEW (the incoming row) before it lands
- Triggers can cascade — a trigger can fire another trigger on a different table
- High-write tables with expensive triggers can have significant throughput reduction
- TRUNCATE does not fire row-level triggers, only statement-level ones

---

## What It Is

A trigger is like a motion sensor in a building's security system. You do not have to remember to log every time someone enters a room. The sensor notices the motion automatically and fires the alarm or records the event, regardless of who the person is or what door they used. The person walking through the door does not have to know the sensor exists. The behavior happens at the infrastructure level, not at the person level. That is exactly how a database trigger works: the event (a row change) is detected automatically, and a predefined response fires without any participation from the application that caused the event.

In PostgreSQL, a trigger is a two-part object. First, you write a trigger function using CREATE FUNCTION — this is a regular PL/pgSQL function that returns a special type called trigger. Inside this function, PostgreSQL gives you access to two special records: NEW contains the row that is being inserted or updated (the incoming values), and OLD contains the row as it existed before an update or delete. The function can read these records, modify NEW before it is written, raise an exception to cancel the operation, or perform any other SQL work. Second, you attach the function to a specific table event using CREATE TRIGGER, which specifies when the trigger fires (BEFORE or AFTER), which operation (INSERT, UPDATE, DELETE), and at what granularity (FOR EACH ROW or FOR EACH STATEMENT).

The BEFORE/AFTER distinction changes the trigger's capabilities fundamentally. A BEFORE trigger fires before the row change is applied to the table. This gives it the ability to modify the incoming row (by changing NEW) or cancel the entire operation (by returning NULL from the trigger function). This is the right place for automatic field computation — setting updated_at to NOW(), normalizing a value, or enforcing a business rule that the CHECK constraint cannot express. An AFTER trigger fires after the row is already written. The data is committed to the table at that point, so the trigger cannot change what was written. AFTER triggers are the right place for side effects like writing to an audit table or notifying an external system.

The hidden danger of triggers is precisely their invisibility. An application developer writes a simple UPDATE statement, runs it, and the row updates. But three triggers are now also running. One writes to an audit table. One updates a summary counter in another table. One sends a message to a notification queue. None of this is visible in the application code. When the UPDATE takes 200ms instead of 2ms, the developer profiles the UPDATE and finds it fast — but they do not see the trigger overhead. When data appears in unexpected places, the developer searches the application code and finds nothing. Triggers create behavior that exists only in the database schema, making the system harder to reason about holistically.

---

## How It Actually Works

Creating a trigger in PostgreSQL requires two steps: define the trigger function, then attach it to the table. The trigger function always returns trigger (the special type), and it must return either NEW (to proceed with the operation, possibly modified), OLD (for delete triggers), or NULL (to cancel the operation in a BEFORE trigger).

```sql
-- Step 1: Create the trigger function
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;  -- must return NEW to allow the operation to proceed
END;
$$;

-- Step 2: Attach the trigger to a table
CREATE TRIGGER trg_set_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();
```

Now every UPDATE on orders automatically sets updated_at to the current timestamp, regardless of whether the application included that column in the SET clause. The application does not need to remember to set it.

Audit logging with an AFTER trigger demonstrates a different pattern — writing to a separate table after the fact:

```sql
CREATE TABLE order_audit_log (
    id          BIGSERIAL PRIMARY KEY,
    order_id    INT NOT NULL,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    changed_by  TEXT NOT NULL DEFAULT current_user,
    old_status  TEXT,
    new_status  TEXT
);

CREATE OR REPLACE FUNCTION log_order_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO order_audit_log (order_id, old_status, new_status)
        VALUES (NEW.id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_order_status_audit
AFTER UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION log_order_status_change();
```

The IS DISTINCT FROM comparison handles NULL correctly — unlike != which returns NULL when either side is NULL, IS DISTINCT FROM returns true when values differ including when one is NULL. This is important for nullable columns.

Statement-level triggers are less common but worth understanding. A FOR EACH STATEMENT trigger fires once per SQL statement, not once per row. It does not have access to NEW and OLD (because there is no single row to inspect). It is useful for coarse-grained auditing (log that an UPDATE occurred on a table, not which rows changed) or for operations like invalidating a cache after any modification to a table.

```sql
-- Statement-level: fires once per UPDATE statement, regardless of rows affected
CREATE TRIGGER trg_invalidate_cache
AFTER UPDATE ON products
FOR EACH STATEMENT
EXECUTE FUNCTION notify_cache_invalidation();
```

---

## How It Connects

Triggers execute inside the same transaction as the triggering statement. If the trigger function raises an exception, the entire transaction is rolled back — including the original statement that fired the trigger. This tight coupling between triggers and transactions is why understanding ACID properties and transaction boundaries is essential before working with triggers on production tables.

Stored procedures and triggers share the same procedural language (PL/pgSQL) and the same DECLARE/BEGIN/EXCEPTION syntax. The difference is that triggers are called by the database engine implicitly, while stored procedures are called explicitly by application code or a CALL statement.

[[transactions|Transactions]]
[[acid-properties|ACID Properties]]
[[stored-procedures|Stored Procedures]]
[[dml|DML]]

---

## Common Misconceptions

Misconception 1: "Triggers are the right way to enforce referential integrity between tables."
Reality: Foreign key constraints enforced by the database are the right tool for referential integrity. They are faster, declared at the schema level, and automatically maintained by the engine. Triggers that manually check foreign key integrity are reinventing what the database already provides, and they are prone to race conditions under concurrent writes that foreign key constraints handle correctly.

Misconception 2: "BEFORE triggers prevent invalid data from entering the database."
Reality: A BEFORE trigger fires as part of the same transaction as the INSERT or UPDATE. If the trigger function does not return NULL and does not raise an exception, the operation proceeds. The trigger can modify the incoming row, but if it does nothing, the data is written as-is. Constraint validation (NOT NULL, CHECK, UNIQUE, FOREIGN KEY) is separate from trigger logic and runs at constraint-check time, not at trigger time. Triggers are not a replacement for constraints.

Misconception 3: "Triggers are free — they do not affect INSERT/UPDATE performance."
Reality: Every row-level trigger adds overhead to every matching DML operation. On a table that receives 10,000 inserts per second, a trigger that writes to an audit table means 10,000 additional inserts per second into the audit table within the same transactions. This doubles the write load on that pathway. Triggers on high-write tables must be profiled under realistic load.

---

## Why It Matters in Practice

Triggers are the standard mechanism for automatic timestamps in databases where the application cannot be trusted to set them consistently. The pattern of a BEFORE UPDATE trigger setting updated_at = NOW() is so common that many teams create a single trigger function and attach it to dozens of tables. It is reliable, DRY, and requires no application-level participation.

Audit logging via AFTER triggers is similarly common in regulated industries — finance, healthcare, e-commerce with dispute resolution requirements. The audit requirement is: every change to certain tables must be recorded with who changed it, when, and what changed. Putting this in a trigger ensures no application path can bypass the audit, including direct database access by administrators or scripts. The trigger fires regardless of the client.

---

## What Breaks

**Trigger cascade causing unexpected data modifications.** Table A has a trigger that updates table B. Table B has a trigger that updates table C. A developer updates table A, not knowing about the cascade. The UPDATE on A takes 500ms and locks rows in tables B and C that unrelated queries are waiting on. The cascading behavior is invisible in application code and very hard to debug without knowing the trigger chain.

**Trigger on a high-write table creating a write bottleneck.** An e-commerce platform adds an AFTER INSERT trigger on the events table (which receives millions of rows per hour) to write a denormalized summary. Each INSERT now requires two writes within the same transaction. Throughput drops. The trigger was added during a slow traffic period and the performance impact was not caught until a traffic spike.

```sql
-- Checking for triggers on a table (PostgreSQL)
SELECT trigger_name, event_manipulation, action_timing, action_orientation
FROM information_schema.triggers
WHERE event_object_table = 'orders'
ORDER BY trigger_name;
```

**Trigger failure rolling back unrelated work.** A BEFORE INSERT trigger on the users table sends a welcome email via a pg_notify call. The notify fails because of a configuration issue. The INSERT is rolled back. New user registrations fail silently until the trigger bug is found. Any trigger that communicates with an external system creates a dependency that can break core database operations.

---

## Interview Angle

Common question forms:
- "What is a database trigger and when would you use one?"
- "What is the difference between a BEFORE and AFTER trigger?"
- "What are the risks of overusing triggers?"

Answer frame:
Define the trigger as an automatic callback on INSERT/UPDATE/DELETE. Distinguish BEFORE (can modify or cancel the row) from AFTER (side effects, original change already written). Give two concrete use cases: automatic timestamps and audit logging. Then address the risks directly: invisibility to application developers, performance overhead on high-write tables, and cascade complexity. Show awareness that triggers should be used deliberately and documented, not used as a default tool for any cross-table logic.

---

## Related Notes

- [[stored-procedures|Stored Procedures]]
- [[transactions|Transactions]]
- [[acid-properties|ACID Properties]]
- [[dml|DML]]
- [[views|Views]]
