---
title: 02 - Pub/Sub Pattern
description: "The publish-subscribe pattern decouples event producers from multiple consumers via topics  -  understanding it versus point-to-point queues clarifies when each is appropriate."
tags: [pub-sub, messaging, events, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Pub/Sub Pattern

> Pub/sub is the messaging pattern that enables true fan-out: one event, produced once, consumed independently by many services  -  and the decoupling it provides is what makes event-driven architectures possible.

---

## Quick Reference

**Core idea:**
- In pub/sub, publishers send messages to a topic, not to specific consumers
- Subscribers receive all messages published to the topics they subscribe to
- Fan-out: one published message reaches all subscribers independently
- Topics separate the concern of message routing from both producer and consumer logic
- Contrast with point-to-point (queue): one message is consumed by exactly one consumer

**Tricky points:**
- In a pure pub/sub, if no subscriber is active when a message is published, the message is lost (unlike a queue which persists it)
- Kafka and Google Pub/Sub persist messages and replay them for new subscribers  -  this is "durable pub/sub"
- A single subscriber receiving all messages is functionally a queue  -  pub/sub and queues are related patterns
- Subscriber ordering: in most pub/sub systems, different subscribers may process messages in different orders
- Topic design is an architectural decision  -  too many fine-grained topics or too few coarse-grained topics both cause problems

---

## What It Is

Imagine a news wire service. Journalists write stories and send them to the news wire (the topic). Every newspaper that subscribes to the news wire receives every story, independently. The Los Angeles Times does not "compete" with the New York Times for stories  -  each gets its own copy. If the Wall Street Journal subscribes later, it can receive future stories. If a newspaper's printing press breaks down, it can resume receiving stories when it comes back online (if the wire service holds them). The journalist does not know or care which newspapers receive the story.

This is publish-subscribe: a publisher sends to a topic, and any number of subscribers receive independent copies. The key property is fan-out: one message is multiplied into as many copies as there are subscribers, and each subscriber processes its copy independently, at its own pace, without interfering with other subscribers.

The contrast with a point-to-point queue is fundamental. In a queue, one producer sends messages and one consumer (from a pool of consumers) receives each message  -  work is distributed. In pub/sub, one producer sends to a topic and all subscribers receive every message  -  work is broadcast. Use a queue when you want load distribution. Use pub/sub when you want event broadcasting.

The classic use case for pub/sub is event notification: a user signs up. One service sends a welcome email. Another service creates default preferences. Another updates an analytics system. Another triggers an onboarding tour. Each service subscribes to the `user.created` topic and processes the event independently. The signup service does not know about or depend on any of these downstream services. Adding a new downstream service is purely additive  -  the signup service requires no change.

---

## How It Actually Works

The underlying mechanism varies by platform, but the logical model is consistent. Google Cloud Pub/Sub, AWS SNS + SQS fan-out pattern, RabbitMQ topic exchanges, and Kafka with consumer groups all implement variations of pub/sub semantics. In Google Pub/Sub, a publisher creates a topic and publishes messages to it. Subscribers create subscriptions to a topic. Each subscription receives a copy of every message published to the topic. Messages are retained for 7 days by default, allowing subscribers that were offline to catch up.

The SNS + SQS fan-out is a common AWS pattern for durable pub/sub. SNS (Simple Notification Service) implements the topic and fan-out. Each subscriber is an SQS queue (not a service directly). SNS sends one copy of each message to each subscribed SQS queue. Each service has its own SQS queue and reads from it independently. This gives each subscriber its own message buffer (handling different processing speeds independently) while achieving fan-out via SNS. If one subscriber is slow, it does not block others  -  they each drain their own queue.

```python
import boto3
import json

sns = boto3.client('sns')
sqs = boto3.client('sqs')

# Create a topic and subscribe two queues to it
USER_CREATED_TOPIC_ARN = "arn:aws:sns:us-east-1:123:user-created"
EMAIL_QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123/email-service"
ANALYTICS_QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123/analytics-service"

def publish_user_created_event(user_id: int, email: str):
    """Publisher: send event to topic  -  doesn't know who subscribes."""
    sns.publish(
        TopicArn=USER_CREATED_TOPIC_ARN,
        Message=json.dumps({
            "event": "user.created",
            "user_id": user_id,
            "email": email,
            "timestamp": "2026-05-18T10:00:00Z"
        }),
        MessageAttributes={
            "event_type": {
                "DataType": "String",
                "StringValue": "user.created"
            }
        }
    )

# Email service subscriber  -  processes its own copy independently
def email_service_handler(message: dict):
    user_id = message["user_id"]
    email = message["email"]
    send_welcome_email(email)  # this service's specific action
    print(f"Welcome email sent to {email} for user {user_id}")

# Analytics service subscriber  -  same event, different processing
def analytics_service_handler(message: dict):
    user_id = message["user_id"]
    record_signup_event(user_id)  # completely different action on same event
    print(f"Signup event recorded for user {user_id}")
```

Topic design is a subtle architectural decision. Too coarse-grained topics (one `user.events` topic for all user-related events) means every subscriber receives every type of user event and must filter for the ones it cares about  -  wasting processing on irrelevant events. Too fine-grained topics (one topic per event type per user segment) creates hundreds of topics that are operationally difficult to manage and reason about. The convention is: one topic per meaningful business event type (`user.created`, `order.placed`, `payment.completed`). Subscribers receive only events they explicitly subscribe to.

Message filtering reduces the wasted work in coarse-grained topics. SNS supports subscription filter policies that prevent delivery of messages that do not match attribute criteria. A service that only cares about premium users can filter on a `plan: premium` message attribute, receiving only relevant messages without processing all user events.

---

## Visualizer

<iframe src="/static/visualizers/pub-sub-pattern.html" style="width:100%;height:450px;border:none;border-radius:8px;" title="Pub/Sub Pattern Visualizer"></iframe>

---

## How It Connects

When exactly-one-consumer semantics is needed instead of fan-out, a message queue is the right pattern. Pub/sub and message queues are complementary, not competing.

[[message-queues|Message Queues]]

RabbitMQ implements pub/sub through its exchange system. Topic exchanges and fanout exchanges implement different variants of the pattern.

[[rabbitmq|RabbitMQ]]

Kafka's consumer group mechanism blends pub/sub and queue semantics: multiple consumer groups each receive all messages (pub/sub fan-out), but within a group, each message goes to only one consumer (queue load distribution).

[[kafka-system-design|Kafka in System Design]]

---

## Common Misconceptions

Misconception 1: "Pub/sub is the same as a message queue."
Reality: A message queue distributes work across consumers  -  each message is processed by one consumer. Pub/sub broadcasts messages to all subscribers  -  each message is processed by all subscribers independently. The right choice depends on whether you want load balancing (queue) or event notification (pub/sub). Many systems use both: pub/sub for fan-out, followed by a queue per subscriber for load-balanced consumption.

Misconception 2: "If a subscriber goes down, it misses messages forever."
Reality: In durable pub/sub systems (Kafka, Google Pub/Sub, SNS+SQS), messages are persisted and can be replayed. If a subscriber goes down and comes back up, it processes messages from where it left off. In ephemeral pub/sub systems (Redis Pub/Sub, basic WebSocket pub/sub), messages are lost if no subscriber is listening at the moment of publication. Know which you are using.

Misconception 3: "Pub/sub solves all service coupling problems."
Reality: Pub/sub decouples services temporally (they do not need to be online simultaneously) and logically (they do not know about each other). But it introduces temporal coupling through the shared event schema. If the publisher changes the format of `user.created` events, all subscribers break. Schema evolution must be managed explicitly  -  typically through versioning, backward-compatible schema changes, or a schema registry.

---

## Why It Matters in Practice

Pub/sub is the architectural foundation for building event-driven systems. Every feature that should trigger multiple independent side effects  -  sending notifications, updating secondary indexes, triggering workflows, recording analytics  -  benefits from pub/sub decoupling. Without it, the code that creates a user must know about and call every downstream service: email, analytics, preferences, onboarding. With pub/sub, the user service publishes one event and is done. Adding a new downstream service requires no change to the user service.

The operational discipline is monitoring per-subscriber queue depth, delivery latency, and failed message handling (DLQ). Because each subscriber processes independently, one subscriber falling behind does not affect others  -  but you must notice it before the queue grows so large that old messages expire.

---

## Interview Angle

Common question forms:
- "What is the difference between a message queue and pub/sub?"
- "How would you use pub/sub when a user creates an account?"
- "What happens if a subscriber goes down in a pub/sub system?"

Answer frame:
Define pub/sub: publisher sends to topic, all subscribers receive a copy (fan-out). Contrast with queue: single consumer per message (work distribution). Use case: one event triggers multiple independent services. Explain durability: ephemeral vs durable pub/sub. Describe fan-out in AWS: SNS topic + SQS queues per subscriber. Discuss schema coupling: the hidden coupling in pub/sub is the event schema, requiring careful versioning.

---

## Related Notes

- [[message-queues|Message Queues]]
- [[rabbitmq|RabbitMQ]]
- [[kafka-system-design|Kafka in System Design]]
- [[event-driven-architecture|Event-Driven Architecture]]
