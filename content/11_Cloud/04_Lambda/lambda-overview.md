---
title: 33 - Lambda Overview
description: Lambda is AWS's serverless compute platform where you supply code and AWS owns all infrastructure concerns.
tags: [aws, cloud, layer-11, lambda, serverless]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda Overview

> Lambda is AWS's serverless compute service — you deploy a function, AWS runs it in response to events, and you are billed only for the time your code actually executes.

---

## Quick Reference

**Core idea:**
- You write a handler function; AWS provisions, runs, and retires the execution environment
- Billing: per invocation + per GB-second of execution time (128MB increments up to 10GB)
- Maximum execution duration: 15 minutes per invocation
- Memory range: 128MB to 10GB; CPU scales proportionally with memory allocation
- Cold start: first invocation on a new execution environment incurs initialisation overhead
- Use event-driven workloads, webhooks, lightweight APIs, and scheduled jobs

**Tricky points:**
- Lambda is stateless by design — no in-memory state survives across invocations in different environments
- The 15-minute hard limit makes it unsuitable for long-running batch jobs
- Sustained high-throughput workloads can cost more than equivalent EC2 or ECS capacity
- VPC-attached Lambda functions face additional cold-start latency for ENI provisioning
- Account-level default concurrency is 1000; hitting it causes silent throttling

---

## What It Is

Think of Lambda as a vending machine for compute. You stock the machine with your code (the item), and every time someone makes a request (inserts coins), the machine dispenses exactly one execution — no more, no less. You never worry about how the machine keeps the lights on, how many machines are running, or whether the machines need maintenance. AWS takes all of that off your hands. You are billed per dispense, not per hour the machine sits in the corner.

Before Lambda, deploying even a small webhook receiver required provisioning a server, choosing an instance type, configuring the operating system, installing a runtime, writing a process manager configuration, and thinking about what happens when traffic spikes. Lambda collapses all of that surface area. A Python function with the right signature is enough. AWS handles OS patching, runtime updates (when you opt in), horizontal scaling, and hardware failure. You get a managed, auto-scaling execution environment without writing a single line of infrastructure code.

Lambda fits squarely into the event-driven architecture pattern. It is designed to react: a file arrives in S3, a message lands in SQS, an HTTP request hits API Gateway, a schedule fires in EventBridge — Lambda wakes up, processes the event, and exits. The model breaks down when the workload is stateful (requires persistent in-memory caches across requests), when it needs to run longer than 15 minutes, or when it runs at such sustained high concurrency that per-invocation pricing exceeds the equivalent reserved EC2 or ECS capacity. For those cases, EC2, ECS, or EKS are better fits.

---

## How It Actually Works

When Lambda receives an invocation request, it looks for an existing warm execution environment — a container-like sandbox that already has the runtime and your code loaded. If one is available, the request is dispatched to it immediately. If none is available (a cold start scenario), Lambda provisions a new environment: downloads the deployment package or container image, initialises the runtime, runs any module-level initialisation code in your handler file, and then calls your handler function. The environment stays alive for several minutes after each invocation in case another request arrives, which makes subsequent invocations warm.

You can inspect Lambda functions and deploy new ones entirely from the AWS CLI or boto3. The example below creates a function from a ZIP file that was uploaded to S3.

```python
import boto3

client = boto3.client("lambda", region_name="us-east-1")

# Create a new Lambda function
response = client.create_function(
    FunctionName="my-python-function",
    Runtime="python3.12",
    Role="arn:aws:iam::123456789012:role/lambda-execution-role",
    Handler="main.handler",          # file_name.function_name
    Code={
        "S3Bucket": "my-deploy-bucket",
        "S3Key": "packages/my-python-function.zip",
    },
    Timeout=30,                      # seconds, max 900
    MemorySize=256,                  # MB; CPU scales proportionally
    Environment={
        "Variables": {
            "STAGE": "production",
        }
    },
)

print(response["FunctionArn"])

# Invoke the function synchronously
invoke_response = client.invoke(
    FunctionName="my-python-function",
    InvocationType="RequestResponse",  # synchronous
    Payload=b'{"key": "value"}',
)

import json
result = json.loads(invoke_response["Payload"].read())
print(result)
```

The equivalent AWS CLI command to invoke the same function is:

```bash
aws lambda invoke \
    --function-name my-python-function \
    --payload '{"key": "value"}' \
    --cli-binary-format raw-in-base64-out \
    output.json
```

---

## How It Connects

Lambda does not exist in isolation. Execution permissions flow from an IAM role attached to the function, and understanding that role model is a prerequisite for writing Lambda functions that can safely call other AWS services.

[[iam-roles|IAM Roles]] — every Lambda function assumes an IAM role at runtime; that role governs what the function can do in your AWS account.

Lambda's most common integration is with API Gateway for HTTP-triggered workloads and with S3 or SQS for asynchronous event-driven workloads. Understanding those trigger models gives a complete picture of where Lambda fits.

[[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]] — details the event source mapping and invocation models that connect Lambda to the rest of AWS.

---

## Common Misconceptions

Misconception 1: Lambda is always cheaper than EC2.
Reality: Lambda pricing is per-invocation and per GB-second. At sustained, high concurrency — thousands of requests per second running for hours — the accumulated per-invocation costs can exceed the equivalent EC2 reserved instance price. Lambda is cheapest for spiky, bursty, or low-volume workloads.

Misconception 2: Lambda functions are completely stateless, so nothing persists between invocations.
Reality: The execution environment (the container-like sandbox) is reused across warm invocations of the same function. Module-level variables initialised outside the handler persist within that environment. This is intentional and useful for connection pooling, but it also means leftover state from a previous invocation can bleed into a new one if you are not careful.

---

## Why It Matters in Practice

Lambda is the default choice for event-driven workloads in AWS because the operational overhead is genuinely minimal. A Python developer who understands the handler contract, the execution environment lifecycle, and the cold-start behaviour can ship production functions in hours rather than days. The absence of server management removes an entire class of operational concerns — OS vulnerabilities, capacity planning, instance health monitoring — from the team's backlog.

The tradeoffs are real, though. Lambda forces stateless design, demands that workloads complete in under 15 minutes, and requires careful attention to cold-start latency for latency-sensitive paths. Teams that internalise these constraints early make better architectural decisions about when to reach for Lambda versus a longer-running compute option.

---

## What Breaks in Production

**Scenario 1: Silent throttling under load**

An application processes events from an SQS queue. During a traffic spike, the queue depth grows and Lambda scales up. If the account-level concurrency limit (default 1000) is reached, Lambda begins throttling — returning 429 errors. For SQS, throttled invocations are automatically retried, which can cause the queue to grow unboundedly.

```python
# Mistake: no reserved concurrency set, function competes with all other functions
# Fix: set reserved concurrency to isolate this function's scaling budget

import boto3
client = boto3.client("lambda")

# Cap this function to 200 concurrent executions
client.put_function_concurrency(
    FunctionName="queue-processor",
    ReservedConcurrentExecutions=200,
)
```

**Scenario 2: Timeout causes incomplete processing**

A function with a 3-second timeout processes large S3 objects. Objects larger than a few MB occasionally cause the function to exceed the timeout, resulting in partial processing and Lambda retrying the invocation.

```python
# Mistake: not checking remaining time before starting expensive work
# Fix: check context.get_remaining_time_in_millis() early

def handler(event, context):
    if context.get_remaining_time_in_millis() < 5000:
        # Less than 5 seconds left — abort cleanly rather than getting cut off
        raise RuntimeError("Insufficient time remaining to process safely")
    # ... proceed with work
```

---

## Interview Angle

Common question forms:
- "When would you choose Lambda over ECS or EC2?"
- "What is a cold start and how do you mitigate it?"
- "How does Lambda pricing work, and when does it become expensive?"

Answer frame:
Lead with the event-driven, stateless, short-duration constraints. Distinguish between warm and cold invocations. Mention Provisioned Concurrency as a cold-start mitigation. Acknowledge that sustained high-concurrency workloads may favour EC2/ECS on cost. Show awareness of the 15-minute limit and account concurrency cap.

---

## Related Notes

- [[lambda-python|Lambda with Python]]
- [[lambda-cold-start|Lambda Cold Starts]]
- [[lambda-concurrency|Lambda Concurrency and Scaling]]
- [[iam-roles|IAM Roles]]
- [[lambda-triggers|Lambda Triggers]]
