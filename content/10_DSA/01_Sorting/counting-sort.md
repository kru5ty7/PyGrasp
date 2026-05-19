---
title: 24 - Counting Sort
description: A non-comparison sorting algorithm that counts the frequency of each value and reconstructs a sorted output in O(n + k) time, where k is the range of input values.
tags: [dsa, layer-10, sorting, counting-sort, linear-sort]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Counting Sort

> Counting sort breaks the O(n log n) comparison-sort lower bound by never comparing elements — it counts and reconstructs, making it O(n) when the value range is small.

---

## Quick Reference

**Core idea:**
- Count the occurrences of each distinct value in a frequency array indexed by value
- Transform the frequency array into a prefix-sum (cumulative count) array — each entry now holds the starting output index for that value
- Walk the input array and place each element at its correct output index, decrementing the count after each placement
- O(n + k) time and space, where k is the range of values (max - min + 1)
- Stable: the reverse-walk placement step preserves the original relative order of equal elements
- Works only for integers (or objects with a bounded integer key)

**Tricky points:**
- When k >> n (large range, few elements), counting sort uses more time and space than comparison sorts — it is only beneficial when k is O(n)
- The prefix-sum step is essential for stability; a simpler version that just outputs each value `count[v]` times works but loses stability
- Negative integers require offsetting: subtract `min_val` from each value to shift the range to start at 0
- Counting sort is the building block for radix sort: radix sort applies counting sort digit by digit
- Python's integers are unbounded — always check the actual value range before applying counting sort

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case | O(n + k) | O(n + k) |
| Average case | O(n + k) | O(n + k) |
| Worst case | O(n + k) | O(n + k) |

---

## What It Is

Imagine a teacher who needs to return a class of 30 students' test scores in sorted order. Each score is an integer from 0 to 100. Rather than comparing scores pairwise — which takes O(n log n) — she takes a blank sheet with 101 rows labelled 0 through 100. She reads each score and makes a tally mark in the corresponding row. When she is done, she reads the rows from 0 to 100 in order, writing down each score as many times as it was tallied. The result is sorted. She never compared two scores against each other — she compared each score against a fixed scale.

This is counting sort. The "blank sheet with 101 rows" is the count array. The "reading tally marks in order" is the reconstruction step. The algorithm works because the values themselves serve as indices into the count array, and the count array's structure already encodes the sorted order. For a bounded integer domain, this is strictly more efficient than any comparison sort.

The key limitation is that the count array must have k slots where k is the range of possible values. If you are sorting the ages of 1,000 people (values 0–150), k is 151 and the algorithm is extremely efficient. If you are sorting 1,000 people by their social security number (values 0–999,999,999), k is one billion and the count array alone would consume gigabytes of memory. The algorithm's efficiency is tightly coupled to the ratio of n to k. When k is O(n), the total complexity is O(n) — better than any comparison sort. When k is O(n²), it is worse than merge sort. Counting sort is therefore a specialised tool, not a general-purpose one.

---

## How It Actually Works

The stable version of counting sort proceeds in three passes. First, it counts occurrences by creating a count array of size k (the value range) and incrementing count[value] for each element in the input. Second, it converts the count array into a prefix-sum array: count[i] += count[i-1] for i from 1 to k-1. After this step, count[v] holds the number of elements with value at most v, which equals the index one past the last position where v should appear in the output. Third, it places elements into the output array by walking the input in reverse: for each element, its output position is count[element] - 1, and count[element] is decremented to handle duplicates correctly. Walking in reverse ensures that elements with equal values appear in the same relative order as in the input (stable).

```python
def counting_sort(arr: list) -> list:
    """Counting sort: O(n + k), stable, integers only."""
    if not arr:
        return []

    min_val = min(arr)
    max_val = max(arr)
    k = max_val - min_val + 1  # size of the value range

    # Step 1: Count occurrences (offset by min_val to handle negatives)
    count = [0] * k
    for val in arr:
        count[val - min_val] += 1

    # Step 2: Convert to prefix sums
    # count[i] now = number of elements <= (i + min_val)
    for i in range(1, k):
        count[i] += count[i - 1]

    # Step 3: Place elements in output (reverse walk for stability)
    output = [0] * len(arr)
    for val in reversed(arr):
        idx = val - min_val
        count[idx] -= 1
        output[count[idx]] = val

    return output


# Demonstration
scores = [4, 2, 2, 8, 3, 3, 1]
print(counting_sort(scores))  # [1, 2, 2, 3, 3, 4, 8]

ages = [25, 30, 25, 18, 30, 22]
print(counting_sort(ages))    # [18, 22, 25, 25, 30, 30]

# With negatives: the offset handles them automatically
temps = [-5, 3, -1, 0, 2, -5]
print(counting_sort(temps))   # [-5, -5, -1, 0, 2, 3]


def counting_sort_simple(arr: list) -> list:
    """Simplified (non-stable) version — just reconstruct from counts."""
    if not arr:
        return []
    min_val, max_val = min(arr), max(arr)
    count = [0] * (max_val - min_val + 1)
    for val in arr:
        count[val - min_val] += 1
    return [val + min_val for val, freq in enumerate(count) for _ in range(freq)]
```

---

## Visualizer

<iframe src="/static/visualizers/counting-sort.html" style="width:100%;height:420px;border:none;border-radius:8px;" title="Counting Sort Visualizer"></iframe>

---

## How It Connects

Counting sort is the foundational subroutine for radix sort, which sorts large integers by applying counting sort one digit at a time from least significant to most significant. Because counting sort is stable, each digit-level pass preserves the ordering established by previous passes, and the combination of passes correctly sorts the full integers. Understanding why stability is essential to radix sort is a key insight that flows directly from understanding counting sort's prefix-sum placement step.

[[radix-sort-via-counting-sort|Counting Sort as Radix Sort Base]]
[[sorting-comparison|Sorting Algorithm Comparison]]
[[arrays|Arrays]]

---

## Common Misconceptions

Misconception 1: "Counting sort violates the O(n log n) lower bound for sorting."
Reality: The O(n log n) lower bound applies to comparison-based sorting algorithms, which make decisions based on pairwise comparisons between elements. Counting sort is not comparison-based — it uses the integer values as array indices, which is a fundamentally different operation. There is no contradiction: the lower bound simply does not apply to non-comparison sorts. The cost is paid elsewhere: in the constraint that elements must be integers within a bounded range.

Misconception 2: "Counting sort is O(n) time."
Reality: Counting sort is O(n + k) time, where k is the range of values. If k is O(n), the algorithm is effectively O(n). But if k is much larger than n — for example, sorting 100 values in the range 0 to 1,000,000 — then k dominates and the algorithm is O(k) = O(1,000,000), which is far slower than merge sort's O(n log n) = O(100 * 7) ≈ O(700). Always check the k/n ratio before choosing counting sort.

Misconception 3: "The simple version of counting sort (output each value count[v] times) is equivalent to the prefix-sum version."
Reality: The simple version is correct but not stable: it writes all occurrences of a value consecutively without preserving the original relative order of those occurrences. For sorting plain integers where values carry no associated data, this does not matter. But when sorting objects by an integer key (for example, sorting student records by grade), the non-stable version can mix up records with equal keys. The prefix-sum version preserves their original relative order, which is essential when counting sort is used as a subroutine inside radix sort.

---

## Why It Matters in Practice

Counting sort is the right tool when you need to sort large quantities of integers drawn from a bounded range. Sorting millions of log events by hour of day (0-23), sorting exam scores (0-100), sorting character frequencies for a compression algorithm — these are all cases where k is small enough that counting sort's O(n + k) dominates comparison sort's O(n log n). Database systems use counting-sort-based algorithms internally for aggregation operations on integer columns.

In Python, the `collections.Counter` class performs the counting step of counting sort in a single pass. For the specific case of sorting integers in a small range, the simple (non-stable) version can be written in two lines using Counter, making it both the theoretically optimal and practically convenient choice.

---

## Interview Angle

Common question forms:
- "What is the time complexity of counting sort and when is it better than merge sort?"
- "Implement counting sort."
- "Is counting sort stable? How does the prefix-sum step ensure stability?"
- "How does counting sort extend to radix sort?"

Answer frame:
State O(n + k) time and space. Explain when it beats O(n log n) comparison sorts: when k is O(n), i.e., when the value range is not much larger than the number of elements. For stability: explain that the reverse-walk placement with prefix sums ensures equal elements from later in the input are placed at later positions, preserving original order. For radix sort: counting sort applied least-significant-digit to most-significant-digit; stability of each pass ensures correctness of the full sort.

---

## Related Notes

- [[sorting-comparison|Sorting Algorithm Comparison]]
- [[merge-sort|Merge Sort]]
- [[arrays|Arrays]]
- [[collections-module|Collections Module]]
