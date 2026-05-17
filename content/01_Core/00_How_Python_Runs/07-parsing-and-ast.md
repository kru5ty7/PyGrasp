---
title: 07 - Parsing and the AST
description: The parser takes Python's token stream and builds an Abstract Syntax Tree — a hierarchical data structure that represents the grammatical structure of the source code and serves as the input to the bytecode compiler.
tags: [parser, ast, abstract-syntax-tree, compilation, cpython, grammar, layer-0, core]
status: draft
difficulty: intermediate
layer: 0
domain: core
created: 2026-05-17
---

# Parsing and the AST

> The parser takes Python's token stream and builds an Abstract Syntax Tree — a hierarchical data structure that represents the grammatical structure of the source code and serves as the input to the bytecode compiler.

---

## Quick Reference

**Core idea:**
- The **parser** reads the token stream from the tokenizer and builds an **AST** (Abstract Syntax Tree) representing the program's grammatical structure
- Python's `ast` module provides the AST node types and functions: `ast.parse(source)` returns the root node; `ast.dump(tree)` shows the structure
- AST nodes represent grammatical constructs: `Module`, `FunctionDef`, `ClassDef`, `If`, `For`, `BinOp`, `Call`, `Name`, `Constant`
- The AST is **abstract** — it omits tokens that carry no semantic information (parentheses, commas, colons, INDENT/DEDENT); only semantic structure is preserved
- **AST transformations** using `ast.NodeTransformer` enable compile-time code modification — the foundation of tools like `pytest`'s assertion rewriting and `numba`'s JIT

**Tricky points:**
- `ast.parse()` produces the AST but does **not** check semantic correctness — `ast.parse("x = undefined_var")` succeeds; `NameError` is a runtime error, not a parse error
- CPython 3.9+ uses a **PEG parser** (replacing the older LL(1) parser) — more expressive grammar, better error messages, slightly different AST for some edge cases
- AST nodes have **line number and column offset** attributes (`lineno`, `col_offset`) — this is how error messages and debuggers identify source locations
- `compile(ast_tree, filename, mode)` compiles an AST to a code object, enabling programmatic code generation and transformation pipelines
- `ast.fix_missing_locations(tree)` fills in missing `lineno` and `col_offset` values — required before compiling a manually constructed or modified AST

---

## What It Is

Think of diagramming a sentence in English grammar class. "The cat sat on the mat" is a sequence of words, but a sentence diagram organizes those words into a hierarchical structure: the sentence has a subject ("the cat") and a predicate ("sat on the mat"); the predicate has a verb ("sat") and a prepositional phrase ("on the mat"); the prepositional phrase has a preposition ("on") and a noun phrase ("the mat"). The raw words are the tokens; the sentence diagram is the AST. The diagram throws away information that has no grammatical meaning (spacing, exact punctuation style) and keeps only structural relationships.

Python's AST is that grammatical diagram for Python code. After the tokenizer has produced `NAME('def')`, `NAME('add')`, `OP('(')`, `NAME('x')`, `OP(',')`, `NAME('y')`, `OP(')')`, `OP(':')`, `NEWLINE`, `INDENT`, `NAME('return')`, `NAME('x')`, `OP('+')`, `NAME('y')`, `NEWLINE`, `DEDENT`, the parser organizes these tokens into a tree: a `FunctionDef` node with name `"add"`, a list of `arg` nodes, and a body containing a `Return` node wrapping a `BinOp` node with `Add` as the operator and two `Name` nodes as operands. The tree structure directly represents the nesting and relationships that the flat token stream only implied.

The AST is the natural representation for the compiler because it makes the code's structure explicit. Generating bytecode for a `BinOp` node means: compile the left operand, compile the right operand, emit the operator instruction. Generating bytecode for an `If` node means: compile the test, emit a conditional jump, compile the body, patch the jump target, optionally compile the else branch. These recursive patterns over tree nodes map naturally to the recursive structure of the AST.

---

## How It Actually Works

CPython's current parser (since 3.9) is a PEG (Parsing Expression Grammar) parser, generated from the grammar specification in `Grammar/python.gram`. PEG parsers use memoization to avoid redundant computation and can express more complex grammar rules than the older LL(1) parser — notably, they can handle left-recursive rules and produce better error messages by tracking how far parsing succeeded before failing.

The parser produces a Concrete Syntax Tree (CST) internally, then simplifies it into the AST by discarding structural tokens (parentheses, commas) that are implied by the tree structure. The result is a tree of `ast.AST` node instances. Each node type is defined in `Parser/Python.asdl` (the ASDL grammar) and generated into C code. The Python `ast` module exposes these node types and provides utility functions.

`ast.parse(source_string)` runs the full tokenize-parse pipeline and returns the root `Module` node. `ast.walk(tree)` yields all nodes in depth-first order. `ast.NodeVisitor` and `ast.NodeTransformer` are the standard base classes for writing AST visitors and transformers. A `NodeTransformer` that overrides `visit_Name(self, node)` can replace every `Name` node in the tree — `pytest` uses this to transform `assert x == y` into code that captures the values of `x` and `y` for a detailed failure message.

The compiled form of the AST is obtained by passing it to `compile()`: `code = compile(tree, "<string>", "exec")`. The resulting code object can be executed with `exec(code)` or inspected with `dis.dis(code)`. This programmatic pipeline — parse, transform, compile, execute — is how runtime code generation and domain-specific optimizations work in Python.

---

## How It Connects

Tokenization is the step that feeds the parser. The token stream produced by the tokenizer (NAME, OP, NUMBER, INDENT, DEDENT tokens) is the input to the parser. Understanding what tokens are available and their sequence is what makes grammar rules meaningful.
[[tokenization|Tokenization]]

The AST is the input to the bytecode compiler. After the AST is built, the compiler traverses it and generates bytecode instructions. The structure of the AST directly shapes the structure of the bytecode — nested expressions produce stacked bytecode; function definitions produce nested code objects.
[[bytecode|Bytecode]]

---

## Common Misconceptions

Misconception 1: "If `ast.parse()` succeeds, the code is valid Python."
Reality: `ast.parse()` checks only syntactic validity — that the code conforms to Python's grammar. Semantic errors like `NameError` (using an undefined variable), `TypeError` (wrong types in operations), and `AttributeError` (accessing a non-existent attribute) are not detectable at parse time. `ast.parse("1 / 0")` succeeds; the `ZeroDivisionError` only occurs when the bytecode is executed. Static analysis tools (mypy, pyflakes) do additional semantic checking on top of the AST.

Misconception 2: "Modifying the AST of a running program changes its behavior."
Reality: By the time Python is executing bytecode, the AST has already been compiled and discarded. The AST is an intermediate representation that exists only during the compilation phase — it is not retained at runtime. Modifying the AST of a function's code does not change that function's bytecode. To modify behavior at runtime, you must either modify the bytecode directly (using `types.CodeType`) or modify the source and recompile, or use a hook that intercepts compilation (like `importlib` machinery or `sys.meta_path`).

---

## Why It Matters in Practice

AST manipulation is the foundation of Python's metaprogramming ecosystem. `pytest` rewrites `assert` statements by transforming the AST before compilation to add diagnostic information. `numba` walks the AST of decorated functions and compiles them to native machine code. `mypy` type-checks code by analyzing the AST and inferring types. `Black` reformats code by parsing to an AST and re-serializing it. Understanding the AST is understanding how these tools achieve their transformations.

The `ast` module is also useful for safe evaluation of untrusted expressions. `ast.literal_eval(string)` parses the string and evaluates it only if it contains a literal value (number, string, list, dict, tuple, set, bool, None) — it raises `ValueError` for any other expression. This is the safe alternative to `eval()` for parsing configuration values, JSON-like strings, or user input that should only contain data literals.

---

## Interview Angle

Common question forms:
- "What is an Abstract Syntax Tree?"
- "How does Python's compiler use the AST?"
- "What can you do with the `ast` module?"

Answer frame: The AST is the grammatical structure of Python source code represented as a tree of node objects. The parser builds it from the token stream; the bytecode compiler traverses it to generate bytecode. The `ast` module provides `ast.parse()` (produce the tree), `ast.NodeVisitor` (walk without modification), `ast.NodeTransformer` (walk with modification), and `compile()` (AST → code object). Practical uses: `pytest` assertion rewriting, linters, formatters, JIT compilers, safe expression evaluation via `ast.literal_eval()`.

---

## Related Notes

- [[tokenization|Tokenization]]
- [[bytecode|Bytecode]]
- [[source-to-execution|From Source Code to Execution]]
