---
title: Lambda Handlers
description: The Lambda handler is the entry point for every invocation — its structure, initialisation patterns, and event-specific shapes determine correctness and performance.
tags: [aws, cloud, layer-11, lambda, handlers, events]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda Handlers

> The handler is the contract between your code and the Lambda runtime — mastering its initialisation patterns, per-trigger event shapes, and error semantics separates resilient functions from brittle ones.

---

## Quick Reference

**Core idea:**
- Handler config format: `filename.function_name` (e.g. `main.handler`)
- Code outside the handler function runs once per execution environment — use it for connection pooling and heavy initialisation
- API Gateway handler must return `{'statusCode': int, 'body': str}`
- S3 handler: iterate `event['Records']`, each record has `s3.bucket.name` and `s3.object.key`
- SQS handler: iterate `event['Records']`, each record has `body` (string) and `messageId`
- EventBridge (scheduled) handler: event has `source`, `detail-type`, and `detail` but no business payload

**Tricky points:**
- Unhandled exceptions cause async invocations to retry — idempotency is essential for S3 and SQS triggers
- SQS partial batch failure: if one record in a batch throws, the entire batch retries unless you use `ReportBatchItemFailures`
- S3 object keys are URL-encoded — decode them with `urllib.parse.unquote_plus`
- Initialisation code runs once, but the execution environment can be recycled with a new function version — do not assume it is permanent
- Returning `None` from a synchronously invoked handler (API Gateway) results in the caller receiving an empty 200 — almost never what you want

---

## What It Is

The Lambda handler is like the `main()` function in a traditional application, but it is called by an external orchestrator — the Lambda runtime — rather than by the operating system. The runtime starts your process, imports your module (running all module-level code in the process), and then calls your handler function once per invocation, passing the trigger payload as `event` and runtime metadata as `context`. The runtime owns the process lifecycle; you own the handler logic.

The module-level execution boundary is one of the most consequential design decisions in Lambda. Any code that sits outside the handler function — creating database connections, instantiating SDK clients, loading ML models — runs exactly once when the execution environment is first created (a cold start), and then those objects persist across all warm invocations handled by that environment. This is deliberate. Opening a database connection on every invocation would be catastrophically expensive for a high-traffic function. But it also means that stale state — an expired credential, a closed connection, a corrupted in-memory cache — can silently affect every subsequent warm invocation until the environment is recycled.

The event schema is not universal. AWS defines a specific JSON structure for each trigger type. Treating a Lambda handler as a generic message receiver without knowing which trigger calls it is a frequent source of production bugs. A developer who has internalised the event shape for API Gateway proxy integration, S3 event notifications, and SQS polling — the three most common Python Lambda trigger types — can implement correct handlers without consulting the documentation for each deploy.

---

## How It Actually Works

The initialisation pattern for connection pooling is straightforward: instantiate the client or connection at module level, check on each warm invocation whether the connection is still healthy, and reconnect if necessary. For SQS and S3 triggers where partial batch failures are possible, the handler must collect failures and return them in the `batchItemFailures` format rather than raising an uncaught exception that would cause the entire batch to retry.

```python
import json
import logging
import os
import urllib.parse

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# --- Initialisation (runs once per execution environment) ---
s3_client = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


# --- API Gateway handler ---
def api_handler(event, context):
    """Handle API Gateway Lambda Proxy Integration requests."""
    logger.info(json.dumps({
        "handler": "api",
        "method": event.get("httpMethod"),
        "path": event.get("path"),
        "request_id": context.aws_request_id,
    }))

    body = json.loads(event.get("body") or "{}")

    try:
        result = process_api_request(body)
        return {
            "statusCode": 200,
            "body": json.dumps(result),
            "headers": {"Content-Type": "application/json"},
        }
    except ValueError as exc:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": str(exc)}),
            "headers": {"Content-Type": "application/json"},
        }
    except Exception as exc:
        logger.exception("Unhandled error in api_handler")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Internal server error"}),
            "headers": {"Content-Type": "application/json"},
        }


# --- S3 event notification handler ---
def s3_handler(event, context):
    """Handle S3 object creation events."""
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        # S3 keys are URL-encoded — decode before use
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        logger.info(json.dumps({"bucket": bucket, "key": key}))

        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response["Body"].read().decode("utf-8")
        process_s3_object(bucket, key, content)


# --- SQS handler with partial batch failure reporting ---
def sqs_handler(event, context):
    """
    Handle SQS messages with partial batch failure support.
    Requires the function's event source mapping to have
    FunctionResponseTypes = ["ReportBatchItemFailures"].
    """
    failures = []

    for record in event["Records"]:
        message_id = record["messageId"]
        try:
            body = json.loads(record["body"])
            process_sqs_message(body)
        except Exception as exc:
            logger.error(json.dumps({
                "error": str(exc),
                "message_id": message_id,
            }))
            failures.append({"itemIdentifier": message_id})

    # Return only the failed item identifiers — successful ones are deleted automatically
    return {"batchItemFailures": failures}


# --- EventBridge scheduled handler ---
def scheduled_handler(event, context):
    """Handle EventBridge scheduled rule invocations."""
    logger.info(json.dumps({
        "source": event.get("source"),
        "detail_type": event.get("detail-type"),
        "time": event.get("time"),
    }))
    run_scheduled_job()


def process_api_request(body): ...
def process_s3_object(bucket, key, content): ...
def process_sqs_message(body): ...
def run_scheduled_job(): ...
```

Enabling partial batch failure reporting on an existing SQS event source mapping via the CLI:

```bash
# Get the UUID of the existing event source mapping
aws lambda list-event-source-mappings \
    --function-name queue-processor \
    --query "EventSourceMappings[0].UUID" \
    --output text

# Update it to report partial failures
aws lambda update-event-source-mapping \
    --uuid <UUID-from-above> \
    --function-response-types ReportBatchItemFailures
```

---

## How It Connects

The handler patterns described here depend on the trigger type. API Gateway, S3, and SQS are the three most common trigger sources for Python Lambda functions, and each has its own invocation semantics.

[[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]] — covers the event source mappings, invocation models, and trigger-specific configuration options that determine how and when your handler is called.

Structured logging inside handlers is observable only because CloudWatch Logs captures the function's stdout. Understanding how to query those logs with CloudWatch Logs Insights completes the observability picture.

[[cloudwatch|CloudWatch]] — explains log groups, log streams, and the Logs Insights query language for searching Lambda execution logs.

---

## Common Misconceptions

Misconception 1: An unhandled exception in a Lambda handler means the request fails once and is done.
Reality: For asynchronous invocations (S3, SNS, EventBridge), Lambda retries the invocation up to two additional times on failure. For SQS event source mappings, a failure causes the entire batch to return to the queue and be retried up to the queue's maximum receive count, then routed to the DLQ. Handlers for async triggers must be idempotent — processing the same event twice must produce the same outcome without side effects.

Misconception 2: Module-level code is safe to use for credentials loaded at startup.
Reality: Short-lived credentials — such as those obtained by calling STS AssumeRole or by reading from Secrets Manager — expire. If the execution environment lives for hours and the credentials expire after one hour, subsequent warm invocations will fail with authentication errors. Either use the Lambda execution role's automatically-rotated credentials (via boto3's default credential chain), or refresh credentials inside the handler when they are near expiry.

---

## Why It Matters in Practice

Handler structure directly determines the operational behaviour of a Lambda function under load. A handler that places expensive initialisation inside the handler body re-runs that cost on every single invocation. A handler that fails on one SQS record and raises an exception causes every message in the batch to be retried — including the ones that succeeded — leading to duplicate processing and potential data corruption. Getting the initialisation pattern and the partial batch failure pattern correct from the start avoids an entire class of production incidents.

---

## What Breaks in Production

**Scenario 1: S3 key with spaces causes `NoSuchKey`**

```python
# Mistake: using the raw key directly
key = record["s3"]["object"]["key"]  # "uploads/my file.txt" → "uploads/my+file.txt"
s3_client.get_object(Bucket=bucket, Key=key)  # NoSuchKey

# Fix: URL-decode the key
import urllib.parse
key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
```

**Scenario 2: Entire SQS batch retried due to one bad message**

```python
# Mistake: letting an exception propagate for one bad message
def sqs_handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        process(body)  # raises ValueError for one malformed message
    # → entire batch is retried, good messages processed again

# Fix: collect failures and return batchItemFailures
def sqs_handler(event, context):
    failures = []
    for record in event["Records"]:
        try:
            process(json.loads(record["body"]))
        except Exception:
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
```

---

## Interview Angle

Common question forms:
- "What code should live outside versus inside the handler function?"
- "How do you handle partial batch failures in an SQS Lambda?"
- "What happens if a Lambda function throws an unhandled exception?"

Answer frame:
Explain the execution environment lifecycle: module-level code runs once on cold start, handler runs per invocation. Discuss idempotency requirements for async triggers. Walk through the `batchItemFailures` pattern for SQS. Distinguish between sync invocations (API Gateway returns the error to the caller) and async (Lambda retries automatically).

---

## Related Notes

- [[lambda-python|Lambda with Python]]
- [[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]]
- [[lambda-cold-start|Lambda Cold Starts]]
- [[cloudwatch|CloudWatch]]
- [[sqs|SQS (Simple Queue Service)]]
