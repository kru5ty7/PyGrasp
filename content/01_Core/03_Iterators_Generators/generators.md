---
title: 03 - Generators
description: A generator is a function that can pause its execution mid-way, yield a value to its caller, and resume from exactly where it left off  -  implemented in CPython by suspending and restoring the function's entire frame, making lazy sequences and cooperative concurrency possible with ordinary Python syntax.
tags: [generators, yield, frame, coroutines, iterators, lazy, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-17
---

# Generators

> A generator is a function that can pause its execution mid-way, yield a value to its caller, and resume from exactly where it left off  -  implemented in CPython by suspending and restoring the function's entire frame, making lazy sequences and cooperative concurrency possible with ordinary Python syntax.

---

## Quick Reference

**Core idea:**
- A function containing `yield` becomes a **generator function**  -  calling it returns a generator object, it does not execute the body
- Generator objects implement the **iterator protocol**: `__iter__` returns self, `__next__` runs until the next `yield`
- CPython suspends a generator by **saving its frame** (evaluation stack + instruction pointer) and returns control to the caller
- Resuming calls `_PyEval_EvalFrameDefault` with the saved frame  -  execution continues at the `YIELD_VALUE` opcode
- `yield from iterable` delegates to another iterator; `send(value)` injects a value into the generator (the `yield` expression evaluates to it)

**Tricky points:**
- Calling a generator function does **not run any of its code**  -  the body only starts running when you call `next()` on the returned object
- `return value` inside a generator raises `StopIteration(value)`  -  the value is on the exception, not returned normally
- A generator is **exhausted** after `StopIteration`  -  calling `next()` again keeps raising `StopIteration`; you cannot restart it
- `yield from` does more than delegation  -  it also passes `send()` values and `throw()` exceptions through to the inner generator, which is the foundation of `async/await`
- Generator expressions like `(x*2 for x in range(10))` are lazy  -  they produce a generator object, not a list; they are not evaluated until iterated

---

## What It Is

Imagine a librarian who can pause mid-sentence while reading you a long document, hand you the page they were on, go do something else, and then come back to pick up exactly where they left off  -  same sentence, same word, same thought. No bookmark needed. They just suspended themselves and resumed perfectly. A Python generator works like that librarian. It can stop at any `yield` statement, hand a value to whoever called it, and later pick up exactly where it paused  -  with all its local variables intact, its loops mid-iteration, its call stack preserved.

The key syntax is `yield`. Any function that contains the word `yield` anywhere in its body becomes a generator function. Calling a generator function does not run the function. Instead, CPython returns a generator object immediately  -  a suspended, not-yet-started execution of the function body. The body only runs when you call `next()` on that object. At that point, the function executes until it hits a `yield` expression, at which point it hands the yielded value to the caller and pauses. The next call to `next()` resumes from the instruction immediately after the `yield`.

Generators are Python's mechanism for lazy evaluation. A regular function that returns a list must build the entire list in memory before returning anything. A generator function can produce values one at a time, generating each only when requested. This makes it possible to work with sequences that are too large to fit in memory, or sequences that are infinite, or sequences whose next value is expensive to compute and may not always be needed. `range(1_000_000)` is a generator-like object for exactly this reason  -  it does not build a million integers in memory, it computes them on demand.

---

## How It Actually Works

When CPython compiles a generator function, it sets a flag on the resulting `PyCodeObject` (`CO_GENERATOR`). When the function is called, CPython checks this flag and, instead of executing the function body, allocates a generator object (`PyGenObject`) that wraps a suspended frame. The frame is fully initialized  -  local variable array allocated, instruction pointer set to the start of the function  -  but not yet executed. The generator object is returned to the caller.

When `next()` is called on the generator, CPython calls `_PyEval_EvalFrameDefault` with the generator's saved frame. The evaluator runs normally until it encounters the `YIELD_VALUE` opcode (compiled from a `yield` expression). At `YIELD_VALUE`, the evaluator pops the top of the evaluation stack (the yielded value), marks the generator as suspended, saves the frame state (the current instruction pointer and evaluation stack), and returns the yielded value to the caller. The frame is not destroyed  -  it stays alive inside the generator object.

When `next()` is called again, the saved frame is handed back to `_PyEval_EvalFrameDefault`, which resumes execution at the instruction after `YIELD_VALUE`. All local variables from the previous run are exactly as they were  -  they are still in the local variable array of the saved frame. When the function body reaches its end or a `return` statement, CPython raises `StopIteration` (with the return value as the exception's value if `return value` was used) and marks the generator as exhausted.

`send(value)` works by placing `value` at the top of the evaluation stack before resuming  -  this is the value that the `yield` expression evaluates to on resume. This is the mechanism that underpins coroutines: `async def` functions are generator functions under the hood (using `CO_COROUTINE` instead of `CO_GENERATOR`), and `await expr` is `yield from expr` in disguise. The entire `async/await` system is built on the generator frame suspension mechanism.

---

## How It Connects

Generators work by suspending and restoring the interpreter loop's frame. The frame contains the evaluation stack and the instruction pointer  -  the exact state the interpreter loop needs to resume. Understanding how the loop uses frames is what makes the generator mechanism concrete rather than magical.
[[interpreter-loop|The Interpreter Loop]]

Generators implement the iterator protocol: they have `__iter__` (returns self) and `__next__` (runs until yield or StopIteration). Understanding the iterator protocol clarifies exactly what a generator object is  -  not a special new kind of thing, but a specific implementation of a well-defined interface.
[[iterators|Iterators and Iterables]]

`yield from` in a generator is the direct syntactic ancestor of `await` in a coroutine. Coroutines are built on top of the generator frame suspension mechanism  -  an `async def` function is compiled almost identically to a generator, with `await` compiling to `SEND`/`YIELD_FROM` opcodes. Generators are the foundation that coroutines stand on.
[[coroutines|Coroutines]]

---

## Common Misconceptions

Misconception 1: "Calling a generator function runs the function and returns the first yielded value."
Reality: Calling a generator function runs none of its code. It returns a generator object in a suspended, not-yet-started state. The function body starts running only when `next()` is called on that object for the first time. This is why `def gen(): print("start"); yield 1` prints nothing when you call `gen()`  -  it only prints when you call `next(gen())`.

Misconception 2: "A generator can be iterated multiple times like a list."
Reality: A generator is a stateful, one-pass iterator. Once it has raised `StopIteration`, it is exhausted. Calling `next()` again keeps raising `StopIteration`. If you need to iterate the same data multiple times, you need either a list (which stores all values at once) or a new generator object (call the generator function again). Passing an exhausted generator to `list()`, `for`, or `sum()` produces an empty result with no error.

---

## Why It Matters in Practice

Generators solve a real memory problem elegantly. Reading a 10 GB log file line by line with `for line in open("huge.log"):` works because Python's file objects are iterators that read one line at a time  -  a generator-like pattern. Processing a database query result with a server-side cursor that streams rows one at a time instead of fetching all rows into memory at once follows the same pattern. Anywhere you have "produce one item, process it, produce the next item," a generator gives you a clean way to write that pipeline without holding everything in memory.

Generators also make it possible to write cooperative multitasking in pure Python. An event loop can drive multiple generators, calling `next()` on each in turn, allowing each to do a small unit of work and yield back control. This is exactly the model that `asyncio` uses: `async def` functions are coroutines that yield back to the event loop at every `await`, and the event loop is a scheduler that decides which coroutine to resume next. Understanding generators is the prerequisite for understanding how async Python actually works at the bytecode level.

---

## Interview Angle

Common question forms:
- "What is a generator in Python and how is it different from a regular function?"
- "What happens when you call a generator function?"
- "How does `yield from` relate to `await`?"

Answer frame: Define a generator function as one containing `yield`  -  calling it returns a suspended generator object, not a result. Explain the frame suspension mechanism: the frame (stack + instruction pointer) is saved at `yield` and restored at `next()`. Describe `send(value)` as injecting a value back into the suspended frame. Connect `yield from` to `async/await`  -  coroutines are generators with `CO_COROUTINE` flag, and `await` is `yield from` in disguise. Use lazy evaluation as the practical motivation.

---

## Related Notes

- [[interpreter-loop|The Interpreter Loop]]
- [[iterators|Iterators and Iterables]]
- [[coroutines|Coroutines]]
