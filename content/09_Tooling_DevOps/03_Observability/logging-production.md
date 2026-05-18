---
title: 01 - Production Logging
description: "Production logging requires choosing appropriate severity levels, using rotating file handlers to prevent disk exhaustion, shipping logs to centralized systems like ELK or Loki, and knowing what to log  -  and critically, what not to log  -  for both usefulness and security."
tags: [logging, production, rotating-handler, elk, loki, log-levels, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Production Logging

> Production logging is not about printing debug statements  -  it is about creating a reliable record of application behavior that is searchable, retained appropriately, and does not contain sensitive data, using severity levels that allow operators to filter signal from noise.

---

## Quick Reference

**Core idea:**
- Five levels in order: `DEBUG < INFO < WARNING < ERROR < CRITICAL`
- `logging.basicConfig(level=logging.INFO)`  -  minimum configuration; logs INFO and above
- `RotatingFileHandler`  -  rotates log files when they reach a size limit, keeping N backups
- `TimedRotatingFileHandler`  -  rotates on time intervals (daily, hourly)
- In production: stream logs to stdout/stderr (Docker captures these), not to files inside the container
- **What to log**: requests (method, path, status, duration), errors with tracebacks, business events (user created, payment processed)

**Tricky points:**
- Logging in Python is hierarchical  -  a logger named `myapp.api` is a child of `myapp`, which is a child of the root logger; propagation carries log records up the hierarchy
- `logger.exception(msg)` logs at ERROR level and automatically includes the current exception traceback  -  preferred over `logger.error(msg)` when inside an `except` block
- Log levels should be runtime-configurable  -  hardcoding `DEBUG` in production floods logs with noise; use environment variables (`LOG_LEVEL=INFO`) to set levels
- Never log passwords, API keys, personal data, or credit card numbers  -  log scrubbing is hard; not logging them in the first place is easy
- `logging.getLogger(__name__)`  -  the standard idiom; creates a logger named after the module, which participates correctly in the hierarchy

---

## What It Is

Logging is the instrument panel of a running application. When code is executing on a production server, developers cannot attach a debugger and cannot add print statements without redeploying. Logs are the only window into what the application is doing. Without meaningful logs, diagnosing a production incident becomes archaeological: examining database state, inferring what might have happened, guessing at causes. With structured, appropriately leveled logs, operators can reconstruct the exact sequence of events that led to a failure.

The severity level system is the primary tool for filtering signal from noise. A production application handles thousands of requests per minute. If every function call, every database query, and every variable assignment were logged, the sheer volume would be unnavigable. Severity levels  -  DEBUG for developer-targeted detail, INFO for normal operational milestones, WARNING for recoverable anomalies, ERROR for failures that require attention, CRITICAL for failures that threaten the system  -  allow log consumers to filter. Operations teams set their log aggregation tools to alert on ERROR and CRITICAL, monitor INFO-level trends, and ignore DEBUG entirely in production.

Centralized logging is the practice of shipping all logs from all application instances to one place. In a container environment, an application might run across dozens of pods. Each pod writes logs to stdout. A log aggregation system (Loki, Elasticsearch with Logstash, AWS CloudWatch) collects these streams, indexes them, and provides a query interface. The developer or operator never needs to SSH into individual machines to read log files  -  they query the centralized store.

---

## How It Actually Works

Python's `logging` module uses a hierarchy of loggers, handlers, and formatters:

```python
import logging
import sys
from logging.handlers import RotatingFileHandler

# Create a logger for this module
logger = logging.getLogger(__name__)


def configure_logging(level: str = "INFO") -> None:
    """Configure application-wide logging."""
    log_level = getattr(logging, level.upper())

    # Root logger configuration
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)

    # Formatter: timestamp, level, logger name, message
    formatter = logging.Formatter(
        fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )

    # Stream handler: writes to stdout (Docker captures this)
    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(formatter)
    root_logger.addHandler(stream_handler)

    # Rotating file handler: for non-containerized deployments
    # Rotates when file reaches 10MB, keeps 5 backups
    file_handler = RotatingFileHandler(
        filename="app.log",
        maxBytes=10 * 1024 * 1024,  # 10 MB
        backupCount=5,
        encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    root_logger.addHandler(file_handler)

    # Silence noisy third-party loggers
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)
```

Logging in application code:

```python
import logging

logger = logging.getLogger(__name__)

def process_payment(user_id: int, amount: float) -> dict:
    logger.info("Processing payment", extra={"user_id": user_id, "amount": amount})

    try:
        result = payment_gateway.charge(user_id, amount)
        logger.info("Payment successful", extra={"transaction_id": result.id})
        return result
    except PaymentGatewayError as e:
        # logger.exception includes traceback automatically
        logger.exception(
            "Payment failed",
            extra={"user_id": user_id, "error_code": e.code}
        )
        raise
    except Exception as e:
        logger.critical("Unexpected payment error", exc_info=True)
        raise
```

**What to log and what not to log:**

Good log targets: HTTP request metadata (method, path, response status, duration in ms), business events (user registered, order placed, payment processed), error conditions with context (which user, which resource, what was attempted), startup and shutdown events, configuration loaded.

Never log: passwords, hashed passwords, API keys, OAuth tokens, session tokens, credit card numbers, full social security numbers, personally identifiable information (PII), or the full body of requests/responses that might contain any of the above.

For Docker/container deployments, the standard is to log to stdout and let the container runtime (Docker, Kubernetes) handle log routing. Kubernetes captures container stdout and makes it available via `kubectl logs`. Log aggregation agents (Fluentd, Fluent Bit, Promtail) tail the container logs and forward them to Elasticsearch (ELK) or Loki (Grafana stack).

---

## How It Connects

Structured logging (JSON logs) is the next step from plain text logs  -  it makes the `extra={}` fields queryable in log aggregation systems.

[[structured-logging|Structured Logging]]

FastAPI middleware can log every request's method, path, status code, and response time  -  a logging middleware that wraps every handler.

[[fastapi-middleware|Middleware in FastAPI]]

Sentry captures exceptions at ERROR/CRITICAL level with full context, complementing log-based observability with error aggregation and alerting.

[[sentry|Sentry]]

---

## Common Misconceptions

Misconception 1: "DEBUG level should be enabled in production for maximum visibility."
Reality: DEBUG level generates enormous log volume  -  every database query, every internal function call, every HTTP header. In production this volume is both expensive to store and impossible to navigate. Set production to INFO or WARNING, and use DEBUG only when actively diagnosing a specific problem. Configure this via an environment variable so it can be changed without redeployment.

Misconception 2: "Writing logs to a file inside a Docker container is equivalent to logging to stdout."
Reality: Files written inside a container's filesystem are lost when the container is removed. Container log infrastructure (Docker daemon, Kubernetes log rotation, Fluentd agents) is designed to collect stdout, not arbitrary files inside containers. Log to stdout in containerized environments; let the infrastructure handle persistence and aggregation.

Misconception 3: "Including detailed error context in logs (like full exception messages) is sufficient for debugging."
Reality: Log messages should include context about what was being attempted and with what inputs (user_id, resource_id, operation type), not just the exception message. An error log that says `"ValueError: invalid literal for int() with base 10: 'abc'"` without context is nearly useless. An error log that includes `{"user_id": 42, "field": "age", "input": "abc", "error": "ValueError"}` tells you exactly what happened and where to look.

---

## Why It Matters in Practice

Mean Time to Resolution (MTTR)  -  the time from when an incident is detected to when it is resolved  -  is directly correlated with log quality. A team with structured, appropriately leveled, centralized logs can diagnose most production incidents from their desk in minutes. A team with ad-hoc print statements, no log levels, or logs that contain noise but not the relevant context spends hours SSHing into machines and guessing.

Log retention policy also matters. Storing DEBUG logs for 90 days costs far more than storing INFO logs for 30 days. Setting appropriate levels in production and configuring retention based on severity level is an operational cost decision as much as a technical one.

---

## Interview Angle

Common question forms:
- "How do you approach logging in a production Python application?"
- "What is the difference between the logging levels?"

Answer frame:
Describe the five levels and their intended use cases. Explain the logger hierarchy and propagation (child loggers -> parent -> root). Describe the production setup: log to stdout in containers, use `RotatingFileHandler` for non-containerized. Mention centralized logging (ELK, Loki) and the log aggregation agent pattern. Emphasize what not to log (PII, credentials). A strong answer mentions `logger.exception()` for automatic traceback inclusion.

---

## Related Notes

- [[structured-logging|Structured Logging]]
- [[metrics-and-monitoring|Metrics and Monitoring]]
- [[sentry|Sentry]]
