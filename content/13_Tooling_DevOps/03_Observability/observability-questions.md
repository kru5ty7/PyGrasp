---
title: 07 - Observability Question Bank
description: "Platform-engineering interview questions on observability - metrics vs logs vs traces, how Prometheus scrapes and stores metrics, metric types and PromQL basics, SLI/SLO/error budgets, alert design, and a latency-spike triage walkthrough."
tags: [observability, prometheus, grafana, sli, slo, error-budget, alerting, interview-prep, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-06
---

# Observability Question Bank

> Interview prep — Platform Engineering. Concepts transfer even when the named stack (Prometheus/Grafana/ELK) is a gap: metrics vs logs vs traces, SLI/SLO discipline, and alert design are stack-independent. Do not claim to have run Prometheus if you haven't — lead with the real stack, then the concepts.

---

## The Three Pillars

**Q: Metrics vs logs vs traces — when is each the right tool?**

Answer frame: metrics are cheap aggregated numbers for trends and alerting ("error rate is rising" — [[metrics-and-monitoring|Metrics and Monitoring]]); logs are discrete events with full context for the *why* ("this request failed with this stack trace" — [[logging-production|Production Logging]], [[structured-logging|Structured Logging]]); traces follow one request across service boundaries for the *where* ("the latency lives in this downstream call" — [[opentelemetry|OpenTelemetry]]). Detection with metrics, localization with traces, explanation with logs.

---

## Prometheus

**Q: How does Prometheus scrape and store metrics? Histogram vs counter vs gauge. PromQL basics.**

Answer frame: pull model — Prometheus scrapes `/metrics` HTTP endpoints on an interval and stores samples in a local time-series database, with service discovery (e.g. Kubernetes pod annotations) finding targets automatically ([[prometheus-python|Prometheus with Python]]). Counter = monotonically increasing (requests served; query with `rate()`); gauge = value that goes both ways (memory in use, queue depth); histogram = observations in buckets, enabling percentile estimates via `histogram_quantile()` — latency SLOs are computed from histograms. PromQL basics worth having cold: `rate(http_requests_total{status=~"5.."}[5m])` for error rate; RED method (rate, errors, duration) as the framework for what to instrument.

---

## SLI / SLO / Error Budgets

**Q: Define SLI, SLO, and error budget. Design alerts that don't page at 3am for noise.**

Answer frame: SLI = a measured indicator of service health (proportion of successful requests, latency under threshold); SLO = the target on that SLI (99.9% over 30 days); error budget = 1 − SLO, the allowed unreliability — spend it on shipping, freeze features when it's exhausted. Alerting: page on user-impacting symptoms (SLO burn rate), not causes (CPU high); multi-window burn-rate alerts catch fast burns quickly and slow burns eventually; everything that isn't actionable at 3am becomes a ticket, not a page.

---

## Triage Walkthrough

**Q: You're paged for a latency spike on a platform API — walk through triage.**

Answer frame: confirm real user impact (dashboards: p50 vs p99, error rate, traffic); scope it (all routes or one, all consumers or one, one AZ/node or all); correlate with change events (deploys, config, dependency releases — the most common cause); check saturation (CPU throttling, memory pressure, connection pools, downstream latency via traces); mitigate first (roll back, shed load, scale) and root-cause after; write it up blameless. The order matters: mitigate before diagnose when users are hurting.

---

## Gap-Probe

**Q: "What did you actually use for monitoring in your last role?"** — real stack first (e.g. CloudWatch, centralized logging, uptime SLAs — [[cloudwatch|CloudWatch]]), then map each concept above onto it, then state plainly that Prometheus/Grafana specifically is prep-level knowledge, not production experience.

---

## Related Notes

- [[metrics-and-monitoring|Metrics and Monitoring]]
- [[prometheus-python|Prometheus with Python]]
- [[logging-production|Production Logging]]
- [[structured-logging|Structured Logging]]
- [[opentelemetry|OpenTelemetry]]
- [[cloudwatch|CloudWatch]]
- [[cicd-design-questions|CI/CD Design Question Bank]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
