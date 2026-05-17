---
title: 04 - Saga Pattern
description: "How to implement distributed transactions across microservices using choreography or orchestration, with compensating transactions to handle failures."
tags: [saga-pattern, distributed-transactions, microservices, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Saga Pattern

> The Saga pattern is how you implement a business transaction that spans multiple services — accepting that distributed transactions cannot be atomic across services, and designing for compensating rollback instead.

---

## Quick Reference

**Core idea:**
- A saga is a sequence of local transactions, each in one service, connected by events or commands
- Choreography: each service reacts to an event and emits another event — the workflow emerges implicitly
- Orchestration: a central saga orchestrator issues commands to services and tracks state
- Compensating transactions: when a step fails, previously-completed steps are reversed by compensating actions
- Sagas provide eventual consistency, not ACID atomicity — there is a window where the system is in an intermediate state

**Tricky points:**
- Compensating transactions can also fail — you need a way to handle failed compensations
- Choreography is loosely coupled but hard to monitor — you cannot easily see where a saga is in its flow
- Orchestration is easier to monitor but introduces a central orchestrator as a dependency
- Sagas do not prevent concurrent sagas from reading inconsistent intermediate state — this is a "dirty read"
- The order in which compensations must be applied is the reverse of the order of successful steps

---

## What It Is

Think about booking a vacation. You book a flight, then a hotel, then a rental car. Each is confirmed separately. Now imagine the hotel is fully booked — the second step fails. You must cancel the flight you already booked (compensating transaction). If the car rental confirmation also fails, you must cancel both the flight and the hotel. The sequence of bookings that must be reversed when a later step fails is the saga.

In distributed systems, a business operation often spans multiple services. Placing an order might involve: the order service creating the order, the inventory service reserving stock, the payment service charging the customer, and the shipping service scheduling delivery. Each of these is a separate service with its own database. There is no distributed transaction that makes all four atomic — that would require two-phase commit across all services, which is slow, fragile, and not supported by most message brokers.

The saga pattern breaks the business operation into a sequence of local transactions, one per service. Each local transaction is ACID within its own database. If all steps succeed, the business operation completes successfully. If any step fails, the system executes compensating transactions in reverse order — each compensating transaction reverses the effect of its corresponding successful step. The system eventually reaches a consistent state, either the fully-committed state (all steps succeeded) or the fully-compensated state (all completed steps were reversed).

Choreography and orchestration are the two coordination approaches for sagas. In choreography, each service reacts to an event by executing its local transaction and then emitting an event that triggers the next step. Service A publishes "OrderCreated"; Service B hears it, reserves inventory, and publishes "InventoryReserved"; Service C hears that, charges the customer, and publishes "PaymentProcessed." If Service C fails, it publishes "PaymentFailed"; Service B hears that and publishes "InventoryReleased"; the inventory reservation is reversed. The saga's workflow is implicit in the event reactions.

Orchestration uses a central saga orchestrator — a service that knows the full workflow. The orchestrator sends a command to Service A ("reserve inventory"), waits for success or failure, then sends a command to Service B ("charge customer"), and so on. If a command fails, the orchestrator sends compensating commands to all previously-succeeded services ("release inventory reservation"). The workflow is explicit and centrally managed.

---

## How It Actually Works

Choreography saga design starts with defining the events that trigger each step and the compensating actions for each step. For an order saga:

Step 1: Order Service creates order → emits `OrderCreated`
Compensating: Order Service marks order as `cancelled`

Step 2: Inventory Service receives `OrderCreated`, reserves stock → emits `InventoryReserved`
Compensating: Inventory Service releases reservation

Step 3: Payment Service receives `InventoryReserved`, charges card → emits `PaymentProcessed`
Compensating: Payment Service issues refund

Step 4: Shipping Service receives `PaymentProcessed`, schedules delivery → emits `ShipmentScheduled`
Compensating: Shipping Service cancels shipment

If payment fails, Payment Service emits `PaymentFailed`. Inventory Service hears `PaymentFailed`, releases the reservation (compensation step 2). Order Service hears `InventoryReleased`, cancels the order (compensation step 1). The cascade of compensations is triggered by failure events, not by a central coordinator.

```python
# Orchestration-based saga using a state machine
import uuid
from enum import Enum
from dataclasses import dataclass, field
from typing import Optional

class SagaState(Enum):
    STARTED = "started"
    INVENTORY_RESERVED = "inventory_reserved"
    PAYMENT_PROCESSED = "payment_processed"
    COMPLETED = "completed"
    COMPENSATING_PAYMENT = "compensating_payment"
    COMPENSATING_INVENTORY = "compensating_inventory"
    FAILED = "failed"

@dataclass
class OrderSaga:
    saga_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    order_id: str = ""
    state: SagaState = SagaState.STARTED
    reservation_id: Optional[str] = None
    payment_id: Optional[str] = None

class OrderSagaOrchestrator:
    """Central orchestrator for the order placement saga."""

    def start(self, order_id: str, items: list, amount: int) -> OrderSaga:
        saga = OrderSaga(order_id=order_id)
        db.save_saga(saga)  # persist saga state

        # Step 1: Reserve inventory
        try:
            result = inventory_service.reserve(items, saga.saga_id)
            saga.reservation_id = result["reservation_id"]
            saga.state = SagaState.INVENTORY_RESERVED
            db.save_saga(saga)
        except Exception:
            saga.state = SagaState.FAILED
            db.save_saga(saga)
            raise

        # Step 2: Process payment
        try:
            result = payment_service.charge(amount, saga.saga_id)
            saga.payment_id = result["payment_id"]
            saga.state = SagaState.PAYMENT_PROCESSED
            db.save_saga(saga)
        except Exception:
            # Compensate: release inventory
            saga.state = SagaState.COMPENSATING_INVENTORY
            db.save_saga(saga)
            self._compensate_inventory(saga)
            raise

        # Step 3: Schedule shipment
        try:
            shipping_service.schedule(order_id, saga.saga_id)
            saga.state = SagaState.COMPLETED
            db.save_saga(saga)
        except Exception:
            # Compensate: refund payment and release inventory
            saga.state = SagaState.COMPENSATING_PAYMENT
            db.save_saga(saga)
            self._compensate_payment(saga)
            raise

        return saga

    def _compensate_payment(self, saga: OrderSaga):
        """Reverse payment if it was charged."""
        if saga.payment_id:
            try:
                payment_service.refund(saga.payment_id)
            except Exception:
                # Log and schedule for retry — compensation failures need human attention
                alert_on_call(f"Compensation failed: saga {saga.saga_id}")
            self._compensate_inventory(saga)

    def _compensate_inventory(self, saga: OrderSaga):
        """Release inventory reservation."""
        if saga.reservation_id:
            try:
                inventory_service.release_reservation(saga.reservation_id)
                saga.state = SagaState.FAILED
                db.save_saga(saga)
            except Exception:
                alert_on_call(f"Inventory compensation failed: saga {saga.saga_id}")
```

The saga's state must be persisted durably, with each transition stored before the corresponding service call is made. This ensures that if the orchestrator crashes mid-saga, it can resume from the last durable state when it restarts. This is the "saga log" — a durable record of where the saga is in its execution.

Dirty reads are an unavoidable property of sagas. Between the inventory reservation (step 2) and the payment success (step 3), the system is in an intermediate state: inventory is reserved but payment has not been confirmed. If another part of the system reads the inventory count during this window, it sees the stock as reduced before the order is confirmed. This is an isolation violation that ACID transactions prevent but sagas cannot. Mitigations include: not showing intermediate state to users, using "soft reservations" that are visible only to the saga, or accepting the temporary inconsistency as a business decision.

---

## How It Connects

The Saga pattern is directly tied to event-driven architecture. Choreography sagas are implemented as a chain of events on an event bus.

[[event-driven-architecture|Event-Driven Architecture]]

CQRS is often combined with the Saga pattern: the saga produces events that update the read model, which serves queries about the saga's current state.

[[cqrs|CQRS]]

The outbox pattern ensures that the event publication at each saga step is atomic with the local database transaction.

[[outbox-pattern|Outbox Pattern]]

---

## Common Misconceptions

Misconception 1: "A saga provides the same guarantees as a distributed transaction."
Reality: A saga provides eventual consistency, not atomicity. Between steps, the system can be in an intermediate state visible to other operations. Sagas do not provide isolation. The choice of saga over distributed transaction is the deliberate acceptance of weaker guarantees in exchange for better availability and simpler infrastructure.

Misconception 2: "Compensating transactions are guaranteed to succeed."
Reality: A compensating transaction is itself a distributed operation that can fail. A refund API might be temporarily unavailable. An inventory release might fail due to a database timeout. Compensation failures require explicit handling: retry with backoff, alert operations staff, and log for manual review. The saga must handle the "compensation failed" case as part of its error handling.

Misconception 3: "Choreography is always better because it is more loosely coupled."
Reality: Choreography is more loosely coupled but harder to monitor, debug, and reason about at scale. When a business transaction spans 8 services in a choreography model and one of them is not firing its compensation correctly, tracing the saga's current state requires correlating events across all 8 services. Orchestration makes the saga state explicit and centrally visible, at the cost of the orchestrator becoming a dependency.

---

## Why It Matters in Practice

Sagas are the practical solution to distributed transactions in microservices. Every e-commerce order placement, every financial transfer across service boundaries, every multi-step workflow — these all require saga-style coordination. Understanding the pattern means designing business workflows that handle partial failures gracefully, rather than hoping that all steps always succeed.

For Python developers, the most practical starting point is orchestration with explicit saga state persisted in a database. This is more operationally visible than choreography and easier to debug. Message queue-based choreography sagas are appropriate when the service boundaries are well-established and observability tooling is in place.

---

## Interview Angle

Common question forms:
- "How do you handle a distributed transaction across multiple microservices?"
- "What is the Saga pattern and what are its two implementation approaches?"
- "What is a compensating transaction?"

Answer frame:
Define the problem: ACID transactions don't span services; 2PC is slow and fragile. Introduce the Saga: sequence of local transactions with compensating transactions for rollback. Describe choreography: event-driven, decentralized, implicit workflow. Describe orchestration: central coordinator, explicit state, easier to monitor. Explain compensating transactions: reversal of each step, applied in reverse order. Acknowledge dirty reads as an inherent property. Discuss failure handling in compensations.

---

## Related Notes

- [[microservices-basics|Microservices Basics]]
- [[event-driven-architecture|Event-Driven Architecture]]
- [[outbox-pattern|Outbox Pattern]]
- [[cqrs|CQRS]]
- [[circuit-breaker|Circuit Breaker]]
