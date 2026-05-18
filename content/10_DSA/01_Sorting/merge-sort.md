---
title: 21 - Merge Sort
description: A divide-and-conquer sorting algorithm that recursively splits the array in half, sorts each half, and merges the sorted halves into a single sorted result.
tags: [dsa, layer-10, sorting, merge-sort, divide-and-conquer]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Merge Sort

> Merge sort guarantees O(n log n) in all cases — a promise that quick sort cannot make — and its merge step is one of the most reusable subroutines in computer science.

---

## Quick Reference

**Core idea:**
- Divide: split the array into two equal halves
- Conquer: recursively sort each half (base case: array of length 0 or 1)
- Merge: combine two sorted halves into one sorted array using two pointers
- O(n log n) in all cases — best, average, and worst
- O(n) extra space for the merge step — not in-place
- Stable: equal elements from the left half are placed before equal elements from the right half

**Tricky points:**
- The merge step is the key intellectual contribution; the divide step is trivial
- The two-pointer merge requires O(n) extra space; truly in-place merge sort exists but is complex and slower in practice
- Merge sort is preferred over quick sort for linked lists: no random access is needed, and the merge can be done with O(1) extra pointers
- The recursion depth is O(log n), so the call stack uses O(log n) space in addition to the O(n) merge buffer
- Merge sort is stable; quick sort in its standard form is not
- External merge sort (sorting data larger than RAM) is a direct extension of this algorithm

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case | O(n log n) | O(n) |
| Average case | O(n log n) | O(n) |
| Worst case | O(n log n) | O(n) |

---

## What It Is

Imagine you have two piles of sorted index cards and you want to combine them into one sorted pile. You hold one pile in each hand and compare the top card of each. You take whichever top card is smaller, place it face-down on the output pile, and repeat. When one pile runs out, you place all remaining cards from the other pile on the output. This two-pile combination is the merge operation, and it runs in O(n) time where n is the total number of cards.

Merge sort builds this merge operation into a recursive strategy. To sort a single pile of shuffled cards, split it roughly in half, sort each half (by recursively applying the same strategy), then merge the two sorted halves. The splitting continues until every subpile has just one card, which is trivially sorted. The recursion then unwinds, merging pairs of single cards into sorted pairs, then pairs of sorted pairs into sorted fours, and so on until the full sorted sequence is assembled. Because each merge level processes all n elements and there are log n levels (the array halves each time), the total work is O(n log n).

The guarantee of O(n log n) in all cases is what distinguishes merge sort from quick sort. Quick sort is faster in practice on average but can degrade to O(n²) with bad pivot choices. Merge sort never degrades — it sorts n elements with exactly O(n log n) operations regardless of how the input is arranged. This predictability makes merge sort the preferred choice in contexts where worst-case guarantees matter, such as sorting in real-time systems or as the basis for external sorting algorithms that process data larger than available memory.

---

## How It Actually Works

The algorithm splits the input at the midpoint, recursively sorts the left and right halves, then calls the merge function to combine them. The base case returns immediately for arrays of length 0 or 1. The merge function uses two index pointers, one for each half, and builds the result by repeatedly taking the smaller of the two pointed-to elements. When one half is exhausted, the remaining elements of the other half are appended directly — they are already sorted.

The merge function creates a temporary list to hold the merged result. This is where the O(n) space cost comes from: at the top level of recursion, the merge needs an auxiliary array of size n. The space is reused across recursive calls because they do not all exist simultaneously, so the dominant space cost is the single top-level merge buffer, giving O(n) total extra space.

```python
def merge_sort(arr: list) -> list:
    """Merge sort: O(n log n) guaranteed, stable, O(n) space."""
    if len(arr) <= 1:
        return arr

    mid = len(arr) // 2
    left = merge_sort(arr[:mid])
    right = merge_sort(arr[mid:])
    return _merge(left, right)


def _merge(left: list, right: list) -> list:
    """Merge two sorted lists into one sorted list."""
    result = []
    i = j = 0
    while i < len(left) and j < len(right):
        # Use <= to preserve stability: left element goes first on ties
        if left[i] <= right[j]:
            result.append(left[i])
            i += 1
        else:
            result.append(right[j])
            j += 1
    # Append any remaining elements from either half
    result.extend(left[i:])
    result.extend(right[j:])
    return result


# Demonstration
data = [38, 27, 43, 3, 9, 82, 10]
print(merge_sort(data))  # [3, 9, 10, 27, 38, 43, 82]


# Merge sort on a linked list: merge is O(1) extra space with pointers
# because no copying is needed — nodes are relinked, not copied
def merge_sort_linked(head):
    """Skeleton — split at middle with slow/fast pointer, merge by relinking."""
    pass  # full implementation omitted for brevity
```

---

## How It Connects

Merge sort is the canonical example of the divide-and-conquer strategy. Understanding the recurrence T(n) = 2T(n/2) + O(n) and solving it to O(n log n) using the Master Theorem is a standard step in algorithm analysis. The merge operation itself appears as a building block in other algorithms: the classic interview problem of counting inversions in an array is solved by instrumenting the merge step to count how many left-half elements each right-half element skips over.

[[divide-and-conquer|Divide and Conquer]]
[[quick-sort|Quick Sort]]
[[python-sort-internals|Timsort — Python's Sorting Algorithm]]
[[sorting-comparison|Sorting Algorithm Comparison]]

---

## Common Misconceptions

Misconception 1: "Merge sort uses O(log n) space because the recursion is log n levels deep."
Reality: The recursion depth is O(log n), so the call stack uses O(log n) space. However, the merge buffers at each level of recursion use O(n) total space across all active stack frames. The dominant space cost is the O(n) merge buffer, not the O(log n) call stack. Merge sort uses O(n) extra space overall.

Misconception 2: "Merge sort is always better than quick sort because it guarantees O(n log n)."
Reality: Merge sort's O(n) space cost is a significant disadvantage compared to quick sort's O(log n) space (in-place, average case). Quick sort also has better cache performance in practice because it accesses memory sequentially within its partitions, whereas merge sort writes to a separate buffer. For in-memory sorting of random data, quick sort is typically faster. Merge sort is preferred for stability guarantees, linked list sorting, and external sorting.

Misconception 3: "Merge sort for linked lists requires O(n) extra space for the merge."
Reality: For arrays, merge requires O(n) extra space to hold the merged result before copying back. For linked lists, the merge can be performed in-place by relinking nodes using only a constant number of pointers — no auxiliary array is needed. This makes merge sort uniquely well-suited for linked lists, where O(n log n) time and O(1) extra space (beyond the recursion stack) is achievable.

---

## Why It Matters in Practice

Merge sort's real-world importance comes from three areas. First, it is the foundation of external sorting: when data is too large to fit in memory, merge sort's structure maps naturally onto reading and writing sorted runs to and from disk. Database systems and big-data processing frameworks use merge-based algorithms for exactly this reason. Second, it is stable, making it appropriate whenever the relative order of equal elements must be preserved — a property quick sort does not provide. Third, it is the algorithm used in Python's Timsort as the outer structure: Timsort identifies sorted runs and merges them using a modified merge sort with a galloping optimisation.

The merge subroutine also appears independently in several important interview problems: merging k sorted lists, counting inversions, and finding the median of two sorted arrays all reduce to merge-step variants. Knowing merge sort deeply means you understand not just one algorithm but a family of merge-based techniques.

---

## Interview Angle

Common question forms:
- "Implement merge sort."
- "What is the space complexity of merge sort?"
- "Why is merge sort preferred over quick sort for linked lists?"
- "How would you use merge sort to count inversions in an array?"

Answer frame:
Describe the three steps (divide, conquer, merge) and explain that the non-trivial work is in the merge step. State O(n log n) time in all cases and O(n) space, clarifying that the O(log n) recursion depth contributes less than the O(n) merge buffer. For linked lists: explain that the merge can relink nodes in O(1) extra space, whereas arrays require copying. For counting inversions: each time a right-half element is placed before a remaining left-half element during merge, it contributes inversions equal to the number of remaining left-half elements — instrument the merge step to accumulate this count.

---

## Related Notes

- [[quick-sort|Quick Sort]]
- [[divide-and-conquer|Divide and Conquer]]
- [[python-sort-internals|Timsort — Python's Sorting Algorithm]]
- [[sorting-comparison|Sorting Algorithm Comparison]]
- [[linked-lists|Linked Lists]]
