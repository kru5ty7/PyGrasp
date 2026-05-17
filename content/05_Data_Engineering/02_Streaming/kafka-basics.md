---
title: 01 - Apache Kafka Basics
description: "Apache Kafka is a distributed, append-only commit log that functions as a high-throughput, fault-tolerant message bus for real-time event streaming between producer and consumer applications."
tags: [kafka, streaming, message-broker, event-streaming, distributed, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Apache Kafka Basics

> Kafka is the backbone of event-driven architecture at scale — a distributed log that retains every event, allows any number of consumers to read at their own pace, and never drops a message under normal operation.

---

## Quick Reference

**Core idea:**
- Kafka is a distributed commit log — events are appended to topics and retained for a configurable period (default 7 days)
- Architecture: `Broker` (server), `Topic` (named stream), `Partition` (ordered sub-stream), `Producer` (writes events), `Consumer` (reads events)
- Kafka does NOT push messages to consumers — consumers pull from their current `offset`
- `offset` = position of a consumer in a partition; committed offsets determine where reading resumes after restart
- Events in a partition are strictly ordered; events across partitions have no ordering guarantee
- Kafka retains all events regardless of whether consumers have read them — new consumers can replay from the beginning

**Tricky points:**
- Kafka is not a job queue — it does not delete messages when consumed; multiple consumer groups read the same events independently
- Default `acks=1` in producers means the leader broker acknowledges without waiting for replicas — use `acks=all` for durability
- Increasing partition count after a topic is created changes key-to-partition mapping — existing partitioned keys may land differently
- `auto.offset.reset=earliest` vs `latest` matters when a consumer group has never committed an offset for a topic
- Kafka Streams and ksqlDB are separate streaming computation layers on top of Kafka — Kafka itself only stores and routes events

---

## What It Is

Think of a city's public announcement system — a series of bulletin boards, each designated for a specific topic: "weather updates," "traffic alerts," "city events." Newspapers post their announcements on the relevant boards. Anyone in the city can walk up to any board, start reading from any point in the history of announcements, and read at whatever pace they like. Reading an announcement does not remove it from the board. A new newspaper arriving in the city can read every announcement posted since the board was installed. Multiple readers at the same board can be at different positions simultaneously and never interfere with each other. Apache Kafka is that bulletin board system, built for millions of messages per second across thousands of topics.

Kafka was created at LinkedIn in 2010 to solve a specific problem: connecting dozens of systems (user activity tracking, operational metrics, log aggregation, database change events) through a single, high-throughput, durable pipeline instead of building direct connections between every pair of systems. The insight was that a centralized, append-only, replicated log could serve as the universal data bus. Every event posted by any producer would be retained and available to every consumer, at whatever read speed each consumer could sustain, with no coupling between producers and consumers.

This design makes Kafka different from traditional message queues (like RabbitMQ or SQS) in a fundamental way. A queue delivers a message once to one consumer and then deletes it. Kafka retains every message for a configured time window (or forever, with log compaction) and allows multiple independent consumers to read the same messages at their own pace. A new consumer group starting today can read every event from the last seven days — or from the very beginning if the retention policy allows. This replay capability is what makes Kafka suitable for use cases like event sourcing, audit logs, and stream processing alongside the real-time feed.

---

## How It Actually Works

A Kafka cluster consists of one or more broker processes (servers). Topics are distributed across brokers by partitioning. Each topic is divided into N partitions; each partition is an ordered, immutable sequence of records. A partition is replicated across R brokers (the `replication.factor`), with one broker designated as the "leader" for each partition and the others as "followers." All reads and writes for a partition go through the leader; followers replicate asynchronously. If the leader broker fails, ZooKeeper (or KRaft in Kafka 3.3+) elects a new leader from the in-sync followers.

Producers write events to a topic. By default, a producer distributes events across partitions using a hash of the event key: `partition = hash(key) % num_partitions`. Events with the same key always go to the same partition, which guarantees ordering for that key. Events with no key are distributed round-robin across partitions. The producer's `acks` setting controls durability:
- `acks=0`: fire and forget — no acknowledgment; possible data loss on broker crash
- `acks=1`: leader acknowledges after writing — data in leader memory; possible loss if leader fails before replication
- `acks=all` (or `acks=-1`): all in-sync replicas acknowledge — no data loss unless all replicas fail simultaneously

```
Topic: "user-events"
Partition 0: [event@0, event@1, event@2, event@3]   ← offset sequence
Partition 1: [event@0, event@1]
Partition 2: [event@0, event@1, event@2, event@3, event@4]

Consumer Group "analytics":
  Consumer A reads Partition 0 at offset 3
  Consumer B reads Partition 1 at offset 0
  Consumer C reads Partition 2 at offset 4

Consumer Group "backup":
  Consumer X reads ALL partitions (one consumer for the whole topic)
  Current offsets: P0@2, P1@0, P2@3  ← independent from "analytics" group
```

Consumers in the same consumer group divide the partitions among themselves — each partition is consumed by at most one consumer in a group. A consumer group with fewer members than partitions means some members read multiple partitions; a group with more members than partitions means some members are idle. This is why partition count sets the maximum consumer parallelism for a topic. Offsets are committed by consumers back to Kafka (in the `__consumer_offsets` internal topic) or to an external store. On restart, a consumer fetches its last committed offset and resumes from that position.

---

## How It Connects

The producer and consumer API — how Python code interacts with Kafka brokers, the `bootstrap_servers` configuration, serializers, and the `confluent_kafka` / `kafka-python` client libraries — is the practical level at which Python developers use Kafka.

[[kafka-producers-consumers|Kafka Producers and Consumers]]

Topics and partitions determine the ordering, parallelism, and retention model of a Kafka deployment — understanding their design trade-offs is essential for architecting a Kafka-based data pipeline.

[[kafka-topics-partitions|Kafka Topics and Partitions]]

Consumer groups provide the parallelism model for consuming Kafka topics — how partitions are assigned to consumers and what happens during rebalancing.

[[kafka-consumer-groups|Kafka Consumer Groups]]

---

## Common Misconceptions

Misconception 1: "Kafka is a message queue — when a consumer reads a message, it's deleted."
Reality: Kafka is a distributed log with retention. Messages are retained for a configured period (default 7 days) regardless of consumption. Multiple consumer groups read the same messages independently, each maintaining their own offset. Only when log compaction is enabled does Kafka discard older records for the same key.

Misconception 2: "Kafka guarantees global ordering of messages across all partitions in a topic."
Reality: Kafka guarantees ordering only within a single partition. Across partitions, there is no ordering guarantee. If global ordering is required, use a single-partition topic — at the cost of limiting consumer parallelism to one consumer per group.

Misconception 3: "Adding more consumers to a consumer group always increases throughput."
Reality: Consumer parallelism is bounded by the number of partitions. A consumer group with 10 consumers reading a 4-partition topic means 6 consumers are idle. To increase maximum consumer parallelism, you must increase the number of partitions.

---

## Why It Matters in Practice

Kafka's retention and replay capabilities change the architecture of data systems in a fundamental way. With a traditional queue, data loss during a consumer outage means those messages are gone — the system must have been designed around this. With Kafka, a consumer outage means the consumer falls behind in its offset; when it recovers, it catches up by reading from its last committed offset. Data is not lost because Kafka never deleted it. This makes Kafka the durable backbone for event-driven architectures where reliability and replayability are non-negotiable.

Understanding that Kafka is a pull-based system (consumers poll, not push) and that it is not a job queue (messages are not deleted on consumption) is the foundation for architecting systems correctly around it. Treating Kafka like SQS or RabbitMQ — expecting automatic redelivery to idle consumers, expecting messages to disappear after one read — produces systems that are either correct but inefficient or efficient but silently wrong.

---

## Interview Angle

Common question forms:
- "How does Kafka differ from a traditional message queue like RabbitMQ?"
- "What is a Kafka offset and how does it affect consumer behavior?"
- "What determines the maximum parallelism for consuming a Kafka topic?"

Answer frame:
Kafka vs queue: Kafka retains messages for a time window regardless of consumption; queues delete messages after delivery. Multiple consumer groups read Kafka independently (fan-out); queues deliver each message to one consumer. Kafka is pull-based; queues can be push-based. Offset: the position of a consumer in a partition — committed to Kafka after successful processing; allows resume from the last committed position on restart. Maximum parallelism: bounded by partition count — one consumer per partition per group maximum; idle consumers beyond partition count cannot receive messages.

---

## Related Notes

- [[kafka-producers-consumers|Kafka Producers and Consumers]]
- [[kafka-topics-partitions|Kafka Topics and Partitions]]
- [[kafka-consumer-groups|Kafka Consumer Groups]]
- [[kafka-python|Kafka with Python]]
