---
title: 46 - CloudWatch
description: CloudWatch is AWS's monitoring and observability service — it centralises logs, metrics, and alarms from all AWS services and your own application code into a single, queryable platform.
tags: [aws, cloud, layer-11, cloudwatch, monitoring, logging]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# CloudWatch

> CloudWatch is the observability backbone of AWS — Lambda execution logs, custom application metrics, and infrastructure alarms all flow through it, making it the first place you look when something breaks in production.

---

## Quick Reference

**Core idea:**
- Three pillars: Logs (centralised log storage and search), Metrics (numeric time-series), Alarms (trigger actions on metric thresholds)
- Lambda automatically writes stdout/stderr to CloudWatch Logs (log group `/aws/lambda/<function-name>`)
- Custom metrics: `put_metric_data` API or Embedded Metrics Format (EMF) via structured log lines
- Log Insights: SQL-like query language for searching and aggregating log data
- Alarms: trigger SNS notifications, Auto Scaling actions, or Lambda functions when metrics breach thresholds
- Costs money at scale — log ingestion, storage, metric API calls, and alarm evaluations all have per-unit pricing

**Tricky points:**
- CloudWatch Logs are organised into log groups (per service/function) and log streams (per execution environment)
- Lambda log groups are not deleted when you delete the function — clean them up explicitly
- Default CloudWatch Logs retention: indefinite (and billed indefinitely) unless you set a retention policy
- The Embedded Metrics Format (EMF) lets you emit custom metrics as structured log lines — no separate PutMetricData calls
- CloudWatch metric resolution: standard is 1-minute granularity; high-resolution metrics are 1-second but cost 3x more

---

## What It Is

CloudWatch is the nerve system of an AWS account. Think of it as a hospital's monitoring room where every patient (AWS service or application instance) is connected to sensors (log agents, metric reporters). The monitoring room displays all vital signs in real time (CloudWatch Metrics dashboards), records a complete history of readings (CloudWatch Logs), and sounds an alarm when a reading goes out of the normal range (CloudWatch Alarms). A developer on call does not visit each server to check its health; they look at the monitoring room.

Logs in CloudWatch are organised hierarchically: log groups contain log streams. For Lambda, each function gets one log group (`/aws/lambda/function-name`), and each execution environment within that function gets its own log stream. When Lambda scales to 100 concurrent executions, there are 100 active log streams simultaneously writing to the same log group. CloudWatch Logs Insights queries run across all streams in a log group simultaneously, which makes it possible to find a specific error across all concurrent Lambda executions in a single query.

Metrics are numeric time-series. AWS services emit dozens of standard metrics automatically — Lambda emits `Invocations`, `Errors`, `Duration`, `ConcurrentExecutions`, `Throttles`, and `ColdStartCount`. Your application code can emit custom metrics that represent business events: number of orders processed, fraud detection scores, cache hit rates. Custom metrics are the bridge between infrastructure health and business health. An alarm on `Errors > 5` tells you something is wrong; an alarm on `OrdersProcessed < 100 in the last 5 minutes during business hours` tells you revenue is at risk.

---

## How It Actually Works

The Embedded Metrics Format (EMF) is the most efficient way to emit custom metrics from Lambda. Instead of making a separate `put_metric_data` API call (which adds latency to each invocation), you write a specially structured JSON log line that CloudWatch Logs automatically parses into a metric. The Lambda function's logging output doubles as metric reporting — one operation, two observable outputs.

```python
import json
import logging
import os
import time
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# --- Custom metric via Embedded Metrics Format (EMF) ---
def emit_metric(metric_name: str, value: float, unit: str = "Count", **dimensions):
    """
    Emit a custom CloudWatch metric as a structured EMF log line.
    No additional API call — CloudWatch Logs parses this automatically.
    """
    emf_record = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": os.environ.get("METRICS_NAMESPACE", "MyApp"),
                "Dimensions": [list(dimensions.keys())],
                "Metrics": [{"Name": metric_name, "Unit": unit}],
            }],
        },
        metric_name: value,
        **dimensions,
    }
    # EMF records must be printed to stdout, not via the standard logger
    print(json.dumps(emf_record))


def handler(event, context):
    start_time = time.time()

    try:
        records_processed = process_batch(event.get("Records", []))

        duration_ms = (time.time() - start_time) * 1000
        emit_metric("RecordsProcessed", records_processed, "Count", FunctionName=context.function_name)
        emit_metric("ProcessingDuration", duration_ms, "Milliseconds", FunctionName=context.function_name)

        logger.info(json.dumps({
            "event": "batch_processed",
            "records": records_processed,
            "duration_ms": round(duration_ms, 2),
            "request_id": context.aws_request_id,
        }))

        return {"statusCode": 200, "body": json.dumps({"processed": records_processed})}

    except Exception as exc:
        emit_metric("ProcessingErrors", 1, "Count", FunctionName=context.function_name)
        logger.exception(json.dumps({
            "event": "batch_failed",
            "error": str(exc),
            "request_id": context.aws_request_id,
        }))
        raise


def process_batch(records):
    return len(records)


# --- Custom metric via PutMetricData API (for non-Lambda contexts) ---
def put_custom_metric(metric_name: str, value: float, namespace: str = "MyApp"):
    cloudwatch = boto3.client("cloudwatch", region_name="us-east-1")
    cloudwatch.put_metric_data(
        Namespace=namespace,
        MetricData=[{
            "MetricName": metric_name,
            "Value": value,
            "Unit": "Count",
            "Dimensions": [
                {"Name": "Environment", "Value": os.environ.get("STAGE", "dev")},
            ],
        }],
    )
```

Creating a CloudWatch Alarm that fires when Lambda error rate exceeds 1% and notifies an SNS topic:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name lambda-high-error-rate \
    --alarm-description "Lambda error rate > 1% over 5 minutes" \
    --namespace AWS/Lambda \
    --metric-name Errors \
    --dimensions Name=FunctionName,Value=my-api-function \
    --statistic Sum \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 1 \
    --comparison-operator GreaterThanThreshold \
    --treat-missing-data notBreaching \
    --alarm-actions arn:aws:sns:us-east-1:123456789012:ops-alerts
```

Querying Lambda cold start durations with CloudWatch Logs Insights:

```bash
aws logs start-query \
    --log-group-name "/aws/lambda/my-api-function" \
    --start-time $(date -d "24 hours ago" +%s) \
    --end-time $(date +%s) \
    --query-string '
        filter @type = "REPORT"
        | stats
            avg(@initDuration) as avg_cold_start_ms,
            max(@initDuration) as max_cold_start_ms,
            count(@initDuration) as cold_start_count,
            avg(@duration) as avg_duration_ms
          by bin(1h)
        | sort by bin(1h) asc
    '
```

Setting a log group retention policy to control costs:

```bash
aws logs put-retention-policy \
    --log-group-name "/aws/lambda/my-api-function" \
    --retention-in-days 30
```

---

## How It Connects

CloudWatch Logs is the default output destination for Lambda functions and the primary debugging tool for production Lambda issues. The structured logging patterns described in the handlers note are designed specifically to be queryable with CloudWatch Logs Insights.

[[lambda-handlers|Lambda Handlers]] — the structured JSON logging pattern used in Lambda handlers is what makes CloudWatch Logs Insights queries effective; the two notes are companion pieces.

Alarms in CloudWatch are commonly configured to trigger SNS notifications when metrics breach thresholds, completing the observability-to-alerting pipeline.

[[sns|SNS (Simple Notification Service)]] — CloudWatch Alarms frequently use SNS as their notification action to fan out alerts to email, PagerDuty, Slack webhooks, or Lambda functions.

---

## Common Misconceptions

Misconception 1: CloudWatch Logs retention is free — logs are stored indefinitely at no cost.
Reality: CloudWatch Logs charges for both ingestion (per GB written) and storage (per GB per month stored). A high-traffic Lambda function that logs 1GB per day with indefinite retention accumulates storage costs continuously. Always set a retention policy on every log group — 30 days is sufficient for debugging; longer retention for compliance purposes belongs in S3 with log archival.

Misconception 2: Using the Python `logging` module in Lambda automatically formats logs in a way that CloudWatch Logs Insights can query efficiently.
Reality: The default Python logging format produces unstructured text (`2026-05-18 INFO handler.py:42 Processing request`). CloudWatch Logs Insights can search it, but structured JSON logs (`{"event": "request_received", "request_id": "abc", "method": "POST"}`) are far more efficient to query and filter because Logs Insights can use field-level indexing on JSON properties. Always use `json.dumps` to emit structured log lines in Lambda.

---

## Why It Matters in Practice

CloudWatch is unavoidable for AWS workloads — Lambda writes to it automatically, and every AWS service emits metrics to it. The question is not whether to use CloudWatch but how deeply to invest in structured logging, custom metrics, and alarms. Teams that log structured JSON, emit custom business metrics alongside infrastructure metrics, and configure alarms before incidents occur can diagnose and resolve production issues in minutes rather than hours. Teams that log unstructured text and ignore CloudWatch until something breaks spend the critical first hour of an incident trying to understand what is happening.

---

## What Breaks in Production

**Scenario 1: Log group with indefinite retention accumulates unbounded costs**

```bash
# Mistake: deploying Lambda functions without setting log retention
# After 6 months of high-traffic production use, the log storage bill is unexpectedly large

# Fix: set retention on all log groups (automate this via IaC or a Lambda that runs on log group creation)
aws logs describe-log-groups \
    --query "logGroups[?retentionInDays==null].logGroupName" \
    --output text | tr '\t' '\n' | while read group; do
        aws logs put-retention-policy \
            --log-group-name "$group" \
            --retention-in-days 30
    done
```

**Scenario 2: Alarm missing `treat-missing-data` causes false alarm on function restart**

```bash
# Mistake: alarm evaluates "missing data" as BREACHING
# When a function has zero invocations for 5 minutes (legitimate low traffic),
# the Errors metric has no data points, alarm fires as if there were errors

# Fix: set treat-missing-data to notBreaching for count-based alarms
aws cloudwatch put-metric-alarm \
    --alarm-name lambda-errors \
    --treat-missing-data notBreaching \  # no invocations = no errors, not an alarm
    # ... rest of alarm configuration
```

---

## Interview Angle

Common question forms:
- "How do you monitor a Lambda function in production?"
- "What is the Embedded Metrics Format and why use it over PutMetricData?"
- "How would you query Lambda logs to find all invocations that took longer than 5 seconds?"

Answer frame:
Describe the three CloudWatch pillars (Logs, Metrics, Alarms) and their roles. Explain that Lambda logs automatically to CloudWatch. Contrast EMF (low-latency, batched metric emission via log lines) with PutMetricData (synchronous API call, adds latency). Give a CloudWatch Logs Insights query as an example. Mention retention policies as a cost control.

---

## Related Notes

- [[lambda-handlers|Lambda Handlers]]
- [[lambda-overview|Lambda Overview]]
- [[sns|SNS (Simple Notification Service)]]
- [[metrics-and-monitoring|Metrics and Monitoring]]
- [[logging-production|Production Logging]]
