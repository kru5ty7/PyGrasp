---
title: Bytecode
description: Bytecode is the intermediate language CPython compiles your source code into before running it — closer to machine instructions than Python, but still requiring CPython to execute.
tags: [bytecode, cpython, compilation, dis, PyCodeObject, core]
status: draft
difficulty: intermediate
layer: 0
domain: core
created: 2026-05-17
---

# Bytecode

> Bytecode is the intermediate language CPython compiles your source code into before running it — closer to machine instructions than Python, but still requiring CPython to execute.

---

## Quick Reference

**Core idea:**
- Bytecode = instruction set for CPython's virtual machine — **not native machine code**
- Stored in `PyCodeObject` (accessible as `fn.__code__`); key fields: `co_code`, `co_consts`, `co_varnames`, `co_names`, `co_argcount`
- Each instruction = **2 bytes** (1 opcode + 1 argument); `EXTENDED_ARG` for larger arguments
- Stack-based VM: `LOAD_FAST` pushes a value; `BINARY_OP` pops two, pushes the result
- Inspect with `import dis; dis.dis(fn)` — shows opcode names, offsets, and arguments
- CPython 3.11+: **adaptive specialization** — hot opcodes silently replaced with faster type-specific variants

**Tricky points:**
- Fewer bytecode instructions **≠ faster** — `CALL` costs far more than `LOAD_FAST`; measure, don't count
- Same `.pyc` runs on any OS with compatible CPython — bytecode is **portable**, machine code is not
- List comprehension faster than `for` + `.append()` because `LIST_APPEND` works at C level — no Python-level attribute lookup
- `x is None` faster than `x == None` — `IS_OP` is a pointer compare; `COMPARE_OP` dispatches through `__eq__`

---

## What It Is

Imagine a conductor working with a full orchestra. The composer writes a score — expressive, readable, full of musical notation. But the conductor does not hand the score directly to the first violin and say "play this." They prepare a simplified part sheet for each musician: just the notes they need, in the order they need to play them, with little extra context. The orchestra reads the part sheets; the score is for the conductor's understanding. Python bytecode is CPython's part sheet. Your source code is the full score — readable, expressive, but not what CPython actually works with when it runs your program.

Bytecode is a sequence of instructions designed specifically for CPython's internal virtual machine. Each instruction is simple and has a name like `LOAD_FAST`, `BINARY_OP`, `CALL`, or `RETURN_VALUE`. These names describe operations on a stack — a small workspace where values are pushed, operated on, and popped. A Python expression like `x + 1` becomes multiple bytecode instructions: one to load the value of `x` onto the stack, one to load the constant `1`, and one to perform the addition. The result ends up back on the stack, ready for whatever instruction comes next.

You can inspect bytecode directly in Python using the `dis` module — short for "disassembler." Running `import dis; dis.dis(my_function)` prints a human-readable version of the bytecode for that function. The output shows each instruction's offset in bytes, its name, and any argument it takes. Reading `dis` output is one of the most direct ways to understand what Python is actually doing when it runs your code, and it is a skill that pays off when you want to understand performance differences between two equivalent-looking pieces of code.

---

## How It Actually Works

CPython stores bytecode inside a `PyCodeObject`. This is a Python object — you can access it as `my_function.__code__`. The code object holds not just the raw bytecode instructions (in `co_code` in older CPython versions, or `co_code`/`co_linetable` in newer ones) but also everything the evaluator needs to run them: the tuple of constants used in the function (`co_consts`), the names of local variables (`co_varnames`), the names of global names referenced (`co_names`), the number of arguments (`co_argcount`), and the source file and line number mappings for tracebacks.

Each bytecode instruction occupies two bytes in the raw instruction stream: one byte for the opcode (which operation) and one byte for the argument (a small integer whose meaning depends on the opcode). For opcodes that need a larger argument, CPython prepends `EXTENDED_ARG` instructions to build up the value before the actual instruction. This fixed two-byte encoding is why CPython can advance through bytecode cheaply — it always knows where the next instruction starts.

The evaluator in `Python/ceval.c` uses the opcode as an index into a dispatch mechanism. In CPython 3.11 and later, this is an adaptive interpreter — the evaluator can specialize certain instructions based on the types it actually observes at runtime. For example, if `BINARY_OP` is called repeatedly with two integers, CPython can replace it with a faster `BINARY_OP_ADD_INT` variant that skips the type dispatch. This specialization happens automatically and silently. It is one of the ways modern CPython partially closes the performance gap with statically typed languages without requiring any changes to your code.

---

## How It Connects

Bytecode is produced by the compilation stage and consumed by the evaluation stage. The evaluation stage is the interpreter loop — the C function that fetches each bytecode instruction and executes it. Understanding the loop explains why certain bytecodes are cheap, why function calls have overhead, and how the execution stack behaves.
[[interpreter-loop|The Interpreter Loop]]

Bytecode instructions operate on Python objects. When `LOAD_FAST` pushes a value onto the evaluation stack, it is pushing a pointer to a Python object. When `BINARY_OP` runs, it calls the relevant method on those objects. The fact that every value is a Python object — with a type, a reference count, and a memory layout — shapes what every bytecode instruction actually does at the C level.
[[everything-is-an-object|Everything is an Object]]

---

## Common Misconceptions

Misconception 1: "Bytecode is platform-specific machine code."
Reality: Python bytecode is not native machine code and cannot run directly on a CPU. It is an instruction set designed for CPython's own virtual machine. The same `.pyc` file runs on any operating system with a compatible CPython version — precisely because it is not machine code. Tools like Cython, PyPy, or Nuitka can produce native code from Python, but that is a separate step not involved in standard CPython execution.

Misconception 2: "Optimizing Python means writing code that generates less bytecode."
Reality: Fewer bytecode instructions does not reliably mean faster execution. Some bytecode instructions are extremely cheap; others (like function calls, attribute lookups, or operations on arbitrary objects) are expensive regardless of instruction count. Meaningful Python optimization requires understanding which operations are slow at the C level, not just minimizing instruction count. The `dis` module shows you what instructions are generated; profiling tools show you which ones cost time.

---

## Why It Matters in Practice

Reading bytecode output from `dis` turns intuition into evidence. When you wonder why a list comprehension is faster than an equivalent `for` loop with `.append()`, `dis` shows you the difference: the comprehension uses a dedicated `LIST_APPEND` opcode that operates at the C level without the overhead of a Python-level attribute lookup on the list. When you wonder why `x is None` is faster than `x == None`, the bytecode shows you that `IS_OP` is a pointer comparison while `COMPARE_OP` dispatches through the object's `__eq__` method.

Bytecode is also stable enough to be relied on in tooling. Linters, type checkers, and code coverage tools all work at the bytecode level or the AST level rather than at the source text level. Understanding what bytecode is helps you understand what those tools are actually measuring and why they sometimes report surprising results.

---

## Interview Angle

Common question forms:
- "What is Python bytecode?"
- "What does the `dis` module do and when would you use it?"
- "Why is Python slower than C if it compiles to bytecode first?"

Answer frame: Define bytecode as an intermediate instruction set for CPython's virtual machine, not native machine code. Explain that it lives in `PyCodeObject` and is what the interpreter loop actually processes. Mention `dis` as the tool for inspecting it. Address the speed question by noting that each bytecode instruction executes through a C function dispatch with full Python object overhead — there is no static type information to eliminate that overhead, unlike in a C compiler.

---

## Related Notes

- [[source-to-execution|From Source Code to Execution]]
- [[interpreter-loop|The Interpreter Loop]]
- [[everything-is-an-object|Everything is an Object]]
