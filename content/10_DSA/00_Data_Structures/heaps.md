---
title: 13 - Heaps and Priority Queues
description: A heap is a complete binary tree stored as an array where the parent is always the minimum (min-heap) or maximum (max-heap) of its subtree.
tags: [dsa, layer-10, heap, priority-queue]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Heaps and Priority Queues

> A heap is the most efficient structure for repeatedly finding and removing the smallest (or largest) element - the backbone of priority queues, heap sort, and shortest-path algorithms.

---

## Quick Reference

**Core idea:**
- Heap property: every parent is ≤ its children (min-heap) or ≥ its children (max-heap)
- Complete binary tree stored as a flat array: for index i, left child = 2i+1, right child = 2i+2, parent = (i−1)//2
- Python's `heapq` module: min-heap on a list. O(log n) push, O(log n) pop, O(1) peek (`heap[0]`)
- Build heap from n elements in O(n) using `heapq.heapify` - not O(n log n)
- Heap does NOT support O(log n) arbitrary search - only the root (min or max) is directly accessible

**Tricky points:**
- Python `heapq` is a min-heap only; to get max-heap behaviour, store negated values: push `−x`, pop and negate the result
- The heap property does not mean the array is sorted - siblings have no ordering relationship
- `heapq.heappop` returns and removes the root, then sifts down the last element to restore the heap - the returned element is the global minimum, not the first element of the underlying list after the operation
- For a priority queue with tuples `(priority, item)`, Python compares tuples element-by-element - if priorities are equal, it compares items; items must support `<` or you must use a sequence number as a tiebreaker
- `heapq.nlargest(k, iterable)` is O(n log k), not O(n log n) - efficient for small k

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Push (heappush) | O(log n) | O(log n) |
| Pop min (heappop) | O(log n) | O(log n) |
| Peek min (heap[0]) | O(1) | O(1) |
| Heapify (build heap) | O(n) | O(n) |
| Search arbitrary element | O(n) | O(n) |
| nlargest / nsmallest | O(n log k) | O(n log k) |

Space complexity: O(n)

---

## What It Is

Imagine a hospital emergency department using a triage system. When a patient arrives, a nurse assesses their urgency and assigns a priority number - 1 for critical, 5 for non-urgent. The waiting room is not a regular queue. The next patient called is always the one with the lowest priority number, regardless of when they arrived. When two patients have the same priority, arrival order breaks the tie. At any moment, a new critical patient can arrive and immediately jump to the front.

This is exactly what a priority queue does, and a heap is the efficient implementation of this structure. A min-heap always has the minimum element at its root - instantly accessible in O(1). Removing that minimum takes O(log n): the last element in the array is moved to the root, and it is "sifted down" by repeatedly swapping it with the smaller of its two children until the heap property is restored. Inserting a new element takes O(log n): it is appended at the end and "sifted up" until it reaches a position where it is greater than or equal to its parent.

The counter-intuitive O(n) heapify operation builds a heap from an unordered list in linear time. Naive thinking suggests O(n log n) - push n elements, each taking O(log n). But the heapify algorithm works bottom-up: it starts at the last internal node (the parent of the last element) and sifts down each node. Most nodes are near the bottom of the tree and only need to sift down a small number of levels. The mathematical sum of work across all levels converges to O(n), not O(n log n).

---

## How It Actually Works

The array representation is the clever trick that makes heaps practical. Instead of allocating node objects with left/right pointers, a heap stores all values in a flat list. For a node at index i, its left child is at index 2i + 1, its right child is at 2i + 2, and its parent is at (i − 1) // 2. This arithmetic is derived from the complete binary tree structure - every level is fully populated before the next level begins, so the mapping from tree position to array index is consistent.

Sift-up (used during push) compares the newly added element at the last index with its parent at (i−1)//2. If the element is smaller (min-heap), it swaps with the parent. This continues until the element is greater than or equal to its parent, or it reaches the root. Sift-down (used during pop) places the last element at the root, then compares it to its children. It swaps with the smaller child if that child is smaller. This continues until both children are larger or it reaches a leaf.

```python
import heapq

# ---- Basic heapq operations (min-heap) ----
heap = []
heapq.heappush(heap, 5)
heapq.heappush(heap, 1)
heapq.heappush(heap, 3)
heapq.heappush(heap, 2)
heapq.heappush(heap, 4)

print("Peek min:", heap[0])              # 1 - O(1)
print("Pop min:", heapq.heappop(heap))   # 1 - O(log n)
print("Heap after pop:", heap)           # not fully sorted, heap property only

# ---- Heapify - O(n) build from list ----
data = [5, 3, 8, 1, 9, 2, 7, 4, 6]
heapq.heapify(data)                      # in-place, O(n)
print("Heapified:", data)                # heap[0] = 1, but rest is not sorted

# ---- Max-heap using negation ----
max_heap = []
for x in [5, 1, 3, 2, 4]:
    heapq.heappush(max_heap, -x)         # store negated

max_val = -heapq.heappop(max_heap)       # negate result
print("Max heap pop:", max_val)          # 5

# ---- Priority queue with (priority, counter, item) tuples ----
import itertools

counter = itertools.count()   # unique sequence numbers for FIFO tiebreaking

pq = []
tasks = [
    (2, "medium task"),
    (1, "urgent task"),
    (2, "another medium task"),   # same priority as first medium
    (3, "low priority task"),
]
for priority, name in tasks:
    heapq.heappush(pq, (priority, next(counter), name))

while pq:
    pri, seq, name = heapq.heappop(pq)
    print(f"  [{pri}] {name}")
# [1] urgent task
# [2] medium task (arrived first among priority-2)
# [2] another medium task
# [3] low priority task


# ---- Manual sift-up and sift-down for understanding ----
def sift_up(heap, i):
    """Restore heap property upward from index i."""
    while i > 0:
        parent = (i - 1) // 2
        if heap[i] < heap[parent]:
            heap[i], heap[parent] = heap[parent], heap[i]
            i = parent
        else:
            break

def sift_down(heap, i, size):
    """Restore heap property downward from index i."""
    while True:
        smallest = i
        left = 2 * i + 1
        right = 2 * i + 2
        if left < size and heap[left] < heap[smallest]:
            smallest = left
        if right < size and heap[right] < heap[smallest]:
            smallest = right
        if smallest == i:
            break
        heap[i], heap[smallest] = heap[smallest], heap[i]
        i = smallest

# ---- Heap sort ----
def heap_sort(arr):
    """Sort in ascending order using a min-heap. O(n log n)."""
    heapq.heapify(arr)                   # O(n)
    return [heapq.heappop(arr) for _ in range(len(arr))]  # n × O(log n)

print("Heap sort:", heap_sort([5, 3, 8, 1, 9, 2, 7]))  # [1, 2, 3, 5, 7, 8, 9]

# ---- K largest / K smallest ----
data = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5]
print("3 largest:", heapq.nlargest(3, data))     # [9, 6, 5] - O(n log 3)
print("3 smallest:", heapq.nsmallest(3, data))   # [1, 1, 2] - O(n log 3)

# ---- Merge sorted iterables ----
sorted_lists = [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
merged = list(heapq.merge(*sorted_lists))   # O(n log k) where k = number of lists
print("Merged:", merged)  # [1, 2, 3, 4, 5, 6, 7, 8, 9]
```

---

## Visualizer

<iframe src="/static/visualizers/heap-tree.html" style="width:100%;height:500px;border:none;border-radius:8px;" title="Heap Tree Visualizer"></iframe>

---

## How It Connects

Heap sort uses the heap structure to sort an array in O(n log n) guaranteed time. Unlike quick sort, it has no worst-case degeneration. Understanding the heap is a prerequisite for understanding heap sort as a sorting algorithm that does not require additional memory.

[[heap-sort|Heap Sort]]

Dijkstra's shortest path algorithm uses a min-heap (priority queue) to always process the unvisited node with the smallest known distance. The O((V + E) log V) complexity of Dijkstra's comes directly from the O(log V) cost of heap operations.

[[dijkstra|Dijkstra's Algorithm]]

---

## Common Misconceptions

Misconception 1: "A heap is a sorted array."
Reality: A heap satisfies the heap property - each parent is smaller (or larger) than its children - but siblings have no defined ordering relationship. `heap[1]` and `heap[2]` (the two children of the root) have no guaranteed order relative to each other. A sorted array satisfies `arr[i] ≤ arr[i+1]` for all i, which is a much stronger constraint.

Misconception 2: "heapq.heapify is O(n log n) because it processes n elements."
Reality: `heapq.heapify` is O(n). The bottom-up heapify algorithm processes nodes from the last internal node upward, and nodes at lower levels do far less work than nodes near the top. The total work sums to O(n) by the convergence of a geometric series.

Misconception 3: "Python's heapq supports a max-heap natively."
Reality: Python's `heapq` is a min-heap only. To simulate a max-heap, store negated values (for numbers) or wrap objects in a class with reversed comparison. For complex objects, you can also define a `__lt__` method that reverses the comparison.

---

## Why It Matters in Practice

Priority queues built on heaps are fundamental infrastructure. Dijkstra's algorithm and A* pathfinding - used in navigation, routing, and game AI - depend on a min-heap to process nodes in order of their tentative distance. Task schedulers in operating systems and application-level job queues use priority heaps to ensure high-priority work runs first. The `heapq.merge` function provides O(n log k) external merge for sorted data that does not fit in memory - relevant for large-scale data processing.

In Python specifically, `heapq` is the correct tool whenever you need repeated access to the minimum or maximum of a dynamic set. Common patterns: finding the k largest or k smallest elements in a stream (`heapq.nlargest`/`nsmallest`), implementing a Dijkstra traversal, building a median-maintenance structure using two heaps (a max-heap for the lower half and a min-heap for the upper half), and implementing event-driven simulations where events are processed in time order.

---

## Interview Angle

Common question forms:
- "Find the kth largest element in an unsorted array."
- "Merge k sorted linked lists."
- "Find the median from a data stream."
- "Implement a task scheduler with priorities."
- "Why is heapify O(n) rather than O(n log n)?"

Answer frame:
For kth largest, describe maintaining a min-heap of size k: iterate the array, push each element, and if the heap exceeds k elements, pop the minimum. At the end, the root is the kth largest. For median maintenance, describe two heaps: a max-heap for the lower half, a min-heap for the upper half, rebalanced to maintain equal or off-by-one sizes. For the heapify O(n) question, describe the bottom-up algorithm and the observation that most nodes are near leaves where sift-down cost is O(1) - the geometric series argument.

---

## Related Notes

- [[queues|Queues]]
- [[heap-sort|Heap Sort]]
- [[dijkstra|Dijkstra's Algorithm]]
