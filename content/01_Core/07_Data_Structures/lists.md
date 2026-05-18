---
title: 01 - Lists
description: "Python's list is a dynamic array of PyObject pointers with amortized O(1) append via over-allocation, making it the go-to sequential container  -  unless insertion order at the front matters."
tags: [lists, dynamic-array, ob_item, over-allocation, list_resize, layer-1, core]
status: draft
difficulty: intermediate
layer: 1
domain: core
created: 2026-05-18
---

# Lists

> Python's list is a resizable C array of object pointers  -  understanding its growth formula explains why `append` is nearly free but `insert(0, x)` punishes you.

---

## Quick Reference

**Core idea:**
- Internally: a `PyListObject` with an `ob_item` field  -  a C array of `PyObject *` pointers
- Over-allocation formula: new capacity ≈ `(n + n >> 3 + 6)`, roughly 12.5% growth, so appends amortize to O(1)
- `list.__sizeof__()` returns struct size; `sys.getsizeof()` adds the GC overhead header
- Length (`len()`) and allocated slots are tracked separately  -  slots ≥ length always
- `list.sort()` uses Timsort, stable, O(n log n) in the worst case

**Tricky points:**
- `insert(0, x)` is O(n): every existing pointer must shift right one slot in the C array
- `list + list` always creates a new list  -  no in-place extension
- `a = b = []` makes two names point to the same list object; `a = []; b = []` makes two
- Slicing returns a shallow copy  -  nested objects are shared between the original and the slice
- `del lst[i]` shifts all elements after index `i` left  -  O(n) for the front, O(1) at the tail

---

## What It Is

Think of a list like a whiteboard with numbered slots. When you first create the board, you're given slightly more slots than you need  -  because whoever made the board knew you'd probably add more items soon. When you append an item, you fill the next empty slot. Only when all reserved slots are full does someone bring you a bigger whiteboard, copy everything over, and give you the new one  -  but they always give you extra slots again. This copy-and-grow operation happens rarely enough that the average cost per append stays tiny.

A Python list holds not the objects themselves but references to them  -  like a contact list that stores phone numbers, not the actual people. Every element, regardless of type, costs the same amount in the list: one pointer-sized slot (8 bytes on 64-bit). The objects those pointers point to live elsewhere in the heap, managed separately by CPython's memory allocator.

Lists are ordered and allow duplicates. They support heterogeneous elements because every slot is just a pointer and pointers are uniform in size. The ordered nature is not a happy accident  -  it is guaranteed by the contiguous C array layout. Index access is always O(1) because you are doing pointer arithmetic: `ob_item[i]` is `base_address + i * sizeof(PyObject *)`.

---

## How It Actually Works

In CPython's `listobject.c`, a list is represented by `PyListObject`:

```c
typedef struct {
    PyObject_VAR_HEAD
    PyObject **ob_item;   /* pointer to the array of item pointers */
    Py_ssize_t allocated; /* number of slots allocated, >= ob_size */
} PyListObject;
```

`ob_size` (from `PyObject_VAR_HEAD`) is the current length  -  what `len()` returns. `allocated` is the number of pointer slots that have been reserved in the C heap. These two numbers diverge because of the over-allocation strategy implemented in `list_resize()`. When Python needs to grow the list to hold `n` items, it allocates `n + (n >> 3) + (n < 9 ? 3 : 6)` slots. For a list of 8 elements, that means allocating 11 slots. This means the next three `append` calls will cost only an O(1) pointer write into an already-allocated slot, amortizing the expensive `realloc` across many operations.

When you call `list.append(x)`, CPython calls `list_resize(self, n+1)`. If `n+1 <= allocated`, it sets `ob_item[n] = x` and increments `ob_size`  -  pure pointer assignment, nothing more. Only when `n+1 > allocated` does a `realloc` occur. Contrast this with `list.insert(0, x)`: the function calls `memmove` to shift every existing pointer one position to the right before writing the new pointer at index 0. For a list of a million items, that is a million pointer copies. Profilers frequently surface this pattern in code that builds a list by prepending.

---

## How It Connects

Reference counting is the mechanism that keeps each object alive as long as at least one list (or any other container) holds a pointer to it. When a list slot is overwritten or the list is cleared, the reference count of the displaced object is decremented.

[[reference-counting|Reference Counting]]

The `collections.deque` structure exists precisely because lists are bad at front insertion. Understanding why lists use a C array makes deque's doubly-linked block design make sense.

[[collections-module|collections Module]]

Lists are mutable  -  their `ob_item` array can be reallocated and their slots can be overwritten. This is why lists cannot be used as dictionary keys or set members, a distinction that tuples and frozensets are designed to fill.

[[mutability|Mutability]]

---

## Common Misconceptions

Misconception 1: "A Python list is implemented as a linked list."
Reality: It is a contiguous C array of pointers. Random access is O(1), not O(n). A linked list would make index access proportional to position, which `list[i]` is not.

Misconception 2: "Every `append` triggers a reallocation."
Reality: Reallocation happens only when the allocated capacity is exhausted. Because over-allocation reserves ~12.5% extra slots, a long sequence of appends triggers very few reallocations, and the amortized cost per append is O(1).

Misconception 3: "Slicing a list is free."
Reality: `lst[a:b]` allocates a new list object and copies `b-a` pointers into it. The pointers are copied (shallow), not the objects they reference, but the copy itself is O(k) where k is the slice length.

---

## Why It Matters in Practice

The single most common list performance mistake in Python code is building a list by repeatedly inserting at position 0  -  `lst.insert(0, item)` or `lst = [item] + lst`. Each call shifts all existing elements, turning an O(n) process into O(n²) overall. Switching to `collections.deque` and `appendleft` reduces this to O(n). The second most common mistake is concatenating strings inside a loop using `list_of_strings[i] + new_string` and then joining  -  but this applies to strings; for lists themselves, `extend` and `+=` are in-place and efficient.

Understanding allocated vs. length capacity also matters when holding large lists in long-lived objects. A list that once held a million items and was trimmed to ten still holds the full one-million-slot allocation. Calling `copy()` or slicing `[:]` produces a new list sized tightly to the current length, reclaiming the excess memory.

---

## Interview Angle

Common question forms:
- "What is the time complexity of `list.append` vs `list.insert(0, x)`?"
- "How does Python implement dynamic arrays internally?"
- "Why can't you use a list as a dict key?"

Answer frame:
A strong answer explains that lists are backed by a C array of PyObject pointers (not a linked list), that `append` is O(1) amortized because of over-allocation via `list_resize`, that `insert(0, x)` is O(n) due to `memmove`, and that mutability prevents hashing. Bonus: mention the `ob_item` field and the growth formula `n + (n >> 3) + 6`.

---

## Related Notes

- [[tuples|Tuples]]
- [[collections-module|collections Module]]
- [[mutability|Mutability]]
- [[reference-counting|Reference Counting]]
- [[python-memory-model|Python Memory Model]]
