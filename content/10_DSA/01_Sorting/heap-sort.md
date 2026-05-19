---
title: 23 - Heap Sort
description: An in-place sorting algorithm that builds a max-heap from the array, then repeatedly extracts the maximum element to produce a sorted sequence in O(n log n) guaranteed time.
tags: [dsa, layer-10, sorting, heap-sort]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Heap Sort

> Heap sort solves the problem that selection sort identified - "finding the minimum efficiently" - by replacing the linear scan with a heap, turning O(n²) into O(n log n) with no extra space.

---

## Quick Reference

**Core idea:**
- Phase 1 (heapify): transform the array into a max-heap in O(n) time using repeated sift-down from the last internal node to the root
- Phase 2 (extraction): repeatedly swap the root (maximum) with the last element, shrink the heap by one, and restore the heap property via sift-down - O(log n) per extraction, O(n log n) total
- O(n log n) in all cases - no worst-case degradation
- In-place: O(1) extra space (heap is stored within the array itself)
- Not stable: the extraction swaps disrupt the relative order of equal elements
- The heapify phase takes O(n) time despite there being O(n) nodes - each sift-down at lower levels is short

**Tricky points:**
- The O(n) heapify is a non-obvious result: naively you might expect O(n log n); the actual cost is O(n) because most nodes are near the leaves and have small sift-down distances
- Heap sort is not cache-friendly: heap operations jump between parent and child indices that are far apart in memory, causing many cache misses compared to merge sort or quick sort
- The extraction loop builds the sorted array from the end of the array backwards, so the final result is in ascending order when using a max-heap
- Sift-down (also called heapify-down or push-down) works from a node toward the leaves; sift-up works from a node toward the root - only sift-down is needed in heap sort
- Heap sort is rarely used in production despite its theoretical guarantees

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case | O(n log n) | O(1) |
| Average case | O(n log n) | O(1) |
| Worst case | O(n log n) | O(1) |

---

## What It Is

Returning to the librarian analogy: instead of repeatedly scanning the entire unsorted shelf to find the smallest book (selection sort), imagine the librarian organises the unsorted books into a special structure - a heap - that guarantees the largest book is always on top. She picks the top book off (the maximum), places it at the far right of the sorted section, and then quickly restores the heap property among the remaining books. Picking the next maximum is now cheap: it is always on top. She repeats until the heap is empty.

The heap is the key data structure here. A max-heap is a binary tree stored implicitly in an array where every parent is greater than or equal to its children. The root, at index 0, always holds the maximum element. Removing the root and restoring the heap property (by sifting the replacement element down to its correct level) takes O(log n) time because the heap's height is O(log n). This transforms selection sort's O(n²) linear scan into O(n log n) heap operations.

The cleverness of heap sort is that the heap lives inside the original array with no extra memory. For an array of size n, the left child of element at index i is at index 2i+1, and the right child is at 2i+2. This indexing formula means a binary heap can be stored, accessed, and modified entirely within the original array. The sorted portion and the heap portion coexist in the same array throughout the algorithm, separated by a shrinking boundary. This is why heap sort achieves O(1) extra space - a property that merge sort cannot match.

---

## How It Actually Works

The algorithm has two phases. The heapify phase converts the array into a max-heap. It starts from the last internal node (at index n//2 - 1) and calls sift-down on each node moving toward the root. Nodes near the leaves have almost no distance to sift down, so the total work is O(n) rather than O(n log n). This O(n) build time is a tighter analysis than the O(n log n) you might expect from calling sift-down n times.

The extraction phase begins with the heap fully built. It swaps the root (the maximum) with the last element in the heap, shrinks the heap boundary by one (that last element is now in its final sorted position at the end of the array), and calls sift-down on the new root to restore the heap property. Repeating this n-1 times produces a fully sorted array in ascending order, all within the original array.

```python
def heap_sort(arr: list) -> list:
    """Heap sort: O(n log n) guaranteed, O(1) space, not stable."""
    arr = arr[:]  # work on a copy
    n = len(arr)

    # Phase 1: Build max-heap
    # Start from last internal node and sift down to root
    for i in range(n // 2 - 1, -1, -1):
        _sift_down(arr, n, i)

    # Phase 2: Extract elements one by one
    for i in range(n - 1, 0, -1):
        # Move current root (maximum) to end of heap
        arr[0], arr[i] = arr[i], arr[0]
        # Restore heap property for the reduced heap (size i)
        _sift_down(arr, i, 0)

    return arr


def _sift_down(arr: list, heap_size: int, root: int) -> None:
    """Sift the element at `root` down to restore the max-heap property."""
    largest = root
    left = 2 * root + 1
    right = 2 * root + 2

    if left < heap_size and arr[left] > arr[largest]:
        largest = left
    if right < heap_size and arr[right] > arr[largest]:
        largest = right

    if largest != root:
        arr[root], arr[largest] = arr[largest], arr[root]
        _sift_down(arr, heap_size, largest)


# Demonstration
data = [12, 11, 13, 5, 6, 7]
print(heap_sort(data))  # [5, 6, 7, 11, 12, 13]

# Python's heapq module provides a min-heap
# For max-heap behaviour, negate values or use the heap sort above
import heapq
min_heap = [3, 1, 4, 1, 5, 9]
heapq.heapify(min_heap)
print([heapq.heappop(min_heap) for _ in range(len(min_heap))])  # sorted ascending
```

---

## Visualizer

<iframe src="/static/visualizers/heap-sort.html" style="width:100%;height:420px;border:none;border-radius:8px;" title="Heap Sort Visualizer"></iframe>

---

## How It Connects

Heap sort is the direct algorithmic evolution of selection sort: both repeatedly select the extremum from the unsorted portion and place it in its final position, but heap sort uses the heap data structure to make each selection O(log n) instead of O(n). Understanding heaps - how they are stored in arrays, the sift-down operation, and the O(n) build time - is a prerequisite for making sense of heap sort's analysis.

[[heaps|Heaps]]
[[selection-sort|Selection Sort]]
[[sorting-comparison|Sorting Algorithm Comparison]]

---

## Common Misconceptions

Misconception 1: "Building a heap takes O(n log n) time because you call sift-down O(n) times."
Reality: The O(n) heapify time comes from a tighter analysis. Nodes at the bottom of the heap (leaves) require 0 sift-down operations. Nodes one level above leaves require at most 1 swap. Only the root requires O(log n) swaps. When you sum the work across all nodes weighted by their height, the total converges to O(n). This is a standard result that every interviewer asking about heaps expects you to know.

Misconception 2: "Heap sort should be preferred over quick sort because it guarantees O(n log n) and uses O(1) space."
Reality: Heap sort's O(n log n) worst case and O(1) space are genuine advantages on paper, but in practice heap sort is slower than quick sort on typical inputs due to poor cache performance. Heap operations access elements at indices i, 2i+1, 2i+2 - these jump around in memory, causing frequent cache misses. Quick sort accesses elements in a much more sequential pattern, making much better use of CPU cache lines. Introsort (used in C++ STL) combines quick sort with heap sort as a fallback to get the best of both.

Misconception 3: "Heap sort is stable."
Reality: Heap sort is not stable. The extraction phase swaps the root with the last element of the heap, which can move an element far from its original position. Equal elements can end up in any relative order. If stability is required, merge sort is the O(n log n) in-place-recursive option with guaranteed stability.

---

## Why It Matters in Practice

Heap sort is not the first choice for general-purpose sorting in production code - that distinction belongs to Timsort, introsort, or other hybrids. Its value lies in two places. First, it is part of introsort (introspective sort), which begins with quick sort and falls back to heap sort when the recursion depth exceeds 2*log(n), guaranteeing O(n log n) worst case for the combined algorithm. The C++ standard library's `std::sort` uses introsort. Second, understanding heap sort deepens your understanding of the heap data structure itself: the sift-down operation, the array-based implicit tree, and the O(n) heapify are all things that come up in heap-related interview questions beyond pure sorting.

In interviews, heap sort is asked less often than quick sort or merge sort, but it connects directly to heap-related questions: find the k largest elements, implement a priority queue, build a median-maintenance data structure. The sift-down subroutine you write for heap sort is reused in all of these.

---

## Interview Angle

Common question forms:
- "Implement heap sort."
- "What is the time complexity of building a heap?"
- "Why is heap sort not used in practice despite its O(n log n) guarantee?"
- "How does heap sort relate to selection sort?"

Answer frame:
Describe the two phases clearly: O(n) heapify by iterating sift-down from n//2-1 to 0, then O(n log n) extraction by swapping root to sorted end and sifting down. Explain O(n) build time with the height-weighted argument. For the practical question: state that cache performance is the key weakness - heap sort's non-sequential memory access pattern causes frequent cache misses, while quick sort is faster in practice because it accesses memory more sequentially. Mention introsort as the production answer that uses heap sort as a safety net.

---

## Related Notes

- [[heaps|Heaps]]
- [[selection-sort|Selection Sort]]
- [[quick-sort|Quick Sort]]
- [[sorting-comparison|Sorting Algorithm Comparison]]
