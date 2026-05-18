---
title: 11 - Strategy Pattern
description: The Strategy pattern defines a family of interchangeable algorithms encapsulated in separate objects, letting you swap behavior at runtime without modifying the context that uses it.
tags: [design-patterns, strategy, behavioral, algorithms, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Strategy Pattern

> The Strategy pattern encapsulates interchangeable algorithms behind a common interface, letting the client switch behavior at runtime by swapping the strategy object.

---

## Quick Reference

**Core idea:**
- Extract varying behavior into **strategy objects** (or functions) that implement a common interface
- The **context** holds a reference to a strategy and delegates the varying behavior to it
- Eliminates conditionals: instead of if-elif chains that select behavior, swap the strategy object
- In Python, first-class functions are the simplest strategy implementation - pass a function instead of creating a class
- Directly implements the Open/Closed Principle: new strategies require no changes to existing code

**Tricky points:**
- In Python, passing a function is often simpler than creating a strategy class - use classes only when the strategy has state
- The context should not know which concrete strategy it holds - it works through the interface
- Strategies must have the same interface (or Protocol signature) to be interchangeable
- Do not create a Strategy pattern for behavior that will never vary - that is YAGNI

---

## What It Is

Think of a navigation app that offers different route options: fastest route, shortest route, scenic route, avoid-tolls route. The core navigation logic (display map, track position, show turns) is the same regardless of route type. Only the route calculation algorithm differs. You do not build four separate navigation apps. You build one app that accepts a routing algorithm as a parameter. Switching from "fastest" to "scenic" swaps the algorithm without changing anything else.

The Strategy pattern works the same way in code. You identify the behavior that varies and extract it into interchangeable objects. A payment system might use different pricing strategies: flat rate, percentage, tiered. A compression utility might use different algorithms: gzip, bzip2, lzma. A sorting function might use different comparison strategies: alphabetical, by date, by size. Each strategy implements the same interface, and the context uses whichever strategy it is given.

In Python, the simplest strategy is a function. Python's built-in `sorted()` function uses the Strategy pattern via its `key` parameter: `sorted(users, key=lambda u: u.age)`. The sorting algorithm (Timsort) is the context. The key function is the strategy. You swap strategies by passing different key functions.

---

## How It Actually Works

The context stores a reference to the current strategy (a function or object). When the context needs the varying behavior, it calls the strategy. Strategies implement the same interface (same function signature, or same Protocol methods). The client configures the context with the desired strategy.

```python
from typing import Protocol, Callable


# Approach 1: Function-based strategy (most Pythonic)
def price_flat(amount: float) -> float:
    """Flat fee of $2.99."""
    return amount + 2.99

def price_percentage(amount: float) -> float:
    """2.5% fee."""
    return amount * 1.025

def price_tiered(amount: float) -> float:
    """Tiered: 1% under $100, 0.5% over."""
    if amount < 100:
        return amount * 1.01
    return amount * 1.005


class PaymentProcessor:
    def __init__(self, pricing_strategy: Callable[[float], float]):
        self._pricing = pricing_strategy

    def process(self, amount: float) -> float:
        total = self._pricing(amount)
        print(f"Charged: ${total:.2f} (original: ${amount:.2f})")
        return total

# Swap strategies at construction time
processor = PaymentProcessor(price_flat)
processor.process(50.0)   # $52.99

processor = PaymentProcessor(price_percentage)
processor.process(50.0)   # $51.25


# Approach 2: Class-based strategy (when strategy has state)
class ShippingStrategy(Protocol):
    def calculate(self, weight_kg: float, distance_km: float) -> float: ...

class StandardShipping:
    def calculate(self, weight_kg: float, distance_km: float) -> float:
        return weight_kg * 0.5 + distance_km * 0.01

class ExpressShipping:
    def calculate(self, weight_kg: float, distance_km: float) -> float:
        return (weight_kg * 0.5 + distance_km * 0.01) * 2.5

class FreeShipping:
    def __init__(self, min_order: float):
        self.min_order = min_order
        self._fallback = StandardShipping()

    def calculate(self, weight_kg: float, distance_km: float) -> float:
        return 0.0  # free regardless of weight/distance


class Order:
    def __init__(self, items: list[dict], shipping: ShippingStrategy):
        self.items = items
        self._shipping = shipping

    @property
    def subtotal(self) -> float:
        return sum(i["price"] * i["quantity"] for i in self.items)

    def total(self, weight_kg: float, distance_km: float) -> float:
        shipping_cost = self._shipping.calculate(weight_kg, distance_km)
        return self.subtotal + shipping_cost

    def change_shipping(self, strategy: ShippingStrategy) -> None:
        """Swap strategy at runtime."""
        self._shipping = strategy


items = [{"price": 25.0, "quantity": 2}, {"price": 15.0, "quantity": 1}]

order = Order(items, StandardShipping())
print(f"Standard: ${order.total(2.0, 500):.2f}")  # 65 + 6.0 = 71.00

order.change_shipping(ExpressShipping())
print(f"Express: ${order.total(2.0, 500):.2f}")    # 65 + 15.0 = 80.00

order.change_shipping(FreeShipping(min_order=50))
print(f"Free: ${order.total(2.0, 500):.2f}")        # 65 + 0 = 65.00


# Real-world: Python's sorted() is Strategy pattern
users = [
    {"name": "Charlie", "age": 30},
    {"name": "Alice", "age": 25},
    {"name": "Bob", "age": 35},
]

by_name = sorted(users, key=lambda u: u["name"])
by_age = sorted(users, key=lambda u: u["age"])
by_age_desc = sorted(users, key=lambda u: u["age"], reverse=True)
```

---

## How It Connects

Strategy is the most direct implementation of the Open/Closed Principle. New strategies are new classes or functions. The context never changes.

[[ocp|Open/Closed Principle]]

[[design-patterns-overview|Design Patterns Overview]]

Strategy uses composition: the context holds a strategy object. This is the canonical example of composition over inheritance for varying behavior.

[[composition-over-inheritance|Composition Over Inheritance]]

In Python, strategies are often plain functions thanks to first-class functions. Understanding closures helps when strategies need to capture state.

[[first-class-functions|First Class Functions]]

[[closures|Closures]]

---

## Common Misconceptions

Misconception 1: "You always need a Strategy class hierarchy."
Reality: In Python, a function parameter is the simplest strategy. Use a class only when the strategy has internal state or multiple methods. `sorted(data, key=func)` is strategy without any classes.

Misconception 2: "Strategy and State patterns are the same."
Reality: Both swap behavior objects, but Strategy lets the client choose the algorithm. State lets the object change its own behavior based on internal state transitions. Strategy is external selection; State is internal transitions.

---

## Why It Matters in Practice

Strategy eliminates the if-elif chains that grow with every new behavior variant. Every time you add a new elif branch to a pricing function, a shipping calculator, or a validation pipeline, you are missing an opportunity for Strategy. The pattern makes each variant independently testable and the context immune to variant changes.

---

## Interview Angle

Common question forms:
- "What is the Strategy pattern?"
- "Refactor this if-elif chain using Strategy."
- "How does Python make the Strategy pattern simpler than Java?"

Answer frame:
Define Strategy as interchangeable algorithms behind a common interface. Show the if-elif before and the strategy-based after. Demonstrate both function-based and class-based approaches. Mention `sorted(key=...)` as a built-in example. Connect to OCP.

---

## Related Notes

- [[ocp|Open/Closed Principle]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[composition-over-inheritance|Composition Over Inheritance]]
- [[first-class-functions|First Class Functions]]
- [[closures|Closures]]
