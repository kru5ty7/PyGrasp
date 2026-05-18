---
title: 05 - Builder Pattern
description: The Builder pattern separates the construction of a complex object from its representation, letting you construct objects step by step and produce different configurations using the same construction process.
tags: [design-patterns, builder, creational, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Builder Pattern

> The Builder pattern constructs complex objects step by step, separating the construction process from the final representation so that the same process can create different configurations.

---

## Quick Reference

**Core idea:**
- Builder separates **construction** (how to assemble) from **representation** (what you get)
- Useful when an object has many optional parameters, required validation across parameters, or multi-step construction
- In Python, the `@dataclass` with defaults, keyword arguments, and `__post_init__` often replaces the need for a Builder
- The fluent interface variant returns `self` from each method, enabling method chaining: `builder.set_x(1).set_y(2).build()`
- Common in Python: `argparse.ArgumentParser`, SQLAlchemy query builder, Pydantic model construction

**Tricky points:**
- In Python, keyword arguments with defaults often eliminate the need for the Builder pattern entirely
- The Builder is mutable during construction but the product should be immutable after `build()` is called
- A Builder without a `build()` method that validates the complete state can produce invalid objects
- Overusing Builder for simple objects with few parameters adds unnecessary complexity

---

## What It Is

Think of ordering a custom sandwich at a deli counter. You do not get handed a pre-made sandwich. Instead, you build it step by step: choose the bread, add the protein, pick the cheese, select vegetables, choose the sauce. Each step is independent - you can skip cheese, double the protein, or add extra sauce. At the end, the deli assembles your choices into the final sandwich. The order slip is the builder. The sandwich is the product. The deli counter is the director that follows the slip to assemble the result.

The Builder pattern works the same way in code. When an object has many parameters - some required, some optional, some with complex dependencies - a constructor with fifteen arguments becomes unreadable. The Builder lets you set each parameter with a named method, validate the combination when you call `build()`, and produce the final immutable object. Each method call is self-documenting: `query.select("name").from_table("users").where("age > 18")` is clearer than `Query("name", "users", None, None, "age > 18", None, None)`.

In Python, keyword arguments with defaults solve many Builder use cases. `User(name="Alice", email="alice@test.com", role="admin")` is clear and does not require a separate Builder class. The Builder pattern becomes valuable when construction involves validation logic that spans multiple fields, when the construction process has a specific order, or when you need to reuse the same construction process to create different representations.

---

## How It Actually Works

The Builder stores configuration state in its own attributes, validates the combination when `build()` is called, and returns a new product object. The product is typically a dataclass or a class with `__slots__` that is immutable after creation.

The fluent interface variant returns `self` from each setter method, allowing method chaining. This is a stylistic choice, not a requirement of the pattern.

```python
from dataclasses import dataclass, field
from typing import Optional


@dataclass(frozen=True)
class HTTPRequest:
    """Immutable product - cannot be modified after creation."""
    method: str
    url: str
    headers: dict[str, str]
    body: Optional[str]
    timeout: float
    retries: int
    auth: Optional[tuple[str, str]]


class HTTPRequestBuilder:
    """Builds HTTPRequest step by step with validation."""

    def __init__(self, method: str, url: str):
        self._method = method
        self._url = url
        self._headers: dict[str, str] = {}
        self._body: Optional[str] = None
        self._timeout: float = 30.0
        self._retries: int = 0
        self._auth: Optional[tuple[str, str]] = None

    def header(self, key: str, value: str) -> "HTTPRequestBuilder":
        self._headers[key] = value
        return self  # fluent interface

    def body(self, content: str, content_type: str = "application/json") -> "HTTPRequestBuilder":
        self._body = content
        self._headers["Content-Type"] = content_type
        return self

    def timeout(self, seconds: float) -> "HTTPRequestBuilder":
        if seconds <= 0:
            raise ValueError("Timeout must be positive")
        self._timeout = seconds
        return self

    def retries(self, count: int) -> "HTTPRequestBuilder":
        if count < 0:
            raise ValueError("Retries must be non-negative")
        self._retries = count
        return self

    def basic_auth(self, username: str, password: str) -> "HTTPRequestBuilder":
        self._auth = (username, password)
        return self

    def build(self) -> HTTPRequest:
        """Validate and create the immutable product."""
        if self._method in ("GET", "HEAD", "DELETE") and self._body:
            raise ValueError(f"{self._method} requests should not have a body")
        if self._auth and "Authorization" in self._headers:
            raise ValueError("Cannot set both basic_auth and Authorization header")

        return HTTPRequest(
            method=self._method,
            url=self._url,
            headers=dict(self._headers),  # defensive copy
            body=self._body,
            timeout=self._timeout,
            retries=self._retries,
            auth=self._auth,
        )


# Fluent construction
request = (
    HTTPRequestBuilder("POST", "https://api.example.com/users")
    .header("Accept", "application/json")
    .body('{"name": "Alice"}')
    .timeout(10.0)
    .retries(3)
    .basic_auth("admin", "secret")
    .build()
)

print(request.method)   # POST
print(request.headers)  # {'Accept': 'application/json', 'Content-Type': 'application/json'}
print(request.retries)  # 3


# Validation catches invalid combinations
try:
    (
        HTTPRequestBuilder("GET", "https://api.example.com/users")
        .body("should not have body")
        .build()
    )
except ValueError as e:
    print(f"Caught: {e}")  # GET requests should not have a body


# Pythonic alternative: dataclass with __post_init__ validation
@dataclass
class SimpleRequest:
    method: str
    url: str
    headers: dict[str, str] = field(default_factory=dict)
    body: Optional[str] = None
    timeout: float = 30.0

    def __post_init__(self):
        if self.method in ("GET", "HEAD") and self.body:
            raise ValueError(f"{self.method} should not have a body")

# For simpler cases, this is enough
req = SimpleRequest(method="GET", url="https://example.com", timeout=5.0)
```

---

## How It Connects

Builder is a creational pattern that complements Factory Method. Factory Method decides which class to instantiate. Builder decides how to configure the instance.

[[factory-method|Factory Method Pattern]]

[[design-patterns-overview|Design Patterns Overview]]

Python's dataclasses with `frozen=True` and `__post_init__` provide built-in support for many Builder use cases. Understanding dataclasses helps you decide when a separate Builder class is justified.

[[dataclasses|Dataclasses]]

---

## Common Misconceptions

Misconception 1: "Builder is always better than a constructor with many parameters."
Reality: In Python, keyword arguments with defaults handle most cases. `User(name="Alice", role="admin")` is clear without a Builder. Use Builder when construction involves multi-step validation, when the same process should produce different types, or when the construction order matters.

Misconception 2: "The fluent interface (method chaining) is required for the Builder pattern."
Reality: Method chaining is a stylistic choice. A Builder with separate method calls that do not return `self` is still a Builder. The pattern is about separating construction from representation, not about syntax style.

---

## Why It Matters in Practice

Builders appear in Python libraries as query builders (SQLAlchemy's `select().where().order_by()`), argument parsers (`argparse`), and test data factories (factory_boy). Understanding the pattern helps you design APIs that guide users through complex configurations with validation at each step, rather than exposing constructors with twenty parameters.

---

## Interview Angle

Common question forms:
- "What is the Builder pattern and when would you use it?"
- "How does Builder differ from Factory?"
- "Implement a Builder for a complex configuration object."

Answer frame:
Define Builder as step-by-step construction with validation. Show a fluent interface example. Explain when Python's keyword arguments suffice and when Builder adds value (cross-field validation, multi-step construction). Contrast with Factory (which class vs how to configure).

---

## Related Notes

- [[factory-method|Factory Method Pattern]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[dataclasses|Dataclasses]]
