---
title: 01 - Testing Basics
description: "Software testing verifies that code behaves correctly — unit tests test individual functions in isolation, integration tests test components together, end-to-end tests test the whole system; the test pyramid suggests many unit tests, fewer integration tests, and even fewer E2E tests."
tags: [testing, unit-tests, integration-tests, test-pyramid, assertions, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# Testing Basics

> Software testing verifies that code behaves correctly — unit tests test individual functions in isolation, integration tests test components together, end-to-end tests test the whole system; the test pyramid suggests many unit tests, fewer integration tests, and even fewer E2E tests.

---

## Quick Reference

**Core idea:**
- **Unit test**: tests a single function/class in isolation; fast; no external dependencies (DB, network mocked)
- **Integration test**: tests multiple components together (e.g., FastAPI handler + real database); slower
- **End-to-end (E2E)**: tests the full system as a user would; slowest; most brittle
- **Test pyramid**: many unit tests (cheap) → fewer integration tests → very few E2E tests
- Arrange-Act-Assert (AAA) pattern: setup → call the thing → verify the result

**Tricky points:**
- Unit tests should be fast (<10ms each) — testing is run frequently; slow tests discourage running them
- Isolation via mocking: `unittest.mock.patch` or `pytest-mock` replace real dependencies with controllable fakes — but mock what you own, not third-party libraries directly
- **False confidence from mocks**: mocking too aggressively means your tests pass but the real system fails; integration tests catch what unit tests miss
- Tests should be deterministic — a test that sometimes passes and sometimes fails (flaky test) is worse than no test
- Test naming: `test_create_user_returns_201_on_valid_input` is better than `test_create_user` — describes the expected behavior

---

## What It Is

Testing is the practice of verifying that code does what it's supposed to do, catches regressions (code that was working but broke after a change), and documents intended behavior. A test suite that runs in seconds and catches bugs before they reach production is one of the highest-leverage investments in a codebase.

The test pyramid provides a guideline for test distribution: unit tests are the base (many, fast, cheap), integration tests in the middle, E2E tests at the top (few, slow, expensive). Over-relying on E2E tests makes the suite slow and brittle; under-testing at the integration level misses real-world failure modes.

---

## How It Actually Works

AAA pattern:
```python
def test_calculate_discount():
    # Arrange
    price = 100.0
    discount_percent = 20
    
    # Act
    result = calculate_discount(price, discount_percent)
    
    # Assert
    assert result == 80.0
```

Testing error cases:
```python
import pytest

def test_divide_by_zero_raises():
    with pytest.raises(ZeroDivisionError):
        divide(10, 0)

def test_negative_age_raises_value_error():
    with pytest.raises(ValueError, match="age must be non-negative"):
        User(name="Alice", age=-1)
```

Parametrize to test multiple inputs:
```python
@pytest.mark.parametrize("input,expected", [
    (0, True),
    (1, False),
    (-1, False),
    (100, False),
])
def test_is_zero(input, expected):
    assert is_zero(input) == expected
```

What to test:
- Happy path: typical valid input produces correct output
- Error path: invalid input raises expected exception / returns error
- Edge cases: empty list, zero, None, maximum value, minimum value
- Boundary conditions: first/last element, exactly at a limit

---

## How It Connects

Pytest is the standard test runner for Python — understanding testing basics is the prerequisite for using pytest's fixtures and parametrize.
[[pytest|Pytest]]

FastAPI apps are tested with `TestClient` or `AsyncClient` — integration tests that exercise the full request-response cycle.
[[testing-fastapi|Testing FastAPI]]

---

## Common Misconceptions

Misconception 1: "100% code coverage means the code is well-tested."
Reality: Coverage measures which lines are executed, not which behaviors are verified. A test that calls every function but never checks the output has 100% coverage with zero assertions. Coverage is a useful floor, not a ceiling.

Misconception 2: "Tests slow down development."
Reality: Tests slow down the first hour and speed up every hour after. Finding a bug with a test takes minutes; finding it in production takes hours. A test suite that catches regressions in seconds is faster than manually re-testing every feature after each change.

---

## Why It Matters in Practice

Test categories in a web app:
```
Unit tests (fast):
  - Business logic functions
  - Pydantic validators
  - Utility functions
  
Integration tests (medium):
  - FastAPI endpoints with a test database
  - Database queries with real data
  
E2E tests (slow):
  - Full user flows (register → login → create resource → delete)
  - Browser-based tests (Playwright, Selenium)
```

The goal: catch bugs as early and cheaply as possible. A bug caught by a unit test is cheaper than one caught by QA, which is cheaper than one caught in production.

---

## Interview Angle

Common question forms:
- "What is the test pyramid?"
- "What is the difference between unit and integration tests?"

Answer frame: **Unit tests** test one function in isolation with dependencies mocked — fast, many. **Integration tests** test components together with real infrastructure — slower, fewer. **E2E tests** test the full system — slowest, fewest. Test pyramid: many unit, fewer integration, very few E2E. AAA pattern: Arrange, Act, Assert. Tests catch regressions — invest in them early to save time later.

---

## Related Notes

- [[pytest|Pytest]]
- [[fixtures|Fixtures]]
- [[mocking|Mocking]]
- [[testing-fastapi|Testing FastAPI]]
