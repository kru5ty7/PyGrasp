---
title: Decorators
description: "A decorator is a callable that takes a function (or class) as input and returns a replacement — `@decorator` above a function definition is syntactic sugar for immediately passing the function to the decorator and rebinding the name to the result."
tags: [decorators, closures, functools, wraps, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Decorators

> A decorator is a callable that takes a function (or class) as input and returns a replacement — `@decorator` above a function definition is syntactic sugar for immediately passing the function to the decorator and rebinding the name to the result.

---

## Quick Reference

**Core idea:**
- `@decorator` over a function is exactly `fn = decorator(fn)` — nothing more, nothing less
- A decorator receives the original function, wraps it in a new function (a closure), and returns the wrapper
- `functools.wraps(original)` on the wrapper copies `__name__`, `__doc__`, `__annotations__`, `__module__`, `__qualname__`, `__wrapped__` — always use it
- Decorators can be **stacked** — they apply bottom-up: `@A` then `@B` is `fn = A(B(fn))`
- Decorators can take **arguments** by adding another layer of nesting: a function that returns a decorator that returns a wrapper

**Tricky points:**
- A decorator that forgets `return wrapper` returns `None`, silently replacing the function with `None` — every call to the decorated function will raise `TypeError: 'NoneType' object is not callable`
- Stacked decorators apply **bottom-up, not top-down** — `@A` over `@B` means `A` wraps the result of `B(fn)`, so `B` runs first
- Without `functools.wraps`, `fn.__name__` becomes the wrapper's name — this breaks logging, debugging, and docstring tools
- A decorator that takes arguments (`@retry(times=3)`) requires **three levels**: the argument-taking outer function, the decorator, and the wrapper
- Class decorators work exactly the same way as function decorators — they receive the class and return a replacement

---

## What It Is

Think of a passport stamp. You hand your passport to the border officer, they look at it, add a stamp, and hand it back. Your passport is still your passport — it has the same information — but now it also carries the stamp. You could have multiple officers stamp it in sequence. A Python decorator does the same thing to a function: it receives the function, wraps it with new behavior, and returns the wrapped version. The name that originally pointed to the function now points to the wrapper instead.

The `@` syntax is a convenience built directly into Python's parser. When you write `@some_decorator` above a `def`, the parser generates code that is exactly equivalent to defining the function normally and then immediately passing it to `some_decorator`, with the result rebound to the same name. There is no magic. The decorator is called at the moment the class or module body is executed — at import time for module-level functions, at class creation time for methods. The original function is replaced before any code that uses the function runs.

The most common pattern for a decorator is: define an outer function that receives the original function, define a wrapper function inside it (creating a closure that captures the original), and return the wrapper. The wrapper calls the original and does something extra — logging before and after, retrying on failure, caching the result, checking permissions, timing the execution. Because functions are objects in Python and closures carry state, all of this is expressible in a few lines of regular Python code without any framework support.

---

## How It Actually Works

At the bytecode level, `@decorator` over a function compiles to the same sequence as defining the function and then applying the decorator. The `def` statement creates a function object and pushes it onto the evaluation stack. Then `CALL` (or the appropriate call opcode) calls the decorator with the function object as the argument. The result is stored back under the original name. The parser performs this transformation — the `@` syntax is resolved at compile time into explicit call instructions.

`functools.wraps` works by copying specific attributes from the original function to the wrapper. Internally, it uses `functools.update_wrapper`, which copies `__module__`, `__name__`, `__qualname__`, `__annotations__`, `__doc__`, and `__dict__` from the wrapped function to the wrapper, and sets `__wrapped__` on the wrapper to point to the original. The `__wrapped__` attribute is particularly useful: it allows `inspect.unwrap()` to peel off all the decorator layers and reach the original function — important for documentation generators and some testing frameworks.

Parameterized decorators — decorators that take arguments — require an extra function layer. `@retry(times=3)` is evaluated as `retry(times=3)` first (at parse/import time), which must return a decorator. That decorator is then applied to the function, which must return the wrapper. The three-level structure is: `retry(times=3)` returns `decorator`, `decorator(fn)` returns `wrapper`, `wrapper(*args, **kwargs)` calls `fn(*args, **kwargs)` with retry logic. This pattern is why parameterized decorators require the extra level — the `@` expression must evaluate to something callable that accepts a function.

---

## How It Connects

The typical decorator pattern — outer function captures the original function, inner wrapper function calls it — is a closure. The wrapper closes over the original function object. Understanding cells and how closures preserve references across function lifetimes is what explains why the original function is accessible inside the wrapper long after the decorator call has finished.
[[closures|Closures]]

Decorators operate on functions, and functions are first-class objects. The entire decorator pattern depends on the fact that functions can be passed as arguments, returned from functions, and assigned to variables just like any other value. Without functions being objects, `fn = decorator(fn)` would not make sense.
[[everything-is-an-object|Everything is an Object]]

Class-based decorators use `__call__` — the dunder method that makes any object callable. A class can be used as a decorator if it implements `__call__`, and the decorator instance holds the original function as an instance attribute. This is the pattern used when a decorator needs to maintain state across multiple calls to the decorated function.
[[dunder-methods|Dunder Methods]]

---

## Common Misconceptions

Misconception 1: "Decorators modify the function in place."
Reality: Decorators replace the function. `@decorator` rebinds the name to whatever the decorator returns. The original function object still exists (accessible via `fn.__wrapped__` if `functools.wraps` was used), but the name now points to the wrapper. The original function is not modified — a new object is created and bound to the name.

Misconception 2: "Stacked decorators apply top-down, like reading the code."
Reality: Stacked decorators apply bottom-up. Given:
```
@A
@B
def fn(): ...
```
This is `fn = A(B(fn))`. `B` is applied to the original `fn` first, then `A` is applied to the result of `B`. When `fn` is called, `A`'s wrapper runs first, then `B`'s wrapper, then the original. The visual order (top-down) is the opposite of the application order (bottom-up).

---

## Why It Matters in Practice

Decorators are how Python frameworks add behavior to your functions without requiring you to modify them. FastAPI uses `@app.get("/path")` to register route handlers. Celery uses `@app.task` to register tasks. `pytest` uses `@pytest.fixture` and `@pytest.mark.parametrize`. `dataclasses` uses `@dataclass` on classes. In each case, the decorator receives your function or class, wraps or transforms it, and registers it in some framework-internal structure. You write plain Python; the decorator handles the integration.

The most practical thing to internalize about decorators is the `functools.wraps` discipline. Omitting it makes debugging harder — function names in stack traces and logs become the wrapper's name (`wrapper`) instead of the original. It breaks `help()`, which shows the wrapper's docstring instead of the original. It can cause issues with frameworks that inspect `__name__` to build routing tables or test discovery. `functools.wraps` is a one-line fix that prevents all of these problems; it should be considered mandatory for any decorator that wraps a function.

---

## Interview Angle

Common question forms:
- "What is a decorator in Python?"
- "Write a decorator that times how long a function takes."
- "What does `functools.wraps` do and why is it important?"

Answer frame: Define `@decorator` as `fn = decorator(fn)` — syntactic sugar for immediate rebinding. Show the three-layer structure: outer function receives `fn`, inner wrapper calls `fn` with added behavior, outer function returns wrapper. Explain `functools.wraps` as preserving `__name__`, `__doc__`, and `__wrapped__`. For parameterized decorators, describe the extra layer: `@retry(3)` evaluates `retry(3)` first, which must return the decorator. Mention stacking order (bottom-up).

---

## Related Notes

- [[closures|Closures]]
- [[everything-is-an-object|Everything is an Object]]
- [[dunder-methods|Dunder Methods]]
