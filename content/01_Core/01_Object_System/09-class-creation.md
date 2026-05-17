---
title: How Classes Are Created
description: "When Python processes a `class` statement, it follows a precise sequence — determine the metaclass, call __prepare__ for the namespace, execute the class body, then call the metaclass to build the class object — understanding this sequence demystifies decorators, metaclasses, and descriptors."
tags: [class-creation, metaclass, class-statement, namespace, cpython, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# How Classes Are Created

> When Python processes a `class` statement, it follows a precise sequence — determine the metaclass, call __prepare__ for the namespace, execute the class body, then call the metaclass to build the class object — understanding this sequence demystifies decorators, metaclasses, and descriptors.

---

## Quick Reference

**Core idea:**
- The `class` statement is syntactic sugar for a specific sequence: **determine metaclass → `__prepare__` → execute body → call metaclass**
- Step 1: the metaclass is the explicit `metaclass=` keyword, or inherited from the most derived base class's metaclass, or `type`
- Step 2: `metaclass.__prepare__(name, bases)` returns the initial namespace dict (default `{}`) — enables ordered attribute tracking
- Step 3: the class body executes as a code block with the namespace as its local scope — `def` and assignments populate it
- Step 4: `metaclass(name, bases, namespace)` produces the class object — this is `type.__new__` for standard classes

**Tricky points:**
- `__set_name__(owner, name)` is called on any descriptor found in the namespace **after** the class is created — `property`, `classmethod`, and custom descriptors that define `__set_name__` receive the owning class and the attribute name they were assigned
- Class decorators (`@decorator` on a class definition) run **after** the class is fully created — they receive the complete class object and return a replacement
- The class body executes in a **fresh scope** — name lookups during the class body do not use LEGB; they use the namespace dict directly and then the enclosing scope for outer names
- `super()` with no arguments works inside class bodies because the compiler implicitly stores `__class__` (a cell variable pointing to the class being defined) in the method's closure
- Mutating the namespace **during** the class body (not before or after) is what `__prepare__` is for — return a custom dict to intercept attribute assignments

---

## What It Is

Think of a class statement as a construction project with four phases. Phase 1: hire the architect — Python determines which "design firm" (metaclass) will oversee the project. Phase 2: prepare the blueprint template — the architect provides a standard project specification form (`__prepare__` returns the namespace). Phase 3: fill in the blueprint — the class body executes, filling the spec with method definitions, attributes, and constants. Phase 4: build the structure — the architect takes the completed spec and constructs the actual building (the class object). If the project has decorators, they are like a final inspection that can still modify the building after it is complete.

Most Python developers write `class MyClass:` and think of it as a single atomic operation. But it is a four-step process, and each step is an interception point where behavior can be customized. Metaclasses intercept steps 1–4. `__prepare__` intercepts the namespace creation. `__init_subclass__` runs as part of step 4 in base classes. `__set_name__` runs after step 4 for descriptors. Class decorators run entirely after step 4. Each mechanism targets a different phase of the same construction process.

The fact that the class body executes as code — not that it is parsed as declarations — is what makes Python class definitions so flexible. `def method(self):` inside a class body is just a function definition that assigns to the local namespace. But so is any other Python statement: `if sys.platform == "win32": platform_method = win_impl; else: platform_method = unix_impl`. You can compute attributes conditionally, loop to generate multiple methods, or call functions that return methods. The class body is executable Python, not a static declaration.

---

## How It Actually Works

The Python compiler compiles a `class` statement into bytecode that calls `__build_class__` (available as `builtins.__build_class__`). The bytecode loads the class body as a code object and passes it, along with the class name and base classes, to `__build_class__`. This C function implements the four steps.

Step 1 — Metaclass resolution: `__build_class__` calls `_calculate_metaclass(meta, bases)`. It checks the explicit `metaclass=` keyword argument. If absent, it iterates over the base classes and takes the most-derived metaclass (the one that is a subclass of all others). If no bases, defaults to `type`.

Step 2 — Prepare: if the metaclass has `__prepare__`, calls `metaclass.__prepare__(name, bases)` to get the initial namespace. The returned object (usually a `dict`, sometimes an `OrderedDict` or custom mapping) is what the class body will populate.

Step 3 — Execute body: the class body's code object is called as a function with the namespace as its local scope. Every `def` and assignment in the class body adds to this namespace. `__qualname__` is automatically set in the namespace. If the class body defines `__init_subclass__` kwargs on base classes, they are collected here.

Step 4 — Construct class: `metaclass(name, bases, namespace)` is called. For standard `type`, this calls `type.__new__(type, name, bases, namespace)`, which constructs the `PyTypeObject` C struct, calls `__set_name__` on each descriptor in the namespace, then calls `__init_subclass__` on each base class.

---

## How It Connects

Metaclasses intercept the full class creation process. The metaclass determines which class-creation machinery runs — its `__prepare__`, `__new__`, and `__init__` are the customization points for steps 1–4.
[[metaclasses|Metaclasses]]

Descriptors' `__set_name__` hook is called in step 4 after the class is created. This is how descriptors like `property` can know the attribute name they were assigned to — a mechanism not possible before `__set_name__` was added in Python 3.6.
[[descriptors|Descriptors]]

Class decorators run after step 4. They are the simplest way to modify a class post-creation: wrap methods, register the class, add attributes. Unlike metaclasses, class decorators do not affect subclasses unless explicitly designed to.
[[decorators|Decorators]]

---

## Common Misconceptions

Misconception 1: "The class body is a static namespace — you can't use regular Python code in it."
Reality: The class body is executed as a code block. Any Python statement is valid: conditionals, loops, function calls, imports. Assignments and `def` statements populate the class namespace, but so does any code that binds names. The class body's execution is what allows computed attributes, conditional method definitions, and metaclass-driven inspection of the namespace as it is built.

Misconception 2: "Class decorators and metaclasses do the same thing."
Reality: They run at different phases and have different scopes. A class decorator runs after the class is fully created — it receives a completed class object. A metaclass runs during class creation — it can modify the namespace before the class object exists. A class decorator does not affect subclasses; a metaclass is inherited by subclasses. For one-off per-class transformations, a decorator is simpler. For hierarchy-wide customization that must apply to all subclasses, a metaclass (or `__init_subclass__`) is needed.

---

## Why It Matters in Practice

Understanding the class creation sequence explains why `super()` works without arguments. The Python compiler, when it sees a `class` statement, wraps all `def` blocks inside it with a closure that captures `__class__` — a cell variable pointing to the class being created. This cell is filled in step 4 when the class object is constructed. `super()` reads `__class__` from this closure, which is why calling `super()` with no arguments works correctly even in deeply nested subclass hierarchies.

The `__set_name__` hook introduced in Python 3.6 is one of the most practically useful class-creation hooks. A descriptor class can define `def __set_name__(self, owner, name): self.attr_name = name` and automatically know which attribute it was assigned to. This eliminated the need to pass the attribute name explicitly to descriptor constructors (like `name = Column("name", String)` versus just `name = Column(String)`), making many ORM-style APIs much cleaner.

---

## Interview Angle

Common question forms:
- "What happens when Python processes a `class` statement?"
- "When does `__set_name__` get called?"
- "What is `__prepare__` used for?"

Answer frame: The `class` statement triggers a four-step process: (1) determine metaclass from keyword or base classes, (2) call `metaclass.__prepare__()` to get the initial namespace dict, (3) execute the class body with that namespace, (4) call `metaclass(name, bases, namespace)` to create the class object. `__set_name__` is called on descriptors after step 4. Class decorators run after step 4. `super()` works because the compiler implicitly captures `__class__` as a cell variable in methods.

---

## Related Notes

- [[metaclasses|Metaclasses]]
- [[type-and-object|type and object]]
- [[descriptors|Descriptors]]
- [[decorators|Decorators]]
- [[mro|Method Resolution Order]]
