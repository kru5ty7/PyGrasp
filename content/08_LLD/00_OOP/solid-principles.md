---
title: 07 - SOLID Principles
description: SOLID is a set of five design principles that guide class-level design decisions, helping you build code that is easier to understand, extend, and maintain as requirements change.
tags: [oop, solid, srp, ocp, lsp, isp, dip, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# SOLID Principles

> SOLID is five design principles - Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, and Dependency Inversion - that guide you toward code that is easy to change without breaking.

---

## Quick Reference

**Core idea:**
- **S** - Single Responsibility: a class should have one reason to change
- **O** - Open/Closed: a class should be open for extension but closed for modification
- **L** - Liskov Substitution: a subclass must be usable wherever its parent is expected without breaking behavior
- **I** - Interface Segregation: clients should not depend on methods they do not use
- **D** - Dependency Inversion: high-level modules should depend on abstractions, not on concrete implementations
- SOLID principles work together - violating one often forces you to violate others

**Tricky points:**
- SOLID is about managing change - the principles are most valuable in code that will evolve over time; throwaway scripts do not benefit
- Over-applying SOLID creates over-engineered code with too many tiny classes and indirection layers
- Python's duck typing and Protocols make ISP and DIP more natural than in Java, where explicit interfaces are required
- SOLID does not mean "write more classes" - sometimes a function is the right abstraction
- The principles are guidelines, not laws - knowing when to break them matters as much as knowing them

---

## What It Is

Think of a well-organized workshop. Each tool has one purpose (a hammer drives nails, a saw cuts wood - Single Responsibility). When you need a new capability, you buy a new attachment rather than modifying an existing tool (Open/Closed). Any Phillips-head screwdriver works in any Phillips-head screw - you do not need the exact same brand (Liskov Substitution). You do not force an electrician to carry plumbing tools (Interface Segregation). The work order says "fasten these boards" without specifying which screws or tools to use - the carpenter decides (Dependency Inversion).

Robert C. Martin introduced the SOLID acronym to capture five principles that address the most common causes of rigid, fragile, and hard-to-change code. Each principle tackles a specific type of coupling or rigidity. Together, they guide you toward a codebase where adding features means writing new code rather than modifying existing code, where changing one module does not ripple through the system, and where components can be tested in isolation.

SOLID emerged from the object-oriented programming community, but the underlying ideas apply beyond classes. A Python module that does too many unrelated things violates SRP. A function that handles ten different cases with isinstance checks violates OCP. An API endpoint that returns fifty fields when the client needs three violates ISP. The principles are about managing dependencies and change, regardless of the programming paradigm.

The most important meta-principle behind SOLID is this: code that is easy to change beats code that is easy to write. Writing a monolithic class is faster initially. Splitting responsibilities, defining abstractions, and inverting dependencies takes more upfront effort. The payoff comes when requirements change - and they always do. SOLID code absorbs change locally rather than propagating it globally.

---

## How It Actually Works

Each SOLID principle addresses a specific axis of change. SRP ensures that a class changes for only one reason, so changes to logging do not affect business logic. OCP ensures that new behavior is added by writing new code (new classes, new functions) rather than modifying existing code. LSP ensures that subclasses are truly substitutable, so polymorphic code works correctly. ISP ensures that clients depend only on what they actually use, reducing the blast radius of interface changes. DIP ensures that business logic does not depend on infrastructure details, so you can swap databases or notification channels without touching core logic.

In Python, these principles manifest differently than in Java or C#. Python's duck typing means you often get ISP for free - a function that calls `obj.read()` does not depend on any other methods the object might have. Python's first-class functions mean you do not always need a class to satisfy OCP - a callback or strategy function works. Python's Protocols give you DIP without verbose interface declarations. The principles are the same, but the Pythonic implementation is more concise.

```python
# A class that violates multiple SOLID principles
class BadUserManager:
    """Does everything: validation, storage, notification, logging."""
    
    def create_user(self, name: str, email: str) -> dict:
        # Validates (SRP violation - mixed with storage)
        if "@" not in email:
            raise ValueError("Invalid email")
        
        # Stores directly (DIP violation - depends on concrete DB)
        import sqlite3
        conn = sqlite3.connect("users.db")
        conn.execute("INSERT INTO users VALUES (?, ?)", (name, email))
        conn.commit()
        
        # Sends email (SRP violation - notification is a separate concern)
        import smtplib
        server = smtplib.SMTP("smtp.gmail.com")
        server.send_message(f"Welcome {name}!")
        
        # Logs (SRP violation - yet another concern)
        with open("app.log", "a") as f:
            f.write(f"Created user {name}\n")
        
        return {"name": name, "email": email}


# Refactored to follow SOLID
from abc import ABC, abstractmethod
from typing import Protocol


# SRP: each class has one responsibility
class UserValidator:
    def validate(self, name: str, email: str) -> None:
        if not name.strip():
            raise ValueError("Name cannot be empty")
        if "@" not in email:
            raise ValueError("Invalid email format")


# DIP: depend on abstraction, not concrete DB
class UserRepository(Protocol):
    def save(self, user: dict) -> None: ...
    def find_by_email(self, email: str) -> dict | None: ...


# ISP: NotificationSender only has what notification needs
class NotificationSender(Protocol):
    def send(self, to: str, message: str) -> None: ...


# OCP: new notification channels = new classes, no modification
class EmailSender:
    def send(self, to: str, message: str) -> None:
        print(f"Email to {to}: {message}")

class SlackSender:
    def send(self, to: str, message: str) -> None:
        print(f"Slack to {to}: {message}")


# The service depends on abstractions (DIP)
# Each dependency has a single responsibility (SRP)
# New implementations extend without modifying (OCP)
class UserService:
    def __init__(
        self,
        validator: UserValidator,
        repo: UserRepository,
        notifier: NotificationSender,
    ):
        self._validator = validator
        self._repo = repo
        self._notifier = notifier

    def create_user(self, name: str, email: str) -> dict:
        self._validator.validate(name, email)
        user = {"name": name, "email": email}
        self._repo.save(user)
        self._notifier.send(email, f"Welcome {name}!")
        return user
```

---

## Visualizer

<iframe src="/static/visualizers/solid-principles.html" style="width:100%;height:420px;border:none;border-radius:8px;" title="SOLID Principles Visualizer"></iframe>

---

## How It Connects

Each SOLID principle has its own dedicated note that goes deeper into examples, edge cases, and Python-specific implementations.

[[srp|Single Responsibility Principle]]

[[ocp|Open/Closed Principle]]

[[lsp|Liskov Substitution Principle]]

[[isp|Interface Segregation Principle]]

[[dip|Dependency Inversion Principle]]

SOLID principles naturally lead to composition over inheritance. When you invert dependencies (DIP) and segregate interfaces (ISP), you end up composing small, focused objects rather than building deep inheritance hierarchies.

[[composition-over-inheritance|Composition Over Inheritance]]

Design patterns are the practical application of SOLID principles. The Strategy pattern implements OCP. The Repository pattern implements DIP. The Observer pattern implements ISP. Understanding SOLID helps you recognize when a pattern is the right solution.

[[design-patterns-overview|Design Patterns Overview]]

---

## Common Misconceptions

Misconception 1: "SOLID means every class should be tiny and do only one thing."
Reality: SRP says a class should have one **reason to change**, not one method. A class can have many methods if they all change for the same reason. An `HTTPClient` with `get()`, `post()`, `put()`, and `delete()` has one responsibility: making HTTP requests. Splitting each method into its own class would be absurd over-application of SRP.

Misconception 2: "SOLID is always the right approach."
Reality: SOLID adds abstraction layers that make code harder to navigate. For a simple script, a small internal tool, or a prototype, applying SOLID everywhere creates unnecessary complexity. The principles are most valuable in code that will be maintained by multiple people over an extended period. Knowing when SOLID is not worth the overhead is a sign of engineering maturity.

Misconception 3: "If my code follows SOLID, it is well-designed."
Reality: SOLID addresses class-level design. It does not address system-level architecture, performance, security, data modeling, or many other aspects of good software. You can have perfectly SOLID code that is architecturally flawed, uses the wrong data structures, or has security vulnerabilities. SOLID is necessary but not sufficient for good design.

---

## Why It Matters in Practice

SOLID shows its value when requirements change. A new payment provider means writing a new class, not modifying existing payment logic (OCP + DIP). A new notification channel means adding a sender, not touching the alert service (ISP + OCP). A bug in validation does not require reading through database and email code to find it (SRP). These benefits compound over time: each new feature becomes a local addition rather than a global surgery.

In interviews, SOLID is one of the most frequently tested design topics. Interviewers use it to assess whether you can think about code structure, not just code functionality. Being able to identify SOLID violations in existing code and propose focused refactorings demonstrates design maturity.

---

## Interview Angle

Common question forms:
- "What are the SOLID principles? Explain each one briefly."
- "Look at this class - which SOLID principles does it violate?"
- "How would you refactor this code to follow SOLID?"
- "Which SOLID principle is most important to you and why?"

Answer frame:
Name all five with one-sentence definitions. Give a concrete example of violating and then fixing one principle (SRP with a God class is the easiest). Explain that SOLID is about managing change, not about writing more classes. Mention that Python's duck typing and Protocols make ISP and DIP more natural. Acknowledge that over-applying SOLID is itself a design problem.

---

## Related Notes

- [[srp|Single Responsibility Principle]]
- [[ocp|Open/Closed Principle]]
- [[lsp|Liskov Substitution Principle]]
- [[isp|Interface Segregation Principle]]
- [[dip|Dependency Inversion Principle]]
- [[composition-over-inheritance|Composition Over Inheritance]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[oop-basics|OOP Basics]]
