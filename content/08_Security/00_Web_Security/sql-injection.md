---
title: 02 - SQL Injection
description: "SQL injection occurs when attacker-controlled input is concatenated into a SQL query, allowing the attacker to alter the query's structure and read, modify, or delete arbitrary database content."
tags: [sql-injection, injection, database, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# SQL Injection

> SQL injection is the oldest and most destructive injection vulnerability — understanding the exact mechanism makes it impossible to accidentally introduce in Python code.

---

## Quick Reference

**Core idea:**
- Occurs when user input is embedded in a SQL string by concatenation rather than parameterization
- The attacker closes the developer's quote, injects their own SQL syntax, and comments out the rest
- Parameterized queries (prepared statements) are the complete defense — they separate code from data at the database protocol level
- SQLAlchemy ORM and Core both use parameterization by default; raw `text()` with f-strings bypasses this
- Blind SQL injection extracts data without seeing query output — through boolean conditions or time delays

**Tricky points:**
- ORM-generated queries are safe; `session.execute(text(f"SELECT ... {user_input}"))` is not — the ORM does not protect you when you opt into raw SQL
- Second-order injection: data is stored safely (parameterized) but later retrieved and interpolated into another query without re-parameterization
- Error-based injection: verbose database errors in HTTP responses leak schema information that guides further attacks
- `UNION`-based injection requires the attacker to know the number and types of columns in the original query — but this information is easily extracted incrementally
- Input validation (allow-listing characters) is a defense-in-depth measure, not a substitute for parameterization

---

## What It Is

Imagine a library catalog system where a librarian accepts a book title from a visitor and reads it aloud to search the database. If the librarian simply reads whatever is written on the paper, a visitor could write `"anything"; DROP TABLE books; --` and the librarian would say that aloud, causing the system to delete everything. That is SQL injection: the user-provided value is treated as part of the instruction rather than as pure data.

SQL injection works because early web applications (and many modern ones) build SQL queries by concatenating strings. A Python function that searches for users might look like: `query = "SELECT * FROM users WHERE username = '" + username + "'"`. If `username` is `alice`, the query is perfectly valid. If `username` is `alice' OR '1'='1`, the resulting query is `SELECT * FROM users WHERE username = 'alice' OR '1'='1'` — which returns every row in the table because `1=1` is always true. The developer intended to retrieve one user; the attacker retrieves all of them.

The full classic payload `' OR 1=1--` works by first closing the opening quote the developer wrote (the leading `'`), then appending a condition that is always true (`OR 1=1`), then commenting out everything that follows with `--` so the developer's closing quote does not cause a syntax error. The attacker has effectively rewritten the query without touching the source code.

---

## How It Actually Works

Consider this vulnerable Python function:

```python
def get_user(username: str):
    query = f"SELECT id, email FROM users WHERE username = '{username}'"
    return db.execute(query).fetchone()
```

When called with `username = "admin' --"`, the executed SQL becomes:

```sql
SELECT id, email FROM users WHERE username = 'admin' --'
```

The `--` comments out the trailing quote, making the query syntactically valid and returning the admin row. With `username = "' UNION SELECT username, password FROM users--"`, the executed SQL becomes:

```sql
SELECT id, email FROM users WHERE username = '' UNION SELECT username, password FROM users--
```

The UNION appends the entire password table to the result set. The attacker now has every username and password hash in the database from a single HTTP request.

Blind SQL injection operates without direct output. Time-based blind injection uses database sleep functions: `'; IF (SELECT COUNT(*) FROM users WHERE username='admin') > 0 WAITFOR DELAY '0:0:5'--`. If the HTTP response takes five seconds, the condition is true. The attacker uses this binary oracle to extract the entire database one bit at a time, automating the process with tools like sqlmap. Boolean-based blind injection works the same way but uses response differences (a "not found" page vs. a "found" page) rather than timing.

The complete defense is parameterized queries at every call site. SQLAlchemy Core's `text()` supports bind parameters:

```python
from sqlalchemy import text

def get_user(username: str):
    query = text("SELECT id, email FROM users WHERE username = :username")
    return db.execute(query, {"username": username}).fetchone()
```

The database driver sends the query and the parameter separately. The database parses the query template once, then substitutes the value in at execution time — the value is never interpreted as SQL syntax regardless of what characters it contains. The ORM approach is even simpler: `session.query(User).filter(User.username == username).first()` generates parameterized SQL automatically.

---

## How It Connects

SQL injection is the canonical A03 Injection vulnerability from the OWASP list, and understanding it mechanically illustrates why the entire injection category is dangerous.

[[owasp-top-10|OWASP Top 10]]

SQLAlchemy is the primary Python ORM, and knowing which patterns are safe versus which bypass parameterization is essential for writing safe database access code.

[[sqlalchemy-core|SQLAlchemy Core]]

---

## Common Misconceptions

Misconception 1: "I escape special characters with backslashes before inserting user input, so I'm protected."
Reality: Character escaping is fragile and database-specific. Different databases have different escaping rules, and certain character set encodings have historically allowed bypasses where multi-byte characters contain bytes that look like backslashes. Parameterization is not "better escaping" — it is a fundamentally different mechanism that separates the query structure from the data at the protocol level, making injection structurally impossible.

Misconception 2: "The ORM protects me from SQL injection."
Reality: The ORM protects you when you use it correctly — when you use its query-building API. The moment you call `session.execute(text(f"SELECT ... {user_input}"))` or `db.execute(f"SELECT ...")`, you are back to string concatenation and all protections are gone. Many SQLi vulnerabilities in ORM-based applications come from developers writing raw SQL for performance or convenience and forgetting that they have opted out of the ORM's protections.

Misconception 3: "We use an input validation library that rejects dangerous characters, so we're safe."
Reality: Input validation as a SQL injection defense is an ongoing arms race with character encoding tricks, second-order injection, and the impossibility of knowing in advance which characters are "dangerous" in every context. A username containing a single quote is perfectly legitimate. Parameterization eliminates the problem entirely rather than trying to predict and filter attack vectors.

---

## Why It Matters in Practice

SQL injection vulnerabilities have been behind some of the largest data breaches in history. The 2008 Heartland Payment Systems breach (130 million credit card numbers) and the 2012 Yahoo breach (450,000 credentials) were both rooted in SQL injection. These are not historical curiosities — SQLi remains in the OWASP Top 10 in 2021 and continues to be discovered in production applications regularly, including Python web applications where developers trusted ORM safety without understanding when it applies.

The consequence of SQLi in a Python application with a standard relational database is typically complete data exfiltration of every table the database user has access to. In many applications the web application connects to the database with a user that has write access, enabling the attacker to also modify or delete data, add administrative accounts, or (on certain database configurations) execute operating system commands via SQL.

---

## Interview Angle

Common question forms:
- "How does SQL injection work? Walk me through an example payload."
- "How do you prevent SQL injection in Python?"
- "What is the difference between first-order and second-order SQL injection?"
- "Does using an ORM protect against SQL injection?"

Answer frame:
A strong answer walks through the classic `' OR 1=1--` payload step by step, explaining what each character does to the query structure. It then explains parameterized queries correctly — not as "escaping" but as separating code from data at the protocol level. It answers the ORM question with nuance: the ORM protects you when you use its query API, but raw SQL bypasses the protection. A strong answer also mentions blind injection to show awareness that attackers do not need to see query output to extract data.

---

## Related Notes

- [[owasp-top-10|OWASP Top 10]]
- [[sqlalchemy-core|SQLAlchemy Core]]
- [[insecure-deserialization|Insecure Deserialization]]
- [[bandit|Bandit (Python Security Linter)]]
