---
title: 06 - Composition Over Inheritance
description: Composition builds complex objects by combining simpler ones through has-a relationships rather than is-a inheritance, producing more flexible, testable, and maintainable designs.
tags: [oop, composition, inheritance, has-a, delegation, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Composition Over Inheritance

> Composition builds complex behavior by combining objects rather than extending classes, favoring has-a relationships over is-a hierarchies for greater flexibility and reduced coupling.

---

## Quick Reference

**Core idea:**
- **Inheritance** models "is-a": a `Dog` is an `Animal`. **Composition** models "has-a": a `Car` has an `Engine`
- Composition means a class holds references to other objects and delegates behavior to them rather than inheriting it
- Composed objects can be swapped at runtime - an `EmailNotifier` can be replaced with an `SMSNotifier` without changing the class that uses it
- Inheritance locks you into a fixed hierarchy at class definition time - you cannot swap a parent class at runtime
- The Gang of Four (GoF) principle: "Favor object composition over class inheritance"

**Tricky points:**
- Composition requires explicit delegation - you must forward method calls to the composed objects, which adds boilerplate compared to inheritance where methods are inherited automatically
- Python's mixins blur the line - a mixin is inheritance used to compose behavior, which is a pragmatic middle ground
- Inheritance is still the right choice when there is a genuine is-a relationship and you need substitutability (Liskov Substitution Principle)
- Overusing composition can fragment behavior across many small objects, making the system harder to follow than a simple inheritance hierarchy

---

## What It Is

Think of building with LEGO bricks versus carving from a single block of wood. When you carve from wood, you start with a fixed shape and remove material - once you carve a chair, you cannot easily turn it into a table. The structure is rigid and committed. When you build with LEGO, you snap together independent pieces. You can pull off the armrests to make a bench, swap the legs for wheels to make a cart, or add a back to make a throne. Each piece is independent and reusable. Composition is building with LEGO. Inheritance is carving from wood.

In software, inheritance creates a rigid hierarchy. A `FileLogger` that inherits from `Logger` which inherits from `OutputHandler` is locked into that chain. If you want a logger that writes to both a file and a database, you cannot easily inherit from both `FileLogger` and `DatabaseLogger` without running into multiple inheritance complexity. With composition, you design a `Logger` that holds a list of `OutputHandler` objects. You pass in a `FileHandler`, a `DatabaseHandler`, or both. You can add, remove, or replace handlers at runtime. The `Logger` delegates the actual writing to whatever handlers it has, without knowing or caring about their specific types.

The Gang of Four design patterns book - the foundational text on software design patterns - states this principle explicitly: "Favor object composition over class inheritance." Their reasoning is that inheritance breaks encapsulation (the child class depends on the parent's implementation details), creates tight coupling (changing the parent affects all children), and makes it hard to change behavior at runtime (the class hierarchy is fixed at definition time). Composition avoids all three problems.

Python developers encounter this choice constantly. Should your `APIClient` inherit from `requests.Session`, or should it hold a session as an attribute? Should your `CSVExporter` inherit from `Exporter`, or should `DataPipeline` hold an `exporter` attribute that can be any object with an `export()` method? The answer is almost always composition unless there is a genuine type relationship that requires substitutability.

---

## How It Actually Works

Composition in Python is straightforward: one object stores a reference to another object as an attribute and calls methods on it. There is no special syntax or mechanism - it is just attribute assignment and method calls. The "composed" object has no knowledge that it is being used inside another object. This loose coupling is the key advantage.

Delegation is the pattern that makes composition work. Instead of inheriting a method, the outer object defines a method that calls the inner object's method. Python's `__getattr__` can automate delegation: if an attribute is not found on the outer object, `__getattr__` can forward the lookup to the inner object. This gives you inheritance-like convenience with composition's flexibility, though it sacrifices explicitness.

```python
from abc import ABC, abstractmethod
from typing import Protocol


# BAD: Inheritance hierarchy that becomes rigid
class InheritanceAnimal:
    def __init__(self, name: str):
        self.name = name

    def eat(self) -> str:
        return f"{self.name} eats"

class InheritanceFlyingAnimal(InheritanceAnimal):
    def fly(self) -> str:
        return f"{self.name} flies"

class InheritanceSwimmingAnimal(InheritanceAnimal):
    def swim(self) -> str:
        return f"{self.name} swims"

# Problem: a duck can both fly AND swim.
# Multiple inheritance? InheritanceFlyingSwimmingAnimal?
# What about a penguin that swims but does not fly?
# The hierarchy breaks down.


# GOOD: Composition - behaviors are independent, pluggable objects
class FlyBehavior(Protocol):
    def fly(self) -> str: ...

class SwimBehavior(Protocol):
    def swim(self) -> str: ...


class Wings:
    def fly(self) -> str:
        return "soars through the sky"

class NoFlight:
    def fly(self) -> str:
        return "cannot fly"

class Fins:
    def swim(self) -> str:
        return "glides through water"

class NoSwimming:
    def swim(self) -> str:
        return "cannot swim"


class Animal:
    def __init__(
        self,
        name: str,
        fly_behavior: FlyBehavior,
        swim_behavior: SwimBehavior,
    ):
        self.name = name
        self.fly_behavior = fly_behavior    # has-a relationship
        self.swim_behavior = swim_behavior  # has-a relationship

    def fly(self) -> str:
        return f"{self.name} {self.fly_behavior.fly()}"

    def swim(self) -> str:
        return f"{self.name} {self.swim_behavior.swim()}"


# Any combination of behaviors, no inheritance hierarchy needed
duck = Animal("Duck", Wings(), Fins())
penguin = Animal("Penguin", NoFlight(), Fins())
eagle = Animal("Eagle", Wings(), NoSwimming())

print(duck.fly())      # Duck soars through the sky
print(duck.swim())     # Duck glides through water
print(penguin.fly())   # Penguin cannot fly
print(penguin.swim())  # Penguin glides through water

# Behaviors can be swapped at runtime
penguin.fly_behavior = Wings()  # penguin learned to fly
print(penguin.fly())            # Penguin soars through the sky


# Real-world example: pluggable notification system
class NotificationSender(Protocol):
    def send(self, to: str, message: str) -> None: ...


class EmailSender:
    def __init__(self, smtp_host: str):
        self.smtp_host = smtp_host

    def send(self, to: str, message: str) -> None:
        print(f"Email to {to} via {self.smtp_host}: {message}")


class SMSSender:
    def __init__(self, api_key: str):
        self.api_key = api_key

    def send(self, to: str, message: str) -> None:
        print(f"SMS to {to}: {message}")


class SlackSender:
    def __init__(self, webhook_url: str):
        self.webhook_url = webhook_url

    def send(self, to: str, message: str) -> None:
        print(f"Slack to #{to}: {message}")


class AlertService:
    """Composes multiple notification channels.
    
    Adding a new channel (push notifications, Discord, etc.)
    requires zero changes to this class.
    """
    def __init__(self, senders: list[NotificationSender]):
        self._senders = senders

    def alert(self, to: str, message: str) -> None:
        for sender in self._senders:
            sender.send(to, message)

    def add_sender(self, sender: NotificationSender) -> None:
        self._senders.append(sender)


# Production: email + Slack
service = AlertService([
    EmailSender("smtp.company.com"),
    SlackSender("https://hooks.slack.com/..."),
])
service.alert("ops-team", "Server CPU at 95%")

# Tests: no real email/SMS needed
class FakeSender:
    def __init__(self):
        self.sent: list[tuple[str, str]] = []

    def send(self, to: str, message: str) -> None:
        self.sent.append((to, message))

fake = FakeSender()
test_service = AlertService([fake])
test_service.alert("test", "hi")
assert fake.sent == [("test", "hi")]
```

---

## How It Connects

Composition is the foundation of most design patterns. The Strategy pattern composes a behavior object. The Observer pattern composes a list of listeners. The Decorator pattern composes a wrapped object. Understanding composition is prerequisite to understanding these patterns.

[[strategy-pattern|Strategy Pattern]]

[[observer-pattern|Observer Pattern]]

[[decorator-pattern|Decorator Pattern]]

The Dependency Inversion Principle says high-level modules should depend on abstractions. Composition is how you implement this: the high-level module holds a reference to an abstraction (a Protocol or ABC), and the concrete implementation is injected at construction time.

[[dip|Dependency Inversion Principle]]

[[dependency-injection-pattern|Dependency Injection Pattern]]

Inheritance is not wrong - it is appropriate when there is a genuine is-a relationship and you need the Liskov Substitution Principle to hold. The choice between inheritance and composition depends on whether the relationship is truly "is-a" or "has-a."

[[inheritance-oop|Inheritance]]

[[lsp|Liskov Substitution Principle]]

---

## Common Misconceptions

Misconception 1: "Composition over inheritance means never use inheritance."
Reality: The principle says to prefer composition, not to forbid inheritance. Inheritance is the right tool when there is a genuine is-a relationship: a `PostgresRepository` is a `Repository`, a `ValueError` is an `Exception`. The problem is when inheritance is used for code reuse in the absence of a type relationship. If you are inheriting just to get some methods for free, composition is almost always better.

Misconception 2: "Composition requires more code, so it is worse."
Reality: Composition requires explicit delegation, which adds a few lines of boilerplate. But inheritance creates implicit coupling - changing a parent class can break children in ways that are hard to predict and debug. The extra lines of delegation are a small price for the ability to swap implementations, test in isolation, and change behavior at runtime. The maintenance cost over the lifecycle of the codebase favors composition.

Misconception 3: "Python mixins are the same as composition."
Reality: Mixins use inheritance (they appear in the class's MRO), but they are designed to be composed like independent behaviors. A mixin like `LoggableMixin` adds logging methods to any class that inherits from it. This is a pragmatic middle ground - Pythonic and widely used - but it still creates coupling through the MRO. True composition holds independent objects as attributes and delegates to them, which allows runtime swapping and avoids MRO complications.

---

## Why It Matters in Practice

Most real-world systems evolve over time. Today your application sends email notifications. Next month the product manager wants Slack notifications. Next quarter, push notifications. With inheritance, each new notification type requires a new subclass and potentially restructuring the hierarchy. With composition, you write a new `PushNotificationSender` class that implements the `send()` method and plug it into the existing `AlertService`. Zero changes to existing code.

Testability is the other major benefit. When your `OrderService` composes a `PaymentGateway` and a `InventoryChecker`, you can pass fake versions of both in tests. With inheritance, the `OrderService` inherits database access behavior directly, and testing requires a real database or complex mocking of internal methods.

---

## Interview Angle

Common question forms:
- "What does 'composition over inheritance' mean?"
- "When would you use inheritance vs composition?"
- "Can you refactor this inheritance hierarchy to use composition?"
- "How does composition improve testability?"

Answer frame:
Define composition as has-a vs inheritance as is-a. Explain that composition enables runtime flexibility, independent testing, and adherence to the Open/Closed Principle. Give the notification sender example. Acknowledge that inheritance is correct for genuine type relationships (exceptions, ABCs). Mention that the Gang of Four and SOLID principles both favor composition for most design decisions.

---

## Related Notes

- [[strategy-pattern|Strategy Pattern]]
- [[observer-pattern|Observer Pattern]]
- [[decorator-pattern|Decorator Pattern]]
- [[dip|Dependency Inversion Principle]]
- [[dependency-injection-pattern|Dependency Injection Pattern]]
- [[inheritance-oop|Inheritance]]
- [[lsp|Liskov Substitution Principle]]
- [[oop-basics|OOP Basics]]
