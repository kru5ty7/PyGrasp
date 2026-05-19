---
title: 02 - Immutable Objects for Safety
description: Immutable objects cannot be modified after creation, eliminating race conditions in concurrent code because multiple threads can read the same data without synchronization.
tags: [concurrency, immutability, thread-safety, frozen, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Immutable Objects for Safety

> Immutable objects cannot be changed after creation, making them inherently thread-safe because concurrent reads never conflict and writes are impossible.

---

## Quick Reference

**Core idea:**
- An immutable object's state is fixed at creation time and never changes
- No locks are needed for concurrent access to immutable data - reads are always safe
- Python built-in immutables: `int`, `float`, `str`, `tuple`, `frozenset`, `bytes`
- `@dataclass(frozen=True)` creates immutable dataclass instances that raise `FrozenInstanceError` on attribute assignment
- Instead of modifying an immutable object, you create a new one with the desired changes (`dataclasses.replace()`)

**Tricky points:**
- A frozen dataclass containing a mutable field (like a `list`) is only shallowly immutable - the list contents can still change
- Immutability has a memory cost: every "modification" creates a new object (but Python reuses small ints and interns strings)
- `NamedTuple` is another way to create immutable value objects in Python
- Immutability does not mean an object is hashable - it is hashable only if all its contents are also immutable

---

## What It Is

Think of a printed book. Once published, the text on every page is fixed. A thousand people can read the same book simultaneously without any coordination - nobody can change the words while someone else is reading them. If the author wants to fix a typo, they publish a new edition (a new object) rather than sneaking into libraries and modifying existing copies. The old edition remains unchanged for everyone who has it.

Immutable objects work the same way in code. A `frozenset`, a `tuple`, or a frozen dataclass cannot be modified after creation. Any number of threads can read them simultaneously without locks, without coordination, without any possibility of race conditions. When you need a "modified" version, you create a new object with the changes applied. The original remains unchanged for any other code that references it.

This is the most powerful thread-safety strategy because it eliminates the problem at the root. Locks are a mechanism for managing shared mutable state. Immutable objects eliminate shared mutable state entirely, making locks unnecessary. The tradeoff is memory and performance: creating new objects instead of modifying existing ones uses more memory and CPU. In practice, this tradeoff is almost always worth it for data that flows through your application (configuration, events, messages, DTOs).

---

## How It Actually Works

Python's `@dataclass(frozen=True)` makes instances immutable by overriding `__setattr__` and `__delattr__` to raise `FrozenInstanceError`. The object's `__dict__` is populated during `__init__` and then locked down. `dataclasses.replace()` creates a new instance with specified fields changed, copying unchanged fields from the original.

For deeper immutability, ensure all fields are themselves immutable. A frozen dataclass with a `list` field is only surface-level immutable - the list contents can still be mutated. Use `tuple` instead of `list` and `frozenset` instead of `set` for truly deep immutability.

```python
from dataclasses import dataclass, field, replace
from typing import NamedTuple
import threading
from concurrent.futures import ThreadPoolExecutor


# Frozen dataclass - immutable value object
@dataclass(frozen=True)
class Config:
    host: str
    port: int
    debug: bool = False
    allowed_origins: tuple[str, ...] = ()  # tuple, not list!

config = Config(host="0.0.0.0", port=8080, allowed_origins=("localhost",))

# Cannot modify
try:
    config.port = 9090  # FrozenInstanceError
except AttributeError as e:
    print(f"Cannot modify: {e}")

# Create modified copy instead
new_config = replace(config, port=9090, debug=True)
print(config.port)      # 8080 - original unchanged
print(new_config.port)   # 9090 - new object


# NamedTuple - lightweight immutable value object
class Point(NamedTuple):
    x: float
    y: float

    def distance_to(self, other: "Point") -> float:
        return ((self.x - other.x) ** 2 + (self.y - other.y) ** 2) ** 0.5

p1 = Point(3, 4)
p2 = p1._replace(x=6)  # new Point, original unchanged
print(p1.distance_to(p2))  # 3.0


# Thread-safe shared config: immutable, no locks needed
@dataclass(frozen=True)
class AppState:
    version: str
    feature_flags: frozenset[str]
    rate_limit: int

# Multiple threads read without any synchronization
shared_state = AppState(
    version="1.2.0",
    feature_flags=frozenset({"dark_mode", "new_checkout"}),
    rate_limit=100,
)

def worker(thread_id: int, state: AppState) -> str:
    # Safe: state is immutable, no locks needed
    if "dark_mode" in state.feature_flags:
        return f"Thread {thread_id}: dark mode enabled (v{state.version})"
    return f"Thread {thread_id}: standard mode"

with ThreadPoolExecutor(max_workers=8) as pool:
    futures = [pool.submit(worker, i, shared_state) for i in range(8)]
    for f in futures:
        print(f.result())


# Event sourcing with immutable events
@dataclass(frozen=True)
class Event:
    type: str
    timestamp: float
    data: tuple  # immutable nested data

    @classmethod
    def create(cls, event_type: str, **data) -> "Event":
        import time
        return cls(type=event_type, timestamp=time.time(),
                   data=tuple(data.items()))

event = Event.create("user_registered", name="Alice", email="a@b.com")
print(event)


# PITFALL: shallow immutability
@dataclass(frozen=True)
class BadConfig:
    tags: list[str]  # MUTABLE field in frozen dataclass!

bad = BadConfig(tags=["a", "b"])
bad.tags.append("c")  # This works! The list is mutable.
print(bad.tags)  # ["a", "b", "c"] - immutability violated

# FIX: use immutable containers
@dataclass(frozen=True)
class GoodConfig:
    tags: tuple[str, ...]  # immutable all the way down

good = GoodConfig(tags=("a", "b"))
# good.tags.append("c")  # AttributeError - tuple has no append
```

---

<iframe src="/static/visualizers/immutable-objects.html" width="100%" height="400px" style="border:none;border-radius:6px;"></iframe>

---

## How It Connects

Immutability eliminates the root cause of race conditions. Understanding mutability and its risks is prerequisite.

[[mutability|Mutability]]

[[thread-safety-basics|Thread Safety Basics]]

Frozen dataclasses and NamedTuples are the primary tools for creating immutable objects in Python.

[[dataclasses|Dataclasses]]

[[named-tuples|Named Tuples]]

Immutable objects are inherently hashable (if all fields are hashable), making them usable as dictionary keys and set members.

[[hashing|Hashing]]

---

## Common Misconceptions

Misconception 1: "`frozen=True` makes everything immutable."
Reality: `frozen=True` prevents reassigning attributes on the dataclass instance. If an attribute is a mutable container (list, dict, set), the container's contents can still be modified. True immutability requires using immutable containers (tuple, frozenset, bytes) for all fields.

Misconception 2: "Immutable objects are always slower because you create copies."
Reality: Immutable objects avoid lock overhead in concurrent code, which can be more expensive than object creation. Python's memory allocator is fast, and small immutable objects (ints, short strings) are cached and reused. For data that flows through the system (events, messages, config), the performance difference is negligible.

---

## Why It Matters in Practice

Configuration objects, event payloads, DTOs, and value objects should almost always be immutable. These objects flow through multiple layers of your application and may be accessed by multiple threads. Making them immutable eliminates an entire class of bugs without requiring any synchronization code.

Immutable objects also make debugging easier. When you know an object cannot change after creation, you can examine it at any point in the debugger and trust that its state is the same as when it was created.

---

## Interview Angle

Common question forms:
- "How does immutability help with thread safety?"
- "How do you create immutable objects in Python?"
- "What is the difference between shallow and deep immutability?"

Answer frame:
Define immutability as state fixed at creation time. Explain that concurrent reads are always safe on immutable data (no locks needed). Show `@dataclass(frozen=True)` and `NamedTuple`. Warn about shallow immutability (mutable fields in frozen dataclasses). Show `replace()` for creating modified copies.

---

## Related Notes

- [[mutability|Mutability]]
- [[thread-safety-basics|Thread Safety Basics]]
- [[dataclasses|Dataclasses]]
- [[named-tuples|Named Tuples]]
- [[hashing|Hashing]]
