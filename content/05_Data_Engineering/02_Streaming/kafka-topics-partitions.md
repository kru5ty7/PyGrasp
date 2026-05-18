---
title: 03 - Kafka Topics and Partitions
description: "Kafka topics are named streams divided into ordered partitions  -  the number of partitions determines parallelism, the replication factor determines fault tolerance, and key-based partitioning determines ordering guarantees."
tags: [kafka, topics, partitions, replication, log-compaction, retention, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Kafka Topics and Partitions

> Topics and partitions are the fundamental unit of Kafka's capacity planning  -  partition count sets the ceiling on consumer parallelism, and getting it wrong is expensive to fix after a topic has live consumers.

---

## Quick Reference

**Core idea:**
- Topic = named, append-only, multi-partition stream; partition = ordered sub-stream stored as a sequence of segment files on disk
- `num.partitions` is set at topic creation; increasing it later breaks key-based ordering for existing keys
- `replication.factor` = number of broker copies; typically 3 in production; `min.insync.replicas` = minimum for writes
- Retention policies: `retention.ms` (time-based), `retention.bytes` (size-based), or `cleanup.policy=compact` (keep only latest per key)
- Partition assignment for a keyed message: `partition = murmur2(key) % num_partitions`
- Segment files: each partition is a series of `log` + `index` file pairs; active segment is the one being written to

**Tricky points:**
- Partition count cannot be safely decreased  -  only increased (and that breaks key routing)
- `replication.factor` must be less than or equal to the number of brokers; RF=1 means no redundancy
- Log compaction guarantees the latest value per key is retained indefinitely  -  it does NOT guarantee latest value is immediately visible
- `__consumer_offsets` and `__transaction_state` are internal Kafka topics  -  do not manually produce to them
- A topic with a single partition has a write throughput ceiling equal to one broker's disk write speed  -  partition count is the horizontal scaling unit for write throughput

---

## What It Is

Consider a highway system connecting a city. Instead of one road carrying all traffic, city planners build multiple parallel lanes. Each lane carries traffic in one direction (from source to destination). Traffic controllers assign vehicles to lanes: heavy trucks always use lane 3, passenger cars from downtown use lane 1, passenger cars from the airport use lane 2. Vehicles in the same lane stay in their original order  -  if car A entered lane 1 before car B, car A will exit before car B. But you cannot compare when a vehicle in lane 1 departed versus a vehicle in lane 3  -  the lanes are independent. Kafka topics are the highway, partitions are the lanes, and key-based routing assigns messages to lanes.

A Kafka topic is a logical grouping of events that belong together: "user-checkout-events," "server-error-logs," "sensor-temperature-readings." Topics are subdivided into partitions, each of which is an independent ordered sequence of events. When a producer sends an event with a key, Kafka computes `hash(key) mod num_partitions` to determine which partition the event goes to. Events with the same key always land in the same partition, which preserves their order relative to each other. Events with different keys may land in different partitions, and their relative order is undefined.

The partition count is the most important topic configuration choice because it determines the maximum parallelism for both writes (multiple producers can write to different partitions simultaneously) and reads (one consumer per partition in a consumer group). Setting a topic's partition count too low limits how fast consumers can process its events. Setting it too high creates unnecessary overhead in the broker (each partition is a directory of files, and the broker must manage metadata for every partition across all brokers). Production guidance: start with the number of partitions that matches your peak consumer parallelism need, typically 6-24 for most topics, with high-throughput topics going to 50-100 or more.

---

## How It Actually Works

On disk, each partition is stored as a series of segment files in a directory on the broker. Each segment consists of a `.log` file (the actual event data, appended sequentially), an `.index` file (mapping event offsets to byte positions within the log file for fast seeks), and a `.timeindex` file (mapping timestamps to offsets). The active segment is the one currently being written to; when it reaches `segment.bytes` in size (default 1 GB) or `segment.ms` in age (default 7 days), it is "rolled"  -  closed and a new active segment opened. The Kafka log retention process periodically deletes segment files that are older than `retention.ms` or that push the total partition size above `retention.bytes`.

```
Partition directory: /kafka-data/my-topic-0/
├── 00000000000000000000.log          # events 0 - 999
├── 00000000000000000000.index
├── 00000000000000000000.timeindex
├── 00000000000000001000.log          # events 1000 - 1999
├── 00000000000000001000.index
├── 00000000000000001000.timeindex
└── 00000000000000002000.log          # active segment: events 2000+
    00000000000000002000.index
```

Log compaction is a different retention mode that keeps the latest value per message key indefinitely. Instead of deleting old segments by time or size, the log compactor runs in the background and produces a new, compacted log containing only the most recent event for each unique key. Events with a `null` value (tombstone records) are eventually deleted along with their key. Log compaction is the foundation of Kafka's "event sourcing" use case: a topic with compaction enabled is equivalent to a key-value store whose change log is always available  -  consumers can subscribe to all changes, or read only the latest value for each key by consuming the entire compacted log once.

Replication works at the partition level. Each partition has one leader replica and `replication.factor - 1` follower replicas spread across different brokers. All reads and writes go through the leader. Followers pull new events from the leader and replicate asynchronously. The set of followers that are "caught up" (within `replica.lag.time.max.ms` of the leader) is called the ISR  -  In-Sync Replicas. When `acks=all` is set on the producer, the leader waits for all ISR members to acknowledge the write. `min.insync.replicas` (typically set to 2 for a RF=3 topic) ensures that writes fail rather than proceed with insufficient replication  -  preventing data loss during cascading broker failures.

---

## How It Connects

The producer's key hashing strategy and the consumer group partition assignment are both direct consequences of topic partition structure  -  these topics form a coherent picture of how events flow through Kafka.

[[kafka-producers-consumers|Kafka Producers and Consumers]]

Consumer groups map one-to-one with partitions: understanding partition count and assignment is prerequisite to understanding how consumer group rebalancing works.

[[kafka-consumer-groups|Kafka Consumer Groups]]

---

## Common Misconceptions

Misconception 1: "I can safely decrease the partition count of a topic if I realize I created too many."
Reality: Kafka does not support decreasing partition count. To reduce partitions, you must create a new topic with the desired count, migrate data to it, and update all producers and consumers to use the new topic  -  a complex operational procedure. Partition count is a permanent decision; plan carefully.

Misconception 2: "Log compaction means old events are eventually deleted  -  it's just time-based retention with different cleanup."
Reality: Log compaction keeps the latest event per key permanently. Events are never deleted unless the latest event for that key is a tombstone (null value). An event from three years ago is still present in a compacted log if it is the most recent event for its key and no tombstone has been sent. Time-based and size-based retention delete by age/size regardless of key.

Misconception 3: "Setting `replication.factor=3` means I have 3 independent copies  -  losing 2 brokers is safe."
Reality: With RF=3 and `min.insync.replicas=2`, you can tolerate losing 1 broker (the minority). Losing 2 brokers leaves you with 1 replica  -  below `min.insync.replicas`, writes will fail. RF=3 with `min.insync.replicas=1` tolerates 2 broker losses for writes but risks data loss (the surviving replica might be behind). The standard production configuration is RF=3, `min.insync.replicas=2`.

---

## Why It Matters in Practice

Partition count decisions made at topic creation have permanent consequences. A low-partition topic that becomes high-throughput requires partition increase, which breaks key ordering  -  a disruptive change requiring producer and consumer coordination. A high-partition topic with few actual consumers wastes broker resources and slows leader election. Getting partition counts right requires thinking about peak consumer parallelism, write throughput, and message key cardinality before the topic goes into production.

Understanding the segment file structure also matters for operational work: disk usage grows predictably with `retention.ms` and write rate; disk monitoring should alert before segments start filling the disk; compacted topics require explicit tombstone management to actually free disk space for deleted keys.

---

## Interview Angle

Common question forms:
- "How does Kafka achieve ordering guarantees?"
- "What is log compaction and when would you use it?"
- "What factors influence how many partitions a topic should have?"

Answer frame:
Ordering: guaranteed within a partition (events are appended in order); no ordering guarantee across partitions. Key-based routing (`hash(key) % num_partitions`) ensures same-key events land in the same partition. Log compaction: instead of deleting by age, retains only the latest event per key indefinitely; use for event sourcing, materialized views of current state, or any use case where latest state matters but history is optional. Partition count factors: maximum consumer parallelism needed (one consumer per partition per group max), write throughput ceiling (partition = unit of write parallelism), broker resource overhead.

---

## Related Notes

- [[kafka-basics|Apache Kafka Basics]]
- [[kafka-producers-consumers|Kafka Producers and Consumers]]
- [[kafka-consumer-groups|Kafka Consumer Groups]]
