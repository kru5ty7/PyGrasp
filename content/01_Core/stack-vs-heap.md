---
title: Stack vs Heap
description: The stack holds function call frames and is managed automatically by the call order; the heap holds all Python objects and is managed by CPython's allocator and garbage collector — in Python, almost everything lives on the heap.
tags: [stack, heap, memory, frame-object, pymalloc, cpython, layer-0, core]
status: draft
difficulty: beginner
layer: 0
domain: core
created: 2026-05-17
---

# Stack vs Heap

> The stack holds function call frames and is managed automatically by the call order; the heap holds all Python objects and is managed by CPython's allocator and garbage collector — in Python, almost everything lives on the heap.

---

## Quick Reference

**Core idea:**
- **Stack**: LIFO memory region managed automatically — in Python, used for C-level execution (the OS thread stack) and conceptually for the chain of Python frames
- **Heap**: large, dynamically managed memory region — where every Python object (`int`, `list`, `dict`, `function`, class instance) is allocated via pymalloc or `malloc`
- In Python, **variable names do not live on the stack** — local variables are stored in the frame's fast-locals array, which is on the heap (or CPython's frame stack in 3.11+)
- Every `int`, `str`, `list`, and custom object is heap-allocated — there is no stack allocation of Python objects
- The Python call stack is a **logical concept** (the chain of frames) — it is distinct from the OS thread stack (where C function calls and CPython's eval loop live)

**Tricky points:**
- Python has no stack-allocated objects — `x = 42` does not put an integer on the stack; it creates a heap object and stores a reference (pointer) in the frame's locals array
- The **OS thread stack** is a real C-level memory region — CPython's eval loop runs on it; overflowing it (via excessive recursion depth) causes a C stack overflow / segfault
- CPython 3.11+ allocates `_PyInterpreterFrame` structs in a per-thread **frame stack** (a heap-allocated C array) — this is not the OS thread stack but mimics its LIFO behavior for efficiency
- In languages like C, local variables live on the OS stack; in Python, local variables live in the frame's `f_localsplus` array on the heap — this is why Python closures can capture locals without them "going away" after return
- Memory fragmentation is primarily a heap concern — the stack is uniformly managed by growth and shrinkage

---

## What It Is

Think of a restaurant kitchen. The counter space next to each chef (the stack) is small, organized, and managed automatically — a chef puts an ingredient down when starting a dish and picks it back up when needed; the counter is cleared when the dish is done. This space is fast and structured. The pantry (the heap) is large, unstructured storage where ingredients are kept in bins of various sizes — the chef explicitly requests ingredients and returns them when done; the pantry manager tracks what is where. Counter space is automatic and bounded; pantry is explicit and large.

In low-level languages like C, local function variables really do live on the stack — they are allocated in the function's stack frame when the function is called and freed automatically when it returns. This is fast but limiting: stack frames have fixed size and the total stack is small (typically 1–8 MB per thread). Heap allocation is more flexible but requires explicit management (in C: `malloc`/`free`; in Python: the garbage collector).

Python makes a different trade-off: almost nothing lives on the actual OS stack. Every Python object — even a trivial `int(1)` produced in the middle of a calculation — is heap-allocated. The frame objects that conceptually form the call stack are also heap objects (or CPython 3.11's frame stack, which is a heap-allocated C array). This means Python has no stack size constraint on objects, closures always work correctly (captured variables are on the heap and outlive their function), and every object has a lifetime managed by reference counting and the GC rather than by the call structure.

---

## How It Actually Works

When a Python program runs, CPython's eval loop is a C function executing on the OS thread stack. The C variables that CPython uses internally (the bytecode dispatch loop variables, the current instruction pointer as a C local) live on the OS thread stack. This is the "real" stack in the system. Python's recursion limit prevents this C stack from overflowing — but because each Python frame is not actually on the C stack (it is a heap object), the C stack's depth stays nearly constant regardless of Python recursion depth.

The heap is where Python's action is. `PyObject_Malloc(size)` allocates memory from pymalloc's pool system (for objects ≤ 512 bytes) or from the C runtime `malloc` (for larger objects). `PyObject_Free(p)` returns the memory. Every `list`, `dict`, `str`, `int`, `tuple`, class instance, function object, and module is a C struct allocated on this heap. The heap's size is bounded only by available virtual memory.

When you write `x = 5` inside a function, here is what actually happens in memory: `5` is an integer in the small integer cache (already heap-allocated). The name `x` is assigned in the function's frame's fast-locals array (which is part of the frame object on the heap or frame stack). No new C stack allocation happens. When the function returns, the frame is freed (or returned to a free list), and if `x` was the last reference to the integer (not the case for cached `5`), the integer would be freed too.

---

## How It Connects

The call stack is the logical structure formed by Python's chain of frame objects. The frame objects themselves live on the heap (or CPython's frame stack). The call stack concept is implemented on top of the heap allocation model.
[[call-stack|The Call Stack]]

Python's memory model explains how objects are organized in memory and why the heap is necessary for Python's dynamic object model. The stack-vs-heap distinction is the underlying physical memory organization that the Python memory model describes at a higher level.
[[python-memory-model|Python's Memory Model]]

pymalloc is the allocator that manages the heap for Python's small objects. Understanding the heap is understanding what pymalloc is managing: the pool of memory from which all Python objects are carved.
[[memory-allocator|Python's Memory Allocator]]

---

## Common Misconceptions

Misconception 1: "Python is slow because it uses the heap for everything."
Reality: Heap allocation has overhead (it requires the allocator to find and record a free block), but CPython's pymalloc minimizes this overhead for small objects — allocation from a pool is an O(1) pointer operation. The bigger performance cost is not the heap allocation itself but what the heap enables: every object is dynamically typed (requires `ob_type` lookup for every operation), reference-counted (requires `ob_refcnt` increment/decrement for every assignment), and garbage-collected. These dynamic semantics — not heap allocation per se — are the primary performance cost.

Misconception 2: "When a function returns, all its local variables are freed immediately."
Reality: When a function returns, its frame object is freed (or pooled for reuse). The local variables stored in the frame's fast-locals array are references (pointers) to heap objects. When the frame is freed, those references are released — which decrements the reference counts of the pointed-to objects. If those objects have no other references, they are immediately freed. But if other code holds references to the same objects (the caller received the return value, a closure captured a variable, a list still contains the object), they remain alive on the heap. The frame's removal does not immediately free the objects it referenced.

---

## Why It Matters in Practice

The stack-vs-heap distinction explains why Python closures work intuitively. When an inner function captures a variable from an outer function, the captured variable is stored in a "cell object" on the heap — not on the outer function's stack frame. When the outer function returns and its frame is freed, the cell object persists because the inner function holds a reference to it. In C, capturing a stack-allocated local variable in a function pointer would leave a dangling pointer; Python's heap-based model makes closures safe by design.

Memory profiling with `tracemalloc` traces heap allocations. Every allocation in `tracemalloc` output is a heap allocation — there are no stack allocations to trace in Python code. This makes `tracemalloc` comprehensive for Python-level analysis: it captures every object created by Python code, with its allocation site.

---

## Interview Angle

Common question forms:
- "Where do Python variables live — stack or heap?"
- "Why can Python closures access outer function variables after the outer function returns?"
- "How does Python manage memory?"

Answer frame: In Python, all objects live on the heap — ints, strings, lists, function objects, frames. There are no stack-allocated objects. Variable names (local variables) are stored in the frame's fast-locals array, which is part of the frame object on the heap. The OS thread stack holds CPython's C-level eval loop but not Python objects. Closures work because captured variables are stored in cell objects on the heap, surviving the outer frame's deletion. Memory is managed by reference counting (immediate) plus the cyclic GC (periodic, for cycles).

---

## Related Notes

- [[call-stack|The Call Stack]]
- [[python-memory-model|Python's Memory Model]]
- [[memory-allocator|Python's Memory Allocator]]
- [[frame-object|The Frame Object]]
