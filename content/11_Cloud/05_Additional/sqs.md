---
title: 43 - SQS (Simple Queue Service)
description: SQS is AWS's managed message queue - it decouples producers from consumers and provides durable, at-least-once message delivery with configurable retention and dead-letter queue support.
tags: [aws, cloud, layer-11, sqs, messaging, queues]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# SQS (Simple Queue Service)

> SQS is a managed message queue that decouples the components of a distributed system - producers write messages, consumers poll and process them independently, and SQS durably buffers everything in between.

---

## Quick Reference

**Core idea:**
- Two queue types: Standard (at-least-once, unordered, near-unlimited throughput) and FIFO (exactly-once, ordered, 3000 msg/s with batching)
- Visibility timeout: how long a message is hidden after being received - if not deleted before expiry, it reappears
- Message retention: 1 minute to 14 days (default 4 days)
- Dead-letter queue (DLQ): receives messages that fail processing N times (`maxReceiveCount`)
- Long polling: `WaitTimeSeconds=20` reduces empty responses and API cost vs short polling
- Max message size: 256KB; for larger payloads use SQS Extended Client or store in S3 and send the S3 key

**Tricky points:**
- Standard queues deliver at-least-once - design consumers to be idempotent
- FIFO deduplication ID prevents the same message from being processed twice within 5 minutes
- Visibility timeout must exceed consumer processing time - messages reappear if the consumer does not delete them in time
- SQS does not push messages - consumers must poll (Lambda's event source mapping handles this for you)
- Deleting a message requires the receipt handle from the receive call, not the message ID

---

## What It Is

SQS is like a managed post office between two offices in a building. The first office (the producer) drops letters (messages) into a mailbox (the queue) whenever it has something to communicate. The second office (the consumer) visits the mailbox periodically, picks up letters, reads them, and discards them when done. The post office guarantees that every letter will be held safely until it is picked up - it does not matter if the second office is closed for an hour, on holiday, or overwhelmed with other work. The letters wait. The first office never needs to know whether the second office is available; it drops letters and moves on.

This decoupling is the architectural superpower of message queues. Without SQS, a producer calling a downstream service synchronously is coupled to that service's availability. If the downstream service is slow, the producer blocks. If it is down, the request fails. If the downstream service needs to be scaled or replaced, the producer must be modified. With SQS in between, the producer fires a message and is free. The downstream service processes at its own pace, scales independently, and can be taken down and restarted without the producer ever noticing.

The distinction between Standard and FIFO queues maps to the distinction between "best effort with high throughput" and "guaranteed ordering with exactly-once delivery." Standard queues deliver messages in roughly the order they were sent, with occasional reordering, and guarantee at-least-once delivery - meaning the same message may appear more than once. FIFO queues preserve insertion order strictly and deduplicate messages within a five-minute deduplication window, but cap throughput at 3,000 messages per second with batching or 300 without. Most workloads tolerate Standard queue semantics if consumers are written to be idempotent; FIFO queues are necessary when ordering and deduplication are business requirements, not just nice-to-haves.

---

## How It Actually Works

The core operations are send, receive, and delete. Receiving a message sets the visibility timeout - the message disappears from the queue for other consumers for the timeout duration. The consumer must delete the message (using the receipt handle) before the timeout expires. If it does not, the message becomes visible again and another consumer (or the same one) will receive it. This mechanism provides durability: if a consumer crashes mid-processing, the message is not lost - it reappears after the visibility timeout and is retried.

```python
import boto3
import json
import time

sqs = boto3.client("sqs", region_name="us-east-1")

QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123456789012/my-processing-queue"

# --- Producer: send messages ---
def send_order(order: dict) -> str:
    response = sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(order),
        MessageAttributes={
            "OrderType": {
                "StringValue": order.get("type", "standard"),
                "DataType": "String",
            }
        },
    )
    return response["MessageId"]

# Send a batch (up to 10 messages, up to 256KB total)
entries = [
    {
        "Id": str(i),
        "MessageBody": json.dumps({"order_id": i, "type": "express"}),
    }
    for i in range(5)
]
sqs.send_message_batch(QueueUrl=QUEUE_URL, Entries=entries)


# --- Consumer: poll, process, delete ---
def consume_messages():
    while True:
        response = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=10,      # 1–10 per receive call
            WaitTimeSeconds=20,          # long polling - wait up to 20s for messages
            VisibilityTimeout=60,        # hide message for 60s while processing
            MessageAttributeNames=["All"],
        )

        messages = response.get("Messages", [])
        if not messages:
            print("Queue empty, waiting...")
            continue

        for message in messages:
            receipt_handle = message["ReceiptHandle"]
            body = json.loads(message["Body"])

            try:
                process_order(body)
                # Delete only after successful processing
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
                print(f"Processed and deleted: {message['MessageId']}")
            except Exception as exc:
                print(f"Failed to process {message['MessageId']}: {exc}")
                # Do NOT delete - message will reappear after VisibilityTimeout


def process_order(order: dict):
    print(f"Processing order: {order}")
    time.sleep(1)  # simulate work


# --- Create a queue with a dead-letter queue ---
def setup_queues():
    # Create the DLQ first
    dlq_response = sqs.create_queue(
        QueueName="my-processing-queue-dlq",
        Attributes={"MessageRetentionPeriod": "1209600"},  # 14 days
    )
    dlq_url = dlq_response["QueueUrl"]
    dlq_attrs = sqs.get_queue_attributes(
        QueueUrl=dlq_url, AttributeNames=["QueueArn"]
    )
    dlq_arn = dlq_attrs["Attributes"]["QueueArn"]

    # Create the main queue with DLQ redrive policy
    sqs.create_queue(
        QueueName="my-processing-queue",
        Attributes={
            "VisibilityTimeout": "60",
            "MessageRetentionPeriod": "345600",  # 4 days
            "RedrivePolicy": json.dumps({
                "deadLetterTargetArn": dlq_arn,
                "maxReceiveCount": "3",  # move to DLQ after 3 failed attempts
            }),
        },
    )
```

---

## How It Connects

SQS is the most common trigger source for Lambda functions in data processing pipelines. The Lambda event source mapping polls SQS on your behalf, and the SQS queue's visibility timeout must be configured in coordination with the Lambda function's timeout.

[[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]] - details the event source mapping configuration, partial batch failure handling, and how Lambda and SQS interact during failures and retries.

SQS is frequently paired with SNS in the fan-out pattern: an SNS topic receives one message and fans it out to multiple SQS queues, each serving a different consumer. This pattern decouples producers from multiple downstream processing pipelines.

[[sns|SNS (Simple Notification Service)]] - covers the SNS-to-SQS fan-out pattern, topic subscriptions, and message filtering.

---

## Common Misconceptions

Misconception 1: Deleting a message from SQS means it was processed successfully.
Reality: Deleting a message only means the consumer called `delete_message`. Whether the processing logic inside the consumer actually succeeded is entirely up to your code. The responsibility for deleting a message only after confirming successful processing falls on the consumer. A consumer that deletes immediately on receive and then crashes will silently lose the message.

Misconception 2: Standard queue messages are delivered in the order they were sent.
Reality: Standard queues offer best-effort ordering, which means messages are generally delivered in order but with no guarantee. Under load, reordering can and does occur. If strict ordering matters - payment events, state machine transitions - use FIFO queues or implement sequence handling in your consumer logic.

---

## Why It Matters in Practice

SQS is the default choice for decoupling services in AWS architectures, particularly anywhere a producer sends work that may burst unpredictably or where the consumer needs to scale independently. The combination of durable message retention, visibility timeout, and DLQ provides a complete reliability model: messages are not lost on consumer failure, failed messages eventually reach the DLQ for inspection, and the consumer can be scaled to match queue depth. Every Python developer deploying to AWS will encounter SQS as a Lambda trigger or as an explicit polling consumer.

---

## What Breaks in Production

**Scenario 1: Visibility timeout shorter than processing time causes duplicate processing**

```python
# Mistake: receive with 30s visibility, processing takes 45s
response = sqs.receive_message(
    QueueUrl=QUEUE_URL,
    VisibilityTimeout=30,   # message reappears at 30s
    WaitTimeSeconds=20,
)
# ... processing takes 45 seconds ...
# Message reappears at 30s, another consumer picks it up → duplicate processing

# Fix: set visibility timeout well above expected processing time
# Or extend the visibility timeout mid-processing
sqs.change_message_visibility(
    QueueUrl=QUEUE_URL,
    ReceiptHandle=receipt_handle,
    VisibilityTimeout=120,  # extend by another 120 seconds
)
```

**Scenario 2: Short polling wastes money and produces empty responses**

```python
# Mistake: short polling loops generate many empty responses and API calls
while True:
    response = sqs.receive_message(QueueUrl=QUEUE_URL, MaxNumberOfMessages=10)
    # WaitTimeSeconds defaults to 0 - returns immediately even if queue is empty
    # 1000s of empty API calls per hour accumulate cost

# Fix: use long polling
response = sqs.receive_message(
    QueueUrl=QUEUE_URL,
    MaxNumberOfMessages=10,
    WaitTimeSeconds=20,   # wait up to 20s - SQS returns when messages arrive or timeout
)
```

---

## Interview Angle

Common question forms:
- "Explain how SQS visibility timeout works and why it matters."
- "When would you use a FIFO queue versus a Standard queue?"
- "What is a dead-letter queue and how do you configure one?"

Answer frame:
Walk through the receive-process-delete lifecycle and explain that the visibility timeout is the retry mechanism. Distinguish Standard (at-least-once, unordered, high throughput) from FIFO (exactly-once, ordered, 3000 msg/s). Describe the DLQ as the overflow bucket for messages that repeatedly fail. Mention that consumers must be idempotent for Standard queues.

---

## Related Notes

- [[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]]
- [[sns|SNS (Simple Notification Service)]]
- [[lambda-concurrency|Lambda Concurrency and Scaling]]
- [[message-queues|Message Queues]]
- [[pub-sub-pattern|Pub/Sub Pattern]]
