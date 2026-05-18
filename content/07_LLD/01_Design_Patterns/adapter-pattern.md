---
title: 07 - Adapter Pattern
description: The Adapter pattern converts one interface into another that clients expect, letting classes with incompatible interfaces work together without modifying either.
tags: [design-patterns, adapter, structural, wrapper, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Adapter Pattern

> The Adapter wraps an object with an incompatible interface and exposes the interface that the client expects, bridging the gap without modifying either side.

---

## Quick Reference

**Core idea:**
- Adapter translates one interface into another - the client calls methods it expects, the adapter forwards to the adapted object's actual methods
- Solves the problem of integrating third-party libraries or legacy code whose interfaces do not match your system's conventions
- Two forms: **class adapter** (uses inheritance) and **object adapter** (uses composition) - Python favors the object adapter
- The adapter itself contains no business logic - it only translates method names, parameter formats, and return types
- Common in Python: wrapping REST APIs, database drivers, logging backends, and serialization libraries

**Tricky points:**
- An adapter that contains business logic is doing too much - it should only translate, not transform
- Multiple adapters for the same target interface is a sign that you should define a Protocol and have each adapter implement it
- Adapters add a layer of indirection - if the interfaces are close enough, renaming methods might be simpler
- Python's duck typing reduces the need for formal adapters - if the method names already match, no adapter is needed

---

## What It Is

Think of a power adapter for international travel. Your laptop charger has a US plug. The outlet in Europe has a different shape. You do not rewire your charger or replace the outlet. You use an adapter that accepts the US plug on one side and fits the European outlet on the other. The adapter does not change the electricity - it only changes the physical interface.

The Adapter pattern does the same in code. You have a class your system depends on (the client interface) and a class you want to use (the adaptee) that has different method names, parameter types, or return formats. The adapter wraps the adaptee, implements the client interface, and translates each call. Your system calls `adapter.save(user)`, the adapter internally calls `legacy_db.insert_record(user_dict)`. Neither side is modified.

In Python, adapters are commonly used when integrating third-party libraries. Your application defines a `NotificationSender` Protocol with `send(to, message)`. The Twilio SDK has `client.messages.create(body=msg, to=number, from_=sender)`. An adapter wraps the Twilio client and translates `send()` into `messages.create()`. If you later switch from Twilio to another SMS provider, you write a new adapter. Your application code does not change.

---

## How It Actually Works

The object adapter holds a reference to the adaptee and delegates calls by translating method signatures. The adapter class implements the interface the client expects (often a Protocol) and internally calls the adaptee's actual methods with the correct parameter mapping.

```python
from typing import Protocol
from dataclasses import dataclass
import json


# Your system's expected interface
class NotificationSender(Protocol):
    def send(self, to: str, message: str) -> bool: ...


# Third-party SMS library (you cannot modify this)
class TwilioClient:
    def __init__(self, account_sid: str, auth_token: str):
        self.sid = account_sid
        self.token = auth_token

    def create_message(self, body: str, to_number: str, from_number: str) -> dict:
        print(f"Twilio: sending '{body}' to {to_number} from {from_number}")
        return {"status": "sent", "sid": "SM123"}


# Legacy email library (different interface)
class LegacyEmailClient:
    def __init__(self, smtp_host: str):
        self.host = smtp_host

    def dispatch_email(self, recipient: str, subject: str, html_body: str) -> int:
        print(f"Email to {recipient}: {subject}")
        return 200  # status code


# Adapter 1: Twilio -> NotificationSender
class TwilioAdapter:
    def __init__(self, client: TwilioClient, from_number: str):
        self._client = client
        self._from = from_number

    def send(self, to: str, message: str) -> bool:
        result = self._client.create_message(
            body=message,
            to_number=to,
            from_number=self._from,
        )
        return result["status"] == "sent"


# Adapter 2: Legacy email -> NotificationSender
class EmailAdapter:
    def __init__(self, client: LegacyEmailClient):
        self._client = client

    def send(self, to: str, message: str) -> bool:
        status = self._client.dispatch_email(
            recipient=to,
            subject="Notification",
            html_body=f"<p>{message}</p>",
        )
        return status == 200


# Your application code depends on NotificationSender, not on concrete libraries
class AlertService:
    def __init__(self, sender: NotificationSender):
        self._sender = sender

    def send_alert(self, user_contact: str, alert_text: str) -> None:
        success = self._sender.send(user_contact, alert_text)
        if not success:
            print(f"Failed to send alert to {user_contact}")


# Wire up with SMS
twilio = TwilioClient("ACxxx", "token123")
sms_sender = TwilioAdapter(twilio, from_number="+1234567890")
alert_service = AlertService(sms_sender)
alert_service.send_alert("+0987654321", "Server CPU critical")

# Wire up with email - zero changes to AlertService
email_client = LegacyEmailClient("smtp.company.com")
email_sender = EmailAdapter(email_client)
alert_service = AlertService(email_sender)
alert_service.send_alert("ops@company.com", "Server CPU critical")


# Data format adapter - adapting JSON API responses
@dataclass
class User:
    id: str
    full_name: str
    email: str

class ExternalAPIClient:
    """Third-party API returns data in a different format."""
    def fetch_user(self, user_id: str) -> dict:
        return {
            "userId": user_id,
            "firstName": "Alice",
            "lastName": "Smith",
            "emailAddress": "alice@example.com",
            "createdAt": "2026-01-01",
        }

class UserAPIAdapter:
    """Adapts external API format to our domain model."""
    def __init__(self, api: ExternalAPIClient):
        self._api = api

    def get_user(self, user_id: str) -> User:
        raw = self._api.fetch_user(user_id)
        return User(
            id=raw["userId"],
            full_name=f"{raw['firstName']} {raw['lastName']}",
            email=raw["emailAddress"],
        )

adapter = UserAPIAdapter(ExternalAPIClient())
user = adapter.get_user("123")
print(f"{user.full_name} <{user.email}>")  # Alice Smith <alice@example.com>
```

---

## How It Connects

The Adapter pattern is a structural pattern that composes objects to achieve interface compatibility. It uses composition (has-a the adaptee) rather than inheritance.

[[design-patterns-overview|Design Patterns Overview]]

[[composition-over-inheritance|Composition Over Inheritance]]

Adapters implement the Dependency Inversion Principle: your business logic depends on an abstraction (the Protocol), and the adapter connects that abstraction to a concrete third-party library.

[[dip|Dependency Inversion Principle]]

The Facade pattern is related but different: Facade simplifies a complex subsystem into a single interface, while Adapter converts one interface into another.

[[facade-pattern|Facade Pattern]]

---

## Common Misconceptions

Misconception 1: "An adapter should transform data, not just translate interfaces."
Reality: An adapter should only translate interface differences - method names, parameter order, return types. If you are transforming business data (calculating, aggregating, filtering), that logic belongs in a service or mapper, not in an adapter. An adapter that does too much becomes a maintenance burden.

Misconception 2: "You need an adapter for every third-party library."
Reality: If the library's interface matches your needs (or close enough with duck typing), use it directly. Adapters are valuable at architectural boundaries where you want to isolate your code from external dependencies. A library used in one place does not need an adapter.

---

## Why It Matters in Practice

Adapters are essential for integrating third-party services without coupling your codebase to their APIs. When Stripe changes their SDK, you update one adapter file. When you switch from SendGrid to Mailgun, you write a new adapter. Without adapters, vendor API changes require modifying every file that uses the vendor, and switching vendors is a project-wide refactor.

---

## Interview Angle

Common question forms:
- "What is the Adapter pattern?"
- "How would you integrate a third-party library with an incompatible interface?"
- "What is the difference between Adapter and Facade?"

Answer frame:
Define Adapter as interface translation. Show a concrete example (SMS library with different method signatures). Explain object adapter (composition) vs class adapter (inheritance). Distinguish from Facade (simplification vs translation). Connect to DIP and testability.

---

## Related Notes

- [[design-patterns-overview|Design Patterns Overview]]
- [[composition-over-inheritance|Composition Over Inheritance]]
- [[dip|Dependency Inversion Principle]]
- [[facade-pattern|Facade Pattern]]
