---
title: 02 - Arrays
description: Arrays store elements in contiguous memory blocks, enabling O(1) random access by index.
tags: [dsa, layer-10, arrays, contiguous-memory]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Arrays

> Arrays are the most fundamental data structure in computing — a fixed block of memory cells numbered from zero, forming the backbone of nearly every other structure built on top of them.

---

## Quick Reference

**Core idea:**
- Elements stored in contiguous (adjacent) memory locations
- Index-based access is O(1) because the address of element i is: base_address + i × element_size
- Python's `list` is a dynamic array — it over-allocates and resizes by doubling when full
- CPython stores a list as an array of pointers to PyObject structs, not the objects directly
- Append to end is O(1) amortized; insert/delete in the middle is O(n) due to shifting

**Tricky points:**
- Python lists are not fixed-size like C arrays — they resize automatically, which has cost implications
- `list.insert(0, x)` is O(n) — it shifts every existing element one position to the right
- `list.pop(0)` is O(n) — same problem, shifts all remaining elements left
- Accessing an index out of bounds raises IndexError, not undefined behaviour like in C
- Negative indices in Python are syntactic sugar: `lst[-1]` is `lst[len(lst) - 1]`

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Access by index | O(1) | O(1) |
| Search (unsorted) | O(n) | O(n) |
| Insert at end (append) | O(1) amortized | O(n) on resize |
| Insert at middle/start | O(n) | O(n) |
| Delete at end (pop) | O(1) | O(1) |
| Delete at middle/start | O(n) | O(n) |

Space complexity: O(n)

---

## What It Is

Imagine a row of numbered post-office boxes mounted on a wall. Box 0 is at the far left, box 1 is immediately to its right, and so on in a perfectly straight, unbroken line. If you know you want box 47, you walk directly to it — no searching, no following directions from one box to the next. The boxes are physically adjacent, and their numbers are sequential, so the position of any box is immediately calculable. This is the defining feature of an array: contiguous storage that makes positional access instant.

Now imagine that wall of post-office boxes is fully occupied and a new letter arrives for a forty-ninth tenant. You have two choices: refuse the letter, or build a bigger wall, move all existing boxes to the new wall, and add the new one. The first option describes a fixed-size array; the second describes a dynamic array. Python's `list` uses the dynamic approach, and it is clever about it — rather than building a wall for exactly one more box every time, it builds a wall with extra capacity, so that the next several additions are free. Only when that extra capacity runs out does it build again, this time even bigger. On average, every addition still only costs one unit of work.

The real-world impact of contiguous memory goes beyond the arithmetic of address calculation. Modern CPUs have caches that load chunks of memory at a time. When you access element 0 of an array, elements 1 through 15 (or more) are often loaded into cache alongside it. Iterating through an array therefore benefits from this spatial locality — consecutive accesses are served from fast cache rather than slow main memory. This is one reason arrays outperform linked lists in practice even when their theoretical complexity is identical.

---

## How It Actually Works

In CPython, a `list` object contains a pointer to an array of pointers. Each slot in that pointer array holds the memory address of a Python object — so when you store integers, strings, or custom objects in a list, what actually lives in the contiguous block is a sequence of 8-byte pointers (on a 64-bit system), not the objects themselves. The objects are scattered across the heap. This design allows lists to hold heterogeneous types, because every slot is the same size regardless of what it points to.

When you call `lst.append(x)`, CPython checks whether `len(lst) < lst.allocated`. If capacity remains, it places the pointer at the next available slot and increments the length counter — this is O(1). When capacity is exhausted, CPython calls a resize function that allocates a new, larger pointer array. The growth formula used in CPython is not exactly doubling; it uses `new_size = (old_size * 9 // 8) + 6` for small lists, transitioning toward roughly 1.125× growth. The entire existing array is then copied to the new allocation, and the old one is freed. This is the occasional O(n) cost that makes append O(1) amortized rather than O(1) proper.

```python
import sys

# Basic array operations
lst = [10, 20, 30, 40, 50]

# O(1) random access
print(lst[2])        # 30
print(lst[-1])       # 50 — negative indexing

# O(n) search
print(42 in lst)     # False — scans every element
print(lst.index(30)) # 2 — linear scan until found

# O(1) amortized append
lst.append(60)

# O(n) insert at position — shifts elements right
lst.insert(0, 0)     # [0, 10, 20, 30, 40, 50, 60]

# O(n) delete from front — shifts elements left
lst.pop(0)           # removes 0, shifts all others left

# O(1) delete from end
lst.pop()            # removes 60, no shifting needed

# Observe over-allocation
a = []
prev = sys.getsizeof(a)
for i in range(20):
    a.append(i)
    curr = sys.getsizeof(a)
    if curr != prev:
        print(f"Resized at len={len(a)}: {prev} -> {curr} bytes, allocated for ~{(curr - 56) // 8} slots")
        prev = curr

# Slicing creates a new list — O(k) where k is slice length
sub = lst[1:3]       # new list object, copies pointers

# List comprehension — O(n)
squares = [x ** 2 for x in range(10)]
```

---

## How It Connects

Big O Notation provides the formal framework for all the complexity claims made about arrays — the reason we say O(1) for index access and O(n) for insertion is grounded in what Big O actually measures. Understanding amortized analysis is essential to correctly describing why append is O(1).

[[big-o-notation|Big O Notation]]

Linked lists exist precisely because arrays have expensive middle insertion and deletion. The contrast between the two structures is the most common introductory data structure comparison, and knowing arrays deeply makes the linked list's trade-offs immediately clear.

[[linked-lists|Linked Lists]]

Python's built-in list type is the direct implementation of a dynamic array. Understanding that a Python list is an array of object pointers — not a raw value array — explains memory behaviour, the cost of `copy()`, and why lists of large objects have the same per-element cost as lists of small integers.

[[lists|Python Lists]]

---

## Common Misconceptions

Misconception 1: "Python lists are slow because they're dynamic."
Reality: Dynamic resizing adds amortized cost only on growth, and the growth formula minimises the number of resizes. For sequential appends, Python lists are extremely fast in practice. The real performance penalty comes from O(n) operations like `insert(0, x)` or `pop(0)`, not from being dynamic.

Misconception 2: "Random access is O(1) because Python is doing something clever."
Reality: Random access is O(1) because of elementary arithmetic. The pointer array is contiguous in memory, so the address of element i is the base address plus i times the pointer size. This requires one multiplication and one addition — a fixed number of operations regardless of n.

Misconception 3: "list.copy() is O(1) because it's just copying a reference."
Reality: `list.copy()` creates a new list and copies all n pointers into it. That is O(n). The objects themselves are not copied (it is a shallow copy), but the pointer array must be duplicated in full.

---

## Why It Matters in Practice

Arrays are the default choice for ordered collections because their cache-friendly memory layout and O(1) access make them fast for the operations that matter most: building up a collection incrementally (append), reading elements by position, and iterating through all elements. Almost every Python program uses lists as the primary in-memory data store.

Knowing when arrays become the wrong choice is equally important. If your algorithm frequently inserts or deletes at arbitrary positions, the O(n) shifting cost compounds quickly at scale. A data set of one million items where you insert at the front on every operation gives you a billion pointer-shifts per run. In those cases, a different structure — linked list, deque, or sorted container — is the correct tool.

---

## Interview Angle

Common question forms:
- "What is the time complexity of inserting at the beginning of a list?"
- "Why is Python's list append O(1) amortized and not strictly O(1)?"
- "When would you choose a linked list over an array?"
- "What happens internally when a Python list runs out of capacity?"

Answer frame:
Describe the contiguous memory model first, then derive the complexity from first principles — O(1) access because address is calculated directly, O(n) insert/delete because of shifting. For the amortized append question, describe the over-allocation strategy, explain that resize is O(n) but happens rarely enough that the average across all appends is O(1). For the linked list comparison, frame it as a trade-off: arrays win on access and cache locality, linked lists win on mid-sequence insertion and deletion.

---

## Related Notes

- [[big-o-notation|Big O Notation]]
- [[linked-lists|Linked Lists]]
- [[deques|Deques]]
