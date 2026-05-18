---
title: 09 - Open/Closed Principle
description: Software entities should be open for extension but closed for modification - you should be able to add new behavior without changing existing, tested code.
tags: [oop, solid, ocp, extension, polymorphism, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Open/Closed Principle

> A class should be open for extension (you can add new behavior) but closed for modification (you do not change its existing source code to do so).

---

## Quick Reference

**Core idea:**
- OCP says you should add new functionality by writing **new code**, not by modifying existing code
- Achieved through **polymorphism**: define an abstraction, then add new implementations without touching the code that uses the abstraction
- In Python: use ABCs, Protocols, strategy functions, plugins, or registries to allow extension without modification
- The "closed" part protects existing, tested behavior from regressions when new features are added
- The "open" part ensures the design anticipates change and provides extension points

**Tricky points:**
- You cannot predict every axis of change - OCP applies to the axes of change you reasonably anticipate, not to everything
- Premature OCP creates over-abstracted code with extension points that are never used
- OCP does not mean never modify code - bug fixes, refactoring, and changing business rules often require modification
- Python's dynamic nature (duck typing, first-class functions, decorators) makes OCP easier to achieve than in statically typed languages

---

## What It Is

Think of a power strip with outlets. The power strip is closed for modification - you do not open it up and rewire it when you buy a new appliance. But it is open for extension - you plug in a new device and it works. The power strip's design anticipated that new devices would come along. It provides a standard interface (the outlet) that any device can use. Adding a new device does not require changing the power strip.

In software, OCP means designing your code so that adding a new feature is a matter of writing a new class or function that plugs into the existing system, rather than opening up existing classes and modifying their internals. Consider a discount calculator with an if-elif chain: `if customer_type == "premium": ...` `elif customer_type == "employee": ...`. Every new customer type requires modifying this function. That is a class (or function) that is open for modification and closed for extension - the opposite of OCP.

The OCP-compliant design replaces the if-elif chain with polymorphism. You define a `DiscountStrategy` interface with a `calculate()` method. Each customer type has its own strategy class. The discount calculator receives a strategy object and calls `calculate()` on it. Adding a new customer type means writing a new strategy class. The calculator itself is never modified - it is closed for modification and open for extension.

Python makes OCP particularly natural because functions are first-class objects. Instead of creating a strategy class hierarchy, you can often just pass a function. A sorting function that accepts a `key` parameter is open for extension (pass any key function) and closed for modification (the sort algorithm itself never changes). This functional approach to OCP is arguably more Pythonic than the class-based approach.

---

## How It Actually Works

OCP is typically implemented through one of several patterns: strategy (swap behavior via composed objects or callbacks), template method (override specific steps in a base class), plugin registry (register new handlers at runtime), or decorator (wrap existing behavior with new behavior). Each approach provides extension points where new code plugs in without modifying the existing code.

In Python, the plugin registry pattern is particularly powerful. You define a registry (a dictionary mapping names to handlers), provide a decorator for registering new handlers, and the core logic looks up handlers by name. Adding a new handler means decorating a new function - the core logic and existing handlers are untouched.

```python
from typing import Protocol, Callable
from functools import singledispatch


# BEFORE: OCP violation - every new shape requires modifying this function
def calculate_area_bad(shape_type: str, **kwargs) -> float:
    if shape_type == "circle":
        return 3.14159 * kwargs["radius"] ** 2
    elif shape_type == "rectangle":
        return kwargs["width"] * kwargs["height"]
    elif shape_type == "triangle":
        return 0.5 * kwargs["base"] * kwargs["height"]
    # Every new shape = modify this function
    else:
        raise ValueError(f"Unknown shape: {shape_type}")


# AFTER: OCP-compliant with Protocol and polymorphism
class Shape(Protocol):
    def area(self) -> float: ...

import math

class Circle:
    def __init__(self, radius: float):
        self.radius = radius
    def area(self) -> float:
        return math.pi * self.radius ** 2

class Rectangle:
    def __init__(self, width: float, height: float):
        self.width = width
        self.height = height
    def area(self) -> float:
        return self.width * self.height

# Adding a new shape = write a new class. ZERO modification to existing code.
class Hexagon:
    def __init__(self, side: float):
        self.side = side
    def area(self) -> float:
        return (3 * math.sqrt(3) / 2) * self.side ** 2

def total_area(shapes: list[Shape]) -> float:
    """This function never changes, no matter how many shapes exist."""
    return sum(s.area() for s in shapes)


# Plugin registry pattern - very Pythonic OCP
_exporters: dict[str, Callable] = {}

def register_exporter(format_name: str):
    """Decorator to register a new export format."""
    def decorator(func: Callable) -> Callable:
        _exporters[format_name] = func
        return func
    return decorator

def export_data(data: list[dict], format_name: str) -> str:
    """Core function - never modified when new formats are added."""
    if format_name not in _exporters:
        raise ValueError(f"Unknown format: {format_name}. "
                         f"Available: {list(_exporters.keys())}")
    return _exporters[format_name](data)

@register_exporter("csv")
def _export_csv(data: list[dict]) -> str:
    if not data:
        return ""
    headers = ",".join(data[0].keys())
    rows = "\n".join(",".join(str(v) for v in row.values()) for row in data)
    return f"{headers}\n{rows}"

@register_exporter("json")
def _export_json(data: list[dict]) -> str:
    import json
    return json.dumps(data, indent=2)

# New format? Just add a new decorated function. export_data never changes.
@register_exporter("yaml")
def _export_yaml(data: list[dict]) -> str:
    lines = []
    for item in data:
        lines.append("- " + ", ".join(f"{k}: {v}" for k, v in item.items()))
    return "\n".join(lines)

sample = [{"name": "Alice", "score": 95}, {"name": "Bob", "score": 87}]
print(export_data(sample, "csv"))
print(export_data(sample, "json"))
print(export_data(sample, "yaml"))
```

---

## How It Connects

OCP is closely tied to polymorphism. The mechanism that makes code open for extension is polymorphic dispatch - whether through method overriding, duck typing, or function callbacks.

[[polymorphism|Polymorphism]]

The Strategy pattern is the most direct implementation of OCP. It extracts varying behavior into interchangeable strategy objects, keeping the context class closed for modification.

[[strategy-pattern|Strategy Pattern]]

OCP is one of five SOLID principles. SRP often enables OCP: a class with a single responsibility is easier to design with stable extension points.

[[solid-principles|SOLID Principles]]

[[srp|Single Responsibility Principle]]

Python decorators provide a natural extension mechanism. A decorator wraps existing behavior without modifying the original function, which is OCP applied at the function level.

[[decorators|Decorators]]

---

## Common Misconceptions

Misconception 1: "OCP means you should never modify existing code."
Reality: OCP applies to adding new behavior. Bug fixes, performance improvements, and refactoring existing behavior all require modifying existing code and are perfectly appropriate. OCP says that when you add a **new feature** (a new payment method, a new export format, a new discount type), you should write new code rather than editing existing code. The distinction is between extending functionality and fixing or improving it.

Misconception 2: "I should make everything extensible from the start."
Reality: Over-engineering for hypothetical future changes is as harmful as ignoring OCP entirely. Apply OCP to the axes of change you can reasonably anticipate based on domain knowledge and past experience. If your payment system has only supported credit cards for three years, building a plugin system for payment methods is premature. If your application already uses three export formats and users regularly request new ones, an extensible exporter is justified.

Misconception 3: "If-elif chains always violate OCP."
Reality: An if-elif chain that handles a small, stable set of cases (checking HTTP methods, handling a few enum values) is fine. OCP violations matter when the set of cases grows over time. If you find yourself adding a new elif branch every sprint, that is a signal to refactor toward polymorphism.

---

## Why It Matters in Practice

OCP violations are the most common source of regression bugs in growing codebases. Every time you open a working function to add a new elif branch, you risk breaking the existing branches. The new code might introduce a subtle interaction with existing logic, or the indentation might be wrong, or a shared variable gets corrupted. OCP-compliant code avoids this because existing code is never edited when new features are added.

OCP also reduces the blast radius of code reviews. When adding a new export format is a new file with a new class (rather than modifications sprinkled throughout an existing file), the code review is focused on the new code only. Reviewers do not need to verify that existing behavior is preserved because existing code was not touched.

---

## Interview Angle

Common question forms:
- "What is the Open/Closed Principle?"
- "How would you refactor this if-elif chain to follow OCP?"
- "Give an example of OCP in a real Python project."

Answer frame:
Define OCP as open for extension, closed for modification. Show the if-elif anti-pattern and refactor with polymorphism (strategy or registry). Explain that Python's first-class functions make OCP natural (pass a key function to `sorted()`, pass a callback to a framework). Mention the risk of premature abstraction. Connect to Strategy pattern and decorator pattern as implementations.

---

## Related Notes

- [[polymorphism|Polymorphism]]
- [[strategy-pattern|Strategy Pattern]]
- [[solid-principles|SOLID Principles]]
- [[srp|Single Responsibility Principle]]
- [[decorators|Decorators]]
- [[oop-basics|OOP Basics]]
