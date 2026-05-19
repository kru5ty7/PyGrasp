---
title: 21 - S3 Event Notifications
description: S3 event notifications let you trigger downstream processing automatically when objects are created, deleted, or restored - the foundation of event-driven data pipelines on AWS.
tags: [aws, cloud, layer-11, s3, events, lambda]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# S3 Event Notifications

> S3 event notifications decouple the act of storing a file from the act of processing it - enabling event-driven architectures where a file upload automatically triggers Lambda, SQS, or SNS without any polling.

---

## Quick Reference

**Core idea:**
- S3 sends notifications when objects are created (`s3:ObjectCreated:*`), deleted, or restored from Glacier
- Destinations: Lambda (invoke directly), SQS (queue the event), SNS (fan out to multiple subscribers)
- Filter by key prefix (e.g. `uploads/`) and suffix (e.g. `.jpg`) to target specific object types
- The event payload includes the bucket name, object key, size, ETag, and the triggering event type
- EventBridge integration provides richer filtering, cross-account routing, and replay capability

**Tricky points:**
- S3 cannot send notifications to multiple Lambda functions for the same event type and prefix/suffix combination - use SNS or EventBridge for fan-out
- Notifications are delivered at least once - your Lambda or SQS consumer must be idempotent
- The Lambda that receives the notification must have a resource-based policy allowing S3 to invoke it
- S3 event notifications do not guarantee ordering - a notification for object version N+1 may arrive before the notification for version N
- Large batches of concurrent uploads can cause S3 to retry notification delivery, leading to duplicate invocations

---

## What It Is

Think of S3 event notifications as a doorbell on your storage system. Normally, S3 sits silently holding your files. But with event notifications configured, every time someone drops a new file through the letter slot, the doorbell rings and wakes up a function to process it. You do not need a process running in a loop asking "has a new file arrived?" - the doorbell tells you the moment it happens.

This push model is the foundation of event-driven data architectures on AWS. The classic example is an image processing pipeline: a user uploads a photo to an S3 bucket, the upload triggers a Lambda function, and the Lambda function reads the image, resizes it to three thumbnail sizes, and writes the thumbnails back to a different S3 prefix. The user's upload is decoupled from the resizing work - S3 acts as the trigger boundary. The user's request returns immediately after the upload; the processing happens asynchronously.

The choice of destination - Lambda, SQS, or SNS - reflects the processing model. Lambda is appropriate for lightweight, fast processing that can run within a few seconds per event. SQS is appropriate for workloads where processing may be slow, where you want rate limiting (Lambda concurrency control), or where you need to dequeue and process in batches. SNS is appropriate for fan-out - sending the same event to multiple subscribers simultaneously, such as both a Lambda for processing and another Lambda for logging.

---

## How It Actually Works

When you configure a notification, you specify three things: the event types to watch (using wildcards like `s3:ObjectCreated:*` or specific types like `s3:ObjectCreated:Put`), an optional filter with a prefix and/or suffix to limit which objects trigger notifications, and the destination (Lambda ARN, SQS queue ARN, or SNS topic ARN). S3 stores this configuration on the bucket itself. When a matching event occurs, S3 calls the destination asynchronously.

The event payload is a JSON document wrapped in a Records array. Each record contains the event version, event source (`aws:s3`), AWS region, event time, event name, the request parameters, and the S3 object details. The S3 object block includes the bucket name, the object key (URL-encoded - you must decode it), the object size, the ETag, and the version ID if versioning is enabled. Lambda receives this payload directly as the event parameter; SQS receives it as the message body.

```bash
# Create an SQS queue and grant S3 permission to send to it
aws sqs create-queue --queue-name s3-events-queue

# Get the queue ARN
QUEUE_ARN=$(aws sqs get-queue-attributes \
    --queue-url https://sqs.eu-west-1.amazonaws.com/123456789012/s3-events-queue \
    --attribute-names QueueArn \
    --query Attributes.QueueArn --output text)

# Configure S3 event notification to send to SQS
aws s3api put-bucket-notification-configuration \
    --bucket my-bucket \
    --notification-configuration file://notification-config.json

# notification-config.json:
# {
#   "QueueConfigurations": [{
#     "QueueArn": "arn:aws:sqs:eu-west-1:123456789012:s3-events-queue",
#     "Events": ["s3:ObjectCreated:*"],
#     "Filter": {"Key": {"FilterRules": [
#       {"Name": "prefix", "Value": "uploads/"},
#       {"Name": "suffix", "Value": ".jpg"}
#     ]}}
#   }]
# }
```

```python
import boto3
import json
import urllib.parse

s3 = boto3.client("s3")

# Configure S3 to invoke a Lambda on object creation
lambda_arn = "arn:aws:lambda:eu-west-1:123456789012:function:ProcessUpload"

s3.put_bucket_notification_configuration(
    Bucket="my-bucket",
    NotificationConfiguration={
        "LambdaFunctionConfigurations": [
            {
                "LambdaFunctionArn": lambda_arn,
                "Events": ["s3:ObjectCreated:*"],
                "Filter": {
                    "Key": {
                        "FilterRules": [
                            {"Name": "prefix", "Value": "uploads/"},
                            {"Name": "suffix", "Value": ".jpg"},
                        ]
                    }
                },
            }
        ]
    },
)

# Lambda handler that processes the S3 event
def lambda_handler(event, context):
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        # Object key is URL-encoded in the event - must decode
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        size = record["s3"]["object"]["size"]
        etag = record["s3"]["object"]["eTag"]

        print(f"Processing: s3://{bucket}/{key} ({size} bytes)")

        s3_client = boto3.client("s3")
        response = s3_client.get_object(Bucket=bucket, Key=key)
        image_bytes = response["Body"].read()
        # ... process image ...

# Grant S3 permission to invoke the Lambda (resource-based policy - required)
import boto3
lam = boto3.client("lambda")
lam.add_permission(
    FunctionName="ProcessUpload",
    StatementId="S3InvokePermission",
    Action="lambda:InvokeFunction",
    Principal="s3.amazonaws.com",
    SourceArn="arn:aws:s3:::my-bucket",
    SourceAccount="123456789012",  # prevents confused deputy attack
)

# Enable EventBridge notifications (alternative - richer routing)
s3.put_bucket_notification_configuration(
    Bucket="my-bucket",
    NotificationConfiguration={"EventBridgeConfiguration": {}},  # enable EventBridge
)
```

---

## How It Connects

S3 event notifications are one of the most common Lambda triggers in production AWS architectures. The Lambda function that receives the notification needs an execution role with permissions to read from S3 and write to wherever it stores results.

[[lambda-triggers|Lambda Triggers]] - S3 event notifications are one of several ways to trigger Lambda; understanding the invocation model (synchronous vs asynchronous) affects error handling and retry behaviour.

When processing volume is high, routing S3 events through SQS before Lambda allows you to control processing rate, batch records, and handle failures with a dead-letter queue.

[[sqs|SQS]] - using SQS as an intermediate layer between S3 event notifications and Lambda processing enables backpressure, batching, and dead-letter queue retry for failed records.

---

## Common Misconceptions

Misconception 1: S3 event notifications are delivered exactly once.
Reality: S3 guarantees at-least-once delivery. In rare cases of infrastructure failures or retries, the same event may be delivered more than once. Lambda functions and SQS consumers must be written to be idempotent - processing the same event twice should produce the same result as processing it once (e.g., using the ETag or version ID as a deduplication key).

Misconception 2: You can configure multiple Lambda functions to receive the same S3 event for the same prefix and suffix.
Reality: Each S3 bucket notification configuration allows only one destination per event type and filter combination. To fan out a single S3 event to multiple consumers, publish to SNS (which can deliver to multiple Lambda subscriptions) or use EventBridge (which supports multiple rules targeting different destinations).

---

## Why It Matters in Practice

S3 event notifications eliminate the need for polling loops. Without them, processing uploaded files would require a scheduled job that lists objects, identifies new ones, processes them, and marks them as processed - fragile, expensive in API calls, and slow (polling interval latency). With event notifications, processing starts within milliseconds of the upload completing.

Event-driven S3 processing is the backbone of modern data ingestion pipelines. CSV files uploaded to S3 trigger Lambda to validate and load them into DynamoDB. Images uploaded by users trigger thumbnail generation. Log files shipped from EC2 trigger ingestion into a data warehouse. The pattern is the same regardless of the processing type: object lands in S3, notification fires, processor runs, result lands somewhere else.

---

## What Breaks in Production

**Forgetting to URL-decode the object key in the Lambda handler.** S3 URL-encodes the key in the event payload - keys with spaces or special characters will be broken if you use the raw value.

```python
# Bad - key with spaces or special characters will be wrong
key = record["s3"]["object"]["key"]   # "uploads/user+profile%20photo.jpg"

# Good - always decode
import urllib.parse
key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])  # "uploads/user profile photo.jpg"
```

**Notification configuration silently overwrites the existing configuration.** Calling `put_bucket_notification_configuration` replaces the entire notification config, not just the rule you are adding.

```python
# Bad - overwrites all existing notification rules
s3.put_bucket_notification_configuration(
    Bucket="my-bucket",
    NotificationConfiguration={
        "LambdaFunctionConfigurations": [new_rule]  # existing rules are deleted
    },
)

# Good - read existing config first, then merge
existing = s3.get_bucket_notification_configuration(Bucket="my-bucket")
existing.pop("ResponseMetadata", None)
existing.setdefault("LambdaFunctionConfigurations", []).append(new_rule)
s3.put_bucket_notification_configuration(
    Bucket="my-bucket", NotificationConfiguration=existing)
```

---

## Interview Angle

Common question forms:
- "How would you build an image processing pipeline triggered by S3 uploads?"
- "What are the differences between routing S3 events to Lambda directly vs through SQS?"
- "How do you handle duplicate S3 event notifications?"

Answer frame:
For the pipeline: S3 → Lambda trigger with prefix/suffix filter, Lambda reads the object, processes it, writes result. For Lambda vs SQS: direct Lambda is simpler but cannot batch or rate-limit; SQS enables batching, backpressure, DLQ retry, and decoupling. For deduplication: idempotent processing using the object key + ETag as a deduplication key, or Dynamo conditional writes.

---

## Related Notes

- [[s3-overview|S3 Overview]]
- [[lambda-triggers|Lambda Triggers]]
- [[sqs|SQS]]
- [[s3-versioning|S3 Versioning]]
- [[s3-python|S3 with Python (boto3)]]
