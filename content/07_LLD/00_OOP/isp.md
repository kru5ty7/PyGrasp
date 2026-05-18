---
title: 11 - Interface Segregation Principle
description: Clients should not be forced to depend on methods they do not use - split large interfaces into smaller, focused ones so that each client only knows about the methods it actually calls.
tags: [oop, solid, isp, interfaces, protocols, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Interface Segregation Principle

> No client should be forced to depend on methods it does not use - prefer many small, specific interfaces over one large, general-purpose interface.

---

## Quick Reference

**Core idea:**
- ISP says to split fat interfaces into smaller, role-specific ones so that each client depends only on what it needs
- In Python, **Protocols** naturally enforce ISP - a function that calls `obj.read()` only depends on the `read()` method, not on everything else the object can do
- Duck typing gives Python implicit ISP - you never depend on methods you do not call
- ABCs that grow too large (too many abstract methods) force implementers to write stubs for methods they do not need
- ISP reduces the impact of interface changes: modifying one small interface does not force unrelated clients to change

**Tricky points:**
- Python's duck typing means ISP violations are less common than in Java, but they still occur with large ABCs and Pydantic models
- A Protocol with too many methods is an ISP violation even in Python - the benefit of Protocols is that they can be small
- ISP does not mean every method needs its own interface - group methods by which clients use them together
- Response models that return fifty fields when the client needs three are an API-level ISP violation

---

## What It Is

Think of a restaurant's ordering system. The waiter needs to see the menu items and place orders. The chef needs to see order details and mark them as complete. The manager needs to see sales reports and adjust prices. A system that forces all three roles to use the same interface - with every button and screen visible to everyone - is cluttered and confusing. The waiter does not need the price adjustment screen. The chef does not need sales reports. A well-designed system gives each role an interface tailored to their needs: the waiter sees only order-related screens, the chef sees only kitchen-related screens, and the manager sees only management screens.

Interface Segregation Principle applies this idea to code. When a class or module exposes a large interface with many methods, not every client needs all of them. A `FileManager` interface with `read()`, `write()`, `delete()`, `set_permissions()`, `compress()`, and `encrypt()` forces a logging service that only needs `write()` to depend on a class that also handles encryption and permissions. If the encryption interface changes, the logging service's dependency is affected even though it never uses encryption.

ISP says to split the interface. Create a `Writable` protocol with just `write()`. Create a `Readable` protocol with just `read()`. Create a `Deletable` protocol with `delete()`. Each client depends only on the protocol it uses. The concrete `FileManager` class can implement all of them, but clients reference only the small protocols they need.

In Python, duck typing provides implicit ISP. A function that calls `obj.write(data)` does not care what else `obj` can do. It depends on exactly one method. Protocols formalize this implicit contract for type checkers. The danger zone in Python is large ABCs: if you define an ABC with fifteen abstract methods, every concrete implementation must implement all fifteen, even if most callers only use two or three. That is an ISP violation.

---

## How It Actually Works

ISP violations in Python typically appear as ABC bloat or "fat" base classes. When a base class defines many abstract methods and concrete classes implement half of them as `raise NotImplementedError` or `pass`, that is a sign that the interface is too broad. Each group of methods that gets implemented together (or stubbed out together) is a candidate for its own protocol or ABC.

The solution is to define small, focused Protocols that represent the capabilities a client actually uses. A client that reads data depends on `Readable`. A client that writes data depends on `Writable`. A client that manages lifecycle depends on `Closeable`. The concrete class implements all three, but no client depends on more than it needs.

```python
from typing import Protocol


# ISP VIOLATION: one fat interface forces all implementers to handle everything
class BadWorker(Protocol):
    def code(self) -> str: ...
    def test(self) -> str: ...
    def design(self) -> str: ...
    def manage(self) -> str: ...
    def deploy(self) -> str: ...

# A junior developer must implement manage() and design()
# even though they do not do those things.
# A designer must implement code(), test(), deploy()
# even though they do not do those things.


# ISP-COMPLIANT: small, role-specific interfaces
class Coder(Protocol):
    def code(self) -> str: ...

class Tester(Protocol):
    def test(self) -> str: ...

class Designer(Protocol):
    def design(self) -> str: ...

class Manager(Protocol):
    def manage(self) -> str: ...

class Deployer(Protocol):
    def deploy(self) -> str: ...


# Concrete classes implement only what they actually do
class Developer:
    def code(self) -> str:
        return "Writing Python code"

    def test(self) -> str:
        return "Running pytest"

    def deploy(self) -> str:
        return "Deploying to production"


class UXDesigner:
    def design(self) -> str:
        return "Creating wireframes"


class TechLead:
    def code(self) -> str:
        return "Reviewing PRs"

    def manage(self) -> str:
        return "Running sprint planning"

    def deploy(self) -> str:
        return "Approving releases"


# Each function depends only on the capability it needs
def run_code_review(coder: Coder) -> None:
    print(coder.code())

def run_test_suite(tester: Tester) -> None:
    print(tester.test())

def run_deployment(deployer: Deployer) -> None:
    print(deployer.deploy())

# Developer satisfies Coder, Tester, and Deployer
dev = Developer()
run_code_review(dev)  # works - Developer has code()
run_test_suite(dev)   # works - Developer has test()
run_deployment(dev)   # works - Developer has deploy()

# UXDesigner only satisfies Designer
ux = UXDesigner()
# run_code_review(ux)  # type error - UXDesigner has no code()


# Real-world example: data access layer
class Readable(Protocol):
    def get(self, id: str) -> dict | None: ...
    def list_all(self) -> list[dict]: ...

class Writable(Protocol):
    def save(self, entity: dict) -> None: ...

class Deletable(Protocol):
    def delete(self, id: str) -> bool: ...


class PostgresRepository:
    """Implements all three interfaces, but each client sees only what it needs."""

    def get(self, id: str) -> dict | None:
        return {"id": id, "source": "postgres"}

    def list_all(self) -> list[dict]:
        return [{"id": "1"}, {"id": "2"}]

    def save(self, entity: dict) -> None:
        print(f"Saved {entity}")

    def delete(self, id: str) -> bool:
        print(f"Deleted {id}")
        return True


# Read-only service only depends on Readable
class ReportGenerator:
    def __init__(self, source: Readable):
        self._source = source

    def generate(self) -> str:
        items = self._source.list_all()
        return f"Report: {len(items)} items"


# Admin service depends on all three
class AdminService:
    def __init__(self, repo_r: Readable, repo_w: Writable, repo_d: Deletable):
        self._reader = repo_r
        self._writer = repo_w
        self._deleter = repo_d


# Same object, different views
repo = PostgresRepository()
report = ReportGenerator(repo)         # sees only Readable methods
admin = AdminService(repo, repo, repo) # sees all methods
```

---

## How It Connects

Python's Protocol system is the primary tool for implementing ISP. Small Protocols let you express exactly which capabilities a client depends on.

[[protocols|Protocols]]

ISP is closely related to SRP: a class that violates SRP (too many responsibilities) often exposes a fat interface that violates ISP. Splitting responsibilities also splits the interface.

[[srp|Single Responsibility Principle]]

ISP is one of five SOLID principles. It interacts with DIP: when you invert dependencies, the abstractions you depend on should be small and focused (ISP), not broad and monolithic.

[[solid-principles|SOLID Principles]]

[[dip|Dependency Inversion Principle]]

---

## Common Misconceptions

Misconception 1: "ISP means every method should be in its own interface."
Reality: ISP says to group methods by client usage. If every client that calls `read()` also calls `seek()`, then `read()` and `seek()` belong in the same interface. The test is: are there clients that need one without the other? If yes, separate them. If no, keep them together.

Misconception 2: "Python's duck typing makes ISP irrelevant."
Reality: Duck typing provides implicit ISP at the call site, but explicit ISP (via Protocols) provides type safety, documentation, and IDE support. More importantly, ISP violations in ABCs and Pydantic models cause real problems in Python: implementers write dead-code stubs, and API responses carry fields that clients ignore but still parse and transmit.

Misconception 3: "ISP is only about classes and interfaces."
Reality: ISP applies at every level. An API endpoint that returns user profile data, purchase history, notification preferences, and admin flags when the client only needs the user's name is an API-level ISP violation. A configuration object that requires thirty fields when a component uses three is a configuration-level ISP violation.

---

## Why It Matters in Practice

ISP violations create unnecessary coupling. When a `ReportGenerator` depends on a `FullRepository` interface with `save()`, `delete()`, and `get()`, a change to the `delete()` signature forces recompilation and retesting of the `ReportGenerator` even though it never calls `delete()`. With ISP-compliant Protocols, the `ReportGenerator` depends only on `Readable`, and changes to `Deletable` are invisible to it.

ISP also improves testability. Mocking a small `Readable` protocol requires implementing two methods. Mocking a fat `FullRepository` ABC requires implementing ten methods, most of which are irrelevant to the test.

---

## Interview Angle

Common question forms:
- "What is the Interface Segregation Principle?"
- "How would you refactor this large interface to follow ISP?"
- "How does ISP relate to Python's duck typing?"

Answer frame:
Define ISP as no client should depend on methods it does not use. Show a fat interface and refactor into small Protocols. Explain that Python's duck typing provides implicit ISP but explicit Protocols add type safety. Connect to SRP (splitting responsibilities splits interfaces) and DIP (depend on small abstractions). Mention the real-world analogy of API responses with too many fields.

---

## Related Notes

- [[protocols|Protocols]]
- [[srp|Single Responsibility Principle]]
- [[solid-principles|SOLID Principles]]
- [[dip|Dependency Inversion Principle]]
- [[abstraction|Abstraction]]
- [[oop-basics|OOP Basics]]
