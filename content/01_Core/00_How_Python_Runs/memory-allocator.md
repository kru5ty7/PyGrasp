---
title: 21 - Python's Memory Allocator
description: CPython uses a three-tier memory allocation system — the system allocator, the pymalloc arena allocator, and the object-specific allocators — designed to reduce the overhead of allocating and freeing the millions of small short-lived objects typical Python programs create.
tags: [memory-allocator, pymalloc, arenas, pools, blocks, cpython, memory, layer-0, core]
status: draft
difficulty: intermediate
layer: 0
domain: core
created: 2026-05-17
---

# Python's Memory Allocator

> CPython uses a three-tier memory allocation system — the system allocator, the pymalloc arena allocator, and the object-specific allocators — designed to reduce the overhead of allocating and freeing the millions of small short-lived objects typical Python programs create.

---

## Quick Reference

**Core idea:**
- CPython's `pymalloc` allocator manages objects **= 512 bytes** (the vast majority of Python objects) in a three-level hierarchy: **arenas ? pools ? blocks**
- **Arena**: 256 KB chunk obtained from the OS via `malloc` — subdivided into pools
- **Pool**: 4 KB page within an arena — all blocks in a pool are the same fixed size class
- **Block**: the individual allocation unit within a pool — size classes from 8 to 512 bytes in 8-byte increments
- Objects **> 512 bytes** bypass pymalloc and go directly to the system allocator (`malloc`/`free`)

**Tricky points:**
- `pymalloc` **does not return memory to the OS** until an entire arena is empty — a single surviving object in an arena keeps all 256 KB allocated
- This can cause apparent "memory leaks" in long-running processes where many objects are created and most are freed, but arenas never fully empty
- Python's memory usage reported by the OS (`RSS`) can stay high even after large objects are deleted, because pymalloc holds empty arenas
- Each pool serves a **single size class** — a pool that held 32-byte blocks will only ever hold 32-byte blocks, even after all those blocks are freed
- `tracemalloc` (stdlib) traces allocations to their Python source location — use it to find which code is responsible for memory growth

---

## What It Is

Think of a city's housing development strategy. Building individual custom houses for each resident (using `malloc`/`free` for every Python object) is expensive and slow — each build requires a separate permit, architect, and construction crew. Instead, the city builds large apartment blocks (arenas) subdivided into floors (pools), and each floor contains units of the same size (blocks). When a new resident arrives needing a 30 square meter studio, they are assigned to the appropriate floor in an existing apartment block. When they leave, their unit is marked available but the floor and building remain in place for the next resident. Only when an entire building is completely empty does the city return the land. Python's allocator works the same way — the granular per-object allocation cost is amortized across thousands of allocations from the same pre-allocated arena.

Python programs are dominated by small, short-lived object allocations. Every integer arithmetic operation may create a new integer object. Every string concatenation may create a new string. Every function call creates a new frame object. If each of these went through the operating system's general-purpose allocator, the overhead from system calls and fragmentation would be significant. CPython's `pymalloc` allocator is purpose-built for this pattern: it requests large chunks from the OS infrequently, then parcels out small fixed-size blocks within those chunks at near-zero cost.

The three-tier hierarchy is the mechanism. At the bottom, the OS provides large contiguous memory regions (arenas). Each arena is divided into pools, each pool serving a specific size class. Within a pool, allocation is as simple as taking the next block from a free list — a linked list of available blocks. The free list is maintained in the blocks themselves (freed blocks store a pointer to the next free block). This means allocation and deallocation within a pool can be O(1) pointer operations rather than the complex bookkeeping of a general-purpose allocator.

---

## How It Actually Works

`pymalloc` maintains 64 size classes, each 8 bytes apart: 8, 16, 24, 32, ..., 512 bytes. When CPython allocates an object, the request size is rounded up to the nearest size class. For a 20-byte request, the allocator uses the 24-byte size class. This rounding wastes some bytes per allocation but allows entire pools to be dedicated to one size, simplifying the free list management.

An arena is 256 KB, aligned to a page boundary. An arena begins life with all its space available as pools. When a pool is needed for a new size class, an arena provides a 4 KB chunk. The pool is initialized with all its blocks (4096 ÷ block_size = number of blocks) on a free list. Subsequent allocations from that size class reuse the same pool until it is full, then a new pool is initialized.

When a block is freed, it is pushed back onto the pool's free list — not returned to the OS. When a pool empties completely, it is returned to the arena. When an arena has all its pools freed, the arena itself is returned to the OS via `free()`. This last condition — all pools in a 256 KB arena must be completely empty — is why pymalloc can hold OS memory for a long time. In a server process that processes many requests, each request creating hundreds of short-lived objects, arenas tend to remain partially occupied indefinitely.

Allocations larger than 512 bytes bypass pymalloc and use `malloc` from the C runtime directly. Large objects — long strings, large lists, big dicts — are allocated and freed with the OS allocator, which handles large allocations more efficiently than pymalloc's fixed-size block scheme.

---

## How It Connects

The memory model note describes where Python objects live in memory and the relationship between the stack and heap. The allocator is the implementation mechanism for the heap side: when a Python object is created, pymalloc provides the memory from the appropriate pool, and when the object is freed (by reference counting or GC), pymalloc returns the block to the pool's free list.
[[python-memory-model|Python's Memory Model]]

Reference counting drives pymalloc deallocation — when `ob_refcnt` reaches zero, CPython calls the type's `tp_dealloc` slot, which calls `PyObject_Free()`, which calls pymalloc's block-return logic. The interaction between the reference counter and the allocator is how most Python memory is recycled.
[[reference-counting|Reference Counting]]

---

## Common Misconceptions

Misconception 1: "Deleting large Python objects frees memory back to the OS immediately."
Reality: Freeing a Python object returns its block to pymalloc's free list. The 256 KB arena containing that block is only returned to the OS when every block in every pool in that arena has been freed. For typical Python programs, arenas contain many objects from different allocation bursts, making complete arena emptying rare. The memory is not leaked — it is available for future Python allocations — but the process RSS (as seen by the OS) does not decrease. This is why Python programs can appear to have a memory "high-water mark."

Misconception 2: "`gc.collect()` frees memory back to the OS."
Reality: `gc.collect()` runs the cyclic garbage collector, which finds and frees unreachable cyclic objects. The freed blocks go back into pymalloc's free lists. Whether that results in memory being returned to the OS depends on whether the freed blocks allow entire arenas to become empty — which depends on the specific allocation pattern. `gc.collect()` is not a "free all memory" call; it is a "collect unreachable cycles" call.

---

## Why It Matters in Practice

The `tracemalloc` module is the right tool for diagnosing Python memory growth. `tracemalloc.start()` before the operation of interest, followed by `tracemalloc.take_snapshot()` and `snapshot.statistics("lineno")`, shows exactly which lines of Python code are responsible for the most allocated memory. This works regardless of whether the memory growth is from a bug (a reference being held unintentionally) or a feature (a growing cache). It traces at the Python level, not the C level — pymalloc's internals are transparent to it.

For applications where memory reclamation to the OS matters (long-running services with periodic high-allocation bursts), `PYTHONMALLOC=malloc` replaces pymalloc with the system allocator for all allocations. This gives the OS allocator (which has its own logic for returning memory) full control, at the cost of higher per-allocation overhead. Alternatively, PyPy's garbage collector has different reclamation behavior and generally returns more memory to the OS after collection cycles.

---

## Interview Angle

Common question forms:
- "How does Python manage memory for small objects?"
- "Why does a Python process's memory not decrease after deleting objects?"
- "What is pymalloc?"

Answer frame: CPython uses pymalloc for objects = 512 bytes — a three-tier allocator: arenas (256 KB OS allocations) ? pools (4 KB, one per size class) ? blocks (8–512 bytes, fixed per pool). Allocation is O(1) — take from the pool's free list. Deallocation returns block to the free list; memory returns to OS only when a full arena empties. This is why `del` doesn't lower RSS — the arena holds onto the memory for future allocations. Use `tracemalloc` to trace allocation sources.

---

## Related Notes

- [[python-memory-model|Python's Memory Model]]
- [[reference-counting|Reference Counting]]
- [[garbage-collection|Garbage Collection]]
- [[object-header|Python Object Header]]
