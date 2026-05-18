---
title: 06 - Dependency Injection
description: Dependency injection is a design pattern where a function or class declares what it needs rather than creating it  -  in FastAPI, it is a first-class feature implemented via function parameters and decorators that wires up authentication, database sessions, and shared services automatically.
tags: [dependency-injection, DI, FastAPI, decorators, design-patterns, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Dependency Injection

> Dependency injection is a design pattern where a function or class declares what it needs rather than creating it  -  in FastAPI, it is a first-class feature implemented via function parameters and decorators that wires up authentication, database sessions, and shared services automatically.

---

## Quick Reference

**Core idea:**
- DI = **declare what you need as parameters**; a framework or container resolves and provides them
- In FastAPI: `Depends(fn)` as a default value tells FastAPI to call `fn` and inject the result as the argument
- Dependencies can be **nested**  -  a dependency can itself have dependencies; FastAPI resolves the full graph
- Dependencies can be **generators**  -  `yield` once to provide the value; code after `yield` runs on cleanup (like a context manager)
- FastAPI **caches** dependencies with the same scope by default  -  a dependency called multiple times in the same request is only executed once

**Tricky points:**
- `Depends()` is evaluated **per request**, not at startup  -  each request gets a fresh dependency execution (unless cached by scope)
- A generator dependency that `yield`s inside a `try`/`finally` is the correct pattern for cleanup  -  the `finally` block runs even if the route handler raises
- `Annotated[Type, Depends(fn)]` (Python 3.9+) is the preferred syntax  -  it keeps the type annotation separate from the dependency marker
- Dependencies declared at the **router or app level** apply to all routes under them  -  use this for auth checks that apply globally
- You can override dependencies in tests with `app.dependency_overrides[original_dep] = mock_dep`  -  this is FastAPI's built-in test isolation mechanism

---

## What It Is

Think of a hotel concierge service. When a guest checks in, they do not arrange their own car rental, book their own restaurant, or source their own amenities. They tell the concierge what they need, and the concierge handles the sourcing and delivery. The guest's job is to state their needs, not to fulfil them. Dependency injection works the same way: a function declares what it needs as parameters, and an external system  -  the injector or container  -  is responsible for providing them. The function stays focused on its own work; the infrastructure for obtaining its dependencies lives elsewhere.

In software, dependency injection separates the use of a dependency from its creation. Without DI, a function that needs a database connection creates it internally: `conn = create_db_connection()`. This couples the function to the specific way connections are created  -  you cannot test the function without a real database, and you cannot change how connections are created without modifying the function. With DI, the function accepts the connection as a parameter: `def handler(conn: Connection)`. The caller (or framework) is responsible for providing the connection. The function is testable with a mock connection and reusable across different connection strategies.

FastAPI implements dependency injection directly in its routing system. When you annotate a route handler parameter with `Depends(some_function)`, FastAPI calls `some_function` before the handler and passes the result as the argument. `some_function` is a dependency  -  it can be any callable, including one that itself has `Depends` parameters. FastAPI resolves the full dependency graph before calling the handler: it figures out everything that needs to be called, in what order, calls them, and passes the results through to the handler.

---

## How It Actually Works

FastAPI's dependency injection is implemented by inspecting function signatures. When a route is registered, FastAPI uses `inspect.signature()` to examine the handler's parameters. For each parameter with a default value of `Depends(fn)`, FastAPI notes that this parameter requires the result of calling `fn`. It then inspects `fn`'s signature recursively to find any dependencies `fn` itself has. This builds a dependency graph at route registration time.

At request time, FastAPI traverses the dependency graph, calling each dependency in dependency order (leaves first). If a dependency has already been called during this request (because two route parameters depend on the same function), FastAPI uses the cached result rather than calling it again. This deduplication ensures that, for example, a database session dependency is only created once per request even if multiple route parameters or nested dependencies request it.

Generator dependencies are the pattern for managed resources. A dependency that `yield`s once provides the value before the yield as the injected resource. FastAPI wraps generator dependencies in a context manager: it calls `next()` to get the value (running the setup code before the yield), injects it, runs the route handler, and then calls `next()` again on the generator (running the teardown code after the yield, inside a try/finally to ensure cleanup even on exceptions). This is identical to how `contextlib.contextmanager` works and relies on the same generator frame suspension mechanism.

Dependencies can also be classes. A class with a `__call__` method can be used as a dependency  -  FastAPI calls the instance when resolving the dependency. This is used for dependencies that need configuration: `auth = Depends(OAuth2PasswordBearer(tokenUrl="/token"))` passes a configured `OAuth2PasswordBearer` instance as a dependency callable.

---

## How It Connects

FastAPI's `Depends()` is syntactically implemented using Python decorators and function signature inspection. Understanding how Python decorators work  -  how `@app.get("/path")` registers a route  -  and how Python's function parameters and defaults work is the mechanical foundation of how FastAPI wires up the DI system.
[[decorators|Decorators]]

FastAPI's dependency injection is the mechanism by which Pydantic models, authentication schemes, database sessions, and shared configuration are provided to route handlers. The DI system is the glue that connects all of FastAPI's components into a cohesive request-handling pipeline.
[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "Dependency injection is just passing arguments to functions."
Reality: Basic argument passing and DI have the same result but different control flow. With manual argument passing, the caller creates and passes the dependency  -  the caller is responsible. With DI, the framework or container creates and provides the dependency  -  the function declares its needs and the framework takes responsibility for fulfilment. The difference matters at scale: in a large application, manual wiring of dozens of shared dependencies (database sessions, auth, config, cache clients) across hundreds of route handlers becomes unmanageable. DI makes the wiring declarative and centralised.

Misconception 2: "Dependencies in FastAPI are singletons  -  they are created once at startup."
Reality: By default, FastAPI dependencies are request-scoped  -  they are called once per request (with deduplication within a request). They are not created at application startup. Application-level singletons (database connection pools, HTTP client instances) should be created explicitly, usually in the application lifespan handler, and accessed via a dependency that returns the already-created instance. The dependency function itself is called per request; what it returns may be a shared object if that object was created at startup.

---

## Why It Matters in Practice

Dependency injection is what makes FastAPI applications testable without a live database, authentication server, or external service. `app.dependency_overrides` is the mechanism: for any `Depends(real_fn)` in your app, you can register a `mock_fn` in the overrides dict during tests. FastAPI will call `mock_fn` instead of `real_fn` for the duration of the test. This means your route handler tests can run with in-memory stubs for all external dependencies  -  no Docker containers, no test databases, no mocked HTTP calls at the `requests` level.

The generator dependency pattern for database sessions is one of the most important practical applications. The correct pattern is: a dependency function opens a database session, yields it, and closes it in a `finally` block. Every route that needs database access includes this dependency. FastAPI ensures the session is opened before the handler, passed in, and closed after  -  regardless of whether the handler succeeded or raised. This is preferable to managing sessions manually in each handler, where a forgotten close or an uncaught exception could leak the connection.

---

## Interview Angle

Common question forms:
- "What is dependency injection and why is it useful?"
- "How does `Depends()` work in FastAPI?"
- "How do you test a FastAPI route that uses a database dependency?"

Answer frame: Define DI as declaring what you need rather than creating it  -  the framework provides it. Explain FastAPI's `Depends()`: at registration, FastAPI inspects signatures and builds a dependency graph; at request time, it resolves the graph, caches results within the request, and injects values. Describe generator dependencies for cleanup: setup before yield, teardown after in a finally block. For testing: `app.dependency_overrides` replaces real dependencies with test stubs without touching handler code.

---

## Related Notes

- [[decorators|Decorators]]
- [[fastapi|FastAPI]]
