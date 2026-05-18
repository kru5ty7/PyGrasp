---
title: 07 - Logging
description: "Python's logging module provides a hierarchical, configurable logging system — loggers emit records, handlers route them to destinations, and formatters control the output shape, all independently configurable."
tags: [logging, getLogger, handlers, formatters, propagate, basicConfig, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Logging

> Python's `logging` module is a production-grade observability layer built into the standard library — it separates what you log from where logs go and what they look like, letting each concern be configured independently.

---

## Quick Reference

**Core idea:**
- `logging.getLogger(__name__)` — creates or retrieves a logger named after the current module; hierarchy follows Python package dot notation
- Five severity levels: `DEBUG` (10), `INFO` (20), `WARNING` (30), `ERROR` (40), `CRITICAL` (50)
- Architecture: Logger → Handler(s) → Formatter; loggers decide what to emit, handlers decide where it goes, formatters decide how it looks
- `propagate = True` (default): log records bubble up the logger hierarchy to the root logger — source of duplicate log lines
- `logging.basicConfig()` configures the root logger; only has effect if the root logger has no handlers yet

**Tricky points:**
- `logging.warning("msg")` is a shortcut to the root logger — avoid it in libraries; use `logging.getLogger(__name__)` instead
- A logger's effective level inherits from its parent if no level is set on the logger itself
- Adding the same handler to a logger twice (common in Jupyter notebooks with `basicConfig`) causes duplicate log output
- `logging.exception("msg")` logs at ERROR level AND includes the current exception's traceback — must be called inside an `except` block
- `%(message)s` in a format string calls `str(record.getMessage())` lazily — logging does not format the message if the record's level is below the handler's level

---

## What It Is

Imagine a newsroom with reporters, editors, and publishing desks. Reporters gather stories — they do not decide which paper to print them in or how to lay them out. Editors decide which stories are worth running (applying a threshold: only stories above a certain importance get passed on). Publishing desks receive approved stories, format them for their specific outlet (newspaper, website, radio), and send them out. Each layer is independently configured: a reporter in the sports section does not need to know about the technology desk's formatting rules.

Python's `logging` module follows exactly this newsroom model. Your code creates loggers (the reporters) that emit log records. Each logger has a level threshold — records below the threshold are silently dropped at the source. Records that pass the threshold travel up the logger hierarchy to the root logger (or stop when `propagate = False`). Handlers attached to any logger in the chain (the publishing desks) receive the record and route it to a destination: the console, a file, a remote server, an email address. Formatters attached to each handler control how the record is rendered as text.

The architecture's strength is that application code only needs to call `logger.info("...")` — it does not need to know whether logs are going to stdout, a file, or a monitoring service. Configuration is entirely external to the logging calls themselves. A library that uses `logging.getLogger(__name__)` correctly will be completely silent in applications that do not configure a handler for it, and will automatically gain output when the deploying application sets up logging.

---

## How It Actually Works

`logging.getLogger(name)` looks up a `Logger` object in the global `logging.Manager.loggerDict` dictionary. If a logger with that name already exists, it is returned; otherwise, a new one is created. The hierarchy is implicit: a logger named `myapp.database` is a child of `myapp`, which is a child of the root logger. This is determined by the dot-separated name — no explicit parent-child registration is needed.

```python
import logging

logger = logging.getLogger(__name__)   # e.g., "myapp.database"
logger.setLevel(logging.DEBUG)

handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s %(name)s %(levelname)s %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

logger.info("Database connected")
logger.debug("Query: %s", sql_query)   # % formatting, not f-string — lazy evaluation
```

The lazy evaluation detail in the last line is important. `logger.debug("Query: %s", sql_query)` passes the format string and arguments separately. The `%` substitution is only performed if the record's level passes all threshold checks. If DEBUG logging is disabled, `sql_query` is never converted to a string at all. Using f-strings — `logger.debug(f"Query: {sql_query}")` — evaluates the expression eagerly, paying the formatting cost even when the message is never emitted.

The `propagate` attribute controls whether records travel up the hierarchy. With `propagate = True` (default), a record emitted by `myapp.database` is also processed by any handlers on `myapp` and on the root logger. Duplicate log output almost always means the same record is being processed by handlers at multiple levels. The fix is either `logger.propagate = False` on the child logger or ensuring handlers are attached only to the root logger (the standard deployment pattern).

`logging.basicConfig()` is a convenience that adds a `StreamHandler` with a default formatter to the root logger, but only if the root logger has no handlers. Call it once at startup, before any loggers emit records. In library code, never call `basicConfig()` — it is the application's responsibility to configure logging.

---

## How It Connects

Exception chaining and logging intersect at `logger.exception()`. This method logs at ERROR level and appends the full exception chain (via `traceback.format_exc()`) to the log record. It is the standard way to log caught exceptions with their full context in one call.

[[exception-chaining|Exception Chaining]]

Context managers can wrap logging setup — the `logging.handlers.RotatingFileHandler` is typically managed as a resource, and `contextlib.contextmanager` is useful for temporarily redirecting log output in tests.

[[context-managers|Context Managers]]

In web frameworks, `logging.getLogger(__name__)` combined with a request-scoped filter is how per-request log correlation (request IDs, user IDs) is injected into log records without modifying every logging call.

[[namespaces-and-scopes|Namespaces and Scopes]]

---

## Common Misconceptions

Misconception 1: "Calling `logging.basicConfig()` in multiple places is fine — it is idempotent."
Reality: `basicConfig()` only has effect the first time it is called when the root logger has no handlers. Subsequent calls are silently ignored. If a library calls `basicConfig()` before your application does, your configuration will never take effect.

Misconception 2: "A logger with no level set will not emit any records."
Reality: A logger with no level set has effective level `NOTSET` (0), which means it defers to its parent. Records travel up the hierarchy until they reach a logger with a level set or the root logger. If the root logger has no level set, its default is `WARNING`.

Misconception 3: "Using f-strings in logging calls is equivalent to using `%` formatting."
Reality: f-strings evaluate eagerly — the formatted string is computed before the logging framework decides whether the record should be emitted. Using `%s` with positional arguments defers formatting to after the level check, saving CPU for suppressed messages.

---

## Why It Matters in Practice

Duplicate log lines are the most common production logging problem, and `propagate = True` is almost always the cause. If your application configures a handler on both the root logger and a child logger, every record from the child will be processed twice. The standard pattern is to configure handlers only on the root logger via `logging.basicConfig()` or `logging.config.dictConfig()`, and let all child loggers propagate to it.

Log level discipline is a close second. Libraries that log at WARNING or higher are generally silent in production unless something is actually wrong. Libraries that log at DEBUG or INFO flood production logs with noise. The convention — which `logging.getLogger(__name__)` supports natively — is that library code always uses named loggers, never calls the module-level `logging.warning()` shortcut, and sets no handlers of its own. Application operators decide what to capture.

---

## Interview Angle

Common question forms:
- "What is the architecture of Python's logging module?"
- "Why do I see duplicate log lines and how do I fix it?"
- "What is the difference between `logger.exception()` and `logger.error()`?"

Answer frame:
Logger → Handler → Formatter. Loggers decide whether to emit (level check), handlers decide where to send (stdout, file, remote), formatters decide the text layout. Duplicate lines: `propagate = True` causes records to reach handlers at multiple levels — fix by adding handlers only to root. `logger.exception()` logs at ERROR and appends the current exception traceback; `logger.error()` logs at ERROR without the traceback.

---

## Related Notes

- [[exception-chaining|Exception Chaining]]
- [[exceptions|Exceptions]]
- [[context-managers|Context Managers]]
- [[contextlib|contextlib]]
