---
title: 02 - Compiled vs Interpreted Languages
description: Compiled languages translate source code to machine code before execution; interpreted languages translate and execute source code at runtime — Python sits between both models, compiling to bytecode which is then interpreted by the CPython virtual machine.
tags: [compiled, interpreted, bytecode, cpython, execution, layer-0, core]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# Compiled vs Interpreted Languages

> Compiled languages translate source code to machine code before execution; interpreted languages translate and execute source code at runtime — Python sits between both models, compiling to bytecode which is then interpreted by the CPython virtual machine.

---

## Quick Reference

**Core idea:**
- **Compiled**: source → machine code (once, ahead of time) → run directly on CPU (C, Rust, Go)
- **Interpreted**: source → executed line by line at runtime by another program (the interpreter)
- Python **compiles to bytecode** (`.pyc` files), then the CPython interpreter executes that bytecode — it is neither purely compiled nor purely interpreted
- The compilation step in Python happens automatically and is hidden from the developer; the bytecode step is what makes Python slower than C but faster to iterate on
- **JIT-compiled** languages (Java, PyPy) compile bytecode to native machine code at runtime — Python/CPython does not do this by default

**Tricky points:**
- "Python is interpreted" is a common simplification — Python always compiles to bytecode first; the bytecode is what is interpreted
- **PyPy** is a Python implementation with a JIT compiler — it runs the same Python code significantly faster than CPython by compiling hot bytecode paths to machine code
- Compilation in CPython is not optional — it always happens, even for a one-line script, though it may not write to disk if the source is a REPL input
- The terms describe the **primary execution model**, not a strict binary — most languages have hybrid characteristics

---

## What It Is

Think of translating a novel from French to English. One approach: hire a translator to produce a complete English-language book before any reader touches it. The readers then read the English book directly — fast, with no translation overhead per page. This is compilation. A second approach: hire a simultaneous interpreter who reads each French sentence and speaks the English translation aloud as readers listen — no upfront cost, but the interpreter's overhead is present for every sentence. This is interpretation. A third approach: first produce a simplified intermediate version of the novel — something not quite French or English but easier to interpret quickly — and then have the interpreter work from that intermediate form. This is what Python does.

Compiled languages like C and Rust translate the entire source code to machine instructions — the binary opcodes that the CPU understands directly — before the program is ever run. This translation is done once by the compiler. The resulting executable contains no source code; it is pure machine language. Running it involves no translation overhead. The CPU executes the instructions directly. The tradeoff is build time: every change requires recompiling.

Interpreted languages like early Ruby or basic shell scripts have an interpreter read and execute source code line by line at runtime. There is no separate compilation step. This enables interactive execution, faster development cycles, and immediate error feedback. The tradeoff is execution speed: every line must be parsed and dispatched by the interpreter on every execution, even if the same line runs a million times in a loop.

Python occupies a middle ground. When you run `python script.py`, CPython first compiles the source file to bytecode — a compact, portable instruction format specific to the CPython virtual machine. This bytecode is then executed by the CPython eval loop, which reads one bytecode instruction at a time and dispatches it. The compilation step is automatic and typically invisible, though its output (`.pyc` files in `__pycache__`) persists to disk to avoid recompiling unchanged files.

---

## How It Actually Works

CPython's compilation pipeline converts source code to a code object containing bytecode. The pipeline: source text → tokenizer → parser → abstract syntax tree (AST) → symbol table → bytecode compiler → `PyCodeObject`. Each stage transforms the representation: the tokenizer produces a stream of tokens; the parser builds an AST; the compiler walks the AST and emits bytecode instructions. The result is a `PyCodeObject`, which contains the bytecode as a bytes sequence, the constants used, the names referenced, and metadata about the code (filename, line number mapping).

The bytecode is a sequence of two-byte instructions (in CPython 3.6+, each instruction is a word with an opcode and argument). Instructions like `LOAD_FAST`, `BINARY_ADD`, `CALL_FUNCTION`, and `RETURN_VALUE` are the vocabulary of the CPython virtual machine. This bytecode is not CPU instructions — no CPU understands `LOAD_FAST`. It is instructions for the CPython interpreter, which is a C program that switches on each opcode and executes the corresponding C code.

This two-stage model is why Python's performance profile differs from both C and REPL-style scripting. The compilation stage catches syntax errors before execution and reduces parsing overhead at runtime. But the interpretation stage — the C eval loop dispatching each bytecode instruction — adds overhead that does not exist in compiled languages, where the same sequence is CPU instructions executed directly.

---

## How It Connects

The output of Python's compilation step is bytecode. Understanding what bytecode is — its format, how to inspect it, and what information it encodes — is the direct follow-on to understanding why Python compiles at all.
[[bytecode|Bytecode]]

CPython is the reference implementation that performs both the compilation and interpretation described here. Its specific implementation choices — the C-based eval loop, the bytecode format, the compilation pipeline — are what make Python behave the way it does.
[[cpython|CPython]]

---

## Common Misconceptions

Misconception 1: "Python is slow because it is interpreted."
Reality: Python is slow relative to compiled languages primarily because of the overhead of the CPython eval loop (dispatching each bytecode instruction through C function calls), the GIL, and the cost of Python's dynamic type system (every operation looks up the type of its operands at runtime). The "interpreted" label is imprecise; PyPy, which also interprets Python bytecode but adds a JIT compiler, runs Python 5–10× faster than CPython. The slowness is in CPython's execution model, not in interpretation per se.

Misconception 2: "Compiled languages are always faster than interpreted languages."
Reality: Modern JIT-compiled languages like Java and JavaScript (V8) can match or exceed C for many workloads because the JIT can make runtime optimizations based on observed execution patterns. Conversely, poorly optimized C can be slower than well-optimized JVM bytecode. "Compiled vs interpreted" is a description of the translation model, not a reliable predictor of performance. Performance depends on the specific implementation, the workload, and how much optimization the runtime applies.

---

## Why It Matters in Practice

Understanding Python's two-stage model explains why some errors are caught before the program runs (syntax errors — caught at compile time) and others only surface during execution (NameError, TypeError — runtime errors from the interpreter). It also explains why Python startup time includes a compilation cost for files not yet in `__pycache__`, and why deploying pre-compiled `.pyc` files can modestly speed up import-heavy applications.

The distinction also matters when choosing between CPython and alternative Python runtimes. PyPy's JIT compiler makes CPU-bound Python code dramatically faster — sometimes approaching C speeds — at the cost of longer warmup time and occasional incompatibilities with CPython extensions. Cython compiles Python-like syntax to C extensions, effectively giving Python code compiled-language speed for targeted hot paths.

---

## Interview Angle

Common question forms:
- "Is Python compiled or interpreted?"
- "Why is Python slower than C?"
- "What is the difference between CPython and PyPy?"

Answer frame: Python is compiled to bytecode, then that bytecode is interpreted by the CPython virtual machine — it is a two-stage model. CPython is slow because each bytecode instruction dispatches through a C switch statement, adding overhead absent in native machine code. PyPy adds a JIT that compiles hot paths to machine code. Distinguish syntax errors (compile-time) from runtime errors (interpreter-time).

---

## Related Notes

- [[what-is-python|What is Python]]
- [[cpython|CPython]]
- [[bytecode|Bytecode]]
- [[source-to-execution|From Source Code to Execution]]
