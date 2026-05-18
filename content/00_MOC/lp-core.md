---
title: Learning Path  -  Core Python
description: Ground-up reading path through how CPython runs Python code and the language features built on top of that runtime.
tags: [moc, learning-path, core, layer-0, layer-1]
---

# Learning Path  -  Core Python

> How Python actually runs, from source file to executed bytecode, and the language features that make Python Python. Read in order  -  each note assumes the ones before it.

---

## Layer 0  -  How Python Runs

1. [[what-is-python|What is Python]]
2. [[compiled-vs-interpreted|Compiled vs Interpreted Languages]]
3. [[cpython|CPython]]
4. [[other-python-implementations|Other Python Implementations]]
5. [[source-to-execution|From Source Code to Execution]]
6. [[tokenization|Tokenization]]
7. [[parsing-and-ast|Parsing and the AST]]
8. [[bytecode|Bytecode]]
9. [[pyc-files|.pyc Files and __pycache__]]
10. [[interpreter-loop|The Interpreter Loop]]
11. [[frame-object|The Frame Object]]
12. [[call-stack|The Call Stack]]
13. [[stack-vs-heap|Stack vs Heap]]
14. [[everything-is-an-object|Everything is an Object]]
15. [[object-header|Python Object Header]]
16. [[id-and-memory-address|id() and Memory Addresses]]
17. [[python-memory-model|Python's Memory Model]]
18. [[reference-counting|Reference Counting]]
19. [[cyclic-references|Cyclic References]]
20. [[garbage-collection|Garbage Collection]]
21. [[memory-allocator|Python's Memory Allocator]]
22. [[interning|Object Interning]]
23. [[small-integer-cache|Small Integer Cache]]
24. [[mutability|Mutability vs Immutability]]
25. [[copy-vs-deepcopy|Shallow Copy vs Deep Copy]]

---

## Layer 1a  -  The Object System

1. [[python-data-model|The Python Data Model]]
2. [[dunder-methods|Dunder Methods]]
3. [[type-and-object|type and object]]
4. [[metaclasses|Metaclasses]]
5. [[class-creation|How Classes Are Created]]
6. [[mro|Method Resolution Order (MRO)]]
7. [[multiple-inheritance|Multiple Inheritance]]
8. [[abstract-base-classes|Abstract Base Classes]]
9. [[protocols|Protocols and Structural Subtyping]]
10. [[descriptors|Descriptors]]
11. [[properties|Properties]]
12. [[slots|__slots__]]
13. [[classmethod-staticmethod|classmethod vs staticmethod]]
14. [[dataclasses|Dataclasses]]
15. [[enums|Enums]]
16. [[namedtuples|Named Tuples]]

---

## Layer 1b  -  Scopes and Functions

1. [[namespaces-and-scopes|Namespaces and Scopes]]
2. [[legb-rule|The LEGB Rule]]
3. [[closures|Closures]]
4. [[free-variables|Free Variables]]
5. [[first-class-functions|First Class Functions]]
6. [[higher-order-functions|Higher Order Functions]]
7. [[lambda|Lambda Functions]]
8. [[decorators|Decorators]]
9. [[decorator-with-arguments|Decorators with Arguments]]
10. [[functools|functools Module]]
11. [[partial-functions|Partial Functions]]
12. [[args-and-kwargs|*args and **kwargs]]

---

## Layer 1c  -  Iterators and Generators

1. [[iterators|Iterators and Iterables]]
2. [[for-loop-internals|How For Loops Work Internally]]
3. [[generators|Generators]]
4. [[generator-expressions|Generator Expressions]]
5. [[yield-from|yield from]]
6. [[list-comprehensions|List Comprehensions]]
7. [[lazy-evaluation|Lazy Evaluation]]
8. [[itertools|itertools Module]]

---

## Layer 1d  -  Types and Typing

1. [[type-hints|Type Hints]]
2. [[typing-module|The typing Module]]
3. [[generic-types|Generic Types]]
4. [[type-narrowing|Type Narrowing]]
5. [[runtime-vs-static-typing|Runtime vs Static Typing]]
6. [[mypy|Mypy]]
7. [[pyright|Pyright]]
8. [[type-guards|Type Guards]]

---

## Layer 1e  -  Error Handling and Context

1. [[exceptions|Exceptions]]
2. [[exception-hierarchy|Exception Hierarchy]]
3. [[custom-exceptions|Custom Exceptions]]
4. [[exception-chaining|Exception Chaining]]
5. [[context-managers|Context Managers]]
6. [[contextlib|contextlib]]
7. [[logging|Logging]]

---

## Layer 1f  -  Modules and Packages

1. [[modules|Modules]]
2. [[packages|Packages]]
3. [[import-system|The Import System]]
4. [[sys-path|sys.path]]
5. [[relative-imports|Relative Imports]]
6. [[virtual-environments|Virtual Environments]]
7. [[pip-and-packaging|pip and Packaging]]
8. [[pyproject-toml|pyproject.toml]]

---

## Layer 1g  -  Built-in Data Structures

1. [[lists|Lists]]
2. [[tuples|Tuples]]
3. [[dicts|Dictionaries]]
4. [[sets|Sets]]
5. [[strings|Strings]]
6. [[bytes-and-bytearray|Bytes and Bytearray]]
7. [[collections-module|collections Module]]
8. [[dict-internals|How Python Dicts Work Internally]]
