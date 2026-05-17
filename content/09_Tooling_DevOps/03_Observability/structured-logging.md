---
title: 02 - Structured Logging
description: "Structured logging emits log records as JSON objects rather than formatted strings, making every field independently queryable in log aggregation systems — the structlog library adds context binding, processor pipelines, and consistent JSON output to Python's standard logging."
tags: [structured-logging, structlog, json-logs, observability, context-binding, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Structured Logging

> Structured logging replaces human-readable log strings with machine-readable JSON objects, transforming logs from text that humans search with `grep` into records that log aggregation systems can query by field, filter by value, and analyze at scale.

---

## Quick Reference

**Core idea:**
- Emit logs as JSON: `{"timestamp": "...", "level": "info", "event": "...", "request_id": "abc123"}`
- `structlog` library provides context binding, processor pipelines, and JSON output for Python
- `structlog.contextvars.bind_contextvars(request_id=...)` — binds context for the entire request lifecycle
- JSON logs are queryable by field in Elasticsearch, Loki, Datadog: `level:error AND user_id:42`
- Every log record should have consistent fields: `timestamp`, `level`, `event`, `service`, plus context fields
- `structlog.stdlib.add_logger_name` and `structlog.stdlib.add_log_level` — processors that add standard fields

**Tricky points:**
- `structlog` wraps Python's standard `logging` module by default — it produces stdlib-compatible records that feed into existing log handlers (RotatingFileHandler, etc.)
- Context binding in `structlog` is thread-local (or async-context-local with `contextvars`) — bind request_id at request start, and every log within the request includes it without passing it explicitly
- JSON logs are not human-friendly at the terminal — `structlog.dev.ConsoleRenderer()` gives pretty-printed colored output for development, while `structlog.processors.JSONRenderer()` is for production
- Log events should be constant strings (`"payment processed"`) not formatted strings (`f"Payment {txn_id} processed"`) — the variable parts go in bound context fields
- Avoid re-binding the same key in nested calls; instead bind at the outermost scope (e.g., middleware for request_id) and let inner code add its own fields

---

## What It Is

Traditional Python logging produces text strings: `"2026-05-18 12:34:56 | INFO | Payment 12345 processed for user 42"`. This is readable to a human scanning a terminal, but it is opaque to a machine. To find all failed payments in Elasticsearch, you would need a regex to parse "Payment X processed for user Y" — fragile, slow, and dependent on the log format never changing.

Structured logging emits the same information as a JSON object: `{"timestamp": "2026-05-18T12:34:56", "level": "info", "event": "payment processed", "transaction_id": 12345, "user_id": 42, "amount": 99.99}`. Now every field is independently addressable. Elasticsearch indexes every key. A query like `event:"payment processed" AND level:"error"` finds all failed payment log records across all services, across all time ranges, instantly — without parsing strings or writing regex.

The `structlog` library is the standard Python tool for structured logging. It wraps Python's logging module and adds three key capabilities. First, it provides a processor pipeline — a chain of functions that transform the log record before emission, adding fields like timestamps and log levels, redacting sensitive data, or converting to JSON. Second, it provides context binding — the ability to attach key-value pairs to the current execution context (request, background task) so that every log statement automatically includes them without the developer having to pass them explicitly. Third, it separates the rendering concern from the logging concern — the same logging code can produce pretty terminal output in development and JSON in production, just by changing the processors.

---

## How It Actually Works

**Configuring structlog for production:**

```python
import logging
import sys
import structlog

def configure_structlog(production: bool = True) -> None:
    """Configure structlog with appropriate renderers for environment."""

    shared_processors = [
        # Add timestamp to every record
        structlog.processors.TimeStamper(fmt="iso"),
        # Add log level
        structlog.stdlib.add_log_level,
        # Add logger name
        structlog.stdlib.add_logger_name,
        # Add exception info as structured data (not formatted string)
        structlog.processors.format_exc_info,
        # Prepare for stdlib logging (adds _record to the event_dict)
        structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
    ]

    structlog.configure(
        processors=shared_processors,
        wrapper_class=structlog.stdlib.BoundLogger,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )

    # Configure stdlib logging to use structlog's formatter
    renderer = (
        structlog.processors.JSONRenderer()
        if production
        else structlog.dev.ConsoleRenderer(colors=True)
    )

    formatter = structlog.stdlib.ProcessorFormatter(
        processor=renderer,
        foreign_pre_chain=shared_processors[:-1],  # For stdlib-originated logs
    )

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    root_logger = logging.getLogger()
    root_logger.addHandler(handler)
    root_logger.setLevel(logging.INFO)
```

**Using structlog in application code:**

```python
import structlog

# Get a structured logger for this module
logger = structlog.get_logger(__name__)

async def handle_payment(user_id: int, amount: float) -> dict:
    # bind_contextvars attaches to the current async context
    # Every subsequent log in this context includes these fields
    structlog.contextvars.bind_contextvars(user_id=user_id, operation="payment")

    logger.info("payment started", amount=amount)

    try:
        result = await payment_gateway.charge(user_id, amount)
        logger.info(
            "payment succeeded",
            transaction_id=result.id,
            amount=amount,
        )
        return result
    except PaymentError as e:
        logger.error(
            "payment failed",
            error_code=e.code,
            error_message=str(e),
        )
        raise
```

**FastAPI middleware for request context binding:**

```python
import uuid
import structlog
from fastapi import Request

async def logging_middleware(request: Request, call_next):
    # Clear any context from a previous request
    structlog.contextvars.clear_contextvars()

    # Bind request context — all logs within this request include these fields
    structlog.contextvars.bind_contextvars(
        request_id=str(uuid.uuid4()),
        method=request.method,
        path=request.url.path,
    )

    logger = structlog.get_logger(__name__)
    logger.info("request received")

    response = await call_next(request)

    logger.info(
        "request completed",
        status_code=response.status_code,
    )

    return response
```

The JSON output of the above middleware log:

```json
{"timestamp": "2026-05-18T12:34:56.789Z", "level": "info", "event": "request completed",
 "logger": "myapp.middleware", "request_id": "550e8400-e29b-41d4-a716-446655440000",
 "method": "POST", "path": "/api/payments", "status_code": 200}
```

Every log record for that request automatically includes `request_id`, `method`, and `path` — without the payment handler explicitly knowing about these fields.

---

## How It Connects

Structured logging is the next maturity level beyond production logging — it builds on the same handler and logger infrastructure but changes the output format for machine consumption.

[[logging-production|Production Logging]]

FastAPI middleware is the natural place to bind request context (request_id, user_id) to the structlog context, ensuring all logs within a request lifecycle share these fields.

[[fastapi-middleware|Middleware in FastAPI]]

OpenTelemetry traces and structured logs complement each other — traces show the timing and structure of a request, logs show the detailed events; linking them via trace_id makes both more useful.

[[opentelemetry|OpenTelemetry]]

---

## Common Misconceptions

Misconception 1: "Structured logging means I format the message differently — `logger.info(f'{key}={value}')` becomes `logger.info('event', key=value)`."
Reality: The format change is the surface behavior. The deep change is that the log record becomes a dictionary of typed fields rather than a formatted string. The event string should be a constant descriptor (`"payment processed"`) and all variable data should be keyword arguments. This is what makes log aggregation queries work — you query `payment_processed AND amount>100`, not `grep "payment processed"`.

Misconception 2: "structlog replaces Python's logging module entirely."
Reality: structlog wraps Python's standard `logging` module by default. It uses Python loggers and handlers for the actual output. The benefit is that third-party libraries that use `logging.getLogger(__name__)` also produce structured output when structlog is configured with `ProcessorFormatter`. The two systems coexist and cooperate.

Misconception 3: "JSON logs are fine for both terminal viewing and production aggregation."
Reality: JSON logs in a terminal are nearly unreadable — a single log line can be 200+ characters of JSON with no color or indentation. structlog addresses this with its dual-renderer approach: `ConsoleRenderer` (colored, pretty, human-readable) in development, `JSONRenderer` in production. The rendering is configuration, not code — the same log calls work in both environments.

---

## Why It Matters in Practice

The operational value of structured logging becomes apparent at scale. A service handling 1,000 requests per second produces millions of log records per day. Finding the logs for a specific user's failed payment means either parsing text with regex (fragile, slow) or querying by field (`user_id:42 AND event:"payment failed" AND timestamp:[2026-05-18 TO 2026-05-19]`). The query takes milliseconds; the regex approach may not even be possible.

Binding context variables at the request boundary (request_id, user_id, tenant_id) is the technique that makes distributed debugging feasible. When a payment fails, the operator searches for `request_id:"550e8400"` and sees every log record from every service that participated in that request, in chronological order. Without request_id correlation, reconstructing the sequence of events across multiple services requires reading multiple unrelated log streams and inferring connections by timestamp.

---

## Interview Angle

Common question forms:
- "What is structured logging and why would you use it over plain text logs?"
- "How do you ensure all logs for a single request include the same correlation ID?"

Answer frame:
Explain the difference: plain text logs are grep-able by humans, structured JSON logs are queryable by machines. Describe structlog's context binding via `contextvars` — bind `request_id` in middleware, every log in that request context includes it. Explain the processor pipeline (add timestamp, level, JSON render). Note the dev (ConsoleRenderer) vs prod (JSONRenderer) configuration pattern.

---

## Related Notes

- [[logging-production|Production Logging]]
- [[metrics-and-monitoring|Metrics and Monitoring]]
- [[opentelemetry|OpenTelemetry]]
- [[sentry|Sentry]]
- [[fastapi-middleware|Middleware in FastAPI]]
