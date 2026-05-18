---
title: 05 - OpenTelemetry
description: "OpenTelemetry is a vendor-neutral observability framework unifying traces, metrics, and logs under one API  -  traces follow requests as they cross service boundaries via spans with trace IDs, and auto-instrumentation hooks into FastAPI and common libraries without code changes."
tags: [opentelemetry, otel, tracing, spans, traces, observability, auto-instrumentation, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# OpenTelemetry

> OpenTelemetry is the vendor-neutral standard for observability  -  it provides a single API for collecting traces (how a request flows through services), metrics (what is measured), and logs (what happened), exporting all three to any compatible backend without changing instrumentation code.

---

## Quick Reference

**Core idea:**
- **Traces**: records of a request's journey  -  from entry point through all downstream calls, as a tree of spans
- **Span**: one unit of work within a trace (one HTTP call, one DB query, one function call)
- **Trace ID**: a single identifier shared by all spans in one request  -  links spans across services
- **OTLP**: OpenTelemetry Protocol  -  the standard wire format for exporting telemetry to backends (Jaeger, Tempo, Datadog)
- `opentelemetry-instrument fastapi-app`  -  zero-code auto-instrumentation via a wrapper command
- `from opentelemetry import trace; tracer = trace.get_tracer(__name__)`  -  manual instrumentation API

**Tricky points:**
- Auto-instrumentation uses monkey-patching to hook into framework and library code at startup  -  it works without code changes but captures only what the auto-instrumentation packages know about
- Trace context propagation across HTTP services requires the calling service to send the `traceparent` W3C header, and the receiving service to extract and continue the trace
- Sampling rate is critical for high-traffic services  -  tracing every request can be costly; `TraceIdRatioBased(0.1)` samples 10% of requests
- The OTLP exporter sends spans to a collector (OpenTelemetry Collector, or directly to a backend) asynchronously  -  application performance is minimally affected
- OpenTelemetry's metrics API can replace `prometheus_client` in new projects  -  but check that the target backend supports OTLP metrics (Prometheus scraping still requires the Prometheus exporter)

---

## What It Is

OpenTelemetry addresses a problem that arises when running multiple services: understanding how a single user request flows through the system. Logs tell you what each service individually did. Metrics tell you the aggregate health of each service. But neither answers: "this request took 2 seconds  -  which service was slow, and what was it doing?" Distributed tracing is the answer. It follows a request as it crosses service boundaries, records timing at each stage, and assembles all those timings into a tree that shows exactly where time was spent.

A trace is the complete record of one request across all the services it touched. Each discrete operation within that trace  -  an HTTP call to a downstream service, a database query, a background task  -  is recorded as a span. All spans from one request share the same trace ID. When span B was caused by span A, span B records span A's ID as its parent. This parent-child relationship forms the tree structure. The root span is the top-level request entry. Leaf spans are the atomic operations (database queries, cache lookups). In between are service-crossing spans that connect the two.

OpenTelemetry was created by merging the OpenTracing and OpenCensus projects into a single vendor-neutral standard. Before OpenTelemetry, different vendors had proprietary tracing APIs  -  if you instrumented your code with Zipkin's API and later switched to Jaeger, you had to re-instrument everything. OpenTelemetry defines a standard API that any instrumented code writes to, and a set of exporter plugins that translate that API's data to vendor-specific formats. Switch backends by changing the exporter configuration, not the instrumentation code.

---

## How It Actually Works

**Auto-instrumentation** is the zero-code entry point. The `opentelemetry-instrument` command wraps a Python application and patches common libraries at startup:

```bash
pip install \
    opentelemetry-api \
    opentelemetry-sdk \
    opentelemetry-instrumentation-fastapi \
    opentelemetry-instrumentation-sqlalchemy \
    opentelemetry-instrumentation-httpx \
    opentelemetry-exporter-otlp

# Run FastAPI with auto-instrumentation
OTEL_SERVICE_NAME=myapp \
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317 \
opentelemetry-instrument uvicorn main:app
```

This automatically instruments FastAPI routes, SQLAlchemy queries, and HTTPX client calls  -  creating spans for each operation, propagating trace context in HTTP headers, and exporting to the OTLP endpoint.

**Manual instrumentation** for custom operations:

```python
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

tracer = trace.get_tracer(__name__)

async def process_payment(user_id: int, amount: float) -> dict:
    # Start a new span  -  child of the current active span (the HTTP request span)
    with tracer.start_as_current_span("process_payment") as span:
        # Add attributes (searchable metadata) to the span
        span.set_attribute("user.id", user_id)
        span.set_attribute("payment.amount", amount)

        try:
            # This inner call creates its own child span if SQLAlchemy is instrumented
            result = await charge_gateway(user_id, amount)

            span.set_attribute("transaction.id", result.id)
            span.set_status(Status(StatusCode.OK))
            return result

        except PaymentError as e:
            # Record the error on the span
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            raise
```

**SDK configuration** in application startup:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import TraceIdRatioBased
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

def configure_tracing(service_name: str, otlp_endpoint: str, sample_rate: float = 0.1):
    resource = Resource.create({
        "service.name": service_name,
        "service.version": "1.5.0",
        "deployment.environment": "production",
    })

    provider = TracerProvider(
        resource=resource,
        sampler=TraceIdRatioBased(sample_rate),  # Sample 10% of traces
    )

    exporter = OTLPSpanExporter(endpoint=otlp_endpoint)
    provider.add_span_processor(BatchSpanProcessor(exporter))

    trace.set_tracer_provider(provider)
```

**Trace context propagation** between services uses the W3C `traceparent` header. When service A makes an HTTP call to service B using HTTPX with the HTTPX instrumentation package, the instrumentation automatically injects the current trace context into the request headers. Service B's auto-instrumentation extracts the trace context and continues the same trace. All spans from both services share the same trace ID and appear in the same trace in the backend.

---

## How It Connects

Prometheus metrics and OpenTelemetry traces are complementary observability signals  -  metrics answer "how many and how fast" at aggregate, traces answer "what happened for this specific request."

[[metrics-and-monitoring|Metrics and Monitoring]]

Structured logs with a `trace_id` field can be correlated with traces in backends like Grafana Tempo + Loki  -  the same trace_id appears in both logs and traces for the same request.

[[structured-logging|Structured Logging]]

FastAPI middleware and route handlers are the natural places to add manual span attributes  -  custom spans around business logic operations that auto-instrumentation does not capture.

[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "OpenTelemetry tracing and logging are the same thing  -  both record what happened."
Reality: Logs record discrete events as text or structured records: "user 42 logged in at 12:34:56." Traces record the structure and timing of a request across services as a tree of spans. They answer different questions: logs are "what events occurred," traces are "how did this specific request flow and where was time spent." The two are complementary  -  many observability platforms allow linking a trace ID from a span to the corresponding log records.

Misconception 2: "Auto-instrumentation captures everything I need  -  I do not need to add manual spans."
Reality: Auto-instrumentation captures framework-level operations: HTTP request handling, database queries, cache calls. It does not capture business logic. If you want to trace "how long did payment validation take" vs "how long did the gateway call take" vs "how long did the fraud check take," those internal breakdowns require manual span creation with `tracer.start_as_current_span()`.

Misconception 3: "I should trace 100% of requests to have complete observability."
Reality: At high traffic volumes (thousands of requests per second), storing and processing every trace is prohibitively expensive. Sampling 1 - 10% of traces is typically sufficient for performance analysis because performance characteristics are consistent across requests  -  if p95 latency is 500ms, you do not need to examine every individual request to know that. For errors, tail-based sampling (sample 100% of requests that resulted in an error, 1% of successful requests) provides comprehensive error coverage with controlled volume.

---

## Why It Matters in Practice

Distributed tracing becomes indispensable when diagnosing latency in microservice architectures. When a slow API call is reported, the trace shows: 50ms in the API gateway, 10ms in the authentication service, 1200ms in the payment service (breakdown: 20ms in validation, 1150ms in the charge_gateway span). The problem is immediately localized  -  the payment gateway API is slow. Without tracing, this diagnosis requires correlating logs across three services and guessing at timing.

The vendor-neutral standard matters for longevity. Instrumenting code with OpenTelemetry's API means the instrumentation code never changes when switching from Jaeger to Grafana Tempo to Datadog. Only the exporter configuration changes. For organizations that expect to evolve their observability stack, this is a meaningful investment in maintainability.

---

## Interview Angle

Common question forms:
- "How would you implement distributed tracing in a microservice Python application?"
- "What are the three pillars of observability?"

Answer frame:
Describe the three pillars: logs (events), metrics (aggregates), traces (request flows). Explain traces as trees of spans with a shared trace ID  -  the trace ID enables correlating spans across service boundaries. Describe the OTLP exporter model (vendor-neutral, swappable backend). Mention auto-instrumentation for zero-code setup and manual spans for business logic. Note sampling as the performance trade-off for high-traffic services.

---

## Related Notes

- [[metrics-and-monitoring|Metrics and Monitoring]]
- [[prometheus-python|Prometheus with Python]]
- [[structured-logging|Structured Logging]]
- [[sentry|Sentry]]
- [[fastapi|FastAPI]]
