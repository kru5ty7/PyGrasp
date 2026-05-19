---
title: 08 - Decorator Pattern
description: The Decorator pattern attaches additional behavior to an object dynamically by wrapping it in another object with the same interface, providing a flexible alternative to subclassing for extending functionality.
tags: [design-patterns, decorator, structural, wrapper, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Decorator Pattern

> The Decorator pattern wraps an object to add behavior dynamically while preserving the original interface, allowing you to layer responsibilities without modifying the original class.

---

## Quick Reference

**Core idea:**
- A decorator wraps an object, implements the same interface, and adds behavior before/after delegating to the wrapped object
- Decorators are stackable: wrap with logging, then wrap that with caching, then wrap that with retry
- Unlike inheritance, decorators are applied at runtime and can be combined in any order
- Python has two related concepts: the **GoF Decorator pattern** (wrapping objects) and **Python decorators** (`@decorator` syntax for wrapping functions)
- Python's `@decorator` syntax is a specific implementation of the GoF Decorator pattern for functions and methods

**Tricky points:**
- Each decorator must implement the same interface as the wrapped object - otherwise the chain breaks
- Too many stacked decorators create deep call chains that are hard to debug (stack traces are long and confusing)
- Python function decorators and the GoF Decorator pattern solve the same problem at different levels: functions vs objects
- `functools.wraps` is essential for Python function decorators to preserve the original function's metadata

---

## What It Is

Think of gift wrapping. You have a book (the core object). You wrap it in tissue paper (adds padding). Then you put it in a decorative box (adds presentation). Then you tie a ribbon around it (adds visual flair). Each layer adds something without changing the book. Each layer has the same shape - it is still a rectangular package you can hand to someone. You can add or remove layers independently. The tissue paper does not know about the ribbon. The box does not know about the tissue paper.

The Decorator pattern works the same way. You have a core object that does something useful. You wrap it in another object that adds logging. You wrap that in another object that adds caching. You wrap that in another object that adds retry logic. Each wrapper implements the same interface as the core, so the caller does not know how many layers are present. Each wrapper adds its behavior and delegates to the next layer.

Python's `@decorator` syntax is the language's built-in support for this pattern at the function level. When you write `@timed` above a function, Python replaces the function with a wrapper that measures execution time and then calls the original. When you write `@retry(max_attempts=3)`, you get a wrapper that catches exceptions and retries. These decorators compose: `@timed @retry @log_calls` layers three behaviors on a single function.

The GoF version operates on objects rather than functions. A `LoggingRepository` wraps a `Repository`, implements the same interface, logs each call, and delegates to the real repository. A `CachingRepository` wraps a `Repository`, checks a cache before delegating. You can stack them: `CachingRepository(LoggingRepository(PostgresRepository()))`.

---

## How It Actually Works

A function decorator in Python is a callable that takes a function and returns a new function. The `@` syntax is syntactic sugar: `@decorator def f(): ...` is equivalent to `f = decorator(f)`. The `functools.wraps` decorator copies the original function's `__name__`, `__doc__`, and `__module__` to the wrapper, so introspection tools and documentation generators see the original function's metadata.

An object decorator implements the same interface as the wrapped object. It stores a reference to the wrapped object, adds behavior in its methods, and delegates to the wrapped object for the core logic.

```python
import functools
import time
from typing import Any, Callable, Protocol


# 1. Python function decorators (most common form)
def timed(func: Callable) -> Callable:
    """Measures execution time."""
    @functools.wraps(func)
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f"{func.__name__} took {elapsed:.4f}s")
        return result
    return wrapper

def retry(max_attempts: int = 3, delay: float = 1.0):
    """Retries on failure with exponential backoff."""
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_attempts:
                        raise
                    wait = delay * (2 ** (attempt - 1))
                    print(f"Attempt {attempt} failed: {e}, retrying in {wait}s")
                    time.sleep(wait)
        return wrapper
    return decorator

@timed
@retry(max_attempts=3, delay=0.1)
def fetch_data(url: str) -> str:
    """Fetch data from URL."""
    return f"data from {url}"

result = fetch_data("https://api.example.com")
# Preserves original metadata thanks to @functools.wraps
print(fetch_data.__name__)  # "fetch_data", not "wrapper"


# 2. GoF Object Decorator - same interface, added behavior
class DataSource(Protocol):
    def read(self) -> str: ...
    def write(self, data: str) -> None: ...


class FileDataSource:
    """Core component."""
    def __init__(self, path: str):
        self._path = path
        self._data = ""

    def read(self) -> str:
        return self._data

    def write(self, data: str) -> None:
        self._data = data
        print(f"Written to {self._path}: {data[:50]}...")


class EncryptionDecorator:
    """Adds encryption. Same interface, wraps another DataSource."""
    def __init__(self, source: DataSource):
        self._source = source

    def read(self) -> str:
        data = self._source.read()
        return self._decrypt(data)

    def write(self, data: str) -> None:
        encrypted = self._encrypt(data)
        self._source.write(encrypted)

    def _encrypt(self, data: str) -> str:
        return "".join(chr(ord(c) + 1) for c in data)  # simple shift

    def _decrypt(self, data: str) -> str:
        return "".join(chr(ord(c) - 1) for c in data)


class CompressionDecorator:
    """Adds compression. Same interface, wraps another DataSource."""
    def __init__(self, source: DataSource):
        self._source = source

    def read(self) -> str:
        data = self._source.read()
        return self._decompress(data)

    def write(self, data: str) -> None:
        compressed = self._compress(data)
        self._source.write(compressed)

    def _compress(self, data: str) -> str:
        return f"[compressed:{len(data)}]{data}"

    def _decompress(self, data: str) -> str:
        if data.startswith("[compressed:"):
            return data.split("]", 1)[1]
        return data


# Stack decorators: file -> encryption -> compression
source = CompressionDecorator(
    EncryptionDecorator(
        FileDataSource("secret.dat")
    )
)

source.write("sensitive user data")
print(source.read())  # "sensitive user data" - unwrapped automatically
```

<iframe src="/static/visualizers/decorator-pattern.html" width="100%" height="460px" style="border:none;border-radius:6px;" title="Decorator Pattern Visualizer"></iframe>

---

## How It Connects

Python's `@decorator` syntax is syntactic sugar built on first-class functions. Understanding how decorators work requires understanding closures, first-class functions, and `functools.wraps`.

[[decorators|Decorators]]

[[closures|Closures]]

[[first-class-functions|First Class Functions]]

The Decorator pattern is a structural pattern based on composition. Each decorator composes the wrapped object rather than inheriting from it.

[[design-patterns-overview|Design Patterns Overview]]

[[composition-over-inheritance|Composition Over Inheritance]]

---

## Common Misconceptions

Misconception 1: "Python's `@decorator` and the GoF Decorator pattern are different things."
Reality: They solve the same problem at different levels. Python's `@decorator` wraps functions. The GoF Decorator wraps objects. Both add behavior to an existing entity without modifying it, preserving the original interface. Python's `@decorator` is a language-level implementation of the GoF concept.

Misconception 2: "You should always use decorators instead of subclassing to add behavior."
Reality: Decorators are best for cross-cutting concerns (logging, caching, retry, timing) that apply to many different objects. For behavior that is intrinsic to a type (a `PremiumUser` has different pricing than a `User`), inheritance or composition is more appropriate. Use decorators when the added behavior is orthogonal to the core behavior.

---

## Why It Matters in Practice

Python function decorators are one of the most frequently used language features. `@app.route()` in Flask, `@pytest.fixture` in pytest, `@property` in Python itself, `@login_required` in Django - these are all decorator pattern applications. Understanding how they work (a function that takes a function and returns a function) is essential for using and writing them correctly.

The object decorator pattern appears in middleware stacks, I/O wrappers, and instrumentation layers. Python's `io` module uses it: `BufferedReader` wraps a `RawIOBase`, adding buffering without changing the read interface.

---

## Interview Angle

Common question forms:
- "What is the Decorator pattern?"
- "Implement a retry decorator in Python."
- "What is the difference between inheritance and the Decorator pattern?"
- "How does `functools.wraps` work and why is it needed?"

Answer frame:
Define decorator as same-interface wrapper that adds behavior. Show both function decorator (`@timed`) and object decorator (`LoggingRepository`). Explain composability (stack multiple decorators). Distinguish from inheritance (runtime vs compile-time, combinatorial vs linear). Mention `functools.wraps` for preserving metadata.

---

## Related Notes

- [[decorators|Decorators]]
- [[closures|Closures]]
- [[first-class-functions|First Class Functions]]
- [[design-patterns-overview|Design Patterns Overview]]
- [[composition-over-inheritance|Composition Over Inheritance]]
