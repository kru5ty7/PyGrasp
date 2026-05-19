---
title: 12 - Dependency Inversion Principle
description: High-level modules should not depend on low-level modules - both should depend on abstractions, so that business logic is decoupled from infrastructure details like databases, APIs, and file systems.
tags: [oop, solid, dip, abstraction, dependency-injection, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Dependency Inversion Principle

> High-level modules should not depend on low-level modules. Both should depend on abstractions. Abstractions should not depend on details. Details should depend on abstractions.

---

## Quick Reference

**Core idea:**
- DIP says business logic (high-level) should not import or depend on infrastructure code (low-level) directly
- Instead, define an **abstraction** (Protocol or ABC) that the business logic depends on, and have the infrastructure code implement it
- The "inversion" is in the direction of dependency: instead of business logic depending on the database, the database adapter depends on the interface that business logic defines
- DIP enables **dependency injection**: pass concrete implementations into the business logic at construction time
- DIP is what makes code testable in isolation - swap the real database for a fake in tests

**Tricky points:**
- DIP does not mean "use interfaces everywhere" - it applies at **architectural boundaries** where business logic meets infrastructure
- The abstraction should be owned by the high-level module, not by the low-level module - this is the "inversion"
- Python's duck typing provides implicit DIP - a function that calls `obj.save()` does not care what `obj` actually is
- Over-applying DIP creates unnecessary indirection - if a function directly calls `json.dumps()`, adding a `Serializer` abstraction is premature unless you anticipate swapping serialization formats

---

## What It Is

Think of an electrical appliance and a power outlet. A lamp does not contain its own generator. A toaster does not have a built-in coal furnace. Instead, both depend on a standard interface: the electrical outlet. The power plant (low-level infrastructure) also conforms to this interface by delivering power at the standard voltage and frequency. The appliance and the power source do not know about each other - they both depend on the outlet standard (the abstraction). You can swap the power source from coal to solar without changing the lamp. You can swap the lamp for a computer without changing the power source. This is dependency inversion.

In software, the "power outlet" is an abstraction - a Protocol or ABC that defines what operations are available. The "appliance" is your business logic (high-level module). The "power source" is your infrastructure (database, email service, payment gateway). Without DIP, your business logic directly imports and calls the database module. This means your business logic cannot work without the database. It cannot be tested without the database. It cannot switch to a different database without being modified.

With DIP, your business logic defines an interface: "I need something that can save and retrieve users." The database module implements that interface. The business logic never imports the database module directly. Instead, the concrete database implementation is injected at construction time. The dependency arrow is inverted: instead of business logic depending on the database, the database adapter depends on the interface defined by the business logic.

This inversion is the key insight. In the non-inverted design, the high-level policy module (business rules) depends on the low-level detail module (database). Changes to the database force changes to the business logic. In the inverted design, both depend on the abstraction, and neither depends on the other. You can change the database from Postgres to MongoDB by writing a new adapter that implements the same interface. The business logic is untouched.

---

## How It Actually Works

DIP in Python is implemented through constructor injection combined with Protocols or ABCs. The high-level class declares its dependencies as constructor parameters typed with abstractions. The composition root (the entry point of the application, or a dependency injection container) creates the concrete implementations and wires them together.

The abstraction should be defined alongside the high-level module, not alongside the low-level module. If `UserService` needs a repository, the `Repository` Protocol is defined in the same package as `UserService`, not in the database package. This ensures that the database package depends on (implements) the business layer's interface, not the other way around.

```python
from typing import Protocol
from dataclasses import dataclass


# The abstraction lives with the business logic, NOT with the infrastructure
class UserRepository(Protocol):
    """Defined by the business layer. Infrastructure implements it."""
    def get(self, user_id: str) -> dict | None: ...
    def save(self, user: dict) -> None: ...
    def find_by_email(self, email: str) -> dict | None: ...


class EmailSender(Protocol):
    """Defined by the business layer."""
    def send(self, to: str, subject: str, body: str) -> None: ...


# HIGH-LEVEL MODULE: business logic depends on abstractions only
class UserService:
    """Contains business rules. Has no idea about Postgres, Redis, or SMTP."""

    def __init__(self, repo: UserRepository, emailer: EmailSender):
        self._repo = repo      # abstraction, not concrete class
        self._emailer = emailer # abstraction, not concrete class

    def register(self, name: str, email: str) -> dict:
        existing = self._repo.find_by_email(email)
        if existing:
            raise ValueError(f"Email {email} already registered")

        user = {"name": name, "email": email, "status": "active"}
        self._repo.save(user)
        self._emailer.send(email, "Welcome!", f"Hello {name}, welcome aboard!")
        return user

    def deactivate(self, user_id: str) -> None:
        user = self._repo.get(user_id)
        if not user:
            raise ValueError(f"User {user_id} not found")
        user["status"] = "inactive"
        self._repo.save(user)


# LOW-LEVEL MODULE: infrastructure implements the abstraction
class PostgresUserRepository:
    """Concrete implementation. Depends on the Protocol, not the other way around."""
    def __init__(self, connection_string: str):
        self._conn_str = connection_string

    def get(self, user_id: str) -> dict | None:
        # Real Postgres query here
        print(f"SELECT * FROM users WHERE id = '{user_id}'")
        return {"name": "Alice", "email": "alice@example.com", "status": "active"}

    def save(self, user: dict) -> None:
        print(f"INSERT/UPDATE users SET ... WHERE email = '{user['email']}'")

    def find_by_email(self, email: str) -> dict | None:
        print(f"SELECT * FROM users WHERE email = '{email}'")
        return None


class SMTPEmailSender:
    def __init__(self, host: str, port: int):
        self._host = host
        self._port = port

    def send(self, to: str, subject: str, body: str) -> None:
        print(f"SMTP {self._host}:{self._port} -> {to}: {subject}")


# COMPOSITION ROOT: wire everything together at the application entry point
def create_app() -> UserService:
    repo = PostgresUserRepository("postgresql://localhost/mydb")
    emailer = SMTPEmailSender("smtp.company.com", 587)
    return UserService(repo, emailer)


# TESTING: swap implementations without touching UserService
class FakeUserRepository:
    def __init__(self):
        self._store: dict[str, dict] = {}

    def get(self, user_id: str) -> dict | None:
        return self._store.get(user_id)

    def save(self, user: dict) -> None:
        self._store[user["email"]] = user

    def find_by_email(self, email: str) -> dict | None:
        return self._store.get(email)


class FakeEmailSender:
    def __init__(self):
        self.sent: list[tuple[str, str, str]] = []

    def send(self, to: str, subject: str, body: str) -> None:
        self.sent.append((to, subject, body))


def test_registration():
    repo = FakeUserRepository()
    emailer = FakeEmailSender()
    service = UserService(repo, emailer)

    user = service.register("Alice", "alice@test.com")

    assert user["name"] == "Alice"
    assert repo.find_by_email("alice@test.com") is not None
    assert len(emailer.sent) == 1
    assert emailer.sent[0][0] == "alice@test.com"

test_registration()
print("Test passed!")
```

---

## Visualizer

<iframe src="/static/visualizers/dip.html" style="width:100%;height:440px;border:none;border-radius:8px;" title="Dependency Inversion Principle Visualizer"></iframe>

---

## How It Connects

DIP relies on abstractions to decouple modules. Python's ABCs and Protocols are the mechanisms for defining these abstractions.

[[abstraction|Abstraction]]

[[protocols|Protocols]]

[[abstract-base-classes|Abstract Base Classes]]

The Dependency Injection pattern is the practical implementation of DIP. DIP is the principle; DI is the technique for applying it.

[[dependency-injection-pattern|Dependency Injection Pattern]]

DIP is the fifth SOLID principle and arguably the most architecturally significant. It determines the dependency direction between layers of your application.

[[solid-principles|SOLID Principles]]

FastAPI's dependency injection system is a real-world implementation of DIP in Python. Understanding DIP helps you use FastAPI's `Depends()` effectively.

[[dependency-injection|Dependency Injection]]

---

## Common Misconceptions

Misconception 1: "DIP means using dependency injection frameworks."
Reality: DIP is a design principle about dependency direction. Dependency injection is a technique for implementing it. You can follow DIP by simply passing dependencies through constructors - no framework needed. In Python, constructor injection is usually sufficient. DI containers (like `dependency-injector`) are useful in large applications but are not required by DIP.

Misconception 2: "DIP means every function call should go through an abstraction."
Reality: DIP applies at **architectural boundaries** - where business logic meets infrastructure (databases, APIs, file systems, external services). Calling `len(my_list)` or `json.dumps(data)` directly is fine. Adding abstractions for standard library calls creates pointless indirection. Apply DIP where you need swappability, testability, or protection from external change.

Misconception 3: "The abstraction should be defined in a shared or infrastructure package."
Reality: The abstraction should be owned by the high-level module that uses it. If `UserService` needs a repository, the `Repository` Protocol is defined in the business logic package. The database package imports and implements it. This ensures the dependency direction flows from infrastructure toward business logic, not the reverse.

---

## Why It Matters in Practice

DIP is the difference between tests that run in 50 milliseconds and tests that require a database, an SMTP server, and a payment gateway. When your business logic depends on abstractions, you inject fakes in tests and real implementations in production. Without DIP, testing the `register_user` function requires a real database connection, making tests slow, flaky, and dependent on external infrastructure.

DIP also protects against vendor lock-in. When your payment logic depends on a `PaymentProcessor` Protocol rather than directly on the Stripe SDK, switching to a different payment provider means writing a new adapter. The business logic, the tests, and every caller of `PaymentProcessor` remain unchanged. Without DIP, switching providers requires modifying every file that imports the Stripe SDK.

---

## Interview Angle

Common question forms:
- "What is the Dependency Inversion Principle?"
- "What is the difference between DIP and dependency injection?"
- "How does DIP improve testability?"
- "Show me how you would decouple business logic from a database."

Answer frame:
State the two rules: high-level depends on abstractions, not low-level; abstractions do not depend on details. Show a concrete example with business logic, a Protocol, and two implementations (production + test). Explain that the abstraction is owned by the business layer. Distinguish DIP (principle about direction) from DI (technique for passing implementations). Connect to testability and vendor independence.

---

## Related Notes

- [[abstraction|Abstraction]]
- [[protocols|Protocols]]
- [[abstract-base-classes|Abstract Base Classes]]
- [[dependency-injection-pattern|Dependency Injection Pattern]]
- [[solid-principles|SOLID Principles]]
- [[dependency-injection|Dependency Injection]]
- [[composition-over-inheritance|Composition Over Inheritance]]
