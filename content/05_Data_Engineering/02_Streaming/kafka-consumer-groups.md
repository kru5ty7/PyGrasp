---
title: 05 - Kafka Consumer Groups
description: "Kafka consumer groups are the mechanism for parallel, fault-tolerant consumption — partitions are assigned to group members, and a rebalance redistributes them automatically when membership changes."
tags: [kafka, consumer-groups, rebalance, partition-assignment, offset, fault-tolerance, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Kafka Consumer Groups

> Consumer groups turn Kafka's append-only log into a scalable, fault-tolerant processing layer — the number of partitions sets the ceiling, and rebalancing handles membership changes automatically but with a processing pause cost.

---

## Quick Reference

**Core idea:**
- A consumer group is a named set of consumer instances that collectively consume a topic
- Each partition is assigned to exactly one consumer in the group — no two consumers in the same group read the same partition
- A consumer can be assigned multiple partitions; a consumer with no partitions is idle
- `group.id` is the group identifier — all consumers with the same `group.id` share partition assignments
- Group coordinator: a Kafka broker that manages group membership, offset commits, and rebalances
- `GroupMetadataManager` tracks offsets in the internal `__consumer_offsets` topic

**Tricky points:**
- Rebalance pauses ALL consumers in the group while partitions are reassigned — a "stop the world" event for that group
- Cooperative incremental rebalance (Kafka 2.4+): only partitions that are moving between consumers are paused — set `partition.assignment.strategy=cooperative-sticky`
- `session.timeout.ms`: if a consumer doesn't send heartbeats within this window, it's declared dead and triggers a rebalance
- `heartbeat.interval.ms` should be ~1/3 of `session.timeout.ms` — default is 3000ms heartbeat / 10000ms session
- Static membership (`group.instance.id`): a consumer with a fixed instance ID keeps its partitions during restarts without triggering a rebalance — reduces rebalance frequency for predictable deployments

---

## What It Is

Think of a package delivery company that has a city divided into delivery zones. Each delivery driver is responsible for one or more zones. If a driver calls in sick, a dispatcher reassigns their zones to other drivers — the deliveries still get done, just by different people. If the company hires three new drivers, the dispatcher redistributes zones so everyone has a manageable workload. If business booms and they need faster delivery, they can hire more drivers — but only up to the number of zones. More drivers than zones, and some stand around with nothing to deliver. Kafka consumer groups work exactly this way: the city is the topic, zones are partitions, drivers are consumers, and the dispatcher is the Kafka group coordinator.

A consumer group allows multiple processes to cooperatively consume a Kafka topic in parallel. Each consumer in the group is assigned a non-overlapping subset of the topic's partitions. All consumers read simultaneously and independently — one processes partition 0, another processes partition 1, another handles partitions 2 and 3. The group as a whole makes progress through the entire topic at the combined rate of all its members. If one consumer crashes, its partitions are distributed among the surviving members — processing slows but does not stop.

This group model supports two distinct use cases that often coexist. Within a group, partitions are distributed for parallel processing — each message is processed by exactly one consumer in the group. Across groups, every group gets every message independently — multiple consumer groups on the same topic each receive the full stream. A "real-time analytics" consumer group and a "backup to S3" consumer group both read every event, each maintaining their own independent offsets and processing logic.

---

## How It Actually Works

When a consumer with a given `group.id` connects to Kafka, it sends a `FindCoordinator` request to locate the broker assigned as group coordinator for that `group.id`. The group coordinator is a specific broker whose identity is determined by `hash(group.id) % num_partitions(__consumer_offsets)`. Once found, the consumer sends a `JoinGroup` request. The first consumer to join becomes the group leader. The group leader runs the partition assignment algorithm (using the configured `partition.assignment.strategy`) and sends the resulting assignment back to the coordinator via a `SyncGroup` request. The coordinator distributes the assignments to all group members in their `SyncGroup` responses.

```python
from confluent_kafka import Consumer
import json

config = {
    "bootstrap.servers": "localhost:9092",
    "group.id": "order-processor",
    "auto.offset.reset": "earliest",
    "enable.auto.commit": False,
    # Modern assignment strategy: only affected partitions pause during rebalance
    "partition.assignment.strategy": "cooperative-sticky",
    # Heartbeat and session config
    "session.timeout.ms": 30000,
    "heartbeat.interval.ms": 10000,
    # Static membership: keep partitions across restarts without rebalance
    # "group.instance.id": f"worker-{socket.gethostname()}",
}

def on_assign(consumer, partitions):
    print(f"Partitions assigned: {[p.partition for p in partitions]}")

def on_revoke(consumer, partitions):
    # Commit offsets for partitions being taken away before they're reassigned
    consumer.commit(asynchronous=False)
    print(f"Partitions revoked: {[p.partition for p in partitions]}")

consumer = Consumer(config)
consumer.subscribe(["order-events"], on_assign=on_assign, on_revoke=on_revoke)

try:
    while True:
        msg = consumer.poll(timeout=1.0)
        if msg is None:
            continue
        if msg.error():
            print(f"Error: {msg.error()}")
            continue

        order = json.loads(msg.value())
        process_order(order)

        # Manual commit after successful processing
        consumer.commit(asynchronous=False)

finally:
    consumer.close()
```

Assignment strategies determine how partitions are distributed among group members. Three built-in strategies exist: `range` (consecutive partitions to each consumer — may create uneven distribution), `roundrobin` (distribute one partition at a time in round-robin order), and `sticky` / `cooperative-sticky` (minimize partition movement during rebalances by preferring to keep a consumer's current assignment when membership changes). The `cooperative-sticky` strategy (Kafka 2.4+) is the modern recommendation because it supports incremental cooperative rebalancing: only the partitions that must move are temporarily unassigned; consumers can continue processing their retained partitions during a rebalance. The older eager strategies require all consumers to stop and release all partitions before any new assignments are made.

Offset commits for consumer groups are stored in the `__consumer_offsets` internal topic, keyed by `(group_id, topic, partition)`. Each committed offset record specifies the next offset to be consumed — if offset 100 was the last processed, commit offset 101 so the next session starts at 101. The group coordinator compacts `__consumer_offsets` like any compacted topic, so it retains only the latest committed offset per group/topic/partition triple.

---

## How It Connects

Understanding how producers publish events and what offset semantics mean for consumers is the prerequisite for understanding how consumer groups track independent progress through the same topic.

[[kafka-producers-consumers|Kafka Producers and Consumers]]

Partition count directly limits consumer group parallelism — a foundational relationship between topic design and consumer group scaling.

[[kafka-topics-partitions|Kafka Topics and Partitions]]

---

## Common Misconceptions

Misconception 1: "Adding more consumers to a group always increases throughput linearly."
Reality: Throughput scales linearly up to the number of partitions. A group with 10 consumers on a 4-partition topic has 6 idle consumers. Beyond one consumer per partition, additional consumers provide only failover capacity, not additional throughput.

Misconception 2: "A rebalance only briefly pauses one consumer — the rest keep running."
Reality: With eager rebalancing (the default in Kafka < 2.4 and the default `range`/`roundrobin` strategies), a rebalance stops ALL consumers in the group — they all release their partitions and wait for the new assignment. Processing for the entire topic halts during the rebalance. Use `cooperative-sticky` to enable incremental rebalancing where only partitions that are actually moving are briefly unassigned.

Misconception 3: "Two separate Python processes with different `group.id` values compete for messages — only one will get each message."
Reality: Different consumer groups are completely independent. Each group receives every message in the topic independently. "Competition for messages" describes queuing systems (RabbitMQ, SQS); in Kafka, multiple groups on the same topic each see the full event stream.

---

## Why It Matters in Practice

Rebalance frequency and duration are the most common Kafka operational concern for Python teams. Any consumer that takes too long between `poll()` calls — because it is doing slow database writes, slow HTTP requests, or CPU-intensive processing — exceeds `max.poll.interval.ms` and triggers a rebalance. The rebalance pauses all consumers, redistributes partitions, and the slow consumer rejoins to start processing again — potentially triggering another rebalance if it slows down again. This creates a rebalance storm that makes the consumer group essentially non-functional.

The correct fix is to separate consumption from processing: consume messages quickly into an in-memory queue, commit offsets optimistically, and process from the queue asynchronously. Or use the `cooperative-sticky` strategy to make individual rebalances less disruptive while fixing the slow-processing root cause.

---

## Interview Angle

Common question forms:
- "How does Kafka consumer group partition assignment work?"
- "What is a rebalance and what causes it?"
- "How do you scale Kafka consumers?"

Answer frame:
Partition assignment: the group coordinator picks a group leader; the leader runs the assignment algorithm (range, roundrobin, sticky) distributing partitions across all active members; assignments are sent back via SyncGroup. Rebalance causes: consumer joins, consumer leaves or crashes (session timeout), partition count change, subscription change. Rebalance effect: all consumers stop, release partitions, receive new assignments — processing pauses. Scaling: add consumers up to partition count — beyond that, consumers are idle. To scale further, increase partition count (cannot decrease later).

---

## Related Notes

- [[kafka-basics|Apache Kafka Basics]]
- [[kafka-producers-consumers|Kafka Producers and Consumers]]
- [[kafka-topics-partitions|Kafka Topics and Partitions]]
- [[kafka-python|Kafka with Python]]
