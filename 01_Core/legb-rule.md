---
title: The LEGB Rule
description: LEGB is the order Python searches for a name: Local → Enclosing → Global → Built-in — it is not a suggestion but a strict compile-time and runtime contract that determines which object every name in your code refers to.
tags: [LEGB, scopes, namespaces, global, nonlocal, closures, layer-1, core]
status: draft
difficulty: beginner
layer: 1
domain: core
created: 2026-05-17
---

# The LEGB Rule

> LEGB is the order Python searches for a name: Local → Enclosing → Global → Built-in — it is not a suggestion but a strict compile-time and runtime contract that determines which object every name in your code refers to.

---

## Quick Reference

**Core idea:**
- **L**ocal → **E**nclosing → **G**lobal → **B**uilt-in — Python searches these four levels in order, stopping at the first match
- **Local**: names assigned inside the current function
- **Enclosing**: names in any containing function's scope (from inner to outer); accessed via `LOAD_DEREF` / cell objects
- **Global**: the module's `__dict__`; accessed via `LOAD_GLOBAL`
- **Built-in**: `builtins.__dict__` — `len`, `print`, `range`, `Exception`, etc.
- `global x` → bind all assignments to `x` in this function to the **global** namespace
- `nonlocal x` → bind all assignments to `x` in this function to the **nearest enclosing** namespace that has `x`

**Tricky points:**
- Python decides whether a name is local **at compile time** — any assignment to a name inside a function makes it local for the **entire** function body, even before the assignment line
- Referencing a name before its assignment in the same function raises `UnboundLocalError`, not `NameError` — the search never reaches the global
- `global x` does not require `x` to exist in the global namespace yet — it creates it there on first assignment
- `nonlocal x` **requires** `x` to exist in an enclosing scope — if it doesn't, it's a `SyntaxError` at compile time
- Class bodies **do not** create an enclosing scope for methods — `self.attr` is required; you cannot see class variables via LEGB from a method

---

## What It Is

Imagine four layers of a filing system stacked on top of each other. When someone needs a document named "budget," they search from the top down: first their own desk drawer, then the shared drawer on the same floor, then the main office filing cabinet, then the company-wide archive. They stop as soon as they find the document. If it is on their desk, they never open the shared drawer. If it is nowhere, they report it missing. Python's name lookup works exactly this way, with four fixed layers that are always searched in the same order.

Local is your desk drawer — names defined or assigned inside the current function. Enclosing is the shared drawer — names from any function that contains the current function, searched from the innermost containing function outward. Global is the main office filing cabinet — the current module's namespace. Built-in is the company archive — Python's `builtins` module, which holds `len`, `print`, `range`, `True`, `False`, `None`, all the exception types, and everything else that works without an import.

When Python encounters a bare name like `x` in your code, it looks through these four layers in order and returns the first `x` it finds. The search stops at the first hit. If `x` is defined locally, the global `x` and the built-in `x` (if any) are invisible — the local one shadows them. If `x` is not found in any layer, Python raises `NameError`. The lookup order is not configurable. It is not affected by inheritance or imports. It is always L → E → G → B.

---

## How It Actually Works

The "compile-time" part of LEGB is what surprises most developers. Python's compiler does a single pass over each function body before generating any bytecode. During this pass, it categorizes every name in the function as either local, cell (an enclosing-scope variable used by a nested function), free (a variable from an enclosing scope), or global. The categorization rule is simple: if a name appears on the left side of an assignment anywhere in the function body (including `for` targets, `with` targets, function parameters, `import` names, and `except` clause variables), it is local. Otherwise it is looked up in the outer scopes.

The consequence of this compile-time decision is that the local/global distinction is made for the entire function at once, not line by line. Consider a function where `x` is assigned on line 10 but read on line 5. CPython marks `x` as local (because line 10 assigns to it), and when line 5 runs and tries to read `x`, it looks in the local variable array. There is no value there yet, so it raises `UnboundLocalError`. The global `x` is never checked — it was ruled out at compile time. The fix is either `global x` at the top of the function, or moving the assignment before the read.

The `global` and `nonlocal` keywords override the compile-time categorization. `global x` in a function tells the compiler: categorize `x` as global for this entire function — all reads and writes to `x` go to the module namespace. `nonlocal x` tells the compiler: categorize `x` as free (from an enclosing scope) for this entire function — all reads and writes go to the nearest enclosing function's namespace that has `x`. Both keywords must appear before any use of the name in the function, and the compiler raises a `SyntaxError` if this rule is violated.

---

## How It Connects

LEGB is the lookup rule; namespaces are the data structures being looked up. The local namespace is a C array; the global namespace is a dict; the built-in namespace is a dict. Understanding why these structures differ — and why the local one is faster — requires understanding what a namespace actually is at the CPython level.
[[namespaces-and-scopes|Namespaces and Scopes]]

The enclosing scope level of LEGB is what makes closures possible. When a nested function references a name from its enclosing function, that name becomes a "cell variable" — shared between both functions via a special cell object, not a regular entry in the local array. The closure note explains the mechanism by which the "E" in LEGB works across function lifetimes.
[[closures|Closures]]

---

## Common Misconceptions

Misconception 1: "You can shadow a built-in by accident just by using the same name."
Reality: You can, and it is a common source of bugs. If you name a variable `list`, `type`, `id`, `input`, or `len` inside a function, that local name shadows the built-in for the rest of the function. The built-in is still there — at the B level — but the local name at the L level is found first. The shadowing lasts only for the function's scope; other functions are not affected. PEP 8 recommends appending a trailing underscore to avoid conflicts: `list_` instead of `list`.

Misconception 2: "Using `global x` makes `x` a global variable everywhere in the program."
Reality: `global x` only affects the current function. It tells that function to use the module-level `x` for all reads and writes of `x`. Other functions in the same module are unaffected — they each make their own local/global determination. `global` is a per-function instruction to the compiler, not a property of the variable itself.

---

## Why It Matters in Practice

LEGB is the rule behind every "why does my variable have the wrong value" bug. The UnboundLocalError from referencing a name before its assignment, the accidental shadowing of a built-in, the surprise of `nonlocal` being required to modify an enclosing variable — all of these trace directly to LEGB. Once you know the rule and understand that it is decided at compile time, these behaviors stop being mysterious and become predictable.

LEGB also explains why global variables slow things down. `LOAD_FAST` (local access) is an array index — O(1) with no hashing. `LOAD_GLOBAL` (global access) is a dictionary lookup — O(1) on average but with hashing overhead. This is why a tight inner loop in performance-critical code sometimes assigns a global function reference to a local variable: `local_len = len` before the loop, then `local_len(x)` inside it. It is a real optimization, and it is a direct consequence of LEGB.

---

## Interview Angle

Common question forms:
- "Explain Python's scoping rules."
- "Why does this code raise UnboundLocalError?" (snippet that reads a name before assigning to it in the same function)
- "What does the `global` keyword do?"

Answer frame: State LEGB with the four levels in order. Emphasize that the local/global decision happens at compile time — any assignment in a function makes that name local for the entire function. Use this to explain `UnboundLocalError`: the name was categorized as local, so the outer scope is never checked, even if a global with that name exists. Explain `global` as a compile-time override. Close with `nonlocal` for modifying enclosing scope variables.

---

## Related Notes

- [[namespaces-and-scopes|Namespaces and Scopes]]
- [[closures|Closures]]
