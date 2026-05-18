---
title: 10 - Test Coverage
description: "Test coverage measures which lines and branches of code are executed during a test run, providing a quantitative signal about untested code paths  -  but not about whether the tested behavior is correct."
tags: [coverage, pytest-cov, testing, quality, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Test Coverage

> Coverage measures which lines of code ran during tests  -  it tells you where your tests are not looking, but not whether they are looking correctly.

---

## Quick Reference

**Core idea:**
- `coverage run -m pytest` traces execution; `coverage report` shows line counts; `coverage html` produces browsable output
- Line coverage: was each line executed? Branch coverage (`--branch`): was each side of every `if` taken?
- `.coveragerc` or `[tool.coverage]` in `pyproject.toml`: configure `source`, `omit`, and `fail_under`
- `pytest-cov`: `pytest --cov=myapp --cov-report=html --cov-fail-under=80`  -  runs tests and generates coverage in one command
- 100% coverage does not mean correct code  -  it means every line ran, not that every outcome was verified

**Tricky points:**
- Branch coverage is almost always more valuable than line coverage  -  an `if/else` where only the truthy branch is tested shows 100% line coverage but only 50% branch coverage
- `# pragma: no cover` excludes a line or block from coverage measurement  -  use for `if TYPE_CHECKING:` blocks, `__repr__` methods, and unreachable defensive code
- Coverage of `__init__.py` files and configuration code often adds noise  -  list them in `omit`
- Coverage data from parallel test runs must be combined with `coverage combine` before reporting
- CI gates on `fail_under` percentages can incentivize writing coverage-boosting tests (lines that run but assert nothing) rather than meaningful tests

---

## What It Is

Imagine walking through a building in the dark. Coverage is the light from your torch  -  it shows you which rooms you visited. A room you visited might be fine or it might have a problem you did not notice in the dark. But a room you never visited definitely has not been inspected. Coverage gives you a map of uninspected rooms.

Line coverage tracks the simplest thing: did this line of code execute? If a function is never called in tests, every line in it is uncovered. If an exception handler block is never triggered, those lines are uncovered. Coverage reports show uncovered lines highlighted in red, giving developers a quick visual guide to where tests are missing entirely. This is valuable for identifying dead zones in the test suite  -  large sections of code that tests never reach.

Branch coverage extends this concept to conditional logic. A line like `if user.is_admin:` might always evaluate to `True` in tests, meaning the `else` branch never runs. Line coverage counts the `if` line as covered because it executed. Branch coverage counts it as partially covered because only one of the two possible outcomes was tested. Branch coverage gives a much more accurate picture of how thoroughly the logic has been exercised  -  an untested branch is a code path that could behave incorrectly with no test to catch it.

---

## How It Actually Works

The `coverage` package wraps the test runner and instruments the code, inserting trace hooks that record which lines execute. `pytest-cov` integrates this into pytest's command-line interface.

```bash
# Using coverage directly
coverage run -m pytest tests/
coverage report
coverage html  # opens at htmlcov/index.html
coverage xml   # for CI systems (Codecov, Coveralls)

# Using pytest-cov (recommended)
pytest --cov=myapp --cov-report=term-missing --cov-report=html --cov-fail-under=80

# With branch coverage
pytest --cov=myapp --cov-branch --cov-report=term-missing
```

Configuration belongs in `pyproject.toml` rather than a separate `.coveragerc` file.

```toml
[tool.coverage.run]
source = ["myapp"]
branch = true
omit = [
    "myapp/__init__.py",
    "myapp/migrations/*",
    "myapp/settings*.py",
    "tests/*",
]

[tool.coverage.report]
fail_under = 80
show_missing = true
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "raise NotImplementedError",
    "@abstractmethod",
    "if __name__ == .__main__.:",
]
```

The `# pragma: no cover` comment suppresses coverage measurement for lines that should be excluded  -  typically protocol implementations, type-checking-only blocks, and defensive assertions.

```python
if TYPE_CHECKING:  # pragma: no cover
    from myapp.models import User

def __repr__(self) -> str:  # pragma: no cover
    return f"User(id={self.id}, email={self.email})"
```

Coverage data from parallel test runs (using `pytest-xdist` for parallel execution) must be combined before reporting.

```bash
pytest --cov=myapp --cov-parallel -n auto  # run tests in parallel
coverage combine                            # merge .coverage.* files
coverage report
```

---

## How It Connects

pytest-cov integrates coverage measurement directly into pytest runs  -  coverage is configured alongside other pytest settings.

[[pytest|pytest]]

TDD uses coverage not as a target metric but as a verification tool  -  tests written first should naturally produce high coverage of the code that was written to make them pass.

[[tdd|Test-Driven Development]]

---

## Common Misconceptions

Misconception 1: "Achieving 100% test coverage means the code is fully tested."
Reality: 100% line coverage means every line executed at least once. A test can execute every line without making a single meaningful assertion  -  `assert True` after calling every function achieves 100% coverage. Coverage is a necessary condition for testing a line, not a sufficient condition. High coverage with weak assertions is common and gives false confidence.

Misconception 2: "Coverage should always be as high as possible  -  aim for 100%."
Reality: The last 5-10% of coverage often covers defensive error handling, unreachable code paths, and platform-specific branches that are genuinely difficult or impossible to test meaningfully. Spending significant effort reaching 100% while neglecting to write meaningful assertions for the well-covered 90% is counterproductive. A healthy target is 80-90% with branch coverage and a focus on asserting correct behavior, not just executing lines.

---

## Why It Matters in Practice

Coverage reports are most useful as a diagnostic tool  -  they show which code regions have no tests at all. Teams that use coverage as a CI gate must ensure the threshold encourages meaningful tests, not just execution. Understanding the difference between line and branch coverage, knowing how to configure `fail_under` and `omit`, and using `# pragma: no cover` appropriately makes coverage reporting a useful signal rather than a metric to game.

---

## Interview Angle

Common question forms:
- "What is the difference between line coverage and branch coverage?"
- "Does 100% test coverage guarantee correct code?"
- "How do you integrate coverage into a CI pipeline?"

Answer frame:
Line coverage: every line executed. Branch coverage: both sides of every `if` taken  -  more valuable because it catches untested else-branches. 100% coverage does not guarantee correctness  -  a test can run every line without asserting anything meaningful. CI integration: `pytest --cov=myapp --cov-fail-under=80` fails the build if coverage drops below the threshold. Configure `omit` for migrations and settings files that inflate noise.

---

## Related Notes

- [[pytest|pytest]]
- [[tdd|Test-Driven Development]]
- [[testing-basics|Testing Basics]]
- [[parametrize|Parametrize]]
