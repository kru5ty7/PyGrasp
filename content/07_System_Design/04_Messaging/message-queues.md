---
title: 01 - Message Queues
description: "How message queues decouple producers from consumers, the at-least-once vs exactly-once delivery guarantee tradeoff, and why dead letter queues are essential for reliability."
tags: [message-queues, async, producers-consumers, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Message Queues

> A message queue is a contract between two services that they can operate independently — and understanding the delivery guarantees is what determines whether that independence is safe.

---

## Quick Reference

**Core idea:**
- A message queue buffers messages from producers until consumers are ready to process them
- Producers send to the queue without knowing who processes the message; consumers pull from the queue
- At-least-once delivery: the queue retries failed messages — consumers must be idempotent
- Exactly-once delivery: technically possible but expensive; requires coordination between queue and consumer
- Dead letter queue (DLQ): messages that fail processing after N retries are moved here for inspection

**Tricky points:**
- "At-least-once" means a message can be delivered multiple times — your consumer must handle duplicates
- Message ordering is only guaranteed within a single queue partition (or not at all in some systems)
- A consumer that acknowledges a message before completing processing will lose that message on crash
- A consumer that crashes before acknowledging will receive the message again — this is at-least-once
- Poison messages (messages that always fail processing) block the queue unless a DLQ is configured

---

## What It Is

Imagine a restaurant where customers place orders with a waiter, and the waiter writes the orders on slips and puts them in a basket. The kitchen picks up slips from the basket when it is ready. The waiter (producer) does not wait for the kitchen (consumer) to finish each dish before taking the next order. The basket (queue) buffers orders between the front-of-house and back-of-house. If the kitchen falls behind, the basket fills up. If the kitchen is fast, the basket is nearly empty. Neither the waiter nor the kitchen needs to know about each other — only the format of the order slip matters.

This is the core value of a message queue: temporal decoupling between producers and consumers. The producer sends a message and immediately moves on to the next task, without waiting for processing to complete. The consumer processes messages at its own pace. This decoupling has several important consequences. First, services can fail and restart independently — a consumer crash does not affect the producer. Second, the queue absorbs traffic spikes: if a thousand orders arrive at once but the kitchen can only handle ten at a time, the queue absorbs the spike and consumers drain it gradually. Third, consumer throughput can be scaled by adding more consumer instances.

Delivery guarantees are the most important conceptual aspect of message queues. At-most-once delivery means a message is delivered zero or one times — if the consumer crashes, the message is not redelivered. This is simple but risks message loss. At-least-once delivery means a message is delivered one or more times — if the consumer crashes before acknowledging, the message is redelivered. This is safe (no message loss) but requires consumer idempotency, because the same message may be processed multiple times. Exactly-once delivery is conceptually desirable but extremely difficult: it requires distributed coordination that is expensive and complex. Most production systems use at-least-once with idempotent consumers.

The dead letter queue is a safety net for poison messages — messages that consistently fail processing. Without a DLQ, a message that triggers an application bug is retried forever (or blocks the queue). With a DLQ, after N failed delivery attempts, the message is moved to the DLQ. Operators can inspect the DLQ, fix the bug, and replay messages. This prevents one bad message from blocking an entire queue.

---

## How It Actually Works

Message acknowledgment is the mechanism behind at-least-once delivery. When a consumer receives a message, the queue marks it as "in flight" — it is not yet deleted from the queue. The consumer processes the message and, if successful, sends an acknowledgment. The queue then deletes the message. If the consumer crashes before acknowledging, the "in flight" timer expires and the queue redelivers the message to the next available consumer. The practical implication: the consumer must acknowledge only after successfully completing all processing — including any database writes or downstream API calls. Acknowledging before processing is complete risks silent message loss.

Idempotency is the design principle that makes at-least-once safe. An operation is idempotent if performing it multiple times has the same effect as performing it once. A consumer that sends a welcome email must be idempotent: if it receives the same "new user registered" message twice and sends two welcome emails, that is a user experience failure. Idempotency is implemented by tracking which messages have already been processed (using the message's unique ID as a key in a database or distributed set) and skipping messages that were previously processed.

```python
import redis
import json
import boto3
from typing import Callable

sqs = boto3.client('sqs')
r = redis.Redis()

QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123/my-queue"
DLQ_URL = "https://sqs.us-east-1.amazonaws.com/123/my-queue-dlq"

def process_messages(handler: Callable[[dict], None]):
    """Poll SQS and process messages with idempotency and DLQ handling."""
    while True:
        response = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=20,          # long polling — reduces empty responses
            VisibilityTimeout=30,        # how long the message is invisible to others
        )

        for message in response.get('Messages', []):
            message_id = message['MessageId']
            receipt_handle = message['ReceiptHandle']
            body = json.loads(message['Body'])

            # Idempotency check: have we already processed this message?
            already_processed = r.get(f"processed_msg:{message_id}")
            if already_processed:
                # Already processed — safe to acknowledge without reprocessing
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
                continue

            try:
                handler(body)  # application-level processing

                # Mark as processed BEFORE acknowledging
                r.setex(f"processed_msg:{message_id}", 86400, "1")  # 24h idempotency window

                # Acknowledge AFTER successful processing
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)

            except Exception as e:
                # Do NOT delete the message — let the VisibilityTimeout expire
                # SQS will redeliver; after max retries, it moves to DLQ
                print(f"Processing failed for {message_id}: {e}")
```

Message ordering is a common misconception point. A single SQS standard queue provides best-effort ordering with no guarantees — messages may arrive out of order. SQS FIFO queues guarantee ordering within a message group, with lower throughput. Kafka guarantees ordering within a single partition but not across partitions. RabbitMQ queues process messages in FIFO order within a single queue. If ordering matters for your use case, the choice of queue technology and configuration must reflect this.

Queue depth — the number of messages waiting to be processed — is a critical operational metric. If queue depth grows continuously, consumers cannot keep up with producers. The remedy is scaling consumers. If queue depth is consistently near zero, consumers are over-provisioned. Auto-scaling consumer groups based on queue depth (AWS Auto Scaling based on `ApproximateNumberOfMessages`) is the standard operational pattern.

---

## How It Connects

The pub/sub pattern extends message queues by allowing a single message to be delivered to multiple independent consumers, each receiving their own copy.

[[pub-sub-pattern|Pub/Sub Pattern]]

Kafka is a high-throughput message system that provides persistence and consumer group semantics beyond what traditional queues offer. Understanding basic queue semantics makes Kafka's additions clear.

[[kafka-system-design|Kafka in System Design]]

Event-driven architecture is the broader design pattern of which message queues are a component. Understanding EDA helps clarify when a queue is the right mechanism.

[[event-driven-architecture|Event-Driven Architecture]]

---

## Common Misconceptions

Misconception 1: "Message queues guarantee exactly-once delivery."
Reality: Exactly-once delivery requires distributed coordination between the queue and the consumer's processing system. Most queue systems (SQS, RabbitMQ) provide at-least-once. Kafka provides exactly-once semantics only within the Kafka ecosystem (idempotent producers + transactional consumers), and with significant performance overhead. For most production systems, at-least-once with idempotent consumers is the practical standard.

Misconception 2: "I should acknowledge the message as soon as I receive it."
Reality: Acknowledging before processing means that if the consumer crashes during processing, the message is deleted from the queue and never processed — a silent message loss. Always perform all processing first, then acknowledge. If the work fails, do not acknowledge and let the queue's retry mechanism handle it.

Misconception 3: "A queue handles backpressure automatically."
Reality: A queue buffers messages and allows consumers to process at their own rate — this is temporal buffering. But if the producer rate permanently exceeds the consumer rate, the queue grows without bound. Some queue systems have depth limits; exceeding them causes new messages to be rejected. Backpressure must be handled by monitoring queue depth and scaling consumers, or by applying admission control on the producer side.

---

## Why It Matters in Practice

Message queues are how you decouple components that should not be directly coupled. Sending an email notification, triggering a video encoding job, updating a search index, or running a fraud detection check — these are all tasks that should happen asynchronously after a user action, not synchronously in the request handler. Doing them synchronously makes the user wait for all of them to complete. Moving them to a queue makes the user experience instant and the work happens in the background.

The idempotency requirement is the most important discipline. Every consumer must be designed idempotent from the beginning — retrofitting idempotency onto a non-idempotent consumer is painful. Always ask: "What happens if this message is delivered twice?" before writing the consumer.

---

## Interview Angle

Common question forms:
- "When would you use a message queue in a system design?"
- "What is at-least-once delivery and what does it require from the consumer?"
- "What is a dead letter queue and why is it important?"

Answer frame:
Explain the core value: temporal decoupling and traffic spike buffering. Describe at-least-once vs exactly-once: at-least-once is practical; exactly-once is expensive. Explain the acknowledgment protocol: process first, then acknowledge. Describe idempotency: why it is required for at-least-once, how to implement it with message ID tracking. Explain DLQ: poison message handling, operator inspection, replay capability.

---

## Related Notes

- [[pub-sub-pattern|Pub/Sub Pattern]]
- [[rabbitmq|RabbitMQ]]
- [[kafka-system-design|Kafka in System Design]]
- [[event-driven-architecture|Event-Driven Architecture]]
- [[idempotency|Idempotency]]
