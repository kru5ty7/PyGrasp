---
title: 04 - Mocking
description: "Mocking replaces real dependencies with controllable fakes during testing  -  `unittest.mock.patch` temporarily replaces an object; `MagicMock` is a flexible stand-in; `pytest-mock` provides the `mocker` fixture; use mocks to isolate unit tests from external services (databases, APIs, file systems)."
tags: [mocking, unittest-mock, patch, MagicMock, pytest-mock, side_effect, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Mocking

> Mocking replaces real dependencies with controllable fakes during testing  -  `unittest.mock.patch` temporarily replaces an object; `MagicMock` is a flexible stand-in; `pytest-mock` provides the `mocker` fixture; use mocks to isolate unit tests from external services (databases, APIs, file systems).

---

## Quick Reference

**Core idea:**
- `from unittest.mock import patch, MagicMock, AsyncMock`
- `@patch("mymodule.requests.get")`  -  replaces `requests.get` within `mymodule` during the test
- `mock.return_value = x`  -  set what the mock returns when called
- `mock.side_effect = Exception(...)`  -  make the mock raise an exception
- `mock.assert_called_once_with(arg)`  -  verify the mock was called correctly
- `AsyncMock`  -  for mocking `async def` functions (returns an awaitable)

**Tricky points:**
- Patch the name where it's used, not where it's defined  -  `@patch("myapp.services.requests.get")` not `@patch("requests.get")` if `myapp.services` imports `requests`
- `MagicMock` auto-creates attributes and methods on access  -  `mock.anything.chained.call()` works without setup; this can hide typos in attribute names
- `spec=SomeClass`  -  mock that only allows attributes/methods that exist on `SomeClass`; prevents attribute typos in tests
- `AsyncMock` for async functions  -  `MagicMock` returns a regular value, not a coroutine; calling `await mock()` on a `MagicMock` raises `TypeError`
- Over-mocking: mocking implementation details (private methods, internal state) creates brittle tests that break on refactoring; mock at the boundary (external APIs, I/O)

---

## What It Is

Mocking allows you to test code in isolation by replacing dependencies with controlled fakes. A function that calls an external API, writes to a file, or queries a database is hard to test without the real infrastructure. A mock replaces the dependency with an object you control: you specify what it returns, verify it was called correctly, and make it raise exceptions to test error paths.

The key principle: mock at the boundary between your code and the outside world. Don't mock internal Python functions or your own business logic  -  those should be tested with real behavior.

---

## How It Actually Works

`patch` as decorator:
```python
from unittest.mock import patch, MagicMock

@patch("myapp.email.send_email")
def test_registration_sends_email(mock_send_email):
    mock_send_email.return_value = True
    
    register_user("alice@example.com", "password")
    
    mock_send_email.assert_called_once_with(
        to="alice@example.com",
        template="welcome",
    )
```

`patch` as context manager:
```python
def test_get_user_calls_api():
    with patch("myapp.client.requests.get") as mock_get:
        mock_get.return_value.json.return_value = {"id": 1, "name": "Alice"}
        mock_get.return_value.status_code = 200
        
        result = get_user_from_api(1)
        assert result["name"] == "Alice"
```

`side_effect` for exceptions and sequences:
```python
@patch("myapp.db.get_user")
def test_retries_on_db_error(mock_get):
    # First call raises, second succeeds
    mock_get.side_effect = [ConnectionError("timeout"), {"id": 1}]
    
    result = get_user_with_retry(1)
    assert result == {"id": 1}
    assert mock_get.call_count == 2
```

`AsyncMock` for async functions:
```python
from unittest.mock import AsyncMock, patch

@patch("myapp.services.fetch_user", new_callable=AsyncMock)
async def test_async_handler(mock_fetch):
    mock_fetch.return_value = User(id=1, name="Alice")
    
    result = await get_user_handler(1)
    assert result.name == "Alice"
    mock_fetch.assert_awaited_once_with(1)
```

`pytest-mock`  -  cleaner syntax via `mocker` fixture:
```python
def test_with_mocker(mocker):
    mock_send = mocker.patch("myapp.email.send_email")
    mock_send.return_value = True
    
    register_user("alice@example.com")
    
    mock_send.assert_called_once()
    # auto-cleaned up after test  -  no need for context manager or decorator
```

---

## How It Connects

Mocking is used in unit tests to isolate functions from their dependencies  -  together with fixtures, it's how you set up unit test environments.
[[fixtures|Fixtures]]

In FastAPI testing, `dependency_overrides` is the preferred alternative to mocking for replacing dependencies  -  it works at the FastAPI level rather than patching Python names.
[[testing-fastapi|Testing FastAPI]]

---

## Common Misconceptions

Misconception 1: "Mock the module where it's defined."
Reality: Patch where the name is used. If `myapp.services` does `import requests`, patch `myapp.services.requests.get`, not `requests.get`. Python looks up names in the module's namespace; patching the original module doesn't affect already-imported references.

Misconception 2: "More mocking = more isolated = better tests."
Reality: Over-mocking tests implementation details rather than behavior. Tests that mock every function call break when you refactor (even if behavior is unchanged). Mock at the boundary (HTTP calls, file I/O, external services) and test business logic with real code.

---

## Why It Matters in Practice

When to mock vs. use real implementations:
```
Mock:
  - External HTTP APIs (requests to third-party services)
  - Email sending, SMS, push notifications
  - File system operations in unit tests
  - Time (datetime.now()) for deterministic tests

Use real:
  - Database (use a test DB with transactions rolled back)
  - Business logic functions (test them directly)
  - Internal module functions (refactor makes mocks break)
```

`freezegun` for time mocking:
```python
from freezegun import freeze_time

@freeze_time("2026-01-01 12:00:00")
def test_token_expiry():
    token = create_token(expires_in=3600)
    assert not is_expired(token)  # 12:00 + 1h = 13:00
    
    # advance time
    with freeze_time("2026-01-01 14:00:00"):
        assert is_expired(token)  # past expiry
```

---

## Interview Angle

Common question forms:
- "How do you mock an external API call in tests?"
- "What is the difference between `patch` and `MagicMock`?"

Answer frame: `MagicMock` is a flexible fake object  -  set `.return_value`, `.side_effect`, check `.assert_called_once_with()`. `patch` temporarily replaces a name in a module with a mock  -  patch where it's used, not where it's defined. `AsyncMock` for async functions. `side_effect=Exception` to test error handling. For FastAPI: prefer `dependency_overrides` over patching to replace dependencies.

---

## Related Notes

- [[pytest|Pytest]]
- [[fixtures|Fixtures]]
- [[testing-fastapi|Testing FastAPI]]
- [[testing-basics|Testing Basics]]
