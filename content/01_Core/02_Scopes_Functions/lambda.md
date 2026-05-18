---
title: 08 - Lambda Functions
description: "A `lambda` expression creates an anonymous single-expression function object  -  it is syntactic shorthand for a `def` with no name and a single `return` expression, typically used inline where a full `def` would be verbose."
tags: [lambda, anonymous-functions, first-class-functions, higher-order, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# Lambda Functions

> A `lambda` expression creates an anonymous single-expression function object  -  it is syntactic shorthand for a `def` with no name and a single `return` expression, typically used inline where a full `def` would be verbose.

---

## Quick Reference

**Core idea:**
- `lambda params: expression` creates a function object; the expression is the implicit return value
- The result is identical to `def _anon(params): return expression`  -  the same `function` type, same calling convention
- `lambda` is an **expression**, not a statement  -  it can appear inside a list, dict, function call, or assignment without a separate line
- The function object produced by `lambda` has `__name__ == '<lambda>'`
- All of `*args`, `**kwargs`, default arguments, and keyword-only parameters are supported in lambda: `lambda *a, **kw: (a, kw)`

**Tricky points:**
- `lambda` body must be a single **expression**  -  no statements (`if/else` as a ternary is fine, but `if` as a statement is not, nor are `for` loops, `try`, `with`, or assignments)
- Walrus operator (`:=`) is an expression and can appear in lambda bodies: `lambda x: (y := x + 1, y * 2)[1]`
- Lambdas capture free variables the same way closures do  -  the loop-closure bug applies: `[lambda: i for i in range(3)]` all return 2
- PEP 8 discourages assigning a lambda to a variable: `f = lambda x: x + 1`  -  prefer `def f(x): return x + 1` for named use
- Lambdas cannot have annotations  -  `lambda x: int: x` is a syntax error; annotations require `def`

---

## What It Is

Think of a sticky note versus a signed document. A signed document has a name, a date, and is filed away for future reference  -  it is a `def` function. A sticky note is quick, disposable, written and used in the moment  -  it is a `lambda`. Lambdas are for when you need a function right now, in one place, and giving it a name would cost more than it is worth. The classic case: sorting a list of dictionaries by a key.

`sorted(users, key=lambda u: u["age"])`  -  the `key` argument expects a callable. Writing `def get_age(u): return u["age"]` and then `sorted(users, key=get_age)` works, but the name `get_age` is used only once and immediately thrown away. The lambda expresses the same intent in one line without introducing a name into the surrounding scope.

The design philosophy is that the lambda's value comes from being an expression. `def` is a statement  -  it cannot appear inside another expression. `lambda` can appear wherever any other expression can, which is why it fits naturally as an argument, a default value, or a list element.

---

## How It Actually Works

`lambda params: expr` is compiled to the same bytecode as:

```python
def <lambda>(params):
    return expr
```

The resulting object is a `function` type with all the same attributes: `__code__`, `__globals__`, `__defaults__`, `__closure__`. The only differences are `__name__ == '<lambda>'` and `__qualname__` which shows the enclosing scope.

Because `lambda` is an expression, `MAKE_FUNCTION` bytecode is emitted inline  -  the function object is created and pushed onto the stack at that point in the expression, rather than stored into a name.

Free variables in lambdas work through the same cell mechanism as closures. A lambda inside a loop:

```python
fns = [lambda: i for i in range(3)]
```

Each lambda has `i` as a free variable referencing the loop variable's cell. After the loop, all three lambdas read the same cell value (`i == 2`). Fix: `lambda i=i: i`  -  the default argument copies the current value at creation time.

---

## How It Connects

Lambdas are first-class function objects  -  the same type as any other function. The distinction is purely syntactic: lambdas are expressions, `def` creates statements.
[[first-class-functions|First-Class Functions]]

The loop-closure bug and free variable capture in lambdas follow exactly the same rules as closures.
[[free-variables|Free Variables]]

---

## Common Misconceptions

Misconception 1: "`lambda` creates a special, limited type of function."
Reality: `lambda` produces the same `function` object as `def`. It has the same attributes, supports the same calling conventions, and can have closures, defaults, and variadic arguments. The only limitations are syntactic: one expression for the body, no annotations, no statements.

Misconception 2: "`lambda` is always the cleaner choice for inline functions."
Reality: PEP 8 explicitly recommends `def` over assigning a `lambda` to a variable, because `def` provides a better `__name__` (used in tracebacks and `repr`), allows annotations, and allows multi-line bodies if needed. Lambdas are appropriate inline  -  as arguments  -  but not as named function definitions.

---

## Why It Matters in Practice

`key` functions for sorting and min/max are the canonical use case: `sorted(data, key=lambda x: x.priority)`, `min(points, key=lambda p: p.distance_to(origin))`. The lambda is short enough that a separate `def` would just create noise.

`tkinter`, `PyQt`, and other GUI toolkits accept callbacks as arguments. `button.configure(command=lambda: print("clicked"))` creates a zero-argument callable inline. The alternative  -  defining a separate function for a one-liner callback  -  is less readable.

`map(lambda x: x ** 2, numbers)` and `filter(lambda x: x > 0, numbers)` are common patterns, though list comprehensions (`[x**2 for x in numbers]`) are often preferred for readability.

---

## Interview Angle

Common question forms:
- "What is a lambda in Python and when would you use it?"
- "What are the limitations of lambdas?"

Answer frame: `lambda params: expr` creates an anonymous function object  -  same type as `def`, but limited to a single expression and cannot have type annotations or statements. The typical use case is inline key functions: `sorted(items, key=lambda x: x.value)`. PEP 8 discourages assigning lambdas to variables  -  use `def` for named functions. Free variable capture follows the same rules as closures, so the loop-closure bug applies.

---

## Related Notes

- [[first-class-functions|First-Class Functions]]
- [[free-variables|Free Variables]]
- [[higher-order-functions|Higher-Order Functions]]
- [[functools|functools]]
