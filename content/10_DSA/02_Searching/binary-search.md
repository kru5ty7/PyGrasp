---
title: 28 - Binary Search
description: Binary search finds a target in a sorted array by repeatedly halving the search space, achieving O(log n) time by eliminating half the remaining candidates with each comparison.
tags: [dsa, layer-10, searching, binary-search]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Binary Search

> Binary search is deceptively simple to describe and surprisingly easy to implement incorrectly — mastering its loop invariant and boundary conditions is an essential skill.

---

## Quick Reference

**Core idea:**
- Maintain a search window `[lo, hi]` that is guaranteed to contain the target if it exists
- Compute the midpoint `mid = lo + (hi - lo) // 2` and compare `arr[mid]` to the target
- If equal: found. If target is less: search the left half. If target is greater: search the right half.
- Repeat until the window is empty (lo > hi)
- O(log n) time, O(1) space (iterative); O(log n) space (recursive due to call stack)
- Critical precondition: the array must be sorted

**Tricky points:**
- The midpoint formula `(lo + hi) // 2` can overflow in languages with fixed-width integers; `lo + (hi - lo) // 2` is safe (Python integers are unbounded, but the safe form is good habit)
- The loop condition is `lo <= hi` for exact-match search; `lo < hi` for finding insertion points — using the wrong one causes off-by-one errors
- After the loop exits with the target not found, `lo` is the insertion point where the target would belong
- Closed interval `[lo, hi]` vs half-open interval `[lo, hi)` are two valid formulations — choose one consistently and never mix them
- Python's `bisect` module provides production-quality binary search implementations

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case (target at midpoint) | O(1) | O(1) |
| Average case | O(log n) | O(1) |
| Worst case | O(log n) | O(1) |

---

## What It Is

Picture a dictionary — a physical one with thousands of pages — and the task of finding the word "palindrome." Nobody opens the dictionary at page 1 and reads forward. Instead, you open to roughly the middle. If the page shows words beginning with "M," you know "palindrome" starts with "P," so the left half of the dictionary is irrelevant. You open to the middle of the right half. Now you see words beginning with "S," so "palindrome" is in the left portion of that half. You keep bisecting. Within about a dozen page-openings, you reach the exact page. This is binary search: each step eliminates half the remaining candidates, reducing the problem size exponentially.

The guarantee of O(log n) follows directly from this halving. An array of 1,000 elements requires at most 10 comparisons (2^10 = 1024). An array of one million elements requires at most 20 comparisons (2^20 ≈ 1,000,000). An array of one billion elements requires at most 30 comparisons. This logarithmic growth is extraordinarily efficient and is one of the most consequential properties in computer science. For any sorted data structure where random access is available, binary search is almost always the right search algorithm.

The absolute requirement for sorted input is the algorithm's only constraint, and it is non-negotiable. The halving step works because a comparison with the midpoint tells you definitively which half the target belongs to — but only if the elements are in order. With unsorted data, knowing that arr[mid] is smaller than the target tells you nothing about where the target is. The precondition "array is sorted" is the entire reason binary search works. If the array is not sorted, binary search gives incorrect results silently — it will not raise an error, it will return a wrong answer.

---

## How It Actually Works

The iterative implementation maintains two pointers, `lo` and `hi`, representing the current search window as a closed interval `[lo, hi]`. Initially `lo = 0` and `hi = len(arr) - 1`, representing the entire array. In each iteration, it computes the midpoint and compares the element at that position to the target. If equal, it returns the index. If the target is smaller than `arr[mid]`, the right half is discarded by setting `hi = mid - 1`. If the target is larger, the left half is discarded by setting `lo = mid + 1`. The loop continues as long as `lo <= hi`; when `lo > hi`, the search window is empty and the target is not present.

The recursive implementation expresses the same logic in a more natural recursive form: base case is an empty window (lo > hi), recursive case picks a midpoint and recurses on one half. The iterative form is preferred in practice because it uses O(1) space; the recursive form uses O(log n) call stack space.

```python
def binary_search(arr: list, target) -> int:
    """Iterative binary search: O(log n) time, O(1) space.
    Returns index of target, or -1 if not found. Array must be sorted."""
    lo, hi = 0, len(arr) - 1
    while lo <= hi:
        # Safe midpoint: avoids overflow in fixed-width integer languages
        mid = lo + (hi - lo) // 2
        if arr[mid] == target:
            return mid
        elif arr[mid] < target:
            lo = mid + 1   # target is in the right half
        else:
            hi = mid - 1   # target is in the left half
    return -1  # target not found


def binary_search_recursive(arr: list, target, lo: int = 0, hi: int = None) -> int:
    """Recursive binary search: O(log n) time, O(log n) space."""
    if hi is None:
        hi = len(arr) - 1
    if lo > hi:
        return -1  # base case: empty window
    mid = lo + (hi - lo) // 2
    if arr[mid] == target:
        return mid
    elif arr[mid] < target:
        return binary_search_recursive(arr, target, mid + 1, hi)
    else:
        return binary_search_recursive(arr, target, lo, mid - 1)


# Demonstration
data = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
print(binary_search(data, 7))    # 3
print(binary_search(data, 6))    # -1
print(binary_search(data, 1))    # 0
print(binary_search(data, 19))   # 9


# Python's bisect module — production-quality binary search
import bisect

sorted_list = [1, 3, 5, 7, 9, 11]

# bisect_left: index where target would be inserted (leftmost position)
print(bisect.bisect_left(sorted_list, 7))   # 3 (exact match position)
print(bisect.bisect_left(sorted_list, 6))   # 3 (insertion point for 6)

# bisect_right: index after the last existing occurrence
print(bisect.bisect_right(sorted_list, 7))  # 4

# insort: insert while maintaining sort order — O(log n) search + O(n) insert
bisect.insort(sorted_list, 6)
print(sorted_list)  # [1, 3, 5, 6, 7, 9, 11]

# Check if a value exists using bisect_left
def contains(arr, target):
    i = bisect.bisect_left(arr, target)
    return i < len(arr) and arr[i] == target

print(contains(sorted_list, 7))   # True
print(contains(sorted_list, 4))   # False
```

---

## Visualizer

<iframe src="/static/visualizers/binary-search.html" style="width:100%;height:400px;border:none;border-radius:8px;" title="Binary Search Visualizer"></iframe>

---

## How It Connects

Binary search is one of the most important applications of the divide-and-conquer pattern: each step reduces the problem size by half, leading directly to O(log n) complexity. The binary search tree data structure extends this idea by building the sorted structure into a tree rather than a flat array, allowing O(log n) search along with O(log n) insertion and deletion. Understanding the loop invariant of binary search — that the target is in `[lo, hi]` if it exists — is the foundation for understanding the variations that handle duplicate elements and finding boundary positions.

[[divide-and-conquer|Divide and Conquer]]
[[binary-search-variations|Binary Search Variations]]
[[binary-search-trees|Binary Search Trees]]

---

## Common Misconceptions

Misconception 1: "Binary search is always faster than linear search."
Reality: For very small arrays, linear search is faster in practice because it has lower overhead — no midpoint computation, no conditional branching, and sequential memory access that the CPU cache handles efficiently. The crossover point is typically around 10-20 elements depending on the hardware and data type. Binary search's advantage becomes dominant as n grows. For n = 5, linear search is fine; for n = 5,000, binary search is essential.

Misconception 2: "Binary search works on any sorted collection."
Reality: Binary search requires O(1) random access — the ability to jump directly to index mid without traversing from the beginning. It works on arrays and Python lists (which are arrays under the hood). It does not work directly on linked lists, because computing `arr[mid]` on a linked list requires O(n/2) time to traverse to that position, making the overall complexity O(n log n) — worse than linear search. For sorted linked lists, you need skip lists or balanced BSTs to achieve O(log n) search.

Misconception 3: "Using `(lo + hi) // 2` for the midpoint is fine in Python."
Reality: In Python, this expression is correct because Python integers have arbitrary precision and do not overflow. However, using `lo + (hi - lo) // 2` is a better habit because it translates safely to C, Java, and other languages with fixed-width integers where `lo + hi` could overflow a 32-bit integer for large arrays. Many interview problems expect you to write code that would also work in C++, and the safe form demonstrates awareness of this issue.

---

## Why It Matters in Practice

Binary search is the correct algorithm for searching sorted data in virtually every situation. It appears not just as a standalone search but as an internal component of many other algorithms: finding insertion points, determining where a condition transitions from false to true (predicate-based binary search), searching in sorted databases, and autocomplete systems all use binary search in some form. Python's `bisect` module provides a production-ready implementation that handles edge cases and is faster than a hand-rolled version due to its C implementation.

In practice, the most common use of binary search is `bisect.bisect_left` and `bisect.bisect_right` for maintaining sorted lists and performing range queries. If you find yourself writing a while loop to search a sorted list, reach for `bisect` instead — it is well-tested, faster, and expresses the intent more directly.

---

## Interview Angle

Common question forms:
- "Implement binary search."
- "What is the time complexity of binary search and why?"
- "What is the difference between bisect_left and bisect_right?"
- "Binary search on a rotated sorted array."

Answer frame:
Implement the iterative form with the closed-interval invariant `[lo, hi]`. Use `lo + (hi - lo) // 2` for the midpoint and explain why. State O(log n) and give the intuition (each step halves the search space). For bisect_left vs bisect_right: both find the target's position, but left gives the leftmost index where the target could be inserted (before existing occurrences), right gives the rightmost (after existing occurrences) — this matters when duplicates are present. For rotated sorted array: identify which half is sorted (one half always is), check whether the target lies in the sorted half, and recurse on the appropriate partition.

---

## Related Notes

- [[linear-search|Linear Search]]
- [[binary-search-variations|Binary Search Variations]]
- [[binary-search-trees|Binary Search Trees]]
- [[divide-and-conquer|Divide and Conquer]]
