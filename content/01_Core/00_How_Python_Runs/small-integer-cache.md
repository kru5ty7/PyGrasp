---
title: 23 - Small Integer Cache
description: CPython pre-allocates integer objects for values -5 through 256 at interpreter startup — these cached integers are reused for every occurrence of those values, so id(0) == id(0) is always True and assigning x = 1 never allocates new memory.
tags: [small-integer-cache, integer-cache, interning, cpython, memory, optimization, layer-0, core]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# Small Integer Cache

> CPython pre-allocates integer objects for values -5 through 256 at interpreter startup — these cached integers are reused for every occurrence of those values, so id(0) == id(0) is always True and assigning x = 1 never allocates new memory.

---

## Quick Reference

**Core idea:**
- CPython pre-creates `PyLongObject` instances for integers **-5 through 256** during interpreter initialization
- Every Python operation that produces an integer in this range — arithmetic, indexing, `len()`, `ord()` — returns a pointer to the corresponding cached object, not a newly allocated one
- `id(1) == id(1)` is always `True`; `id(1000) == id(1000)` is `False` in most contexts
- The cache is an array of `PyLongObject` structs in `Objects/longobject.c`: `static PyLongObject small_ints[NSMALLNEGINTS + NSMALLPOSINTS]`
- The reference counts of cached integers grow very high — every use of `0`, `1`, `True` (which is `int(1)`), or list/dict lengths in this range increments the count

**Tricky points:**
- The boundary **256** is not arbitrary — it covers common array indices, ASCII character codes, and most counter values; 257+ are less common and the cache cost would be higher
- `True` is `1` and `False` is `0` — they are instances of `bool` (a subclass of `int`) stored as separate objects, but identity comparisons show they share the int objects
- In the **interactive REPL**, `a = 257; b = 257; a is b` ? `False` (two separate integer objects). In a **compiled module**, the compiler may deduplicate constant 257 in the bytecode, so the same constant is `True`
- The cache only applies to the **CPython runtime** — PyPy, Jython, and MicroPython may cache different ranges or nothing
- Negative integers below -5 are not cached: `id(-6) == id(-6)` is `False`

---

## What It Is

Think of a vending machine for the most common coins. Rather than manufacturing a new coin each time someone needs change, the vending machine pre-stocks hundreds of pennies, nickels, dimes, and quarters at the start of the day. When you need a quarter, you get one of the pre-existing quarters from the machine's stock. When a thousand customers each need a quarter for their transaction, they are all using quarters from the same stock — no new quarters are manufactured. CPython's integer cache works the same way: the most commonly needed integers are pre-manufactured at startup, and every request for those values returns one of the pre-made objects.

The integer cache exists because small integers are extraordinarily common in Python programs. Loop counters, list indices, string lengths, hash values, return codes, boolean arithmetic — an enormous fraction of integer operations produces values in the range -5 to 256. Without the cache, each of these would require allocating a new `PyLongObject`, incrementing its reference count when stored, and decrementing and freeing it when no longer needed. For a program running millions of iterations, this would create millions of tiny allocations and deallocations per second.

The cache makes these operations free from an allocation perspective. `i += 1` where `i = 0` produces `1` — the cached integer at index 6 of the small_ints array. No allocation, no deallocation, just a pointer to a pre-existing object. The reference count of the cached `1` object goes up when the result is assigned and down when it falls out of scope, but the object itself is permanent for the life of the interpreter.

---

## How It Actually Works

In `Objects/longobject.c`, the cache is defined as:

```c
#define NSMALLNEGINTS 5
#define NSMALLPOSINTS 257
static PyLongObject small_ints[NSMALLNEGINTS + NSMALLPOSINTS];
```

This is a C array of 262 `PyLongObject` structs (one for each integer from -5 to 256). During interpreter initialization (`_PyLong_Init()`), each struct is initialized with the correct integer value and a reference count that starts high enough to prevent premature deallocation. The macro `IS_SMALL_INT(ival)` checks if a value falls in the cached range, and `__PyLong_GetSmallInt_internal(ival)` returns a pointer to the corresponding array element.

Every path in CPython that creates a Python integer — binary arithmetic (`PyLong_FromLong`), type conversion (`int(x)`), indexing, `len()` — calls `IS_SMALL_INT` on the result before potentially allocating. If the result is in range, a pointer to the cached object is returned directly. The cached object's reference count is incremented as usual (the cache does not exempt cached integers from reference counting), but the object is never actually freed because its reference count never reaches zero — it is always at least 1 from the array itself.

The CPython compiler also performs a related optimization: constant integers in source code that appear in the bytecode's `co_consts` tuple are deduplicated within a code object. Two occurrences of the constant `257` in the same function body may share one `PyLongObject` (even though 257 is outside the cache range) because the compiler stores constants once per code object. This is why `a = 257; b = 257; a is b` can be `True` in a compiled function but `False` in the REPL (where each line is its own compilation unit).

---

## How It Connects

The small integer cache is the most important specific instance of CPython's interning optimization. It is essentially integer interning: one canonical object per small integer value, shared by all references. Understanding general interning — and why it is only applied to immutable objects — provides the conceptual framework for the cache.
[[interning|Object Interning]]

The `id()` function makes the cache observable: `id(1) == id(1)` is always `True` because both calls return the address of the same cached `PyLongObject`. This is the most commonly cited example of `id()` producing identical values for what appear to be independent expressions.
[[id-and-memory-address|id() and Memory Addresses]]

---

## Common Misconceptions

Misconception 1: "All integers in Python are the same object if their values are equal."
Reality: Only integers in the range -5 to 256 are guaranteed to be the same object. `a = 1000; b = 1000; a is b` is `False` in general (both are separate `PyLongObject` allocations, despite having equal values). Even for integers within the cache range, the guarantee is implementation-specific to CPython — other implementations may not cache the same range. Never use `is` to compare integer values; use `==`.

Misconception 2: "The small integer cache means Python is slow at large integer arithmetic."
Reality: The cache affects only allocation and deallocation overhead, not arithmetic speed. `1000 + 1000` is just as fast as `1 + 1` for the actual addition computation. The difference is that `1 + 1` returns a cached object (no allocation) while `1000 + 1000` allocates a new `PyLongObject`. For code that creates many large integer temporaries in a loop, this allocation overhead is measurable, but it is rarely the bottleneck — the interpreter dispatch cost and the arithmetic itself dominate.

---

## Why It Matters in Practice

The cache boundary explains a classic Python interview puzzle: `a = 256; b = 256; print(a is b)` prints `True`, but `a = 257; b = 257; print(a is b)` prints `False` (when run in separate statements in a REPL or as a script). The boundary at 256 is the exact cutoff of the cache. This is a CPython implementation detail, not a language guarantee, which is precisely why it is a useful question for testing understanding of CPython internals versus the Python language specification.

Memory profiling of Python programs occasionally reveals surprising results: a program using only small integers (loop counters from 0 to 255) will show very low integer allocation counts in `tracemalloc` output, because the cached integers are never allocated by the application code. A program generating large integers frequently will show many integer allocations. Understanding the cache helps interpret memory profiler output correctly.

---

## Interview Angle

Common question forms:
- "Why does `a = 256; b = 256; a is b` return True but `a = 257; b = 257; a is b` return False?"
- "What is the small integer cache in CPython?"

Answer frame: CPython pre-allocates integer objects for -5 through 256 at startup. Every operation producing a value in this range returns the same pre-existing object — no allocation. `a is b` is True for small integers because both variables point to the same cached object. Above 256, new objects are allocated for each literal (in the REPL) and they have different memory addresses. Within a compiled function, the compiler may share the constant anyway. This is CPython-specific; never rely on `is` for integer equality.

---

## Related Notes

- [[interning|Object Interning]]
- [[id-and-memory-address|id() and Memory Addresses]]
- [[reference-counting|Reference Counting]]
- [[object-header|Python Object Header]]
