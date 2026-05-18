---
title: 01 - What is Python
description: Python is both a language specification and a runtime  -  knowing the difference is what separates "I write Python" from "I understand Python."
tags: [python, fundamentals, interpreter, cpython, language]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# What is Python

> Python is both a language specification and a runtime  -  knowing the difference is what separates "I write Python" from "I understand Python."

---

## Quick Reference

**Core idea:**
- Python = language **specification** (the rules) + **implementation** (the program that runs those rules)
- CPython is the reference implementation  -  the one from python.org; other implementations exist (PyPy, Jython, MicroPython)
- CPython pipeline: source -> bytecode -> virtual machine execution (not direct interpretation)
- "Python is slow" and "Python has a GIL" are statements about **CPython**, not the Python language spec

**Tricky points:**
- "Is Python interpreted?"  -  incomplete answer; CPython **compiles to bytecode first**, then the VM interprets that bytecode
- The GIL belongs to CPython, not Python  -  PyPy handles it differently; CPython 3.13 makes it optional
- `.pyc` files are CPython's **compile cache**  -  not OS-executable binaries; they still need CPython to run
- Saying "Python can't do X" when you mean "CPython's design makes X hard" leads to wrong conclusions

---

## What It Is

Think of Python as two separate things that most developers treat as one. The first is a recipe book: a set of rules that defines what valid Python code looks like and what it means. The second is the kitchen: the actual machinery that reads those rules and carries them out. When most people say "Python," they mean both at once. Understanding why they are separate is the foundation of everything else in this vault.

The recipe book is called the Python language specification. It says things like "an if statement works this way," "a list comprehension means this," and "dividing two integers produces this result." The specification does not care how these rules are carried out. It only defines what the rules are. You could build a completely different kitchen that follows the same recipe book and it would still be valid Python.

The kitchen  -  the software that actually reads and runs your code  -  is called an implementation. The most widely used implementation is CPython, the one you get when you visit python.org. But others exist: PyPy compiles Python to machine code for speed, Jython runs Python on the Java Virtual Machine, and MicroPython runs on microcontrollers. Each of these follows the same recipe book but builds the kitchen differently. When this vault talks about how Python works internally, it means CPython specifically, because that is what almost every production system uses.

---

## How It Actually Works

When you run a Python file, CPython does not read your source code line by line and execute it directly. That would be too slow and too fragile. Instead, it works in stages. First it reads your `.py` file and checks that the syntax is valid. Then it compiles that source into a lower-level representation called bytecode  -  a sequence of compact instructions designed for a virtual machine, not a physical processor. Finally, the CPython virtual machine reads those bytecode instructions one by one and carries them out.

This compilation step is why `.pyc` files appear in a `__pycache__` folder next to your source files. CPython caches compiled bytecode so it does not recompile unchanged files on every run. This is not the same as compiling C to a binary  -  the bytecode still needs CPython to execute it. It cannot run directly on your CPU. That distinction matters because it explains both Python's portability (the same bytecode runs on any machine with CPython installed) and its performance profile (there is always a layer of interpretation between your code and the hardware, and that layer has costs).

---

## How It Connects

Python's actual runtime behavior  -  its speed, its memory use, its concurrency model  -  all come from the implementation, not the language specification. To understand why Python programs behave the way they do, you need to understand CPython: what it is, how it is structured, and why it was designed the way it was. CPython is the kitchen; everything else in this vault is a closer look at how that kitchen works.
[[cpython|CPython]]

CPython does not run your source code directly. It compiles it to an intermediate form first. That intermediate form has its own structure and rules, and understanding it reveals a lot about what Python can and cannot do efficiently.
[[bytecode|Bytecode]]

---

## Common Misconceptions

Misconception 1: "Python is slow because it's interpreted."
Reality: Python is not purely interpreted  -  CPython compiles source code to bytecode before running it. The performance cost comes from executing that bytecode in a virtual machine rather than running native machine code directly, and from the overhead of CPython's dynamic type system and runtime checks. Calling it "interpreted" is an oversimplification that points you toward the wrong mental model for diagnosing performance issues.

Misconception 2: "Python is Python  -  there's only one."
Reality: Python is a language specification, and multiple independent implementations exist. CPython is the reference implementation and by far the most common, but PyPy, Jython, and MicroPython all run valid Python code. When someone says "Python has a GIL" or "Python can't use multiple cores," they are describing CPython specifically, not the Python language specification. PyPy's GIL situation is different, and future CPython versions are actively changing this behavior.

---

## Why It Matters in Practice

Most Python developers write code without ever thinking about the gap between the language and the runtime. That works until it doesn't. When you hit a performance wall, knowing whether the bottleneck is in your algorithm, in CPython's virtual machine, or in something like the GIL is the difference between a fix that works and a week of misdiagnosis. When you read that "Python 3.13 removes the GIL," knowing that this is a CPython change  -  not a language change  -  tells you exactly what will and will not change about your code's behavior.

Understanding Python as a two-part system is also what makes it possible to reason about edge cases and implementation differences. Two implementations can agree on what a piece of code does while differing in how fast it runs, how much memory it uses, or whether it can take advantage of multiple CPU cores. Those differences are not bugs in one or the other. They are the natural result of different kitchens following the same recipe book.

---

## Interview Angle

Common question forms:
- "Is Python interpreted or compiled?"
- "What is CPython and how does it differ from Python the language?"
- "Why is Python slower than C or Java?"

Answer frame: Open by separating the language specification from the implementation. State that CPython compiles source code to bytecode before running it  -  so "purely interpreted" is not accurate. Explain that performance characteristics like speed and the GIL belong to CPython, not to the Python spec itself. Close by noting that other implementations exist with different trade-offs, which shows you understand the distinction concretely.

---

## Related Notes

- [[cpython|CPython]]
- [[bytecode|Bytecode]]
