---
title: functools
description: The `functools` module provides higher-order function utilities — `lru_cache` for memoization, `wraps` for decorator metadata preservation, `partial` for partial application, `reduce` for fold operations, `total_ordering` for comparison method generation, and `cache`/`cached_property` for lazy computation.
tags: [functools, lru_cache, wraps, partial, reduce, total_ordering, cached_property, memoization, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# functools

> The `functools` module provides higher-order function utilities — `lru_cache` for memoization, `wraps` for decorator metadata preservation, `partial` for partial application, `reduce` for fold operations, `total_ordering` for comparison method generation, and `cache`/`cached_property` for lazy computation.

---

## Quick Reference

**Core idea:**
- `@functools.lru_cache(maxsize=128)` — memoizes a function's return values keyed by arguments; evicts with LRU policy when full
- `@functools.cache` (Python 3.9+) — unbounded cache, equivalent to `lru_cache(maxsize=None)`, lower overhead
- `functools.wraps(fn)` — copies `__name__`, `__doc__`, `__annotations__`, `__module__`, `__qualname__`, `__dict__` from `fn` to a wrapper; sets `__wrapped__ = fn`
- `functools.partial(fn, *args, **kwargs)` — creates a new callable with some arguments pre-filled
- `functools.reduce(fn, iterable, initial)` — left fold: applies `fn(acc, elem)` cumulatively
- `@functools.total_ordering` — given `__eq__` and one of `__lt__`/`__le__`/`__gt__`/`__ge__`, generates the remaining comparison methods
- `functools.cached_property` — a non-data descriptor that computes a value once and stores it in the instance `__dict__`

**Tricky points:**
- `lru_cache` requires all arguments to be **hashable** — unhashable arguments (lists, dicts) raise `TypeError`; convert to tuples before caching
- `lru_cache` on a method caches per instance if called as `instance.method(args)` — but the cache key includes `self`, so each instance's results are cached separately; the cache is on the class, so instances are never garbage-collected while their cached results exist (memory leak risk)
- `cached_property` stores the result in the **instance** `__dict__` — it is a non-data descriptor, so the instance dict entry shadows it on subsequent access; it does not work with `__slots__` classes (no `__dict__`)
- `total_ordering` is convenient but slow — it generates wrappers around the provided methods; for performance-critical code, define all six comparison methods explicitly
- `functools.wraps` is itself a decorator-with-arguments — `@wraps(fn)` sets up metadata copying for the wrapper it decorates

---

## What It Is

Think of `functools` as a toolkit for working with functions as objects. Most of the module's tools address one of three categories: caching (avoid recomputing results), wrapping (build new functions from existing ones), and reduction (combine sequences using a function).

`lru_cache` is the most commonly used tool. Given a pure function — one whose output depends only on its inputs — the cache turns each unique input into a stored result. The second call with the same arguments is a cache lookup; the function body is not re-executed. For computationally expensive functions called repeatedly with the same inputs, this can be a orders-of-magnitude speedup.

`functools.wraps` is the tool every decorator author needs. Decorators replace a function with a wrapper, which breaks the original function's identity — the wrapper has its own `__name__`, `__doc__`, etc. `@wraps(original)` copies the metadata so the wrapper appears to be the original function from the perspective of introspection tools.

---

## How It Actually Works

`lru_cache` wraps the function in a C-level implementation (`_functools.lru_cache_object`) that maintains an ordered dictionary keyed by the argument tuple. On each call, the argument tuple is hashed and looked up. On a hit, the entry is moved to the front of the LRU order and the cached value is returned. On a miss, the function is called, the result is stored, and if the cache exceeds `maxsize`, the least recently used entry is evicted.

`cache` (Python 3.9+) is identical to `lru_cache(maxsize=None)` but uses a simpler dict implementation without the LRU bookkeeping overhead.

`cached_property` is a descriptor class:

```python
class cached_property:
    def __get__(self, obj, cls):
        if obj is None:
            return self
        value = self.func(obj)
        obj.__dict__[self.attrname] = value  # store in instance dict
        return value
```

On the next access, the instance `__dict__` entry shadows the `cached_property` descriptor (non-data descriptor — no `__set__`), so `__get__` is never called again. The value is computed exactly once per instance.

`total_ordering` inspects the class for `__eq__` and whichever of the four ordering methods is defined, then adds `__wrapped__` versions of the missing methods that call the provided ones. For example, if `__lt__` is defined, `__le__` is generated as `lambda self, other: self < other or self == other`.

---

## How It Connects

`functools.partial` is covered separately as it is a standalone concept with its own patterns.
[[partial-functions|Partial Functions]]

`functools.wraps` is required in every well-written decorator — it is the tool that makes decorators transparent to introspection.
[[decorator-with-arguments|Decorators with Arguments]]

`cached_property` interacts with `__slots__` — slots classes have no `__dict__`, so `cached_property` cannot store the cached value. Alternative: use a slot with a sentinel value and compute on first access in `__get__`.
[[slots|__slots__]]

---

## Common Misconceptions

Misconception 1: "`lru_cache` on a method is memory-safe."
Reality: `lru_cache` on a method keeps `self` in the cache keys, which keeps the instance alive as long as the cache entry exists. If the cache is large and holds many instances, those instances are never garbage-collected. For instance methods, consider `cached_property` (stores per-instance) or an explicit per-instance cache dict instead of `lru_cache`.

Misconception 2: "`@cache` and `@lru_cache` are interchangeable."
Reality: `@cache` is unbounded — it never evicts entries. `@lru_cache(maxsize=128)` limits the cache to 128 entries and evicts the least recently used when full. For functions that may be called with a large variety of inputs, an unbounded cache can exhaust memory. Use `lru_cache` with a bounded `maxsize` when input cardinality is high.

---

## Why It Matters in Practice

Fibonacci memoization with `@cache` is the textbook example, but the real-world use is any pure function with expensive computation called repeatedly with the same arguments: database query results, parsed configuration files, compiled regular expressions (though `re` has its own cache), network resource lookups.

`@total_ordering` is the right tool for value objects that need full comparison support. A `Version(major, minor, patch)` class defines `__eq__` and `__lt__`, and `@total_ordering` generates the rest. The tradeoff: slightly slower comparisons versus significant code savings.

`functools.singledispatch` (not in Quick Reference but part of the module) implements single-dispatch generic functions — a function with different implementations for different argument types, selected at runtime. It is the Python mechanism for type-based dispatch without `isinstance` chains.

---

## Interview Angle

Common question forms:
- "What does `functools.lru_cache` do?"
- "How do you preserve function metadata in a decorator?"
- "What is `functools.partial`?"

Answer frame: `lru_cache` memoizes a function's return value keyed by its arguments — arguments must be hashable. `@cache` is an unbounded version (Python 3.9+). `functools.wraps(fn)` copies `__name__`, `__doc__`, and other attributes from `fn` to a wrapper — essential in every decorator. `partial(fn, arg)` pre-fills arguments. `cached_property` computes a value once and stores it in the instance dict (non-data descriptor). The `lru_cache`-on-method memory leak: `self` in the cache key keeps instances alive.

---

## Related Notes

- [[partial-functions|Partial Functions]]
- [[decorator-with-arguments|Decorators with Arguments]]
- [[decorators|Decorators]]
- [[higher-order-functions|Higher-Order Functions]]
