---
title: 07 - List Comprehensions
description: "List comprehensions are a concise syntax for building lists by mapping and/or filtering an iterable in a single expression  -  they compile to faster bytecode than equivalent `for` loops and signal intent clearly, but set/dict comprehensions and generator expressions follow the same syntax for different collection types."
tags: [list-comprehensions, set-comprehension, dict-comprehension, generator-expression, comprehension-syntax, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# List Comprehensions

> List comprehensions are a concise syntax for building lists by mapping and/or filtering an iterable in a single expression  -  they compile to faster bytecode than equivalent `for` loops and signal intent clearly, but set/dict comprehensions and generator expressions follow the same syntax for different collection types.

---

## Quick Reference

**Core idea:**
- `[expr for var in iterable]`  -  builds a list by applying `expr` to each element
- `[expr for var in iterable if condition]`  -  filters elements before applying `expr`
- `{expr for var in iterable}`  -  set comprehension (deduplicated, unordered)
- `{key: value for var in iterable}`  -  dict comprehension
- `(expr for var in iterable)`  -  generator expression (lazy, does not build a list)
- Nested comprehensions: `[expr for x in outer for y in inner]`  -  equivalent to two nested `for` loops

**Tricky points:**
- The comprehension variable (e.g., `x` in `[f(x) for x in items]`) is scoped to the comprehension  -  it does not leak into the enclosing scope (unlike `for` loop variables, which do leak)
- Nested comprehensions are read left-to-right: `[f(x, y) for x in a for y in b]` means outer `x`, inner `y`  -  same order as nested `for` loops
- The `if` clause filters the **source** iterable  -  it is not a ternary expression; `[x if cond else alt for x in items]` uses the ternary expression in the `expr` position
- Comprehensions have their own scope  -  a variable name used in the comprehension shadows the outer scope name within the comprehension
- Large comprehensions build the entire list in memory; generator expressions are the lazy alternative for large iterables

---

## What It Is

Think of a shopping list annotated with a filter: "everything in the pantry that is expired, write on the disposal list." The filter (expired) and the transformation (write on disposal list) are applied to a source (pantry contents) in one mental operation. List comprehensions express exactly this: source, optional filter, transformation  -  in one readable expression.

Before comprehensions, the equivalent was: create an empty list, loop over the source, append items. This pattern was so common that Python added comprehension syntax to express it as a single expression. The resulting code is more readable because the intent is visible in one glance: what is being built, from what, and with what condition.

The syntax maps cleanly to the operations: `[expression for item in source if condition]` reads almost like English  -  "expression, for each item in source, if condition holds."

---

## How It Actually Works

List comprehensions compile to a separate code object in CPython  -  they run inside an implicit function scope, which is why the loop variable does not leak. The bytecode creates a new list, evaluates the `for` expression to get an iterator, loops calling `next()`, applies the `if` filter, and appends matching results.

Compared to an equivalent `for` loop with `.append()`, a list comprehension is typically 10-30% faster because:
1. The append operation is looked up once per comprehension (stored in a fast local), not on every iteration via attribute lookup on the list object
2. Fewer bytecode instructions per iteration

A nested comprehension `[f(x, y) for x in a for y in b]` is equivalent to:

```python
result = []
for x in a:
    for y in b:
        result.append(f(x, y))
```

The outer `for` clause is the outer loop. All conditions and inner `for` clauses are evaluated in left-to-right order.

Generator expression `(expr for ...)` is syntactically identical to a list comprehension but with parentheses  -  it creates a generator object instead of a list. When passed as the sole argument to a function, the outer parentheses of the function call serve double duty: `sum(x**2 for x in range(10))` does not require an extra pair of parentheses.

---

## How It Connects

Generator expressions are the lazy version of list comprehensions  -  same syntax, but produce a generator object. When processing large iterables where only part of the result is needed, a generator expression avoids building the full list.
[[generator-expressions|Generator Expressions]]

List comprehensions use the for-loop iterator protocol internally  -  the same `iter()`/`next()` mechanism as an explicit `for` loop.
[[for-loop-internals|For Loop Internals]]

---

## Common Misconceptions

Misconception 1: "The loop variable in a comprehension is available after it."
Reality: Comprehension variables are scoped to the comprehension  -  in Python 3, `[x for x in range(3)]` does not define `x` in the enclosing scope. This changed from Python 2, where comprehension variables did leak. `for` loop variables still leak: `for x in range(3): pass` leaves `x = 2` in scope.

Misconception 2: "`[f(x) for x in items if condition]` and `[f(x) if condition else alt for x in items]` mean the same thing."
Reality: They are different. `if condition` after `for x in items` is a filter  -  elements where `condition` is false are excluded entirely. `f(x) if condition else alt` is a ternary in the expression position  -  every element is included, but some get `f(x)` and others get `alt`. Mixing them up produces incorrect results silently.

---

## Why It Matters in Practice

List comprehensions are idiomatic Python for data transformation. `[int(s) for s in fields]`, `[r for r in records if r.active]`, `{k: v for k, v in pairs}`  -  these are the standard patterns. Comprehensions are preferred over `map`/`filter` when the transformation is complex enough to benefit from named variables.

Dict comprehensions enable concise inversion and transformation: `{v: k for k, v in mapping.items()}` inverts a dict; `{k: v.strip() for k, v in raw.items()}` cleans values.

Matrix operations use nested comprehensions: `[[row[i] for row in matrix] for i in range(cols)]` transposes a matrix. The nesting is readable when broken across lines.

---

## Interview Angle

Common question forms:
- "What is a list comprehension?"
- "What is the difference between a list comprehension and a generator expression?"
- "Does the comprehension variable leak into the enclosing scope?"

Answer frame: A list comprehension builds a list in one expression: `[expr for x in iterable if condition]`. It is faster than an equivalent `for` + `.append()` loop. The variable is scoped to the comprehension (does not leak in Python 3). Set and dict comprehensions use `{}`; generator expressions use `()` and are lazy. The `if` clause is a filter; a ternary in the expression position (`expr if cond else alt`) includes all elements.

---

## Related Notes

- [[generator-expressions|Generator Expressions]]
- [[for-loop-internals|For Loop Internals]]
- [[generators|Generators]]
- [[lazy-evaluation|Lazy Evaluation]]
