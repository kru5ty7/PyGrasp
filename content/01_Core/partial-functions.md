---
title: Partial Functions
description: `functools.partial` creates a new callable by pre-filling some arguments of a function — the resulting partial object can be called with the remaining arguments later, enabling specialization and argument adaptation without writing a new function.
tags: [partial, functools, partial-application, currying, callable, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Partial Functions

> `functools.partial` creates a new callable by pre-filling some arguments of a function — the resulting partial object can be called with the remaining arguments later, enabling specialization and argument adaptation without writing a new function.

---

## Quick Reference

**Core idea:**
- `functools.partial(fn, *args, **kwargs)` returns a `partial` object that, when called, behaves like `fn` with the given `args`/`kwargs` pre-filled
- Additional arguments passed when calling the partial are appended to the pre-filled positionals; additional keyword arguments override or extend the pre-filled ones
- `partial.func` — the original function; `partial.args` — pre-filled positional args tuple; `partial.keywords` — pre-filled keyword args dict
- `partial` objects are callable — `callable(p)` is `True`; they can be passed wherever a function is expected

**Tricky points:**
- Pre-filled positional arguments cannot be skipped — `partial(f, 1)` pre-fills the first positional; you cannot pre-fill the second positional and leave the first open (use keyword arguments for that)
- `partial` does not copy `__name__`, `__doc__`, or `__module__` from the original function — `p.__name__` raises `AttributeError`; use `functools.update_wrapper(p, fn)` or `functools.wraps` if you need metadata
- Keyword arguments pre-filled in `partial` can be overridden at call time: `partial(f, x=1)(x=2)` calls `f(x=2)` — later keywords win
- `partial` is not the same as currying — currying transforms `f(a, b)` into `f(a)(b)`, always one argument at a time; `partial` pre-fills any subset of arguments

---

## What It Is

Think of a stamp pre-inked with a company logo. Rather than applying the logo image each time, you pre-load the stamp with the logo and then press it wherever needed. The stamp is specialized for that one logo, but it still requires you to specify where to press it. `functools.partial` pre-loads a function with some arguments, creating a specialized callable that still requires the remaining arguments to be provided when called.

The practical value is adapter creation. Many Python APIs expect a function with a specific signature. If you have a function that takes more arguments than the API expects, `partial` bridges the gap: pre-fill the extra arguments, leaving only the required signature exposed.

`sorted(items, key=partial(get_attribute, "priority"))` is a contrived but illustrative example: `get_attribute("priority", obj)` retrieves an attribute by name; `partial(get_attribute, "priority")` creates a single-argument callable that retrieves `"priority"` from any object passed to it.

---

## How It Actually Works

`functools.partial` is implemented in C as `_functools.partial`. The `partial` object stores:
- `func`: the original callable
- `args`: tuple of pre-filled positional arguments
- `keywords`: dict of pre-filled keyword arguments

When the partial object is called with additional arguments:

```python
p = partial(fn, 1, 2, x=3)
p(4, y=5)
# equivalent to: fn(1, 2, 4, x=3, y=5)
```

The pre-filled `args` are prepended to any new positional arguments; the pre-filled `keywords` are merged with any new keyword arguments (new keywords override pre-filled ones for the same key).

`partial` objects have a `__call__` method that performs this merge and calls `self.func`. They are not functions themselves — `type(p)` is `functools.partial`, not `function` — but they are callable.

`methodcaller` (from `operator`) is a related utility: `operator.methodcaller("strip")(s)` calls `s.strip()`. It is more limited than `partial` but cleaner for method dispatch.

---

## How It Connects

`functools.partial` is one of the tools in the `functools` module alongside `lru_cache`, `wraps`, and `reduce`.
[[functools|functools]]

`partial` and `lambda` solve similar problems — both create specialized callables. `lambda x: f(x, config)` is equivalent to `partial(f, config)` for fixed positional arguments. `partial` is more transparent (inspectable via `.func`, `.args`, `.keywords`) and avoids creating a new `function` object.
[[lambda|Lambda Functions]]

---

## Common Misconceptions

Misconception 1: "`partial` is the same as currying."
Reality: Currying transforms a multi-argument function into a chain of single-argument functions: `f(a, b)` becomes `f_curried(a)(b)`. `partial` pre-fills a specific subset of arguments at once and returns a callable for the rest. Python does not have built-in currying; `partial` is partial application (pre-filling any subset), not currying (one argument at a time).

Misconception 2: "Pre-filled keyword arguments in a partial cannot be changed."
Reality: Keyword arguments pre-filled in `partial` can be overridden at call time. `p = partial(connect, host="localhost"); p(host="example.com")` calls `connect(host="example.com")` — the override wins. This makes `partial` flexible for providing defaults that callers can still change.

---

## Why It Matters in Practice

Adapting functions for APIs is the primary use case. `sorted(items, key=partial(operator.getitem, "score"))` — `operator.getitem` takes `(container, key)`, but `sorted`'s `key` expects a single-argument function. `partial(operator.getitem, "score")` creates a callable that takes one argument (the container) and gets `"score"` from it.

Thread and process targets: `threading.Thread(target=partial(worker, config=settings))` creates a thread that runs `worker(config=settings)`. Without `partial`, you would need a lambda or a wrapper function.

Configuring test fixtures: `factory = partial(User, role="guest", active=True)` creates a factory for guest users in tests — `factory(name="Alice")` creates `User(name="Alice", role="guest", active=True)`.

---

## Interview Angle

Common question forms:
- "What is `functools.partial`?"
- "What is the difference between `partial` and currying?"

Answer frame: `functools.partial(fn, *args, **kwargs)` returns a partial object that, when called, prepends the pre-filled positional args and merges the pre-filled keyword args. The result is callable anywhere a function is expected. It is partial application — pre-filling any subset of arguments — not currying (currying chains single-argument calls). Pre-filled keyword args can be overridden at call time. `partial.func`, `partial.args`, `partial.keywords` give access to the internals.

---

## Related Notes

- [[functools|functools]]
- [[lambda|Lambda Functions]]
- [[higher-order-functions|Higher-Order Functions]]
- [[args-and-kwargs|*args and **kwargs]]
