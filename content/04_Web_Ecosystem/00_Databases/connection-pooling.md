---
title: 07 - Database Connection Pooling
description: "A connection pool maintains a cache of open database connections so that each request reuses an existing TCP connection rather than paying the cost of a new handshake and authentication on every query."
tags: [connection-pool, sqlalchemy, pgbouncer, postgresql, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Database Connection Pooling

> A connection pool is a cache of pre-opened database connections — reusing them eliminates the repeated cost of TCP handshakes and database authentication, making it one of the highest-leverage performance levers in a web application.

---

## Quick Reference

**Core idea:**
- Opening a database connection is expensive: TCP handshake, TLS negotiation, database-side authentication — typically 5–50 ms each
- A pool holds `pool_size` persistent connections and lends them to callers for the duration of a query
- `max_overflow` allows temporary extra connections beyond `pool_size` during spikes; they close when released
- `pool_recycle` closes and reopens connections older than N seconds — prevents "server has gone away" errors
- `pool_pre_ping=True` sends a lightweight `SELECT 1` before lending each connection, discarding stale ones

**Tricky points:**
- `pool_size` + `max_overflow` is the hard ceiling on simultaneous database connections — set it lower than your database's `max_connections` limit, leaving headroom for admin tools
- `NullPool` creates a new connection for every request and closes it immediately — correct for serverless functions where processes do not persist between invocations
- `StaticPool` shares one connection across all callers — correct for in-memory SQLite in tests, wrong everywhere else
- `pool_timeout` is how long a caller waits for a connection from the pool before raising `TimeoutError` — a full pool under load is a backpressure signal, not something to raise the limit to avoid
- PgBouncer operates outside the application; it multiplexes many application connections onto fewer PostgreSQL backend connections, useful when you have many app instances

---

## What It Is

Imagine a checkout counter at a busy store. Opening a new register for every single customer is wasteful — by the time the register is booted and the cashier is logged in, the customer has been waiting far longer than necessary. A sensible store keeps a set of registers open and ready, assigns customers to available ones, and only opens additional registers if the queue grows beyond what the standing set can handle. That is exactly what a connection pool does for database access.

Every time your application connects to PostgreSQL from scratch, the database server must verify credentials, allocate memory for the backend process, and negotiate a protocol version. On a local loopback interface this takes a few milliseconds; over a network with TLS it can take 20–50 ms. For an endpoint that executes five queries per request, naively opening a new connection on every request multiplies that overhead into every user interaction. A pool eliminates this by keeping connections open and sharing them across requests.

SQLAlchemy's default pool implementation is `QueuePool`. It maintains a pool of `pool_size` connections (default 5) and allows up to `max_overflow` additional connections (default 10) to be opened when the pool is exhausted. Connections that overflow are closed when returned rather than recycled back into the pool. The `pool_recycle` parameter is a safety valve: connections older than the specified number of seconds are closed and reopened on their next checkout, preventing the "server has gone away" error that occurs when a database server closes idle connections (MySQL default is 8 hours; PostgreSQL does not close idle connections by default but load balancers and firewalls often do).

---

## How It Actually Works

SQLAlchemy configures pooling through keyword arguments to `create_engine()`. The engine is a long-lived object created once at application startup, not per request.

```python
from sqlalchemy import create_engine

engine = create_engine(
    "postgresql+psycopg2://user:pass@localhost/mydb",
    pool_size=10,
    max_overflow=20,
    pool_timeout=30,       # seconds to wait for a connection
    pool_recycle=1800,     # recycle connections older than 30 minutes
    pool_pre_ping=True,    # test connection health before checkout
)
```

`pool_pre_ping=True` is strongly recommended for production. Without it, a stale connection (closed by a network device or database restart) is returned to the caller, who discovers it is dead only when trying to execute a query. With pre-ping enabled, SQLAlchemy issues a fast `SELECT 1` before handing the connection to the caller; if it fails, the connection is discarded and a fresh one is opened transparently.

For Lambda functions, containerized tasks that stop and restart frequently, or any environment where the process does not survive between requests, `NullPool` is correct. A pooled connection that is never returned to the pool (because the process exited) is a connection leak from the database's perspective.

```python
from sqlalchemy.pool import NullPool, StaticPool

# Serverless / short-lived processes
engine = create_engine(database_url, poolclass=NullPool)

# In-memory SQLite for unit tests — one shared connection required
engine = create_engine("sqlite:///:memory:", poolclass=StaticPool,
                       connect_args={"check_same_thread": False})
```

PgBouncer is an external connection pooler that runs as a sidecar process between the application and PostgreSQL. It presents a PostgreSQL interface on one port and proxies to the real PostgreSQL server using a much smaller set of server-side connections. In transaction-mode pooling, a server connection is held only for the duration of a single transaction and then returned to PgBouncer's pool — this allows thousands of application connections to share tens of server connections. The trade-off is that session-level state (prepared statements, advisory locks, `SET` commands) is lost between transactions.

---

## How It Connects

SQLAlchemy Core creates and configures the engine, which owns the pool. The ORM Session borrows a connection from the engine's pool for the duration of a transaction.

[[sqlalchemy-core|SQLAlchemy Core]]

Async engines use the same pool concepts but with async-compatible pool implementations inside `create_async_engine`.

[[sqlalchemy-async|SQLAlchemy Async]]

---

## Common Misconceptions

Misconception 1: "More connections in the pool always means better performance."
Reality: PostgreSQL allocates a dedicated backend process per connection. Too many connections exhaust server memory and increase lock contention. The optimal pool size for CPU-bound database work is often close to the number of CPU cores on the database server. PgBouncer is the correct solution when the application needs more concurrency than the database can handle as separate connections.

Misconception 2: "pool_pre_ping slows down every query."
Reality: The pre-ping is a single round-trip lightweight command executed only when a connection is checked out of the pool — not before every query within a transaction. For long-lived connections in production, the cost is negligible compared to the benefit of catching stale connections before they surface as opaque errors inside business logic.

---

## Why It Matters in Practice

Connection management is invisible until it breaks. Under low load, a badly configured pool works fine because there are always spare connections. Under real traffic, exhausted pools manifest as `TimeoutError` exceptions that appear unrelated to anything in the application code. Knowing the pool parameters, setting `pool_pre_ping=True` by default, and understanding when to use `NullPool` prevents a class of production incidents that are time-consuming to diagnose after the fact.

---

## Interview Angle

Common question forms:
- "Why do web applications use connection pools?"
- "What is the difference between pool_size and max_overflow in SQLAlchemy?"
- "When would you use NullPool?"

Answer frame:
Connection pools exist because opening a database connection is expensive — TCP, TLS, and auth overhead adds up. `pool_size` is the steady-state set of open connections; `max_overflow` allows temporary extras during load spikes. `NullPool` skips pooling entirely and is correct for serverless or short-lived processes that would otherwise leak connections on exit. `pool_pre_ping=True` is a best-practice default that silently handles stale connections.

---

## Related Notes

- [[sqlalchemy-core|SQLAlchemy Core]]
- [[sqlalchemy-orm|SQLAlchemy ORM]]
- [[sqlalchemy-async|SQLAlchemy Async]]
- [[database-sessions|Database Sessions in FastAPI]]
- [[asyncpg|asyncpg]]
