---
title: Free Variables
description: A free variable is a name used in a function but not defined in that function's local scope — it is resolved by looking outward through enclosing scopes; when a function captures a free variable from an enclosing function's scope, it becomes a closure cell.
tags: [free-variables, closures, LEGB, __closure__, cell-objects, nonlocal, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Free Variables

> A free variable is a name used in a function but not defined in that function's local scope — it is resolved by looking outward through enclosing scopes; when a function captures a free variable from an enclosing function's scope, it becomes a closure cell.

---

## Quick Reference

**Core idea:**
- A **free variable** in a function is a name that appears in the function body but is not assigned in that function's local scope (not via `=`, `for`, `with`, `import`, or parameter binding)
- At compile time, CPython marks each name in a function as `LOCAL`, `GLOBAL`, or `FREE` based on the function body and surrounding scopes
- Free variables from enclosing `def` scopes are captured as **cell objects** — the inner function and outer function share the same cell object
- `fn.__code__.co_freevars` lists the free variable names; `fn.__closure__` is a tuple of cell objects holding the actual values
- `nonlocal x` makes `x` a free variable that is also **writable** from the inner function — without `nonlocal`, a free variable is read-only (assignment creates a new local)

**Tricky points:**
- The classic loop-closure bug: `[lambda: i for i in range(3)]` — all three lambdas share the same cell for `i`; after the loop, `i == 2` in all three; to capture the value at each iteration use `lambda i=i: i` (default argument trick) or `functools.partial`
- `nonlocal` only works for names in **enclosing function** scopes — it cannot reach module-level globals (use `global` for that)
- A function that has free variables is a **closure** — `fn.__closure__` will be a tuple; a function with no free variables has `fn.__closure__ = None`
- Cells outlive the enclosing function — the inner function holds a reference to the cell object, which holds the value; if the value is a large object, it stays alive as long as the closure does

---

## What It Is

Think of a recipe card referencing "the family spice blend" — an ingredient not defined on the card itself. The card is a free reference: it does not define what the spice blend is, it only uses it. Whoever reads the card must look outside the card to find the blend. That external lookup is exactly what free variables do: the function refers to a name that is defined somewhere outside it, and at call time, Python looks outward through enclosing scopes to find it.

In Python, every name in a function falls into one of three categories. Local names are assigned within the function. Global names are at module level. Free variables are everything else — names used in the function but defined in an enclosing function's scope. The compiler determines which category each name belongs to by scanning the function body. The assignment `x = ...` in the function body makes `x` local; otherwise `x` is free or global.

The most important consequence: when a free variable comes from an enclosing `def`, the inner function captures a reference to the cell object shared with the outer function. This means the inner function sees the current value of the variable at call time, not the value at the time it was created — which is why the loop-closure bug exists and why `nonlocal` modifications are visible across all closures sharing the same cell.

---

## How It Actually Works

CPython's compiler performs a two-pass analysis on each function body. In the first pass it collects all names that appear in assignment positions (including `for` loop targets, function parameters, `import` names, `with` targets). These become the function's local variables (`co_varnames`). In the second pass, names that are read but not in `co_varnames` are marked as free variables — unless they are module globals or builtins.

For each free variable, CPython generates `LOAD_DEREF` (to read) and `STORE_DEREF` (to write with `nonlocal`) bytecode instructions instead of `LOAD_FAST` / `STORE_FAST`. `LOAD_DEREF` reads from a cell object; `STORE_DEREF` writes to it.

Cell objects (`cell` type in CPython) are shared containers. The outer function uses `MAKE_CELL` to convert its local variable to a cell at the start of execution. The inner function's code object references the same cell via its `__closure__` tuple. Reading `cell.cell_contents` gives the current value. If the outer function reassigns the variable, the cell's contents change — all inner functions sharing that cell see the new value immediately.

```python
def outer():
    x = 10
    def inner():
        return x  # x is a free variable
    x = 20        # modifies the shared cell
    return inner

f = outer()
f()  # returns 20, not 10 — the cell holds the current value
```

---

## How It Connects

Free variables are the mechanism behind closures — a closure is a function that has at least one free variable captured from an enclosing scope. The closure's `__closure__` attribute holds the cell objects; `co_freevars` lists the names.
[[closures|Closures]]

The LEGB rule describes the lookup order for names: Local → Enclosing → Global → Builtin. Free variables are the Enclosing part of LEGB — names resolved in enclosing function scopes.
[[legb-rule|The LEGB Rule]]

---

## Common Misconceptions

Misconception 1: "A free variable captures the value at the time the closure is created."
Reality: A free variable captures a reference to a **cell object**, not the value. The cell holds the current value of the variable. If the enclosing scope changes the variable after the closure is created, the closure sees the new value. This is the source of the loop-closure bug: all closures created inside a loop share the same cell for the loop variable, which holds the final loop value when the closures are eventually called.

Misconception 2: "`nonlocal` makes a variable global."
Reality: `nonlocal` makes a free variable writable from the inner function — it references the cell in the nearest enclosing function scope that defines that name. It does not promote the variable to module scope. `global` promotes to module scope; `nonlocal` reaches into the enclosing function scope only.

---

## Why It Matters in Practice

The loop-closure bug is the most common free variable pitfall:

```python
fns = [lambda: i for i in range(3)]
fns[0]()  # 2, not 0 — all share the same cell for i
```

Fix with a default argument that copies the current value:

```python
fns = [lambda i=i: i for i in range(3)]
fns[0]()  # 0
```

Default arguments are evaluated at function creation time and stored in `fn.__defaults__` — they are not free variables, so they do not share a cell.

Counter factories and stateful callbacks are the positive use case: a `make_counter()` function returns a closure over a `count` variable. Each call to `make_counter()` creates a new cell with a fresh count; different counters are independent. `nonlocal count` inside the inner function allows it to increment the counter.

---

## Interview Angle

Common question forms:
- "What is a free variable in Python?"
- "Why does the loop closure capture the wrong value?"
- "What is `nonlocal` for?"

Answer frame: A free variable is a name used in a function but not defined in its local scope — Python finds it by looking outward through enclosing scopes. In CPython, it is implemented as a shared cell object between the outer and inner functions. The inner function sees the cell's current value at call time, not the value when the closure was created — this is the loop closure bug. `nonlocal` allows the inner function to write to the shared cell. Fix the loop bug by using a default argument to copy the current value at each iteration.

---

## Related Notes

- [[closures|Closures]]
- [[legb-rule|The LEGB Rule]]
- [[decorators|Decorators]]
- [[namespaces-and-scopes|Namespaces and Scopes]]
