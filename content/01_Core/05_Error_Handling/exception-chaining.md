---
title: 04 - Exception Chaining
description: "Exception chaining links exceptions causally using __cause__ (explicit, via raise X from Y) and __context__ (implicit, when an exception occurs while handling another)  -  preserving the full history of what went wrong."
tags: [exception-chaining, __cause__, __context__, raise-from, __traceback__, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Exception Chaining

> Exception chaining is Python's mechanism for saying "this error happened because of that error"  -  preserving the full causal story in the traceback so that both the symptom and the root cause are visible.

---

## Quick Reference

**Core idea:**
- `raise NewException from original`  -  explicit chaining; sets `__cause__`; displays "The above exception was the direct cause of the following exception"
- Implicit chaining: exception raised inside `except` block sets `__context__` on the new exception automatically; displays "During handling of the above exception, another exception occurred"
- `raise NewException from None`  -  suppresses chaining display; `__context__` is still set but `__suppress_context__ = True`
- `__traceback__` attribute: the traceback object attached to each exception; `traceback.format_exc()` produces a string
- Chained exceptions form a linked list via `__cause__`/`__context__`  -  Python displays the entire chain on crash

**Tricky points:**
- `raise X from Y` sets `Y` as `X.__cause__` AND sets `X.__suppress_context__ = False`  -  the cause is always shown
- `raise X from None` sets `__suppress_context__ = True`  -  the implicit `__context__` is hidden from the traceback display
- `__context__` is always set when an exception is raised inside an `except` block, regardless of whether `from` is used
- Circular exception chains are detected and truncated by the traceback formatter
- Suppressing with `from None` is appropriate when converting library-specific exceptions to public API exceptions  -  hiding implementation details

---

## What It Is

Imagine a car mechanic who diagnoses a broken engine and, while reaching for a wrench in the dark, drops it and injures their hand. There are now two problems: the broken engine (the original issue) and the injured hand (the new issue that happened while addressing the first). A good incident report captures both  -  "the mechanic injured their hand while attempting to fix the engine." Stripping the report down to just "the mechanic injured their hand" loses critical context about what triggered the sequence of events.

Python exception chaining is that incident report. When code raises an exception, catches it, and raises a different exception  -  whether intentionally (converting a low-level error to a high-level one) or accidentally (a bug inside the exception handler itself)  -  Python records the causal link. The full chain is printed when the program crashes, showing both the original exception and the new one in the order they occurred.

The distinction between explicit and implicit chaining matters for communication. Explicit chaining via `raise X from original` declares intent: "I am transforming this exception, and here is the root cause." Implicit chaining just records the fact: "while I was handling one exception, another one occurred  -  they may or may not be related." `raise X from None` is the escape hatch for cases where you intentionally want to hide the chain  -  typically when you are exposing a clean public API and do not want internal library exceptions leaking out to callers.

---

## How It Actually Works

When Python raises an exception, the C-level `_PyErr_SetObject` stores a reference to any currently-active exception in the new exception's `__context__` field. This happens automatically whenever an exception is raised while another exception is being handled  -  the "currently handling" state is tracked in the thread state (`PyThreadState.exc_info`).

```python
try:
    int("not a number")
except ValueError as e:
    raise RuntimeError("conversion failed")
    # RuntimeError.__context__ is set to the ValueError automatically
```

The `from` clause in `raise X from Y` sets `X.__cause__ = Y` and `X.__suppress_context__ = False`. The traceback formatter uses this when printing: if `__cause__` is set, it prints the chain with the "direct cause" message; if `__suppress_context__` is `False` and `__context__` is set, it prints the chain with the "during handling" message; if `__suppress_context__` is `True`, the `__context__` is silently skipped.

```python
# Explicit: "The above exception was the direct cause..."
try:
    risky_operation()
except LowLevelError as e:
    raise HighLevelError("operation failed") from e

# Suppress: clean public API, hide internal exception
try:
    risky_operation()
except LowLevelError:
    raise HighLevelError("operation failed") from None
```

The `__traceback__` attribute holds the traceback object for the exception  -  a linked list of `frame` objects representing the call stack at the time of the exception. `traceback.print_exception(type(e), e, e.__traceback__)` reproduces the standard traceback output. `traceback.format_exc()` captures it as a string. Traceback objects can be walked manually via `tb.__tb_next` for custom formatting or error reporting.

---

## How It Connects

Exception chaining builds on the exception hierarchy  -  every raised exception is a subclass of `BaseException`, and the chaining attributes (`__cause__`, `__context__`, `__traceback__`) are defined at the `BaseException` level, available on every exception.

[[exceptions|Exceptions]]

Context managers interact with exception chaining  -  when a `__exit__` method raises an exception, the original exception that triggered `__exit__` becomes the `__context__` of the new one.

[[context-managers|Context Managers]]

Custom exception classes should be aware of chaining when converting between exception types. A well-designed library catches internal exceptions and re-raises as public API exceptions, using `from` to preserve the chain or `from None` to suppress it intentionally.

[[custom-exceptions|Custom Exceptions]]

---

## Common Misconceptions

Misconception 1: "Using `raise NewException` inside an `except` block loses the original exception."
Reality: Python automatically sets `NewException.__context__` to the original exception. The original exception is preserved and displayed in the traceback. It is only suppressed if you explicitly write `from None`.

Misconception 2: "`raise X from None` deletes the original exception."
Reality: `from None` sets `__suppress_context__ = True`, which hides the `__context__` from traceback display. The `__context__` attribute is still set on the exception object and is accessible programmatically  -  it is just not shown in the default output.

Misconception 3: "Exception chaining only applies to exceptions you explicitly chain with `from`."
Reality: Implicit chaining happens automatically whenever an exception is raised inside an `except` block. The `from` clause controls explicit chaining and whether the cause is labeled as "direct cause" or "during handling."

---

## Why It Matters in Practice

Losing the original exception context is one of the most frustrating debugging antipatterns. Code that does `except Exception: raise RuntimeError("something went wrong")`  -  without `from`  -  still chains the exceptions (via `__context__`), but code that uses `except Exception: raise RuntimeError(...) from None` intentionally strips the cause. In library code, this distinction is design: preserve the chain in internal error handling so debugging is possible; suppress it at the public API boundary so implementation details do not leak.

In production logging, accessing `exc.__context__` and `exc.__cause__` allows loggers and error reporters to capture the full exception chain, not just the outermost exception. Standard `logging.exception()` and `traceback.format_exc()` include the full chain automatically  -  but custom error reporting that only captures `str(exc)` or `type(exc)` will miss the chain entirely.

---

## Interview Angle

Common question forms:
- "What is the difference between `raise X from Y` and just `raise X` inside an `except` block?"
- "What does `raise X from None` do and when would you use it?"
- "How do you access the original exception that caused a chained exception?"

Answer frame:
`raise X from Y` sets `X.__cause__ = Y` (explicit chaining, shown as "direct cause"). Raising inside `except` implicitly sets `X.__context__` (shown as "during handling"). `raise X from None` sets `__suppress_context__ = True`, hiding the `__context__` from display but not deleting it. Access original: `exc.__cause__` (explicit) or `exc.__context__` (implicit). Use `from None` when hiding library internals from callers.

---

## Related Notes

- [[exceptions|Exceptions]]
- [[exception-hierarchy|Exception Hierarchy]]
- [[context-managers|Context Managers]]
- [[custom-exceptions|Custom Exceptions]]
