---
title: 11 - The Frame Object
description: A frame object (PyFrameObject) is the runtime execution context for a single function call  -  it holds the local variables, the bytecode instruction pointer, the value stack, and a reference to the enclosing frame, forming the call stack.
tags: [frame-object, pyframeobject, call-stack, local-variables, execution-context, cpython, layer-0, core]
status: draft
difficulty: intermediate
layer: 0
domain: core
created: 2026-05-17
---

# The Frame Object

> A frame object (PyFrameObject) is the runtime execution context for a single function call  -  it holds the local variables, the bytecode instruction pointer, the value stack, and a reference to the enclosing frame, forming the call stack.

---

## Quick Reference

**Core idea:**
- Every function call in Python creates a **frame object** (`PyFrameObject` in C) that holds all execution state for that call
- A frame contains: the **code object** (`f_code`), a **locals array** (fast locals for arguments and local variables), the **value stack** (operands for bytecode instructions), and a pointer to the **previous frame** (`f_back`)
- The chain of `f_back` pointers from the current frame to `None` forms the **call stack**
- `sys._getframe()` returns the current frame; `inspect.currentframe()` is the public API
- In CPython 3.11+, frames are allocated in a **frame stack** per thread rather than on the heap, significantly reducing function call overhead

**Tricky points:**
- The frame's **value stack** is the operand stack that bytecode instructions push to and pop from  -  it is distinct from the local variables array
- `f_locals` on a live frame is **computed on demand**  -  it creates a dict from the fast locals array each time it is accessed; modifying the returned dict does not change the actual locals
- Generators and coroutines **suspend** execution by preserving their frame  -  the frame is not destroyed when a generator yields; it is detached from the thread's frame stack and reattached on the next `next()` call
- `traceback.tb_frame` gives access to the frames in a traceback  -  used by debuggers and exception formatters
- CPython 3.11 replaced heap-allocated `PyFrameObject` with a lighter `_PyInterpreterFrame` struct; the Python-visible `frame` type is now a thin wrapper

---

## What It Is

Think of a frame object as a workspace that a contractor sets up for a specific job. When hired to install kitchen cabinets, the contractor brings a specific toolkit (local variables), a job sheet listing the steps (bytecode), a notepad for scratch work (the value stack), and the address of their manager to report to when done (the pointer to the previous frame). When the cabinet installation job is finished, the workspace is packed up and the contractor reports back to the manager. If they need to install flooring during the cabinet job (a nested function call), they set up a new workspace for flooring, complete it, and return to the cabinet workspace exactly where they left off.

A frame encapsulates everything that makes a function call independent from every other function call running at the same time (in recursive calls, threads, or nested function calls). Two recursive calls to the same function have different frame objects  -  each has its own locals array with its own values of `n`, `result`, `index`, or whatever the function uses  -  despite sharing the same code object. The code object describes what to do; the frame is the context in which it is being done at this moment.

The frame is where Python's execution model becomes concrete. The interpreter loop executes bytecode instructions against a frame: `LOAD_FAST 0` loads local variable 0 from the frame's fast locals array onto the frame's value stack. `BINARY_OP +` pops two items from the value stack, adds them, and pushes the result. `STORE_FAST 1` pops from the value stack and stores in local slot 1. Every bytecode instruction reads from or writes to the current frame's state.

---

## How It Actually Works

In CPython, a frame's key fields are: `f_code` (the `PyCodeObject` containing the bytecode and constants), `f_lasti` (the index of the last bytecode instruction executed  -  the instruction pointer), `f_localsplus` (a C array holding fast locals, free variables, and the value stack contiguously), and `f_back` (pointer to the caller's frame, `NULL` for the top-level frame).

The `f_localsplus` array is divided into three logical sections. The first `co_nlocals` slots are the fast locals  -  local variables and parameters. The next section holds free variables (variables from enclosing scopes, stored as cells). The remaining slots are the value stack. The interpreter pushes and pops from the value stack section using a stack pointer (`stackpointer`) that tracks the current top.

When a function is called, CPython's `_PyEval_EvalFrameDefault()` creates a new frame, sets `f_back` to the current frame, sets the interpreter's "current frame" pointer to the new frame, and starts executing the new code object's bytecode. When the function returns (`RETURN_VALUE` instruction), the return value is passed to the caller, the frame is deallocated (or, for generators, suspended), and the interpreter's current frame pointer is reset to `f_back`.

In CPython 3.11+, frames are allocated on a per-thread C stack (the "frame stack") rather than on the Python heap. This avoids `malloc` overhead for each function call and improves cache locality. The `PyFrameObject` seen by Python code (`sys._getframe()`) is a Python-level wrapper around the internal `_PyInterpreterFrame` struct. This change reduced function call overhead significantly and is part of the broader CPython speedup effort in 3.11 and later.

---

## How It Connects

The frame object is what the call stack is made of. Each function call on the call stack corresponds to exactly one live frame. The `f_back` chain of frames is the call stack. When Python prints a traceback, it walks this chain from the current frame back to the module-level frame, printing each frame's file, line number, and local context.
[[call-stack|The Call Stack]]

The interpreter loop executes bytecode instructions against the current frame. The eval loop reads the instruction pointer from the frame, fetches the next bytecode instruction, dispatches it, and updates the frame's value stack and locals. The frame is the interpreter loop's execution context.
[[interpreter-loop|The Interpreter Loop]]

Generators work by suspending and resuming frames. When a generator yields, its frame is detached from the thread's frame stack and stored in the generator object. When `next()` is called, the frame is reattached and execution resumes from where it left off. This is what makes generator suspension fundamentally different from a normal return.
[[generators|Generators]]

---

## Common Misconceptions

Misconception 1: "Modifying `frame.f_locals` changes the function's actual local variables."
Reality: `frame.f_locals` is computed on demand by copying fast locals (from the C array) into a Python dict. Modifying the returned dict does not write back to the fast locals array. The actual locals live in `f_localsplus` and are only accessible through the bytecode instructions `LOAD_FAST` and `STORE_FAST`. This is why monkey-patching local variables via `sys._getframe()` does not work reliably in CPython.

Misconception 2: "Every Python object creates a frame."
Reality: Frames are created only for function calls and module-level execution. Attribute lookups, list comprehensions (they have their own frame in Python 3, but not in 2), lambda calls, and generator expressions all create frames, but simple expressions, assignments, and method calls on objects do not create frames unless they involve a Python function call. The C implementation of a built-in function like `len()` does not create a Python frame  -  it calls the C function directly, which is why built-in functions do not appear in Python tracebacks.

---

## Why It Matters in Practice

Debuggers, profilers, and tracing tools all operate on frames. `pdb` inspects `f_locals`, `f_globals`, and `f_code.co_filename` to show the current execution context. `cProfile` hooks into frame creation and destruction to measure per-function time. `sys.settrace()` and `sys.setprofile()` install callbacks that are called on frame events (call, return, exception). Understanding the frame object is understanding the hook points that all Python debugging and profiling infrastructure uses.

The cost of function calls in CPython is primarily the cost of frame allocation. Every `def` call creates a frame; every return destroys it. In CPython 3.11+, this cost dropped significantly due to stack-allocated frames. For extremely performance-sensitive inner loops, minimizing function call overhead  -  inlining logic, using built-in functions (which don't create Python frames), or moving hot loops to C extensions  -  is the most effective optimization.

---

## Interview Angle

Common question forms:
- "What is a Python frame object?"
- "How does Python implement the call stack?"
- "What happens to a generator's frame when it yields?"

Answer frame: A frame object is the runtime context for a single function call  -  it holds the code object, local variable array, value stack, and a pointer to the caller's frame. The chain of `f_back` pointers forms the call stack. The interpreter loop reads bytecode from the frame's code object and operates on the frame's value stack and locals. Generator frames are suspended (detached from the thread stack) on yield and resumed on `next()`. CPython 3.11+ allocates frames on a C stack rather than the heap for speed.

---

## Related Notes

- [[interpreter-loop|The Interpreter Loop]]
- [[call-stack|The Call Stack]]
- [[generators|Generators]]
- [[bytecode|Bytecode]]
