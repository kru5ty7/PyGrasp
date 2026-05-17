---
title: Context Managers
description: A context manager is any object that implements `__enter__` and `__exit__` — the `with` statement calls them to set up and tear down a context reliably, even if an exception occurs, making resource management in Python predictable and safe.
tags: [context-managers, with-statement, dunder, contextlib, generators, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Context Managers

> A context manager is any object that implements `__enter__` and `__exit__` — the `with` statement calls them to set up and tear down a context reliably, even if an exception occurs, making resource management in Python predictable and safe.

---

## Quick Reference

**Core idea:**
- `with obj as x:` calls `x = obj.__enter__()`, runs the block, then calls `obj.__exit__(exc_type, exc_val, exc_tb)` — always, even on exception
- `__exit__` receives exception info — return a **truthy value** to suppress the exception; return `None`/`False` to re-raise
- `contextlib.contextmanager` lets you write a context manager as a generator: code before `yield` is `__enter__`; code after is `__exit__`
- The `as x` target is the **return value of `__enter__`**, not the context manager itself — `open()` returns a file object from `__enter__`
- Context managers can be nested: `with A() as a, B() as b:` is exactly `with A() as a: with B() as b:`

**Tricky points:**
- `with obj:` is NOT equivalent to `try: ... finally: obj.close()` — `__exit__` receives exception information and can suppress it; `finally` cannot
- `__exit__` is called even if `__enter__` succeeded and the `with` block raised — but **not** if `__enter__` itself raised
- `contextlib.contextmanager` generator must `yield` exactly once — yielding zero times (returning without yield) or more than once raises `RuntimeError`
- Returning a truthy value from `__exit__` **silently suppresses** the exception — this is usually wrong; only do it if suppressing is the intended behavior
- `contextlib.suppress(ExceptionType)` is a context manager that explicitly suppresses a specific exception — cleaner than a bare `except: pass`

---

## What It Is

Think of a bank's safe deposit box room. When you enter, the guard checks your ID and hands you the key (setup). You do your work with the box. When you leave — whether you finished normally or were interrupted — the guard ensures the box is locked and returned, and the room is properly closed behind you (teardown). The guard's job happens regardless of what occurred during your visit. A Python context manager is that guard. The `with` statement guarantees that the setup and teardown happen correctly and in order, no matter what happens in between.

Before context managers, Python code that needed to guarantee cleanup used try/finally: open a resource before the try, close it in the finally block. This pattern works, but it is verbose, easy to forget, and harder to read than the operation it protects. The `with` statement condenses this into a single construct. Any object that implements `__enter__` and `__exit__` can be used with `with`. When you write `with open("file.txt") as f:`, Python calls `file_object.__enter__()`, which returns the file object itself. When the block ends — normally or via an exception — Python calls `file_object.__exit__(exc_type, exc_val, exc_tb)`, which closes the file.

The most important property of the `with` statement is that `__exit__` is always called after `__enter__` succeeds, regardless of what happens in the block. An exception, a `return`, a `break`, a `continue` — none of these bypass `__exit__`. This guarantee is what makes `with` suitable for resource management: files are closed, database connections are released, locks are released, temporary state is restored. The teardown is built into the structure of the code, not left to the programmer to remember.

---

## How It Actually Works

CPython compiles the `with` statement into bytecode using two opcodes: `BEFORE_WITH` and `WITH_EXCEPT_START`. `BEFORE_WITH` calls `__enter__` on the context manager and pushes the result onto the evaluation stack (this becomes the `as` target if `as` is present). The block body executes normally. If no exception occurs, `WITH_EXCEPT_START` is reached, CPython calls `__exit__(None, None, None)`, and execution continues after the `with` block. If an exception occurs anywhere in the block, Python unwinds the stack to the `with` block's cleanup handler and calls `__exit__(exc_type, exc_val, exc_tb)` with the exception information.

The `__exit__` method receives three arguments: the exception type, the exception value, and the traceback object. If no exception occurred, all three are `None`. If `__exit__` returns a truthy value, CPython treats the exception as handled and does not propagate it — execution continues normally after the `with` block. If `__exit__` returns a falsy value (including `None`, which is what methods return when there is no explicit return statement), the exception is re-raised. This is why almost all `__exit__` implementations either do not return (implicitly returning `None`) or return `False` — they want the exception to propagate.

`contextlib.contextmanager` is a decorator that converts a generator function into a context manager. The generator must `yield` exactly once. Code before the `yield` runs in `__enter__`. The value yielded becomes the `as` target. Code after the `yield` runs in `__exit__`. If an exception occurs in the `with` block, it is thrown into the generator at the `yield` point using `generator.throw(exc_type, exc_val, exc_tb)`. The generator can handle the exception in a try/except around the yield, or let it propagate. This pattern lets you write context managers with the natural linear structure of a generator instead of splitting logic between `__enter__` and `__exit__` methods.

---

## How It Connects

`__enter__` and `__exit__` are dunder methods — they are looked up on the type via CPython's slot mechanism, not on the instance. Understanding what dunder methods are, how they are looked up, and why they are defined on the type rather than the instance is the foundation for understanding how the `with` statement dispatches to them.
[[dunder-methods|Dunder Methods]]

`contextlib.contextmanager` uses a generator to split the setup and teardown into a before-yield and after-yield structure. The generator's frame suspension mechanism — the same one that makes regular generators work — is what allows the execution to pause at `yield`, run the `with` block, and then resume for teardown. Context managers and generators are more closely related than they appear.
[[generators|Generators]]

---

## Common Misconceptions

Misconception 1: "`with open(file) as f:` is just a nicer way to write `try: f = open(file) ... finally: f.close()`."
Reality: They are functionally similar for the common case, but `with` provides more: `__exit__` receives exception information and can inspect or suppress it, while `finally` cannot. `with` is also more composable — multiple context managers in a single `with` statement, or nesting them, is cleaner than nested try/finally blocks. The `with` statement is the officially recommended pattern because it is more readable and more capable.

Misconception 2: "The `as x` variable in `with obj as x:` is the context manager `obj`."
Reality: `x` is the return value of `obj.__enter__()`, which is not necessarily `obj` itself. For files, `open("f.txt").__enter__()` returns the file object, which happens to be the same as the result of `open()`. But for other context managers — a `threading.Lock`, a `decimal.localcontext()`, or a custom context manager — `__enter__` may return something completely different, or `None`. When in doubt, check what `__enter__` returns, not what you passed to `with`.

---

## Why It Matters in Practice

Context managers are the correct way to handle any resource with setup and teardown. Database connections (`with engine.connect() as conn:`), file handles (`with open(path) as f:`), network sockets, thread locks (`with lock:`), temporary directory creation, database transactions — all of these benefit from the `with` guarantee that teardown always runs. Without `with`, every caller must remember to close/release/commit/rollback, and any code path that forgets — an early return, an unexpected exception — leaks the resource.

`contextlib.contextmanager` in particular makes it trivially easy to convert any setup/teardown pair into a reusable context manager. Instead of writing a class with `__enter__` and `__exit__`, a decorated generator function works just as well in most cases and is far more readable. Tools like `pytest.raises()`, `unittest.mock.patch()`, and `tempfile.TemporaryDirectory()` are all context managers, which is why the `with` pattern is ubiquitous in Python testing and standard library usage.

---

## Interview Angle

Common question forms:
- "What is a context manager in Python?"
- "What is the difference between a `with` statement and try/finally?"
- "How would you write a custom context manager?"

Answer frame: Define a context manager as any object with `__enter__` and `__exit__`. Explain what the `with` statement does: calls `__enter__`, runs the block, calls `__exit__` always. Note that `__exit__` receives exception info and can suppress by returning truthy. Give two implementation options: a class with both methods, or `@contextlib.contextmanager` with a generator and `yield`. Differentiate from try/finally: `__exit__` gets exception info; finally does not.

---

## Related Notes

- [[dunder-methods|Dunder Methods]]
- [[generators|Generators]]
