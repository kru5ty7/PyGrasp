---
title: SQL Data Types
description: SQL data types define what values a column can hold and how the database stores and compares them, and choosing the wrong type at schema creation time causes correctness problems that are expensive to fix later.
tags: [sql, layer-9, types, schema]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# SQL Data Types

> The data type you choose for a column is a contract between the schema and the application — and breaking that contract with FLOAT for currency or VARCHAR for timestamps creates bugs that only appear under exactly the wrong conditions.

---

## Quick Reference

**Core idea:**
- Every column in a SQL table has a data type. The type controls what values are valid and how the database stores and compares them.
- Integer types: SMALLINT (2 bytes), INTEGER (4 bytes), BIGINT (8 bytes). Use BIGINT for primary keys that may grow large.
- Text types: TEXT (unlimited length) and VARCHAR(n) (limited length). In PostgreSQL, TEXT is preferred. VARCHAR(255) is a MySQL habit.
- Numeric precision: NUMERIC (or DECIMAL) stores exact decimal numbers. Never use FLOAT or DOUBLE for money.
- Timestamps: TIMESTAMPTZ (timestamp with time zone) is preferred over TIMESTAMP (without time zone). Always store UTC.
- BOOLEAN stores true/false. UUID stores globally unique 128-bit identifiers. JSONB stores structured JSON with indexing support.

**Tricky points:**
- FLOAT and DOUBLE are approximate numeric types. `0.1 + 0.2` does not equal `0.3` in floating-point. Using FLOAT for money causes rounding errors that accumulate over time.
- VARCHAR(255) is a MySQL pattern. In PostgreSQL, VARCHAR(255) and TEXT have identical storage. There is no performance benefit to VARCHAR(255) in PostgreSQL.
- TIMESTAMP without time zone stores the value you give it without any time zone context. If the server time zone changes, the meaning of stored values changes. TIMESTAMPTZ always stores in UTC internally.
- SERIAL is a PostgreSQL convenience shorthand for an integer column with a sequence. BIGSERIAL is preferred for primary keys. In PostgreSQL 10+, GENERATED AS IDENTITY is the standards-compliant alternative.
- JSONB is binary JSON — it parses and stores the JSON efficiently, supports indexing, and is queryable. JSON (without B) is stored as text and is not indexable. Use JSONB.

---

## What It Is

Think of data types like the labels on slots in a physical organizer. A slot labeled "phone number" will not fit a printed photograph; a slot labeled "date" will not accept a product description. Labeling the slots precisely — rather than just using a generic "anything goes here" container for everything — means the organizer stays usable over time: the right things go in the right places, you can find what you need, and mismatches are caught when you try to put something in the wrong slot.

SQL data types are the labels on table columns. When you declare a column as `INTEGER`, the database will only store whole numbers in that column and will reject strings or fractional values at insert time. When you declare a column as `TIMESTAMPTZ`, the database stores the value in a precise time-aware format and allows you to perform date arithmetic and timezone conversion. Choosing the right type is a decision made once at schema creation time, and changing it later requires an ALTER TABLE migration that may rewrite all existing data.

Integer types store whole numbers without fractional parts. SMALLINT stores values from -32,768 to 32,767 and uses 2 bytes per value. INTEGER (also written INT) stores values from roughly -2.1 billion to 2.1 billion and uses 4 bytes. BIGINT stores values from roughly -9.2 quintillion to 9.2 quintillion and uses 8 bytes. For primary keys, BIGINT (or BIGSERIAL for auto-incrementing) is the safe choice: applications regularly exhaust INTEGER primary key space as they grow, and migrating from INTEGER to BIGINT on a large table is painful.

Text types in SQL store character strings. TEXT in PostgreSQL stores strings of unlimited length. VARCHAR(n) stores strings up to n characters and rejects longer values. In PostgreSQL, there is no performance difference between TEXT and VARCHAR — they use the same underlying storage. The VARCHAR(n) limit is enforced as a constraint but does not make the column faster or smaller. PostgreSQL developers generally prefer TEXT with a CHECK constraint if a length limit is needed, because this gives a cleaner error message and is easier to change. VARCHAR(255) appears frequently in PostgreSQL schemas because MySQL developers brought the habit with them — in MySQL, VARCHAR length affects storage, so 255 was a common limit. In PostgreSQL, it provides no benefit.

Numeric and decimal types store precise decimal numbers. NUMERIC(precision, scale) stores a number with exactly the specified number of significant digits (precision) and digits after the decimal point (scale). For example, NUMERIC(10, 2) can store values up to 99,999,999.99 with exactly two decimal places. This is exact arithmetic — the database does not round or approximate. FLOAT and DOUBLE PRECISION are approximate types. They use binary floating-point representation, which cannot exactly represent many decimal fractions. The classic example is that 0.1 + 0.2 in binary floating-point equals 0.30000000000000004, not 0.3. For any column storing money, prices, or financial values, always use NUMERIC or INTEGER (storing amounts in the smallest unit, like cents).

---

## How It Actually Works

PostgreSQL's type system is extensible — unlike most databases, PostgreSQL lets you define custom types, operators, and functions. Every built-in type is stored in the `pg_type` system catalog. When a query compares or operates on values, PostgreSQL looks up operator functions that match the types involved. This is why adding two INTEGERs uses a different code path than adding two NUMERICs.

TIMESTAMPTZ (timestamp with time zone) stores an 8-byte integer representing microseconds since midnight UTC on January 1, 2000. The "with time zone" in the name is slightly misleading — PostgreSQL does not store the time zone. It stores the absolute UTC moment. When you insert a value, PostgreSQL converts it from the session's time zone to UTC. When you read the value, PostgreSQL converts it from UTC to the session's time zone for display. This means the underlying stored value is always unambiguous. TIMESTAMP (without time zone) stores the clock-face time you give it, with no time zone information attached. If you insert '2024-06-15 12:00:00' with TIMESTAMP, the database stores those numbers literally. If the server changes time zone, the same stored value now means a different moment in time.

JSONB stores JSON data in a parsed binary format. The original JSON text is not preserved (key order and duplicate keys are normalized away). JSONB supports GIN indexes, which allow the database to efficiently answer queries like "find all rows where the JSON object contains the key 'status' with value 'active'". This makes JSONB suitable for semi-structured data that needs to be searched. Regular JSON stores the raw text and must re-parse it on every access — it is never the right choice over JSONB.

```sql
-- Preferred integer primary key using BIGSERIAL
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,  -- auto-incrementing 8-byte integer
    name TEXT NOT NULL
);

-- PostgreSQL 10+ standards-compliant alternative
CREATE TABLE events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL
);

-- Money: use INTEGER (cents) or NUMERIC — never FLOAT
CREATE TABLE products (
    id          BIGSERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    price_cents INTEGER NOT NULL CHECK (price_cents >= 0),  -- store in cents
    -- OR: use NUMERIC for exact decimals
    price_exact NUMERIC(10, 2)
);

-- Timestamps: always use TIMESTAMPTZ
CREATE TABLE sessions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- JSONB for semi-structured data
CREATE TABLE events_log (
    id         BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    payload    JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Query JSONB fields
SELECT id, payload->>'user_id' AS user_id
FROM events_log
WHERE payload->>'event_type' = 'login'
  AND created_at > now() - INTERVAL '1 day';

-- BOOLEAN
CREATE TABLE feature_flags (
    id      BIGSERIAL PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    enabled BOOLEAN NOT NULL DEFAULT false
);
```

---

## How It Connects

Data types are declared in CREATE TABLE statements and modified with ALTER TABLE. Choosing the wrong type at schema creation means a later migration that rewrites all rows in the table — potentially locking the table for minutes.

[[ddl|DDL — CREATE, ALTER, DROP]]

Constraints enforce rules on top of types. NOT NULL, CHECK, and UNIQUE constraints work in combination with the column's type to define exactly what values are valid.

[[constraints|Constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK)]]

JSONB columns require specialized queries and indexing strategies. The JSON in SQL note covers how to query JSONB fields, use the `->>` and `@>` operators, and create GIN indexes.

[[json-in-sql|JSON in SQL]]

---

## Common Misconceptions

Misconception 1: "VARCHAR(255) is faster or more efficient than TEXT in PostgreSQL."
Reality: In PostgreSQL, VARCHAR(n) and TEXT use identical storage. There is no performance difference. VARCHAR(255) provides only a length constraint — the database will reject strings longer than 255 characters. This constraint is occasionally useful, but the specific value 255 has no special significance in PostgreSQL. It is a MySQL habit.

Misconception 2: "I can use FLOAT for monetary values. I will round to two decimal places before storing."
Reality: Floating-point numbers cannot exactly represent most decimal fractions. Rounding before storage does not fix this — the rounding calculation itself uses floating-point arithmetic. Sums and aggregates of FLOAT money columns accumulate errors. A financial report built on FLOAT columns will eventually show the wrong totals. Use INTEGER (cents) or NUMERIC.

Misconception 3: "TIMESTAMP and TIMESTAMPTZ are the same thing — I just use TIMESTAMP and set the server to UTC."
Reality: TIMESTAMP without time zone stores the clock-face time with no interpretation. If your application runs in multiple time zones, or if the database server's time zone configuration ever changes, stored TIMESTAMP values become ambiguous. TIMESTAMPTZ always stores an absolute UTC moment, regardless of server configuration. It is the safe and correct choice for any timestamp that will be displayed to users or used in time zone calculations.

---

## Why It Matters in Practice

Type selection is permanent in the sense that changing it requires a migration. A column that starts as VARCHAR(50) and later needs to hold longer strings requires an ALTER TABLE that may or may not lock the table. A column that starts as FLOAT for currency requires a careful migration to convert all stored values to NUMERIC without introducing rounding errors in the conversion itself. Getting the type right at schema design time avoids an entire class of migrations.

Using TIMESTAMPTZ instead of TIMESTAMP is especially important for applications with international users. An event stored with TIMESTAMP at midnight in New York looks like 5 AM when read by a UTC server and 1 AM when read by an EST server, depending on configuration. TIMESTAMPTZ eliminates this ambiguity by always storing and returning UTC, letting the application layer convert to the user's local time zone for display.

---

## What Breaks

Using INTEGER instead of BIGINT for a primary key on a rapidly growing table eventually overflows. INTEGER can hold approximately 2.1 billion values. For a high-volume event logging table, this limit can be reached in months or years. When the sequence hits the max, inserts fail with an overflow error.

```sql
-- This will eventually fail on a high-traffic table:
CREATE TABLE events (
    id SERIAL PRIMARY KEY  -- SERIAL is INT, max ~2.1 billion
);
-- Use BIGSERIAL instead:
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY  -- max ~9.2 quintillion
);
```

Storing financial values as FLOAT leads to accumulated rounding errors that only appear in totals and aggregates, not in individual row inspections.

```sql
-- Create a table with FLOAT for prices (wrong choice)
CREATE TABLE line_items (price FLOAT);
INSERT INTO line_items VALUES (0.10), (0.20);

-- This sum may not equal 0.30 due to floating-point representation
SELECT SUM(price) FROM line_items;
-- Possible result: 0.30000000000000004

-- Correct: store cents as INTEGER
CREATE TABLE line_items (price_cents INTEGER);
INSERT INTO line_items VALUES (10), (20);
SELECT SUM(price_cents) FROM line_items;  -- exactly 30, always
```

---

## Interview Angle

Common question forms:
- "How would you store monetary values in a database?"
- "What is the difference between TIMESTAMP and TIMESTAMPTZ?"
- "When would you use JSONB versus a separate table?"
- "Why is VARCHAR(255) common even in PostgreSQL schemas?"

Answer frame:
For money: INTEGER (cents) or NUMERIC — never FLOAT. Explain why (binary floating-point cannot represent most decimal fractions exactly). For timestamps: TIMESTAMPTZ always, because it stores an absolute UTC moment regardless of server configuration. For JSONB: use it for semi-structured data that varies per row, that needs to be searched, and where the schema is not fully known in advance. For VARCHAR(255): acknowledge the MySQL origin of the habit and explain that in PostgreSQL it adds a constraint but no performance benefit.

---

## Related Notes

- [[ddl|DDL — CREATE, ALTER, DROP]]
- [[constraints|Constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, CHECK)]]
- [[json-in-sql|JSON in SQL]]
- [[sql-databases|SQL Databases (PostgreSQL, MySQL, SQLite)]]
