---
title: 07 - Deques
description: A deque (double-ended queue) supports O(1) insertion and removal at both ends, making it the correct structure for queue and sliding-window operations in Python.
tags: [dsa, layer-10, deque, double-ended-queue]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Deques

> A deque is a sequence that is equally open at both ends — it is both a queue and a stack in one structure, and Python's `collections.deque` is the correct implementation for any algorithm that needs O(1) access at either end.

---

## Quick Reference

**Core idea:**
- O(1) `append` (right end) and `appendleft` (left end)
- O(1) `pop` (right end) and `popleft` (left end)
- Implemented internally as a doubly linked list of fixed-size blocks
- `maxlen` parameter creates a fixed-capacity deque that auto-evicts the oldest element
- The canonical Python replacement for any queue operation that would otherwise use `list.pop(0)`

**Tricky points:**
- `deque[i]` index access is O(n) — it traverses the linked list; do not use a deque when random access is needed
- `deque` does not support slicing (`d[1:3]` raises TypeError)
- `list.pop(0)` is O(n) — the single most common queue performance mistake in Python
- Rotating (`deque.rotate(k)`) is O(k) not O(1), but efficient for small k
- A deque with `maxlen` does not raise an error when it fills up — it silently evicts the oldest element

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| append (right) | O(1) | O(1) |
| appendleft (left) | O(1) | O(1) |
| pop (right) | O(1) | O(1) |
| popleft (left) | O(1) | O(1) |
| Access by index | O(n) | O(n) |
| Search (in operator) | O(n) | O(n) |
| len() | O(1) | O(1) |

Space complexity: O(n)

---

## What It Is

Picture a tube of tennis balls that is open at both ends. You can push a ball in from either end, and you can pull a ball out from either end. If you only ever push from the right and pull from the left, you have a standard queue. If you only ever push and pull from the right, you have a stack. The tube does not care — it supports both patterns equally well. This is the deque: a structure that places no restriction on which end you use.

The most practically important use is replacing the queue anti-pattern. In Python, many developers implement a queue using a `list`, calling `append` to enqueue and `pop(0)` to dequeue. This looks correct and produces the right output, but `pop(0)` is O(n) because it shifts every remaining element one position left. A deque's `popleft` does the same logical thing in O(1) by maintaining a pointer to the leftmost block, so no shifting is required. At small sizes this is invisible; at ten thousand operations per second the difference is catastrophic.

The `maxlen` parameter produces a rolling window structure. When `maxlen=5` is set and you `append` a sixth element, the leftmost element is automatically evicted. This is exactly the semantic needed for a moving average, a recent-events log, or any "last N items" buffer. The deque handles the eviction without any conditional logic in the caller — the structure enforces its own size constraint.

---

## How It Actually Works

CPython's `collections.deque` is implemented in C as a doubly linked list of fixed-size blocks, where each block holds 64 elements (this is a CPython implementation detail). Rather than allocating a separate heap node per element (which would be expensive for memory allocation and cache performance), blocks of 64 elements are allocated and chained together. New elements are appended to the current rightmost block until it fills, then a new block is allocated and linked in. The same happens on the left. This design gives O(1) amortized operations at both ends while being significantly more cache-friendly than a true node-per-element linked list.

Index access, `d[i]`, is O(n) because there is no direct index-to-block calculation. CPython does optimise access from the nearer end — `d[0]` and `d[-1]` are O(1) because the head and tail block pointers are directly tracked. But `d[500]` for a deque of 1000 elements requires traversing 7 or 8 blocks from either end.

```python
from collections import deque

# ---- Basic operations ----
d = deque([1, 2, 3])

d.append(4)         # right end — O(1)
d.appendleft(0)     # left end — O(1)
print(d)            # deque([0, 1, 2, 3, 4])

right = d.pop()     # remove and return rightmost — O(1)
left = d.popleft()  # remove and return leftmost — O(1)
print(d)            # deque([1, 2, 3])
print(right, left)  # 4, 0

# Peek without removing
print(d[0])         # 1 — leftmost, O(1)
print(d[-1])        # 3 — rightmost, O(1)


# ---- Sliding window maximum ----
# Classic problem: for each window of size k in an array,
# find the maximum value. Deque stores indices in decreasing value order.
def sliding_window_max(nums, k):
    d = deque()   # stores indices, decreasing value order
    result = []
    for i, num in enumerate(nums):
        # Remove indices outside the window
        while d and d[0] < i - k + 1:
            d.popleft()
        # Remove indices of smaller elements — they can never be the max
        while d and nums[d[-1]] < num:
            d.pop()
        d.append(i)
        if i >= k - 1:
            result.append(nums[d[0]])  # front is always the max in window
    return result

print(sliding_window_max([1, 3, -1, -3, 5, 3, 6, 7], 3))
# [3, 3, 5, 5, 6, 7]


# ---- Fixed-size rolling window with maxlen ----
recent = deque(maxlen=5)
for i in range(8):
    recent.append(i)
    print(list(recent))
# Older elements are automatically evicted:
# [0], [0,1], [0,1,2], [0,1,2,3], [0,1,2,3,4],
# [1,2,3,4,5], [2,3,4,5,6], [3,4,5,6,7]


# ---- Palindrome check ----
def is_palindrome(s):
    d = deque(s.lower().replace(" ", ""))
    while len(d) > 1:
        if d.popleft() != d.pop():
            return False
    return True

print(is_palindrome("racecar"))    # True
print(is_palindrome("hello"))      # False


# ---- Rotate operation ----
d = deque([1, 2, 3, 4, 5])
d.rotate(2)    # shift right by 2: [4, 5, 1, 2, 3]
print(d)
d.rotate(-2)   # shift left by 2: back to [1, 2, 3, 4, 5]
print(d)
```

---

## Visualizer

<iframe src="/visualizers/deque.html" style="width:100%;height:380px;border:none;border-radius:8px;" title="Deque Visualizer"></iframe>

---

## How It Connects

Queues are the direct conceptual ancestor of deques — a deque is a generalised queue where both ends are equally accessible. Understanding why `list.pop(0)` is wrong for a queue and why `deque.popleft()` is right requires understanding the deque's internal structure.

[[queues|Queues]]

Doubly linked lists are the internal mechanism that gives deques their O(1) end operations. CPython's deque is a doubly linked list of fixed-size blocks, which is why index access is O(n) while end access is O(1).

[[doubly-linked-lists|Doubly Linked Lists]]

---

## Common Misconceptions

Misconception 1: "deque is just a list with a different name."
Reality: A deque is a structurally different data structure. A Python `list` is a contiguous array of pointers; a `deque` is a doubly linked list of fixed-size blocks. They have different performance characteristics: list is O(1) random access, O(n) front operations; deque is O(n) random access, O(1) front operations. They are not interchangeable for all use cases.

Misconception 2: "deque[i] is O(1) because collections.deque is highly optimised."
Reality: Index access on a deque is O(n). It traverses the linked blocks to find the requested index. CPython optimises access from either end — `d[0]` and `d[-1]` are O(1) — but arbitrary index access is not. This is why deque does not support slicing.

Misconception 3: "Setting maxlen evicts elements when you try to add and it's full — it raises an error or returns False."
Reality: When a deque with `maxlen` is full, appending a new element silently removes the element at the opposite end. `append` evicts from the left; `appendleft` evicts from the right. No exception is raised and no return value signals the eviction.

---

## Why It Matters in Practice

The sliding window pattern appears in a large category of algorithm problems: maximum or minimum in a sliding window, moving averages, rate limiters, and shortest substring problems. A deque is the efficient enabler of the monotonic queue pattern, where you maintain a deque of candidate elements in sorted order, appending new candidates on the right and removing expired ones from the left. Without O(1) operations at both ends, this pattern degrades to O(n) per window position.

In production Python, `collections.deque` is the correct container for any queue or sliding-buffer use case. Every Python web framework, task queue, and streaming data pipeline that implements its own buffering logic should use deque rather than list for these operations. The performance difference is invisible in tests and CI, and catastrophic in production at sustained load.

---

## Interview Angle

Common question forms:
- "Sliding window maximum — find the max in each window of size k."
- "Implement a queue with O(1) enqueue and dequeue."
- "Why should you not use a list as a queue in Python?"
- "Implement a recent-calls counter that returns the number of calls in the last 3000 milliseconds."

Answer frame:
For the sliding window maximum, name the monotonic deque pattern: maintain a deque of indices in decreasing value order, evicting indices outside the window from the left and smaller elements from the right before inserting. For the queue question, immediately name `collections.deque` and explain the O(n) cost of `list.pop(0)`. For the recent-calls counter (LeetCode 933), describe using a deque with `appendleft` and evicting timestamps older than 3000ms from the right.

---

## Related Notes

- [[queues|Queues]]
- [[stacks|Stacks]]
- [[arrays|Arrays]]
