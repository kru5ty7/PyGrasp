---
title: 11 - Object Interning
description: Interning is CPython's optimization of reusing a single object for multiple references to equal values — rather than creating a new object for every identical string or integer, CPython maintains a pool of canonical objects that all references point to.
tags: [interning, string-interning, identity, is-operator, cpython, optimization, layer-0, core]
status: draft
difficulty: intermediate
layer: 0
domain: core
created: 2026-05-17
---

# Object Interning

> Interning is CPython's optimization of reusing a single object for multiple references to equal values — rather than creating a new object for every identical string or integer, CPython maintains a pool of canonical objects that all references point to.

---

## Quick Reference

**Core idea:**
- **Interning** means two variables holding equal values may point to the **same object in memory** — same `id()`, `is` returns `True`
- CPython automatically interns: small integers (−5 to 256), short strings that look like identifiers, string literals at compile time
- `sys.intern(s)` explicitly interns a string, adding it to the interning pool — useful for frequently repeated strings (dict keys, status codes)
- Interned strings allow **identity comparison** (`is`) instead of value comparison (`==`), which is O(1) vs O(n) for long strings
- Interning is an **implementation detail** — do not use `is` to compare strings for equality in application code

**Tricky points:**
- `a = 256; b = 256; a is b` → `True` (cached); `a = 257; b = 257; a is b` → `False` (not cached) — the boundary is −5 to 256
- String interning is **not guaranteed** — whether two equal string variables are the same object depends on how the strings were created (literal vs. runtime construction)
- `"hello" is "hello"` is `True` in one module (same literal, same code object); `"hel" + "lo" is "hello"` may or may not be `True` depending on CPython's constant folding
- The interning pool for strings is a dict — `sys.intern(s)` adds `s` to this dict; interned strings remain alive as long as the interning dict exists (for the process lifetime)
- Interning behavior is **CPython-specific** — other Python implementations may intern different ranges or nothing at all

---

## What It Is

Think of a library that keeps one master copy of each book. When multiple readers want "Python Cookbook," they all get a reference to the same physical book, rather than the library printing a new copy for each reader. The library maintains a catalogue of canonical copies; anyone wanting a common book gets directed to the master copy. Readers cannot modify the books (they are immutable), so sharing the same physical copy is perfectly safe. Interning works the same way: for certain immutable values, CPython keeps one canonical object in a pool, and every reference to that value points to the same object.

Interning is a memory and performance optimization based on two observations. First, Python programs create the same values repeatedly — the same integer in a loop, the same string as a dictionary key, the same constant in a function. Second, immutable objects can be safely shared — since `int` and `str` objects cannot be modified, having two variables point to the same object is indistinguishable from having them point to equal but separate objects, except at the identity level.

CPython automatically interns two categories. Small integers from −5 to 256 are pre-created at interpreter startup as a fixed array; every `int(42)` or `42` in Python code returns the same C object from this array. Strings that qualify as Python identifiers (contain only letters, digits, and underscores) and appear as string literals in source code are interned at compile time — all references to the string literal `"hello"` within a module's code object share the same string object.

---

## How It Actually Works

The small integer cache is a C array of `PyLongObject` structs allocated at interpreter startup in `Objects/longobject.c`. The array covers integers −5 through 256. Every Python operation that produces an integer in this range — arithmetic, subscript, `len()`, `range()` — returns a pointer to the corresponding element of this array rather than allocating a new `PyLongObject`. The reference count of these cached integers climbs very high during a program's execution because every occurrence of `0` or `1` increments their count.

String interning is maintained in a global Python dict stored in `Objects/unicodeobject.c`. `sys.intern(s)` checks whether `s` is already a key in this dict. If it is, the existing interned string is returned. If not, `s` is added as both key and value and returned. The interning dict holds strong references to all interned strings, so they are never freed. The `unicode_latin1` array in CPython additionally caches all 256 single-character Latin-1 strings, making one-character strings like `"a"`, `" "`, and `"\n"` always interned.

The CPython compiler performs constant folding and string deduplication within a single code object. String literals that appear multiple times in one module's source are compiled into a single string object in the code object's `co_consts` tuple. All references to that literal load the same object via `LOAD_CONST`. This is why `"hello" is "hello"` is always `True` within a single compiled unit, but `"hel" + "lo" is "hello"` may not be — the concatenation happens at runtime and produces a new object unless CPython's peephole optimizer folds it.

---

## How It Connects

Interning is built on the object header's reference count. A cached integer has a very high `ob_refcnt` because every use of that integer increments it. When you do `del x` where `x = 42`, the ref count of the integer `42` object drops by one but stays far above zero — the object is never freed.
[[object-header|Python Object Header]]

The small integer cache described here is a specific and important instance of interning. The integer cache note covers the exact range, the C implementation details, and the practical implications of integer identity comparisons.
[[small-integer-cache|Small Integer Cache]]

Understanding that `is` compares object identity (same `PyObject *` pointer) while `==` compares value (calls `__eq__`) is the practical implication of interning. Interning makes `is` faster for interned values but makes it unreliable for equality checks on non-guaranteed-interned values.
[[reference-counting|Reference Counting]]

---

## Common Misconceptions

Misconception 1: "Two equal strings are always the same object in CPython."
Reality: Only certain strings are automatically interned: string literals in source code (within a module), strings that look like Python identifiers, and explicitly `sys.intern()`-ed strings. Strings constructed at runtime — from user input, file reads, network data, string formatting — are generally not interned and are separate objects even if they have equal values. `"hello" == "hello"` is always `True`; `"hello" is "hello"` is True for literals but not guaranteed for runtime-constructed strings.

Misconception 2: "You should use `is` to compare strings for performance."
Reality: `is` checks identity, not equality. For strings that are not guaranteed to be interned, `is` can return `False` even when the strings have equal content. The performance difference between `is` and `==` for short strings is negligible in practice. Use `==` to compare string values. `sys.intern()` followed by `is` comparison is valid for specific performance-critical uses (like symbol table lookups), but requires explicit interning to be safe.

---

## Why It Matters in Practice

`sys.intern()` is useful in specific high-performance scenarios where the same string value is compared against dictionary keys millions of times. A status code string like `"success"` used as a dict key across millions of parsed API responses: if you intern it once and `sys.intern()` all response status strings before lookup, dictionary key comparison uses pointer equality rather than string character comparison. The speedup is measurable for very high-frequency dict lookups.

The boundary of the integer cache (−5 to 256) produces a subtle and surprising bug: `x = 300; y = 300; x is y` is `False` in the REPL (each assignment creates a new object) but may be `True` in a compiled module (the compiler may share the constant). Never rely on integer identity; always use `==` for integer equality.

---

## Interview Angle

Common question forms:
- "What is string interning in Python?"
- "Why is `a is b` True for small integers but not large ones?"
- "What is the difference between `is` and `==`?"

Answer frame: Interning is CPython's optimization of reusing the same object for equal immutable values. Small integers −5 to 256 are pre-allocated as a fixed C array; all Python code referencing those values points to the same objects. String literals in source code are interned at compile time within a code object. `sys.intern(s)` explicitly interns a string. The practical rule: use `==` for value equality; `is` tests object identity, which interning incidentally makes true for cached objects but is not guaranteed for arbitrary values.

---

## Related Notes

- [[reference-counting|Reference Counting]]
- [[small-integer-cache|Small Integer Cache]]
- [[object-header|Python Object Header]]
- [[everything-is-an-object|Everything is an Object]]
