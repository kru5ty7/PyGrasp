---
title: 11 - The Call Stack
description: The call stack is the chain of active frame objects in a Python thread — each function call pushes a new frame, each return pops it, and the stack's depth limit (default 1000) is what causes RecursionError in infinite recursion.
tags: [call-stack, frame-object, recursion, traceback, cpython, execution, layer-0, core]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# The Call Stack

> The call stack is the chain of active frame objects in a Python thread — each function call pushes a new frame, each return pops it, and the stack's depth limit (default 1000) is what causes RecursionError in infinite recursion.

---

## Quick Reference

**Core idea:**
- The call stack is the sequence of **active frame objects**, linked by `f_back` pointers from the current frame back to the module-level frame
- Each function call **pushes** a new frame onto the stack; each return **pops** it — the currently executing frame is always at the top
- Python's default stack depth limit is **1000 frames** — exceeded by unbounded recursion, producing `RecursionError`
- `sys.getrecursionlimit()` reads the limit; `sys.setrecursionlimit(n)` changes it — risky, as a deeper stack can cause a C-level stack overflow
- A **traceback** is a snapshot of the call stack at the point an exception was raised — walking the traceback's `tb_next` chain reveals each frame in the stack

**Tricky points:**
- Python's stack depth limit counts **Python frames**, not C stack frames — C functions called from Python (built-ins) do not consume the Python frame counter
- `sys.setrecursionlimit()` sets the Python frame limit but **not** the underlying OS thread stack size — deeply recursive Python code can still cause a C stack overflow (segfault) even below the Python limit
- Each thread has its own **independent call stack** — `threading.Thread` gets a fresh, empty stack
- The REPL and `exec()` each start with a module-level frame at the bottom of their respective stacks
- In CPython 3.11+, frames are allocated on a C-level "frame stack" per thread — actual memory for frames is a C array, not the OS thread stack

---

## What It Is

Think of a stack of trays in a cafeteria. Every time a new dish is being prepared, a new tray is placed on top of the stack. The chef always works on the top tray. When the dish is complete, the top tray is removed and the chef resumes working on the tray that was underneath. Dishes are prepared in a strict last-in, first-out order — you cannot finish a lower tray until all the trays above it have been completed and removed. Python's call stack works identically: every function call adds a new frame (tray) on top; when the function returns, its frame is removed and execution resumes in the frame below.

The call stack exists because functions call other functions, which call other functions, and each active call needs to remember where it left off. When `main()` calls `parse()`, which calls `tokenize()`, which calls `read_char()`, there are four active frames simultaneously. Each frame has its own local variables, its own instruction pointer (knowing where in its function's bytecode execution is), and a pointer back to the frame that called it. When `read_char()` returns, its frame is discarded and `tokenize()` resumes at the instruction after the call. The stack naturally enforces this: whatever called most recently is the thing that must return first.

A traceback — the output Python prints when an exception propagates — is a rendering of the call stack at the moment the exception was raised. Reading a traceback from top to bottom gives the call chain in reverse: the bottom entry is the oldest frame (closest to the module level), and the top entry is the most recent frame (where the exception actually occurred). The `traceback` module's `extract_stack()` and the exception's `__traceback__` attribute both provide programmatic access to this same chain.

---

## How It Actually Works

In CPython, each thread maintains a pointer to its current frame (`PyThreadState.frame`). When a Python function is called, a new `PyFrameObject` is created with `f_back = current_frame`, and `PyThreadState.frame` is updated to point to the new frame. When the function returns, `PyThreadState.frame` is reset to `f_back`. The "call stack" is simply the linked list formed by this chain of `f_back` pointers.

The recursion limit is enforced by a counter in `PyThreadState` (`recursion_remaining` in CPython 3.11+). On each function call entry, the counter is decremented. If it reaches zero, `RecursionError` is raised. When the call returns normally, the counter is incremented. `sys.setrecursionlimit(n)` sets the initial value of this counter. There is no actual stack-size measurement — it is purely a frame count.

The traceback object (`PyTracebackObject`) is built when an exception is raised. It captures the current frame (`f_code`, `f_lineno`) at the point of the `raise`. As the exception propagates through `except` blocks and up through call levels, additional `PyTracebackObject` entries are prepended to form the chain. The `traceback.tb_next` pointer chains these entries in order from outermost (earliest) to innermost (where the exception was raised). The `except Exception as e:` clause captures the exception; `e.__traceback__` provides access to this chain.

---

## How It Connects

The call stack is made of frame objects. Each entry on the stack is a `PyFrameObject` with local variables, a code object, an instruction pointer, and a `f_back` pointer. Understanding frame objects is understanding the substance of the call stack.
[[frame-object|The Frame Object]]

The call stack exists on top of the memory model's distinction between stack and heap. The frames themselves are allocated on the heap (or the CPython frame stack in 3.11+), but they conceptually implement the stack data structure that governs function call nesting.
[[stack-vs-heap|Stack vs Heap]]

---

## Common Misconceptions

Misconception 1: "Increasing `sys.setrecursionlimit()` is a safe way to allow deeply recursive algorithms."
Reality: The Python recursion limit counts Python frames. Each frame needs memory and C stack space. Increasing the limit to 10,000 means 10,000 frames can be active simultaneously — each frame might use several hundred bytes, and the OS thread stack (typically 1–8 MB) may overflow before the Python limit is reached, causing a segfault rather than a clean `RecursionError`. Deep recursion is better handled by converting the algorithm to iteration with an explicit stack data structure, which allocates memory on the heap rather than consuming the call stack.

Misconception 2: "The call stack shows all currently running Python code."
Reality: The call stack shows the active call chain for the current thread only. Python programs using `threading` have one call stack per thread — each thread's call stack is independent. To inspect another thread's stack, use `sys._current_frames()`, which returns a dict mapping thread IDs to their current frame. Async code (coroutines) also has its own nuance: suspended coroutines have their frame preserved in the generator object, not on any thread's call stack.

---

## Why It Matters in Practice

`RecursionError` in production code almost always indicates a bug rather than a need to increase the recursion limit. Common causes: mutual recursion between methods where neither terminates (A calls B, B calls A), accidentally using `__repr__` that references the object itself creating infinite `repr()` calls, or genuinely unbounded recursive data structures. The fix is almost always to identify the missing base case or the incorrect termination condition, not to raise the limit.

`traceback.format_stack()` and `traceback.print_stack()` print the current call stack from any point in the code — useful for debugging "how did I get here?" questions without a debugger. Logging the call stack at a specific point (a suspicious code path, a slow query, a lock acquisition) provides the same information as a debugger's backtrace, available in production logs.

---

## Interview Angle

Common question forms:
- "What is the call stack in Python?"
- "What causes RecursionError?"
- "How are tracebacks related to the call stack?"

Answer frame: The call stack is the chain of active frame objects, linked by `f_back` pointers. Each function call pushes a new frame; return pops it. Execution always happens in the top frame. `RecursionError` fires when the frame count exceeds `sys.getrecursionlimit()` (default 1000). A traceback is a snapshot of the call stack at exception-raise time, walking from the deepest (where the error occurred) back toward the module level. `sys._current_frames()` gives all threads' current frames.

---

## Related Notes

- [[frame-object|The Frame Object]]
- [[stack-vs-heap|Stack vs Heap]]
- [[interpreter-loop|The Interpreter Loop]]
- [[generators|Generators]]
