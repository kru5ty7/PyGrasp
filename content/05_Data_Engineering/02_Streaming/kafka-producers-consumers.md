---
title: 02 - Kafka Producers and Consumers
description: "Kafka producers publish events with configurable durability guarantees, and consumers pull events at their own pace with offset management determining exactly-once or at-least-once delivery semantics."
tags: [kafka, producers, consumers, acks, offset, delivery-semantics, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Kafka Producers and Consumers

> Producers and consumers are the two ends of the Kafka log — the producer's `acks` setting determines how much data you can afford to lose, and the consumer's offset commit strategy determines how much data you can afford to reprocess.

---

## Quick Reference

**Core idea:**
- Producer: sends `ProducerRecord(topic, key, value, headers, partition, timestamp)` — key and value are bytes
- `acks` durability: `0` (none), `1` (leader only), `all` (all in-sync replicas)
- Consumer: calls `poll(timeout_ms)` in a loop — returns `ConsumerRecords`; commit offset after processing
- `enable.auto.commit=True` (default): offsets committed automatically every `auto.commit.interval.ms` (5 seconds)
- `enable.auto.commit=False`: manual commit via `consumer.commit()` or `consumer.commit_async()`
- Serializers/deserializers: strings as UTF-8 bytes is common; Avro with Schema Registry is production standard

**Tricky points:**
- `enable.auto.commit=True` can cause message loss: if the consumer crashes after auto-commit but before finishing processing, those messages are marked done but were not actually processed
- `max.poll.records` limits records per `poll()` call — tune to match your processing throughput
- `max.poll.interval.ms`: if `poll()` is not called within this window, the consumer is considered dead and a rebalance is triggered — don't do slow blocking work between polls
- Producers buffer messages in memory (`buffer.memory`) before sending — if the buffer fills up, `send()` blocks or raises, depending on `max.block.ms`
- `compression.type` (snappy, gzip, lz4, zstd) is set per producer and applies per batch — no per-message overhead

---

## What It Is

Think of a radio broadcast system. A radio station (the producer) prepares announcements and broadcasts them on specific frequencies (topics). The broadcasts go out continuously, regardless of how many people are listening. Radio receivers (consumers) tune to a frequency, listen at their own pace, and can rewind to earlier in the broadcast if the station provides a recording service. The station does not know or care who is listening — it broadcasts to the frequency. Listeners do not affect what the station broadcasts — they are fully independent. A listener who missed yesterday's broadcast can access the archived recording and catch up.

In Kafka's architecture, a producer is any application that creates events and sends them to Kafka. An online store sending every checkout event, a server sending log lines, an IoT sensor sending temperature readings, a database change capture system sending row-level change events — these are all producers. They speak Kafka's wire protocol (TCP-based), serialize their events to bytes, and send them to a specific topic. They do not need to know who will read the events or when. The Kafka broker accepts the events, appends them to the appropriate partition's log, and replicates them according to the topic's `replication.factor`.

A consumer is any application that reads events from Kafka. Consumers operate by polling: they call `consumer.poll()` in a loop, which returns a batch of events from the partitions assigned to that consumer. After processing the batch, they commit their offset — telling Kafka "I have successfully processed up to event #N in partition P." If the consumer crashes and restarts, it fetches its last committed offset and resumes from there. The gap between "events received" and "offset committed" is the window of potential reprocessing: if the consumer crashes after processing events but before committing, those events will be reprocessed on restart. This is the "at-least-once" delivery guarantee — events may be processed more than once, but they will not be skipped.

---

## How It Actually Works

The Kafka producer client maintains an internal buffer of `RecordBatch` objects — groups of events destined for the same partition. Batching is critical for throughput: sending 1000 individual messages to a broker over TCP costs far more in round trips than sending one batch of 1000 messages. The producer accumulates messages in a `RecordAccumulator` until either `batch.size` bytes are accumulated or `linger.ms` milliseconds have elapsed, then sends the batch to the broker. Tuning `linger.ms` (default 0) introduces artificial delay to allow more messages to accumulate per batch, trading latency for throughput.

```python
from confluent_kafka import Producer, Consumer, KafkaError
import json

# Producer
producer_config = {
    "bootstrap.servers": "localhost:9092",
    "acks": "all",                    # wait for all in-sync replicas
    "retries": 5,                     # retry on transient errors
    "compression.type": "snappy",
    "linger.ms": 5,                   # accumulate for 5ms before sending
    "batch.size": 65536,              # 64KB batch
}

def delivery_callback(err, msg):
    if err:
        print(f"Delivery failed: {err}")
    else:
        print(f"Delivered to {msg.topic()} [{msg.partition()}] @ offset {msg.offset()}")

producer = Producer(producer_config)

events = [
    {"user_id": 1001, "action": "checkout", "amount": 99.99},
    {"user_id": 1002, "action": "view", "product_id": 42},
]

for event in events:
    producer.produce(
        topic="user-events",
        key=str(event["user_id"]).encode("utf-8"),     # partition routing key
        value=json.dumps(event).encode("utf-8"),
        callback=delivery_callback,
    )

producer.flush()   # block until all messages are delivered (or max.block.ms exceeded)

# Consumer — manual offset commit for exactly-once-style at-least-once
consumer_config = {
    "bootstrap.servers": "localhost:9092",
    "group.id": "analytics-consumer",
    "auto.offset.reset": "earliest",
    "enable.auto.commit": False,        # manual commit for control
}

consumer = Consumer(consumer_config)
consumer.subscribe(["user-events"])

try:
    while True:
        msg = consumer.poll(timeout=1.0)
        if msg is None:
            continue
        if msg.error():
            if msg.error().code() == KafkaError._PARTITION_EOF:
                continue
            raise Exception(f"Consumer error: {msg.error()}")

        event = json.loads(msg.value().decode("utf-8"))
        process_event(event)             # your processing logic

        consumer.commit(asynchronous=False)   # commit after processing
finally:
    consumer.close()
```

Idempotent producers (enable via `enable.idempotence=True`) use a producer ID and sequence number per partition to deduplicate retries at the broker level. Without idempotence, a network timeout can cause the producer to retry a send that actually succeeded — producing a duplicate event. With idempotence, the broker detects and discards duplicate batches from the same producer ID. Transactional producers go further: `producer.begin_transaction()`, writes to multiple topics, `producer.commit_transaction()` — all writes are atomic across topics. The consuming side must use `isolation.level=read_committed` to see only committed transactional writes.

---

## How It Connects

Consumer groups — how partitions are distributed among consumers in the same group, and what happens during a rebalance — are the practical scaling model for Kafka consumers.

[[kafka-consumer-groups|Kafka Consumer Groups]]

The Python Kafka client library options (`confluent-kafka` vs `kafka-python`), their configuration, and specific Python patterns for producers and consumers in real applications.

[[kafka-python|Kafka with Python]]

---

## Common Misconceptions

Misconception 1: "With `enable.auto.commit=True`, I never need to think about offset management."
Reality: Auto-commit commits the offset of the last polled message on a timer, regardless of whether processing succeeded. If your consumer processes 100 messages, auto-commits, then crashes processing message 101, you lose messages 101+ because they were committed. Auto-commit is safe only when your processing is idempotent and you can tolerate reprocessing at-least-once with potential gaps.

Misconception 2: "Calling `producer.flush()` after every message ensures maximum durability."
Reality: `flush()` blocks until all pending messages are delivered — it is correct for ensuring delivery but destroys throughput by forcing synchronous one-message-at-a-time sends. Use `flush()` at shutdown or batch boundaries. The delivery callback mechanism provides async delivery confirmation without blocking.

Misconception 3: "Consumers automatically get messages pushed to them — I don't need to call `poll()` actively."
Reality: Kafka is a pull-based system. Consumers call `poll()` to fetch batches of messages. The Kafka broker tracks consumer group membership based on heartbeat messages sent during `poll()` calls. If `poll()` is not called within `max.poll.interval.ms`, the broker assumes the consumer is dead and triggers a partition rebalance.

---

## Why It Matters in Practice

The delivery guarantee model — at-most-once, at-least-once, or effectively-exactly-once — is determined entirely by how producers configure `acks` and how consumers manage offset commits. Getting this wrong produces systems that silently drop events (at-most-once with crashes) or silently produce duplicate records in the downstream database (at-least-once without idempotent writes). For financial transactions, audit logs, and inventory systems, these are correctness-breaking failures.

The `max.poll.interval.ms` limit is the most common source of unexpected rebalances in production. If a consumer's processing logic takes longer than this limit (default 5 minutes), Kafka removes it from the group, triggers a rebalance (which causes all consumers in the group to pause and reassign partitions), and the slow consumer later rejoins and starts a new rebalance. The fix is always the same: reduce processing time per batch, increase `max.poll.interval.ms` if the processing time is genuinely irreducible, or process asynchronously.

---

## Interview Angle

Common question forms:
- "What is the difference between at-most-once, at-least-once, and exactly-once delivery in Kafka?"
- "What is the risk of `enable.auto.commit=True` in a Kafka consumer?"
- "How does a Kafka producer control durability?"

Answer frame:
At-most-once: commit offset before processing — possible message loss on crash. At-least-once: commit offset after successful processing — possible reprocessing on crash. Exactly-once: requires idempotent or transactional producers + `isolation.level=read_committed` on consumers — achievable in Kafka 0.11+. Auto-commit risk: commits on a timer regardless of processing state — after crash, messages that were polled, committed, but not fully processed are lost. Producer durability: `acks=0` no guarantee, `acks=1` leader persists, `acks=all` all replicas persist — choose based on acceptable data loss tolerance.

---

## Related Notes

- [[kafka-basics|Apache Kafka Basics]]
- [[kafka-topics-partitions|Kafka Topics and Partitions]]
- [[kafka-consumer-groups|Kafka Consumer Groups]]
- [[kafka-python|Kafka with Python]]
