---
title: 06 - Bytes and Bytearray
description: "bytes is an immutable sequence of integers 0–255; bytearray is its mutable counterpart — both expose the buffer protocol for zero-copy interop with sockets, NumPy, and other binary I/O systems."
tags: [bytes, bytearray, buffer-protocol, binary-io, encoding, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Bytes and Bytearray

> `bytes` and `bytearray` are Python's binary containers — the layer below text where network packets, file content, and cryptographic material live before they are decoded into meaning.

---

## Quick Reference

**Core idea:**
- `bytes`: immutable sequence of integers in range 0–255; literal `b"hello"`, indexing returns `int`
- `bytearray`: mutable equivalent — same interface plus in-place mutation methods like `append`, `extend`
- Crossing the text boundary: `str.encode(encoding)` → `bytes`; `bytes.decode(encoding)` → `str`
- Buffer protocol: both `bytes` and `bytearray` expose a raw memory buffer — zero-copy access for `socket.send`, NumPy, `struct`, `ctypes`
- `memoryview` wraps a buffer-protocol object and allows slicing without copying the underlying memory

**Tricky points:**
- `b"hello"[0]` returns `104` (an integer), not `b"h"` (a bytes object) — single-element indexing gives int
- `b"hello"[0:1]` returns `b"h"` — slicing preserves the bytes type
- `bytes + bytes` creates a new bytes object; `bytearray += bytes` extends in-place
- `bytearray` is not hashable; `bytes` is (like str vs list)
- `bytes.hex()` and `bytes.fromhex()` are the idiomatic way to inspect and construct binary data as hex strings

---

## What It Is

Imagine a sealed envelope. Inside the envelope is raw paper — no meaning, no language, just physical marks. Before you can read the letter, you must open the envelope and apply context: "this is written in English, using the Latin alphabet." The envelope is `bytes`; applying the English-alphabet context is decoding; the resulting human-readable message is `str`.

That analogy captures why Python insists on separating `bytes` from `str`. Network packets, file contents, and database BLOBs arrive as raw sequences of octets — integers between 0 and 255 with no inherent textual meaning. Only when you apply a codec (UTF-8, Latin-1, base64) do those octets acquire meaning. Python forces you to be explicit about when that transformation happens, rather than guessing silently and producing garbled text.

`bytearray` adds mutability to `bytes`. Where a `bytes` object cannot be modified after creation, `bytearray` lets you overwrite individual bytes, append new ones, or insert in the middle. This matters when building binary protocol messages incrementally — network frame assemblers, binary serializers, and packet builders all benefit from in-place mutation rather than allocating a new `bytes` object on every change. The `bytearray` fills the same role relative to `bytes` that `list` fills relative to `tuple`.

---

## How It Actually Works

A `bytes` object in CPython is represented by `PyBytesObject`, which stores its contents in a flexible C array appended directly to the struct header — the same layout used by compact strings and tuples. This means the byte data lives contiguously in memory immediately after the Python object header, with no additional heap allocation. Single-byte values from 0 to 255 are cached in a global array `characters[256]` in `bytesobject.c`, so `b"\x00"` through `b"\xff"` each return the same singleton — analogous to the small integer cache.

The buffer protocol is the mechanism that enables zero-copy binary I/O. An object that implements `__buffer__` (or the C-level `bf_getbuffer` slot) exposes a `Py_buffer` struct describing a contiguous region of memory: a pointer, a length, an element size, and format information. When you call `socket.send(data)`, the socket machinery calls `PyBUF_SIMPLE` on the argument — it does not copy the data into a temporary buffer, it reads directly from the memory region described by `data`'s buffer. `bytearray`, `bytes`, `array.array`, and NumPy arrays all implement this protocol.

```python
data = bytearray(b"hello world")
view = memoryview(data)
# Slice the memoryview — no copy, just a new view object
chunk = view[6:11]
print(bytes(chunk))   # b'world'
data[6] = ord('W')
print(bytes(chunk))   # b'World' — view reflects mutation
```

`memoryview` wraps any buffer-protocol object and lets you slice it, reinterpret its element type (e.g., treat a `bytes` of 4-byte floats as `float` elements), and pass subregions to other buffer-protocol consumers — all without copying. This is how NumPy arrays and `bytes` objects interoperate without marshaling.

---

## How It Connects

Strings and bytes are the two sides of the text/binary boundary. Every time Python reads from a file, socket, or subprocess, it receives `bytes`. The decision of when and how to decode those bytes into `str` is one of the most consequential design choices in any Python application that handles external data.

[[strings|Strings]]

The buffer protocol and `memoryview` are the foundation for zero-copy I/O in Python. Understanding this connection explains why passing a `bytearray` to `socket.sendall()` is equivalent to passing a `bytes` object but allows the caller to modify the buffer while constructing it.

[[python-memory-model|Python Memory Model]]

Binary data frequently arrives in structured form — fixed-width integers, floats, network byte order. The `struct` module unpacks `bytes` or `bytearray` into Python objects using format strings, operating directly on the buffer without creating intermediate copies.

[[everything-is-an-object|Everything Is an Object]]

---

## Common Misconceptions

Misconception 1: "Indexing `b'abc'[0]` gives you `b'a'`."
Reality: Indexing a `bytes` or `bytearray` with a single integer returns an `int` (the byte value), not a length-1 bytes object. Use `b'abc'[0:1]` to get `b'a'`.

Misconception 2: "`bytes` and `str` are interchangeable in Python 3."
Reality: In Python 3, `str` and `bytes` are completely separate types with no implicit conversion between them. Any operation that mixes them — like `b"hello" + "world"` — raises `TypeError`. This was intentional: Python 2's implicit mixing was a major source of encoding bugs.

Misconception 3: "Passing `bytearray` to a function that expects `bytes` will fail."
Reality: Most standard library functions accept anything implementing the buffer protocol. `socket.send`, `hashlib.update`, `struct.pack_into`, and similar functions accept `bytes`, `bytearray`, and `memoryview` interchangeably via the buffer protocol.

---

## Why It Matters in Practice

Every Python application that communicates over a network, reads from a file in binary mode, or calls a C extension library will deal with `bytes`. The most common failure mode is forgetting to decode — receiving bytes from a socket and trying to use them as a string, or forgetting to encode before writing. Python 3's strict separation between `str` and `bytes` turns these mistakes into immediate `TypeError` exceptions rather than silent mojibake.

`bytearray` and `memoryview` become important when performance matters at the binary level. Assembling a large binary protocol frame by appending to a `bytearray` is O(n) amortized, while assembling it by concatenating `bytes` objects is O(n²). Similarly, passing a `memoryview` slice to a socket or hash function avoids copying a potentially large buffer just to pass a subset of it.

---

## Interview Angle

Common question forms:
- "What is the difference between `bytes` and `bytearray`?"
- "What is the buffer protocol and why does it matter?"
- "How do you convert between `str` and `bytes` in Python?"

Answer frame:
`bytes` is immutable, hashable, optimized for read-only binary data; `bytearray` is mutable, better for incremental construction. The buffer protocol lets objects expose raw memory directly — `socket.send(bytearray_data)` reads from the C array without copying. `str` ↔ `bytes` conversion always requires a codec: `s.encode('utf-8')` and `b.decode('utf-8')`, and the codec must match the actual encoding of the data.

---

## Related Notes

- [[strings|Strings]]
- [[mutability|Mutability]]
- [[python-memory-model|Python Memory Model]]
- [[everything-is-an-object|Everything Is an Object]]
