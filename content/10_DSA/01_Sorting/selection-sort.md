---
title: 19 - Selection Sort
description: A comparison-based sorting algorithm that repeatedly selects the minimum element from the unsorted portion and places it at the front, making exactly n-1 swaps total.
tags: [dsa, layer-10, sorting, selection-sort]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Selection Sort

> Selection sort trades the number of swaps for simplicity — it makes exactly n-1 swaps regardless of input, which matters when writes to storage are expensive.

---

## Quick Reference

**Core idea:**
- Divide the array into a sorted prefix and an unsorted suffix
- In each pass, find the minimum element in the unsorted suffix
- Swap that minimum with the first element of the unsorted suffix
- The sorted prefix grows by one element per pass
- Exactly n-1 swaps total, regardless of the initial order
- In-place, O(1) extra space

**Tricky points:**
- Selection sort is O(n²) in all cases — there is no early-exit possible because it must scan the entire unsorted portion to confirm the minimum
- Selection sort is not stable in its standard form: swapping the minimum into position can disrupt the relative order of equal elements
- It makes fewer swaps than bubble sort on average, but the same number of comparisons
- Finding the minimum requires a full scan — you cannot know the minimum without looking at every element in the unsorted portion
- The "minimum-finding" inner loop is essentially a linear search applied n times

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case | O(n²) | O(1) |
| Average case | O(n²) | O(1) |
| Worst case | O(n²) | O(1) |

---

## What It Is

Imagine you have a hand of playing cards spread face-up on a table in random order. You want to arrange them from lowest to highest. Your strategy: scan all the cards, find the lowest one, pick it up and place it at the far left. Now scan the remaining cards, find the lowest among those, and place it immediately to the right of the first. Repeat until the table is clear. At every step you are "selecting" the minimum from what remains. You never move a card more than once — each card goes directly from its starting position to its final sorted position. That is selection sort.

The key property this analogy reveals is the write efficiency. Each card is physically moved exactly once. In computing terms, selection sort performs exactly n-1 swaps to sort an array of n elements. Bubble sort, by contrast, can perform O(n²) swaps because it swaps every adjacent pair it encounters out of order. If swapping is expensive — for example, if elements are large records being written to flash memory where writes have limited lifetime — selection sort's minimal write count is a genuine advantage.

The cost of this efficiency is that selection sort offers no shortcut. No matter how close to sorted the input already is, the algorithm must still scan the entire unsorted portion to confirm it has found the minimum. A sorted array takes exactly the same number of comparisons as a completely reversed array. This is why selection sort has no best-case improvement and is O(n²) in all cases without exception.

---

## How It Actually Works

Selection sort maintains a boundary index that separates the sorted portion of the array (to the left) from the unsorted portion (to the right). Initially this boundary is at index 0, meaning the entire array is unsorted. In each iteration, the algorithm finds the index of the minimum element in the unsorted portion by scanning from the boundary to the end. It then swaps the minimum element with the element at the boundary index and advances the boundary by one. After n-1 iterations the boundary has reached the last element and the array is fully sorted.

The inner loop in each pass runs from the current boundary to the end of the array. In the first pass it makes n-1 comparisons, in the second pass n-2, and so on. The total number of comparisons is (n-1) + (n-2) + ... + 1 = n*(n-1)/2, which is O(n²). The number of swaps is at most n-1 — one per pass, and zero if the minimum is already at the boundary position.

```python
def selection_sort(arr: list) -> list:
    """Selection sort: O(n²) comparisons, O(n) swaps."""
    arr = arr[:]  # work on a copy
    n = len(arr)
    for i in range(n - 1):
        # Find the index of the minimum in arr[i:]
        min_idx = i
        for j in range(i + 1, n):
            if arr[j] < arr[min_idx]:
                min_idx = j
        # Swap minimum into the sorted boundary position
        if min_idx != i:
            arr[i], arr[min_idx] = arr[min_idx], arr[i]
    return arr


# Demonstration
data = [64, 25, 12, 22, 11]
print(selection_sort(data))  # [11, 12, 22, 25, 64]

# Verify minimum swaps: for n=5, at most 4 swaps
# Even on already-sorted input, still O(n²) comparisons
print(selection_sort([1, 2, 3, 4, 5]))  # [1, 2, 3, 4, 5]
```

---

## Visualizer

<iframe src="/static/visualizers/selection-sort.html" style="width:100%;height:420px;border:none;border-radius:8px;" title="Selection Sort Visualizer"></iframe>

---

## How It Connects

Selection sort's inner loop is a direct application of linear search: it scans a subarray to find the minimum element by examining each element once. Understanding linear search makes selection sort's mechanics immediate. Heap sort can be understood as selection sort with a more efficient data structure — instead of a linear scan to find the minimum, it maintains a heap that gives O(log n) extraction, turning O(n²) into O(n log n).

[[linear-search|Linear Search]]
[[heap-sort|Heap Sort]]
[[sorting-comparison|Sorting Algorithm Comparison]]

---

## Common Misconceptions

Misconception 1: "Selection sort is stable."
Reality: The standard in-place implementation is not stable. When the minimum element is swapped into position, it can jump over equal elements, disrupting their original relative order. For example, in [3a, 3b, 1], swapping 1 with 3a produces [1, 3b, 3a] — the two 3s have swapped relative order. A stable variant exists but requires shifting rather than swapping, which increases the number of writes.

Misconception 2: "Selection sort is faster than bubble sort because it makes fewer swaps."
Reality: Fewer swaps does not mean faster in practice. Both algorithms make O(n²) comparisons, and comparisons are what dominate CPU time in typical sorting. Selection sort's advantage in write count only matters in specialised storage scenarios (flash memory, EEPROM) where writes are significantly more expensive than reads. For in-memory sorting, insertion sort is better than both.

Misconception 3: "Selection sort can exit early if the input is already sorted."
Reality: It cannot. Unlike bubble sort with the `swapped` flag, selection sort has no mechanism to detect a sorted array. The algorithm must always complete all n-1 passes because it cannot verify the minimum without scanning the full unsorted portion each time.

---

## Why It Matters in Practice

Selection sort is not used in modern software for general sorting. Its O(n²) complexity in all cases and lack of adaptivity make it worse than insertion sort for nearly-sorted data and worse than merge or quick sort for large datasets. It does not appear in standard library implementations.

Its value is pedagogical and situational. It teaches the invariant-based approach to algorithm design: at the start of each pass, the left portion is sorted and contains the smallest i elements. It also introduces the rare scenario where minimising writes matters — in embedded systems writing to flash storage, making n-1 writes instead of potentially O(n²) writes is a meaningful constraint. Understanding selection sort builds the intuition that leads directly to heap sort, which achieves O(n log n) comparisons by replacing the linear minimum-finding scan with a heap.

---

## Interview Angle

Common question forms:
- "Implement selection sort."
- "How many swaps does selection sort make?"
- "Is selection sort stable? Why or why not?"
- "When would you prefer selection sort over other algorithms?"

Answer frame:
Describe the sorted-prefix invariant clearly: each pass selects the minimum from the unsorted suffix and places it at the boundary. State that exactly n-1 swaps occur regardless of input. Explain why it is not stable by giving the concrete counterexample of equal elements being displaced. Answer the "when to use" question honestly: only when write operations are expensive relative to read operations, such as writing to flash memory. Otherwise, insertion sort is preferred for small arrays and Timsort for everything else.

---

## Related Notes

- [[bubble-sort|Bubble Sort]]
- [[insertion-sort|Insertion Sort]]
- [[heap-sort|Heap Sort]]
- [[sorting-comparison|Sorting Algorithm Comparison]]
