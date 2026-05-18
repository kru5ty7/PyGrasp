---
title: 04 - Closures
description: A closure is a function that captures variables from its enclosing scope and carries them along  -  the captured variables live in cell objects that outlast the enclosing function's call frame and are shared between the inner and outer function.
tags: [closures, cells, free-variables, LEGB, decorators, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Closures

> A closure is a function that captures variables from its enclosing scope and carries them along  -  the captured variables live in cell objects that outlast the enclosing function's call frame and are shared between the inner and outer function.

---

## Quick Reference

**Core idea:**
- A closure is a **function + the variables it captured from an enclosing scope**
- Captured variables are stored as **cell objects** in `fn.__closure__`  -  each cell holds a pointer to the object
- Both the inner function and the outer function **share the same cell**  -  a write in either is visible to the other
- `LOAD_DEREF` / `STORE_DEREF` are the bytecode opcodes for reading/writing cell variables
- A function only becomes a closure if it actually **uses** a variable from the enclosing scope (the compiler detects this)

**Tricky points:**
- The classic loop closure bug: `[lambda: i for i in range(3)]`  -  all three lambdas return `2`, not `0, 1, 2`, because all three cells point to the **same `i`** variable, and `i` equals `2` after the loop
- Fix: `lambda i=i: i`  -  capture the current value as a default argument (default arguments are evaluated at definition time)
- `fn.__closure__` is `None` if the function captures no variables  -  it is only a non-None tuple for actual closures
- Closures **keep the enclosing scope alive**  -  if a closure captures a large object, that object stays in memory as long as the closure exists
- `nonlocal` is required to **assign** to a captured variable; reading it works without `nonlocal`

---

## What It Is

Imagine a backpack that a traveler carries when they leave home. The traveler can take objects from the house, put them in the backpack, and use them on the road  -  even after the house is long gone. The contents of the backpack travel with the person. A Python closure works like that backpack: an inner function can take variables from its enclosing function and carry them along, even after the enclosing function has returned and its frame has been destroyed.

In Python, a closure forms when a function is defined inside another function and uses a variable from the outer function's scope. When the inner function is created, Python detects that it references an outer variable and sets up a shared container  -  a cell object  -  to hold that variable. Both the inner function and the outer function access the variable through the same cell. When the outer function returns and its local frame is gone, the cell (and the object it contains) remains alive because the inner function still holds a reference to it.

The practical importance of closures is that they allow functions to carry state without using global variables or class instances. A function that returns another function  -  where the returned function "remembers" values from the call that created it  -  is using a closure. This pattern appears everywhere: in factory functions, in decorators, in partial application, in callbacks that need context. Closures are how Python functions can maintain private, per-instance state without the syntax of a class.

---

## How It Actually Works

When CPython's compiler encounters a nested function that references a variable from an enclosing scope, it compiles both functions with special awareness of this shared variable. The outer variable is marked as a "cell variable" in the outer function (`co_cellvars`) and as a "free variable" in the inner function (`co_freevars`). Instead of storing the variable's value directly in the local variable array, CPython allocates a `PyCellObject`  -  a small wrapper struct with a single `ob_ref` field pointing to the current value.

At runtime, the outer function's frame holds the cell object in a special part of its local storage. The inner function's code object stores a reference to the same cell object in `fn.__closure__`  -  a tuple of cell objects. When the inner function reads the variable with `LOAD_DEREF`, it dereferences the cell (`cell->ob_ref`) to get the current value. When it writes with `STORE_DEREF`, it updates `cell->ob_ref`. When the outer function writes its own local variable (also via `STORE_DEREF`), it updates the same cell. The two functions see the same value because they share the same cell.

This cell-sharing is exactly why the classic loop closure bug happens. When you write `funcs = [lambda: i for i in range(3)]`, all three lambda functions capture the same cell  -  the cell for the loop variable `i`. The lambdas do not capture the value of `i` at the time they are created; they capture the cell itself. When the loop finishes, `i` is `2`. When any of the lambdas is called, it reads the cell and finds `2`. The fix using a default argument (`lambda i=i: i`) works because default argument values are evaluated when the function is defined  -  they are stored in `fn.__defaults__`, not in a cell  -  so each lambda gets its own private copy of the current `i` value.

---

## How It Connects

Closures are the mechanism behind the "E" in LEGB. The enclosing scope level only works because CPython implements it through cell objects  -  a shared reference that persists after the enclosing function's frame is gone. Without cells, the "E" in the lookup order would fail as soon as the enclosing function returned.
[[legb-rule|The LEGB Rule]]

Decorators are the most common place closures appear in real Python code. A decorator is typically a function that returns an inner function, and that inner function closes over the original function and any additional state the decorator needs. Understanding closures is a prerequisite for understanding how decorators work under the hood.
[[decorators|Decorators]]

---

## Common Misconceptions

Misconception 1: "A closure captures the value of a variable at the time the inner function is defined."
Reality: A closure captures a **reference to the cell**, not the value. If the enclosing scope's variable changes after the inner function is defined, the inner function sees the new value when it is called. The classic loop bug is the canonical example  -  the loop variable is captured by reference, so all closures see its final value. To capture a value at a specific point in time, you must copy it explicitly, typically via a default argument.

Misconception 2: "You need `nonlocal` to read a variable from an enclosing scope."
Reality: `nonlocal` is only required when you want to **assign** to an enclosing variable. Reading a variable from an enclosing scope works automatically via `LOAD_DEREF`  -  no keyword needed. `nonlocal x` tells the compiler to use `STORE_DEREF` for assignments to `x`, directing them to the enclosing cell rather than creating a new local. Without `nonlocal`, an assignment to `x` inside the inner function would create a new local `x` instead of modifying the captured one.

---

## Why It Matters in Practice

Closures are the foundation of a large swath of Python patterns. Every decorator that adds behavior to a function  -  timing it, caching it, logging it, retrying it  -  uses a closure. Every factory function that returns customized callables uses a closure. Every callback registered in an event system that needs context about what triggered it uses a closure. Python's `functools.partial` is conceptually a closure factory. If you write Python code of any complexity, you are using closures constantly, even when you do not think of them by that name.

Memory leaks from closures are also a real concern. When an inner function captures a variable, it holds a reference to the object that variable points to. If the inner function is stored in a long-lived data structure  -  a cache, a list of callbacks, an event handler registry  -  the captured object stays in memory for as long as the closure does. A closure that accidentally captures a large object (say, a request object or a database session) in a callback that is registered indefinitely will keep that large object alive long past when it should have been freed.

---

## Interview Angle

Common question forms:
- "What is a closure in Python?"
- "Explain the classic loop closure bug."
- "How do closures relate to decorators?"

Answer frame: Define a closure as a function that captures variables from an enclosing scope via cell objects. Explain cells as shared containers  -  both inner and outer function read/write the same cell. Use the loop bug to illustrate that closures capture cells (references) not values. Show the default-argument fix and explain why it works (defaults are evaluated at definition time and stored separately). Connect to decorators as the most visible practical use of closures.

---

## Related Notes

- [[legb-rule|The LEGB Rule]]
- [[namespaces-and-scopes|Namespaces and Scopes]]
- [[decorators|Decorators]]
