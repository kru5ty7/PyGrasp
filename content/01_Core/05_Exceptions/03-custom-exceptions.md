---
title: 03 - Custom Exceptions
description: "Custom exceptions are user-defined exception classes that inherit from `Exception` or a more specific built-in — they allow callers to catch library-specific errors precisely, carry structured error data as attributes, and form their own hierarchy for graduated exception handling."
tags: [custom-exceptions, exception-hierarchy, Exception, error-handling, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Custom Exceptions

> Custom exceptions are user-defined exception classes that inherit from `Exception` or a more specific built-in — they allow callers to catch library-specific errors precisely, carry structured error data as attributes, and form their own hierarchy for graduated exception handling.

---

## Quick Reference

**Core idea:**
- `class MyError(Exception): pass` — minimal custom exception; inheritable; catchable with `except MyError:`
- Inherit from a specific built-in when semantics match: `class ValidationError(ValueError): pass`
- Add context via attributes in `__init__`: `self.field = field`, `self.message = message`
- Create a hierarchy for graduated handling: `LibraryError` → `NetworkError`, `AuthError`, `ParseError`
- Override `__str__` for a custom human-readable message; `args` is set by `Exception.__init__`

**Tricky points:**
- Always call `super().__init__(message)` — `Exception.__init__` sets `self.args`, which `str(e)` and `repr(e)` use; skipping it breaks these
- Inheriting from multiple exceptions: `class AppError(ValueError, RuntimeError): pass` — valid, but rarely necessary; signals the error is both kinds
- Custom exceptions should **not** inherit from `BaseException` directly — callers use `except Exception:` as a catch-all; inheriting from `BaseException` bypasses this
- Exception class names conventionally end with `Error` (e.g., `ValidationError`, `NetworkError`) — warnings end with `Warning`
- `raise MyError("msg") from original` preserves the original exception as `__cause__` — important for chaining when converting low-level to high-level exceptions

---

## What It Is

Think of the difference between a general "machinery malfunction" alert and specific alerts for "motor overheating," "belt slippage," and "pressure drop." The general alert tells you something is wrong. The specific alerts tell you exactly what is wrong so you can take the right action. Custom exceptions are the specific alerts: they carry the semantic information that lets callers decide how to respond.

A library that only raises `Exception` forces callers to catch `Exception` broadly or parse error messages to understand what went wrong. A library with `ConnectionError`, `AuthenticationError`, and `RateLimitError` allows callers to handle each case appropriately: retry on `ConnectionError`, re-authenticate on `AuthenticationError`, back off on `RateLimitError`.

The hierarchy pattern — a base exception for the library, with specific subclasses — lets some callers catch the specific error and others catch the base class for a general handler. The caller controls the granularity.

---

## How It Actually Works

A minimal custom exception:

```python
class AppError(Exception):
    pass
```

With structured data:

```python
class ValidationError(ValueError):
    def __init__(self, field: str, message: str) -> None:
        self.field = field
        self.message = message
        super().__init__(f"{field}: {message}")
```

The `super().__init__(...)` call stores the message in `self.args[0]`. `str(e)` returns `self.args[0]`; `repr(e)` returns `ClassName(args)`.

A library hierarchy:

```python
class LibraryError(Exception):
    """Base class for all library errors."""

class NetworkError(LibraryError):
    """Raised on network connectivity problems."""

class AuthError(LibraryError):
    """Raised when authentication fails."""
    def __init__(self, user: str) -> None:
        self.user = user
        super().__init__(f"Authentication failed for user: {user}")
```

Callers can catch `LibraryError` for a catch-all, or `AuthError` for specific handling. `isinstance(e, LibraryError)` is `True` for all subclasses.

Exception conversion (low-level to high-level):

```python
try:
    connect()
except ConnectionRefusedError as e:
    raise NetworkError("Could not connect to server") from e
```

The `from e` preserves the original exception as `__cause__`, and the traceback shows both errors.

---

## How It Connects

Custom exceptions should be placed correctly in the built-in hierarchy — inheriting from `ValueError` for validation errors, `RuntimeError` for logic errors, `OSError` for system resource errors, or plain `Exception` for library-specific errors with no built-in analogue.
[[exception-hierarchy|Exception Hierarchy]]

Exception chaining (`raise ... from ...`) is the mechanism for converting low-level exceptions to high-level custom exceptions while preserving the original cause.
[[exceptions|Exceptions]]

---

## Common Misconceptions

Misconception 1: "Custom exceptions need a lot of implementation."
Reality: `class MyError(Exception): pass` is a complete, usable custom exception. It can be raised, caught, and carries a message via `Exception.__init__`. Add `__init__` overrides only when you need structured data beyond a string message.

Misconception 2: "Custom exceptions should inherit from `BaseException` to ensure they are never accidentally swallowed."
Reality: Inheriting from `BaseException` makes the exception bypass `except Exception:` — which is the broad catch-all most code uses. This breaks normal error handling in callers. Only exceptions that need to bypass normal handling (like `SystemExit`) should inherit from `BaseException`. Library exceptions should inherit from `Exception`.

---

## Why It Matters in Practice

API client libraries use custom exceptions to abstract HTTP errors. `requests.HTTPError` (400/500 responses) and `requests.ConnectionError` (network failure) let callers handle each case without checking status codes in except blocks.

Validation frameworks raise `ValidationError` with field and message attributes so the caller can build error responses or user feedback from structured data — not just a string.

Re-raising with context is essential in library code. When a `json.JSONDecodeError` occurs while parsing a config file, `raise ConfigError(f"Invalid config at line {e.lineno}") from e` gives the user a library-level error with context, while preserving the original low-level error in the traceback for debugging.

---

## Interview Angle

Common question forms:
- "How do you define a custom exception in Python?"
- "When should you use a custom exception?"

Answer frame: Subclass `Exception` (or a more specific built-in if the semantics match). Call `super().__init__(message)` to set `args`. Add `__init__` attributes for structured error data. Create a hierarchy: a library base exception and specific subclasses — callers can catch at any level. Convert low-level exceptions to high-level ones with `raise LibraryError("msg") from original_exc` to preserve the cause chain.

---

## Related Notes

- [[exception-hierarchy|Exception Hierarchy]]
- [[exceptions|Exceptions]]
- [[context-managers|Context Managers]]
