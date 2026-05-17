---
title: 01 - Namespaces and Scopes
description: A namespace is a mapping from names to objects; a scope is the region of code where a namespace is directly accessible — together they define how every name in your program is resolved to a value.
tags: [namespaces, scopes, LEGB, cpython, bytecode, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Namespaces and Scopes

> A namespace is a mapping from names to objects; a scope is the region of code where a namespace is directly accessible — together they define how every name in your program is resolved to a value.

---

## Quick Reference

**Core idea:**
- A **namespace** is a dictionary mapping names → objects; Python has four kinds: local, enclosing, global, built-in
- A **scope** is the region of source code where a namespace is directly accessible without a prefix
- Name lookup follows **LEGB order**: Local → Enclosing → Global → Built-in
- Global namespace = module's `__dict__`; built-in namespace = `builtins.__dict__`
- Local namespace for a function = a **C array** indexed by `co_varnames` (not a dict) — faster than dict lookup

**Tricky points:**
- `global x` inside a function doesn't mean "look up x globally" — it means "**all assignments to x in this function** go to the global namespace"
- A variable referenced before assignment inside a function raises `UnboundLocalError` even if a global with that name exists — because Python decides at compile time (not runtime) whether a name is local
- Module-level code and class bodies each get their own namespace, but class body namespaces **don't form an enclosing scope** for methods defined inside — a method cannot see class-level names via LEGB
- `del x` removes the name from the current namespace — it does not delete the object if other references exist

---

## What It Is

Imagine a company with multiple departments, each keeping its own internal phone directory. When someone in the engineering department needs to call "Alex," they first check their own department's directory. If Alex is not there, they check the floor's shared directory, then the building-wide directory, and finally the company-wide directory. Each directory is a namespace; the order in which they are searched is the scoping rule. Python works exactly this way. Every piece of code runs inside a set of nested namespaces, and name lookup always follows a fixed search order.

A namespace in Python is implemented as a Python dictionary: keys are name strings, values are the objects those names refer to. Every module has its own global namespace, stored as the module's `__dict__`. Every function call creates a fresh local namespace for that invocation — separate from every other call, even recursive ones. When you write `x = 42` inside a function, you are adding the key `"x"` to that function's local namespace with the value being the integer object `42`. When you write `x = 42` at the module level, you are adding `"x"` to the module's global namespace.

The four namespaces Python searches, in order, are: local (the current function's namespace), enclosing (the namespaces of any containing functions, from inner to outer), global (the current module's namespace), and built-in (Python's `builtins` module, which contains `len`, `print`, `range`, `Exception`, and all the other names available everywhere). The acronym for this order is LEGB. This search happens every time Python evaluates a name that is not being assigned to — reading `x` triggers a lookup; writing `x = value` assigns to the local namespace by default.

---

## How It Actually Works

CPython optimizes local namespace access significantly. While the global namespace is a real Python `dict` object (the module's `__dict__`), the local namespace for a function is not. At compile time, the compiler knows exactly which names are local to each function by scanning the function body for assignments and `for` targets. These local names are listed in `co_varnames` in the `PyCodeObject`. At runtime, CPython allocates a C array of `PyObject *` pointers — one slot per local variable — indexed by position in `co_varnames`. Accessing a local variable is an O(1) array index into this C array, not a dictionary lookup.

The bytecode opcodes for name lookup reflect this structure. `LOAD_FAST` and `STORE_FAST` access the local variable array by index — this is the fastest kind of name access in Python. `LOAD_GLOBAL` and `STORE_GLOBAL` access the module's `__dict__` by key — a dictionary lookup, slower than array indexing. `LOAD_DEREF` and `STORE_DEREF` access cell objects used by closures (more on this in the Closures note). `LOAD_NAME` is used in class bodies and module-level code where the namespace structure is more flexible.

Python determines whether a name is local, enclosing, or global **at compile time**, not at runtime. The compiler scans the function body and marks any name that appears on the left side of an assignment as local. This happens before any code runs. The consequence is that a name can be "decided local" by the compiler even if the assignment is in a branch that never executes at runtime. If you reference the name before the branch, CPython finds no value in the local array and raises `UnboundLocalError` — not `NameError`, which would fire if Python looked in outer scopes. The name was categorized as local at compile time, so the outer scope is never checked.

---

## How It Connects

The local variable array that CPython uses for fast name access is part of the frame object that the interpreter loop creates for each function call. Understanding namespaces requires understanding that each function invocation gets its own frame, and that frame contains both the local variable array and a reference to the function's global namespace (its module's `__dict__`).
[[interpreter-loop|The Interpreter Loop]]

Every value stored in a namespace — every object that a name maps to — is a Python object. The namespace itself (when it is a dict) is also a Python object. The name lookup system is built entirely on top of the object model.
[[everything-is-an-object|Everything is an Object]]

Closures arise directly from the enclosing scope part of LEGB. When a function references a name from an enclosing function's scope, that name is not looked up via LEGB at runtime — it is captured as a cell object at function definition time. Closures are the mechanism that makes the "E" in LEGB work across function call boundaries.
[[closures|Closures]]

The LEGB rule defines the search order but leaves many questions open: what are the exact rules for each level, how do `global` and `nonlocal` modify the defaults, and what happens in nested scopes? The LEGB note focuses on these details.
[[legb-rule|The LEGB Rule]]

---

## Common Misconceptions

Misconception 1: "Local variables are just entries in a dictionary, like global variables."
Reality: Global variables live in the module's `__dict__` — a real Python dict. Local variables in a function live in a C array indexed by `co_varnames`. This is why local variable access (`LOAD_FAST`) is faster than global variable access (`LOAD_GLOBAL`). There is no local namespace dictionary object you can access directly; `locals()` builds one on demand as a snapshot, but modifying it does not affect actual local variables.

Misconception 2: "Class bodies create an enclosing scope that methods inside can use."
Reality: The class body has its own namespace during class creation, but that namespace does not become an enclosing scope for methods defined inside the class. A method defined in a class cannot see class-level names through LEGB — it can only access them as attributes via `self` or `ClassName`. This is a deliberate design decision, not an oversight, and it surprises developers coming from languages where inner classes or methods can see their containing class's variables directly.

---

## Why It Matters in Practice

Namespace rules explain a large category of Python bugs. The `UnboundLocalError` from referencing a name before its assignment inside a function is one of the most common errors new Python developers hit, and it only makes sense once you understand that the compiler decides at compile time whether a name is local. The fix — either moving the assignment before the reference, or adding `global x` if you mean the global — follows directly from understanding how namespaces work.

The global namespace being the module's `__dict__` has practical implications for module design. Every name defined at the top level of a module is a public attribute of that module object — accessible as `module.name` after import. There is no private scope at the module level in Python; the underscore convention (`_name`) is just a signal, not enforcement. Understanding that the module namespace is just a dictionary also explains why `import *` is dangerous: it copies every non-underscore name from the source module's `__dict__` into the current module's `__dict__`, potentially overwriting existing names silently.

---

## Interview Angle

Common question forms:
- "What is a namespace in Python?"
- "Explain Python's scoping rules."
- "Why does this code raise UnboundLocalError?" (followed by a snippet that assigns to a name inside a conditional)

Answer frame: Define namespace as a name-to-object mapping. Name the four levels (local, enclosing, global, built-in) and the LEGB search order. Explain that the compiler decides at compile time whether a name is local (based on assignment in the function body), and that this is why referencing a name before its local assignment raises `UnboundLocalError` rather than falling through to the global. Mention that locals use a C array (`LOAD_FAST`) while globals use a dict (`LOAD_GLOBAL`).

---

## Related Notes

- [[everything-is-an-object|Everything is an Object]]
- [[interpreter-loop|The Interpreter Loop]]
- [[closures|Closures]]
- [[legb-rule|The LEGB Rule]]
