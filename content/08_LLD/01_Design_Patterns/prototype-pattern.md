---
title: 06 - Prototype Pattern
description: The Prototype pattern creates new objects by cloning an existing object rather than constructing from scratch, useful when object creation is expensive or when objects need to be configured copies of a template.
tags: [design-patterns, prototype, creational, copy, clone, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Prototype Pattern

> The Prototype pattern creates new objects by copying an existing instance, avoiding the cost of building from scratch when creation is expensive or when objects need to start as configured templates.

---

## Quick Reference

**Core idea:**
- Create new objects by **cloning** an existing prototype rather than calling a constructor
- Useful when object creation is expensive (complex initialization, database lookups, network calls)
- Python provides `copy.copy()` (shallow) and `copy.deepcopy()` (deep) as built-in cloning mechanisms
- Common use: creating pre-configured template objects and cloning them with modifications
- Avoids coupling to specific classes - you clone the object without knowing its concrete type

**Tricky points:**
- Shallow copy shares references to nested mutable objects - modifying a nested list in the clone affects the original
- Deep copy is recursive and can be slow for large object graphs with circular references
- Custom `__copy__` and `__deepcopy__` methods let you control exactly what gets cloned
- In Python, dataclasses with `dataclasses.replace()` often provide a cleaner "clone with modifications" pattern

---

## What It Is

Think of a document template system. You have a standard contract template with company name, legal clauses, formatting, and boilerplate text already filled in. For each new client, you do not write the contract from scratch. You copy the template and change only the client-specific fields - name, dates, amounts. The template is the prototype. Each new contract is a clone with modifications.

The Prototype pattern applies this to object creation. Instead of constructing a complex object by calling its constructor and setting thirty attributes, you clone an existing instance that already has most of those attributes set correctly, then modify only what differs. This is especially valuable when creation involves expensive operations - loading configuration files, querying databases, computing derived values - that you want to perform once and reuse.

In Python, the `copy` module provides the cloning mechanism. `copy.copy()` creates a shallow copy (new object, same references to nested objects). `copy.deepcopy()` creates a deep copy (new object, new copies of all nested objects recursively). For dataclasses, `dataclasses.replace()` creates a new instance with specified fields changed, which is often the most Pythonic approach.

---

## How It Actually Works

When you call `copy.copy(obj)`, Python calls `obj.__copy__()` if defined, or falls back to creating a new instance of the same class and copying the `__dict__`. Shallow copy means nested mutable objects (lists, dicts, sets) are shared between the original and the copy. When you call `copy.deepcopy(obj)`, Python recursively copies all nested objects, using a memo dictionary to handle circular references.

```python
import copy
from dataclasses import dataclass, field, replace
from typing import Optional


@dataclass
class ServerConfig:
    host: str
    port: int
    ssl: bool
    timeout: float
    headers: dict[str, str] = field(default_factory=dict)
    middleware: list[str] = field(default_factory=list)
    max_connections: int = 100


# Create a prototype with common settings
production_template = ServerConfig(
    host="0.0.0.0",
    port=443,
    ssl=True,
    timeout=30.0,
    headers={"X-Server": "PyApp", "Strict-Transport-Security": "max-age=31536000"},
    middleware=["auth", "logging", "compression", "rate-limit"],
    max_connections=1000,
)

# Clone and modify for specific services
api_server = replace(production_template, port=8443, max_connections=5000)
admin_server = replace(production_template, port=9443, max_connections=50)

print(api_server.port)            # 8443
print(api_server.ssl)             # True (from template)
print(api_server.max_connections)  # 5000 (overridden)

# WARNING: replace() is a shallow copy - mutable fields are shared
api_server.middleware.append("cors")
print(production_template.middleware)  # also has "cors" - shared reference!


# Deep copy for full independence
staging_server = copy.deepcopy(production_template)
staging_server.host = "staging.internal"
staging_server.ssl = False
staging_server.middleware.append("debug-toolbar")
print(production_template.middleware)  # NOT affected - deep copy


# Custom clone behavior via __copy__ and __deepcopy__
class Connection:
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self._socket = None  # runtime state, should not be cloned
        self._request_count = 0

    def __copy__(self):
        """Shallow clone: copy config, reset runtime state."""
        new = Connection(self.host, self.port)
        # Do NOT copy _socket or _request_count
        return new

    def __deepcopy__(self, memo):
        """Deep clone: same as shallow for this class."""
        return self.__copy__()

    def __repr__(self):
        return f"Connection({self.host}:{self.port}, requests={self._request_count})"


original = Connection("db.prod", 5432)
original._request_count = 1500

cloned = copy.copy(original)
print(original)  # Connection(db.prod:5432, requests=1500)
print(cloned)     # Connection(db.prod:5432, requests=0) - reset


# Prototype registry - store named prototypes for reuse
class ConfigRegistry:
    _prototypes: dict[str, ServerConfig] = {}

    @classmethod
    def register(cls, name: str, config: ServerConfig) -> None:
        cls._prototypes[name] = config

    @classmethod
    def create(cls, name: str, **overrides) -> ServerConfig:
        if name not in cls._prototypes:
            raise KeyError(f"No prototype: {name}")
        base = copy.deepcopy(cls._prototypes[name])
        for key, value in overrides.items():
            setattr(base, key, value)
        return base

ConfigRegistry.register("production", production_template)
new_server = ConfigRegistry.create("production", port=7443, host="custom.internal")
```

---

## Visualizer

<iframe src="/static/visualizers/prototype-pattern.html" style="width:100%;height:440px;border:none;border-radius:8px;" title="Prototype Pattern Visualizer"></iframe>

---

## How It Connects

The Prototype pattern uses Python's `copy` module, which relies on `__copy__` and `__deepcopy__` dunder methods. Understanding shallow vs deep copy is foundational.

[[copy-vs-deepcopy|Copy vs Deepcopy]]

Prototype is a creational pattern alongside Factory Method, Abstract Factory, Builder, and Singleton. While factories create objects from class definitions, Prototype creates objects from existing instances.

[[design-patterns-overview|Design Patterns Overview]]

Python's dataclasses provide `dataclasses.replace()` which is a built-in "clone with modifications" operation, making the Prototype pattern feel native.

[[dataclasses|Dataclasses]]

---

## Common Misconceptions

Misconception 1: "Prototype is just calling `copy.deepcopy()`."
Reality: The pattern includes the concept of a prototype registry and the ability to customize what gets cloned. Runtime state (open connections, counters, locks) should typically not be cloned. Custom `__copy__` and `__deepcopy__` methods let you control this.

Misconception 2: "Prototype is rarely useful in Python."
Reality: The pattern appears constantly in Python - test fixtures (clone a base fixture and modify), configuration management (clone a template config for each environment), and ORM operations (clone a query and add filters). The pattern is common; the GoF name is just rarely used.

---

## Why It Matters in Practice

In testing, prototypes are essential. You create a base test fixture with valid data and clone it for each test, modifying only the fields relevant to that test. This is cleaner and more maintainable than constructing every test object from scratch. Libraries like factory_boy implement this pattern explicitly.

In configuration management, prototypes let you define a production baseline and derive staging, development, and testing configs by cloning and overriding specific values. This ensures that derived configs inherit all production settings by default and differ only where explicitly specified.

---

## Interview Angle

Common question forms:
- "What is the Prototype pattern?"
- "When would you clone an object instead of creating a new one?"
- "What is the difference between shallow and deep copy in Python?"

Answer frame:
Define Prototype as creation by cloning. Explain shallow vs deep copy. Give the configuration template example. Show `dataclasses.replace()` as the Pythonic approach. Mention custom `__copy__`/`__deepcopy__` for controlling what gets cloned.

---

## Related Notes

- [[copy-vs-deepcopy|Copy vs Deepcopy]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[dataclasses|Dataclasses]]
- [[factory-method|Factory Method Pattern]]
