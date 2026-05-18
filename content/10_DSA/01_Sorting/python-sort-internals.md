---
title: 26 - Timsort — Python's Sorting Algorithm
description: Timsort is Python's built-in sorting algorithm, a hybrid of merge sort and insertion sort that exploits naturally ordered subsequences in real-world data for exceptional performance.
tags: [dsa, layer-10, sorting, timsort, python-internals]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Timsort — Python's Sorting Algorithm

> Timsort is not an academic algorithm — it was engineered for the data that real programs actually produce, and the result is a sort that runs in O(n) time on data that is already sorted or nearly sorted.

---

## Quick Reference

**Core idea:**
- Phase 1: scan the array for naturally sorted subsequences called runs; extend short runs to a minimum length using insertion sort
- Phase 2: merge runs on a stack using a modified merge sort, maintaining an invariant about relative run lengths that ensures O(n log n) total merge work
- The galloping optimisation: when one run is dominating during a merge, switch to binary-search-based bulk copying rather than element-by-element comparison
- O(n) best case on sorted or reverse-sorted input; O(n log n) worst case; stable
- Used in Python (`list.sort()`, `sorted()`), Java (for object arrays), Android, and Swift
- Tim Peters designed it in 2002 specifically for CPython

**Tricky points:**
- `list.sort()` sorts in-place and returns None; `sorted()` returns a new list and leaves the original unchanged
- Both accept a `key` function and a `reverse` flag
- The `key` function is called exactly once per element (a Schwartzian transform is applied internally)
- Timsort requires a total ordering — if your comparison function is inconsistent, the result is undefined
- The minimum run length (`minrun`) is chosen to be between 32 and 64 such that n/minrun is a power of two or slightly less, optimising the final merge
- Timsort's stability guarantee means `sorted(records, key=lambda r: r.age)` preserves original order among records with the same age

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case (already sorted) | O(n) | O(n) |
| Typical real-world data | O(n log n) | O(n) |
| Worst case (adversarial input) | O(n log n) | O(n) |

---

## What It Is

Pure merge sort treats every input as if it were completely random: it splits blindly at the midpoint, recurses, and merges, regardless of whether the data already has structure. This is efficient in theory but wasteful in practice, because real-world data is rarely random. A list of timestamps in a server log is usually mostly sorted, with occasional out-of-order entries where events from different threads interleaved. A list of items in a shopping cart is usually in the order the user added them, which is often nearly sorted by category. An array of records pulled from a database table is often pre-sorted because the database returned them in index order.

Tim Peters recognised this in 2002 and designed Timsort around the insight that real data has naturally occurring sorted subsequences. His algorithm first identifies these subsequences — called runs — and then merges them using merge sort. If the data happens to already be sorted, Timsort finds a single run covering the entire array and completes in O(n) time. If the data is completely random with no natural order, Timsort extends short runs to a minimum length using insertion sort (which is fast for short sequences due to low overhead) and then merges, achieving O(n log n). For the vast majority of real inputs — which lie somewhere between fully sorted and fully random — Timsort adapts its effort to the structure present.

The galloping optimisation addresses another real-world pattern: during a merge, one run often dominates for a long stretch. If the algorithm detects that elements from the same run have been winning for several consecutive steps, it switches from element-by-element comparison to a binary search within the other run to find where the next element from the dominant run belongs. This allows it to copy long stretches of elements with a single memory operation rather than looping, which can give a significant practical speedup on data with long sorted regions.

---

## How It Actually Works

The first phase computes the minimum run length (`minrun`). It chooses a value between 32 and 64 such that n divided by minrun is close to a power of two. This guarantees that the merge phase will create a roughly balanced merge tree. Then it scans the array from left to right, identifying runs. A run is a maximal ascending sequence (arr[i] <= arr[i+1]) or a descending sequence (arr[i] > arr[i+1]). Descending runs are reversed in place to become ascending. If a run is shorter than minrun, it is extended to minrun using insertion sort on the elements immediately following the run. Short runs are extended with insertion sort because insertion sort has minimal overhead for small sequences and is adaptive — it handles nearly-sorted runs efficiently.

The second phase maintains a stack of pending runs. After each run is identified, it is pushed onto the stack. Timsort then checks two invariants: if X, Y, Z are the top three run lengths on the stack, the invariants Z > Y + X and Y > X must both hold. If either is violated, runs are merged (the smaller adjacent pair) until the invariants are restored. This invariant guarantees that runs on the stack remain approximately geometrically increasing in length, which ensures that the total merge work across all merges is O(n log n) even in the worst case.

```python
# Python's sort is implemented in C (Objects/listobject.c) — you cannot
# inspect it directly. But you can observe its behaviour and use it correctly.

# list.sort(): in-place, returns None
data = [3, 1, 4, 1, 5, 9, 2, 6]
data.sort()
print(data)  # [1, 1, 2, 3, 4, 5, 6, 9]

# sorted(): returns new list, original unchanged
original = [3, 1, 4, 1, 5]
result = sorted(original)
print(original)  # [3, 1, 4, 1, 5] — unchanged
print(result)    # [1, 1, 3, 4, 5]

# key function — called once per element (not on every comparison)
words = ['banana', 'Apple', 'cherry', 'date']
print(sorted(words, key=str.lower))  # ['Apple', 'banana', 'cherry', 'date']

# key with reverse
data = [('Alice', 30), ('Bob', 25), ('Carol', 35)]
data.sort(key=lambda x: x[1], reverse=True)
print(data)  # [('Carol', 35), ('Alice', 30), ('Bob', 25)]

# Stability demonstration
records = [('A', 2), ('B', 1), ('C', 2), ('D', 1)]
by_val = sorted(records, key=lambda r: r[1])
print(by_val)  # [('B', 1), ('D', 1), ('A', 2), ('C', 2)]
# B before D (original order), A before C (original order) — stable

# Multi-level sort using stability: sort by last name, then by first name
# Two separate stable sorts gives the same result as one key=(last, first) sort
people = [('John', 'Smith'), ('Alice', 'Jones'), ('Bob', 'Smith')]
people.sort(key=lambda p: p[0])   # sort by first name first
people.sort(key=lambda p: p[1])   # then by last name (stable: first-name order preserved within each last name)
print(people)  # [('Alice', 'Jones'), ('Bob', 'Smith'), ('John', 'Smith')]

# Schwartzian transform (key= does this automatically)
# Without key=, this manual pattern was used in older Python:
decorated = [(str.lower(w), w) for w in words]
decorated.sort()
result = [w for _, w in decorated]
```

---

## How It Connects

Timsort is the convergence point of the sorting section. Merge sort provides the outer structure (merging runs), and insertion sort provides the inner structure (extending short runs). The galloping mode is an optimisation that makes the merge step faster for real data. Understanding why Timsort is better than pure merge sort on real data is only possible after understanding what merge sort does and what insertion sort's adaptivity means.

[[merge-sort|Merge Sort]]
[[insertion-sort|Insertion Sort]]
[[sorting-comparison|Sorting Algorithm Comparison]]

---

## Common Misconceptions

Misconception 1: "list.sort() and sorted() have the same performance."
Reality: Both use Timsort and have the same asymptotic complexity. However, `list.sort()` is slightly faster in practice because it sorts in-place and avoids the overhead of allocating a new list. For large lists where memory allocation is significant, `list.sort()` is preferred when you do not need to preserve the original. For small lists or when you need the original unchanged, the difference is negligible.

Misconception 2: "The key= parameter makes sorting slower because it is called on every comparison."
Reality: Python's sort applies the key function once per element at the start (a decorated sort or Schwartzian transform), stores the key values in a temporary array, sorts using those precomputed keys, and discards the temporary array. The key function is not called during comparisons — it is called exactly n times total. This means even expensive key functions do not slow down the comparison phase.

Misconception 3: "Timsort is simply merge sort with insertion sort as a base case."
Reality: This description captures part of the algorithm but misses the most important aspect: Timsort detects and exploits naturally ordered runs in the input. A standard hybrid merge sort with insertion sort as a base case would split at fixed sizes and achieve no better than O(n log n) on all inputs. Timsort achieves O(n) on sorted or reverse-sorted input because it identifies the entire array as a single run and merges nothing. The run-detection and stack-based merge invariant are what make Timsort genuinely different from a naive hybrid.

---

## Why It Matters in Practice

Every time you call `sorted()` or `list.sort()` in Python, you are using Timsort. Understanding what it does means you can make informed decisions about performance. Sorting a list that is already sorted is O(n) — you should feel comfortable sorting and re-sorting without fear. Sorting a list that is being assembled incrementally might be better handled with `bisect.insort()` (which maintains sorted order with O(log n) search and O(n) insert) rather than repeatedly calling sort. For very large datasets that are nearly sorted, Timsort will dramatically outperform any hand-rolled O(n log n) algorithm.

The design of Timsort is also a lesson in engineering: the best algorithm for real-world use is not always the theoretically cleanest algorithm. Timsort is more complex than pure merge sort, but that complexity is purposeful — every part of it addresses a specific pattern observed in real data. This is the kind of thinking that separates engineering from textbook algorithm application.

---

## Interview Angle

Common question forms:
- "What sorting algorithm does Python use?"
- "What is the time complexity of Python's sort?"
- "What is the difference between list.sort() and sorted()?"
- "Why is Timsort better than merge sort for real-world data?"

Answer frame:
Name Timsort immediately and attribute it to Tim Peters (2002). State O(n log n) worst case, O(n) best case on sorted input, stable. Explain the two phases: run detection (extended with insertion sort if short) and merge (with the stack-invariant merge strategy). For list.sort() vs sorted(): same algorithm, list.sort() is in-place and returns None, sorted() returns a new list. For the "why better" question: Timsort exploits natural order in real data through run detection and galloping, giving sub-O(n log n) performance on partially sorted inputs that pure merge sort cannot achieve.

---

## Related Notes

- [[merge-sort|Merge Sort]]
- [[insertion-sort|Insertion Sort]]
- [[quick-sort|Quick Sort]]
- [[sorting-comparison|Sorting Algorithm Comparison]]
- [[lists|Lists]]
