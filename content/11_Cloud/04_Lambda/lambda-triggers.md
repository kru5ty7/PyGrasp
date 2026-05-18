---
title: Lambda Triggers (S3, API Gateway, SQS)
description: Lambda triggers connect event sources to your function — understanding the invocation model, event shape, and failure semantics of each trigger type is essential for correct integration design.
tags: [aws, cloud, layer-11, lambda, triggers, events]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda Triggers (S3, API Gateway, SQS)

> Lambda can be triggered by dozens of AWS services — mastering the three most common (S3, API Gateway, SQS) gives you the templates for the rest, because the invocation model is what determines retry behaviour, error semantics, and scaling.

---

## Quick Reference

**Core idea:**
- S3: synchronous invocation from S3 event notification; function response is ignored; retries are your responsibility
- API Gateway: synchronous invocation; function return value is the HTTP response; caller waits for completion
- SQS: Lambda polls the queue (event source mapping); batch invocation; failed batches retry up to the queue's `maxReceiveCount`
- EventBridge: asynchronous invocation for scheduled rules and custom event patterns
- Event source mapping: Lambda's internal mechanism for polling-based sources (SQS, Kinesis, DynamoDB Streams)

**Tricky points:**
- SQS visibility timeout must be at least 6x the Lambda function timeout to prevent message reappearance during processing
- S3 event notifications are "at-least-once" — the same event can fire twice; handlers must be idempotent
- API Gateway has its own timeout independent of Lambda: 29 seconds for REST API, 30 seconds for HTTP API
- For SQS FIFO queues, Lambda processes one message group at a time — throughput is limited to the number of active message groups
- SNS to Lambda requires adding a resource-based permission to the Lambda function; the SNS topic does not use event source mapping

---

## What It Is

Lambda triggers are the connective tissue between the AWS event ecosystem and your function code. The best analogy is a building's intercom system. Different people can ring different extensions: the front desk (API Gateway) rings when a visitor arrives and expects an immediate response; the loading dock (S3) rings when a delivery arrives and does not wait for an answer; the mailroom (SQS) accumulates parcels and delivers them in batches, ensuring nothing is lost. Your function is the recipient — it processes what arrives, but the delivery mechanism, the retry policy, and the expectation of a response differ completely between each caller.

This distinction between synchronous and asynchronous invocation is the axis around which trigger design revolves. API Gateway invocations are synchronous: the HTTP client is waiting, the API Gateway is waiting, and Lambda must return a response dict within the API Gateway timeout or the caller receives a 502. S3 invocations are effectively asynchronous: S3 fires and forgets. If the Lambda function fails, S3 does not retry automatically (retries must be configured via the Lambda event notification retry settings or a DLQ). SQS uses a polling model called the event source mapping: Lambda continuously polls the queue, receives batches of messages, and only deletes them from the queue when the handler returns without error.

The event source mapping deserves particular attention because it is not immediately obvious. When you configure an SQS queue as a Lambda trigger in the console or via IaC, you are creating an event source mapping resource — a Lambda-managed internal polling process that reads messages from SQS on your behalf and invokes your function with batches. You do not write polling code; Lambda owns the polling loop. This same mechanism applies to Kinesis Data Streams and DynamoDB Streams.

---

## How It Actually Works

The SQS event source mapping is the most nuanced of the three common triggers. The key configuration parameters are batch size (how many messages per invocation, 1–10000), batch window (wait up to N seconds to fill a batch), and visibility timeout alignment. The visibility timeout — how long a message is hidden from other consumers after being received — must exceed the Lambda function timeout to ensure the function has time to finish processing before the message reappears in the queue. AWS recommends setting the visibility timeout to at least 6x the function timeout.

```python
import boto3
import json

lambda_client = boto3.client("lambda", region_name="us-east-1")

# Create an SQS event source mapping
response = lambda_client.create_event_source_mapping(
    EventSourceArn="arn:aws:sqs:us-east-1:123456789012:my-processing-queue",
    FunctionName="my-queue-processor",
    BatchSize=10,
    MaximumBatchingWindowInSeconds=5,   # wait up to 5s to fill a batch
    FunctionResponseTypes=["ReportBatchItemFailures"],  # enable partial batch failures
)
print(f"Mapping UUID: {response['UUID']}")

# Create an S3 event notification trigger via boto3
s3_client = boto3.client("s3")
s3_client.put_bucket_notification_configuration(
    Bucket="my-data-bucket",
    NotificationConfiguration={
        "LambdaFunctionConfigurations": [
            {
                "LambdaFunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:my-s3-processor",
                "Events": ["s3:ObjectCreated:*"],
                "Filter": {
                    "Key": {
                        "FilterRules": [
                            {"Name": "prefix", "Value": "uploads/"},
                            {"Name": "suffix", "Value": ".csv"},
                        ]
                    }
                },
            }
        ]
    },
)
```

Adding an EventBridge scheduled rule that invokes a Lambda function every 5 minutes:

```bash
# Create the rule
aws events put-rule \
    --name every-5-minutes \
    --schedule-expression "rate(5 minutes)" \
    --state ENABLED

# Add the Lambda function as the target
aws events put-targets \
    --rule every-5-minutes \
    --targets "Id=my-scheduled-fn,Arn=arn:aws:lambda:us-east-1:123456789012:function:my-scheduled-function"

# Grant EventBridge permission to invoke the function
aws lambda add-permission \
    --function-name my-scheduled-function \
    --statement-id eventbridge-invoke \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:us-east-1:123456789012:rule/every-5-minutes
```

Handler that correctly processes an SQS event with partial batch failure reporting:

```python
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    failures = []

    for record in event["Records"]:
        message_id = record["messageId"]
        try:
            body = json.loads(record["body"])
            process_message(body)
            logger.info(json.dumps({"processed": message_id}))
        except Exception as exc:
            logger.error(json.dumps({"failed": message_id, "error": str(exc)}))
            failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": failures}


def process_message(body):
    # Business logic here
    pass
```

---

## How It Connects

SQS as a trigger source is inseparable from an understanding of the SQS queue itself — its message retention, visibility timeout, and dead-letter queue configuration all affect how Lambda behaves when processing it.

[[sqs|SQS (Simple Queue Service)]] — the full SQS note covers Standard versus FIFO queues, visibility timeout, DLQ configuration, and the polling model that Lambda's event source mapping relies on.

API Gateway as a Lambda trigger requires understanding the Lambda proxy integration and the response shape requirements covered in the Python handler note.

[[api-gateway-aws|AWS API Gateway]] — the full API Gateway note covers REST vs HTTP API types, request/response transformation, authentication, and stage management.

---

## Common Misconceptions

Misconception 1: S3 event notifications deliver exactly once.
Reality: S3 event notifications provide at-least-once delivery semantics. In rare cases — particularly during partial failures or S3 retries — the same event can be delivered more than once. Handlers that process S3 events must be idempotent: processing the same S3 key twice should produce the same result as processing it once. The standard approach is to check whether the output artifact already exists before doing the work.

Misconception 2: Setting the SQS event source mapping batch size to 1 guarantees that each message is processed independently and failures cannot affect other messages.
Reality: A batch size of 1 does mean each invocation processes exactly one message, which eliminates the partial batch failure problem. However, it significantly increases the number of Lambda invocations (and thus Lambda cost) and reduces throughput compared to batch processing. Partial batch failure reporting (`ReportBatchItemFailures`) achieves independent failure handling with batch sizes greater than 1 and should be preferred.

---

## Why It Matters in Practice

The invocation model (synchronous, asynchronous, polling) determines the entire operational contract of a Lambda integration. Getting the SQS visibility timeout wrong causes messages to be processed multiple times. Ignoring idempotency for S3 triggers causes duplicate writes. Misunderstanding the API Gateway timeout causes users to receive unexplained 502 errors. These are not edge cases — they are the first failure modes any production Lambda deployment encounters.

---

## What Breaks in Production

**Scenario 1: SQS visibility timeout shorter than Lambda timeout causes duplicate processing**

```bash
# Mistake: Lambda timeout is 60s, SQS visibility timeout is 30s
# Message becomes visible again at 30s, another Lambda instance picks it up
# Message is processed twice

# Fix: set SQS visibility timeout >= 6x Lambda timeout
aws sqs set-queue-attributes \
    --queue-url https://sqs.us-east-1.amazonaws.com/123456789012/my-queue \
    --attributes VisibilityTimeout=360  # 6x a 60-second Lambda timeout
```

**Scenario 2: API Gateway returns 502 because handler returns None**

```python
# Mistake: forgetting to return a response from the API Gateway handler
def handler(event, context):
    process_data(event)
    # Returns None implicitly → API Gateway receives no statusCode → 502 Bad Gateway

# Fix: always return a valid API Gateway response dict
def handler(event, context):
    process_data(event)
    return {"statusCode": 200, "body": json.dumps({"status": "ok"})}
```

---

## Interview Angle

Common question forms:
- "What is the difference between synchronous and asynchronous Lambda invocations?"
- "How does Lambda's SQS event source mapping work?"
- "What happens when a Lambda function fails while processing an SQS message?"

Answer frame:
Explain synchronous (API Gateway, waits for response), asynchronous (S3, fires and forgets with Lambda-managed retries), and polling (SQS event source mapping, Lambda polls on your behalf). For SQS failure: describe visibility timeout, the partial batch failure pattern, and the DLQ as the final safety net. Emphasise idempotency as the design principle that makes all trigger types safe.

---

## Related Notes

- [[lambda-handlers|Lambda Handlers]]
- [[lambda-iam|Lambda IAM Execution Role]]
- [[sqs|SQS (Simple Queue Service)]]
- [[api-gateway-aws|AWS API Gateway]]
- [[s3-event-notifications|S3 Event Notifications]]
