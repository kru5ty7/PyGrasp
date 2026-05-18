---
title: 02 - Singleton Pattern
description: The Singleton pattern ensures a class has only one instance and provides a global access point to it, used for shared resources like configuration, connection pools, and loggers.
tags: [design-patterns, singleton, creational, metaclass, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Singleton Pattern

> The Singleton pattern restricts a class to a single instance, ensuring that all code shares the same object for a given resource.

---

## Quick Reference

**Core idea:**
- Singleton ensures exactly **one instance** of a class exists throughout the application
- Every call to the constructor returns the same instance rather than creating a new one
- Common uses: configuration managers, database connection pools, logging handlers, caches
- In Python, **modules are natural singletons** - importing a module twice returns the same module object
- Python offers multiple implementation approaches: `__new__` override, metaclass, module-level instance, decorator

**Tricky points:**
- Singletons are essentially global state - they make code harder to test because you cannot easily substitute a different instance
- Thread safety is a concern: two threads creating the singleton simultaneously might produce two instances
- Singletons create hidden dependencies - a function that uses `Config.instance()` depends on global state that is not visible in its parameter list
- In Python, a module-level instance or `functools.lru_cache` is almost always simpler than a class-based singleton
- Overusing singletons is a design smell - if everything is a singleton, your architecture is a bag of global variables

---

## What It Is

Think of a country's central bank. There is exactly one central bank. Every financial institution that needs to interact with monetary policy talks to the same central bank. You do not create a new central bank for each interaction. The central bank is created once, and every reference to "the central bank" points to the same institution. If the central bank updates the interest rate, every institution sees the new rate because they all share the same source.

The Singleton pattern applies this idea to objects. Some resources should have exactly one instance: a configuration loader that reads settings from a file (you want one consistent view of the config), a database connection pool (you want to reuse connections, not create new pools), a logger (you want all log messages to go through the same handler configuration). The Singleton pattern guarantees that calling `Config()` always returns the same object, no matter how many times it is called from different parts of the code.

In Python, the simplest singleton is a module. When you `import config`, Python loads the module once and caches it. Every subsequent `import config` returns the same module object. A module-level variable `settings = load_settings()` is initialized once and shared everywhere. This is idiomatic Python and often the right choice. The class-based Singleton pattern is needed when you want lazy initialization (create the instance only when first accessed), when you need inheritance, or when the singleton needs methods and a constructor.

The downside of singletons is testability. When a function calls `Database.instance()` internally, you cannot pass a test double. The function has a hidden dependency on global state. This is why many experienced developers prefer dependency injection over singletons: pass the database connection as a parameter, and the caller decides whether to pass a real database or a test fake.

---

## How It Actually Works

The classic Python singleton overrides `__new__` to control object creation. Since `__new__` is called before `__init__`, it can check whether an instance already exists and return it instead of creating a new one. The instance is stored as a class variable.

A metaclass-based singleton is cleaner for multiple singleton classes. The metaclass overrides `__call__`, which is the method that Python invokes when you call a class (e.g., `Config()`). The metaclass checks whether an instance exists and returns it or creates a new one.

For thread safety, you need a lock around the instance check-and-create operation. Without a lock, two threads could both see that the instance does not exist and both create one.

```python
import threading
from typing import Any


# Approach 1: __new__ override (simplest class-based)
class SingletonNew:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self, value: str = "default"):
        self.value = value  # WARNING: __init__ runs every time


s1 = SingletonNew("first")
s2 = SingletonNew("second")
print(s1 is s2)       # True - same object
print(s1.value)        # "second" - __init__ ran twice, overwriting


# Approach 2: Metaclass (cleaner, reusable)
class SingletonMeta(type):
    _instances: dict[type, Any] = {}
    _lock: threading.Lock = threading.Lock()

    def __call__(cls, *args, **kwargs):
        with cls._lock:  # thread-safe
            if cls not in cls._instances:
                instance = super().__call__(*args, **kwargs)
                cls._instances[cls] = instance
        return cls._instances[cls]


class Config(metaclass=SingletonMeta):
    def __init__(self):
        self.settings: dict[str, Any] = {}
        self._loaded = False

    def load(self, path: str) -> None:
        if not self._loaded:
            # Simulate loading from file
            self.settings = {"db_host": "localhost", "db_port": 5432}
            self._loaded = True
            print(f"Config loaded from {path}")

    def get(self, key: str, default: Any = None) -> Any:
        return self.settings.get(key, default)


c1 = Config()
c1.load("config.yaml")
c2 = Config()
print(c1 is c2)                    # True
print(c2.get("db_host"))           # "localhost" - same instance


# Approach 3: Module-level singleton (most Pythonic)
# In config.py:
# _settings = None
# def get_settings():
#     global _settings
#     if _settings is None:
#         _settings = load_from_file("config.yaml")
#     return _settings


# Approach 4: functools.cache (Python 3.9+)
from functools import cache

class DatabasePool:
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        print(f"Pool created for {host}:{port}")

@cache
def get_pool() -> DatabasePool:
    """Called many times, creates pool only once."""
    return DatabasePool("localhost", 5432)

p1 = get_pool()
p2 = get_pool()
print(p1 is p2)  # True - cached


# WHY SINGLETONS HURT TESTABILITY
class BadService:
    def process(self, data: str) -> str:
        config = Config()  # hidden dependency on global state
        db_host = config.get("db_host")
        return f"Processed {data} via {db_host}"

# BETTER: dependency injection
class GoodService:
    def __init__(self, config: Config):
        self._config = config  # explicit dependency, injectable

    def process(self, data: str) -> str:
        db_host = self._config.get("db_host")
        return f"Processed {data} via {db_host}"
```

---

## How It Connects

The Singleton pattern controls object creation, which is the domain of creational patterns. It is the simplest creational pattern but also the most controversial due to its global-state nature.

[[design-patterns-overview|Design Patterns Overview]]

Singletons are often replaced by dependency injection in well-designed systems. DI provides the same "shared instance" benefit without the hidden dependency problem.

[[dependency-injection-pattern|Dependency Injection Pattern]]

[[dip|Dependency Inversion Principle]]

Python's metaclass system is the cleanest way to implement a reusable Singleton. Understanding metaclasses helps you see how `SingletonMeta.__call__` intercepts object creation.

[[metaclasses|Metaclasses]]

Thread safety is critical for singletons in concurrent applications. Without proper locking, the check-and-create logic is a race condition.

[[race-conditions|Race Conditions]]

[[locks|Locks]]

---

## Common Misconceptions

Misconception 1: "Singletons are always bad."
Reality: Singletons are appropriate when an object truly represents a unique resource: a hardware device driver, a connection pool, an application-wide configuration. The problems arise when singletons are used as a convenient way to avoid passing dependencies, turning them into global variables with a class wrapper.

Misconception 2: "A module-level variable is not a singleton."
Reality: In Python, a module-level variable is effectively a singleton. The module is loaded once, the variable is initialized once, and every import returns the same module. This is often the best way to implement a singleton in Python - no metaclass, no `__new__` override, no thread-safety concerns beyond the import lock.

Misconception 3: "Singletons are thread-safe by default."
Reality: A naive `__new__` override without locking is not thread-safe. Two threads can both evaluate `cls._instance is None` as True before either creates the instance. The metaclass approach with `threading.Lock()` fixes this race condition.

---

## Why It Matters in Practice

Connection pools, configuration managers, and logging handlers are the most common legitimate uses of singletons in Python applications. Creating a new database connection pool for every request would exhaust database connections within seconds. A singleton pool is shared across all requests, managing connection reuse and limits.

The tension between singleton convenience and testability is a real architectural decision. Many teams use singletons for infrastructure (connection pools, caches) but use dependency injection for business logic. Understanding both approaches and when to use each is essential for building maintainable applications.

---

## Interview Angle

Common question forms:
- "What is the Singleton pattern and when would you use it?"
- "Implement a thread-safe singleton in Python."
- "What are the downsides of singletons?"
- "How does Python's module system relate to singletons?"

Answer frame:
Define singleton as one instance with global access. Show the metaclass implementation with thread safety. Explain the testability problem (hidden dependencies, cannot substitute in tests). Present the module-level alternative as the Pythonic approach. Discuss when singletons are appropriate (connection pools, config) vs when DI is better (business logic dependencies).

---

## Related Notes

- [[design-patterns-overview|Design Patterns Overview]]
- [[dependency-injection-pattern|Dependency Injection Pattern]]
- [[dip|Dependency Inversion Principle]]
- [[metaclasses|Metaclasses]]
- [[race-conditions|Race Conditions]]
- [[locks|Locks]]
