---
title: 06 - Higher-Order Functions
description: "A higher-order function is one that takes a function as an argument or returns a function as its result  -  `map`, `filter`, `sorted`, and `functools.reduce` are built-in examples; decorators and closure factories are the most common patterns you write yourself."
tags: [higher-order-functions, map, filter, reduce, functional-programming, first-class-functions, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Higher-Order Functions

> A higher-order function is one that takes a function as an argument or returns a function as its result  -  `map`, `filter`, `sorted`, and `functools.reduce` are built-in examples; decorators and closure factories are the most common patterns you write yourself.

---

## Quick Reference

**Core idea:**
- **Higher-order function (HOF)**: takes a function as input, returns a function as output, or both
- `map(fn, iterable)`  -  applies `fn` to each element, returns a lazy iterator
- `filter(pred, iterable)`  -  keeps elements where `pred(element)` is truthy, returns a lazy iterator
- `sorted(iterable, key=fn)`  -  sorts by applying `fn` to each element; `fn` is a HOF argument
- `functools.reduce(fn, iterable, initial)`  -  folds the iterable left-to-right with `fn(acc, element)`
- Returning a function from a function creates a **factory**  -  a function that produces customized functions

**Tricky points:**
- `map` and `filter` are **lazy**  -  they return iterators, not lists; wrap with `list()` to materialize
- `sorted` vs `list.sort`: `sorted` returns a new list; `sort` is in-place; both accept `key=` and `reverse=`
- `functools.reduce` is not a builtin in Python 3 (moved to `functools`)  -  a common gotcha for Python 2 migrants
- HOFs that return functions should preserve the wrapped function's metadata using `functools.wraps`
- The `key` function in `sorted` is called once per element, not once per comparison  -  O(n) evaluations, not O(n log n)

---

## What It Is

Think of a machine tool in a factory. A regular tool does one specific operation. A higher-order tool is a configurable machine that accepts a blade (a function) as input and applies that blade's operation to materials  -  the machine's behavior changes based on which blade is loaded. `sorted` is such a machine: it sorts anything, with any comparison criterion, depending on the `key` function you load into it. `map` is another: it applies any transformation to any iterable, depending on the function you pass.

Higher-order functions are the mechanism by which Python code becomes composable. Instead of writing `sort_by_age`, `sort_by_name`, and `sort_by_score` as three separate functions, you write `sorted` once with a `key` parameter, and the caller provides the dimension of sorting. The sorting logic is fixed; the comparison criterion is variable and injected.

This is also the design of decorators: a decorator is a higher-order function that takes a function and returns a modified version of it. The decorator implements the wrapping logic; the function being decorated provides the core operation.

---

## How It Actually Works

`map(fn, iterable)` is a built-in type in CPython  -  calling it creates a `map` iterator object. Each `next()` call on the iterator calls `fn(next(iterable))` and returns the result. No list is created upfront. This lazy evaluation is why `map` is memory-efficient for large iterables.

`filter(pred, iterable)` similarly creates a `filter` iterator. Each `next()` call advances the underlying iterator until it finds an element where `pred(element)` is truthy.

`functools.reduce(fn, iterable, initial)` is eager  -  it processes the whole iterable immediately. Starting with `acc = initial`, it applies `fn(acc, element)` for each element, updating `acc`. The final `acc` is returned. Without `initial`, the first element is used as the initial accumulator; an empty iterable then raises `TypeError`.

A function factory:

```python
def make_multiplier(n):
    def multiplier(x):
        return x * n
    return multiplier

double = make_multiplier(2)
triple = make_multiplier(3)
double(5)  # 10
triple(5)  # 15
```

`make_multiplier` is a higher-order function  -  it returns a function. Each call creates a new closure over `n`.

---

## How It Connects

Higher-order functions are only possible because functions are first-class objects  -  they can be passed as arguments and returned as values. Without first-class functions, there are no higher-order functions.
[[first-class-functions|First-Class Functions]]

Decorators are the most commonly written higher-order functions: they take a function, return a modified function. `functools.wraps` preserves the decorated function's metadata.
[[decorators|Decorators]]

---

## Common Misconceptions

Misconception 1: "`map` and `filter` are the preferred way to transform collections in Python."
Reality: In modern Python, list comprehensions and generator expressions are generally preferred over `map` and `filter` for readability. `[x**2 for x in items]` is clearer than `list(map(lambda x: x**2, items))`. `map` and `filter` are useful when the transformation function already exists as a named function: `map(str, numbers)` is clean; `map(lambda x: str(x), numbers)` is not an improvement over the comprehension.

Misconception 2: "Higher-order functions are a functional programming specialty, not general Python."
Reality: Every Python program uses higher-order functions constantly. `sorted(data, key=...)`, `max(items, key=...)`, event callbacks, decorators, `threading.Thread(target=fn)`  -  these are all HOF patterns. "Higher-order function" is not a niche concept; it describes a large fraction of idiomatic Python APIs.

---

## Why It Matters in Practice

The `key` parameter pattern is ubiquitous. `sorted(employees, key=attrgetter("salary"), reverse=True)` ranks employees by salary in one line. `max(records, key=lambda r: r.timestamp)` finds the most recent record. The sort key is injected; the sorting machinery is reused.

Function factories enable configuration. `make_validator(max_length=100)` returns a validator function configured with the maximum length. The validator can be passed to a form library's field validation pipeline without the pipeline knowing the specific configuration.

`functools.reduce` implements fold operations: product of a list (`reduce(operator.mul, numbers, 1)`), building a dict from pairs, computing cumulative sums. It is the general left-fold; list comprehensions and `sum`/`min`/`max` cover the common cases more readably.

---

## Interview Angle

Common question forms:
- "What is a higher-order function?"
- "What is the difference between `map`, `filter`, and list comprehensions?"

Answer frame: A higher-order function takes a function as an argument or returns a function. Built-in examples: `sorted(key=fn)`, `map(fn, iter)`, `filter(pred, iter)`. `map` and `filter` return lazy iterators. In modern Python, list comprehensions are often preferred over `map`/`filter` with `lambda`. Decorators are the most commonly written HOFs. Function factories  -  functions that return configured functions  -  are the other major pattern.

---

## Related Notes

- [[first-class-functions|First-Class Functions]]
- [[decorators|Decorators]]
- [[functools|functools]]
- [[lambda|Lambda Functions]]
