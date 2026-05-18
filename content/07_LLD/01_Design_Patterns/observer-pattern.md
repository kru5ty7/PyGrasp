---
title: 10 - Observer Pattern
description: The Observer pattern defines a one-to-many dependency between objects so that when one object changes state, all its dependents are notified and updated automatically.
tags: [design-patterns, observer, behavioral, events, pub-sub, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Observer Pattern

> The Observer pattern lets an object notify multiple dependents automatically when its state changes, without the object knowing who its dependents are.

---

## Quick Reference

**Core idea:**
- **Subject** (observable) maintains a list of **observers** and notifies them when its state changes
- Observers register and unregister dynamically - the subject does not know their concrete types
- Decouples the object that changes from the objects that react to the change
- Python implementation: callback lists, event emitters, `signal` libraries, or built-in `__set_name__` descriptors
- Common in Python: Django signals, GUI event handlers, message broker consumers, reactive systems

**Tricky points:**
- Notification order is typically undefined - observers should not depend on being notified before or after other observers
- Memory leaks: if observers are not unregistered, the subject holds references that prevent garbage collection
- Cascading updates: observer A's reaction triggers observer B, which triggers observer C - can create infinite loops
- In Python, weak references (`weakref`) can prevent the memory leak problem

---

## What It Is

Think of a newspaper subscription. The newspaper publisher does not know who all its subscribers are personally. Subscribers sign up and cancel independently. When a new edition is published, every current subscriber receives a copy. The publisher does not call each subscriber individually - it has a distribution list, and adding or removing a subscriber does not require changing the publishing process. The publisher is the subject. The subscribers are the observers.

The Observer pattern implements this in code. A `StockTicker` holds the current price. Multiple components need to react when the price changes: a chart widget updates, an alert system checks thresholds, a log system records the change. Without Observer, the `StockTicker` would need to know about all these components and call their methods directly. With Observer, each component registers a callback, and the `StockTicker` notifies all registered callbacks when the price changes. Adding a new component (a mobile notification) means registering a new callback - the `StockTicker` is never modified.

In Python, the Observer pattern is often implemented as an event emitter with callback functions rather than observer classes. This is more Pythonic because functions are first-class objects. Instead of creating an `Observer` interface with an `update()` method, you register plain functions as callbacks.

---

## How It Actually Works

The subject maintains a dictionary mapping event names to lists of callback functions. When state changes, it iterates through the relevant callbacks and calls each one. Observers register by passing a callback function to the subject's `subscribe()` or `on()` method and unregister by calling `unsubscribe()` or `off()`.

```python
from typing import Any, Callable
from collections import defaultdict
import weakref


class EventEmitter:
    """Generic observer/event system."""

    def __init__(self):
        self._listeners: dict[str, list[Callable]] = defaultdict(list)

    def on(self, event: str, callback: Callable) -> Callable:
        """Register a callback for an event. Returns the callback for use as decorator."""
        self._listeners[event].append(callback)
        return callback

    def off(self, event: str, callback: Callable) -> None:
        """Unregister a callback."""
        self._listeners[event].remove(callback)

    def emit(self, event: str, **data: Any) -> None:
        """Notify all listeners of an event."""
        for callback in self._listeners.get(event, []):
            callback(**data)


# Usage: Stock price tracker
class StockTicker(EventEmitter):
    def __init__(self, symbol: str, price: float):
        super().__init__()
        self.symbol = symbol
        self._price = price

    @property
    def price(self) -> float:
        return self._price

    @price.setter
    def price(self, new_price: float) -> None:
        old_price = self._price
        self._price = new_price
        self.emit("price_changed",
                  symbol=self.symbol,
                  old_price=old_price,
                  new_price=new_price)


# Observers are plain functions - no interface to implement
def log_price_change(symbol: str, old_price: float, new_price: float) -> None:
    direction = "up" if new_price > old_price else "down"
    print(f"[LOG] {symbol}: ${old_price:.2f} -> ${new_price:.2f} ({direction})")

def alert_on_drop(symbol: str, old_price: float, new_price: float) -> None:
    pct_change = (new_price - old_price) / old_price * 100
    if pct_change < -5:
        print(f"[ALERT] {symbol} dropped {abs(pct_change):.1f}%!")

def update_chart(symbol: str, new_price: float, **_) -> None:
    print(f"[CHART] Plotting {symbol} at ${new_price:.2f}")


# Register observers
ticker = StockTicker("AAPL", 150.0)
ticker.on("price_changed", log_price_change)
ticker.on("price_changed", alert_on_drop)
ticker.on("price_changed", update_chart)

# Price changes notify all observers automatically
ticker.price = 155.0   # LOG + CHART (no alert, price went up)
ticker.price = 140.0   # LOG + ALERT + CHART (dropped > 5%)

# Unregister an observer
ticker.off("price_changed", alert_on_drop)
ticker.price = 130.0   # LOG + CHART only (alert unregistered)


# Class-based observer with Protocol (when observers need state)
from typing import Protocol

class PriceObserver(Protocol):
    def on_price_change(self, symbol: str, price: float) -> None: ...

class PortfolioTracker:
    def __init__(self):
        self.holdings: dict[str, float] = {"AAPL": 10}

    def on_price_change(self, symbol: str, price: float) -> None:
        if symbol in self.holdings:
            value = self.holdings[symbol] * price
            print(f"[PORTFOLIO] {symbol}: {self.holdings[symbol]} shares = ${value:.2f}")

class TradingBot:
    def __init__(self, buy_threshold: float):
        self._threshold = buy_threshold

    def on_price_change(self, symbol: str, price: float) -> None:
        if price < self._threshold:
            print(f"[BOT] BUY signal for {symbol} at ${price:.2f}")
```

---

## How It Connects

The Observer pattern is the behavioral counterpart to the event-driven architecture pattern used in messaging systems and microservices.

[[design-patterns-overview|Design Patterns Overview]]

[[pub-sub-pattern|Pub Sub Pattern]]

Observer decouples the subject from its observers, following the Dependency Inversion Principle. The subject depends on an abstract callback interface, not on concrete observer classes.

[[dip|Dependency Inversion Principle]]

Django's signal system (`pre_save`, `post_save`, `request_started`) is a real-world Observer implementation that lets apps react to framework events without modifying framework code.

[[composition-over-inheritance|Composition Over Inheritance]]

---

## Common Misconceptions

Misconception 1: "Observer and Pub/Sub are the same thing."
Reality: Observer is a direct notification pattern - the subject knows its observers (it holds references to them). Pub/Sub adds a broker between publishers and subscribers - neither side knows about the other. Observer is synchronous and in-process. Pub/Sub is often asynchronous and cross-process.

Misconception 2: "Observers should always be notified synchronously."
Reality: Synchronous notification blocks the subject until all observers finish. For long-running reactions (sending emails, writing to databases), asynchronous notification (via a task queue or asyncio) is more appropriate. The pattern itself is agnostic to sync vs async.

---

## Why It Matters in Practice

Observer is the foundation of event-driven systems, GUI frameworks, and reactive programming. Django signals, Flask's `before_request`/`after_request` hooks, and asyncio's event loop all use observer-like patterns. Understanding Observer helps you design systems where components react to changes without being tightly coupled.

---

## Interview Angle

Common question forms:
- "What is the Observer pattern?"
- "How would you implement an event system in Python?"
- "What is the difference between Observer and Pub/Sub?"

Answer frame:
Define Observer as one-to-many notification. Show the event emitter implementation with callback functions. Explain the decoupling benefit. Distinguish from Pub/Sub (direct vs brokered). Mention Django signals as a real-world example.

---

## Related Notes

- [[design-patterns-overview|Design Patterns Overview]]
- [[pub-sub-pattern|Pub Sub Pattern]]
- [[dip|Dependency Inversion Principle]]
- [[composition-over-inheritance|Composition Over Inheritance]]
