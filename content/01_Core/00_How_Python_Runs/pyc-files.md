---
title: 09 - .pyc Files and __pycache__
description: .pyc files are CPython's cached bytecode  -  when Python imports a module, it compiles the source to bytecode and stores it in __pycache__ so subsequent imports skip the compilation step, validated against the source file's modification time.
tags: [pyc-files, pycache, bytecode-cache, compilation, import, cpython, layer-0, core]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# .pyc Files and __pycache__

> .pyc files are CPython's cached bytecode  -  when Python imports a module, it compiles the source to bytecode and stores it in __pycache__ so subsequent imports skip the compilation step, validated against the source file's modification time.

---

## Quick Reference

**Core idea:**
- When Python imports a `.py` file for the first time, it compiles it to bytecode and saves the result to `__pycache__/module.cpython-312.pyc`
- On subsequent imports, CPython checks if the `.pyc` is newer than the `.py` source and uses the cached bytecode, skipping re-compilation
- `.pyc` file format: 4-byte magic number (version-specific) + 4-byte flags + 8-byte source metadata (mtime + size) + marshalled bytecode
- `__pycache__` is created automatically in the same directory as the source file; the filename encodes the Python version to allow multiple versions to coexist
- Running `python -m compileall .` pre-compiles all `.py` files in a directory tree  -  useful for deployment to skip compilation on first import

**Tricky points:**
- `.pyc` files are **not cross-version**  -  a `.pyc` compiled by Python 3.12 cannot be used by Python 3.11 (different magic number)
- If the source `.py` file is deleted, Python can still import the module from the `.pyc` file alone  -  useful for distributing compiled-only packages
- `python -B` or `PYTHONDONTWRITEBYTECODE=1` suppresses `.pyc` creation  -  useful in Docker images to reduce layer size
- **Hash-based `.pyc` files** (Python 3.8+, `--check-hash-based-pycs`) validate the `.pyc` by hashing the source file instead of checking mtime  -  more reliable in environments where file timestamps are unreliable (Docker builds, CI)
- The magic number in the `.pyc` header changes with every Python release that changes the bytecode format  -  even minor versions can invalidate cached bytecode

---

## What It Is

Think of a chef who translates a handwritten recipe in French into English once, then keeps the English translation in a drawer. Every time someone asks to cook that dish, the chef uses the English translation rather than re-translating the French original. The chef does check the original recipe occasionally  -  if it has been rewritten (modified time changed), the translation is discarded and the new version is translated. Otherwise, the drawer copy is used directly, saving the translation time. Python's `.pyc` files work exactly this way: the French recipe is your `.py` source file; the English translation is the compiled bytecode stored in `__pycache__`.

CPython always needs bytecode to execute Python code  -  it cannot run source directly. The compilation step converts source text to bytecode, and while it is fast, it is not free. For programs with many modules (a typical Django application imports hundreds of modules at startup), compiling all of them from source on every startup would add noticeable delay. The `.pyc` cache eliminates this overhead for modules whose source has not changed.

The `__pycache__` directory was introduced in Python 3.2 to replace the earlier scheme of storing `.pyc` files alongside their `.py` sources. The new location keeps source directories clean and allows multiple Python versions to cache bytecode simultaneously  -  a Python 3.11 `.pyc` and a Python 3.12 `.pyc` for the same module coexist in `__pycache__` with version-tagged filenames.

---

## How It Actually Works

When CPython's import system loads a module, it calls `importlib._bootstrap_external.SourceFileLoader.get_code()`. This method checks whether a valid `.pyc` exists in `__pycache__`. "Valid" means: the magic number matches the current Python version, and either the source file's mtime and size match the values stored in the `.pyc` header (timestamp mode) or the source file's hash matches the stored hash (hash mode).

The `.pyc` file format is minimal. The first 16 bytes are the header: 4 bytes for the version-specific magic number (which changes whenever the bytecode format changes), 4 bytes for bit flags (bit 0 = hash-based, bit 1 = checked/unchecked hash), and 8 bytes for either the source mtime + size (timestamp mode) or a SipHash of the source (hash mode). After the header, the file contains the result of `marshal.dumps(code_object)`  -  the marshalled `PyCodeObject` that the eval loop can execute directly.

If the cache is valid, CPython calls `marshal.loads()` on the bytecode section and gets a ready-to-execute `PyCodeObject` without any compilation. If the cache is missing or invalid, CPython compiles the source, then asynchronously writes the new `.pyc` (in a try/except  -  failure to write the cache is silently ignored, not a fatal error). The write is done with a rename-to-final-path pattern to avoid leaving partially-written `.pyc` files if the process is interrupted.

---

## How It Connects

The bytecode stored in `.pyc` files is the same bytecode described in the bytecode note  -  the `LOAD_FAST`, `BINARY_OP`, `CALL`, and other instructions that the CPython eval loop executes. The `.pyc` is simply a persistent serialization of the `PyCodeObject` that would otherwise be produced in memory.
[[bytecode|Bytecode]]

The compilation pipeline that produces the bytecode stored in `.pyc` files is the full source-to-execution pipeline: tokenize -> parse -> compile to bytecode. The `.pyc` cache allows this pipeline to be skipped when the source has not changed, but the output (the `PyCodeObject`) is identical to what the pipeline would produce.
[[source-to-execution|From Source Code to Execution]]

---

## Common Misconceptions

Misconception 1: "Deleting `__pycache__` will speed up your program."
Reality: Deleting `__pycache__` forces CPython to recompile all modules from source on the next import. This makes the first run after deletion slower, not faster. Subsequent runs will regenerate the cache and return to normal speed. There is no performance benefit to deleting `__pycache__` in normal operation. The reason to delete it is consistency  -  to force a clean recompile when bytecode caching is suspected of causing stale-code issues (rare but possible in unusual deployment configurations).

Misconception 2: ".pyc files contain compiled machine code."
Reality: `.pyc` files contain CPython bytecode  -  instructions for the CPython virtual machine, not for any physical CPU. They cannot be executed without CPython. They are not compiled in the sense that C compilation produces executables. The benefit of `.pyc` is skipping the tokenize-parse-compile-to-bytecode pipeline; the bytecode still requires the CPython interpreter at runtime. Tools like Nuitka and Cython can produce actual machine code from Python, but that is a separate process entirely.

---

## Why It Matters in Practice

In Docker images and deployment pipelines, pre-compiling Python files with `python -m compileall -q .` reduces startup latency by eliminating the compilation step at runtime. It also allows packaging compiled `.pyc` files without source `.py` files for modest IP protection (though `.pyc` files can be decompiled). The `-q` flag suppresses per-file output; `-j0` uses all available CPU cores for parallel compilation.

`PYTHONDONTWRITEBYTECODE=1` is common in Docker base images because it avoids creating `__pycache__` directories that add no value in ephemeral containers where the filesystem is not persistent. It also prevents tests and build processes from polluting source directories with `.pyc` files. However, it means every import pays the compilation cost on every container start  -  for containers that run short-lived tasks, this is acceptable; for long-lived application servers, it adds measurable startup time.

---

## Interview Angle

Common question forms:
- "What is a .pyc file?"
- "Why does Python create a `__pycache__` directory?"
- "How does Python know if a .pyc file is still valid?"

Answer frame: `.pyc` files are cached bytecode  -  serialized `PyCodeObject` instances stored in `__pycache__`. They avoid recompiling unchanged modules on every import. Validity check: the `.pyc` header stores the source mtime and size; CPython checks these against the current source file on every import. If they match, use the cache; if not, recompile and update the cache. Version-tagged filenames allow multiple Python versions to cache the same module. Pre-compile with `python -m compileall`.

---

## Related Notes

- [[bytecode|Bytecode]]
- [[source-to-execution|From Source Code to Execution]]
- [[interpreter-loop|The Interpreter Loop]]
