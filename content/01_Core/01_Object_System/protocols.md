---
title: 09 - Protocols and Structural Subtyping
description: Protocols define interfaces through structure rather than inheritance — a class satisfies a Protocol if it has the required methods and attributes, without needing to explicitly inherit from or register with the Protocol; this is Python's form of duck typing made explicit for static type checkers.
tags: [protocols, structural-subtyping, typing, duck-typing, mypy, python-3.8, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Protocols and Structural Subtyping

> Protocols define interfaces through structure rather than inheritance — a class satisfies a Protocol if it has the required methods and attributes, without needing to explicitly inherit from or register with the Protocol; this is Python's form of duck typing made explicit for static type checkers.

---

## Quick Reference

**Core idea:**
- A `Protocol` class (from `typing`) defines an interface by listing methods and attributes — any class that has those methods/attributes satisfies the protocol, no inheritance needed
- `runtime_checkable` decorator enables `isinstance(obj, MyProtocol)` at runtime — without it, Protocols are only for static type checking
- Structural subtyping: a class is a subtype of a Protocol if its **structure** matches — contrast with ABCs (nominal subtyping: must inherit or register)
- Built-in Protocols in `typing`: `Iterable`, `Iterator`, `Sized`, `Callable`, `Hashable`, `Awaitable`, `AsyncIterable`, `ContextManager`
- `Protocol` was added in Python 3.8 (`typing.Protocol`); `typing_extensions` backports it for older versions

**Tricky points:**
- Protocol methods defined with only `...` as the body are interface requirements — they must be implemented by any satisfying class
- **Class variables** declared in a Protocol body (without assignment) are also requirements — the satisfying class must have those attributes
- `@runtime_checkable` Protocols only check for method **names**, not signatures — `isinstance(obj, MyProtocol)` does not verify argument types
- A class can explicitly inherit from a Protocol to signal intent (`class MyClass(MyProtocol):`) — this makes static type checkers flag missing methods, while still allowing structural matching
- Protocols **can** have implementation — a Protocol method with a body provides a default that satisfying classes inherit if they explicitly inherit from the Protocol

---

## What It Is

Think of a universally compatible power socket standard that any device can use without registration. If a device has the right plug shape — two prongs in the correct positions with the correct spacing — it fits the socket. The socket does not maintain a registry of approved devices. It accepts any device that physically fits. This is structural subtyping: membership is determined by structure, not by any formal registration or inheritance declaration. Python's Protocols are that socket standard: define the "plug shape" (the required methods and attributes), and any class that matches the shape satisfies the protocol.

Before Protocols, Python's duck typing was informal. "If it has `__iter__` and `__next__`, it's an iterator" was documentation convention, not enforceable. `isinstance` checks required explicit ABC inheritance or registration. Type checkers had no way to verify that a function expecting an "iterable" actually received one. Protocols formalize duck typing: you declare the required shape as a `typing.Protocol` subclass, and static type checkers (mypy, pyright) verify that values passed to Protocol-typed parameters actually match the required shape — without modifying the classes being checked.

The contrast with ABCs is the key distinction. A `collections.abc.Iterable` ABC check requires that the class either inherits from `Iterable` or explicitly calls `Iterable.register(cls)`. A `typing.Protocol` check is structural — mypy considers any class with `__iter__` to satisfy `Iterable` without any inheritance or registration. This is why third-party libraries that predate Protocols can be used with Protocol-typed APIs without modification.

---

## How It Actually Works

A Protocol is defined by subclassing `typing.Protocol`:

```python
from typing import Protocol

class Drawable(Protocol):
    def draw(self) -> None: ...
    def get_bounds(self) -> tuple[int, int, int, int]: ...
```

Any class that has `draw(self) -> None` and `get_bounds(self) -> tuple[int, int, int, int]` satisfies `Drawable` structurally. mypy will accept it as a `Drawable` argument without any inheritance declaration.

`@runtime_checkable` enables runtime `isinstance` checks:

```python
from typing import Protocol, runtime_checkable

@runtime_checkable
class Drawable(Protocol):
    def draw(self) -> None: ...
```

`isinstance(some_object, Drawable)` checks whether `some_object` has a `draw` attribute. It does not verify the signature or return type — only presence. Without `@runtime_checkable`, `isinstance(x, Drawable)` raises `TypeError`.

Protocol methods can have default implementations if they contain actual code rather than `...`. A class that explicitly inherits from a Protocol gets these defaults (via normal inheritance), while a class that only structurally satisfies the Protocol does not. This pattern allows Protocols to serve both as "interface definitions" (structural) and "mixin base classes" (nominal, for defaults).

---

## How It Connects

ABCs are the alternative interface mechanism — nominal rather than structural. ABCs require explicit inheritance or `register()` and provide runtime `isinstance` support as a core feature. The choice between ABCs and Protocols depends on whether you need runtime checks (prefer ABCs or `@runtime_checkable` Protocols) versus static-analysis-only verification (prefer Protocols).
[[abstract-base-classes|Abstract Base Classes]]

Type hints are the annotation system that Protocols integrate with. A function annotated `def render(drawable: Drawable)` is verified by mypy to only receive objects that structurally satisfy `Drawable`. Without type hints and type checkers, Protocols provide no enforcement.
[[type-hints|Type Hints]]

---

## Common Misconceptions

Misconception 1: "Protocols require explicit inheritance to work."
Reality: Protocols enable structural subtyping — no inheritance required. A class defined before Protocols existed, in a third-party library you cannot modify, satisfies a Protocol if its structure matches. This is the primary advantage over ABCs: you can define a Protocol against an existing class hierarchy without modifying any existing code.

Misconception 2: "`@runtime_checkable` Protocols are as reliable as ABC `isinstance` checks."
Reality: Runtime Protocol `isinstance` checks only verify attribute presence, not signatures, return types, or attribute types. `class Fake: draw = 42` satisfies a `@runtime_checkable` Protocol that requires `draw` — `isinstance(Fake(), Drawable)` returns True even though `Fake.draw` is an integer, not a callable. ABCs with `@abstractmethod` are stricter at the nominal level. For reliable duck typing, combine `@runtime_checkable` with explicit checking (`callable(obj.draw)`) or use static type checkers instead of runtime checks.

---

## Why It Matters in Practice

Protocols are the right tool for typing library code that should work with any "file-like object." Rather than requiring a specific base class or `io.IOBase` inheritance, define a Protocol:

```python
class Readable(Protocol):
    def read(self, n: int = -1) -> bytes: ...
    def close(self) -> None: ...
```

Any `io.BytesIO`, `http.client.HTTPResponse`, or custom class that has `read` and `close` satisfies this Protocol without modification. This is how the standard library's `io` module types many functions.

The `typing` module's built-in Protocols (`Iterable`, `Iterator`, `Callable`, `Sized`, `Hashable`, `ContextManager`) are the most commonly used. Understanding that these are structural — `def fn(items: Iterable[int])` accepts any class with `__iter__`, not just registered ABCs — is key to writing type-annotated code that is both correct and flexible.

---

## Interview Angle

Common question forms:
- "What is a Protocol in Python typing?"
- "What is structural subtyping?"
- "How do Protocols differ from ABCs?"

Answer frame: Protocols define interfaces structurally — any class with the required methods and attributes satisfies the Protocol without inheriting from it. ABCs use nominal subtyping — classes must explicitly inherit or register. Protocol is from `typing` (Python 3.8+); define by subclassing `Protocol` and listing required methods with `...` bodies. `@runtime_checkable` enables `isinstance` checks (attribute presence only). mypy/pyright verify Protocol satisfaction statically. Use ABCs for runtime enforcement and explicit interface contracts; use Protocols for flexible, non-invasive static type checking.

---

## Related Notes

- [[abstract-base-classes|Abstract Base Classes]]
- [[type-hints|Type Hints]]
- [[python-data-model|The Python Data Model]]
- [[dunder-methods|Dunder Methods]]
