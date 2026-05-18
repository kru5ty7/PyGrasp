---
title: Lambda Cold Starts
description: A cold start is the latency penalty Lambda pays when initialising a new execution environment — understanding its causes and mitigations is essential for latency-sensitive applications.
tags: [aws, cloud, layer-11, lambda, cold-start, performance]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda Cold Starts

> A cold start is the delay between a Lambda invocation arriving and your handler code beginning to execute — it exists because Lambda must first build the execution environment from scratch before calling your function.

---

## Quick Reference

**Core idea:**
- Cold start: new execution environment must be provisioned — download code, start runtime, run module-level initialisation
- Warm invocation: an existing environment handles the request — startup overhead is negligible
- Cold start duration: 100ms to several seconds depending on runtime, package size, and VPC configuration
- Python cold starts are among the fastest (~100–300ms for a minimal function without VPC)
- Provisioned Concurrency: pre-initialises N environments — eliminates cold starts at a per-minute cost
- Keep module-level code lean to minimise cold start duration

**Tricky points:**
- Lambda does not guarantee how long an execution environment stays warm — it can be recycled at any time
- VPC-attached Lambda functions face additional cold-start latency for ENI provisioning (much improved post-2019 hyperplane ENI change, but still measurable)
- Provisioned Concurrency eliminates cold starts but is billed even when idle — it must be cost-justified against p99 latency requirements
- Large deployment packages (heavy ML libraries) significantly increase cold start time — container images do not eliminate cold starts, they can make them worse
- "Warming" a function with scheduled pings is a brittle hack, not a replacement for Provisioned Concurrency

---

## What It Is

A cold start is the Lambda equivalent of arriving at the office on the first day and having to assemble your entire desk setup before you can do any work. A warm invocation is arriving on day two when everything is already in place — you sit down and start immediately. The "desk assembly" process for Lambda has three steps: the execution environment provisioning (allocating compute capacity and network interfaces), the runtime initialisation (starting the Python interpreter), and the function initialisation (importing your module and running all code outside the handler function). The handler itself does not run until all three steps are complete.

Python fares well in cold start comparisons because the CPython interpreter starts quickly and module import time for typical Lambda packages is measured in tens of milliseconds. Compare this to Java or Kotlin Lambda functions, which must start the JVM and load class files — a process that can take one to three seconds even for a minimal function. For Python ML functions with heavy imports (PyTorch, TensorFlow), the module-level import time dominates the cold start and can reach five to ten seconds.

Cold starts matter most for latency-sensitive synchronous workloads — API endpoints where users observe the latency directly. A cold start on an SQS message processing function adds latency to the first message in a batch but has no user-visible impact. A cold start on an API Gateway-fronted Lambda function means a user waiting an extra second or more for the first request to a function that has gone cold. The design response to this distinction is that Provisioned Concurrency investment should be targeted at functions where cold starts are in the user request path.

---

## How It Actually Works

Every millisecond of cold start latency is time before your `handler` function is called. The levers you control are: the deployment package size (smaller packages download faster), the number and size of imports at the module level (deferred imports reduce initialisation time), the runtime (Python vs Java vs .NET), VPC attachment (avoid if the function does not need to reach VPC resources), and Provisioned Concurrency.

Provisioned Concurrency pre-initialises a specified number of execution environments. Those environments complete the three-phase startup process in advance and remain in a ready state. Invocations dispatched to them skip all startup latency and proceed directly to the handler. The cost is that you pay for the provisioned environments whether or not they handle invocations.

```python
import boto3

lambda_client = boto3.client("lambda", region_name="us-east-1")

# Publish a function version (Provisioned Concurrency requires a version or alias, not $LATEST)
version_response = lambda_client.publish_version(FunctionName="my-api-function")
version = version_response["Version"]
print(f"Published version: {version}")

# Configure Provisioned Concurrency on the version
lambda_client.put_provisioned_concurrency_config(
    FunctionName="my-api-function",
    Qualifier=version,
    ProvisionedConcurrentExecutions=10,  # keep 10 environments always warm
)

# Monitor the provisioning status (takes a minute to become READY)
import time

while True:
    config = lambda_client.get_provisioned_concurrency_config(
        FunctionName="my-api-function",
        Qualifier=version,
    )
    status = config["Status"]
    print(f"Status: {status}")
    if status in ("READY", "FAILED"):
        break
    time.sleep(5)
```

Measuring cold start contribution from CloudWatch Logs — Lambda emits an `Init Duration` field in the REPORT log line for cold start invocations:

```bash
# Query CloudWatch Logs Insights for cold start durations
aws logs start-query \
    --log-group-name "/aws/lambda/my-api-function" \
    --start-time $(date -d "1 hour ago" +%s) \
    --end-time $(date +%s) \
    --query-string 'filter @type = "REPORT" | stats avg(@initDuration), max(@initDuration), count(@initDuration) by bin(5m)'
```

Optimising imports to reduce cold start time:

```python
# Suboptimal: all imports at module level, even conditionally-used heavy libraries
import torch                    # 500ms+ import time
import pandas as pd             # 200ms import time
import json                     # <1ms
import os

def handler(event, context):
    if event.get("action") == "train":
        return run_training()   # torch is always imported even for non-training invocations
    return {"statusCode": 200, "body": "{}"}


# Better: defer expensive imports to the code path that needs them
import json
import os

def handler(event, context):
    if event.get("action") == "train":
        import torch            # imported only on this code path
        return run_training(torch)
    return {"statusCode": 200, "body": "{}"}
```

---

## How It Connects

Cold start latency is directly linked to deployment package size. Container images can carry much larger dependency trees than ZIP packages but do not eliminate the cold start — they can increase it if the image is large.

[[lambda-container|Lambda with Container Images]] — describes the container deployment path and how image size affects cold start duration; the tradeoffs between ZIP and container deployment are relevant to cold start optimisation.

Provisioned Concurrency is the production-grade cold start mitigation. It works at the function version or alias level and integrates with Auto Scaling for dynamic scaling of the provisioned pool.

[[lambda-concurrency|Lambda Concurrency and Scaling]] — covers reserved and provisioned concurrency in detail, including the cost model and the Auto Scaling integration for provisioned concurrency.

---

## Common Misconceptions

Misconception 1: Scheduling a CloudWatch Events rule to invoke a Lambda function every few minutes prevents cold starts.
Reality: Scheduled pings keep one execution environment warm but do not help when your function receives concurrent traffic exceeding one invocation. If ten simultaneous requests arrive at a function kept alive by pings, nine of those requests will trigger cold starts on new execution environments. Provisioned Concurrency is the only reliable mechanism for keeping a specified number of environments warm.

Misconception 2: Python Lambda functions do not have cold starts because they are interpreted.
Reality: Python Lambda functions absolutely have cold starts. The cold start is shorter than Java or .NET, but module-level initialisation code — particularly heavy library imports (pandas, boto3 client instantiation, database connection setup) — still contributes meaningful latency. For a Python function with `import pandas as pd` at the top of the module, the import itself can take 200–500ms on the first invocation.

---

## Why It Matters in Practice

Cold start latency is invisible until it is not. A p99 latency graph that suddenly shows spikes correlating with scale-out events is frequently a cold start problem. API endpoints backed by Lambda functions that go cold during overnight low-traffic periods then spike at 9 AM will show the cold start penalty clearly in real-user monitoring. Teams that measure their cold start baseline (`@initDuration` in CloudWatch Logs), understand which functions are user-facing, and apply Provisioned Concurrency selectively to those functions avoid the spike-then-investigation cycle.

---

## What Breaks in Production

**Scenario 1: Heavy imports cause timeout on cold start**

A function with a 10-second timeout imports PyTorch, scikit-learn, and several internal libraries. The module-level import time exceeds the timeout, causing every cold start invocation to fail with a timeout.

```python
# Mistake: importing everything at module level with a tight timeout
import torch
import sklearn
import numpy as np

def handler(event, context):
    # Never actually reached on cold start if imports take >10s
    return {"statusCode": 200, "body": "ok"}

# Fix 1: increase the timeout (memory and timeout are set on the function config)
# aws lambda update-function-configuration --function-name fn --timeout 60

# Fix 2: use a container image and optimise the image layer cache so heavy layers are pre-cached
# Fix 3: use Provisioned Concurrency so cold starts happen before traffic, not during
```

**Scenario 2: VPC attachment doubles cold start latency unnecessarily**

A function is attached to a VPC to access a DynamoDB table — but DynamoDB has a public endpoint and does not require VPC access.

```bash
# Mistake: putting the function in a VPC when it only calls DynamoDB and S3 (both have public endpoints)
# Result: ENI provisioning adds 100-500ms to cold starts

# Fix: remove VPC configuration; use VPC endpoints or public AWS service endpoints instead
aws lambda update-function-configuration \
    --function-name my-function \
    --vpc-config SubnetIds=[],SecurityGroupIds=[]
```

---

## Interview Angle

Common question forms:
- "What is a Lambda cold start and what causes it?"
- "How do you mitigate cold starts in a production Lambda API?"
- "What is Provisioned Concurrency and when is it worth the cost?"

Answer frame:
Define the three phases of cold start (environment provisioning, runtime init, function init). Explain warm vs cold invocation. Describe the mitigations in order of effectiveness: reduce package size and import overhead, avoid unnecessary VPC attachment, and use Provisioned Concurrency for latency-sensitive user-facing functions. Distinguish from the scheduled-ping anti-pattern. Anchor the cost-benefit discussion to user-facing vs background workloads.

---

## Related Notes

- [[lambda-overview|Lambda Overview]]
- [[lambda-concurrency|Lambda Concurrency and Scaling]]
- [[lambda-container|Lambda with Container Images]]
- [[lambda-layers|Lambda Layers]]
- [[cloudwatch|CloudWatch]]
