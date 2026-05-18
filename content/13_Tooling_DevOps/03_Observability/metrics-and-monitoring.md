---
title: 03 - Metrics and Monitoring
description: "Metrics are numeric time-series measurements of application behavior  -  Prometheus defines four types (counter, gauge, histogram, summary) and the RED method (rate, errors, duration) provides a systematic framework for choosing which metrics to instrument."
tags: [metrics, monitoring, prometheus, counter, gauge, histogram, red-method, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Metrics and Monitoring

> Metrics are numeric time-series measurements  -  counters that only go up, gauges that go up and down, histograms that capture value distributions  -  and the RED method (rate, errors, duration) tells you which three metrics to collect for any service to know if it is healthy.

---

## Quick Reference

**Core idea:**
- **Counter**: monotonically increasing integer  -  resets only on restart (total requests, total errors)
- **Gauge**: current value that can increase or decrease (active connections, memory usage, queue depth)
- **Histogram**: samples values into configurable buckets and tracks count and sum (request duration, payload size)
- **Summary**: similar to histogram but calculates quantiles (p50, p95, p99) on the client side
- **RED method**: **R**ate (requests per second), **E**rrors (error rate), **D**uration (latency distribution)
- **USE method**: **U**tilization, **S**aturation, **E**rrors  -  for infrastructure resources (CPU, disk, network)

**Tricky points:**
- Counters never decrease except on process restart  -  computing the rate of a counter requires `rate(counter[5m])` in PromQL, not reading the raw value
- Histogram buckets must be configured before deployment  -  adding or changing buckets requires a restart; choose bucket boundaries that cover your expected latency distribution
- Summary quantiles are calculated in the application process and cannot be aggregated across instances; histograms can be aggregated, making them preferable for multi-instance services
- Cardinality is the enemy of metrics: each unique combination of label values creates a new time series; do not use high-cardinality values (user_id, order_id) as metric labels
- `rate()` vs `irate()` in PromQL: `rate()` is the per-second average over the range; `irate()` is the instantaneous rate based on the last two samples  -  use `rate()` for dashboards, `irate()` for alerts

---

## What It Is

Metrics are the quantitative heartbeat of a running system. Logs tell you what happened  -  specific events with details. Traces tell you how a specific request flowed through the system. Metrics tell you the aggregate state of the system: how many requests are being processed per second, what percentage are failing, how long they take. These aggregate numbers are what monitoring systems use to detect anomalies, trigger alerts, and populate operational dashboards.

The RED method is a three-question framework for any service that handles requests: what is the rate of requests (requests per second)? What is the error rate (fraction of requests that fail)? What is the duration distribution (latency at p50, p95, p99)? These three metrics are sufficient to know whether a service is healthy and to characterize its performance. If rate drops, traffic may be lost. If error rate rises, something is failing. If duration increases, something is slowing down. A dashboard that shows these three metrics for every service is the foundation of operational visibility.

Prometheus is the de facto standard for metrics collection in cloud-native systems. It uses a pull model: the Prometheus server periodically scrapes an HTTP endpoint (typically `/metrics`) on each application instance. The application exposes its current metric values at this endpoint, and Prometheus stores the scraped data as time series. The Prometheus Query Language (PromQL) enables complex aggregations: sum across instances, rate over time, percentile calculations from histogram data. Grafana sits on top of Prometheus and renders dashboards from PromQL queries.

---

## How It Actually Works

The four metric types map to different measurement needs:

**Counter**  -  always increasing:
```python
from prometheus_client import Counter

request_total = Counter(
    "http_requests_total",
    "Total HTTP requests received",
    ["method", "endpoint", "status_code"]  # Labels
)

# Increment
request_total.labels(method="GET", endpoint="/api/users", status_code="200").inc()

# In PromQL: rate of requests per second over last 5 minutes
# rate(http_requests_total[5m])

# Error rate:
# rate(http_requests_total{status_code=~"5.."}[5m])
#   / rate(http_requests_total[5m])
```

**Gauge**  -  current value:
```python
from prometheus_client import Gauge

active_connections = Gauge(
    "active_database_connections",
    "Number of active database connections"
)

active_connections.set(10)   # Set to value
active_connections.inc()     # Increment
active_connections.dec()     # Decrement

# Context manager for tracking in-progress operations
in_progress = Gauge("requests_in_progress", "Requests currently being processed")

with in_progress.track_inprogress():
    process_request()
```

**Histogram**  -  distribution of values:
```python
from prometheus_client import Histogram

request_duration = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)

# Observe a duration
request_duration.labels(method="POST", endpoint="/api/payments").observe(0.245)

# Context manager for timing
with request_duration.labels(method="GET", endpoint="/api/users").time():
    result = fetch_users()

# In PromQL: p95 latency
# histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

**RED method implementation** for a FastAPI service:

The three RED metrics map directly to Prometheus instruments:
- Rate -> `rate(http_requests_total[5m])`
- Errors -> `rate(http_requests_total{status_code=~"5.."}[5m]) / rate(http_requests_total[5m])`
- Duration -> `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))`

**Cardinality warning**  -  the reason labels must be low-cardinality:

```python
# WRONG: user_id can have millions of values  -  creates millions of time series
request_total = Counter("requests", "Total", ["user_id"])
request_total.labels(user_id=str(request.user_id)).inc()  # Never do this

# CORRECT: status code has a small, bounded set of values
request_total = Counter("requests", "Total", ["status_code"])
request_total.labels(status_code=str(response.status_code)).inc()
```

Each unique combination of label values creates a separate time series in Prometheus's storage. Labels with millions of unique values (user IDs, order IDs, session tokens) create millions of time series, exhausting memory and degrading performance. Labels must be low-cardinality: fewer than a few hundred distinct values.

---

## How It Connects

Prometheus with Python shows the specific `prometheus_client` library code for exposing metrics from a FastAPI application and configuring the scrape endpoint.

[[prometheus-python|Prometheus with Python]]

OpenTelemetry is a standardized metrics (and traces, and logs) API  -  it can export to Prometheus as one of its backends.

[[opentelemetry|OpenTelemetry]]

Structured logs and metrics are complementary: metrics answer "how many" and "how long" at aggregate; logs answer "what happened" for specific events.

[[structured-logging|Structured Logging]]

---

## Common Misconceptions

Misconception 1: "I should track every user action as a metric with user_id as a label."
Reality: Metrics are for aggregate statistics, not individual events. User-level granularity belongs in logs or traces. Metrics labels must be low-cardinality  -  a small, bounded set of values. Using user_id as a label creates one time series per user, which at scale exhausts Prometheus memory and storage. Track events per endpoint, per status code, per operation type  -  never per user or per entity ID.

Misconception 2: "A counter at value 10,000 means 10,000 things happened recently."
Reality: A counter is monotonically increasing from zero at process startup. It tells you the cumulative total since the process started. To find out how many things happened recently, you need the rate: `rate(my_counter[5m])` gives the per-second rate over the last 5 minutes. Raw counter values are only meaningful when compared to themselves at different times.

Misconception 3: "Summary and Histogram are interchangeable  -  both calculate percentiles."
Reality: They calculate percentiles differently and have different aggregation properties. A Summary calculates quantiles (p95, p99) in the application process over a sliding time window. A Histogram counts samples in pre-defined buckets and defers quantile calculation to the query time (via `histogram_quantile()`). Critically, Histograms can be aggregated across instances (sum the buckets from all pods, then calculate quantile); Summaries cannot. For multi-instance services, Histograms are almost always the right choice.

---

## Why It Matters in Practice

Metrics-based alerting is the operational model that enables on-call rotations to function. An alert rule like "error rate above 1% for 5 minutes -> page on-call" is only possible with the right metrics properly labeled. Without metrics, on-call engineers must manually check logs and dashboards to determine if something is wrong  -  reactive rather than proactive.

The RED method's value is in providing a consistent vocabulary for discussing service health. Every service gets the same three fundamental metrics. A dashboard that shows rate, error rate, and p95 latency for every microservice in the system makes it possible to identify which service is misbehaving during an incident in seconds, rather than checking each service's idiosyncratic metrics.

---

## Interview Angle

Common question forms:
- "What types of metrics would you instrument on a web service?"
- "What is the difference between a counter and a gauge?"

Answer frame:
Describe the four Prometheus metric types with examples (counter for request totals, gauge for active connections, histogram for latency). Explain the RED method as a framework for what to measure. Cover the cardinality warning  -  high-cardinality labels are a common operational mistake. Distinguish Histogram from Summary (Histogram is aggregatable across instances; Summary is not). A strong answer mentions PromQL rate() for counter interpretation.

---

## Related Notes

- [[prometheus-python|Prometheus with Python]]
- [[opentelemetry|OpenTelemetry]]
- [[structured-logging|Structured Logging]]
- [[logging-production|Production Logging]]
