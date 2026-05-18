---
title: 06 - Event Sourcing
description: "Storing the full history of state changes as an immutable event log, replaying events to rebuild state, and when this approach is the right fit."
tags: [event-sourcing, events, immutability, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Event Sourcing

> Event sourcing replaces "save the current state" with "save everything that happened"  -  and this simple reversal unlocks time travel, audit logs, and event-driven projections, at the cost of significant complexity.

---

## Quick Reference

**Core idea:**
- Instead of storing current state, store the sequence of events that led to that state
- Current state is derived by replaying all events from the beginning (or from a snapshot)
- Events are immutable  -  they are never deleted or modified, only appended
- Snapshots cache the current state after N events to avoid replaying all history on every read
- CQRS is typically combined with event sourcing: the event log is the write side; projections are the read side

**Tricky points:**
- The event log grows forever  -  snapshots and archiving strategies are required for production
- Schema evolution is harder: once an event format is stored, all future replays must handle that format
- Replaying millions of events to rebuild state is slow without snapshots
- "Current state" queries require either a projection or a replay  -  there is no simple SELECT
- Event sourcing is not appropriate for all data  -  financial transactions and audit logs are ideal; configuration data is not

---

## What It Is

Imagine a bank account. In a traditional system, the account record stores the current balance: `{account_id: 123, balance: 1500.00}`. When you deposit $200, the balance is updated to $1700. When you withdraw $50, it becomes $1650. The history is gone  -  you only have the current number. If you need to know what the balance was last Tuesday, or reproduce a series of transactions to find an error, the data is not there.

An event-sourced account stores every transaction instead: "AccountOpened: $0", "Deposited: $500", "Withdrew: $100", "Deposited: $200", "Withdrew: $50". The current balance is derived by replaying these events: 0 + 500 - 100 + 200 - 50 = 550. The history is permanent. You can replay to any point in time to see the balance as of that moment. You can replay to understand exactly what happened during a disputed transaction.

Event sourcing is the pattern of storing state changes as an immutable sequence of events rather than the current state. The event store is the single source of truth. Every change to the domain produces an event  -  a fact that something happened  -  appended to the event log. Nothing is ever updated or deleted. Current state is computed by replaying the event sequence.

This approach has three distinctive properties. First, complete history: every change is recorded with who made it, when, and what changed. This is a built-in audit log. Second, temporal queries: you can reconstruct the state at any point in time by replaying events up to that timestamp. Third, multiple projections: the same event stream can be processed by multiple consumers to build different projections of the same underlying data  -  one for the current account balance, one for monthly statements, one for fraud detection patterns.

---

## How It Actually Works

An aggregate in event sourcing is a domain entity (like a bank account, an order, a user profile) that manages its own state through events. The aggregate has a current state (built from event replay) and produces new events when commands are applied. The event store persists these events. The aggregate's state can be reconstructed at any time by loading its events and replaying them.

Snapshots prevent performance problems with long-lived aggregates. An account with 10 years of daily transactions has over 3,500 events. Replaying 3,500 events on every read is expensive. A snapshot captures the state after every N events (say, every 100 events). To load an account, load the most recent snapshot and replay only the events since that snapshot  -  at most 99 events. The snapshot can be updated periodically in a background job.

```python
from dataclasses import dataclass, field
from typing import Any
import json

@dataclass
class BankAccountEvent:
    event_type: str
    account_id: str
    data: dict
    event_number: int  # sequential, per-aggregate

@dataclass
class BankAccount:
    """Event-sourced bank account aggregate."""
    account_id: str
    balance: float = 0.0
    owner_name: str = ""
    is_frozen: bool = False
    version: int = 0  # last applied event number

    @classmethod
    def from_events(cls, account_id: str, events: list[BankAccountEvent]) -> "BankAccount":
        """Rebuild current state by replaying all events."""
        account = cls(account_id=account_id)
        for event in events:
            account._apply(event)
        return account

    def _apply(self, event: BankAccountEvent) -> None:
        """Apply a single event to update state  -  pure, no side effects."""
        if event.event_type == "AccountOpened":
            self.owner_name = event.data["owner_name"]
            self.balance = event.data.get("initial_deposit", 0.0)
        elif event.event_type == "MoneyDeposited":
            self.balance += event.data["amount"]
        elif event.event_type == "MoneyWithdrawn":
            self.balance -= event.data["amount"]
        elif event.event_type == "AccountFrozen":
            self.is_frozen = True
        self.version = event.event_number

    # Commands: validate and produce events
    def deposit(self, amount: float) -> BankAccountEvent:
        if amount <= 0:
            raise ValueError("Deposit amount must be positive")
        if self.is_frozen:
            raise RuntimeError("Account is frozen")
        event = BankAccountEvent(
            event_type="MoneyDeposited",
            account_id=self.account_id,
            data={"amount": amount, "new_balance": self.balance + amount},
            event_number=self.version + 1
        )
        self._apply(event)  # update in-memory state immediately
        return event

    def withdraw(self, amount: float) -> BankAccountEvent:
        if amount <= 0:
            raise ValueError("Withdrawal amount must be positive")
        if self.is_frozen:
            raise RuntimeError("Account is frozen")
        if self.balance < amount:
            raise ValueError("Insufficient funds")
        event = BankAccountEvent(
            event_type="MoneyWithdrawn",
            account_id=self.account_id,
            data={"amount": amount, "new_balance": self.balance - amount},
            event_number=self.version + 1
        )
        self._apply(event)
        return event

class EventStore:
    """Persistent event store: append-only, ordered by event_number per aggregate."""

    def append(self, event: BankAccountEvent, expected_version: int):
        """Optimistic concurrency: only append if no concurrent writes happened."""
        current = db.get_max_event_number(event.account_id)
        if current != expected_version:
            raise ConcurrencyException(f"Expected version {expected_version}, got {current}")
        db.insert_event(event)

    def load(self, account_id: str, from_version: int = 0) -> list[BankAccountEvent]:
        return db.get_events(account_id, from_version=from_version)

# Application layer: load aggregate, execute command, save events
event_store = EventStore()

def deposit_money(account_id: str, amount: float):
    events = event_store.load(account_id)
    account = BankAccount.from_events(account_id, events)
    new_event = account.deposit(amount)
    event_store.append(new_event, expected_version=new_event.event_number - 1)
```

Schema evolution is one of the hardest aspects of event sourcing. Once an event format is stored in the event log, it is permanent. If the event's schema needs to change, all future replays must handle both the old and new formats. Strategies include: upcasting (transform old events to the new format during replay), versioning events (EventTypeV1, EventTypeV2), and never changing events but adding new event types. This is a commitment that increases in cost over time.

---

## How It Connects

CQRS and event sourcing are closely paired. Event sourcing provides the immutable event log (write side); CQRS defines how projections (read side) are built from those events.

[[cqrs|CQRS]]

Event-driven architecture uses the same events that event sourcing produces, but at the service communication level rather than within one aggregate.

[[event-driven-architecture|Event-Driven Architecture]]

The Saga pattern, which coordinates multi-step distributed transactions, can use an event-sourced state machine to track the saga's progress.

[[saga-pattern|Saga Pattern]]

---

## Common Misconceptions

Misconception 1: "Event sourcing provides a complete audit log automatically."
Reality: Event sourcing provides a complete log of domain state changes  -  what changed and when. But "who made the change" requires attaching user identity to each event explicitly. The events are only as informative as what you put in them. A good event store includes correlation IDs, user IDs, and causation IDs for full auditability.

Misconception 2: "Event sourcing is just Kafka."
Reality: Kafka is a distributed event streaming platform. Event sourcing is an architectural pattern for persisting domain state. Kafka can be used as an event store for event sourcing, but it is not ideal for it  -  Kafka does not natively support per-aggregate ordering, optimistic concurrency control, or snapshot management. Dedicated event stores (EventStoreDB) or purpose-built solutions on top of a relational database are more appropriate for production event sourcing.

Misconception 3: "Event sourcing eliminates the need for a database."
Reality: Event sourcing requires an event store (a database optimized for append-only event log storage per aggregate). It also requires one or more projection stores for efficient queries. Instead of one database, a typical event-sourced system uses two or more: the event store plus projection databases (relational, document, cache, search index). This is more infrastructure, not less.

---

## Why It Matters in Practice

Event sourcing is a powerful pattern for domains where history matters: financial systems, legal systems, healthcare records, e-commerce order lifecycles. It is over-engineering for domains where only current state matters and history is unimportant.

For Python developers, the most practical entry point is implementing a simple event-sourced aggregate for one bounded context where audit history is genuinely needed, using PostgreSQL as the event store (append-only table with optimistic locking). Full event sourcing infrastructure (EventStoreDB, Kafka as event store, distributed projections) is appropriate for organizations at scale with dedicated event streaming infrastructure.

---

## Interview Angle

Common question forms:
- "What is event sourcing and how does it differ from CRUD?"
- "What is a projection in event sourcing?"
- "What are the tradeoffs of event sourcing?"

Answer frame:
Define event sourcing: store events (what happened) not current state. Contrast with CRUD: CRUD stores current state; event sourcing stores all changes. Explain current state recovery: replay events, optionally from a snapshot. Describe projections: derived read models built from event streams. List trade-offs: benefits (audit log, temporal queries, multiple projections) vs costs (complexity, schema evolution difficulty, event store infrastructure). Use cases: financial transactions, order lifecycle, collaborative editing. When not to use: simple CRUD where history has no business value.

---

## Related Notes

- [[cqrs|CQRS]]
- [[event-driven-architecture|Event-Driven Architecture]]
- [[saga-pattern|Saga Pattern]]
- [[acid-vs-base|ACID vs BASE]]
- [[kafka-system-design|Kafka in System Design]]
