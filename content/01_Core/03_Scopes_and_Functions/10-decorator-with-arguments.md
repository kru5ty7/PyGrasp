---
title: Decorators with Arguments
description: A decorator with arguments is a callable that accepts configuration parameters and returns a decorator — it adds an extra function layer so the outer function receives arguments, the middle function receives the function to decorate, and the inner function is the actual wrapper.
tags: [decorators, decorator-arguments, decorator-factory, functools-wraps, parametrized-decorators, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Decorators with Arguments

> A decorator with arguments is a callable that accepts configuration parameters and returns a decorator — it adds an extra function layer so the outer function receives arguments, the middle function receives the function to decorate, and the inner function is the actual wrapper.

---

## Quick Reference

**Core idea:**
- `@decorator(arg)` is equivalent to `fn = decorator(arg)(fn)` — `decorator(arg)` must return a decorator, which then receives `fn`
- Plain `@decorator` is equivalent to `fn = decorator(fn)` — only one call
- The pattern for a decorator with arguments: outer function receives config args → returns a middle function → middle receives `fn` → returns the wrapper
- Always use `@functools.wraps(fn)` on the wrapper to preserve `fn.__name__`, `fn.__doc__`, and `fn.__wrapped__`
- `functools.wraps` copies `__name__`, `__qualname__`, `__doc__`, `__dict__`, `__module__`, `__annotations__`, and sets `__wrapped__`

**Tricky points:**
- A decorator **with** arguments requires three levels of nesting; a decorator **without** arguments requires two; confusing the two is the most common error
- `@decorator()` (with empty parentheses) still requires the three-level pattern — the empty call `decorator()` must return a decorator
- Class-based decorators can unify the two cases: `__init__` can receive either the function or the arguments, and `__call__` handles the remaining step
- `functools.wraps` does not forward `__wrapped__` recursively — stacking multiple `@wraps` decorators is fine; each adds a `__wrapped__` pointing to the layer below
- `fn.__wrapped__` lets introspection tools (and `functools.wraps`) reach the original function through the wrapper chain

---

## What It Is

Think of a security badge system where different doors require different clearance levels. A basic `@requires_auth` decorator is like a single-level badge check: either you are authenticated or not. But `@requires_auth(role="admin")` is a configurable badge check — the configuration (`role="admin"`) is provided at decoration time and then the decorator uses that configuration to check each request. The configuration is "baked in" to the decorator when it is applied to the function; the resulting wrapper remembers it.

The pattern is an extra layer of wrapping. A plain decorator `d` is called as `d(fn)` — one call. A decorator factory `d(arg)` must first be called as `d(arg)` to get a decorator, and then that decorator is called as `decorator(fn)`. Two calls, three function levels: the factory, the decorator, and the wrapper.

The mental model is "configure, then apply." `@retry(times=3)` means: first configure the retry behavior (3 attempts), producing a configured decorator; then apply that configured decorator to the function. The configured decorator captures `times=3` as a free variable in the wrapper.

---

## How It Actually Works

```python
import functools

def retry(times=3):                        # level 1: factory, receives config
    def decorator(fn):                     # level 2: decorator, receives function
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):      # level 3: wrapper, called at runtime
            for attempt in range(times):
                try:
                    return fn(*args, **kwargs)
                except Exception:
                    if attempt == times - 1:
                        raise
        return wrapper
    return decorator

@retry(times=5)
def flaky_request():
    ...
```

`@retry(times=5)` desugars to `flaky_request = retry(times=5)(flaky_request)`. `retry(times=5)` is called first, returning `decorator`. Then `decorator(flaky_request)` is called, returning `wrapper`. `wrapper` has `times=5` captured from `retry`'s scope as a free variable.

`@functools.wraps(fn)` on the wrapper copies metadata. Without it, `flaky_request.__name__` would be `"wrapper"` instead of `"flaky_request"`, and tracebacks and logging would show the wrong function name.

A class-based decorator can handle both `@d` and `@d()` by checking whether the first argument is callable:

```python
class decorator:
    def __init__(self, fn=None, *, timeout=30):
        self.timeout = timeout
        if fn is not None:
            functools.update_wrapper(self, fn)
            self.fn = fn
    def __call__(self, *args, **kwargs):
        if self.fn is None:  # called as @decorator(timeout=60)
            fn = args[0]
            return type(self)(fn, timeout=self.timeout)
        return self.fn(*args, **kwargs)
```

---

## How It Connects

Decorators without arguments are the simpler two-level version of this pattern. Understanding the plain decorator first makes the three-level version a natural extension.
[[decorators|Decorators]]

`functools.wraps` is a decorator itself — it is a decorator with arguments (`@functools.wraps(fn)`) that copies metadata from `fn` to the wrapper function.
[[functools|functools]]

---

## Common Misconceptions

Misconception 1: "`@decorator` and `@decorator()` are the same."
Reality: `@decorator` calls `decorator(fn)` — one call, two levels. `@decorator()` calls `decorator()` first (no `fn`), then calls the result with `fn`. They require different implementations. Writing `@retry` when you meant `@retry()` applies `retry` directly to the function, which then gets a function where it expects configuration — a confusing `TypeError`.

Misconception 2: "`functools.wraps` is optional boilerplate."
Reality: Without `functools.wraps`, the wrapper function's `__name__`, `__doc__`, and `__annotations__` come from the wrapper definition, not the original function. This breaks `help()`, doctest discovery, introspection tools, and logging. It also breaks `functools.lru_cache` and similar decorators that key on `__wrapped__`. Always use `@functools.wraps(fn)` on wrapper functions.

---

## Why It Matters in Practice

`@app.route("/users", methods=["GET"])` in Flask is a decorator with arguments — `app.route("/users", methods=["GET"])` returns a decorator that registers the function as a handler for that URL. The route and methods are the configuration baked in at decoration time.

`@pytest.mark.parametrize("x,expected", [(1, 2), (3, 4)])` is a decorator with arguments that generates multiple test cases from a function. `@lru_cache(maxsize=128)` configures the cache size. All are three-level factories.

Rate limiting, logging with configurable levels, retry with configurable attempts, permission checking with configurable roles — all are naturally expressed as decorators with arguments.

---

## Interview Angle

Common question forms:
- "How do you write a decorator that accepts arguments?"
- "What is the difference between `@decorator` and `@decorator()`?"

Answer frame: A decorator with arguments needs three levels: `decorator_factory(config)` → `decorator(fn)` → `wrapper(*args, **kwargs)`. `@d(arg)` desugars to `fn = d(arg)(fn)`. The config is captured as a free variable in the wrapper. Always apply `@functools.wraps(fn)` to the wrapper to preserve metadata. `@d` (no parens) is a two-level pattern; confusing the two levels is the most common error.

---

## Related Notes

- [[decorators|Decorators]]
- [[functools|functools]]
- [[closures|Closures]]
- [[first-class-functions|First-Class Functions]]
