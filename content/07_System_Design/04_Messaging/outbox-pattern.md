---
title: 06 - Outbox Pattern
description: "The transactional outbox pattern solves the dual-write problem — ensuring a database write and a message publish are atomic even without a distributed transaction."
tags: [outbox-pattern, cdc, dual-write, transactions, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Outbox Pattern

> The outbox pattern solves one of the hardest problems in distributed systems: how do you atomically write to a database and publish a message to a broker, when there is no distributed transaction spanning both?

---

## Quick Reference

**Core idea:**
- The dual-write problem: writing to a DB and publishing to a queue are two separate operations — either can fail
- The outbox pattern: write the event to an `outbox` table in the same transaction as the business data
- A separate process (polling relay or CDC) reads the outbox and publishes events to the message broker
- The event is only published after the database transaction commits — guaranteed atomicity
- CDC tools (Debezium) read the DB's replication log and emit events, eliminating polling overhead

**Tricky points:**
- The relay publishes each event at least once — consumers must still be idempotent
- Event ordering within a transaction is preserved; ordering across transactions depends on the relay implementation
- A long-running relay failure causes the outbox table to grow — needs monitoring
- The `published` flag approach (mark as done after publishing) has a window of potential re-publication on crash
- Debezium reads the WAL directly — this is more reliable than application-level polling but adds operational complexity

---

## What It Is

Imagine a bank teller who needs to record a transaction in the ledger and send a notification letter to the customer. These are two separate actions. If the teller records the ledger entry and then the telephone line breaks before sending the letter, the ledger has the record but the customer never gets notified. If the teller sends the letter first and then drops the ledger book, the customer is notified but there is no record of the transaction. Neither partial success is acceptable.

The teller's solution: write both the ledger entry and a reminder note in the same notebook during the customer interaction (the transaction). Later, a clerk checks the notebook for unsent reminder notes, sends the letters, and marks them as sent. The reminder note in the notebook is the outbox. The clerk is the relay process. The transaction ensures the ledger entry and the reminder note are always written together or not at all.

This is the transactional outbox pattern, applied to distributed systems. When a service needs to both update a database and publish a message to a broker (Kafka, RabbitMQ, SNS), doing them as two separate operations creates the dual-write problem: either can fail independently, leaving the system in an inconsistent state. The service that creates an order and publishes an `OrderPlaced` event faces this exact problem. If the database commit succeeds but the Kafka publish fails, the order exists but no downstream service knows about it. If the Kafka publish succeeds but the database commit fails, services react to an order that was never saved.

The outbox pattern solves this by introducing an `outbox` table in the same database as the business data. In the same database transaction that creates the order, the service also inserts a row into the outbox table describing the event to be published. Since both the order and the outbox entry are written in the same ACID transaction, they either both exist or neither does. A separate relay process reads unprocessed outbox entries and publishes them to the message broker. After successful publication, the relay deletes or marks the outbox entry.

---

## How It Actually Works

The polling relay approach implements the relay as a background job that periodically queries the outbox table for unpublished events. For each unpublished event, it publishes to the message broker and marks the event as published. The query is simple: `SELECT * FROM outbox WHERE published = FALSE ORDER BY created_at LIMIT 100`. The relay runs continuously with a short sleep between iterations.

The publication step is idempotent from the broker's perspective: the relay may publish the same event twice if it crashes after publishing but before marking it as published. This is the at-least-once delivery guarantee that consumers must handle. Setting a unique event ID as the Kafka message key (or using Kafka's idempotent producer) ensures that duplicate publishes by the relay are deduplicated at the broker level.

CDC (Change Data Capture) is a more efficient alternative to polling. Instead of the relay querying the database for new outbox rows, a CDC tool reads the database's replication log directly. Debezium is the most widely used CDC tool for this purpose. It connects to PostgreSQL's logical replication slot or MySQL's binary log, reads each committed insert/update/delete, and emits a corresponding event to Kafka. When Debezium reads an insert to the outbox table, it emits the event to Kafka automatically, without any polling query. This reduces database load and provides lower latency than polling.

```python
# Application service: write to DB + outbox in one transaction
from sqlalchemy.orm import Session
from datetime import datetime
import uuid, json

def place_order(session: Session, user_id: int, items: list) -> dict:
    """Place an order and enqueue the OrderPlaced event atomically."""
    order_id = str(uuid.uuid4())
    total = sum(item["price"] * item["qty"] for item in items)

    with session.begin():  # ACID transaction
        # Write business data
        order = Order(id=order_id, user_id=user_id, total=total, status="placed")
        session.add(order)

        # Write outbox entry in the same transaction
        outbox_entry = OutboxEvent(
            id=str(uuid.uuid4()),
            event_type="OrderPlaced",
            aggregate_id=order_id,
            payload=json.dumps({
                "order_id": order_id,
                "user_id": user_id,
                "total": total,
                "items": items
            }),
            created_at=datetime.utcnow(),
            published=False
        )
        session.add(outbox_entry)
    # Transaction commits here — both order and outbox entry are durable

    return {"order_id": order_id, "total": total}

# Polling relay: runs as a background process or scheduled job
import time
from confluent_kafka import Producer

producer = Producer({'bootstrap.servers': 'kafka:9092'})

def relay_outbox_events(session: Session):
    """Read unpublished outbox events and publish to Kafka."""
    while True:
        with session.begin():
            events = session.query(OutboxEvent).filter_by(published=False).limit(100).all()
            for event in events:
                producer.produce(
                    topic=event.event_type.lower().replace('.', '-'),
                    key=event.aggregate_id,
                    value=event.payload
                )
            producer.flush()  # ensure all messages are delivered

            # Mark as published only after successful delivery
            for event in events:
                event.published = True

        time.sleep(0.5)  # poll every 500ms; CDC-based approaches eliminate this delay
```

The Debezium approach requires configuring a PostgreSQL logical replication slot and a Debezium connector in Kafka Connect. Debezium transforms the outbox entry into a Kafka message using the "outbox event router" single message transform, which uses the event's type to route to the appropriate Kafka topic and the event's payload as the message body. This approach eliminates the polling loop and provides sub-second event publishing after the database commit.

Outbox table cleanup is an operational concern. Published entries accumulate unless they are periodically deleted. A background job that deletes entries older than a certain age (e.g., `DELETE FROM outbox WHERE published = TRUE AND created_at < NOW() - INTERVAL '7 days'`) keeps the table small. Alternatively, entries can be deleted immediately after successful relay publication, but this requires careful handling of relay crashes.

---

## How It Connects

The dual-write problem the outbox solves is a specific instance of the broader challenge in event-driven architecture: ensuring that business state changes and the events that represent them are always consistent.

[[event-driven-architecture|Event-Driven Architecture]]

CDC, the technology powering Debezium-based relay, reads the same database replication log that followers read during replication. Understanding database replication explains why CDC works.

[[database-replication|Database Replication]]

The ACID transaction that makes the outbox pattern work is the same transactional guarantee that distinguishes relational databases from NoSQL stores.

[[acid-vs-base|ACID vs BASE]]

---

## Common Misconceptions

Misconception 1: "The outbox pattern provides exactly-once event delivery."
Reality: The relay may publish an event and then crash before marking it as published, causing it to be published again on restart. This is at-least-once delivery. Consumers must be idempotent: they must handle receiving the same event twice without producing incorrect results. The event ID in the payload is the key to idempotency — consumers track which event IDs they have already processed.

Misconception 2: "I can just use a two-phase commit (2PC) instead of the outbox pattern."
Reality: Two-phase commit between a database and a message broker requires both systems to support XA transactions (a distributed transaction protocol). Most modern message brokers (Kafka, RabbitMQ, SQS) do not support XA. Even when available, 2PC adds significant latency and is a reliability bottleneck (the transaction coordinator is a SPOF). The outbox pattern achieves the same guarantee using only the database's native ACID transactions.

Misconception 3: "Debezium (CDC) means my events are published in real time."
Reality: Debezium reads the database's replication log with a small lag — typically milliseconds to seconds. It is much lower latency than a polling relay (which waits for the next poll interval), but not zero-latency. Additionally, the replication lag of the CDC connector adds to end-to-end event latency. Under heavy load, the CDC connector may fall behind and take time to catch up.

---

## Why It Matters in Practice

The outbox pattern is the correct solution to a problem that every event-driven microservice encounters. Without it, teams either use fire-and-forget event publishing (losing events when the broker is unavailable) or build ad hoc retry mechanisms that have the same dual-write risk. The pattern is not complex — it is just an extra table and a relay process — but it requires deliberate design upfront.

For Python engineers using SQLAlchemy and Kafka, implementing the polling relay as a FastAPI background task or a Celery beat job is straightforward. Transitioning to Debezium requires infrastructure investment but eliminates polling overhead and provides better operability. The choice between polling relay and CDC depends on scale and operational maturity.

---

## Interview Angle

Common question forms:
- "What is the dual-write problem?"
- "How do you ensure a database write and a message publish are atomic?"
- "What is the transactional outbox pattern?"

Answer frame:
Define the dual-write problem: database write and message publish are independent operations — either can fail. State that distributed transactions with most brokers are not supported. Introduce the outbox: same-transaction insert into an `outbox` table. Describe the relay: polling or CDC reads the outbox and publishes to the broker. Emphasize that this is still at-least-once — consumers need idempotency. Mention Debezium as the production-grade CDC approach.

---

## Related Notes

- [[event-driven-architecture|Event-Driven Architecture]]
- [[kafka-system-design|Kafka in System Design]]
- [[database-replication|Database Replication]]
- [[acid-vs-base|ACID vs BASE]]
- [[saga-pattern|Saga Pattern]]
