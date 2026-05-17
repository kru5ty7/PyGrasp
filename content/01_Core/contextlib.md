---
title: contextlib
description: The `contextlib` module provides utilities for creating context managers — `@contextmanager` converts a generator function into a context manager, `suppress` silences specific exceptions, `ExitStack` dynamically composes multiple context managers, and `nullcontext` is a no-op context manager.
tags: [contextlib, contextmanager, suppress, ExitStack, nullcontext, context-managers, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# contextlib

> The `contextlib` module provides utilities for creating context managers — `@contextmanager` converts a generator function into a context manager, `suppress` silences specific exceptions, `ExitStack` dynamically composes multiple context managers, and `nullcontext` is a no-op context manager.

---

## Quick Reference

**Core idea:**
- `@contextlib.contextmanager` — turns a generator function into a context manager; `yield` is the `with` block entry point; code after `yield` is cleanup
- `contextlib.suppress(*exceptions)` — context manager that silences listed exception types; equivalent to `try: ... except ExceptionType: pass`
- `contextlib.ExitStack()` — context manager that holds a dynamic stack of context managers; use `.enter_context(cm)` to register CMs at runtime
- `contextlib.nullcontext(value)` — a no-op context manager; useful for optional CMs in conditional code
- `contextlib.closing(obj)` — wraps any object with `close()` in a context manager that calls `close()` on exit

**Tricky points:**
- `@contextmanager` function must have exactly one `yield` — the body before `yield` is `__enter__`, the body after is `__exit__`
- If an exception is raised in the `with` block, `@contextmanager` re-raises it at the `yield` point — wrap the `yield` in `try/finally` or `try/except` to handle or suppress it
- `ExitStack.enter_context(cm)` calls `cm.__enter__()` and registers `cm.__exit__` to be called in LIFO order when the stack exits; any exception in cleanup propagates correctly
- `suppress` only suppresses exceptions that occur inside the `with` block, not inside the context manager's own setup code
- `@contextmanager` creates a `_GeneratorContextManager` object — it implements both `__enter__`/`__exit__` and the iterator protocol

---

## What It Is

Think of `contextlib` as a toolkit for composing and creating context managers without writing a full class with `__enter__` and `__exit__`. Writing a class for every context manager would be verbose — `contextlib` provides shorthand for the common patterns.

`@contextmanager` is the most valuable tool: it lets you express the setup → hand control to the `with` block → cleanup pattern as a simple generator function. The `yield` is the handoff. Code before `yield` is setup; code after `yield` is cleanup. The generator's paused state between `yield` and the generator's resumption is the `with` block execution.

`ExitStack` addresses the harder problem: combining a variable number of context managers. When you know at write time that you need `open(file1)` and `open(file2)`, nested `with` works. When you have a list of files determined at runtime, you cannot nest them — `ExitStack` manages them dynamically.

---

## How It Actually Works

`@contextmanager` wraps the generator function in a `_GeneratorContextManager` class:

```python
@contextmanager
def managed_resource(arg):
    resource = setup(arg)       # __enter__ code
    try:
        yield resource          # hands resource to the with block
    finally:
        teardown(resource)      # __exit__ cleanup (always runs)
```

`__enter__` calls `next(generator)` to advance to the `yield`, returning the yielded value. `__exit__` sends the exception (if any) to the generator via `generator.throw(exc)`, or calls `next(generator)` if no exception. If the generator handles the exception and does not re-raise, `__exit__` returns `True` (suppressing the exception).

If no exception management is needed:

```python
@contextmanager
def timer():
    start = time.time()
    yield
    print(f"Elapsed: {time.time() - start:.3f}s")
```

`suppress(*exceptions)`:

```python
with suppress(FileNotFoundError):
    os.remove("tmp.txt")  # silently ignored if file doesn't exist
```

Equivalent to:
```python
try:
    os.remove("tmp.txt")
except FileNotFoundError:
    pass
```

`ExitStack` for dynamic composition:

```python
with ExitStack() as stack:
    files = [stack.enter_context(open(f)) for f in filenames]
    # all files are opened; all will be closed when the with block exits
    process(files)
```

If opening file 3 fails, files 1 and 2 are already on the stack and will be closed during stack cleanup.

---

## How It Connects

`contextlib` tools create context managers — objects that implement `__enter__` and `__exit__`. Understanding the underlying protocol explains how `@contextmanager` works.
[[context-managers|Context Managers]]

`@contextmanager` generator-based context managers are generators that yield exactly once. The generator protocol (`send`, `throw`, `close`) is how exception propagation works through `@contextmanager`.
[[generators|Generators]]

---

## Common Misconceptions

Misconception 1: "If an exception occurs in the `with` block, code after `yield` in a `@contextmanager` function still runs."
Reality: It runs only if you wrap the `yield` in `try/finally`. Without it, the exception is thrown into the generator at the `yield` point, the generator's frame is abandoned, and the finally is not run. Always use `try/finally` around `yield` in cleanup-oriented context managers.

Misconception 2: "`suppress` makes error handling silent and therefore bad."
Reality: `suppress` is appropriate for expected, recoverable conditions where no action is needed. `with suppress(FileNotFoundError): os.remove(tmp_path)` is cleaner than `try/except` for "delete if exists" patterns. The key criterion: suppressing an exception should only happen when you have explicitly decided no action is needed for that case — not as a broad catch-all.

---

## Why It Matters in Practice

`@contextmanager` is the standard way to create simple context managers without writing a full class. Database transaction managers, temporary directory management, mock patching, and timer utilities are all naturally expressed as generator-based context managers.

`ExitStack` is essential for dynamic resource management. Processing a variable-length list of files, acquiring a set of locks determined at runtime, or registering cleanup callbacks in a function — all require `ExitStack`.

`contextlib.asynccontextmanager` (not in Quick Reference) is the async version of `@contextmanager` — used for `async with` statements in `asyncio` code.

---

## Interview Angle

Common question forms:
- "How do you create a context manager without a class?"
- "What is `contextlib.suppress`?"

Answer frame: `@contextlib.contextmanager` wraps a generator function — code before `yield` is setup (`__enter__`), code after `yield` is cleanup (`__exit__`). Wrap `yield` in `try/finally` to guarantee cleanup. `suppress(ExcType)` silences specific exceptions — cleaner than `try/except: pass`. `ExitStack` dynamically composes a variable number of context managers, calling their `__exit__` in LIFO order. `nullcontext` is a no-op CM for conditional contexts.

---

## Related Notes

- [[context-managers|Context Managers]]
- [[generators|Generators]]
- [[exceptions|Exceptions]]
