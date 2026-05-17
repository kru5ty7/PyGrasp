---
title: "01 - Python's Memory Model"
description: Python's memory model describes how CPython allocates, organizes, and reclaims the memory used by every object your program creates — a layered system designed around the reality that Python programs create enormous numbers of small, short-lived objects.
tags: [memory, cpython, allocator, heap, pymalloc, gc, core]
status: draft
difficulty: advanced
layer: 0
domain: core
created: 2026-05-17
---

# Python's Memory Model

> Python's memory model describes how CPython allocates, organizes, and reclaims the memory used by every object your program creates — a layered system designed around the reality that Python programs create enormous numbers of small, short-lived objects.

---

## Quick Reference

**Core idea:**
- Three-layer allocator: **OS → `malloc` (objects > 512 bytes) → `pymalloc` (objects ≤ 512 bytes)**
- `pymalloc` structure: **arenas** (256 KB) → **pools** (4 KB, one size class each) → **blocks** (one object slot)
- Size classes: 8, 16, 24 … 512 bytes in multiples of 8
- Per-type **free lists** for floats, frames, etc. — bypass even pymalloc for hot allocations
- Assignment **binds** a name to an object — `a = b` makes two names point to the same object, not a copy

**Tricky points:**
- Process memory stays **high after peak allocation** — freed objects return to pymalloc pools, not the OS; arenas only return to OS when fully empty (rare)
- `a = [1,2,3]; b = a` — **one list, two names**; `b.append(4)` is visible through `a`
- `del x` removes **one reference** — the object lives until its refcount hits zero
- Python list of 1M integers = **1M heap-allocated structs**; NumPy array = **one contiguous C allocation** — this gap is the memory model in action

---

## What It Is

Picture a large warehouse divided into sections. The loading dock handles incoming and outgoing cargo of any size — this is general-purpose storage. But inside the warehouse, there is a special area for small packages that come and go constantly. That area is subdivided into rows of shelves, each shelf holding a specific box size. When a small package arrives, a worker takes it straight to the right shelf size, slots it in, and notes its location. When it leaves, the slot is marked empty and immediately available for the next package of the same size. This is far faster than taking every small package through the general loading dock. CPython's memory system works the same way: a general-purpose allocator handles large objects, while a specialized allocator manages the flood of small objects Python programs constantly create and discard.

Python's memory model is invisible to you as a developer. You do not call `malloc` or `free`. You create objects and they appear; you stop using them and they disappear. But the system underneath makes specific trade-offs that affect your program's performance and memory footprint. The most important of these is that CPython does not return memory to the OS immediately or eagerly. It holds onto freed memory inside its own allocator, ready to hand it out again the next time an object of the same size is needed. This means a Python process that briefly allocated a large number of objects may appear to hold more memory than you expect, even after those objects are gone.

Variables in Python do not own memory. They are references — names that point to objects. When you write `a = [1, 2, 3]` and then `b = a`, you do not have two lists. You have one list object in memory and two names pointing to it. This is the binding model: assignment binds a name to an object, it does not copy the object. The memory model and the reference model are inseparable — understanding one requires understanding the other.

---

## How It Actually Works

CPython uses a three-layer memory architecture. The bottom layer is the OS: raw memory pages obtained via `mmap` or `VirtualAlloc`. The middle layer is the C runtime's allocator (`malloc`/`free`), which CPython uses for objects larger than 512 bytes and for its own internal data structures. The top layer is CPython's own custom allocator, `pymalloc`, which handles objects 512 bytes or smaller — the vast majority of Python objects in practice.

`pymalloc` organizes memory into three tiers: arenas, pools, and blocks. An arena is a 256 KB region of memory obtained from the OS, aligned to a 256 KB boundary. Each arena is divided into pools, each pool is exactly one OS memory page (usually 4 KB). Each pool is dedicated to a single size class — pools hold objects of 8 bytes, or 16 bytes, or 24 bytes, all the way up to 512 bytes in multiples of 8. A block is one slot within a pool — exactly the right size for one object of that pool's size class. When you create a Python integer, `pymalloc` finds a pool for the right size class, takes the next free block, and returns a pointer to it. When the integer is freed, that block is returned to the pool's free list. No call to `malloc` or `free` at the OS level is needed.

This design has an important consequence: arenas are only returned to the OS when every pool inside them is completely empty — all their blocks are free simultaneously. If even one object in an arena is still alive, the entire arena stays allocated. In practice, a mix of long-lived and short-lived objects in the same arena means the arena never fully empties. This is why Python's memory footprint can seem larger than expected and why programs that create and discard many objects may retain their peak memory usage for a long time.

CPython also maintains a free list for certain common object types — small integers (-5 to 256), `None`, `True`, `False`, short strings, and others. These objects are never freed; CPython preallocates them at startup and returns the cached versions when they are requested. For floats and other types with high allocation churn, CPython maintains a separate per-type free list: when a float object is freed, it goes onto the float free list rather than back to `pymalloc`, and the next float allocation takes from that list first. This avoids even `pymalloc` overhead for the most common allocation patterns.

---

## How It Connects

The mechanism by which CPython decides when an object's memory can be freed is reference counting. Every Python object carries a count of how many references point to it, and the count reaching zero triggers immediate deallocation. The memory model describes the allocator; reference counting describes the trigger for deallocation.
[[reference-counting|Reference Counting]]

Reference counting alone cannot handle all cases. Objects that reference each other in a cycle will never reach a zero count even when no external references exist. CPython's cyclic garbage collector exists to find and collect these cycles. It operates on top of the allocator described here, scanning specific generations of objects.
[[garbage-collection|Garbage Collection]]

The fact that every Python value is a heap-allocated `PyObject` struct is the reason the memory model matters. If Python stored values as raw primitives like C does, there would be nothing to allocate on the heap in the first place. The memory model only makes sense in the context of the object model it serves.
[[everything-is-an-object|Everything is an Object]]

---

## Common Misconceptions

Misconception 1: "When I delete a variable in Python, the memory is released back to the OS."
Reality: Deleting a variable removes one reference to an object. If that was the last reference, CPython frees the object's memory — but frees it back to `pymalloc`'s internal pool system, not to the OS. The OS memory stays allocated to the Python process. Memory returns to the OS only when entire arenas empty out, which requires all objects in that arena to be freed simultaneously. For most programs, memory usage appears to grow to a peak and stay there.

Misconception 2: "Python's garbage collector is what frees most objects."
Reality: The garbage collector only handles reference cycles — objects that keep each other alive despite having no external references. The vast majority of Python objects are freed immediately by reference counting the moment their reference count hits zero, with no garbage collector involvement at all. The GC is a supplementary mechanism for a specific edge case, not the primary memory management strategy.

---

## Why It Matters in Practice

The binding model — assignment binds names to objects, it does not copy them — is the source of many Python bugs involving mutable default arguments, shared list state, and unexpected aliasing. When you pass a list to a function and the function modifies it, you see the change outside the function because there is only one list object and both names point to it. This is not a quirk; it is a direct consequence of how Python's memory model works.

The allocator design affects performance in ways that are easy to miss. Creating and discarding many small objects (as you do when building intermediate strings with concatenation, or when using Python-level loops over large datasets) puts sustained pressure on `pymalloc`. NumPy and similar libraries sidestep this by storing data in contiguous C arrays rather than as individual Python objects. When you move from a Python list of integers to a NumPy array, you are switching from a million individually heap-allocated `PyLongObject` structs to a single C array allocation. The performance difference is a direct consequence of the memory model.

---

## Interview Angle

Common question forms:
- "How does Python manage memory?"
- "Why does my Python process use more memory than expected after processing a large dataset?"
- "What is the difference between the garbage collector and reference counting in Python?"

Answer frame: Describe the three-layer allocator (OS → malloc → pymalloc). Explain that most objects are freed by reference counting, not the GC. Explain that pymalloc holds freed memory in internal pools rather than returning it to the OS, which explains sustained memory usage after peak allocation. Distinguish the GC (cycles only) from reference counting (everything else).

---

## Related Notes

- [[everything-is-an-object|Everything is an Object]]
- [[reference-counting|Reference Counting]]
- [[garbage-collection|Garbage Collection]]
