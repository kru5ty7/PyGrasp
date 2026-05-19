---
title: 29 - Binary Search Variations
description: Binary search applied to finding boundary positions, insertion points, searching rotated arrays, and solving optimisation problems by searching on the answer rather than the array.
tags: [dsa, layer-10, searching, binary-search]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Binary Search Variations

> Every binary search variation follows the same pattern: define what `lo` and `hi` represent, write the predicate that determines which half to discard, and decide what to return when the loop exits.

---

## Quick Reference

**Core idea:**
- All binary search variations share one template: maintain invariants about `lo` and `hi`, shrink the window by half each step, and return the correct boundary when done
- Find first occurrence (left boundary): find the leftmost index where `arr[i] == target`
- Find last occurrence (right boundary): find the rightmost index where `arr[i] == target`
- Find insertion point: find where `target` belongs in the sorted array (Python's `bisect_left`)
- Search on the answer: given a monotone predicate `f(x)`, find the minimum x where `f(x)` is True
- Search in rotated sorted array: one partition is always fully sorted - identify it and check if target lies there

**Tricky points:**
- The left-boundary and right-boundary searches look nearly identical; the only difference is whether you move left or right when `arr[mid] == target`
- For the search-on-the-answer template, the predicate must be monotone: False for some prefix, then True for all values from some threshold onward
- When the loop exits, `lo` is the answer for left-boundary searches (smallest valid index)
- Using `mid = lo + (hi - lo) // 2` biases toward the lower middle - for right-boundary searches, some templates need `mid = lo + (hi - lo + 1) // 2` to avoid infinite loops with a two-element window
- Python's `bisect_left` implements the left-boundary/insertion-point search; `bisect_right` implements the right-boundary variant

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case | O(1) | O(1) |
| Average case | O(log n) | O(1) |
| Worst case | O(log n) | O(1) |

---

## What It Is

The basic binary search for an exact match is the simplest application of a more general principle: given a sorted space of possibilities and a question that can be answered "too small," "correct," or "too large," you can find the answer in O(log n) steps by halving the space at each step. Once you internalise this principle, you start seeing binary search in places that do not look like array searches at all.

Consider a software engineer debugging a regression: they know their code worked at some commit in the past and is broken now, and they need to find which specific commit introduced the bug. A linear scan means testing each commit from oldest to newest - O(n) test runs. But if "broken" is a monotone property (once the commit that introduced the bug is passed, all later commits are also broken), binary search applies: test the middle commit, determine whether it is broken or not, and eliminate half the remaining commits. This is `git bisect`, which is literally binary search on a commit history. The array is not an array; it is a timeline of commits.

This generalisation - binary search on the answer rather than the array - is one of the most powerful algorithmic patterns. Many optimisation problems ask: "what is the minimum value of X such that some condition holds?" If the condition is monotone in X (false for small X, true for large X), you can binary search on X directly, calling a predicate function at each midpoint. The predicate function might be arbitrarily complex: simulate a process, run a greedy algorithm, compute a sum. As long as it is monotone, binary search finds the minimum satisfying X in O(log(range)) iterations times the cost of one predicate evaluation.

---

## How It Actually Works

All binary search variations follow one of two templates. The first template finds an exact match (returning mid when arr[mid] == target). The second template finds a boundary position, where the loop always runs until lo == hi and the answer is lo at termination. For boundary searches, the key is never to narrow the window past the answer: for the left boundary, when arr[mid] >= target, set hi = mid (not mid-1), because mid itself might be the answer. For the right boundary, when arr[mid] <= target, set lo = mid (not mid+1).

The rotated array variation adds a structural insight: when a sorted array is rotated, one of the two halves produced by any midpoint split is always fully sorted. You can determine which half is sorted by comparing arr[lo] to arr[mid]. If arr[lo] <= arr[mid], the left half is sorted; otherwise the right half is sorted. Then check whether the target falls within the sorted half and recurse appropriately.

```python
import bisect


# --- Left boundary: first occurrence of target ---
def find_first(arr: list, target) -> int:
    """Returns the index of the first occurrence of target, or -1."""
    lo, hi = 0, len(arr) - 1
    result = -1
    while lo <= hi:
        mid = lo + (hi - lo) // 2
        if arr[mid] == target:
            result = mid   # record this match, but keep looking left
            hi = mid - 1
        elif arr[mid] < target:
            lo = mid + 1
        else:
            hi = mid - 1
    return result


# --- Right boundary: last occurrence of target ---
def find_last(arr: list, target) -> int:
    """Returns the index of the last occurrence of target, or -1."""
    lo, hi = 0, len(arr) - 1
    result = -1
    while lo <= hi:
        mid = lo + (hi - lo) // 2
        if arr[mid] == target:
            result = mid   # record this match, but keep looking right
            lo = mid + 1
        elif arr[mid] < target:
            lo = mid + 1
        else:
            hi = mid - 1
    return result


# --- Insertion point (equivalent to bisect_left) ---
def insertion_point(arr: list, target) -> int:
    """Returns the leftmost index where target can be inserted to keep order."""
    lo, hi = 0, len(arr)
    while lo < hi:
        mid = lo + (hi - lo) // 2
        if arr[mid] < target:
            lo = mid + 1
        else:
            hi = mid
    return lo  # lo == hi at this point


# --- Search on the answer (predicate binary search) ---
def binary_search_answer(lo: int, hi: int, predicate) -> int:
    """Find the minimum x in [lo, hi] where predicate(x) is True.
    Assumes predicate is False for some prefix and True from some point onward."""
    while lo < hi:
        mid = lo + (hi - lo) // 2
        if predicate(mid):
            hi = mid        # mid might be the answer; keep it in range
        else:
            lo = mid + 1    # mid is definitely not the answer
    return lo  # lo == hi; this is the minimum x where predicate is True


# Example: find minimum speed to eat all bananas in h hours
def min_eating_speed(piles, h):
    def can_finish(speed):
        return sum(-(-p // speed) for p in piles) <= h  # ceiling division
    return binary_search_answer(1, max(piles), can_finish)


# --- Search in rotated sorted array ---
def search_rotated(arr: list, target: int) -> int:
    """Binary search in a rotated sorted array. Returns index or -1."""
    lo, hi = 0, len(arr) - 1
    while lo <= hi:
        mid = lo + (hi - lo) // 2
        if arr[mid] == target:
            return mid
        # Determine which half is sorted
        if arr[lo] <= arr[mid]:         # left half is sorted
            if arr[lo] <= target < arr[mid]:
                hi = mid - 1            # target is in the sorted left half
            else:
                lo = mid + 1            # target is in the right half
        else:                           # right half is sorted
            if arr[mid] < target <= arr[hi]:
                lo = mid + 1            # target is in the sorted right half
            else:
                hi = mid - 1            # target is in the left half
    return -1


# Demonstrations
arr = [1, 2, 2, 2, 3, 4]
print(find_first(arr, 2))         # 1
print(find_last(arr, 2))          # 3
print(insertion_point(arr, 2))    # 1 (same as bisect_left)

rotated = [4, 5, 6, 7, 0, 1, 2]
print(search_rotated(rotated, 0)) # 4
print(search_rotated(rotated, 3)) # -1

# Using Python's bisect module for boundary searches
import bisect
print(bisect.bisect_left(arr, 2))  # 1 - first occurrence
print(bisect.bisect_right(arr, 2)) # 4 - one past last occurrence
```

## Visualizer

<iframe src="/static/visualizers/binary-search-variations.html" style="width:100%;height:400px;border:none;border-radius:8px;" title="Binary Search Variations Visualizer"></iframe>

---

## How It Connects

All variations share the same O(log n) complexity as standard binary search - the loop narrows the window by half each iteration regardless of what the predicate or condition is. The predicate-based form is a direct instance of divide and conquer applied to answer spaces rather than data arrays. Many LeetCode hard problems that appear unrelated to searching - minimum capacity to ship packages in D days, Koko eating bananas, splitting an array into k parts with minimised maximum sum - all reduce to binary search on the answer once the monotone predicate is identified.

[[binary-search|Binary Search]]
[[divide-and-conquer|Divide and Conquer]]
[[arrays|Arrays]]

---

## Common Misconceptions

Misconception 1: "Binary search variations require different algorithmic thinking from basic binary search."
Reality: All binary search variations are the same algorithm with different predicates and different interpretations of what the loop invariant represents. The pattern is always: maintain a window that contains the answer, use the predicate to determine which half to discard, and exit when the window collapses to a single point. Recognising this commonality lets you apply binary search to any problem with a monotone structure, not just sorted array searches.

Misconception 2: "When arr[mid] equals the target during a boundary search, you should return mid immediately."
Reality: For the basic exact-match search, returning immediately on a match is correct and efficient. For boundary searches, you must continue: for the first occurrence, record mid as a candidate and narrow right (hi = mid - 1) to check whether an earlier occurrence exists; for the last occurrence, record mid and narrow left (lo = mid + 1) to check whether a later occurrence exists. Returning immediately gives a valid occurrence but not necessarily the first or last.

Misconception 3: "Binary search on the answer only works for searching integer values."
Reality: Binary search on the answer works for any monotone function over a totally ordered domain. You can binary search on real-valued answers (with a tolerance condition) to find, for example, the square root of a number to arbitrary precision. The loop termination condition changes from `lo < hi` (integers) to `hi - lo > epsilon` (reals). The core pattern - evaluate predicate at midpoint, discard half, narrow to convergence - is identical.

---

## Why It Matters in Practice

Binary search variations are among the most commonly tested algorithmic patterns in technical interviews, particularly at senior levels. The exact-match binary search is almost too simple to distinguish candidates; interviewers use rotated array search, first/last occurrence, and binary search on the answer to probe deeper understanding. The ability to recognise when a problem has a monotone structure and to formulate the correct predicate is what separates candidates who memorise binary search from candidates who understand it.

In production code, the Python `bisect` module handles the most common cases (insertion point, first/last occurrence) efficiently. But the predicate-based form - particularly for capacity/scheduling problems in distributed systems or for parameter tuning in machine learning pipelines - appears in real engineering work, not just interviews.

---

## Interview Angle

Common question forms:
- "Find the first and last position of a target in a sorted array."
- "Search in a rotated sorted array."
- "Find the minimum speed/capacity such that X is achievable."
- "How do you find where to insert an element in a sorted list?"

Answer frame:
For boundary searches: describe the left-boundary template (record match, narrow right) and right-boundary template (record match, narrow left). Distinguish from exact-match search. For rotated array: explain the key insight that one half is always sorted, and describe how to identify which half and whether the target lies in it. For binary search on the answer: identify the monotone predicate, set lo and hi to the extremes of the answer range, and apply the left-boundary template with the predicate as the condition. Always state what the loop invariant is - examiners award marks for this explicitly.

---

## Related Notes

- [[binary-search|Binary Search]]
- [[divide-and-conquer|Divide and Conquer]]
- [[arrays|Arrays]]
- [[bfs|Breadth-First Search]]
