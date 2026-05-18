---
title: 07 - Parametrize
description: "pytest.mark.parametrize runs a single test function multiple times with different input sets, eliminating duplicate test functions and surfacing each case as a distinct test in the results."
tags: [pytest, parametrize, testing, test-cases, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Parametrize

> `@pytest.mark.parametrize` is pytest's test multiplication operator — write one test body and feed it a list of input/expected pairs, getting a separate, named test run for each case.

---

## Quick Reference

**Core idea:**
- `@pytest.mark.parametrize('arg, expected', [(input1, output1), (input2, output2)])` — runs the test once per tuple
- Multiple parameters in one decorator: `'x, y, z'` — pytest unpacks each tuple positionally
- `pytest.param(value, marks=pytest.mark.skip, id='case_name')` — per-case marks (skip, xfail) and custom IDs
- Combining with fixtures: parametrized test + parametrized fixture = cartesian product of all combinations
- `--collect-only` lists all generated test IDs; `-k 'case_name'` runs matching subset

**Tricky points:**
- Parametrize IDs are auto-generated from argument values — they can be cryptic for complex objects; use `ids=` or `pytest.param(..., id='name')` for readable names
- Multiple `@pytest.mark.parametrize` decorators on one function create a cartesian product — every combination of every parameter set runs
- Boolean arguments generate confusing IDs: `True` and `False` become `arg0` and `arg1`; always use explicit `ids` or `pytest.param`
- `pytest.mark.parametrize` with a single argument still requires the values as a list: `@pytest.mark.parametrize('x', [1, 2, 3])` not `[(1,), (2,), (3,)]`
- Indirect parametrization (`indirect=True`) passes values to a fixture rather than directly to the test function — used when the parameter needs preprocessing

---

## What It Is

Without `parametrize`, a test suite for a function with multiple input cases looks like a list of nearly identical functions — each with a different set of inputs pasted in. This repetition is not just aesthetically unpleasant; it is a maintenance liability. When the function under test changes its signature or behavior, every copy of the test must be updated. The only thing different between the copies is the data, yet the code structure treats them as separate entities.

`@pytest.mark.parametrize` separates the test logic from the test data. The test body is written once. The data — all the input/expected pairs — lives in a list attached to the decorator. pytest runs the function once for each item in that list, creating a distinct test case with its own name, its own pass/fail status, and its own error output. The test suite output shows each case individually, making it immediately clear which inputs pass and which fail.

This design has a second important property: it makes the set of tested cases visible as a list. When reviewing a pull request, someone can look at the `parametrize` decorator and see at a glance what cases are covered. Edge cases that are missing are conspicuous by their absence in the list. Adding a new case is a one-line addition to the data list — no new function, no copy-pasting.

---

## How It Actually Works

The basic pattern pairs input arguments with expected outputs in a list of tuples.

```python
import pytest
from myapp.math import add, divide

@pytest.mark.parametrize("a, b, expected", [
    (1, 2, 3),
    (0, 0, 0),
    (-1, 1, 0),
    (100, -50, 50),
])
def test_add(a, b, expected):
    assert add(a, b) == expected

# Exception testing with parametrize
@pytest.mark.parametrize("a, b, exc_type", [
    (10, 2, None),           # no exception expected
    (10, 0, ZeroDivisionError),  # exception expected
])
def test_divide(a, b, exc_type):
    if exc_type:
        with pytest.raises(exc_type):
            divide(a, b)
    else:
        result = divide(a, b)
        assert result == a / b
```

`pytest.param()` wraps individual parameter sets to add metadata — custom IDs, skip marks, or expected failure marks.

```python
@pytest.mark.parametrize("value, expected", [
    pytest.param(None, ValueError, id="none_input"),
    pytest.param("", ValueError, id="empty_string"),
    pytest.param("  ", ValueError, id="whitespace_only"),
    pytest.param("alice", "alice", id="valid_lowercase"),
    pytest.param(
        "A" * 1000,
        ValueError,
        marks=pytest.mark.xfail(reason="length validation not yet implemented"),
        id="too_long",
    ),
])
def test_validate_username(value, expected):
    if expected is ValueError:
        with pytest.raises(ValueError):
            validate_username(value)
    else:
        assert validate_username(value) == expected
```

Stacking multiple `@pytest.mark.parametrize` decorators creates a cartesian product — every combination of both parameter sets.

```python
@pytest.mark.parametrize("method", ["GET", "POST", "PUT"])
@pytest.mark.parametrize("status", [200, 400, 404, 500])
def test_response_logging(method, status):
    # Runs 12 times: 3 methods × 4 statuses
    log_entry = format_log_entry(method, status)
    assert log_entry["method"] == method
    assert log_entry["status"] == status
```

Indirect parametrization passes values to a fixture for preprocessing.

```python
@pytest.fixture
def user(request):
    # request.param is the value passed via indirect
    role = request.param
    return create_test_user(role=role)

@pytest.mark.parametrize("user", ["admin", "editor", "viewer"], indirect=True)
def test_user_permissions(user):
    assert user.role in ["admin", "editor", "viewer"]
```

---

## How It Connects

`parametrize` is most powerful when combined with fixtures — fixtures set up shared context while parametrize varies the data inputs.

[[fixtures|Fixtures]]

Property-based testing with Hypothesis is a complementary approach — instead of listing cases manually, Hypothesis generates them automatically.

[[hypothesis|Hypothesis (Property-Based Testing)]]

---

## Common Misconceptions

Misconception 1: "Parametrized tests are less readable than individual test functions."
Reality: Individual test functions for each case scatter the test logic across many functions with identical bodies. `parametrize` centralizes the logic and makes the set of covered cases visible as a single list. For reviewers and future maintainers, a parametrized test with named cases using `pytest.param(..., id='...')` is significantly clearer.

Misconception 2: "Using `ids=` with a list of strings is equivalent to using `pytest.param(..., id='...')`."
Reality: Both label individual cases. The difference is that `pytest.param()` can carry both an ID and marks (skip, xfail) for that specific case, while `ids=` only provides labels. For tests where some cases are expected to fail or should be skipped, `pytest.param()` is required.

---

## Why It Matters in Practice

`parametrize` is one of pytest's most important features for writing maintainable test suites. It reduces duplication, makes coverage explicit, and produces individually identifiable test failures. Knowing how to combine it with `pytest.param()` for marks and IDs, how stacking creates cartesian products, and how indirect parametrization works with fixtures covers most real-world testing patterns.

---

## Interview Angle

Common question forms:
- "How do you test multiple input cases in pytest without duplicating code?"
- "What does `@pytest.mark.parametrize` do?"
- "How do you skip a specific parametrized case?"

Answer frame:
`@pytest.mark.parametrize('arg, expected', [...])` runs the test once per tuple — each case appears as a distinct test in results. Use `pytest.param(value, marks=pytest.mark.skip, id='name')` for per-case marks and readable IDs. Stacking multiple `parametrize` decorators generates a cartesian product. Indirect parametrization passes values through a fixture for preprocessing.

---

## Related Notes

- [[pytest|pytest]]
- [[fixtures|Fixtures]]
- [[hypothesis|Hypothesis (Property-Based Testing)]]
- [[testing-basics|Testing Basics]]
