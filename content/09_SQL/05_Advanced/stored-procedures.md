---
title: 40 - Stored Procedures
description: A stored procedure is a named, reusable block of SQL and procedural logic saved inside the database and callable by name.
tags: [sql, layer-9, stored-procedures, plpgsql]
status: draft
difficulty: intermediate
layer: 9
domain: sql
created: 2026-05-18
---

# Stored Procedures

> A stored procedure is business logic living inside the database — powerful for reducing round-trips and enforcing rules, but notoriously hard to test and version-control.

---

## Quick Reference

**Core idea:**
- A stored procedure is a named block of SQL (and optionally procedural code) stored in the database
- Called with CALL procedure_name(...) in PostgreSQL
- Can accept input and output parameters
- Stored procedures can contain transaction control: COMMIT and ROLLBACK
- Functions (CREATE FUNCTION) differ: they are called inline in queries and cannot issue COMMIT
- Benefits: fewer network round-trips for multi-step operations, logic enforced at the database level

**Tricky points:**
- Procedures cannot return result sets the same way a function can
- Logic in the database is outside normal application testing frameworks
- No git-friendly diff workflow without extra tooling
- Debugging is significantly harder than debugging application code
- The Python ecosystem strongly prefers application-layer logic over stored procedures

---

## What It Is

Think of a stored procedure as a recipe card kept in the kitchen rather than in the chef's notebook upstairs. When the waiter calls "fire table seven," the kitchen does not need to call upstairs to get instructions. The recipe is right there, already compiled, already trusted. The kitchen executes it locally without a back-and-forth relay. That is the original promise of stored procedures: move the logic to where the data lives and eliminate the communication overhead.

A stored procedure is a named, persistent routine stored inside the database engine. It can contain plain SQL statements, conditional logic (IF / CASE), loops (WHILE, FOR, LOOP), exception handling, and transaction management. In PostgreSQL, the procedural language used inside stored procedures is called PL/pgSQL — a language that blends SQL with Pascal-style control flow. Other databases use T-SQL (SQL Server), PL/SQL (Oracle), or similar dialects.

The historical rationale for stored procedures was strong. In the client-server era, network round-trips were expensive. A business process that required ten sequential queries — validate input, lock a row, update a balance, insert a log record, send a notification queue entry — could be collapsed into a single CALL that runs entirely inside the database server. The application made one network call, the procedure did all ten steps, and returned a result. This pattern genuinely improved performance in environments where network latency dominated.

The modern counterargument is equally strong. Application code has mature testing frameworks, continuous integration, code review, and version control. Stored procedure code lives in the database, managed separately from the application, often not under version control at all, and tested — if it is tested — only through integration tests that require a running database. When a stored procedure has a bug, the investigation crosses the application/database boundary in ways that are cognitively expensive. For this reason, most Python teams today use stored procedures sparingly or not at all, pushing all logic into the application layer and using the database as a pure data store.

---

## How It Actually Works

In PostgreSQL, you create a stored procedure with CREATE PROCEDURE. The body is written in PL/pgSQL (or plain SQL, or other supported languages). The crucial difference from CREATE FUNCTION is transaction control: a procedure can issue COMMIT and ROLLBACK, while a function cannot — it always runs inside the caller's transaction.

```sql
-- A stored procedure to transfer funds between accounts
CREATE OR REPLACE PROCEDURE transfer_funds(
    sender_id   INT,
    receiver_id INT,
    amount      NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    sender_balance NUMERIC;
BEGIN
    -- Lock both rows to prevent race conditions
    SELECT balance INTO sender_balance
    FROM accounts
    WHERE id = sender_id
    FOR UPDATE;

    IF sender_balance < amount THEN
        RAISE EXCEPTION 'Insufficient funds: balance is %', sender_balance;
    END IF;

    UPDATE accounts SET balance = balance - amount WHERE id = sender_id;
    UPDATE accounts SET balance = balance + amount WHERE id = receiver_id;

    INSERT INTO transfer_log (sender_id, receiver_id, amount, transferred_at)
    VALUES (sender_id, receiver_id, amount, NOW());

    COMMIT;
END;
$$;

-- Call the procedure
CALL transfer_funds(101, 202, 500.00);
```

The DECLARE block defines local variables. The BEGIN...END block is the executable body. RAISE EXCEPTION acts like throwing an exception — it aborts the current block and rolls back uncommitted changes unless caught. The COMMIT inside the procedure makes the transfer permanent as a unit.

Functions, by contrast, are called inline as part of a SELECT or WHERE clause. They return a value, they cannot issue COMMIT, and they run inside the caller's transaction boundary. Functions are the right tool when you need to encapsulate a computation that returns a single value or a set of rows for use in a query.

```sql
-- A function (not a procedure) — called in a query
CREATE OR REPLACE FUNCTION calculate_discount(price NUMERIC, tier TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN CASE tier
        WHEN 'gold'   THEN price * 0.80
        WHEN 'silver' THEN price * 0.90
        ELSE price
    END;
END;
$$;

-- Used inline in a query
SELECT product_name, calculate_discount(price, customer_tier) AS discounted_price
FROM products
JOIN customers ON customers.preferred_product = products.id
WHERE customers.id = 42;
```

Managing stored procedures under version control requires explicit tooling. Common approaches include storing all CREATE OR REPLACE PROCEDURE statements in .sql migration files tracked in git, or using tools like Flyway or Liquibase to manage database object versions alongside schema migrations. Without such tooling, procedure code drifts out of sync with the application code over time.

---

## How It Connects

Stored procedures interact directly with transactions — a procedure can manage its own commit boundaries, which is the one thing a function cannot do. Understanding transaction control (BEGIN, COMMIT, ROLLBACK, SAVEPOINT) is a prerequisite for writing procedures that behave correctly under concurrency.

Triggers in PostgreSQL are implemented as functions (not procedures) that are called automatically by the database engine. The procedural language mechanics — DECLARE, IF, RAISE — are identical between trigger functions and standalone procedures, so understanding one helps immediately with the other.

[[transactions|Transactions]]
[[acid-properties|ACID Properties]]
[[triggers|Triggers]]
[[savepoints|Savepoints]]

---

## Common Misconceptions

Misconception 1: "Stored procedures are always faster than running the same SQL from application code."
Reality: The performance advantage of stored procedures comes from reducing network round-trips. If an operation requires a single query, a stored procedure adds overhead without benefit — the query must travel to the database either way. For single-query operations, application code calling a parameterized query is equally fast and far more maintainable.

Misconception 2: "Stored procedures and functions are the same thing in PostgreSQL."
Reality: In PostgreSQL, procedures (CREATE PROCEDURE) and functions (CREATE FUNCTION) are distinct objects with different capabilities. The critical difference is transaction control: procedures can issue COMMIT and ROLLBACK, functions cannot. A function always executes within the caller's transaction. Confusing the two leads to bugs where transaction boundaries are not where the developer expects them.

Misconception 3: "Logic in stored procedures is more secure because it is 'inside the database'."
Reality: Stored procedures are not inherently more secure. SQL injection is possible in dynamic SQL inside procedures (EXECUTE format(...)). Access control is managed through GRANT/REVOKE exactly as with tables and views. The security properties of a stored procedure depend entirely on how it is written and what privileges are granted.

---

## Why It Matters in Practice

Stored procedures matter most in organizations with strict database-centric governance — financial institutions, ERPs, legacy enterprise systems — where the database is considered the authoritative enforcer of business rules. In these environments, every application that touches the database must go through procedures, ensuring that rules like "no transfer without an audit log entry" are enforced at the lowest level and cannot be bypassed by any client.

In Python-centric web application teams, stored procedures are rarely written from scratch. The more common encounter is maintaining existing procedures in a legacy codebase, or calling procedures provided by a vendor-supplied database schema. Understanding how to call a stored procedure from Python (cursor.callproc() in psycopg2, or CALL via SQLAlchemy text()) and how to handle output parameters and exceptions is the practical skill most Python developers actually need.

---

## What Breaks

**Unversioned procedure changes causing silent bugs.** A database administrator updates a stored procedure directly in production to fix an urgent bug. The change is not reflected in the git repository. Three months later, a developer deploys from the repository, overwriting the production procedure with the older broken version. The bug reappears and nobody knows why.

**Exception swallowing in loops.** A procedure processes a batch of records in a loop with a WHEN OTHERS THEN NULL exception handler. One record causes a constraint violation, the exception is silently swallowed, and the loop continues. The record is skipped with no error, no log, and no notification. The data silently becomes inconsistent.

```sql
-- Dangerous pattern: catching all exceptions silently
EXCEPTION
    WHEN OTHERS THEN
        NULL;  -- This hides every error including data corruption
```

**Long-running procedure blocking writes.** A stored procedure that processes end-of-month reports holds a transaction open for 45 minutes while crunching through millions of rows. Every UPDATE on any table touched by the procedure blocks waiting for the lock. The application's write throughput collapses. Procedures with long-running transactions must be designed to commit in batches.

---

## Interview Angle

Common question forms:
- "What is the difference between a stored procedure and a function in PostgreSQL?"
- "What are the advantages and disadvantages of stored procedures?"
- "How do you call a stored procedure from Python?"

Answer frame:
Start with the definition and the key distinction from functions — transaction control. Explain the network round-trip benefit honestly, then immediately address the tradeoffs: testing difficulty, version control challenges, debugging complexity. Note that modern Python applications generally prefer application-layer logic. If asked about calling from Python, mention cursor.callproc() or CALL via text() in SQLAlchemy.

---

## Related Notes

- [[transactions|Transactions]]
- [[acid-properties|ACID Properties]]
- [[triggers|Triggers]]
- [[savepoints|Savepoints]]
- [[views|Views]]
