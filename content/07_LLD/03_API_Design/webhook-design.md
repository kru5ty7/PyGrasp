---
title: 08 - Webhook Design
description: Webhooks are HTTP callbacks that notify external systems when events occur, inverting the typical request-response pattern so that producers push updates to consumers instead of consumers polling for changes.
tags: [api, webhooks, events, callbacks, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Webhook Design

> Webhooks are HTTP POST requests that a server sends to a registered URL when an event occurs, enabling real-time event-driven integrations without polling.

---

## Quick Reference

**Core idea:**
- A webhook is a **push notification** via HTTP: when an event happens, the server sends an HTTP POST to a URL the client registered
- Replaces polling: instead of the client asking "did anything change?" every 5 seconds, the server tells the client when something changes
- Webhook payloads should be **signed** (HMAC) so the receiver can verify they came from the expected sender
- Design for **at-least-once delivery**: webhooks can be sent multiple times (retries), so receivers must handle duplicates (idempotency)
- Include an **event type**, a **timestamp**, and the full or partial event data in the payload

**Tricky points:**
- The receiver's endpoint might be down - implement **retry with exponential backoff** and eventually disable the webhook after repeated failures
- Webhook payloads should not contain secrets - the receiver should fetch sensitive data via API using the event ID
- Verify webhook signatures to prevent spoofing - attackers can send fake webhook payloads to your endpoint
- Webhooks are fire-and-forget from the sender's perspective - the sender should not depend on the receiver's response

---

## What It Is

Think of a doorbell. Without one, you would have to keep checking the door every few minutes to see if someone arrived. With a doorbell, visitors announce themselves. You do not waste time checking when no one is there, and you do not miss visitors because you were not checking at the right moment. A webhook is a digital doorbell: the server rings your endpoint when something happens.

Webhooks invert the typical API interaction. In a standard REST API, the client sends requests to the server. With webhooks, the server sends requests to the client. The client registers a URL ("when a payment succeeds, POST to https://myapp.com/webhooks/payments"), and the server calls that URL with event details whenever the event occurs.

The design challenges are reliability (what if the receiver is down?), security (how does the receiver know the webhook is genuine?), and idempotency (what if the same event is delivered twice?). A well-designed webhook system addresses all three: retries with backoff for reliability, HMAC signatures for security, and idempotency keys for deduplication.

---

## How It Actually Works

The webhook sender stores registered endpoint URLs and their associated event subscriptions. When an event occurs, it constructs a payload, signs it with HMAC-SHA256 using a shared secret, sends an HTTP POST, and retries on failure. The receiver verifies the signature, processes the event idempotently, and returns 200 OK to acknowledge receipt.

```python
import hashlib
import hmac
import json
import time
from datetime import datetime
from dataclasses import dataclass, field
from typing import Any
from uuid import uuid4


# --- SENDER SIDE ---

@dataclass
class WebhookSubscription:
    id: str
    url: str
    secret: str
    events: list[str]
    active: bool = True
    failure_count: int = 0
    max_failures: int = 5


@dataclass
class WebhookEvent:
    id: str
    type: str
    timestamp: str
    data: dict[str, Any]


class WebhookSender:
    """Sends webhook notifications with signing and retry."""

    def __init__(self):
        self._subscriptions: list[WebhookSubscription] = []

    def register(self, url: str, events: list[str], secret: str) -> str:
        sub_id = str(uuid4())
        self._subscriptions.append(
            WebhookSubscription(id=sub_id, url=url, secret=secret, events=events)
        )
        return sub_id

    def notify(self, event_type: str, data: dict) -> None:
        """Send webhook to all subscribers of this event type."""
        event = WebhookEvent(
            id=str(uuid4()),
            type=event_type,
            timestamp=datetime.now().isoformat(),
            data=data,
        )
        payload = json.dumps({
            "id": event.id,
            "type": event.type,
            "timestamp": event.timestamp,
            "data": event.data,
        })

        for sub in self._subscriptions:
            if event_type in sub.events and sub.active:
                self._deliver(sub, payload)

    def _deliver(self, sub: WebhookSubscription, payload: str) -> None:
        """Deliver with signature. In production, use async + retry queue."""
        signature = self._sign(payload, sub.secret)
        headers = {
            "Content-Type": "application/json",
            "X-Webhook-Signature": f"sha256={signature}",
            "X-Webhook-Id": str(uuid4()),
            "X-Webhook-Timestamp": str(int(time.time())),
        }

        # In production: httpx.post(sub.url, content=payload, headers=headers)
        # with retry logic on 5xx or timeout
        print(f"POST {sub.url}")
        print(f"  Signature: {signature[:20]}...")
        print(f"  Payload: {payload[:80]}...")

    @staticmethod
    def _sign(payload: str, secret: str) -> str:
        return hmac.new(
            secret.encode(), payload.encode(), hashlib.sha256
        ).hexdigest()


# --- RECEIVER SIDE ---

class WebhookReceiver:
    """Receives and verifies webhooks."""

    def __init__(self, secret: str):
        self._secret = secret
        self._processed_ids: set[str] = set()  # idempotency tracking

    def handle(self, payload: str, signature: str) -> dict:
        """Process an incoming webhook."""
        # 1. Verify signature
        if not self._verify_signature(payload, signature):
            return {"status": "rejected", "reason": "invalid signature"}

        # 2. Parse payload
        event = json.loads(payload)

        # 3. Idempotency check - skip if already processed
        if event["id"] in self._processed_ids:
            return {"status": "duplicate", "event_id": event["id"]}

        # 4. Process the event
        self._process_event(event)

        # 5. Mark as processed
        self._processed_ids.add(event["id"])

        return {"status": "accepted", "event_id": event["id"]}

    def _verify_signature(self, payload: str, signature: str) -> bool:
        expected = hmac.new(
            self._secret.encode(), payload.encode(), hashlib.sha256
        ).hexdigest()
        # Use hmac.compare_digest to prevent timing attacks
        return hmac.compare_digest(f"sha256={expected}", signature)

    def _process_event(self, event: dict) -> None:
        event_type = event["type"]
        print(f"Processing event: {event_type}")

        handlers = {
            "payment.completed": self._handle_payment,
            "user.created": self._handle_user_created,
            "order.shipped": self._handle_order_shipped,
        }
        handler = handlers.get(event_type)
        if handler:
            handler(event["data"])
        else:
            print(f"Unknown event type: {event_type}")

    def _handle_payment(self, data: dict) -> None:
        print(f"Payment {data.get('payment_id')} completed: ${data.get('amount')}")

    def _handle_user_created(self, data: dict) -> None:
        print(f"New user: {data.get('email')}")

    def _handle_order_shipped(self, data: dict) -> None:
        print(f"Order {data.get('order_id')} shipped")


# --- USAGE ---
shared_secret = "whsec_supersecretkey123"

# Sender (e.g., payment service)
sender = WebhookSender()
sender.register(
    url="https://myapp.com/webhooks/payments",
    events=["payment.completed", "payment.failed"],
    secret=shared_secret,
)
sender.notify("payment.completed", {
    "payment_id": "pay_123",
    "amount": 99.99,
    "currency": "USD",
    "customer_id": "cust_456",
})

# Receiver (e.g., your app)
receiver = WebhookReceiver(shared_secret)
payload = json.dumps({
    "id": "evt_789",
    "type": "payment.completed",
    "timestamp": datetime.now().isoformat(),
    "data": {"payment_id": "pay_123", "amount": 99.99},
})
sig = f"sha256={hmac.new(shared_secret.encode(), payload.encode(), hashlib.sha256).hexdigest()}"

result = receiver.handle(payload, sig)
print(f"Result: {result}")

# Duplicate delivery - handled idempotently
result2 = receiver.handle(payload, sig)
print(f"Duplicate: {result2}")  # status: duplicate
```

---

## How It Connects

Webhooks are the push-based counterpart to polling-based API design. Understanding REST API principles provides context for when webhooks are appropriate.

[[api-design-principles|API Design Principles]]

Webhook receivers must handle duplicate deliveries, which requires idempotency. Each event should be processed exactly once even if delivered multiple times.

[[idempotency|Idempotency]]

Webhooks implement the Observer pattern at the system level: the sender is the subject, webhook subscribers are the observers, and HTTP POST is the notification mechanism.

[[observer-pattern|Observer Pattern]]

---

## Common Misconceptions

Misconception 1: "Webhooks guarantee exactly-once delivery."
Reality: Webhooks provide at-least-once delivery. Network failures, timeouts, and retries mean the same event may be delivered multiple times. Receivers must be idempotent - processing the same event twice should have the same effect as processing it once.

Misconception 2: "If the webhook returns 200, the event was successfully processed."
Reality: Returning 200 means the receiver acknowledged receipt. Processing might happen asynchronously (queued for later). Best practice: acknowledge receipt immediately (200), then process asynchronously. This prevents the sender from timing out during slow processing.

---

## Why It Matters in Practice

Webhooks are the backbone of modern integrations. Stripe sends payment events via webhooks. GitHub sends push/PR events. Slack sends interaction events. Designing and consuming webhooks correctly - with signatures, retries, and idempotent processing - is essential for building reliable integrations.

---

## Interview Angle

Common question forms:
- "What are webhooks and how do they differ from polling?"
- "How do you secure webhooks?"
- "How do you handle webhook failures and retries?"

Answer frame:
Define webhooks as push-based HTTP callbacks. Contrast with polling (efficiency, real-time). Explain HMAC signatures for security. Discuss retry with backoff for reliability. Emphasize idempotent processing. Show the event structure (id, type, timestamp, data).

---

## Related Notes

- [[api-design-principles|API Design Principles]]
- [[idempotency|Idempotency]]
- [[observer-pattern|Observer Pattern]]
- [[error-handling-apis|API Error Handling]]
