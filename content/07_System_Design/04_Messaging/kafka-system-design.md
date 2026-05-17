---
title: 04 - Kafka in System Design
description: "Kafka from a system design perspective — partitions for parallelism, consumer groups for scaling, message retention for replay, and when Kafka is the right choice."
tags: [kafka, streaming, partitions, consumer-groups, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Kafka in System Design

> Kafka is not a message queue — it is a distributed, replicated, persistent log, and understanding that distinction changes how you design every system that uses it.

---

## Quick Reference

**Core idea:**
- Kafka topics are divided into partitions; each partition is an ordered, append-only log
- Partitions enable parallelism: N partitions allow N consumers in a group to process concurrently
- Consumer groups provide load balancing: each partition is assigned to exactly one consumer per group
- Messages are retained for a configurable time (default 7 days) — consumers can replay from any offset
- Replication: each partition has one leader and multiple follower replicas for fault tolerance

**Tricky points:**
- Ordering is guaranteed within a partition, not across partitions — if global ordering matters, use one partition
- Adding partitions later is possible but changes which partition a key hashes to — affects ordering guarantees
- A consumer group with more consumers than partitions leaves some consumers idle — useless horizontal scaling
- Kafka does not push to consumers — consumers poll (pull) from the broker
- Consumer offset management: "committing" an offset means "I have processed up to this point"

---

## What It Is

Think of a train system with multiple tracks running between cities. Each track carries trains in one direction: departing trains add cars to the end of the train, and arriving cities receive cars from the front. The track is ordered, persistent, and can be replayed — if a city missed receiving some cars, it can ask the track to resend from the point it last received. Multiple cities can ride the same track independently, each at their own position.

This is Apache Kafka. A Kafka cluster stores streams of messages in topics. A topic is divided into partitions. Each partition is an append-only, ordered log. Producers write to the end of partitions. Consumers read from partitions at their own pace, tracking their position with an offset. The broker retains all messages for a configurable time period, allowing consumers to replay from any point.

The key insight that makes Kafka different from a traditional message queue is retention. In RabbitMQ or SQS, a message is deleted after it is acknowledged. In Kafka, messages persist for days or weeks regardless of whether they have been consumed. This enables: new consumers subscribing to a topic and reading all historical messages; a consumer replaying events after a bug fix; multiple independent consumer groups reading the same topic without interfering with each other. Kafka is a durable, replayable event log, not a transient delivery mechanism.

Partitions are the unit of parallelism. A single partition can only be read by one consumer per consumer group at a time (this is the invariant that guarantees per-partition ordering within a group). If a topic has 6 partitions and a consumer group has 3 consumers, each consumer handles 2 partitions. If the group has 6 consumers, each handles 1 partition. If the group has 7 consumers, one consumer is idle — Kafka cannot distribute one partition across two consumers (that would break ordering). This means maximum parallelism for a consumer group equals the number of partitions.

---

## How It Actually Works

Partition assignment within a consumer group is handled by a group coordinator (a Kafka broker) and the consumer group's leader (the first consumer to join). When consumers join or leave the group, a rebalance occurs: partitions are reassigned among the current members. During a rebalance, no consumer in the group can make progress (they are paused). Large consumer groups with frequent join/leave events (due to rolling deployments) can spend significant time in rebalances. Kafka 2.4+ introduced "incremental cooperative rebalancing" which assigns only the affected partitions rather than all partitions, reducing rebalance disruption.

Offset management is how consumers track their progress. Every message in a partition has an incrementing offset number. When a consumer reads a batch of messages and processes them, it commits the highest offset it has successfully processed to a special Kafka topic (`__consumer_offsets`). If the consumer crashes and restarts, it reads its last committed offset and resumes from there. Committing offsets too early (before processing completes) risks losing messages if the consumer crashes. Committing too late (infrequently) means replaying already-processed messages after a restart. The trade-off between commit frequency and processing overhead is configurable.

Message routing to partitions is determined by the producer. If a message has no key, the producer uses round-robin across partitions. If a message has a key, the producer hashes the key to determine the partition: `partition = hash(key) % num_partitions`. This ensures that all messages with the same key always go to the same partition, preserving per-key ordering. This is how user activity events for the same user always land on the same partition and are processed in order by a single consumer.

```python
from confluent_kafka import Producer, Consumer, KafkaError
import json

# Producer: publish user activity events
producer = Producer({'bootstrap.servers': 'kafka:9092'})

def publish_user_event(user_id: int, event_type: str, payload: dict):
    message = json.dumps({
        "event_type": event_type,
        "user_id": user_id,
        **payload
    })
    # Key = user_id: ensures all events for a user land on the same partition
    producer.produce(
        topic='user-activity',
        key=str(user_id),  # partition routing key
        value=message,
        callback=lambda err, msg: print(f"Delivery failed: {err}" if err else None)
    )
    producer.poll(0)  # trigger callbacks

producer.flush()  # ensure all messages are delivered before shutdown

# Consumer group: three consumers, each handling a subset of partitions
consumer = Consumer({
    'bootstrap.servers': 'kafka:9092',
    'group.id': 'activity-processor',         # consumer group ID
    'auto.offset.reset': 'earliest',          # start from beginning for new groups
    'enable.auto.commit': False,              # manual offset management
})
consumer.subscribe(['user-activity'])

def process_messages():
    try:
        while True:
            msg = consumer.poll(timeout=1.0)
            if msg is None:
                continue
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    continue  # end of partition — normal
                raise Exception(msg.error())

            event = json.loads(msg.value())

            # Process the event
            handle_user_activity(event)

            # Commit offset AFTER successful processing
            consumer.commit(asynchronous=False)

    except KeyboardInterrupt:
        pass
    finally:
        consumer.close()
```

Kafka's retention policy controls how long messages are kept. The default is 7 days of log retention or a configurable byte size limit per partition. When a partition log file ages beyond the retention period, it is deleted. If a consumer is down for longer than the retention period, it loses access to the messages it missed — a "message lag" that cannot be recovered. For event sourcing or audit log use cases, retention might be set to years or "never delete" (log compaction instead, which keeps only the latest value per key).

Log compaction is an alternative to time-based retention. Instead of deleting old messages by age, Kafka compacts the log to keep only the most recent message per key. This is ideal for topics that represent the current state of entities: if each message represents the latest profile for a user ID, compaction means the topic always contains the most recent profile for each user, with old versions removed. This turns a Kafka topic into a materialized view of current state.

---

## How It Connects

The at-least-once delivery guarantee in Kafka (with offset management) connects to the idempotency requirement discussed for message queues. The same pattern applies.

[[message-queues|Message Queues]]

Event-driven architecture relies on Kafka's characteristics: persistent messages, replay, consumer groups, and high throughput. Understanding Kafka is a prerequisite for understanding how large-scale EDA is implemented.

[[event-driven-architecture|Event-Driven Architecture]]

The outbox pattern solves the dual-write problem when writing to both a database and a Kafka topic. CDC tools like Debezium produce Kafka messages from the database's replication log.

[[outbox-pattern|Outbox Pattern]]

---

## Common Misconceptions

Misconception 1: "Kafka guarantees exactly-once processing end to end."
Reality: Kafka supports idempotent producers (preventing producer-level duplicates) and transactional producers/consumers (atomic read-process-write within Kafka). This provides exactly-once within the Kafka topology. However, if your consumer writes to a database or calls an external API as part of processing, "exactly-once" to those external systems requires those systems to support idempotent writes — Kafka cannot guarantee this.

Misconception 2: "I can add consumers to a group to scale beyond the number of partitions."
Reality: Each partition is assigned to exactly one consumer per group. Adding a 7th consumer to a group with 6 partitions leaves the 7th idle. Scaling consumer throughput beyond the partition count requires increasing the partition count (an online operation in Kafka), not adding more consumers.

Misconception 3: "Kafka replaces a database."
Reality: Kafka is an event log, not a queryable database. It supports "replay from the beginning" and "latest value per key" (with compaction), but it does not support SQL queries, joins, or point lookups by arbitrary fields. Kafka Streams and ksqlDB add stream processing capabilities, but for general-purpose data storage and querying, a database is still needed.

---

## Why It Matters in Practice

Kafka is the backbone of high-throughput event streaming at many large-scale companies. In system design interviews, it comes up in virtually every problem that involves real-time data processing, event notification, or audit logging at scale. Understanding partitions (parallelism), consumer groups (load balancing), retention (replay), and offset management (reliability) is the foundation for designing Kafka-based systems correctly.

For Python engineers, the `confluent-kafka-python` library provides a complete Kafka client. The patterns shown above — keyed producers for per-key ordering, manual offset commits after processing, consumer groups for parallel consumption — are the production patterns that prevent the most common reliability bugs.

---

## Interview Angle

Common question forms:
- "How would you use Kafka to process 100,000 events per second?"
- "How do Kafka partitions and consumer groups work together?"
- "What is the difference between Kafka and RabbitMQ?"

Answer frame:
Explain partitions as the unit of ordered storage and parallelism. Explain consumer groups: one consumer per partition maximum, rebalancing on membership changes. Explain retention and replay: unlike queues, Kafka retains messages — consumers can replay. Compare to RabbitMQ: Kafka is a persistent log (pull, long retention), RabbitMQ is a transient broker (push, delete on ack). Use cases: Kafka for high-throughput streaming and audit logs; RabbitMQ for complex routing and task queues.

---

## Related Notes

- [[message-queues|Message Queues]]
- [[pub-sub-pattern|Pub/Sub Pattern]]
- [[event-driven-architecture|Event-Driven Architecture]]
- [[outbox-pattern|Outbox Pattern]]
- [[kafka-basics|Apache Kafka Basics]]
- [[kafka-producers-consumers|Kafka Producers and Consumers]]
