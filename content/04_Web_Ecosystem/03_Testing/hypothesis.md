---
title: 09 - Hypothesis (Property-Based Testing)
description: "Hypothesis is a property-based testing library that automatically generates hundreds of diverse inputs to find edge cases, then shrinks failing examples to the minimal case that reproduces the bug."
tags: [hypothesis, property-based-testing, testing, fuzzing, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Hypothesis (Property-Based Testing)

> Hypothesis generates test inputs you would never think to write by hand  -  it explores the space of possible values systematically, finds the case that breaks your function, and then shrinks it to the simplest possible failing example.

---

## Quick Reference

**Core idea:**
- `@given(st.integers(), st.text())`  -  strategies generate test inputs; Hypothesis chooses values and shrinks on failure
- Strategies: `st.integers()`, `st.text()`, `st.lists(st.integers())`, `st.dictionaries()`, `st.builds(MyClass, ...)`
- Test what properties should hold: encode->decode = original, sort output is always sorted, result is always in valid range
- `@settings(max_examples=500)`  -  more examples for thoroughness; `deadline=None` for slow tests
- Failing inputs are saved to a `.hypothesis/` database and replayed on every subsequent run until fixed

**Tricky points:**
- Hypothesis does not replace example-based tests  -  it finds different kinds of bugs; use both
- Strategies are composable: `st.lists(st.integers(min_value=0, max_value=100), min_size=1)` produces non-empty lists of small non-negative integers
- `assume(condition)` filters out inputs that do not meet a precondition  -  use sparingly; over-filtering makes Hypothesis generate too many rejected examples
- `@given` tests do not accept function arguments that are not strategy-bound  -  they must be parameterized entirely by strategies
- The `@example` decorator pins a specific known-bad case to always be tested, in addition to generated cases

---

## What It Is

Example-based testing is the default mental model: for this input, the output should be this value. It tests the cases you remember to write. The problem is that bugs live in the cases you do not remember  -  the empty string, the negative number, the list with duplicate elements, the maximum integer value, the Unicode string with combining characters. A developer writing tests for a `sum_list()` function will write `[1, 2, 3] -> 6` and `[] -> 0` but may not write `[sys.maxsize, sys.maxsize] -> overflow`, or `[0.1, 0.1, 0.1] -> not exactly 0.3` (floating point).

Property-based testing takes a different approach. Instead of specifying inputs and expected outputs, it specifies a property  -  a statement about what should always be true. For a sorting function: "the output should always be the same length as the input," "every element of the output should appear in the input," and "no element should be greater than its successor." These properties hold for all valid inputs, not just the ones you enumerate. Hypothesis generates inputs that satisfy the type constraints of your strategies and checks that the property holds for all of them.

When Hypothesis finds a failing input, it does not stop there. It shrinks the input by trying progressively simpler variations  -  smaller numbers, shorter strings, shorter lists  -  until it finds the minimal input that still causes the failure. This shrinking is one of Hypothesis's most valuable features. Instead of reporting "the test failed on this 5000-character string," it reports "the test failed on 'x'." The minimal failure is dramatically easier to reason about and fix.

---

## How It Actually Works

A property-based test asserts an invariant that must hold across all generated inputs, not a specific output for a specific input.

```python
from hypothesis import given, settings, example, assume
from hypothesis import strategies as st
import hypothesis.strategies as st

# Property: encode then decode returns the original value
@given(st.text())
def test_encode_decode_roundtrip(text):
    assert decode(encode(text)) == text

# Property: sorted list is always in non-decreasing order
@given(st.lists(st.integers()))
def test_sort_order(lst):
    result = my_sort(lst)
    for i in range(len(result) - 1):
        assert result[i] <= result[i + 1]

# Property: sorted list has same length as input
@given(st.lists(st.integers()))
def test_sort_length_preserved(lst):
    assert len(my_sort(lst)) == len(lst)

# Bounded strategies and assume()
@given(st.integers(min_value=1), st.integers(min_value=1))
def test_division(a, b):
    assume(b != 0)  # filter out zero denominators
    result = a / b
    assert result > 0  # both positive, result must be positive

# Pin a specific known-edge-case in addition to generated ones
@given(st.lists(st.integers()))
@example([])
@example([0])
def test_maximum(lst):
    assume(len(lst) > 0)
    result = find_maximum(lst)
    assert result in lst
    assert all(x <= result for x in lst)

# Build complex objects from strategies
@given(st.builds(
    User,
    username=st.text(min_size=1, max_size=50),
    email=st.emails(),
    age=st.integers(min_value=18, max_value=120),
))
def test_user_validation(user):
    validated = UserValidator(user)
    assert validated.is_valid()
```

The `@settings` decorator controls how Hypothesis runs. Increase `max_examples` for important functions; disable the `deadline` for slow operations.

```python
from hypothesis import settings, HealthCheck

@settings(max_examples=1000, deadline=None, suppress_health_check=[HealthCheck.too_slow])
@given(st.text(alphabet=st.characters(whitelist_categories=("Lu", "Ll", "Nd"))))
def test_slug_generation(text):
    slug = generate_slug(text)
    assert slug == slug.lower()
    assert " " not in slug
```

Hypothesis stores failing examples in `.hypothesis/examples/`  -  this directory should be committed to version control so that known-bad cases are always retested.

---

## How It Connects

Hypothesis works alongside parametrize  -  `@given` handles the case space you cannot enumerate; `@parametrize` handles the specific known edge cases.

[[parametrize|Parametrize]]

Hypothesis can generate instances of models using `st.builds()`  -  factory_boy and Hypothesis serve different roles in test data generation.

[[factory-boy|factory_boy]]

---

## Common Misconceptions

Misconception 1: "Property-based testing replaces example-based tests."
Reality: They test different things. Example-based tests verify specific behavior: "for this input, expect this output." Property-based tests verify invariants: "for all inputs of this type, this property holds." A sorting function test should have both: a property test (output is sorted, same length) and example tests (empty list -> empty list, already sorted list -> unchanged).

Misconception 2: "Hypothesis testing is slow  -  100 examples per test is too many for a CI pipeline."
Reality: Hypothesis runs fast for simple strategies. The default 100 examples run in milliseconds for pure Python functions. The `deadline` setting (200ms by default) caps slow tests. For complex or inherently slow operations, `@settings(max_examples=50, deadline=None)` balances coverage and speed. The time investment is worthwhile  -  Hypothesis finds bugs that hours of manual testing would miss.

---

## Why It Matters in Practice

Hypothesis has found bugs in widely-used libraries and standard library equivalents  -  not because the authors were careless, but because the edge cases are genuinely non-obvious. Encoding functions, parser code, mathematical utilities, and data transformation pipelines are all candidates for property-based testing. Adding Hypothesis to a test suite for these categories of functions catches a class of correctness bugs that example-based tests systematically miss.

---

## Interview Angle

Common question forms:
- "What is property-based testing and how does it differ from example-based testing?"
- "What is Hypothesis and what kind of bugs does it find?"

Answer frame:
Property-based testing asserts invariants that must hold for all valid inputs rather than specific outputs for specific inputs. Hypothesis generates inputs automatically and shrinks failures to the minimal case. It finds edge cases developers don't think to write  -  empty strings, integer overflow, Unicode edge cases. Example-based tests verify specific behavior; Hypothesis verifies correctness properties across the entire input space. Both are needed.

---

## Related Notes

- [[pytest|pytest]]
- [[parametrize|Parametrize]]
- [[factory-boy|factory_boy]]
- [[testing-basics|Testing Basics]]
- [[tdd|Test-Driven Development]]
