---
title: 02 - Exception Hierarchy
description: "Python's exception classes form a tree rooted at `BaseException`  -  `Exception` is the base for all regular errors; `SystemExit`, `KeyboardInterrupt`, and `GeneratorExit` sit directly under `BaseException` and should not be caught routinely; knowing the hierarchy determines which `except` clause catches which errors."
tags: [exception-hierarchy, BaseException, Exception, built-in-exceptions, OSError, ValueError, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Exception Hierarchy

> Python's exception classes form a tree rooted at `BaseException`  -  `Exception` is the base for all regular errors; `SystemExit`, `KeyboardInterrupt`, and `GeneratorExit` sit directly under `BaseException` and should not be caught routinely; knowing the hierarchy determines which `except` clause catches which errors.

---

## Quick Reference

**Core idea (abridged hierarchy):**
```
BaseException
├── SystemExit           # sys.exit()
├── KeyboardInterrupt    # Ctrl+C
├── GeneratorExit        # generator.close()
└── Exception
    ├── ArithmeticError
    │   ├── ZeroDivisionError
    │   └── OverflowError
    ├── LookupError
    │   ├── IndexError
    │   └── KeyError
    ├── OSError (= IOError)
    │   ├── FileNotFoundError
    │   ├── PermissionError
    │   └── TimeoutError
    ├── ValueError
    ├── TypeError
    ├── AttributeError
    ├── NameError
    ├── RuntimeError
    │   └── RecursionError
    ├── StopIteration
    └── Warning
        ├── DeprecationWarning
        └── UserWarning
```
- `isinstance(e, LookupError)` is `True` for both `IndexError` and `KeyError`  -  catching a base class catches all subclasses
- `OSError`, `IOError`, `EnvironmentError` are all the same class in Python 3

**Tricky points:**
- `except Exception` does **not** catch `SystemExit`, `KeyboardInterrupt`, or `GeneratorExit`  -  these require `except BaseException` or targeting them explicitly
- `StopIteration` is under `Exception`  -  it can be caught by `except Exception:`; in generators, it is converted to `RuntimeError` (PEP 479)
- `MemoryError` and `RecursionError` are recoverable exceptions (under `Exception`), but attempting recovery is usually futile
- `Warning` subclasses are also `Exception` subclasses  -  they can be raised and caught like any exception
- User-defined exception classes should inherit from `Exception` (not `BaseException`) unless they are meant to bypass all normal except clauses

---

## What It Is

Think of the exception hierarchy as a taxonomy  -  the same way animals are grouped into species, genus, family, and so on. Catching `OSError` is like catching "any file system problem"  -  it encompasses `FileNotFoundError`, `PermissionError`, `TimeoutError`, and others. Catching `FileNotFoundError` is a more specific catch. The hierarchy lets you write exception handlers at the right level of granularity.

The `BaseException`/`Exception` split is the most important design decision in the hierarchy. `SystemExit` is raised by `sys.exit()`  -  it is supposed to propagate up and exit the program. If `except Exception` caught it, a `sys.exit()` call inside a deeply nested function would silently fail. By placing it under `BaseException`, the `except Exception` catch-all correctly ignores it. The same applies to `KeyboardInterrupt`  -  Ctrl+C should kill the program, not be silently swallowed by error handling.

---

## How It Actually Works

`except E:` uses `isinstance(exception, E)` for matching. Because `isinstance` traverses the class hierarchy, catching a parent class catches all subclasses. The `except` clauses in a `try` block are checked in order  -  the first match wins, so more specific exceptions should come before more general ones.

```python
try:
    f()
except FileNotFoundError:    # more specific first
    handle_missing()
except OSError:               # catches other OS errors
    handle_os_error()
```

If `OSError` came first, `FileNotFoundError` would be caught by it and `FileNotFoundError` handler would never run.

`OSError` unification: in Python 3, `IOError`, `EnvironmentError`, `WindowsError`, and `socket.error` are all aliases for `OSError`. Legacy code catching these aliases works, but they are all the same class.

`ExceptionGroup` (Python 3.11+) is a new `BaseException` subclass that holds multiple exceptions  -  used for concurrent code where multiple errors may occur simultaneously. `except*` syntax handles `ExceptionGroup` by type.

---

## How It Connects

Understanding the hierarchy is prerequisite to writing correct exception handlers. Catching the right level prevents both swallowing unexpected errors (too broad) and missing related errors (too narrow).
[[exceptions|Exceptions]]

Custom exceptions should be placed correctly in the hierarchy  -  inherit from a specific built-in exception that semantically matches the error category.
[[custom-exceptions|Custom Exceptions]]

---

## Common Misconceptions

Misconception 1: "`except Exception` catches all exceptions."
Reality: `except Exception` catches all exceptions under `Exception`, but not `SystemExit`, `KeyboardInterrupt`, or `GeneratorExit`  -  these are direct subclasses of `BaseException`, not `Exception`. Code like `while True: try: ... except Exception: ...` still exits on Ctrl+C.

Misconception 2: "`except (ValueError, TypeError)` is equivalent to `except ValueError: ... except TypeError:`."
Reality: They have different semantics. `except (ValueError, TypeError):` catches either and handles them with the same handler code. `except ValueError: ...; except TypeError: ...` has separate handlers for each type. They produce the same result only if the handler code is identical, but the tuple form is more concise.

---

## Why It Matters in Practice

Catching `LookupError` instead of listing `(KeyError, IndexError)` is cleaner and future-proof  -  if new LookupError subclasses are added, they are automatically caught.

Library error hierarchies mirror the built-in pattern. `requests.RequestException` is the base for all requests errors; `requests.ConnectionError`, `requests.Timeout` are subclasses. Catching the base gives a catch-all; catching subclasses gives specific handling.

`except OSError as e: if e.errno == errno.ENOENT: ...`  -  sometimes you need to catch `OSError` broadly but handle specific error codes differently. This pattern avoids separate `except FileNotFoundError` clauses when you need the general `OSError` for cleanup anyway.

---

## Interview Angle

Common question forms:
- "What is the difference between `BaseException` and `Exception`?"
- "Why shouldn't you use bare `except:`?"

Answer frame: The hierarchy is rooted at `BaseException`. `SystemExit`, `KeyboardInterrupt`, and `GeneratorExit` are direct `BaseException` subclasses  -  they should not be caught by routine error handling. `Exception` is the base for all regular errors; `except Exception` is the safe catch-all. Matching uses `isinstance`  -  catching a parent catches all children. More specific `except` clauses must come before more general ones. User exceptions should inherit from `Exception`.

---

## Related Notes

- [[exceptions|Exceptions]]
- [[custom-exceptions|Custom Exceptions]]
- [[context-managers|Context Managers]]
