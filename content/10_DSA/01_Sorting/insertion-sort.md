---
title: 20 - Insertion Sort
description: A sorting algorithm that builds a sorted array incrementally by inserting each new element into its correct position within the already-sorted prefix.
tags: [dsa, layer-10, sorting, insertion-sort]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Insertion Sort

> Insertion sort mirrors how people naturally sort cards in their hand — and it is fast enough that Python's Timsort uses it for small runs.

---

## Quick Reference

**Core idea:**
- Maintain a sorted prefix; for each new element, find its correct position and insert it
- Elements to the right of the insertion point shift one position right to make room
- O(n) best case on already-sorted input — only one comparison per element needed
- O(n²) worst case on reverse-sorted input — every element must shift past every sorted element
- Stable: equal elements are never moved past each other
- In-place, O(1) extra space; very low overhead for small arrays

**Tricky points:**
- Insertion sort is adaptive: it runs in O(n + inversions) where an inversion is any out-of-order pair — nearly-sorted input is fast
- The shift-right operation writes more elements per insertion than selection sort's single swap, but the total number of writes is proportional to the number of inversions
- Python's Timsort uses insertion sort for subarrays shorter than approximately 64 elements (the `minrun` threshold)
- The inner loop uses a while loop, not a for loop — it stops as soon as the correct position is found
- Binary insertion sort uses binary search to find the insertion point (O(log n) comparisons per element) but still requires O(n) shifts, so the overall complexity remains O(n²)

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case (sorted input) | O(n) | O(1) |
| Average case | O(n²) | O(1) |
| Worst case (reverse sorted) | O(n²) | O(1) |

---

## What It Is

Picture someone picking up playing cards one at a time from a shuffled pile on a table. The first card goes into their empty hand. The second card: they compare it to the first and slide it to the left of the first card if it is lower, or leave it to the right if it is higher. The third card: they slot it into the correct position among the two cards already in hand, shifting cards right to make room. By the time the last card is picked up, the hand is fully sorted. This is insertion sort exactly — and the reason it feels natural is that it matches how humans maintain ordered collections incrementally.

The key insight about insertion sort's performance is that the cost of inserting each element depends entirely on how far it has to travel. If the card being inserted is almost where it belongs, the insertion is cheap — perhaps just one or two comparisons and one shift. If it is the smallest card seen so far, it must travel all the way to the beginning of the sorted hand, comparing and displacing every card along the way. This means insertion sort's actual running time depends on the structure of the input, not just its size.

That dependence on input structure is called adaptivity. Insertion sort is adaptive in a precise sense: its runtime is O(n + k) where k is the number of inversions in the input. An inversion is any pair of elements that are in the wrong order relative to each other. A completely sorted array has zero inversions, giving O(n) time. A completely reversed array has n*(n-1)/2 inversions, giving O(n²) time. Nearly-sorted arrays — which are common in real data — have few inversions, and insertion sort handles them very efficiently. This is why Timsort incorporates insertion sort rather than simply using merge sort for everything.

---

## How It Actually Works

The algorithm divides the array into a sorted left portion and an unsorted right portion. The boundary starts after the first element (a single-element array is trivially sorted). In each step it takes the first element of the unsorted portion — called the key — and walks it backwards through the sorted portion, shifting each sorted element one position to the right until it finds a position where the element to the left is not greater than the key. It places the key there.

The inner while loop is what distinguishes insertion sort from the other elementary algorithms. It stops as soon as the correct position is found, rather than running to the end of the sorted portion. On sorted input, the key is always greater than or equal to its immediate left neighbour, so the while loop never executes and the algorithm completes in O(n) time with n-1 comparisons total.

```python
def insertion_sort(arr: list) -> list:
    """Insertion sort: stable, adaptive, O(n) best case."""
    arr = arr[:]  # work on a copy
    for i in range(1, len(arr)):
        key = arr[i]
        j = i - 1
        # Shift elements of arr[0..i-1] that are greater than key
        # one position to the right
        while j >= 0 and arr[j] > key:
            arr[j + 1] = arr[j]
            j -= 1
        # Place key in its correct sorted position
        arr[j + 1] = key
    return arr


# Demonstration
data = [5, 2, 4, 6, 1, 3]
print(insertion_sort(data))   # [1, 2, 3, 4, 5, 6]

# Nearly-sorted: very fast
nearly_sorted = [1, 2, 4, 3, 5, 6]
print(insertion_sort(nearly_sorted))  # [1, 2, 3, 4, 5, 6]

# Already sorted: O(n) — inner while loop never runs
print(insertion_sort([1, 2, 3, 4, 5]))  # [1, 2, 3, 4, 5]
```

---

## Visualizer

<iframe src="/visualizers/insertion-sort.html" style="width:100%;height:420px;border:none;border-radius:8px;" title="Insertion Sort Visualizer"></iframe>

---

## How It Connects

Insertion sort's efficiency on nearly-sorted data is directly exploited by Timsort, which first identifies naturally sorted runs in the input and then uses insertion sort to extend short runs to the minimum run length. Understanding insertion sort is therefore a prerequisite for understanding why Timsort performs so well on real-world data. The concept of inversions — pairs of elements in the wrong order — is a recurring idea in algorithm analysis and connects directly to how merge sort counts inversions as a classic interview problem.

[[python-sort-internals|Timsort — Python's Sorting Algorithm]]
[[merge-sort|Merge Sort]]
[[sorting-comparison|Sorting Algorithm Comparison]]

---

## Common Misconceptions

Misconception 1: "Insertion sort and selection sort have the same performance."
Reality: They have the same worst-case and average-case time complexity (O(n²)), but insertion sort is faster on nearly-sorted or sorted input because of its O(n) best case and adaptive behaviour. Selection sort is always O(n²) with no early exit. For real-world data that tends to be partially ordered, insertion sort is meaningfully faster.

Misconception 2: "Using binary search to find the insertion point makes insertion sort O(n log n)."
Reality: Binary insertion sort reduces the number of comparisons to O(n log n) total, but the number of element shifts remains O(n²) in the worst case, because after finding the insertion point you still have to move every element between the insertion point and the current position one slot to the right. The dominant cost is shifting, not comparing, so the overall time complexity stays O(n²).

Misconception 3: "Insertion sort is always worse than merge sort, even for small arrays."
Reality: For very small arrays (typically fewer than 16-64 elements), insertion sort is faster than merge sort in practice. Merge sort has significant overhead: recursive calls, memory allocation for temporary arrays, and poor cache locality for tiny subarrays. The constant factor of insertion sort is low enough that it wins on small inputs. This is why Timsort switches to insertion sort below its `minrun` threshold.

---

## Why It Matters in Practice

Insertion sort is the right tool for small arrays and nearly-sorted data. Python's Timsort, Java's Arrays.sort for primitive arrays, and many other production sort implementations use insertion sort as a base case precisely because its low overhead dominates at small sizes. When you know your data will almost always be in order with occasional insertions or mutations — like maintaining a sorted log of events as new events arrive — insertion sort's O(n + k) complexity makes it competitive even against O(n log n) algorithms.

In interviews, insertion sort matters because it introduces the concept of adaptive algorithms and demonstrates that average-case analysis does not tell the full story. An interviewer asking "which sort would you use for a nearly-sorted array of 50 elements?" expects you to reason about constant factors and adaptivity, not just Big-O. The correct answer is insertion sort, and explaining why reveals a deep understanding of how sorting algorithms behave in practice.

---

## Interview Angle

Common question forms:
- "Implement insertion sort."
- "What is the best case for insertion sort and why?"
- "When does Python use insertion sort internally?"
- "How does insertion sort compare to merge sort for small arrays?"

Answer frame:
Describe the sorted-prefix invariant: at each step, arr[0..i-1] is sorted and arr[i] is the current key to be inserted. Explain the backwards scan and shift. State O(n) best case for sorted input and explain why: the inner while condition fails immediately. Mention Timsort's use of insertion sort for small runs. For the practical comparison question, explain that insertion sort has lower constant factors and better cache behaviour than merge sort for small n, which is why production implementations switch to it below a threshold.

---

## Related Notes

- [[bubble-sort|Bubble Sort]]
- [[selection-sort|Selection Sort]]
- [[python-sort-internals|Timsort — Python's Sorting Algorithm]]
- [[sorting-comparison|Sorting Algorithm Comparison]]
