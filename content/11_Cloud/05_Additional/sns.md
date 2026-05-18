---
title: SNS (Simple Notification Service)
description: SNS is AWS's managed pub/sub service — a single published message is pushed to all subscribers simultaneously, enabling fan-out, alerts, and multi-consumer event distribution.
tags: [aws, cloud, layer-11, sns, messaging, pub-sub]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# SNS (Simple Notification Service)

> SNS is a push-based pub/sub service — you publish one message to a topic and SNS delivers it to every subscriber simultaneously, making it the correct choice for fan-out, alerts, and notifications.

---

## Quick Reference

**Core idea:**
- Publisher sends one message to a topic; SNS delivers it to all subscribers
- Subscriber types: Lambda, SQS, HTTP/HTTPS, email, SMS, mobile push
- Push-based: SNS pushes to subscribers — no polling required (unlike SQS)
- Message filtering: subscription filter policies let subscribers receive only matching messages
- SNS FIFO topics: ordered delivery with deduplication, only SQS FIFO queues as subscribers
- Fan-out pattern: SNS → multiple SQS queues, each processed independently

**Tricky points:**
- SNS delivery to HTTP/HTTPS endpoints retries with exponential backoff but does not guarantee delivery if the endpoint is down for an extended period
- Lambda subscribers require a resource-based policy on the Lambda function (just like S3) — the topic itself does not use event source mapping
- Message size limit: 256KB (same as SQS)
- For large payloads, use the SNS Extended Client Library (stores message body in S3, sends S3 reference)
- SNS does not retain messages — if a subscriber is unavailable at delivery time, the message is lost unless an SQS queue is in the subscription chain

---

## What It Is

SNS is a broadcast system, like a public address loudspeaker in a building. When you pick up the microphone (publish to a topic), every room that has opted into the channel (subscribers) hears the announcement simultaneously. It does not matter whether Room 101 is going to act on the announcement immediately, file it for later, or ignore it — the loudspeaker delivers to all subscribed rooms at the moment of broadcast. Contrast this with SQS, which is more like a suggestion box: producers drop notes in, consumers check the box at their own pace.

The architectural power of SNS is the fan-out pattern. A single event — say, a new order placed on an e-commerce site — needs to trigger multiple independent downstream processes: send an order confirmation email, update the inventory system, notify the warehouse, and record the event for analytics. Without SNS, the order service must know about all four downstream consumers and call them individually, creating tight coupling. With SNS, the order service publishes one message to a topic. Four SQS queues are subscribed to the topic. Each SQS queue feeds a separate Lambda function or consumer service. The order service knows nothing about the downstream consumers; new consumers are added by subscribing their SQS queue — no change to the order service required.

The key difference between SNS and SQS in terms of delivery semantics is durability. SQS retains messages for up to 14 days — a consumer can be down for hours and still process its messages when it comes back. SNS pushes to subscribers at the moment of publication. If a subscriber's HTTP endpoint is down, SNS retries according to its retry policy, but after a configured number of failures, the message is dropped. This is why the SNS → SQS fan-out pattern (rather than SNS → HTTP/Lambda directly) is the correct architecture for guaranteed processing: SQS provides the durability buffer, SNS provides the fan-out routing.

---

## How It Actually Works

Message filtering is one of SNS's most useful features for large-scale event routing. Each SQS queue or Lambda subscriber can define a filter policy — a JSON object matching against message attributes. Only messages whose attributes match the filter policy are delivered to that subscriber. This allows a single topic to serve as a routing backbone: an `order-events` topic receives all order events, but the `fulfillment-queue` subscription filters to `{"event_type": ["order_placed", "order_updated"]}` while the `analytics-queue` subscription receives all events unfiltered.

```python
import boto3
import json

sns = boto3.client("sns", region_name="us-east-1")
sqs = boto3.client("sqs", region_name="us-east-1")

# Create an SNS topic
topic_response = sns.create_topic(Name="order-events")
topic_arn = topic_response["TopicArn"]

# Create two SQS queues
fulfillment_queue = sqs.create_queue(QueueName="fulfillment-queue")
analytics_queue = sqs.create_queue(QueueName="analytics-queue")

# Get SQS queue ARNs
fulfillment_arn = sqs.get_queue_attributes(
    QueueUrl=fulfillment_queue["QueueUrl"], AttributeNames=["QueueArn"]
)["Attributes"]["QueueArn"]

analytics_arn = sqs.get_queue_attributes(
    QueueUrl=analytics_queue["QueueUrl"], AttributeNames=["QueueArn"]
)["Attributes"]["QueueArn"]

# Subscribe the fulfillment queue with a filter policy
fulfillment_sub = sns.subscribe(
    TopicArn=topic_arn,
    Protocol="sqs",
    Endpoint=fulfillment_arn,
    Attributes={
        "FilterPolicy": json.dumps({
            "event_type": ["order_placed", "order_updated"],
        }),
        "RawMessageDelivery": "true",  # deliver the raw message body, not SNS envelope
    },
)

# Subscribe the analytics queue without a filter (receives all events)
analytics_sub = sns.subscribe(
    TopicArn=topic_arn,
    Protocol="sqs",
    Endpoint=analytics_arn,
    Attributes={"RawMessageDelivery": "true"},
)

# Allow SNS to send messages to both SQS queues (resource-based policy on each queue)
def allow_sns_to_sqs(queue_url: str, queue_arn: str, topic_arn: str):
    policy = {
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "sns.amazonaws.com"},
            "Action": "sqs:SendMessage",
            "Resource": queue_arn,
            "Condition": {"ArnEquals": {"aws:SourceArn": topic_arn}},
        }],
    }
    sqs.set_queue_attributes(
        QueueUrl=queue_url,
        Attributes={"Policy": json.dumps(policy)},
    )

allow_sns_to_sqs(fulfillment_queue["QueueUrl"], fulfillment_arn, topic_arn)
allow_sns_to_sqs(analytics_queue["QueueUrl"], analytics_arn, topic_arn)


# Publish a message with attributes for filter routing
def publish_order_event(event_type: str, order: dict):
    response = sns.publish(
        TopicArn=topic_arn,
        Message=json.dumps(order),
        MessageAttributes={
            "event_type": {
                "DataType": "String",
                "StringValue": event_type,
            },
        },
    )
    return response["MessageId"]

# This message goes to BOTH queues (event_type="order_placed" matches fulfillment filter)
publish_order_event("order_placed", {"order_id": "123", "total": 99.99})

# This message only goes to analytics queue (event_type="order_shipped" does NOT match fulfillment filter)
publish_order_event("order_shipped", {"order_id": "123", "tracking": "1Z999"})
```

Subscribing a Lambda function to an SNS topic and granting SNS invoke permission:

```bash
# Subscribe Lambda to the topic
aws sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:123456789012:order-events \
    --protocol lambda \
    --notification-endpoint arn:aws:lambda:us-east-1:123456789012:function:order-notifier

# Grant SNS permission to invoke the Lambda function (resource-based policy)
aws lambda add-permission \
    --function-name order-notifier \
    --statement-id sns-invoke \
    --action lambda:InvokeFunction \
    --principal sns.amazonaws.com \
    --source-arn arn:aws:sns:us-east-1:123456789012:order-events
```

---

## How It Connects

SNS and SQS are complementary services — SNS provides fan-out routing, SQS provides durable buffering. Together they form the canonical AWS event distribution pattern.

[[sqs|SQS (Simple Queue Service)]] — the SNS → SQS fan-out pattern depends on understanding SQS queue configuration, DLQ setup, and the SQS permission model that allows SNS to write to the queue.

SNS topics that deliver to Lambda functions require the same resource-based permission model as S3 and EventBridge triggers. The Lambda IAM note covers both sides of the permission model.

[[lambda-iam|Lambda IAM Execution Role]] — covers the resource-based policy on Lambda functions that permits external services like SNS to invoke them.

---

## Common Misconceptions

Misconception 1: SNS guarantees that all subscribers receive every message.
Reality: SNS provides at-least-once delivery for supported subscriber types but does not guarantee delivery if a subscriber endpoint is persistently unavailable. HTTP/HTTPS endpoint subscriptions have a finite retry window after which undeliverable messages are discarded (unless a DLQ is configured on the SNS subscription). Lambda subscriptions are more durable (Lambda has its own retry policy), but the safest architecture for guaranteed processing remains SNS → SQS, where the queue provides durable buffering.

Misconception 2: `RawMessageDelivery` is the default and you get your message body directly.
Reality: By default, SNS wraps your message in a JSON envelope containing metadata fields (`Type`, `MessageId`, `TopicArn`, `Message`, `Timestamp`, `Signature`, etc.). The actual payload is inside the `Message` field. Setting `RawMessageDelivery=true` on the subscription delivers only the raw message body, which is what most SQS consumers and Lambda functions expect. Forgetting this means your consumer receives the SNS envelope and must parse `json.loads(message)["Message"]` to get the payload.

---

## Why It Matters in Practice

SNS solves the fan-out problem cleanly. Without it, every time a new consumer needs to react to an event, the producer must be modified to call the new consumer. With an SNS topic as the central distribution point, new consumers self-subscribe without producer changes. This pattern is the architectural backbone of event-driven microservices in AWS — order events, user sign-up events, and system health events all benefit from the topic model where producers and consumers are fully decoupled.

---

## What Breaks in Production

**Scenario 1: Missing SQS queue policy causes SNS delivery to silently fail**

```python
# Mistake: subscribe an SQS queue to an SNS topic but forget the queue resource policy
sns.subscribe(TopicArn=topic_arn, Protocol="sqs", Endpoint=queue_arn)
# Messages published to the topic are silently dropped — no error on publish
# SNS cannot write to the queue without explicit queue permission

# Fix: add the resource-based policy to the SQS queue (see allow_sns_to_sqs above)
```

**Scenario 2: Consumer not handling the SNS envelope**

```python
# Mistake: treating the SQS message body as the original payload
# when RawMessageDelivery is not enabled
def process_sqs_message(body_str: str):
    data = json.loads(body_str)  # data is the SNS envelope, not the order
    order_id = data["order_id"]  # KeyError — the actual data is in data["Message"]

# Fix: either enable RawMessageDelivery on the subscription,
# or unwrap the SNS envelope in the consumer
def process_sqs_message(body_str: str):
    envelope = json.loads(body_str)
    # If SNS envelope, unwrap; if raw, use directly
    if "Message" in envelope and "TopicArn" in envelope:
        data = json.loads(envelope["Message"])
    else:
        data = envelope
    order_id = data["order_id"]
```

---

## Interview Angle

Common question forms:
- "What is the difference between SNS and SQS?"
- "Describe the SNS fan-out pattern and why you would use it."
- "How does SNS message filtering work?"

Answer frame:
Contrast push (SNS) vs pull (SQS), no retention (SNS) vs durable buffer (SQS). Explain the fan-out pattern: one SNS publish → multiple SQS queues, each processed independently. Describe message filtering with subscription filter policies as an attribute-based routing mechanism. Mention that Lambda subscribers need a resource-based policy, not an event source mapping.

---

## Related Notes

- [[sqs|SQS (Simple Queue Service)]]
- [[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]]
- [[lambda-iam|Lambda IAM Execution Role]]
- [[pub-sub-pattern|Pub/Sub Pattern]]
- [[message-queues|Message Queues]]
