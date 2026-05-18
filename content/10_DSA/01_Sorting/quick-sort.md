---
title: 22 - Quick Sort
description: A divide-and-conquer sorting algorithm that partitions an array around a pivot element and recursively sorts each partition, achieving O(n log n) average time in-place.
tags: [dsa, layer-10, sorting, quick-sort, divide-and-conquer]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Quick Sort

> Quick sort is the most commonly asked sorting algorithm in interviews and the fastest in-memory sort in practice — understanding its pivot strategies and worst-case behaviour is essential.

---

## Quick Reference

**Core idea:**
- Choose a pivot element; partition the array so all elements less than the pivot come before it and all greater elements come after it
- The pivot is now in its final sorted position
- Recursively apply the same process to the left and right partitions
- O(n log n) average case, O(n²) worst case (sorted input with naive pivot)
- In-place: O(log n) stack space (average), O(n) worst case
- Not stable in standard form

**Tricky points:**
- The worst case is O(n²) when the pivot is always the minimum or maximum — this happens with sorted/reverse-sorted input and a "first element" pivot strategy
- Random pivot selection reduces the probability of worst-case behaviour to negligibly small
- Median-of-three (take the median of first, middle, last) is a common production optimisation
- Quick sort is not stable: the partition step moves equal elements relative to the pivot without preserving order
- Python's `sorted()` and `list.sort()` use Timsort, not quick sort; but quick sort is the canonical interview algorithm
- The Lomuto partition scheme is simpler to implement; the Hoare partition scheme is more efficient (fewer swaps)

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case | O(n log n) | O(log n) |
| Average case | O(n log n) | O(log n) |
| Worst case (sorted + first-element pivot) | O(n²) | O(n) |

---

## What It Is

Imagine a librarian who needs to sort a shelf of books by publication year. Her strategy: pick one book at random, set it aside, and push all books published before it to the left end of the shelf and all books published after it to the right end. Now her chosen book has found its exact correct position — everything to its left belongs there, everything to its right belongs there. She then applies the same strategy independently to the left group and the right group, each time picking a book, partitioning around it, and recursing. Eventually every book has been the chosen partitioning book exactly once, and the shelf is sorted.

This partitioning insight is the heart of quick sort. Unlike merge sort, which splits blindly at the midpoint and does all the real work during the merge, quick sort does all its real work during the partition step. After partitioning, the pivot element is in its permanently correct position and never needs to move again. The two sub-problems are genuinely smaller and independent — they can be solved in any order. When the partitioning is balanced (pivot near the median), each level of recursion processes O(n) total elements and there are O(log n) levels, giving O(n log n) total work.

The weak point is pivot selection. If you always pick the first element as the pivot and the input happens to be sorted or reverse-sorted, every partition step places all elements on one side of the pivot, creating sub-problems of size n-1 and 0 instead of n/2 and n/2. The recursion depth becomes O(n) and the total work becomes O(n²). This is why pivot selection strategy matters enormously for quick sort's real-world performance. Random pivot selection ensures that worst-case input cannot be engineered by an adversary, and reduces the expected recursion depth to O(log n) regardless of input order.

---

## How It Actually Works

The Lomuto partition scheme picks the last element as the pivot. It maintains a boundary index i that tracks where elements smaller than the pivot end. It scans from left to right; whenever it finds an element smaller than the pivot, it swaps that element with the element at the boundary and advances the boundary. After the scan, it swaps the pivot from its position at the end into the boundary position. At this point, arr[0..boundary-1] are all less than the pivot, arr[boundary] is the pivot in its final position, and arr[boundary+1..end] are all greater than or equal to the pivot.

The random pivot variant simply picks a random index, swaps that element to the end, and then applies Lomuto partitioning. This one change eliminates the worst-case vulnerability against sorted input with negligible overhead. In practice, a random pivot or median-of-three pivot is always used in production code.

```python
import random


def quick_sort(arr: list) -> list:
    """Quick sort with random pivot: O(n log n) expected, in-place."""
    arr = arr[:]  # work on a copy
    _quick_sort(arr, 0, len(arr) - 1)
    return arr


def _quick_sort(arr: list, lo: int, hi: int) -> None:
    if lo >= hi:
        return
    pivot_idx = _partition(arr, lo, hi)
    _quick_sort(arr, lo, pivot_idx - 1)
    _quick_sort(arr, pivot_idx + 1, hi)


def _partition(arr: list, lo: int, hi: int) -> int:
    """Lomuto partition with random pivot selection."""
    # Randomly choose pivot and move it to the end
    rand_idx = random.randint(lo, hi)
    arr[rand_idx], arr[hi] = arr[hi], arr[rand_idx]

    pivot = arr[hi]
    i = lo - 1  # boundary: arr[lo..i] < pivot

    for j in range(lo, hi):
        if arr[j] <= pivot:
            i += 1
            arr[i], arr[j] = arr[j], arr[i]

    # Place pivot in its final position
    arr[i + 1], arr[hi] = arr[hi], arr[i + 1]
    return i + 1


# Demonstration
data = [3, 6, 8, 10, 1, 2, 1]
print(quick_sort(data))  # [1, 1, 2, 3, 6, 8, 10]

# Worst-case input for naive first-element pivot — random pivot handles this fine
sorted_data = list(range(1000))
print(quick_sort(sorted_data)[:5])  # [0, 1, 2, 3, 4]
```

---

## How It Connects

Quick sort is the most prominent application of the divide-and-conquer paradigm alongside merge sort. The difference between them reveals the two sides of the strategy: quick sort's work happens during the divide (partition) step; merge sort's work happens during the combine (merge) step. The partition operation also appears independently as "find the k-th smallest element" — Quickselect uses a single partition step without full recursion to solve this in O(n) average time.

[[divide-and-conquer|Divide and Conquer]]
[[merge-sort|Merge Sort]]
[[heap-sort|Heap Sort]]
[[sorting-comparison|Sorting Algorithm Comparison]]

---

## Common Misconceptions

Misconception 1: "Quick sort is always faster than merge sort."
Reality: Quick sort has better average-case performance and cache behaviour than merge sort for in-memory sorting of random data, and it avoids merge sort's O(n) extra space cost. However, quick sort's worst case is O(n²) while merge sort guarantees O(n log n). For stable sorting, linked-list sorting, or external sorting, merge sort is preferred. "Faster" depends heavily on the input distribution and the specific use case.

Misconception 2: "Python's sort uses quick sort."
Reality: Python's `list.sort()` and `sorted()` use Timsort, a hybrid of merge sort and insertion sort. Timsort was designed specifically to outperform both pure merge sort and quick sort on the kinds of partially-sorted data that appear in real programs. Quick sort does not appear in CPython's sort implementation.

Misconception 3: "The worst case for quick sort can be avoided by always sorting a pre-shuffled array."
Reality: Pre-shuffling the input before sorting is one approach, but it requires O(n) time and modifies the input. Random pivot selection achieves the same probabilistic guarantee without touching the input order, with only a constant amount of extra work per partition. Median-of-three pivot selection also eliminates the sorted-input worst case while being fully deterministic.

---

## Why It Matters in Practice

Quick sort's in-place operation (O(log n) stack space, no auxiliary array) and excellent cache performance make it the practical choice for large-scale in-memory sorting when O(n log n) average complexity and O(1) extra memory are desired. Many systems languages and standard libraries use introsort — a hybrid that starts with quick sort and switches to heap sort when the recursion depth exceeds a threshold — to guarantee O(n log n) worst case while retaining quick sort's average-case speed.

In interviews, quick sort is the most commonly tested sorting algorithm because it requires understanding pivot selection, partitioning logic, recursion, and complexity analysis simultaneously. Being able to implement the Lomuto or Hoare partition cleanly, explain the worst-case scenario and its cause, and discuss the random pivot fix demonstrates fluency with all three.

---

## Interview Angle

Common question forms:
- "Implement quick sort."
- "What is the worst case for quick sort and how do you avoid it?"
- "Compare quick sort and merge sort."
- "What is Quickselect?"

Answer frame:
Describe the partition step as the key operation: pivot goes to its final position, all smaller elements left, all greater elements right. Implement Lomuto partition clearly. State average O(n log n) and worst-case O(n²), explain that worst case occurs when pivot is always the extreme element (sorted input with first-element pivot). Explain random pivot selection as the fix. For the comparison: quick sort is in-place and cache-friendly but not stable and has a quadratic worst case; merge sort is stable and guarantees O(n log n) but uses O(n) extra space. For Quickselect: instead of recursing on both partitions, recurse only on the partition containing the k-th element — O(n) average.

---

## Related Notes

- [[merge-sort|Merge Sort]]
- [[heap-sort|Heap Sort]]
- [[divide-and-conquer|Divide and Conquer]]
- [[python-sort-internals|Timsort — Python's Sorting Algorithm]]
- [[sorting-comparison|Sorting Algorithm Comparison]]
