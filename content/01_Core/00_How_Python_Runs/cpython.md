---
title: 03 - CPython
description: CPython is the reference implementation of Python  -  the program that actually reads your code, compiles it to bytecode, and runs it. Understanding CPython means understanding what Python actually does at runtime.
tags: [cpython, interpreter, implementation, runtime, core]
status: draft
difficulty: intermediate
layer: 0
domain: core
created: 2026-05-17
---

# CPython

> CPython is the reference implementation of Python  -  the program that actually reads your code, compiles it to bytecode, and runs it. Understanding CPython means understanding what Python actually does at runtime.

---

## Quick Reference

**Core idea:**
- CPython is a **C program**  -  its source is at `github.com/python/cpython`
- Pipeline: source -> lexer (tokens) -> parser (AST) -> compiler (`PyCodeObject`) -> ceval loop (execution)
- The ceval loop (`_PyEval_EvalFrameDefault`) runs for the **entire lifetime** of your program
- CPython manages all memory via reference counting; the GIL exists to protect that from race conditions
- CPython's behavior is the **official answer** when the Python spec is ambiguous  -  it is the reference

**Tricky points:**
- CPython compiles to **bytecode, not machine code**  -  `.pyc` files still need CPython to run
- All Python "quirks" (small integer caching, `is` behavior, atomic ops) are **CPython implementation decisions**, not language rules
- "CPython is Python"  -  wrong; it is one implementation of the Python language specification
- Performance advice about Python (globals are slow, list comprehensions are fast) is always really **CPython** performance advice

---

## What It Is

Imagine a translator who does not just convert words but actually carries out every instruction they translate. You hand them a set of directions written in English, and instead of producing a French version for someone else to follow, they read each line and immediately do the thing it describes. CPython works like that translator. You write code in Python; CPython reads it, converts it into a form it can work with more efficiently, and then executes it step by step.

CPython is a program written in C. It is the software you download when you go to python.org and click "Download Python." It is the thing that runs when you type `python` in a terminal. The name combines "C" (the language it is written in) and "Python" (the language it implements). It is called the reference implementation because when there is any ambiguity about what Python code should do, CPython's behavior is the official answer. Other implementations are considered correct when they match CPython's behavior on the same code.

CPython is also open source. Its source code lives at github.com/python/cpython. You can read the C code that implements every built-in function, every data structure, and every part of the runtime. This matters for this vault because many of the explanations in later notes refer to what CPython's source code actually does  -  not just what Python's documentation says it does.

---

## How It Actually Works

CPython is structured as a pipeline. Your source code enters at one end and execution happens at the other end, with several transformation stages in between. The first stage is the lexer, which breaks your source text into tokens  -  the smallest meaningful units like keywords, variable names, operators, and literals. The second stage is the parser, which assembles those tokens into an Abstract Syntax Tree (AST)  -  a tree structure that represents the grammatical structure of your program. The third stage is the compiler, which walks the AST and emits bytecode instructions. The fourth stage is the evaluator  -  the part CPython calls the ceval loop  -  which executes those bytecode instructions one at a time.

The ceval loop (short for "C evaluation loop") is the heart of CPython. It is a giant C switch statement inside a function called `_PyEval_EvalFrameDefault`. Each iteration of the loop fetches the next bytecode instruction, dispatches to the appropriate case in the switch, executes the logic for that instruction, and then fetches the next one. This is the loop that runs for the entire lifetime of your Python program. Every function call, every assignment, every arithmetic operation passes through this loop. Its performance characteristics are why Python programs run at the speed they do: executing bytecode through a C switch statement in a virtual machine is inherently slower than native machine code, but it gives CPython tremendous flexibility and portability.

CPython also manages all memory for Python objects directly. It allocates memory when objects are created, tracks how many references point to each object, and frees memory when objects are no longer needed. This memory management system is tightly coupled with the Global Interpreter Lock, which exists to make that reference tracking safe in a multi-threaded environment.

---

## How It Connects

Before CPython can execute anything, it must compile your source code into a format the ceval loop can process. That format is bytecode  -  a sequence of low-level instructions that map closely to what the ceval loop knows how to do. Understanding bytecode means understanding what CPython is actually working with at runtime.
[[bytecode|Bytecode]]

The ceval loop processes one bytecode instruction per iteration. To understand the loop's performance implications and its role as the central execution engine, you need to understand the interpreter loop itself  -  what it fetches, what it dispatches, and what happens when a function is called.
[[interpreter-loop|The Interpreter Loop]]

CPython treats every value your program works with  -  integers, strings, functions, classes  -  as an object in memory. This is not just a design choice; it is an architectural constraint that affects how memory is allocated, how comparisons work, and why certain operations behave unexpectedly.
[[everything-is-an-object|Everything is an Object]]

CPython uses a specific strategy to decide when memory held by an object can be safely freed. That strategy is reference counting, and it is so deeply embedded in CPython's design that the Global Interpreter Lock exists largely to protect it.
[[reference-counting|Reference Counting]]

---

## Common Misconceptions

Misconception 1: "CPython and Python are the same thing."
Reality: Python is a language specification  -  a set of rules for what code means. CPython is one program that implements those rules. You can run Python code on PyPy, Jython, or MicroPython and it is still Python, but CPython is not involved. Conflating the two leads to statements like "Python has a GIL" when the accurate statement is "CPython has a GIL." The language spec does not mandate one.

Misconception 2: "CPython compiles Python to machine code."
Reality: CPython compiles Python source to bytecode, not to native machine code. Bytecode is an intermediate representation designed for CPython's own virtual machine  -  the ceval loop. It cannot run directly on a CPU. Tools like Cython, Nuitka, or PyPy's JIT compiler can produce machine code from Python, but that is not what standard CPython does.

---

## Why It Matters in Practice

Almost every behavior that Python developers describe as a "Python quirk" is actually a CPython behavior. The reason modifying a list while iterating over it causes problems, the reason certain operations are atomic and others are not, the reason `is` and `==` behave differently for small integers  -  these all trace back to specific decisions in CPython's implementation. When you understand that CPython is a C program with a specific architecture, these behaviors stop feeling like arbitrary rules and start making sense as engineering trade-offs.

Knowing CPython's structure also makes you a better reader of performance advice. When someone says "avoid global variables in Python because they are slower," they are describing a specific lookup path through CPython's namespace system, not a general truth about programming. When someone says "list comprehensions are faster than for loops," they are describing bytecode differences in CPython. Every piece of Python performance guidance is really CPython performance guidance.

---

## Interview Angle

Common question forms:
- "What is CPython? How does it differ from Python?"
- "Walk me through what happens when you run a Python script."
- "What is the GIL and why does CPython have it?"

Answer frame: Start by distinguishing CPython (a C program, the reference implementation) from Python (the language specification). Describe the pipeline: source -> tokens -> AST -> bytecode -> ceval loop execution. Mention that CPython manages memory via reference counting and that the GIL exists to protect that system. Show that you understand CPython's behaviors are implementation decisions, not language requirements.

---

## Related Notes

- [[what-is-python|What is Python]]
- [[bytecode|Bytecode]]
- [[interpreter-loop|The Interpreter Loop]]
- [[everything-is-an-object|Everything is an Object]]
- [[reference-counting|Reference Counting]]
