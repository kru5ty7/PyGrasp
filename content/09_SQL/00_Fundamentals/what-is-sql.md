---
title: What is SQL
description: SQL is a declarative language for querying and manipulating relational databases, and understanding what "declarative" means unlocks how to think about every query you write.
tags: [sql, layer-9, fundamentals]
status: draft
difficulty: beginner
layer: 9
domain: sql
created: 2026-05-18
---

# What is SQL

> SQL is the language relational databases speak, and knowing the difference between asking *what* you want versus *how* to get it is the first thing that separates developers who write good queries from those who write slow ones.

---

## Quick Reference

**Core idea:**
- SQL stands for Structured Query Language. It was standardized in 1986 and remains the dominant language for relational databases.
- SQL is declarative: you describe the result you want, not the steps to produce it.
- The four main statement categories are SELECT (read), INSERT (create), UPDATE (modify), and DELETE (remove).
- Every SQL statement runs against a database engine, which parses, plans, and executes it.
- PostgreSQL is the reference database used throughout this layer unless otherwise stated.
- SQL is case-insensitive for keywords, but convention is to write keywords in uppercase.

**Tricky points:**
- "Declarative" does not mean the database does whatever it wants — the query optimizer chooses the execution plan, and you can influence it.
- SQL is not a programming language in the traditional sense. It has no loops, no variables in base syntax (only in procedural extensions like PL/pgSQL).
- The written order of a SELECT statement is not the execution order. FROM runs before SELECT.
- NULL is not a value in the normal sense. It is the absence of a value, and it behaves unexpectedly in comparisons.
- Different databases (PostgreSQL, MySQL, SQLite) speak slightly different SQL dialects. Code that works in one may fail in another.

---

## What It Is

Think of SQL like a librarian system. When you walk into a library and say "I want every mystery novel published after 2010, sorted by author," you are not telling the librarian which shelf to check first, which route to walk, or how to carry the books. You are describing the result you want. The librarian (the database engine) figures out the most efficient way to retrieve it. That is what it means for SQL to be declarative.

SQL — Structured Query Language — is the language used to communicate with relational database management systems (RDBMS). An RDBMS is software that stores data in tables, enforces relationships between those tables, and answers queries about the data. PostgreSQL, MySQL, and SQLite are all RDBMS products. Each of them understands SQL, though with small dialect differences.

The contrast to declarative is imperative, which is how most programming languages work. In Python, you write step-by-step instructions: loop over this list, check this condition, append to that array. In SQL, you write a description of the output set you want, and the database decides how to produce it. This is why SQL queries can look deceptively simple while doing enormous amounts of work internally — the engine is doing the iteration, not you.

SQL has been standardized since 1986 by ANSI and ISO. The core syntax has changed little in fifty years, which is why SQL knowledge transfers across jobs and decades. PostgreSQL implements nearly all of the SQL standard plus a rich set of extensions. It is the recommended database for Python backend development and the reference throughout this layer.

---

## How It Actually Works

When you submit a SQL statement, the database engine processes it in several distinct phases. First, the parser reads the text and checks that the syntax is valid SQL. It builds an internal tree structure called a parse tree. Second, the analyzer resolves names — it checks that the tables and columns you referenced actually exist and that you have permission to access them. Third, the query planner (also called the optimizer) takes the logical query and generates one or more physical execution plans. A plan describes the operations the engine will perform: which index to use, which join algorithm to apply, in what order to access tables. The planner estimates the cost of each plan and picks the cheapest one. Fourth, the executor runs the chosen plan and streams rows back to the client.

This pipeline matters because the SQL text you write is not what runs. The optimizer rewrites and rearranges your query to make it faster. When a query is slow, the problem is almost always in the plan the optimizer chose — either because it lacks the right index, or because statistics about the data are stale, or because the query was written in a way that prevents the optimizer from making a good choice. The `EXPLAIN` and `EXPLAIN ANALYZE` commands expose the execution plan so you can inspect it.

```sql
-- The four statement types in SQL
-- SELECT: read rows from a table
SELECT id, name, email FROM users WHERE active = true;

-- INSERT: add new rows
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');

-- UPDATE: modify existing rows
UPDATE users SET email = 'alice@new.com' WHERE id = 42;

-- DELETE: remove rows
DELETE FROM users WHERE active = false;
```

---

## How It Connects

The SELECT statement is the most complex statement in SQL. It has its own execution order, aliasing rules, and distinct behavior — all covered separately. Understanding SELECT well requires understanding how FROM, WHERE, and ORDER BY interact.

[[select-basics|SELECT Basics]]

SQL's declarative nature becomes most important when you start reading query execution plans. The EXPLAIN ANALYZE command reveals what the engine actually did, which is the foundation of all query optimization work.

[[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]

DDL and DML are the two broad categories that all SQL statements fall into. DDL defines structure; DML manipulates data. Understanding this split clarifies which operations are safe and which can cause data loss.

[[ddl|DDL — CREATE, ALTER, DROP]]
[[dml|DML — INSERT, UPDATE, DELETE]]

---

## Common Misconceptions

Misconception 1: "SQL is a simple language because queries read like English."
Reality: The English-like surface syntax hides deep complexity. SQL has non-obvious execution ordering, three-valued logic (true, false, NULL), multiple join types, and optimization subtleties that can make the same logical query run in milliseconds or minutes.

Misconception 2: "You write SQL and the database does exactly what you wrote."
Reality: The database engine translates your SQL into an execution plan. The plan may look nothing like the SQL text. The optimizer may reorder joins, push filters down, or use an index you did not mention. You describe what you want; the engine decides how to get it.

Misconception 3: "SQL is outdated because NoSQL databases exist."
Reality: NoSQL databases solve specific problems (horizontal scale, schema flexibility, document storage) but do not replace relational databases. Relational databases with SQL remain the default for most application backends, and many NoSQL systems have added SQL-like query interfaces.

---

## Why It Matters in Practice

If you do not understand that SQL is declarative, you will fight the database constantly. You will try to control execution order through query structure in ways that do not work, and you will misread slow queries as bugs when they are actually plan choices. Understanding that the optimizer is your ally — and that your job is to give it accurate information (through indexes, statistics, and well-structured queries) — changes how you write and debug SQL.

The four statement categories are not academic trivia. They map directly to security models (you can grant SELECT without granting DELETE), to transaction safety (some operations auto-commit), and to the mental model of what can go wrong. A developer who knows only SELECT syntax but not how INSERT, UPDATE, and DELETE interact with transactions will eventually corrupt data in production.

---

## What Breaks

If you write UPDATE or DELETE without a WHERE clause, the engine applies the change to every row in the table. This is valid SQL — the engine will not warn you. In production, this means every user record gets the same email address, or every order gets deleted. Most production databases are configured with `autocommit = on` by default, which means there is no transaction to roll back. Data is gone.

```sql
-- This deletes every row in the orders table. No warning. No confirmation.
DELETE FROM orders;

-- This is what you meant:
DELETE FROM orders WHERE id = 1001;
```

If you assume SQL keywords are case-sensitive and write tooling that normalizes casing incorrectly, queries may still parse but produce unexpected results if string literals or identifiers are affected. Keywords like `SELECT` are case-insensitive; string values like `'Alice'` are case-sensitive in most databases.

---

## Interview Angle

Common question forms:
- "What is SQL and how does it differ from a programming language like Python?"
- "What does it mean for SQL to be declarative?"
- "What are the main types of SQL statements?"

Answer frame:
Define declarative versus imperative with a concrete example. Name the four statement types and what each does. Mention the query optimizer as the mechanism that converts declarative SQL into an execution plan. If the interviewer pushes further, bring in execution order (FROM before SELECT) or NULL behavior as examples of non-obvious SQL semantics.

---

## Related Notes

- [[select-basics|SELECT Basics]]
- [[ddl|DDL — CREATE, ALTER, DROP]]
- [[dml|DML — INSERT, UPDATE, DELETE]]
- [[sql-databases|SQL Databases (PostgreSQL, MySQL, SQLite)]]
- [[explain-analyze|EXPLAIN and EXPLAIN ANALYZE]]
