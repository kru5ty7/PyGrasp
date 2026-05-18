---
title: 01 - Design Patterns Overview
description: Design patterns are reusable solutions to common software design problems, cataloged by the Gang of Four into creational, structural, and behavioral categories that address object creation, composition, and interaction.
tags: [design-patterns, gof, creational, structural, behavioral, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Design Patterns Overview

> Design patterns are proven, reusable solutions to recurring design problems - they give you a shared vocabulary and a catalog of approaches for structuring code at the class and object level.

---

## Quick Reference

**Core idea:**
- Design patterns are solutions to **recurring problems**, not inventions - they were observed in successful software and cataloged
- The Gang of Four (GoF) book categorizes 23 patterns into three groups: **Creational** (how objects are created), **Structural** (how objects are composed), and **Behavioral** (how objects interact)
- Patterns are not code templates - they are conceptual solutions that you adapt to your language and context
- Python's dynamic features (first-class functions, duck typing, decorators, descriptors) make some patterns trivial or unnecessary
- The value of patterns is communication: saying "use a Strategy here" conveys a complex design decision in two words

**Tricky points:**
- Not every problem needs a pattern - patterns add indirection, and unnecessary indirection is complexity without benefit
- Some GoF patterns (Abstract Factory, Bridge, Visitor) are rarely needed in Python because duck typing and first-class functions provide simpler alternatives
- A pattern applied to the wrong problem makes code worse, not better - patterns solve specific categories of problems
- Knowing the name of a pattern is less important than understanding the problem it solves and when to apply it
- Python has its own idiomatic patterns (context managers, decorators, generators) that do not appear in the GoF catalog

---

## What It Is

Think of architectural blueprints for houses. Over centuries, architects noticed that certain room layouts, structural supports, and ventilation designs keep appearing because they solve universal problems - kitchens near dining rooms, load-bearing walls under heavy floors, windows positioned for cross-ventilation. These are not rigid templates that every house must follow. They are proven solutions that architects adapt to specific sites, climates, and client needs. A new architect studies these patterns to avoid reinventing solutions to problems that have been solved thousands of times.

Design patterns in software serve the same purpose. In 1994, four authors - Erich Gamma, Richard Helm, Ralph Johnson, and John Vlissides, collectively known as the Gang of Four (GoF) - published "Design Patterns: Elements of Reusable Object-Oriented Software." They cataloged 23 patterns they observed repeatedly in well-designed software systems. Each pattern describes a problem that occurs frequently, the core of the solution, and the consequences of applying it. The patterns are language-agnostic concepts, though the original book used C++ and Smalltalk examples.

The 23 patterns fall into three categories. Creational patterns deal with object creation - controlling how and when objects are instantiated. Singleton ensures only one instance exists. Factory Method lets subclasses decide which class to instantiate. Builder separates the construction of a complex object from its representation. Structural patterns deal with how classes and objects are composed into larger structures. Adapter makes incompatible interfaces work together. Decorator adds behavior to objects dynamically. Facade provides a simplified interface to a complex subsystem. Behavioral patterns deal with how objects communicate and distribute responsibility. Strategy lets you swap algorithms at runtime. Observer notifies dependents when state changes. Command encapsulates a request as an object.

Python's dynamic nature means some patterns are simpler or unnecessary compared to Java or C++. The Strategy pattern in Java requires a strategy interface, concrete strategy classes, and a context class. In Python, you pass a function. The Singleton pattern in Java requires careful synchronization. In Python, you use a module-level variable. The Iterator pattern in Java requires implementing an interface. In Python, you write a generator. Understanding which patterns are simplified by Python, and which remain valuable, is the key to applying them effectively.

---

## How It Actually Works

Each design pattern addresses a specific force or tension in software design. Creational patterns address the tension between flexible object creation and tight coupling to concrete classes. If your code directly calls `PostgresDatabase()`, it is coupled to Postgres. A Factory pattern decouples the creation decision from the usage, letting you swap databases without changing calling code.

Structural patterns address the tension between composing objects into useful structures and keeping classes focused. If you need a class that combines logging, caching, and retry logic, you could create a massive class with all three concerns. Or you could use the Decorator pattern to wrap a core object with logging, then wrap that with caching, then wrap that with retry - each concern in its own class, composed dynamically.

Behavioral patterns address the tension between objects that need to collaborate and objects that should remain loosely coupled. If ten UI components need to react when the user's settings change, you could have the settings object directly call methods on all ten components. Or you could use the Observer pattern: components register as observers, and the settings object notifies all observers when it changes, without knowing who they are.

```python
# Quick examples of each category

# CREATIONAL: Factory Method - decouple creation from usage
class Serializer:
    @staticmethod
    def create(format: str) -> "Serializer":
        if format == "json":
            return JSONSerializer()
        elif format == "xml":
            return XMLSerializer()
        raise ValueError(f"Unknown format: {format}")

    def serialize(self, data: dict) -> str:
        raise NotImplementedError


class JSONSerializer(Serializer):
    def serialize(self, data: dict) -> str:
        import json
        return json.dumps(data)

class XMLSerializer(Serializer):
    def serialize(self, data: dict) -> str:
        items = "".join(f"<{k}>{v}</{k}>" for k, v in data.items())
        return f"<data>{items}</data>"


# STRUCTURAL: Decorator - add behavior without modifying the original
from typing import Callable
import time

def timed(func: Callable) -> Callable:
    """Decorator adds timing without modifying the original function."""
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f"{func.__name__} took {elapsed:.4f}s")
        return result
    return wrapper

def retry(max_attempts: int = 3):
    """Decorator adds retry without modifying the original function."""
    def decorator(func: Callable) -> Callable:
        def wrapper(*args, **kwargs):
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_attempts:
                        raise
                    print(f"Attempt {attempt} failed: {e}, retrying...")
        return wrapper
    return decorator

@timed
@retry(max_attempts=3)
def fetch_data(url: str) -> str:
    return f"Data from {url}"


# BEHAVIORAL: Observer - notify without knowing who is listening
class EventEmitter:
    def __init__(self):
        self._listeners: dict[str, list[Callable]] = {}

    def on(self, event: str, callback: Callable) -> None:
        self._listeners.setdefault(event, []).append(callback)

    def emit(self, event: str, **data) -> None:
        for callback in self._listeners.get(event, []):
            callback(**data)

emitter = EventEmitter()
emitter.on("user_created", lambda name, **_: print(f"Welcome {name}!"))
emitter.on("user_created", lambda email, **_: print(f"Sending email to {email}"))
emitter.emit("user_created", name="Alice", email="alice@test.com")
```

---

## How It Connects

SOLID principles are the design philosophy. Design patterns are the practical toolkit that implements those principles in specific situations.

[[solid-principles|SOLID Principles]]

Many patterns rely on composition over inheritance. The Strategy, Observer, Decorator, and Command patterns all compose objects rather than building inheritance hierarchies.

[[composition-over-inheritance|Composition Over Inheritance]]

Python's first-class functions make some patterns trivial. The Strategy pattern reduces to passing a function. The Command pattern reduces to storing a callable. Understanding first-class functions helps you recognize when a full class-based pattern is overkill.

[[first-class-functions|First Class Functions]]

Each individual pattern has a dedicated note that goes deeper into implementation, edge cases, and Python-specific idioms.

[[singleton|Singleton Pattern]]
[[factory-method|Factory Method Pattern]]
[[strategy-pattern|Strategy Pattern]]
[[observer-pattern|Observer Pattern]]
[[decorator-pattern|Decorator Pattern]]

---

## Common Misconceptions

Misconception 1: "Using design patterns makes code automatically better."
Reality: Patterns add abstraction layers and indirection. Applied to the right problem, they make code more flexible and maintainable. Applied to the wrong problem, they make code harder to read and navigate. The question is always: does this pattern solve a problem I actually have, or am I applying it because I know its name?

Misconception 2: "You should learn all 23 GoF patterns."
Reality: In Python, about 8-10 patterns appear frequently (Singleton, Factory, Strategy, Observer, Decorator, Iterator, Command, Adapter, Facade, Repository). Several others are rarely needed because Python's features make them unnecessary. Focus on the patterns that solve problems you encounter in your domain.

Misconception 3: "Patterns are only for object-oriented code."
Reality: The GoF patterns are described in OOP terms, but the underlying problems exist in any paradigm. The Strategy pattern (swap behavior) is a function parameter in functional programming. The Observer pattern (react to changes) is an event emitter or callback list. The Iterator pattern is a generator. Python developers use these patterns constantly, often without realizing it.

---

## Why It Matters in Practice

Design patterns are the shared vocabulary of software design. When a team member says "we need a Repository here," everyone understands the structure without a lengthy explanation. When a code review says "this is a God class - extract a Strategy," the refactoring direction is clear. Patterns accelerate design discussions by providing named, well-understood solutions.

In interviews, design pattern knowledge signals that a candidate thinks about code structure, not just code correctness. Being able to identify which pattern fits a given problem, and equally important, which pattern does not fit, demonstrates design maturity.

---

## Interview Angle

Common question forms:
- "What design patterns do you use regularly?"
- "Explain the difference between creational, structural, and behavioral patterns."
- "How does Python's dynamic typing change how you use design patterns?"
- "Design a notification system - which patterns would you use?"

Answer frame:
Categorize patterns into creational, structural, behavioral with one example each. Explain that Python simplifies many patterns (Strategy becomes a function, Iterator becomes a generator, Singleton becomes a module variable). Name the patterns you actually use and why. For design problems, identify the forces at play and match them to the pattern that addresses those forces.

---

## Related Notes

- [[solid-principles|SOLID Principles]]
- [[composition-over-inheritance|Composition Over Inheritance]]
- [[first-class-functions|First Class Functions]]
- [[singleton|Singleton Pattern]]
- [[factory-method|Factory Method Pattern]]
- [[strategy-pattern|Strategy Pattern]]
- [[observer-pattern|Observer Pattern]]
- [[decorator-pattern|Decorator Pattern]]
