---
title: Exceptions
description: "Python uses exceptions for error signaling — `raise` throws an exception object, `try/except` catches it, `else` runs if no exception occurred, `finally` always runs for cleanup; exceptions propagate up the call stack until caught or they crash the program with a traceback."
tags: [exceptions, try-except, raise, finally, exception-handling, traceback, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Exceptions

> Python uses exceptions for error signaling — `raise` throws an exception object, `try/except` catches it, `else` runs if no exception occurred, `finally` always runs for cleanup; exceptions propagate up the call stack until caught or they crash the program with a traceback.

---

## Quick Reference

**Core idea:**
- `raise ValueError("message")` — creates and raises an exception; execution jumps to the nearest matching `except` block
- `try/except ExceptionType as e:` — catches exceptions of that type (and subclasses)
- `try/except (TypeError, ValueError):` — catches multiple exception types
- `try/else:` — `else` block runs only if the `try` block completed without raising
- `try/finally:` — `finally` block always runs (even if the `try` raised or returned)
- `raise ... from original` — chains exceptions; sets `__cause__`; `raise ... from None` suppresses chaining

**Tricky points:**
- Bare `except:` catches everything including `SystemExit`, `KeyboardInterrupt`, `GeneratorExit` — use `except Exception:` to catch all "regular" exceptions without catching system-exit signals
- The `except` clause binds `e` to the exception, but the name `e` is **deleted** at the end of the `except` block to prevent reference cycles
- `raise` (with no argument) inside `except` re-raises the current exception — useful for logging and re-raising
- Exception objects store `__traceback__` — a traceback linked list; accessing `e.__traceback__` gives the traceback object
- `try/except/else/finally` can all be combined: `try: ... except E: ... else: ... finally: ...`

---

## What It Is

Think of a try/except block as a safety net beneath a tightrope walker. The walker proceeds along the rope (the `try` block). If they fall (an exception is raised), the safety net (the `except` block) catches them and handles the situation. The ground crew (the `finally` block) comes out regardless — whether the walker finished gracefully or fell. And the applause (the `else` block) happens only if the walker finished without falling.

Python uses exceptions for all error conditions — file not found, invalid type, index out of range, network timeout. Unlike languages where errors are return values, Python's exceptions automatically propagate up the call stack until caught. This means you can write the "happy path" without checking every return value for errors, and handle all errors at the appropriate layer.

The alternative approach — using return codes or sentinel values — requires every caller to check and propagate errors manually. Exception propagation handles this automatically: if no one catches a `ValueError` raised 5 levels deep, it bubbles up to the top level and crashes with a traceback showing exactly where the error occurred.

---

## How It Actually Works

When `raise ExceptionType("message")` is executed:
1. An exception instance is created with the message as its argument
2. CPython sets the current exception in the thread state: `type`, `value`, `traceback`
3. CPython begins unwinding the call stack, frame by frame
4. Each frame is checked for matching `except` blocks
5. If a match is found, the `except` block is entered and execution continues
6. If no match is found and the stack is empty, Python prints the traceback and exits

The `try/except/else/finally` structure compiles to a series of exception table entries. CPython's exception table maps bytecode ranges to handler addresses. When an exception is raised, the interpreter finds the innermost matching handler and jumps there.

`except E as e:` — `E` is checked with `isinstance(exception, E)`. Because `isinstance` is used, catching a base class catches all subclasses. `except Exception` catches all exceptions in the `Exception` hierarchy (which excludes `BaseException` subclasses like `SystemExit` and `KeyboardInterrupt`).

Exception chaining: `raise NewError("msg") from original_error` sets `NewError.__cause__ = original_error`. The traceback then shows both exceptions. `raise NewError() from None` sets `__suppress_context__ = True`, hiding any implicit chaining.

The `else` block is often overlooked but useful: code in `else` runs if `try` completed normally, but it is *not* covered by the `except` — exceptions in `else` propagate to the caller.

---

## How It Connects

Custom exceptions extend the exception hierarchy — subclassing `Exception` or more specific base classes allows callers to catch errors at the right level of specificity.
[[custom-exceptions|Custom Exceptions]]

Context managers use exceptions internally — `__exit__` receives exception information and can suppress exceptions by returning `True`. The `with` statement's cleanup behavior is related to `finally`.
[[context-managers|Context Managers]]

---

## Common Misconceptions

Misconception 1: "Bare `except:` is safe to use as a catch-all."
Reality: Bare `except:` catches `SystemExit` (raised when `sys.exit()` is called), `KeyboardInterrupt` (raised on Ctrl+C), and `GeneratorExit`. Catching these prevents the program from exiting. Always use `except Exception:` as the catch-all — it catches all "user-level" exceptions while letting system-exit signals propagate.

Misconception 2: "`finally` runs after `except`."
Reality: `finally` runs after the entire `try/except` block — including after any `except` handler. If `except` re-raises or raises a new exception, `finally` still runs before the new exception propagates. If the `try` block returns, `finally` runs before the return value is passed to the caller. `finally` is guaranteed to run unless the process is killed with SIGKILL.

---

## Why It Matters in Practice

EAFP (Easier to Ask Forgiveness than Permission) is the Pythonic exception-handling philosophy. Rather than checking `if key in d: return d[key]`, use `try: return d[key] except KeyError: return default`. EAFP is cleaner and avoids race conditions (the check and access are not atomic).

`try/finally` is the manual resource cleanup pattern before context managers. It ensures cleanup code runs even if an exception occurs. For resources that implement `__enter__`/`__exit__`, the `with` statement replaces `try/finally`.

Re-raising with context: `except Exception as e: logger.error(e); raise` — log the error and let it propagate. The bare `raise` re-raises the current exception with its original traceback intact.

---

## Interview Angle

Common question forms:
- "What is the difference between `except Exception` and bare `except:`?"
- "When does `else` run in a try block?"
- "What does `finally` do?"

Answer frame: `raise` creates and throws an exception; it propagates up the stack until caught by a matching `except`. Bare `except:` catches everything including `SystemExit`/`KeyboardInterrupt` — use `except Exception:` instead. `else` runs if the `try` block completes without raising (not covered by `except`). `finally` always runs — even if an exception was raised, re-raised, or `return` was executed. `raise ... from original` chains exceptions; `raise ... from None` suppresses chaining.

---

## Related Notes

- [[custom-exceptions|Custom Exceptions]]
- [[exception-hierarchy|Exception Hierarchy]]
- [[context-managers|Context Managers]]
- [[contextlib|contextlib]]
