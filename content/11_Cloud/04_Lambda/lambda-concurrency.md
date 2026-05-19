---
title: 41 - Lambda Concurrency and Scaling
description: Lambda scales by adding concurrent execution environments - understanding the concurrency model, account limits, reserved and provisioned concurrency, and throttling is critical for production reliability.
tags: [aws, cloud, layer-11, lambda, concurrency, scaling]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda Concurrency and Scaling

> Lambda scales horizontally and automatically - every simultaneous invocation gets its own execution environment - but the account-level concurrency ceiling, throttling behaviour, and cost model for pre-warmed environments demand deliberate configuration.

---

## Quick Reference

**Core idea:**
- Concurrency = number of simultaneous in-flight invocations across all function instances
- Account-level default limit: 1000 concurrent executions (soft limit, requestable increase)
- Reserved concurrency: reserves N executions for a specific function (and caps it there)
- Provisioned Concurrency: N environments pre-initialised and always ready - eliminates cold starts, billed per minute
- Throttling (HTTP 429): returned when a function exceeds its reserved limit or the account limit is reached
- CloudWatch metrics: `ConcurrentExecutions`, `Throttles`, `ProvisionedConcurrencyUtilization`

**Tricky points:**
- Setting reserved concurrency to 0 effectively disables a function (useful for emergency stops)
- Reserved concurrency subtracts from the account pool - if one function reserves 800 of 1000, only 200 remain for all other functions
- For SQS event source mappings, Lambda scales in increments of 60 executions per minute, up to the queue's depth
- Provisioned Concurrency requires a published version or alias - it cannot be set on `$LATEST`
- Burst concurrency limit (per-region, per-account): 500–3000 immediate burst capacity, then 500 per minute until the reserved limit is reached

---

## What It Is

Lambda's scaling model is like a self-service copy shop with an unlimited number of photocopiers. Every customer (invocation) who walks in gets their own machine immediately - no waiting in line. The machines spin up and spin down as customers arrive and leave, and you are only charged for the minutes each machine is actually running. This is the promise of automatic horizontal scaling: Lambda adds execution environments (machines) in response to demand without any manual intervention.

The ceiling on this model is the account-level concurrency limit. The default is 1000 concurrent executions across all Lambda functions in a region. If your account runs 900 concurrent executions on one function and another function starts receiving traffic, that second function has only 100 units of concurrency headroom before it hits the account limit and begins returning throttle errors (HTTP 429). In a microservices architecture where dozens of Lambda functions share a single AWS account, this pool contention is a real operational concern.

Reserved concurrency solves the pool contention problem in two directions simultaneously. Setting a function's reserved concurrency to 200 means: this function can use at most 200 concurrent executions, and no other function can claim those 200 slots. The reservation is both a floor (guaranteed availability) and a ceiling (blast radius containment). A runaway function - say, one processing a sudden queue backlog - cannot consume the entire account's concurrency and starve all other functions. Provisioned Concurrency takes a different cut: it pre-initialises environments so that when an invocation arrives, no cold start occurs. It is the latency optimisation; reserved concurrency is the capacity management tool.

---

## How It Actually Works

The burst concurrency limit is a frequently overlooked constraint. When Lambda scales from zero (or low concurrency) to high concurrency, it does not scale instantly to the reserved limit. Lambda initially allows a burst of 500–3000 concurrent executions (region-dependent), then adds 500 additional executions per minute thereafter. If an application goes from 0 to 10,000 concurrent invocations instantaneously, Lambda throttles the excess until its per-minute ramp-up catches up with demand. Applications with known spike patterns should use Provisioned Concurrency to pre-position environments ahead of the spike.

```python
import boto3

lambda_client = boto3.client("lambda", region_name="us-east-1")

# Set reserved concurrency for a function
lambda_client.put_function_concurrency(
    FunctionName="order-processor",
    ReservedConcurrentExecutions=200,
)

# Remove reserved concurrency (function shares the account pool again)
lambda_client.delete_function_concurrency(FunctionName="order-processor")

# Publish a version (required for Provisioned Concurrency)
version_resp = lambda_client.publish_version(FunctionName="api-handler")
version = version_resp["Version"]

# Set Provisioned Concurrency on the version
lambda_client.put_provisioned_concurrency_config(
    FunctionName="api-handler",
    Qualifier=version,
    ProvisionedConcurrentExecutions=20,
)

# Query current concurrency metrics via CloudWatch
cloudwatch = boto3.client("cloudwatch", region_name="us-east-1")
from datetime import datetime, timedelta, timezone

metrics = cloudwatch.get_metric_statistics(
    Namespace="AWS/Lambda",
    MetricName="ConcurrentExecutions",
    Dimensions=[{"Name": "FunctionName", "Value": "order-processor"}],
    StartTime=datetime.now(timezone.utc) - timedelta(hours=1),
    EndTime=datetime.now(timezone.utc),
    Period=60,
    Statistics=["Maximum"],
)

for point in sorted(metrics["Datapoints"], key=lambda x: x["Timestamp"]):
    print(f"{point['Timestamp']}: max={point['Maximum']}")
```

Setting up Auto Scaling for Provisioned Concurrency to scale with traffic patterns:

```bash
# Register the function version as an Auto Scaling target
aws application-autoscaling register-scalable-target \
    --service-namespace lambda \
    --resource-id function:api-handler:5 \
    --scalable-dimension lambda:function:ProvisionedConcurrency \
    --min-capacity 5 \
    --max-capacity 50

# Create a target tracking policy based on utilisation
aws application-autoscaling put-scaling-policy \
    --service-namespace lambda \
    --resource-id function:api-handler:5 \
    --scalable-dimension lambda:function:ProvisionedConcurrency \
    --policy-name track-utilisation \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration '{
        "TargetValue": 0.7,
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "LambdaProvisionedConcurrencyUtilization"
        }
    }'
```

---

## How It Connects

Concurrency and cold starts are tightly coupled. Provisioned Concurrency is the answer to cold starts on latency-sensitive functions, but it requires publishing a function version. The cold start note describes the cost-benefit analysis of Provisioned Concurrency.

[[lambda-cold-start|Lambda Cold Starts]] - covers the cold start lifecycle and explains why Provisioned Concurrency eliminates cold starts where the scheduled-ping approach does not.

The concurrency limit and throttling behaviour are directly relevant to SQS-triggered functions, where throttled invocations cause messages to become visible again in the queue and potentially be retried excessively.

[[sqs|SQS (Simple Queue Service)]] - covers the visibility timeout, dead-letter queue, and how throttling of Lambda invocations interacts with SQS message redelivery.

---

## Common Misconceptions

Misconception 1: Setting a high memory allocation increases Lambda's concurrency.
Reality: Memory allocation and concurrency are independent dimensions. More memory gives a single invocation more CPU (because CPU is proportional to memory), which can make each invocation finish faster, thereby freeing the concurrency slot sooner. But memory does not directly increase the number of simultaneous invocations - that is governed by the concurrency limit.

Misconception 2: Provisioned Concurrency means you pay nothing extra for the provisioned environments when no traffic is running.
Reality: Provisioned Concurrency is billed by the hour at a per-GB-second rate, regardless of whether the environments handle any invocations. Provisioning 20 environments with 1GB memory for 24 hours costs 20 × 1 × 86400 GB-seconds at the provisioned concurrency rate, whether traffic is zero or high. This makes it important to use Auto Scaling to scale the provisioned pool down during low-traffic periods.

---

## Why It Matters in Practice

Lambda's concurrency model is the mechanism that makes it both powerful and potentially dangerous in a shared account. A well-configured function fleet with reserved concurrency per function ensures that a traffic spike on one function cannot starve all others. Provisioned Concurrency, budgeted correctly and scaled with Auto Scaling, eliminates the cold-start user experience problem without paying for idle capacity around the clock. Teams that monitor `Throttles` in CloudWatch and treat any sustained throttling as an operational incident rather than an accepted behaviour build more reliable systems.

---

## What Breaks in Production

**Scenario 1: One function consumes all account concurrency, throttling unrelated functions**

```bash
# Scenario: a batch processing function suddenly receives a large SQS backlog
# It scales to 980 concurrent executions, leaving only 20 for the API-facing functions
# API functions begin returning 429 errors to users

# Fix: set reserved concurrency on both the batch function and the API functions
aws lambda put-function-concurrency \
    --function-name batch-processor \
    --reserved-concurrent-executions 200  # cap the batch function

aws lambda put-function-concurrency \
    --function-name api-handler \
    --reserved-concurrent-executions 400  # guarantee capacity for the API
```

**Scenario 2: Provisioned Concurrency set on `$LATEST` fails**

```python
# Mistake: trying to set Provisioned Concurrency on $LATEST
lambda_client.put_provisioned_concurrency_config(
    FunctionName="my-function",
    Qualifier="$LATEST",          # raises InvalidParameterValueException
    ProvisionedConcurrentExecutions=10,
)

# Fix: publish a version or create an alias, then target that
version = lambda_client.publish_version(FunctionName="my-function")["Version"]
lambda_client.put_provisioned_concurrency_config(
    FunctionName="my-function",
    Qualifier=version,
    ProvisionedConcurrentExecutions=10,
)
```

---

## Interview Angle

Common question forms:
- "How does Lambda scale, and what are the limits?"
- "What is the difference between reserved and provisioned concurrency?"
- "What happens when a Lambda function is throttled?"

Answer frame:
Explain the execution environment model - one environment per concurrent invocation. Describe the account concurrency pool (default 1000) and the burst scaling ramp-up. Distinguish reserved concurrency (capacity management + blast radius cap) from provisioned concurrency (cold start elimination, costs when idle). For throttling: synchronous callers receive 429 and should retry with backoff; SQS event source mappings retry automatically via visibility timeout expiry; EventBridge async invocations are retried by Lambda.

---

## Related Notes

- [[lambda-overview|Lambda Overview]]
- [[lambda-cold-start|Lambda Cold Starts]]
- [[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]]
- [[cloudwatch|CloudWatch]]
- [[sqs|SQS (Simple Queue Service)]]
