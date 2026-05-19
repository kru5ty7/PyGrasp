---
title: 03 - Abstraction
description: Abstraction separates what an object does from how it does it, defining interfaces that callers depend on while hiding implementation details that can change independently.
tags: [oop, abstraction, abc, protocol, interface, layer-7, lld]
status: draft
difficulty: beginner
layer: 7
domain: lld
created: 2026-05-18
---

# Abstraction

> Abstraction defines what an object can do without exposing how it does it, letting callers depend on stable interfaces while implementations vary freely.

---

## Quick Reference

**Core idea:**
- Abstraction separates interface (what operations are available) from implementation (how those operations work)
- In Python, abstraction is achieved through **Abstract Base Classes** (ABCs using `abc` module), **Protocols** (structural typing from `typing`), and **duck typing** (convention-based interfaces)
- An ABC forces subclasses to implement specific methods - failing to do so raises `TypeError` at instantiation time, not at call time
- A Protocol defines a structural interface - any class that has the right methods satisfies the protocol without explicitly inheriting from it
- The caller codes against the abstraction, not the implementation - this makes code pluggable, testable, and resilient to change

**Tricky points:**
- ABCs enforce at instantiation time, not at class definition time - you only get the error when you try to create an instance of a class that forgot to implement an abstract method
- Protocols are checked statically by type checkers (mypy, pyright) but are not enforced at runtime unless you use `runtime_checkable`
- Duck typing is Python's original abstraction mechanism - "if it quacks like a duck" - but it provides no static safety and errors only surface when the missing method is actually called
- Overusing abstraction creates indirection without value - if you have only one implementation, the abstraction layer is premature complexity

---

## What It Is

Think of a power outlet on your wall. You plug in a lamp, a phone charger, or a blender - they all work because they all follow the same interface: two or three prongs, a specific voltage, a specific frequency. You never think about the power plant behind the outlet - whether it is coal, solar, or nuclear. The outlet is the abstraction. It defines what you can do (get electricity) without exposing how the electricity is generated. If the power company switches from coal to solar, your lamp still works because the interface (the outlet) did not change.

Abstraction in software works the same way. You define an interface - a set of methods that a class must provide - and then write your code against that interface. The code that uses a `PaymentProcessor` does not care whether the implementation talks to Stripe, PayPal, or a test stub. It calls `process_payment(amount)` and gets a result. The implementation can be swapped, replaced, or updated without changing the code that depends on it.

Python provides three mechanisms for abstraction, each with different tradeoffs. Duck typing is the most Pythonic and requires no special syntax: if an object has the methods you need, you use it, and you discover problems only at runtime. Abstract Base Classes (ABCs) add explicit contracts: you define a base class with `@abstractmethod` decorators, and Python raises `TypeError` if a subclass fails to implement them. Protocols, introduced in Python 3.8, bring structural typing: you define what methods and attributes a type must have, and type checkers verify compliance without requiring inheritance.

The art of abstraction is knowing when to use it. If you have a payment system that will only ever use Stripe, creating a `PaymentProcessor` ABC with a single `StripeProcessor` subclass adds complexity without benefit. If you have a notification system that might use email today but SMS and push notifications tomorrow, defining a `Notifier` abstraction lets you add implementations without changing the code that sends notifications.

---

## How It Actually Works

Abstract Base Classes use the `abc` module's `ABCMeta` metaclass (or the `ABC` base class, which uses it). When `ABCMeta` creates a class, it checks for any methods decorated with `@abstractmethod` and stores their names in the class's `__abstractmethods__` frozenset. When you try to instantiate a class, `type.__call__` checks whether `__abstractmethods__` is non-empty. If it is, instantiation fails with `TypeError`. This check happens at object creation time, not at class definition time, which means you can define a class that does not implement all abstract methods - you just cannot create instances of it.

Protocols work entirely differently. A `Protocol` class is a special class (from `typing`) that type checkers understand. When mypy sees a function parameter typed as `Protocol`, it checks whether the argument's class has all the methods defined in the protocol - structurally, without requiring inheritance. At runtime, `Protocol` does nothing special. If you add `@runtime_checkable`, Python implements `__instancecheck__` so that `isinstance()` works, but it only checks for method existence, not for method signatures.

```python
from abc import ABC, abstractmethod
from typing import Protocol, runtime_checkable


# Approach 1: Abstract Base Class (nominal typing)
class Repository(ABC):
    """Defines the contract for data access.
    
    Any concrete repository must implement all abstract methods.
    Failing to do so raises TypeError at instantiation.
    """

    @abstractmethod
    def get(self, id: str) -> dict:
        """Retrieve an entity by ID."""
        ...

    @abstractmethod
    def save(self, entity: dict) -> None:
        """Persist an entity."""
        ...

    @abstractmethod
    def delete(self, id: str) -> bool:
        """Delete an entity. Returns True if it existed."""
        ...


class PostgresRepository(Repository):
    def __init__(self, connection_string: str):
        self._conn_str = connection_string

    def get(self, id: str) -> dict:
        # Real implementation would query Postgres
        return {"id": id, "source": "postgres"}

    def save(self, entity: dict) -> None:
        print(f"Saving {entity['id']} to Postgres")

    def delete(self, id: str) -> bool:
        print(f"Deleting {id} from Postgres")
        return True


class InMemoryRepository(Repository):
    def __init__(self):
        self._store: dict[str, dict] = {}

    def get(self, id: str) -> dict:
        return self._store[id]

    def save(self, entity: dict) -> None:
        self._store[entity["id"]] = entity

    def delete(self, id: str) -> bool:
        return self._store.pop(id, None) is not None


# Approach 2: Protocol (structural typing)
@runtime_checkable
class Closeable(Protocol):
    def close(self) -> None: ...


def cleanup(resource: Closeable) -> None:
    """Works with ANY object that has a close() method.
    No inheritance required."""
    resource.close()


# This works - file objects have close()
import io
buf = io.StringIO()
cleanup(buf)  # works - StringIO has .close()

# This also works - custom class with close()
class DatabaseConnection:
    def close(self) -> None:
        print("Connection closed")

cleanup(DatabaseConnection())  # works - structurally compatible

print(isinstance(buf, Closeable))                # True (runtime_checkable)
print(isinstance(DatabaseConnection(), Closeable))  # True


# The service depends on the abstraction, not the implementation
class UserService:
    def __init__(self, repo: Repository):
        self._repo = repo  # could be Postgres, InMemory, Mongo, etc.

    def get_user(self, user_id: str) -> dict:
        return self._repo.get(user_id)

# In production
service = UserService(PostgresRepository("postgresql://..."))

# In tests - swap implementation without changing UserService
service = UserService(InMemoryRepository())
```

---

## Visualizer

<iframe src="/static/visualizers/abstraction.html" style="width:100%;height:460px;border:none;border-radius:8px;" title="Abstraction Visualizer"></iframe>

---

## How It Connects

Abstraction and encapsulation are complementary: encapsulation hides internal state, abstraction hides implementation details behind an interface. Together they ensure that code depends on contracts, not on the specific objects fulfilling those contracts.

[[encapsulation|Encapsulation]]

Abstract Base Classes in Python are the primary mechanism for enforcing abstraction. They use the `abc` module and metaclass machinery to prevent instantiation of incomplete implementations.

[[abstract-base-classes|Abstract Base Classes]]

Protocols provide structural typing, which is Python's type-safe version of duck typing. They let you define interfaces without inheritance hierarchies.

[[protocols|Protocols]]

The Dependency Inversion Principle (the D in SOLID) is the design rule that formalizes abstraction: high-level modules should depend on abstractions, not on concrete implementations.

[[dip|Dependency Inversion Principle]]

---

## Common Misconceptions

Misconception 1: "Abstraction means making things abstract and vague."
Reality: Abstraction means defining a precise contract - what operations exist, what inputs they accept, what outputs they produce - without specifying the implementation. A well-defined abstract interface is more precise than a concrete class, because it states exactly what callers can depend on and nothing more.

Misconception 2: "You always need an ABC or Protocol to create an abstraction."
Reality: Duck typing is Python's original abstraction mechanism. If your function accepts any object with a `read()` method, that is an abstraction - just an implicit one. ABCs and Protocols make the contract explicit and checkable, but they are not required. Use them when the interface is important enough to document formally and enforce.

Misconception 3: "Every class needs an abstract base class above it."
Reality: Creating an ABC for every class - especially when there is only one implementation - adds indirection without benefit. Abstraction should be introduced at boundaries: where implementations might change, where you need testability, or where multiple variants exist. A `UserService` with only one implementation does not need a `UserServiceInterface` ABC.

---

## Why It Matters in Practice

Abstraction is the key to testable code. When your `OrderService` depends on a `Repository` abstraction rather than directly on `PostgresRepository`, you can pass an `InMemoryRepository` in your test suite. Tests run in milliseconds without a database. This is not theoretical - it is the difference between a test suite that takes 30 seconds and one that takes 20 minutes, which determines whether developers actually run tests before committing.

Abstraction also enables parallel development. If you define the `PaymentProcessor` interface first, one developer can build the Stripe implementation while another builds the order processing logic that uses it. They agree on the interface and work independently. Without the abstraction, the second developer is blocked until the first one finishes.

---

## Interview Angle

Common question forms:
- "What is abstraction in OOP?"
- "What is the difference between abstraction and encapsulation?"
- "When would you use an ABC vs a Protocol?"
- "How does Python achieve abstraction without interfaces like Java?"

Answer frame:
Define abstraction as separating interface from implementation. Contrast with encapsulation (hides state vs hides implementation). Explain Python's three mechanisms: duck typing (implicit), ABCs (explicit nominal), Protocols (explicit structural). Give a concrete example of swapping implementations (repository pattern). Emphasize that abstraction enables testability and the Dependency Inversion Principle.

---

## Related Notes

- [[encapsulation|Encapsulation]]
- [[abstract-base-classes|Abstract Base Classes]]
- [[protocols|Protocols]]
- [[dip|Dependency Inversion Principle]]
- [[oop-basics|OOP Basics]]
- [[repository-pattern|Repository Pattern]]
