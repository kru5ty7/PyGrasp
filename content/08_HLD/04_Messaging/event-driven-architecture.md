---
title: 05 - Event-Driven Architecture
description: "Events vs commands vs queries, how loose coupling through events enables independently deployable services, and the eventual consistency tradeoffs that come with it."
tags: [event-driven, architecture, microservices, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Event-Driven Architecture

> Event-driven architecture is the most powerful form of decoupling available to system designers  -  and understanding the difference between an event, a command, and a query is what makes it work rather than creating distributed chaos.

---

## Quick Reference

**Core idea:**
- An event is a fact that something happened  -  immutable, past tense, no instruction to others
- A command is an instruction for another service to do something  -  directed, imperative
- EDA communicates through events; services react to facts rather than receiving commands
- Loose coupling: a producer does not know about consumers; new consumers can be added without changing the producer
- Eventual consistency: because processing is asynchronous, different services will be in sync "eventually"

**Tricky points:**
- "Event" is often misused  -  a message that says "please send this email" is a command, not an event
- Debugging EDA is harder than synchronous systems  -  distributed tracing and correlation IDs are essential
- Event ordering is not guaranteed across topics without careful design
- Exactly-once processing requires idempotent consumers or transactional consumers  -  at-least-once is the default
- Event-driven does not mean "no synchronous calls"  -  events are appropriate for some things, not everything

---

## What It Is

Think about how newspapers work. When a city council votes to change the speed limit, the city does not call every individual organization to notify them. It holds the vote, publishes the meeting minutes (the event), and various organizations  -  insurance companies, road engineers, driving schools, GPS providers  -  all read the minutes and independently update their own systems. The city council does not know who reads the minutes or what they do with them. Organizations can start reading minutes at any time  -  new ones do not require a change to how the city holds votes.

This is event-driven architecture. Services emit events  -  announcements of facts  -  and other services subscribe to those events and react. The speed limit change is the event. The various organizations' updates are the reactions. The city council (producer) is completely decoupled from the updating organizations (consumers).

EDA is defined by its communication model. In a synchronous, command-driven architecture, Service A calls Service B's API to instruct it to do something. Service A waits for B to complete. If B is slow, A is slow. If B is down, A fails. Service A must know about Service B. In EDA, Service A emits an event to an event bus. Services B, C, and D subscribe to that event and react independently. Service A does not wait, does not know about B, C, or D, and is not affected if any of them fail.

The vocabulary distinction matters enormously. An event is a fact: "UserRegistered", "OrderPlaced", "PaymentProcessed". It is in the past tense. It carries information about what happened. It makes no instruction. A command is an instruction: "SendWelcomeEmail", "ReserveInventory", "ProcessPayment". Commands can fail. Events cannot  -  they simply record what happened. Designing EDA with proper events (not disguised commands) enables true decoupling. If the `UserRegistered` event is published and no service consumes it, nothing breaks  -  the registration still happened. If a `SendWelcomeEmail` command is published and the email service is down, the command must be retried or acknowledged as failed.

---

## How It Actually Works

An event-driven system needs three components: an event source (the service that emits events), an event bus (the messaging infrastructure that routes events  -  Kafka, RabbitMQ, SNS), and event handlers (the services that subscribe and react). The event bus provides the temporal decoupling: producers and consumers do not need to be running simultaneously.

Events carry a standard envelope: an event ID (for idempotency), a timestamp (when it occurred), an event type, the aggregate ID (which entity it pertains to), and the event payload (the data describing what changed). A well-designed event is self-contained  -  the consumer does not need to make additional calls to understand it.

Choreography and orchestration are two approaches to implementing multi-step workflows in EDA. In choreography, each service reacts to events and emits its own events, and the workflow emerges from the chain of reactions. In orchestration, a central service (the orchestrator) issues commands to other services and tracks the workflow state. Choreography is more loosely coupled but harder to monitor. Orchestration is easier to reason about but introduces a central dependency. The Saga pattern uses both approaches for distributed transactions.

```python
# Event sourcing with EDA: services emit immutable domain events
from dataclasses import dataclass, field
from datetime import datetime
import uuid
import json

@dataclass
class DomainEvent:
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    event_type: str = ""
    aggregate_id: str = ""
    occurred_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    payload: dict = field(default_factory=dict)

    def to_json(self) -> str:
        return json.dumps({
            "event_id": self.event_id,
            "event_type": self.event_type,
            "aggregate_id": self.aggregate_id,
            "occurred_at": self.occurred_at,
            "payload": self.payload
        })

# Order service: emits domain events
class OrderService:
    def place_order(self, order_data: dict) -> dict:
        order_id = str(uuid.uuid4())
        order = {"id": order_id, "status": "placed", **order_data}

        # Save to database first
        db.save_order(order)

        # Then emit event (in practice: use outbox pattern for atomicity)
        event = DomainEvent(
            event_type="OrderPlaced",
            aggregate_id=order_id,
            payload={
                "order_id": order_id,
                "user_id": order_data["user_id"],
                "total": order_data["total"],
                "items": order_data["items"]
            }
        )
        kafka.publish("orders", key=order_id, value=event.to_json())
        return order

# Inventory service: reacts to OrderPlaced event
def handle_order_placed(event: dict):
    """Independent service  -  knows about the event schema, not OrderService."""
    order_id = event["aggregate_id"]
    items = event["payload"]["items"]
    for item in items:
        inventory.reserve(item["product_id"], item["quantity"], order_id)
    # Emit its own event in response
    event = DomainEvent(
        event_type="InventoryReserved",
        aggregate_id=order_id,
        payload={"order_id": order_id, "reserved_items": items}
    )
    kafka.publish("inventory", key=order_id, value=event.to_json())

# Email service: also reacts to OrderPlaced  -  independent of inventory
def handle_order_placed_for_email(event: dict):
    user_id = event["payload"]["user_id"]
    send_order_confirmation_email(user_id, event["payload"])
```

Distributed tracing becomes essential in EDA. When a request flows through five services via events, understanding the end-to-end latency and locating a failure requires correlating logs across all services. The standard practice is to generate a `correlation_id` (or use the event's `event_id`) that is propagated through every event in a chain, and include it in every log entry. Tools like Jaeger, Zipkin, or AWS X-Ray aggregate these traces into a visual timeline.

---

## How It Connects

Kafka is the most common event bus for high-throughput EDA. Understanding Kafka's partition model and consumer groups explains how EDA scales.

[[kafka-system-design|Kafka in System Design]]

The outbox pattern ensures that a service's database write and its event publication are atomic  -  preventing the dual-write problem that would cause events to be lost or published without the corresponding data being saved.

[[outbox-pattern|Outbox Pattern]]

Event sourcing takes EDA to its logical conclusion: the event log is the source of truth, and current state is derived by replaying events. CQRS is closely related.

[[event-sourcing|Event Sourcing]]

---

## Common Misconceptions

Misconception 1: "Event-driven architecture is eventually consistent, so it is acceptable for financial transactions."
Reality: EDA's eventual consistency means different services will see the same state "eventually." For financial transactions where funds must be reserved before confirmation is given, this is not acceptable without explicit consistency mechanisms. The Saga pattern handles distributed transactions in EDA by using compensating transactions  -  if a step fails, previous steps are reversed. This is complex and must be designed carefully.

Misconception 2: "EDA is always more scalable than synchronous architectures."
Reality: EDA adds messaging infrastructure overhead (the broker), event serialization costs, and complex failure handling. For simple request-response interactions where both services are always available and latency matters, synchronous HTTP calls are simpler and often faster. EDA is better when decoupling, scalability, or resilience to downstream failures is more important than simplicity or latency.

Misconception 3: "Once an event is published, I can change its schema freely."
Reality: Event schemas are contracts. Consumers depend on the shape of events they subscribe to. Changing a field name, removing a field, or changing a field's type breaks consumers. Schema evolution requires backward-compatible changes (add optional fields, never remove required fields) or explicit versioning with a schema registry. This is the hidden coupling in EDA  -  services are decoupled at the code level but coupled at the schema level.

---

## Why It Matters in Practice

EDA enables independent deployment of services. If the email service is deployed with a bug and goes down, it does not prevent orders from being placed  -  the `OrderPlaced` events accumulate in the queue and the email service processes them when it comes back up. This "backpressure buffer" property is one of the most practical benefits of EDA in production.

For Python developers, EDA means designing services to be event producers and consumers, not just HTTP servers. Every important domain action  -  user registration, order placement, payment completion  -  should emit an event. Event consumers implement specific business reactions. The coupling that accumulates in synchronous "call all the things" architectures never forms.

---

## Interview Angle

Common question forms:
- "What is event-driven architecture and how does it differ from REST-based communication?"
- "When would you choose EDA over synchronous calls between services?"
- "What are the challenges of EDA in production?"

Answer frame:
Define EDA: services communicate via events (facts) published to an event bus, not via direct calls. Contrast with synchronous: caller waits, direct dependency. EDA benefits: temporal decoupling, resilience to downstream failures, easy addition of new consumers. EDA challenges: eventual consistency, harder debugging (need distributed tracing), schema coupling. When to use: background processing, multi-service reactions to business events, audit logs. When not to use: simple two-service request-response where consistency and low latency are paramount.

---

## Related Notes

- [[kafka-system-design|Kafka in System Design]]
- [[message-queues|Message Queues]]
- [[pub-sub-pattern|Pub/Sub Pattern]]
- [[outbox-pattern|Outbox Pattern]]
- [[event-sourcing|Event Sourcing]]
- [[microservices-basics|Microservices Basics]]
