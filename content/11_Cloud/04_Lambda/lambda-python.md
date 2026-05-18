---
title: 34 - Lambda with Python
description: Writing, configuring, and deploying Python Lambda functions — the handler contract, the runtime environment, and deployment mechanics.
tags: [aws, cloud, layer-11, lambda, python, serverless]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda with Python

> Python is the most popular Lambda runtime — understanding the handler signature, the event and context objects, and the deployment formats is the foundation of all Lambda work.

---

## Quick Reference

**Core idea:**
- Handler signature: `def handler(event, context)` — names are arbitrary but the convention is `handler`
- `event`: a plain Python dict containing the trigger payload (structure varies by trigger source)
- `context`: an object exposing function metadata and runtime state
- Supported runtimes as of 2024: Python 3.11, 3.12 (3.10 in maintenance)
- Deployment formats: ZIP file (up to 50MB direct, 250MB via S3) or container image (up to 10GB)
- Return value for API Gateway triggers must be a dict with `statusCode` and `body`

**Tricky points:**
- `event['body']` from API Gateway arrives as a JSON string, not a dict — you must call `json.loads`
- The `context` object is not a dict; access its properties as attributes (`context.aws_request_id`)
- `context.get_remaining_time_in_millis()` is a method call, not a property
- Environment variables are strings; cast numeric values explicitly (`int(os.environ["BATCH_SIZE"])`)
- Dependencies not bundled in the deployment package or a layer will cause `ModuleNotFoundError` at runtime

---

## What It Is

Think of the Lambda handler as a postal sorting facility worker who reports for duty every time a new parcel arrives. The parcel is the `event` — it contains everything the worker needs to know about the incoming request: where it came from, what it contains, and what should happen to it. The `context` object is the worker's employee badge — it carries identifying information about the shift (the request ID), how much time is left before the worker must clock out (the remaining execution time), and what the job site is called (the function name). The worker opens the parcel, does the work, and hands back a result. What "result" means depends on who sent the parcel.

Python became the dominant Lambda language because of its rapid development cycle, strong data-processing ecosystem (boto3, requests, pandas, numpy), and relatively fast cold-start behaviour compared to JVM languages. AWS ships fully managed Python runtimes with pre-installed boto3 and botocore, so common AWS SDK calls work out of the box without bundling the SDK in your package.

The deployment model is deliberately simple. You write your code, optionally bundle dependencies alongside it in a ZIP archive, and upload. The handler setting in the Lambda configuration tells AWS which file and function to call: `main.handler` means "call the `handler` function in `main.py`". For larger dependency trees — ML libraries, data processing stacks — the container image deployment path removes the 250MB ZIP limit entirely.

---

## How It Actually Works

The event dict's structure is entirely determined by the trigger source. An S3 event looks completely different from an SQS event, which looks different from an API Gateway proxy event. Your handler code must be written with knowledge of which trigger will call it. For API Gateway (Lambda Proxy Integration), the event carries HTTP metadata: method, path, headers, query string parameters, and the request body as a JSON-encoded string. For SQS, the event contains a `Records` list where each record holds the message body and metadata. For EventBridge scheduled events, the event carries timing metadata with no meaningful business payload.

The context object exposes useful runtime metadata. Its most practically useful member is `get_remaining_time_in_millis()`, which lets a long-running handler check whether it has enough time left to complete a unit of work cleanly before Lambda kills the execution environment.

```python
import json
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Lambda handler demonstrating event and context usage.
    This example handles an API Gateway Lambda Proxy Integration request.
    """
    # Log structured metadata for CloudWatch Logs Insights queries
    logger.info(json.dumps({
        "request_id": context.aws_request_id,
        "function_name": context.function_name,
        "remaining_ms": context.get_remaining_time_in_millis(),
        "memory_limit_mb": context.memory_limit_in_mb,
    }))

    # API Gateway sends the body as a JSON *string* — always parse it
    raw_body = event.get("body") or "{}"
    try:
        body = json.loads(raw_body)
    except json.JSONDecodeError:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Invalid JSON body"}),
            "headers": {"Content-Type": "application/json"},
        }

    # Read configuration from environment variables (always strings)
    stage = os.environ.get("STAGE", "dev")
    max_items = int(os.environ.get("MAX_ITEMS", "100"))

    # Extract query string parameters
    params = event.get("queryStringParameters") or {}
    page = int(params.get("page", "1"))

    # Business logic
    result = {
        "stage": stage,
        "page": page,
        "max_items": max_items,
        "received": body,
    }

    # API Gateway requires this exact response shape
    return {
        "statusCode": 200,
        "body": json.dumps(result),
        "headers": {
            "Content-Type": "application/json",
            "X-Request-Id": context.aws_request_id,
        },
    }
```

Deploying a function from the command line:

```bash
# Package the handler and its dependencies
pip install requests -t package/
cp main.py package/
cd package && zip -r ../function.zip . && cd ..

# Create the function
aws lambda create-function \
    --function-name my-api-handler \
    --runtime python3.12 \
    --role arn:aws:iam::123456789012:role/lambda-exec-role \
    --handler main.handler \
    --zip-file fileb://function.zip \
    --timeout 30 \
    --memory-size 256

# Update an existing function's code
aws lambda update-function-code \
    --function-name my-api-handler \
    --zip-file fileb://function.zip
```

---

## How It Connects

The handler described above is meaningless until it is connected to a trigger. API Gateway, S3 event notifications, and SQS event source mappings are the three most common ways Lambda receives events in Python applications.

[[lambda-handlers|Lambda Handlers]] — goes deeper on the per-trigger event shapes, initialisation patterns, and structured logging conventions.

Every Lambda function runs under an IAM execution role that governs which AWS services it can call. A handler that calls `boto3.client("s3")` will fail with an `AccessDenied` error unless the execution role has the appropriate S3 permissions.

[[lambda-iam|Lambda IAM Execution Role]] — explains the execution role model, resource-based policies, and how to scope permissions correctly.

---

## Common Misconceptions

Misconception 1: The handler function name must be `handler`.
Reality: The function name is arbitrary. What matters is the handler configuration string set on the Lambda function, which takes the form `filename.functionname`. If your file is `app.py` and your function is `process_event`, you set the handler to `app.process_event`.

Misconception 2: boto3 is always available in the Lambda environment without bundling it.
Reality: AWS-managed Python runtimes include boto3 and botocore, but the version bundled with the runtime lags behind the latest release. If your code depends on features in a specific boto3 version, bundle it explicitly in your deployment package so you control the version.

---

## Why It Matters in Practice

Getting the handler contract right is the first step to writing any Lambda function. Misunderstanding how the `event` structure differs between trigger types is the single most common source of Lambda bugs — particularly the `event['body']` as string issue for API Gateway. A developer who internalises the event shape for each trigger type, uses structured logging from the start, and checks remaining time for long-running operations builds functions that are correct, observable, and resilient.

---

## What Breaks in Production

**Scenario 1: Forgetting that `event['body']` is a string**

```python
# Mistake: treating the body as an already-parsed dict
def handler(event, context):
    data = event["body"]          # This is a string, not a dict
    name = data["name"]           # TypeError: string indices must be integers

# Fix: always parse the body
def handler(event, context):
    data = json.loads(event.get("body") or "{}")
    name = data.get("name", "unknown")
```

**Scenario 2: Environment variable type mismatch**

```python
# Mistake: using env var directly as an integer
def handler(event, context):
    limit = os.environ["PAGE_LIMIT"]
    items = fetch_items(limit=limit)  # passes a string to a parameter expecting int

# Fix: cast explicitly
def handler(event, context):
    limit = int(os.environ.get("PAGE_LIMIT", "50"))
    items = fetch_items(limit=limit)
```

**Scenario 3: Missing dependency in deployment package**

A function works locally but raises `ModuleNotFoundError: No module named 'requests'` in Lambda.

```bash
# Mistake: deploying only the handler file
zip function.zip main.py

# Fix: install dependencies into the package directory first
pip install requests -t package/
cp main.py package/
cd package && zip -r ../function.zip . && cd ..
```

---

## Interview Angle

Common question forms:
- "Walk me through the Lambda handler signature in Python."
- "What is in the `context` object and when would you use it?"
- "How does the event structure differ between API Gateway and SQS triggers?"

Answer frame:
Explain `event` as a plain dict whose structure depends entirely on the trigger, and `context` as a runtime metadata object (not a dict). Give the API Gateway example of `body` arriving as a string. Mention `get_remaining_time_in_millis()` for timeout-aware handlers. Describe the deployment package requirement for third-party dependencies.

---

## Related Notes

- [[lambda-overview|Lambda Overview]]
- [[lambda-handlers|Lambda Handlers]]
- [[lambda-environment|Lambda Environment Variables]]
- [[lambda-iam|Lambda IAM Execution Role]]
- [[api-gateway-aws|AWS API Gateway]]
