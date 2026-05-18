---
title: 15 - Dependency Injection Pattern
description: Dependency Injection provides objects with their dependencies from the outside rather than having them create or look up dependencies internally, enabling loose coupling and testability.
tags: [design-patterns, dependency-injection, di, ioc, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Dependency Injection Pattern

> Dependency Injection passes dependencies to an object from the outside rather than having the object create or locate them internally, decoupling components and enabling easy substitution for testing.

---

## Quick Reference

**Core idea:**
- Dependencies are **injected** (passed in) rather than **created internally** or **looked up globally**
- Three forms: **constructor injection** (most common), **method injection** (per-call), **property injection** (after construction)
- DI is the technique that implements the Dependency Inversion Principle (DIP)
- In Python, constructor injection with type hints is the standard approach - no framework required
- FastAPI's `Depends()` is a popular DI mechanism in the Python ecosystem

**Tricky points:**
- DI without a framework means the composition root (entry point) becomes a wiring factory - this is normal and expected
- Over-injecting creates constructors with too many parameters - a sign that the class has too many responsibilities (SRP violation)
- DI frameworks (dependency-injector, injector) add automatic wiring but also add learning curve and magic
- DI is not needed for everything - standard library imports (`json`, `os`, `math`) do not need injection

---

## What It Is

Think of a restaurant where chefs cook meals. In a tightly coupled kitchen, each chef grows their own vegetables, raises their own livestock, and mills their own flour. Changing a tomato supplier means retraining the chef. In a dependency-injected kitchen, ingredients are delivered to the chef. The chef focuses on cooking. Changing a tomato supplier means changing the delivery, not the chef. The chef depends on "tomatoes," not on "Farm ABC's tomatoes."

Dependency Injection applies this to code. Instead of a `UserService` creating its own `PostgresRepository` internally (`self._repo = PostgresRepository("localhost")`), the repository is passed in through the constructor (`def __init__(self, repo: UserRepository)`). The `UserService` does not know or care whether it received a Postgres, MongoDB, or in-memory repository. It just calls `self._repo.get(user_id)`.

The three forms of DI differ in when the dependency is provided. Constructor injection passes dependencies when the object is created - it is the most common and ensures the object is always fully configured. Method injection passes dependencies per method call - useful when the dependency varies between calls. Property injection sets dependencies after construction - useful for optional dependencies but risks using the object before its dependencies are set.

In Python, constructor injection is simple and explicit. You add the dependency as a constructor parameter with a type hint. No framework is required. The "composition root" - typically your `main()` function or FastAPI's dependency system - creates the concrete implementations and wires them together.

---

## How It Actually Works

Without DI, a class creates its own dependencies. With DI, the class receives its dependencies. The composition root (application entry point) is the only place that knows about concrete implementations. Everything else depends on abstractions.

FastAPI's `Depends()` function is a built-in DI mechanism. You define a dependency function, and FastAPI calls it automatically when handling a request. The dependency function can itself have dependencies, forming a dependency tree that FastAPI resolves automatically.

```python
from typing import Protocol
from dataclasses import dataclass


# Abstractions
class UserRepository(Protocol):
    def get(self, user_id: str) -> dict | None: ...
    def save(self, user: dict) -> None: ...

class EmailSender(Protocol):
    def send(self, to: str, subject: str, body: str) -> None: ...

class Logger(Protocol):
    def info(self, message: str) -> None: ...
    def error(self, message: str) -> None: ...


# WITHOUT DI: tight coupling
class BadUserService:
    def __init__(self):
        # Creates its own dependencies - cannot be tested without DB
        from some_db_module import PostgresRepo
        from some_email_module import SMTPSender
        self._repo = PostgresRepo("postgresql://localhost/db")
        self._emailer = SMTPSender("smtp.gmail.com")

    def register(self, name: str, email: str) -> dict:
        user = {"name": name, "email": email}
        self._repo.save(user)  # requires real database
        self._emailer.send(email, "Welcome!", f"Hi {name}")  # sends real email
        return user


# WITH DI: constructor injection
class UserService:
    def __init__(self, repo: UserRepository, emailer: EmailSender, logger: Logger):
        self._repo = repo       # injected
        self._emailer = emailer  # injected
        self._logger = logger    # injected

    def register(self, name: str, email: str) -> dict:
        self._logger.info(f"Registering user: {email}")
        user = {"name": name, "email": email}
        self._repo.save(user)
        self._emailer.send(email, "Welcome!", f"Hi {name}")
        self._logger.info(f"User registered: {email}")
        return user


# Concrete implementations
class PostgresRepository:
    def __init__(self, conn_str: str):
        self._conn = conn_str

    def get(self, user_id: str) -> dict | None:
        return {"id": user_id, "name": "DB User"}

    def save(self, user: dict) -> None:
        print(f"[Postgres] Saved: {user}")


class SMTPEmailSender:
    def __init__(self, host: str):
        self._host = host

    def send(self, to: str, subject: str, body: str) -> None:
        print(f"[SMTP:{self._host}] To: {to}, Subject: {subject}")


class ConsoleLogger:
    def info(self, message: str) -> None:
        print(f"[INFO] {message}")

    def error(self, message: str) -> None:
        print(f"[ERROR] {message}")


# COMPOSITION ROOT: the one place that knows about concrete classes
def create_production_service() -> UserService:
    repo = PostgresRepository("postgresql://prod-db:5432/users")
    emailer = SMTPEmailSender("smtp.company.com")
    logger = ConsoleLogger()
    return UserService(repo, emailer, logger)


# TESTING: inject fakes
class FakeRepository:
    def __init__(self):
        self._data: dict[str, dict] = {}

    def get(self, user_id: str) -> dict | None:
        return self._data.get(user_id)

    def save(self, user: dict) -> None:
        self._data[user.get("email", "unknown")] = user


class FakeEmailSender:
    def __init__(self):
        self.sent: list[tuple] = []

    def send(self, to: str, subject: str, body: str) -> None:
        self.sent.append((to, subject, body))


class NullLogger:
    def info(self, message: str) -> None: pass
    def error(self, message: str) -> None: pass


def test_register():
    repo = FakeRepository()
    emailer = FakeEmailSender()
    service = UserService(repo, emailer, NullLogger())

    service.register("Alice", "alice@test.com")

    assert repo.get("alice@test.com") is not None
    assert len(emailer.sent) == 1
    assert emailer.sent[0][0] == "alice@test.com"
    print("Test passed!")

test_register()


# FastAPI-style DI
"""
from fastapi import FastAPI, Depends

app = FastAPI()

def get_repo() -> UserRepository:
    return PostgresRepository("postgresql://localhost/db")

def get_emailer() -> EmailSender:
    return SMTPEmailSender("smtp.company.com")

def get_service(
    repo: UserRepository = Depends(get_repo),
    emailer: EmailSender = Depends(get_emailer),
) -> UserService:
    return UserService(repo, emailer, ConsoleLogger())

@app.post("/users")
def create_user(name: str, email: str, service: UserService = Depends(get_service)):
    return service.register(name, email)
"""
```

---

## How It Connects

DI is the practical technique for implementing the Dependency Inversion Principle. DIP is the design rule; DI is how you apply it in code.

[[dip|Dependency Inversion Principle]]

[[solid-principles|SOLID Principles]]

The Repository pattern is one of the most common dependencies to inject. Understanding how repositories are injected helps you design testable data access layers.

[[repository-pattern|Repository Pattern]]

FastAPI's `Depends()` system is a production-grade DI mechanism that Python developers use daily. Understanding DI helps you use FastAPI's dependency system effectively.

[[dependency-injection|Dependency Injection]]

If a class's constructor takes too many injected dependencies, it is likely violating SRP. DI makes SRP violations visible through constructor parameter count.

[[srp|Single Responsibility Principle]]

---

## Common Misconceptions

Misconception 1: "You need a DI framework to do dependency injection."
Reality: In Python, constructor injection is just passing arguments. `service = UserService(repo, emailer, logger)` is dependency injection. No framework needed. Frameworks add automatic wiring and lifecycle management, which is useful in large applications but unnecessary for most Python projects.

Misconception 2: "DI means injecting everything, including standard library modules."
Reality: Inject dependencies at architectural boundaries - where your code meets databases, external APIs, file systems, and other infrastructure. Injecting `json`, `os.path`, or `math` adds complexity without benefit. Those are stable, well-tested modules that do not need substitution.

Misconception 3: "DI makes code more complex."
Reality: DI makes dependency relationships explicit. Without DI, dependencies are hidden inside the class (it imports and creates them internally). With DI, dependencies are visible in the constructor signature. The class itself becomes simpler; the composition root absorbs the wiring complexity. The total complexity is the same, but it is organized better.

---

## Why It Matters in Practice

DI is the single most impactful technique for testability. Without DI, testing a service requires mocking internal imports, patching global state, or setting up real infrastructure. With DI, you pass fakes through the constructor. Tests are fast, deterministic, and easy to write.

DI also enables parallel development. If the `UserRepository` interface is defined, one developer can build the service while another builds the Postgres implementation. They agree on the interface and work independently.

---

## Interview Angle

Common question forms:
- "What is dependency injection?"
- "What is the difference between DI and DIP?"
- "How does DI improve testability?"
- "Implement DI without a framework."

Answer frame:
Define DI as passing dependencies from outside. Show constructor injection with Protocol-typed parameters. Demonstrate testing with fakes. Distinguish DI (technique) from DIP (principle). Mention FastAPI's `Depends()` as a real-world example. Note that Python's simplicity means you rarely need a DI framework.

---

## Related Notes

- [[dip|Dependency Inversion Principle]]
- [[solid-principles|SOLID Principles]]
- [[repository-pattern|Repository Pattern]]
- [[dependency-injection|Dependency Injection]]
- [[srp|Single Responsibility Principle]]
- [[design-patterns-overview|Design Patterns Overview]]
