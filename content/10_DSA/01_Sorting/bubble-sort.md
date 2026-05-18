---
title: Bubble Sort
description: A comparison-based sorting algorithm that repeatedly swaps adjacent out-of-order elements, bubbling the largest values to the end of the array.
tags: [dsa, layer-10, sorting, bubble-sort]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Bubble Sort

> Bubble sort is the canonical teaching algorithm for sorting — not because it is useful in practice, but because it makes the sorting problem visible in the simplest possible way.

---

## Quick Reference

**Core idea:**
- Compare adjacent elements and swap them if they are in the wrong order
- After each full pass, the largest unsorted element has "bubbled" to its final position
- Repeat for n-1 passes to sort the entire array
- The `swapped` flag enables an early-exit optimisation that gives O(n) best case
- Stable: equal elements are never swapped, so their original order is preserved
- In-place: uses O(1) extra space

**Tricky points:**
- Without the `swapped` flag, best case is still O(n²) — always check for this in interviews
- After k passes, the last k elements are guaranteed to be in their final positions — the inner loop can shrink
- Bubble sort makes O(n²) comparisons and O(n²) swaps in the worst case — worse than selection sort for swaps in random input
- The name comes from the visual metaphor of values "bubbling up" through the array
- Do not confuse stability (equal elements keep order) with adaptivity (benefits from partially sorted input)

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case (sorted, with swapped flag) | O(n) | O(1) |
| Average case | O(n²) | O(1) |
| Worst case (reverse sorted) | O(n²) | O(1) |

---

## What It Is

Think of a row of children lined up by height who are supposed to be in order from shortest to tallest. A teacher walks down the line comparing each pair of adjacent children. If a taller child is standing to the left of a shorter one, she tells them to swap places. After one full walk down the line, the tallest child has been pushed all the way to the far right — every time the teacher encountered someone taller, that person kept getting moved rightward. The teacher repeats the process, this time stopping one position earlier because the rightmost child is already in the right place. She keeps going until she completes an entire walk without making a single swap, at which point the line is fully sorted.

Bubble sort embodies this idea directly. It operates on an array by scanning from left to right and swapping any adjacent pair that is out of order. The first complete pass guarantees that the maximum element ends up at index n-1. The second pass guarantees that the second-largest element ends up at index n-2. Each pass shrinks the problem by one element. This is why bubble sort requires at most n-1 passes for an array of length n.

The algorithm is important to learn not because you would ever deploy it in production, but because it introduces the core ideas of in-place comparison sorting in the most transparent way. You can trace every step by hand and see exactly why it works. Every more advanced sorting algorithm — selection sort, insertion sort, merge sort — builds on the same idea of comparing and rearranging elements, but does so with more strategic insight about which comparisons to make.

---

## How It Actually Works

The basic version performs n-1 passes over the array. In each pass it scans from index 0 to the last unsorted index and swaps adjacent elements that are out of order. The inner loop boundary shrinks by one after each pass because the largest remaining element has been placed correctly. This gives exactly n*(n-1)/2 comparisons in the worst case, which is O(n²).

The optimised version introduces a boolean flag called `swapped`. At the start of each pass the flag is set to False. If any swap occurs during the pass, the flag is set to True. At the end of a pass, if the flag is still False, the array was already sorted and the algorithm exits early. This single addition transforms the best-case time complexity from O(n²) to O(n) for sorted or nearly-sorted input, because the algorithm detects the sorted state after a single scan. The worst-case and average-case behaviour are unchanged.

```python
def bubble_sort(arr: list) -> list:
    """Optimised bubble sort with early-exit on sorted input."""
    n = len(arr)
    arr = arr[:]  # work on a copy
    for i in range(n - 1):
        swapped = False
        # Inner loop shrinks: last i elements are already in place
        for j in range(n - 1 - i):
            if arr[j] > arr[j + 1]:
                arr[j], arr[j + 1] = arr[j + 1], arr[j]
                swapped = True
        # If no swap occurred, the array is sorted
        if not swapped:
            break
    return arr


# Demonstration
data = [5, 3, 8, 4, 2]
print(bubble_sort(data))   # [2, 3, 4, 5, 8]

already_sorted = [1, 2, 3, 4, 5]
print(bubble_sort(already_sorted))  # exits after 1 pass
```

---

## How It Connects

Bubble sort operates on contiguous elements in an array, so understanding how arrays store data in memory is the right foundation before studying any sorting algorithm. The early-exit optimisation that makes bubble sort O(n) on sorted input is the same concept that makes insertion sort fast on nearly-sorted data.

[[arrays|Arrays]]
[[insertion-sort|Insertion Sort]]
[[sorting-comparison|Sorting Algorithm Comparison]]

---

## Common Misconceptions

Misconception 1: "Bubble sort is O(n) in the best case by default."
Reality: O(n) best case only applies when the `swapped` flag optimisation is included. The naive version without the flag always performs O(n²) comparisons even on a sorted array, because the inner loops run to completion regardless of whether any swaps occur.

Misconception 2: "Bubble sort is stable only in the optimised version."
Reality: Stability is determined by the swap condition, not by the early-exit optimisation. The condition `arr[j] > arr[j+1]` means equal elements are never swapped — so the original relative order of duplicates is always preserved. Both the basic and optimised versions are stable.

Misconception 3: "Bubble sort is useful for small arrays in practice."
Reality: Insertion sort is strictly better for small arrays: it has lower constant factors, is also stable and O(1) space, but makes O(n) comparisons and O(n) writes on nearly-sorted data rather than O(n²). Bubble sort's only practical virtue is its simplicity as a teaching example.

---

## Why It Matters in Practice

Bubble sort is almost never used in production code. Its O(n²) average and worst-case complexity makes it impractical for any non-trivial dataset when better algorithms exist. However, it is a required stop on the path to understanding sorting because it makes the fundamental mechanics transparent. When you can trace bubble sort by hand, the concepts of comparisons, swaps, loop invariants, and stability become concrete.

In interviews, bubble sort comes up as a baseline — examiners use it to check whether you know why it is slow, whether you know the `swapped` flag optimisation, and whether you can articulate when you would instead choose insertion sort, merge sort, or Python's built-in Timsort. Knowing bubble sort well means knowing what makes a bad sorting algorithm, which sharpens your understanding of what makes a good one.

---

## Interview Angle

Common question forms:
- "Implement bubble sort."
- "What is the best-case time complexity of bubble sort?"
- "How would you optimise bubble sort?"
- "Compare bubble sort to insertion sort for small arrays."

Answer frame:
Lead with the core mechanic (adjacent swaps, largest element bubbles to end each pass). State the unoptimised complexity (O(n²) all cases). Introduce the `swapped` flag and explain why it gives O(n) best case. Distinguish bubble sort from insertion sort: both are O(n²) average, but insertion sort has lower constant factors and is preferred for small/nearly-sorted inputs. Acknowledge that neither is used in production — Python's `list.sort()` uses Timsort.

---

## Related Notes

- [[sorting-comparison|Sorting Algorithm Comparison]]
- [[insertion-sort|Insertion Sort]]
- [[selection-sort|Selection Sort]]
- [[python-sort-internals|Timsort — Python's Sorting Algorithm]]
