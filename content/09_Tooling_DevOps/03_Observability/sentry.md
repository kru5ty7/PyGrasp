---
title: 06 - Sentry
description: "Sentry is an error monitoring platform that captures unhandled exceptions with full context, groups them by root cause, tracks their frequency across releases, and provides performance monitoring — integrated into Python applications with a single sentry_sdk.init() call."
tags: [sentry, error-monitoring, exception-tracking, performance-monitoring, release-tracking, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Sentry

> Sentry is an error monitoring service that captures exceptions in production with their full stack trace, local variable state, and request context — grouping duplicate errors, tracking their frequency across releases, and alerting when error rates spike.

---

## Quick Reference

**Core idea:**
- `sentry_sdk.init(dsn="...", traces_sample_rate=0.1)` — minimal setup; integrations auto-detected
- Sentry captures unhandled exceptions automatically once initialized
- Captures: exception type and message, full stack trace, local variables at each frame, HTTP request metadata
- Release tracking: `release="v1.5.0"` in `init()` — shows which release introduced or fixed an error
- `sentry_sdk.capture_exception(e)` — manually capture a handled exception
- `sentry_sdk.capture_message("event", level="warning")` — send a non-exception event

**Tricky points:**
- PII scrubbing is not automatic — Sentry captures request data and local variables which may contain personal data; configure `before_send` to scrub sensitive fields
- Sampling rate `traces_sample_rate` controls performance monitoring traces (expensive); `sample_rate` controls error event sampling (usually 1.0 for all errors)
- Sentry integrates automatically with FastAPI, Django, SQLAlchemy, Celery, HTTPX — detected at `init()` time; no additional code for these frameworks
- `with sentry_sdk.push_scope() as scope: scope.set_user({"id": user_id})` — attaches user identity to all events in the scope
- Sentry's performance monitoring is separate from distributed tracing via OpenTelemetry — they can coexist but overlap

---

## What It Is

Sentry occupies a specific niche in the observability landscape: it is the tool that tells you what went wrong, for which users, in which release, and how many times. Logs capture errors as text records that must be searched and parsed. Metrics measure error rates as aggregate numbers. Sentry captures each error as a rich event with the full context of what was happening when it occurred — the stack trace across every frame, the local variables at each frame, the HTTP request that triggered it, the user who was affected, and the application release that introduced it.

The grouping capability is what makes Sentry operationally valuable. In a service handling millions of requests, the same underlying bug might produce thousands of error events per day. Logs would show thousands of individual error lines. Sentry groups these into a single "issue" based on the error type and the stack trace — you see "TypeError in payment/processor.py:line 142, occurring 3,847 times today, first seen in release v1.4.0." A single issue to investigate, not thousands of log lines to parse.

Release tracking connects error data to the deployment lifecycle. When a release is marked as deployed in Sentry (automatically or via the CI/CD pipeline), Sentry shows which issues are new in that release, which were resolved, and which regressions appeared. This makes the deployment process observable: "we deployed v1.5.0 at 14:00, and a new error in the payment module started appearing at 14:02" is immediately visible in Sentry's release view, pointing directly to the regression.

---

## How It Actually Works

**Minimal setup for FastAPI:**

```python
# main.py
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration
from sentry_sdk.integrations.httpx import HttpxIntegration

sentry_sdk.init(
    dsn="https://abc123@sentry.io/456789",
    release="v1.5.0",                    # Current version
    environment="production",            # "staging", "development"
    traces_sample_rate=0.1,             # Sample 10% of requests for performance
    profiles_sample_rate=0.1,           # CPU profiling (optional)
    integrations=[
        FastApiIntegration(),
        SqlalchemyIntegration(),
        HttpxIntegration(),
    ],
    # PII scrubbing
    send_default_pii=False,             # Do not send IP addresses, cookies
    before_send=scrub_sensitive_data,   # Custom scrubbing function
)
```

**PII scrubbing with `before_send`:**

```python
def scrub_sensitive_data(event: dict, hint: dict) -> dict | None:
    """Remove sensitive fields from Sentry events before sending."""

    # Scrub request body if it contains sensitive fields
    if "request" in event and "data" in event["request"]:
        data = event["request"]["data"]
        for field in ["password", "token", "api_key", "credit_card"]:
            if field in data:
                data[field] = "[REDACTED]"

    # Scrub specific local variables from stack frames
    if "exception" in event:
        for exc_value in event["exception"].get("values", []):
            for frame in exc_value.get("stacktrace", {}).get("frames", []):
                vars_ = frame.get("vars", {})
                for sensitive_key in ["password", "secret", "token"]:
                    if sensitive_key in vars_:
                        vars_[sensitive_key] = "[REDACTED]"

    return event  # Return None to discard the event entirely
```

**Setting user context:**

```python
import sentry_sdk
from fastapi import Request

async def set_sentry_user(request: Request, call_next):
    """Middleware to attach authenticated user to Sentry events."""
    with sentry_sdk.push_scope() as scope:
        if hasattr(request.state, "user"):
            scope.set_user({
                "id": request.state.user.id,
                "email": request.state.user.email,  # only if GDPR allows
                "username": request.state.user.username,
            })
        response = await call_next(request)
    return response
```

**Manual capture for handled exceptions:**

```python
import sentry_sdk

def process_payment(user_id: int, amount: float):
    try:
        result = payment_gateway.charge(user_id, amount)
        return result
    except SoftPaymentError as e:
        # Handled gracefully, but still worth tracking in Sentry
        with sentry_sdk.push_scope() as scope:
            scope.set_tag("payment.failure_type", "soft_decline")
            scope.set_extra("user_id", user_id)
            scope.set_extra("amount", amount)
            sentry_sdk.capture_exception(e)
        return {"status": "declined", "reason": str(e)}
    except Exception as e:
        # Unhandled — Sentry would capture this automatically,
        # but capturing here lets us add context
        sentry_sdk.capture_exception(e)
        raise
```

**Breadcrumbs** are a timeline of events leading up to an exception, automatically recorded by Sentry integrations:

```python
sentry_sdk.add_breadcrumb(
    category="payment",
    message="Initiating gateway charge",
    data={"amount": amount, "gateway": "stripe"},
    level="info"
)
```

When an exception is captured, Sentry includes the last N breadcrumbs as context — showing what sequence of events led to the error.

---

## How It Connects

Sentry complements structured logging — logs provide a searchable stream of all events; Sentry provides error aggregation and alerting for specific error conditions.

[[structured-logging|Structured Logging]]

OpenTelemetry and Sentry both perform distributed tracing — Sentry's performance monitoring creates traces from its SDK, while OpenTelemetry is vendor-neutral. The two can coexist but serve similar purposes.

[[opentelemetry|OpenTelemetry]]

In a CI/CD pipeline, the release version passed to `sentry_sdk.init()` should match the git tag or semantic version used in the deployment — connecting Sentry issues to specific code changes.

[[semantic-versioning|Semantic Versioning]]

---

## Common Misconceptions

Misconception 1: "Sentry captures all exceptions, so I do not need to add any custom instrumentation."
Reality: Sentry automatically captures unhandled exceptions — exceptions that propagate to the top of the call stack without being caught. Exceptions that are caught and handled (e.g., a retry that eventually succeeds) are invisible to Sentry unless explicitly captured with `sentry_sdk.capture_exception()`. Soft failures, business logic errors that do not raise exceptions, and slow operations require explicit instrumentation.

Misconception 2: "Using Sentry with `send_default_pii=True` is fine because the data is encrypted in transit."
Reality: Sentry stores captured data on their servers (or self-hosted). Sending PII (IP addresses, cookies, user emails, full request bodies with form data) means that data is stored outside your control. Many privacy regulations (GDPR, CCPA) restrict sending PII to third-party processors without explicit consent. Use `send_default_pii=False` and the `before_send` hook to explicitly control what is sent.

Misconception 3: "High `traces_sample_rate` gives better observability."
Reality: Performance traces in Sentry (the `traces_sample_rate` parameter) cost money and generate data volume. At a high request rate, `traces_sample_rate=1.0` can generate enormous data volume and significant cost. `0.1` (10%) is a reasonable starting point for most services. Error events (`sample_rate`) should typically be `1.0` — you want to capture all errors, but you can sample performance traces.

---

## Why It Matters in Practice

The operational impact of Sentry is most visible in the gap it fills between "a user reported an error" and "we identified the root cause." Without Sentry, the workflow is: user reports error → find relevant logs → identify error message → search for stack trace → identify failing code → understand what state the application was in. With Sentry, the workflow is: receive Sentry alert with issue link → click issue → see stack trace, local variables, request context, user identity, and the last 20 breadcrumbs. The investigation time drops from an hour to minutes.

The regression detection capability — seeing which new errors appeared in each release — makes deployment safer. A team that deploys and immediately checks Sentry's release view can catch regressions within minutes of deployment. If error rates spike after a deployment, rollback is still straightforward. Left unchecked for hours, regressions compound and become harder to attribute.

---

## Interview Angle

Common question forms:
- "How do you monitor errors in production for a Python application?"
- "What is the difference between Sentry and logging?"

Answer frame:
Describe Sentry as an error aggregation platform (not just logging) — it groups identical errors, provides rich context (stack trace, variables, request context), and tracks errors across releases. Contrast with logs: logs are a stream of all events; Sentry surfaces specific error conditions with enough context to diagnose them immediately. Mention `before_send` for PII scrubbing as a GDPR/security concern. Describe `traces_sample_rate` (performance monitoring, sample < 1.0) vs `sample_rate` (error events, usually 1.0).

---

## Related Notes

- [[logging-production|Production Logging]]
- [[structured-logging|Structured Logging]]
- [[opentelemetry|OpenTelemetry]]
- [[metrics-and-monitoring|Metrics and Monitoring]]
