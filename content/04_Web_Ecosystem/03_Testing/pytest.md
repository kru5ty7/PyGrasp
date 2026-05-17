---
title: 02 - Pytest
description: "pytest is the standard Python testing framework — test functions prefixed with `test_`, automatic discovery, rich assertions with plain `assert`, fixtures for setup/teardown, and plugins for coverage, async, and parametrize; run with `pytest path/` or `pytest -k pattern`."
tags: [pytest, testing, fixtures, parametrize, markers, conftest, layer-3, web]
status: draft
difficulty: beginner
layer: 3
domain: web
created: 2026-05-17
---

# Pytest

> pytest is the standard Python testing framework — test functions prefixed with `test_`, automatic discovery, rich assertions with plain `assert`, fixtures for setup/teardown, and plugins for coverage, async, and parametrize; run with `pytest path/` or `pytest -k pattern`.

---

## Quick Reference

**Core idea:**
- Test functions start with `test_`; test files start with `test_` or end with `_test.py`
- Plain `assert` — pytest rewrites it to show diff on failure; no `assertEqual()`, `assertRaises()` needed
- `pytest.raises(ExcType)` — context manager for expected exceptions
- `-v` — verbose (show each test name); `-k "pattern"` — run tests matching pattern; `-x` — stop on first failure
- `--cov=src --cov-report=term-missing` — coverage report (requires `pytest-cov`)

**Tricky points:**
- `assert a == b` in pytest shows the values of `a` and `b` on failure — this is pytest's assertion rewriting; standard `assert` in non-pytest code does not do this
- `conftest.py` — special file for shared fixtures; pytest loads it automatically; fixtures in `conftest.py` are available to all tests in the same directory and subdirectories
- Scope affects fixture lifetime: `"function"` (default, per test), `"class"`, `"module"`, `"session"` (once per `pytest` run)
- `pytest.mark.skip("reason")` / `pytest.mark.skipif(condition, reason=...)` — conditionally skip tests
- Parallel test execution: `pytest-xdist` with `-n auto` — runs tests on multiple CPUs; requires tests to be independent (no shared mutable state)

---

## What It Is

pytest is the de-facto standard for Python testing. Its philosophy: minimal boilerplate, maximum feedback. You write plain functions, use plain `assert`, and pytest handles collection, execution, and reporting. Fixtures replace `setUp`/`tearDown` from `unittest` with a dependency injection model that is more composable.

The key design decision: assertion rewriting. When you write `assert result == expected`, pytest intercepts it and on failure shows the actual values, not just "AssertionError".

---

## How It Actually Works

Basic test file:
```python
# test_math.py
def add(a, b): return a + b

def test_add_positive():
    assert add(1, 2) == 3

def test_add_negative():
    assert add(-1, -2) == -3

def test_add_produces_correct_type():
    result = add(1.0, 2.0)
    assert isinstance(result, float)
    assert result == pytest.approx(3.0)  # floating point comparison
```

Running:
```bash
pytest                          # discover and run all tests
pytest tests/                   # specific directory
pytest tests/test_math.py       # specific file
pytest tests/test_math.py::test_add_positive  # specific test
pytest -k "add"                 # tests with "add" in name
pytest -v -x --tb=short        # verbose, stop on first failure, short traceback
```

Parametrize:
```python
@pytest.mark.parametrize("a, b, expected", [
    (1, 2, 3),
    (0, 0, 0),
    (-1, 1, 0),
    (100, -50, 50),
])
def test_add(a, b, expected):
    assert add(a, b) == expected
```

Expected exceptions:
```python
def test_divide_zero():
    with pytest.raises(ZeroDivisionError):
        1 / 0

def test_value_error_message():
    with pytest.raises(ValueError, match="must be positive"):
        validate_age(-1)
```

Test classes (optional — for grouping, not required):
```python
class TestUserService:
    def test_create(self): ...
    def test_delete(self): ...
```

---

## How It Connects

Fixtures are pytest's mechanism for setup/teardown and dependency injection — they are the foundation for database sessions, test clients, and shared state in tests.
[[fixtures|Fixtures]]

pytest-asyncio enables async test functions — required for testing FastAPI async endpoints.
[[async-testing|Async Testing]]

---

## Common Misconceptions

Misconception 1: "pytest requires inheriting from `unittest.TestCase`."
Reality: pytest runs both `unittest.TestCase` tests and plain `test_` functions. Modern pytest code uses plain functions and fixtures — no class inheritance needed.

Misconception 2: "`conftest.py` must be in the project root."
Reality: `conftest.py` can be placed at any level in the directory hierarchy — fixtures defined in it are available to all tests in that directory and below. Multiple `conftest.py` files can coexist at different levels, each providing different fixtures.

---

## Why It Matters in Practice

Useful pytest invocations for development:
```bash
pytest -x --tb=short           # fail fast, short tracebacks — fast feedback loop
pytest --lf                    # run only tests that failed last time
pytest -v -k "auth"            # verbose, filter to auth-related tests
pytest --cov=app --cov-report=html  # HTML coverage report
```

`pytest.ini` / `pyproject.toml` configuration:
```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-v --tb=short"
asyncio_mode = "auto"   # pytest-asyncio: auto-detect async tests
```

---

## Interview Angle

Common question forms:
- "How do you run a single test in pytest?"
- "What is a fixture in pytest?"

Answer frame: `pytest path/file.py::test_name` runs a single test. `assert` is plain Python — pytest rewrites it to show values on failure. Fixtures are functions decorated with `@pytest.fixture` that provide setup/teardown; declared as parameters in test functions (dependency injection). `conftest.py` for shared fixtures. `-k "pattern"` to filter tests by name.

---

## Related Notes

- [[testing-basics|Testing Basics]]
- [[fixtures|Fixtures]]
- [[mocking|Mocking]]
- [[testing-fastapi|Testing FastAPI]]
