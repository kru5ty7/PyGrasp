---
title: 10 - Liskov Substitution Principle
description: A subclass must be usable anywhere its parent class is expected without breaking the program's correctness - subtypes must honor the behavioral contract of their supertype.
tags: [oop, solid, lsp, substitutability, contracts, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Liskov Substitution Principle

> If S is a subtype of T, then objects of type T can be replaced with objects of type S without altering the correctness of the program.

---

## Quick Reference

**Core idea:**
- LSP says a subclass must be a **behavioral substitute** for its parent - any code that works with the parent must work identically with the child
- The child can add new behavior but must not break, weaken, or contradict the parent's behavior
- Preconditions (what the method requires) must not be **strengthened** in the child
- Postconditions (what the method guarantees) must not be **weakened** in the child
- Exceptions thrown by the child must be the same type or subtypes of what the parent throws

**Tricky points:**
- The classic Square-Rectangle problem: a `Square` "is-a" `Rectangle` mathematically, but making `Square` inherit from `Rectangle` violates LSP because `set_width()` on a square must also change the height
- LSP violations often hide behind seemingly correct inheritance hierarchies - the compiler does not catch them
- Python's duck typing means LSP applies to any object that claims to support an interface, not just formal inheritance
- An empty method override (`def method(self): pass`) that silently swallows behavior the parent performed is an LSP violation

---

## What It Is

Think of a car rental company. You reserve a "sedan" and the company gives you a Honda Civic, a Toyota Camry, or a Ford Fusion. Any sedan works because they all satisfy the sedan contract: four doors, trunk, fits four passengers, drives on regular gas. If the company substituted a "sedan" with a motorcycle (two wheels, no trunk, fits one passenger), your trip would fail even though a motorcycle is a vehicle. The motorcycle does not satisfy the sedan contract. It is a vehicle, but it is not a valid substitute for a sedan.

Liskov Substitution Principle, formulated by Barbara Liskov in 1987, states that a subtype must be substitutable for its supertype without breaking the program. If your function accepts a `Logger` parameter, it must work correctly with any subclass of `Logger` - `FileLogger`, `DatabaseLogger`, `ConsoleLogger`. If `DatabaseLogger` silently drops log messages when the database is unavailable (while `Logger.log()` is expected to always persist the message), that is an LSP violation. Code that depends on `Logger` assumes messages are persisted; `DatabaseLogger` breaks that assumption.

The principle is about **behavioral compatibility**, not just method signatures. A child class can have the same method signatures as the parent and still violate LSP if the behavior does not match the contract. A `ReadOnlyList` that inherits from `List` and raises an exception on `append()` has the right method signature but violates LSP because callers of `List` expect `append()` to work.

LSP is the principle that makes polymorphism safe. When you write polymorphic code - code that works with any object of a given type - LSP is the guarantee that any subtype will work correctly. Without LSP, polymorphic code is unreliable because you cannot predict which subtypes will break which assumptions.

---

## How It Actually Works

LSP defines four rules that a subclass must follow. First, preconditions must not be strengthened: if the parent accepts any positive integer, the child must not restrict this to even numbers only. Second, postconditions must not be weakened: if the parent guarantees a sorted result, the child must also return a sorted result. Third, invariants must be preserved: if the parent guarantees that `balance >= 0` at all times, the child must maintain this invariant. Fourth, the history constraint: the child must not introduce state changes that the parent would not allow.

In Python, LSP violations often surface as runtime errors or subtle behavior changes. Because Python lacks compile-time contract checking, you rely on tests and discipline to enforce LSP. Type checkers like mypy enforce structural compatibility (return types, parameter types) but cannot check behavioral contracts.

```python
# CLASSIC LSP VIOLATION: Square extends Rectangle

class Rectangle:
    def __init__(self, width: float, height: float):
        self._width = width
        self._height = height

    @property
    def width(self) -> float:
        return self._width

    @width.setter
    def width(self, value: float) -> None:
        self._width = value

    @property
    def height(self) -> float:
        return self._height

    @height.setter
    def height(self, value: float) -> None:
        self._height = value

    def area(self) -> float:
        return self._width * self._height


class Square(Rectangle):
    """LSP VIOLATION: overrides setters to maintain square invariant,
    but breaks the Rectangle contract."""
    def __init__(self, side: float):
        super().__init__(side, side)

    @Rectangle.width.setter
    def width(self, value: float) -> None:
        self._width = value
        self._height = value  # side effect: changes height too

    @Rectangle.height.setter
    def height(self, value: float) -> None:
        self._width = value
        self._height = value  # side effect: changes width too


def resize_rectangle(rect: Rectangle) -> None:
    """This function assumes Rectangle contract:
    setting width does NOT affect height."""
    rect.width = 10
    rect.height = 5
    assert rect.area() == 50, f"Expected 50, got {rect.area()}"

resize_rectangle(Rectangle(1, 1))  # passes
# resize_rectangle(Square(1))      # FAILS: area is 25, not 50


# LSP-COMPLIANT DESIGN: use a common abstraction without implying substitutability

from abc import ABC, abstractmethod


class Shape(ABC):
    @abstractmethod
    def area(self) -> float: ...

class LspRectangle(Shape):
    def __init__(self, width: float, height: float):
        self.width = width
        self.height = height

    def area(self) -> float:
        return self.width * self.height

class LspSquare(Shape):
    def __init__(self, side: float):
        self.side = side

    def area(self) -> float:
        return self.side ** 2

# Both are Shapes, but Square does not claim to be a Rectangle.
# No broken contracts.


# ANOTHER LSP VIOLATION: weakening postconditions

class Cache:
    def get(self, key: str) -> str | None:
        """Returns the cached value, or None if not found.
        Guaranteed to never raise an exception."""
        return self._store.get(key)

class StrictCache(Cache):
    def get(self, key: str) -> str | None:
        """LSP VIOLATION: strengthens precondition by raising on empty key."""
        if not key:
            raise ValueError("Key must not be empty")  # parent allows empty keys
        return self._store.get(key)


# LSP-COMPLIANT: child honors parent's contract
class RedisCache(Cache):
    def __init__(self, host: str):
        self._host = host
        self._store: dict[str, str] = {}

    def get(self, key: str) -> str | None:
        """Honors contract: returns value or None, never raises."""
        try:
            return self._store.get(key)
        except Exception:
            return None  # degrades gracefully, does not raise
```

---

## Visualizer

<iframe src="/static/visualizers/lsp.html" style="width:100%;height:460px;border:none;border-radius:8px;" title="Liskov Substitution Principle Visualizer"></iframe>

---

## How It Connects

LSP is the principle that makes inheritance safe. Without it, polymorphic code that accepts a parent type cannot trust that child types will behave correctly.

[[inheritance-oop|Inheritance]]

[[polymorphism|Polymorphism]]

LSP violations often indicate that composition would be a better fit than inheritance. The Square-Rectangle problem goes away when Square and Rectangle are siblings under Shape rather than parent-child.

[[composition-over-inheritance|Composition Over Inheritance]]

LSP is one of five SOLID principles. It interacts closely with OCP: if subtypes violate LSP, code that tries to be open for extension breaks when extended with misbehaving subtypes.

[[solid-principles|SOLID Principles]]

[[ocp|Open/Closed Principle]]

---

## Common Misconceptions

Misconception 1: "If the child class has all the same methods as the parent, it satisfies LSP."
Reality: LSP is about behavioral compatibility, not just structural compatibility. A `ReadOnlyList` that inherits from `List` and raises `NotImplementedError` on `append()` has the right methods but violates LSP because callers expect `append()` to work. Method signatures are necessary but not sufficient.

Misconception 2: "LSP means child classes cannot override parent methods."
Reality: Child classes are expected to override methods - that is the point of inheritance. LSP says the overridden method must honor the parent's contract. It can add behavior, return a more specific type, or accept broader inputs. It must not strengthen preconditions, weaken postconditions, or violate invariants.

Misconception 3: "The Square-Rectangle problem is just academic and does not happen in real code."
Reality: The pattern appears frequently in practice. A `ReadOnlyFile` that inherits from `File` and raises on `write()`. A `GuestUser` that inherits from `User` and cannot change its email. A `FreeAccount` that inherits from `Account` and silently ignores `upgrade()`. These are all real-world LSP violations that cause bugs when polymorphic code assumes the parent's contract holds.

---

## Why It Matters in Practice

LSP violations create bugs that are hard to reproduce because they only surface when a specific subtype is used in a specific context. Your test suite might pass with `FileLogger`, but production uses `BufferedFileLogger` (which silently loses messages when the buffer is full), and you miss critical log entries during an incident. The code "works" with the parent type and breaks silently with the child type.

LSP violations also make code reviews misleading. A reviewer sees a class that inherits from a well-tested parent and assumes it works the same way. The subtle behavioral difference - a weakened postcondition, a new exception type, a silently dropped operation - is easy to miss in review but catastrophic in production.

---

## Interview Angle

Common question forms:
- "What is the Liskov Substitution Principle?"
- "Explain the Square-Rectangle problem."
- "How do you detect LSP violations in Python?"
- "Give a real-world example of an LSP violation."

Answer frame:
State the principle: subtypes must be substitutable for their supertypes. Walk through the Square-Rectangle example showing how setting width on a square breaks the rectangle contract. List the rules: no stronger preconditions, no weaker postconditions, preserved invariants. Explain that Python does not enforce LSP at compile time, so tests and discipline are the primary safeguards. Suggest composition as the fix when an inheritance hierarchy violates LSP.

---

## Related Notes

- [[inheritance-oop|Inheritance]]
- [[polymorphism|Polymorphism]]
- [[composition-over-inheritance|Composition Over Inheritance]]
- [[solid-principles|SOLID Principles]]
- [[ocp|Open/Closed Principle]]
- [[oop-basics|OOP Basics]]
