---
title: 03 - Factory Method Pattern
description: The Factory Method pattern defines an interface for creating objects but lets subclasses or functions decide which class to instantiate, decoupling object creation from usage.
tags: [design-patterns, factory, creational, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Factory Method Pattern

> The Factory Method encapsulates object creation in a method or function, so that calling code requests an object without knowing the concrete class being instantiated.

---

## Quick Reference

**Core idea:**
- A factory method creates and returns objects without the caller specifying the exact class
- Decouples **what** is created from **who** decides which class to use
- In Python, factory methods are often standalone functions or `@classmethod` alternatives to `__init__`
- The pattern follows OCP: adding a new product type means adding a new class, not modifying the factory's callers
- Common in Python: `dict.fromkeys()`, `datetime.fromtimestamp()`, `pathlib.Path()` (returns `PosixPath` or `WindowsPath`)

**Tricky points:**
- In Python, a simple function often replaces the full GoF Factory Method class hierarchy
- Factory methods are not the same as the Abstract Factory pattern - Factory Method creates one product, Abstract Factory creates families of related products
- Overusing factories adds indirection without value when there is only one product type
- Python's `__init_subclass__` and class registries can automate factory registration

---

## What It Is

Think of ordering food at a restaurant versus cooking at home. When you cook at home, you decide every ingredient, every step, every tool. When you order at a restaurant, you say "I want the pasta" and the kitchen decides which pasta, which sauce, which technique. You get the food you asked for without being involved in the creation details. The kitchen is the factory. You specify what you want, and the factory handles how.

The Factory Method pattern applies this to object creation. Instead of calling `PostgresDatabase("localhost", 5432)` directly, you call `Database.create("postgres")` and the factory method returns the right object. If the application later needs MySQL support, you write a new `MySQLDatabase` class and update the factory - but every caller that uses `Database.create()` continues to work without changes.

In Python, factory methods appear in three forms. First, as `@classmethod` alternatives to `__init__`: `User.from_dict(data)` or `Config.from_yaml(path)`. These provide named constructors that are clearer than overloading `__init__` with many parameter combinations. Second, as standalone functions: `create_connection(config)` that returns the right connection type based on the config. Third, as the full GoF pattern with a creator class hierarchy - rarely needed in Python because functions and classmethods cover most cases.

The key benefit is that the creation logic lives in one place. If every module independently decides `if db_type == "postgres": ... elif db_type == "mysql": ...`, adding a new database type requires finding and updating every decision point. A factory centralizes this logic.

---

## How It Actually Works

The GoF Factory Method pattern uses inheritance: a base creator class defines the factory method as abstract, and each concrete creator overrides it to instantiate a specific product. In Python, this is often simplified to a single function or classmethod with a dispatch dictionary.

Python's `__init_subclass__` hook enables automatic registration: every subclass registers itself in a class-level dictionary when it is defined. The factory method looks up the registry. Adding a new product type means defining a new class - no modification to the factory or the registry logic.

```python
from abc import ABC, abstractmethod
from typing import Any


# Approach 1: Simple factory function (most Pythonic)
class Serializer(ABC):
    @abstractmethod
    def serialize(self, data: dict) -> str: ...

class JSONSerializer(Serializer):
    def serialize(self, data: dict) -> str:
        import json
        return json.dumps(data, indent=2)

class YAMLSerializer(Serializer):
    def serialize(self, data: dict) -> str:
        lines = [f"{k}: {v}" for k, v in data.items()]
        return "\n".join(lines)

class XMLSerializer(Serializer):
    def serialize(self, data: dict) -> str:
        items = "".join(f"  <{k}>{v}</{k}>\n" for k, v in data.items())
        return f"<data>\n{items}</data>"

def create_serializer(format: str) -> Serializer:
    """Factory function - single point of creation logic."""
    factories = {
        "json": JSONSerializer,
        "yaml": YAMLSerializer,
        "xml": XMLSerializer,
    }
    if format not in factories:
        raise ValueError(f"Unknown format: {format}. Options: {list(factories)}")
    return factories[format]()

# Caller is decoupled from concrete classes
s = create_serializer("json")
print(s.serialize({"name": "Alice", "age": 30}))


# Approach 2: @classmethod factory (named constructors)
from dataclasses import dataclass
from datetime import datetime

@dataclass
class Event:
    name: str
    timestamp: datetime
    source: str
    metadata: dict

    @classmethod
    def from_dict(cls, data: dict) -> "Event":
        """Factory: create from raw dictionary."""
        return cls(
            name=data["name"],
            timestamp=datetime.fromisoformat(data["timestamp"]),
            source=data.get("source", "unknown"),
            metadata=data.get("metadata", {}),
        )

    @classmethod
    def system_event(cls, name: str) -> "Event":
        """Factory: create a system-generated event."""
        return cls(
            name=name,
            timestamp=datetime.now(),
            source="system",
            metadata={"auto_generated": True},
        )

e1 = Event.from_dict({"name": "login", "timestamp": "2026-05-18T10:00:00"})
e2 = Event.system_event("health_check")


# Approach 3: Auto-registering factory with __init_subclass__
class Handler(ABC):
    _registry: dict[str, type["Handler"]] = {}

    def __init_subclass__(cls, handler_type: str = "", **kwargs):
        super().__init_subclass__(**kwargs)
        if handler_type:
            Handler._registry[handler_type] = cls

    @classmethod
    def create(cls, handler_type: str, **kwargs) -> "Handler":
        """Factory method: looks up the registry."""
        if handler_type not in cls._registry:
            raise ValueError(f"No handler for: {handler_type}")
        return cls._registry[handler_type](**kwargs)

    @abstractmethod
    def handle(self, data: Any) -> str: ...


class EmailHandler(Handler, handler_type="email"):
    def __init__(self, host: str = "smtp.local"):
        self.host = host

    def handle(self, data: Any) -> str:
        return f"Email via {self.host}: {data}"


class SlackHandler(Handler, handler_type="slack"):
    def __init__(self, webhook: str = "https://hooks.slack.com"):
        self.webhook = webhook

    def handle(self, data: Any) -> str:
        return f"Slack to {self.webhook}: {data}"


# New handler? Just define a class. No factory modification needed.
class SMSHandler(Handler, handler_type="sms"):
    def handle(self, data: Any) -> str:
        return f"SMS: {data}"


# Usage
h = Handler.create("email", host="smtp.company.com")
print(h.handle("Server down"))         # Email via smtp.company.com: Server down

h2 = Handler.create("sms")
print(h2.handle("Alert!"))             # SMS: Alert!

print(f"Registered handlers: {list(Handler._registry.keys())}")
# ['email', 'slack', 'sms']
```

---

## How It Connects

The Factory Method pattern is the foundational creational pattern. Abstract Factory extends it to create families of related objects.

[[abstract-factory|Abstract Factory Pattern]]

[[design-patterns-overview|Design Patterns Overview]]

Factory Method directly implements the Open/Closed Principle: new product types are added by writing new classes, not by modifying the factory or its callers.

[[ocp|Open/Closed Principle]]

Python's `__init_subclass__` hook enables automatic factory registration, eliminating the need to manually update a dispatch dictionary when new subclasses are created.

[[class-creation|Class Creation]]

---

## Common Misconceptions

Misconception 1: "A factory is just an if-elif chain that creates objects."
Reality: The if-elif chain is the simplest form, but the real value is the abstraction. Callers interact with the factory method and receive an abstract type. They do not know or depend on which concrete class was created. The auto-registering pattern eliminates even the if-elif, making the factory truly open for extension.

Misconception 2: "You always need a Factory class with inheritance like in the GoF book."
Reality: In Python, a standalone factory function or a `@classmethod` is usually sufficient. The full GoF pattern with abstract creators and concrete creators is needed only when you have multiple product families or when the creation logic itself varies across contexts.

---

## Why It Matters in Practice

Factory methods appear everywhere in Python libraries. `pathlib.Path()` returns a `PosixPath` on Linux and `WindowsPath` on Windows. `logging.getLogger(name)` returns an existing logger or creates a new one. `json.loads()` creates Python objects from JSON strings. Understanding the pattern helps you use these APIs effectively and design similar APIs in your own code.

In application code, factories centralize creation logic that would otherwise be duplicated across modules. When your application creates database connections in fifteen places and the connection parameters change, you update one factory instead of fifteen call sites.

---

## Interview Angle

Common question forms:
- "What is the Factory Method pattern?"
- "When would you use a factory instead of direct instantiation?"
- "Implement a factory that creates different serializers based on format."
- "What is the difference between Factory Method and Abstract Factory?"

Answer frame:
Define Factory Method as encapsulated creation logic. Show a concrete example (serializer factory). Explain the benefit: callers are decoupled from concrete classes, new types require no caller changes. Distinguish from Abstract Factory (one product vs product families). In Python, mention `@classmethod` factories and `__init_subclass__` auto-registration as idiomatic approaches.

---

## Related Notes

- [[abstract-factory|Abstract Factory Pattern]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[ocp|Open/Closed Principle]]
- [[class-creation|Class Creation]]
- [[solid-principles|SOLID Principles]]
