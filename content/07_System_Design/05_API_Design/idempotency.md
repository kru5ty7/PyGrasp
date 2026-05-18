---
title: 06 - Idempotency
description: "Idempotency keys, PUT vs POST semantics, and why designing retry-safe API operations is essential for reliable distributed systems."
tags: [idempotency, api-design, reliability, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Idempotency

> Idempotency is the property that makes retrying safe  -  and without it, your distributed system has bugs that only appear when things go wrong, which is exactly when you can least afford them.

---

## Quick Reference

**Core idea:**
- An operation is idempotent if performing it multiple times has the same result as performing it once
- GET, PUT, DELETE are idempotent by HTTP specification; POST and PATCH are not
- Idempotency keys: a unique client-generated ID attached to a request, allowing the server to detect duplicates
- Payment and order creation must be idempotent  -  network failures cause retries, retries cause duplicates
- Deduplication window: how long the server stores idempotency keys before forgetting past requests

**Tricky points:**
- PUT is idempotent (same full replacement twice = same result); PATCH is not always (increment PATCH is not idempotent)
- An idempotency key deduplicates based on the key, not the payload  -  same key with different payload returns the original response
- The server must persist idempotency keys durably (not in memory)  -  a restart must remember past requests
- Idempotency windows expire  -  an old idempotency key may not be recognized after weeks
- "Safe" and "idempotent" are different: GET is both; DELETE is idempotent but not safe (it has side effects)

---

## What It Is

Imagine a bank's telephone service. You call to transfer $100 from savings to checking. The line drops before the bank confirms. Did the transfer happen? You do not know. You call back and try again. If the transfer was not idempotent, the bank processes it a second time and you transfer $200 total. If it was idempotent  -  you identify the original transfer with a reference number and the bank detects the duplicate  -  the second call is a no-op, and you successfully transfer $100.

Idempotency is the mathematical property where applying a function multiple times produces the same result as applying it once: f(f(x)) = f(x). In HTTP APIs, it means that a client can safely retry a failed request without worrying about duplicate effects. This matters whenever a request might fail in a way that leaves the client uncertain about whether the operation succeeded: network timeouts, connection resets, server crashes, or slow responses that trigger client-side retries.

HTTP methods have defined idempotency semantics. GET, HEAD, OPTIONS, and TRACE are safe (no state change) and idempotent. PUT replaces a resource: sending the same PUT request twice results in the same state (the second replace has no additional effect). DELETE removes a resource: deleting a resource that no longer exists returns 404 but the resulting state (resource absent) is the same. These are idempotent. POST creates a resource or triggers an action: two POST requests create two resources or trigger the action twice. PATCH modifies specific fields: if the PATCH sets a value, applying it twice has the same result (idempotent); if the PATCH increments a value, applying it twice produces a different result (not idempotent).

Payment processing is the most critical domain for idempotency. A user clicks "pay now". The request reaches the payment service. The payment service processes the charge. The response is lost in transit. The user's browser times out. The user clicks "pay now" again. Without idempotency, the user is charged twice. This is a fundamental business correctness requirement. Stripe, PayPal, and every serious payment API require idempotency keys for charge operations.

---

## How It Actually Works

The idempotency key is a client-generated unique identifier, typically a UUID, included in the request header (e.g., `Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000`). When the server receives a request with an idempotency key, it first checks whether it has seen this key before. If yes, it returns the stored response for that key without reprocessing. If no, it processes the request, stores the response associated with the key, and returns it.

The server stores idempotency keys and their responses in a durable store (database or Redis with persistence) with a TTL. Using an in-memory store means a server restart loses all idempotency state and all pending clients will experience duplicate operations on the next retry. Using a distributed store means all instances share the same idempotency state, so a retry hitting a different server instance is correctly deduplicated.

The deduplication logic must handle concurrent requests. If two requests with the same idempotency key arrive simultaneously (before either is processed), the server must ensure only one is processed. A database row with a unique constraint on the idempotency key prevents duplicate concurrent processing  -  the second INSERT fails with a unique constraint violation, signaling that processing is already in progress.

```python
import uuid
import json
import redis
from fastapi import FastAPI, Header, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Optional

app = FastAPI()
r = redis.Redis()

class PaymentRequest(BaseModel):
    amount_cents: int
    currency: str
    source_token: str

class PaymentResponse(BaseModel):
    payment_id: str
    status: str
    amount_cents: int

def process_payment(amount_cents: int, currency: str, source_token: str) -> dict:
    """Actual payment processing  -  must only be called once per logical request."""
    payment_id = str(uuid.uuid4())
    # Call payment processor (Stripe, etc.)
    result = stripe.charge(amount=amount_cents, currency=currency, source=source_token)
    return {"payment_id": payment_id, "status": "success", "amount_cents": amount_cents}

@app.post("/payments", response_model=PaymentResponse)
async def create_payment(
    request: PaymentRequest,
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key")
):
    if not idempotency_key:
        raise HTTPException(status_code=400, detail="Idempotency-Key header required")

    cache_key = f"idempotency:{idempotency_key}"

    # Check if we've seen this key before
    cached_response = r.get(cache_key)
    if cached_response:
        # Return the original response without reprocessing
        stored = json.loads(cached_response)
        if stored.get("status") == "processing":
            raise HTTPException(status_code=409, detail="Request is being processed")
        return PaymentResponse(**stored["response"])

    # Mark as "processing" before starting  -  prevents concurrent duplicates
    # nx=True: only set if key doesn't exist (atomic check-and-set)
    claimed = r.set(cache_key, json.dumps({"status": "processing"}), nx=True, ex=3600)
    if not claimed:
        raise HTTPException(status_code=409, detail="Concurrent request with same idempotency key")

    try:
        result = process_payment(request.amount_cents, request.currency, request.source_token)
        # Store successful response (expires after 24 hours)
        r.set(cache_key, json.dumps({"status": "done", "response": result}), ex=86400)
        return PaymentResponse(**result)
    except Exception as e:
        # Clear the processing marker so client can retry
        r.delete(cache_key)
        raise HTTPException(status_code=500, detail=str(e))
```

The idempotency key approach also requires a decision about payload mismatches. If a client sends a request with idempotency key `key-123` and amount $100, then retries with the same key but amount $200 (perhaps due to a bug), the server should return the original response ($100) or an error indicating payload mismatch. Most payment APIs (Stripe) return the original response regardless, on the principle that the key is the identity of the request, not the payload.

---

## How It Connects

Idempotency is the consumer-side requirement that makes at-least-once message delivery safe. Message queues guarantee at-least-once; idempotent consumers make that safe.

[[message-queues|Message Queues]]

The HTTP method semantics that define idempotency (PUT, DELETE) are part of the broader REST API design contract.

[[api-design-principles|API Design Principles]]

In the outbox pattern, the relay may publish the same event more than once. Event consumers must be idempotent to handle this correctly.

[[outbox-pattern|Outbox Pattern]]

---

## Common Misconceptions

Misconception 1: "PUT is always idempotent, so I should use PUT instead of POST for creation."
Reality: PUT at a specific URL is idempotent (two PUTs to `/users/123` produce the same result). But clients do not always know the resource ID before creation  -  the server assigns it. Using POST for creation (where the server generates the ID) is the correct pattern. For idempotent creation (where the client provides the ID or an external idempotency key), PUT at a specific URL or POST with an idempotency key are both valid.

Misconception 2: "GET requests don't need idempotency consideration."
Reality: GET is defined as safe and idempotent. Most GET implementations are naturally idempotent (reading data does not change it). But a GET that triggers side effects (logging, analytics incrementing, quota deduction) may not be. Such GET requests violate the HTTP spec and should be POST operations with idempotent handling.

Misconception 3: "Idempotency keys only matter for payment operations."
Reality: Any operation that creates resources, sends notifications, or modifies state in a way that matters needs idempotency if there is any risk of the client retrying. Creating user accounts (duplicate accounts on retry), sending emails (duplicate emails), order creation (duplicate orders), and resource reservation (double-booking) are all cases where idempotency is critical.

---

## Why It Matters in Practice

Without idempotency for mutating operations, retry logic (which every reliable client should implement) creates duplicate effects. Infrastructure that retries requests automatically  -  load balancers, API gateways, CDNs  -  can trigger duplicates without the client code doing anything wrong. A network timeout does not tell the client whether the server received and processed the request  -  it only tells the client that no response arrived. Idempotency keys solve this uncertainty by making the retry outcome deterministic.

For Python developers, idempotency should be a first-class design concern for any endpoint that creates, modifies, or deletes resources. FastAPI and Django REST Framework do not provide idempotency handling out of the box  -  it must be implemented explicitly in the handler, using the pattern shown above.

---

## Interview Angle

Common question forms:
- "What is idempotency and why does it matter?"
- "How would you implement idempotent API endpoints?"
- "What HTTP methods are idempotent and why?"

Answer frame:
Define idempotency: same result regardless of how many times you apply it. Explain why it matters: retries are necessary, and retries without idempotency cause duplicates. Describe HTTP method idempotency: GET/PUT/DELETE yes, POST/PATCH no. Describe idempotency keys: client-generated UUID, server stores key + response in durable cache, returns stored response on duplicate. Walk through the implementation: check before processing, set processing marker with NX, process, store response, return. Cover the concurrent duplicate case: NX set prevents two simultaneous requests with the same key.

---

## Related Notes

- [[api-design-principles|API Design Principles]]
- [[message-queues|Message Queues]]
- [[outbox-pattern|Outbox Pattern]]
- [[rest|REST]]
