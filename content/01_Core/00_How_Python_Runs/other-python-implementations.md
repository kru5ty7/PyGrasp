---
title: 04 - Other Python Implementations
description: CPython is the reference implementation of Python, but PyPy, Jython, MicroPython, and GraalPy are alternative implementations that run the same Python language on different runtimes or with different performance characteristics.
tags: [pypy, jython, micropython, graalpy, cpython, implementations, layer-0, core]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# Other Python Implementations

> CPython is the reference implementation of Python, but PyPy, Jython, MicroPython, and GraalPy are alternative implementations that run the same Python language on different runtimes or with different performance characteristics.

---

## Quick Reference

**Core idea:**
- **CPython** is the default Python  -  the reference implementation written in C, what you get from python.org
- **PyPy** is a Python interpreter with a JIT compiler  -  runs the same code 5 - 10× faster for CPU-bound workloads by compiling hot bytecode to machine code at runtime
- **Jython** compiles Python to JVM bytecode, enabling Python code to call Java libraries and run on the JVM
- **MicroPython** is a lean CPython subset for microcontrollers (ESP32, Raspberry Pi Pico)  -  runs on hardware with kilobytes of RAM
- **GraalPy** (formerly GraalVM Python) runs Python on the GraalVM, enabling polyglot programs that mix Python, JavaScript, Ruby, and Java

**Tricky points:**
- PyPy is **not always faster**  -  the JIT has warmup time; short-lived scripts or I/O-bound code see little benefit; C extension-heavy code (NumPy) may be slower
- PyPy **does not fully support all CPython C extensions**  -  `pip install numpy` works on CPython; on PyPy it requires a compatibility layer and not all versions are supported
- Jython is **frozen at Python 2.7** (as of 2024)  -  it has not tracked CPython's evolution and is rarely used for new projects
- MicroPython uses a **subset of the standard library**  -  many CPython modules are absent or have reduced APIs
- All these implementations run **the same Python language**  -  they differ in the runtime, not the language spec

---

## What It Is

Think of the English language as Python. When we say "English," we mean a shared set of grammar rules and vocabulary. But English can be spoken with a British accent, an American accent, or a Scottish accent  -  the same language, different implementations of the sound system. CPython is the reference accent: the one that defines what "correct" sounds like. PyPy is an accent that uses different vocal techniques (JIT compilation) to speak much faster. Jython is English spoken by someone whose native tongue is Java  -  they translate each sentence into Japanese Java internally. MicroPython is English on a strict vocabulary budget  -  the same grammar but far fewer words available.

Every Python implementation runs Python source code and must conform to the Python language specification. The language specification defines what `for x in [1,2,3]: print(x)` should do. All implementations agree on that. Where they differ is in how they execute it: which runtime they use, how they handle memory, how they optimize execution, and which standard library modules they provide. From the Python language's perspective, they are all "Python." From a deployment perspective, they have very different characteristics.

The existence of multiple implementations reflects a tension between the Python language (a specification) and CPython (an implementation). CPython is both the reference implementation and the engine of 99% of production Python. Its C extension interface (`CPython C API`) is so widely used that many popular libraries (NumPy, pandas, cryptography) compile C extensions that only work with CPython. This C extension ecosystem is a significant practical lock-in that has limited adoption of PyPy and other alternatives despite their technical merits.

---

## How It Actually Works

PyPy runs Python code through a tracing JIT compiler. It begins by interpreting Python bytecode normally and tracks which code paths are executed most frequently ("hot paths"). When a loop body or function is identified as hot, the JIT records the types and values observed and compiles that specific sequence to native machine code. Future executions of that hot path run the compiled code directly, bypassing the interpreter overhead entirely. This is why PyPy is fast for CPU-bound loops but offers little benefit for short-running scripts  -  the JIT has no time to warm up and produce compiled code.

Jython compiles Python source directly to JVM `.class` files, following the same compilation pipeline as Java. Python classes become JVM classes; Python functions become JVM methods. This means Python code running on Jython can import and call Java libraries directly with no FFI overhead  -  the two are running on the same JVM with compatible object models. The tradeoff is that Jython must track CPython's evolution independently, which is why it has fallen behind.

MicroPython replaces CPython's heap allocator, garbage collector, and standard library with versions designed for systems with 256 KB of flash storage and 64 KB of RAM. It compiles Python source to a compact bytecode format and interprets it on the device's CPU directly. The compiler and interpreter are implemented in C and fit in the flash memory of a microcontroller. Many CPython idioms work identically; what is missing is most of the standard library, especially networking, file system, and OS modules  -  replaced by hardware-specific alternatives.

---

## How It Connects

CPython is the baseline that all other implementations are measured against. Understanding CPython's architecture  -  its bytecode format, its object model, its C extension interface  -  explains why alternative implementations face the compatibility challenges they do.
[[cpython|CPython]]

The compiled-vs-interpreted spectrum helps explain where each implementation sits. PyPy moves Python toward the compiled end with JIT. Jython puts Python on the JVM, a managed runtime. MicroPython keeps the interpreted model but minimizes everything for embedded use.
[[compiled-vs-interpreted|Compiled vs Interpreted Languages]]

---

## Common Misconceptions

Misconception 1: "PyPy is a drop-in replacement for CPython."
Reality: PyPy runs most pure-Python code correctly and faster. But C extensions compiled for CPython (most scientific Python libraries  -  NumPy, SciPy, pandas) do not work natively in PyPy. PyPy provides a CPyExt compatibility layer, but coverage is incomplete. For applications that heavily use NumPy or other C extension libraries, switching to PyPy often breaks dependencies and the compatibility layer adds overhead that erases the JIT speedup. PyPy is best suited for pure-Python CPU-intensive workloads.

Misconception 2: "Using a different Python implementation changes the language."
Reality: All compliant Python implementations run the same Python language  -  the same syntax, semantics, and standard behavior. A Python script that avoids CPython-specific internals and CPython-only C extension libraries will run correctly on PyPy, MicroPython (if it stays within the supported subset), and Jython. What differs is the runtime environment: performance characteristics, available libraries, threading behavior (MicroPython has no GIL and no threading; PyPy has its own GIL implementation), and available standard library modules.

---

## Why It Matters in Practice

The choice of Python implementation matters most in two scenarios: performance-critical pure-Python code and resource-constrained embedded systems. For a CPU-intensive simulation written in pure Python, PyPy can provide a 5 - 20× speedup with zero code changes. For deploying Python on an ESP32 microcontroller, MicroPython is the only viable option. For all other production Python  -  web APIs, data pipelines, machine learning, scripting  -  CPython with well-chosen libraries is the right default.

GraalPy deserves attention for polyglot applications: systems that need to mix Python data processing with Java services or JavaScript logic in a single runtime. It is used in Oracle's database for server-side Python scripting within SQL queries. For most Python developers it is irrelevant, but it demonstrates that Python's language specification is portable enough to run on radically different runtimes.

---

## Interview Angle

Common question forms:
- "What is the difference between CPython and PyPy?"
- "Why might you use PyPy instead of CPython?"

Answer frame: CPython is the reference implementation  -  C-based interpreter, the python.org default. PyPy adds a JIT compiler that compiles hot bytecode to native machine code, achieving 5 - 10× speedup for CPU-bound pure-Python code. Limitation: PyPy does not fully support CPython C extensions (NumPy, pandas). Other implementations: Jython (Python on JVM, frozen at 2.7), MicroPython (embedded systems, tiny resource footprint), GraalPy (polyglot JVM). Key distinction: all run the same Python language; they differ in runtime, performance, and library compatibility.

---

## Related Notes

- [[cpython|CPython]]
- [[compiled-vs-interpreted|Compiled vs Interpreted Languages]]
- [[bytecode|Bytecode]]
