---
title: 01 - Big O Notation
description: Big O notation describes how an algorithm's time or space requirements scale as input size grows.
tags: [dsa, layer-10, complexity, big-o]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Big O Notation

> Big O notation is the language of algorithmic efficiency — the standard way developers and interviewers communicate how a solution behaves at scale.

---

## Quick Reference

**Core idea:**
- Big O describes the upper bound on growth rate, not the exact running time
- We drop constants: O(2n) becomes O(n), O(500) becomes O(1)
- We drop lower-order terms: O(n² + n) becomes O(n²)
- Common classes in ascending cost: O(1) < O(log n) < O(n) < O(n log n) < O(n²) < O(2ⁿ)
- Python list `append` is O(1) amortized — occasionally O(n) but averages out
- Space complexity follows the same notation — measures memory, not time

**Tricky points:**
- Best/average/worst case are different things; Big O usually refers to worst unless stated otherwise
- O(1) does not mean fast — it means constant relative to input size
- Amortized analysis averages cost over a sequence of operations, not a single call
- Two nested loops over different inputs is O(n × m), not O(n²)
- Python dict lookup is O(1) average, but O(n) worst case due to hash collisions

---

## Complexity

| Class | n = 10 | n = 100 | n = 1000 |
|---|---|---|---|
| O(1) | 1 | 1 | 1 |
| O(log n) | ~3 | ~7 | ~10 |
| O(n) | 10 | 100 | 1,000 |
| O(n log n) | ~33 | ~664 | ~9,966 |
| O(n²) | 100 | 10,000 | 1,000,000 |
| O(2ⁿ) | 1,024 | 1.27 × 10³⁰ | astronomical |

Space complexity: varies by algorithm — O(1) for in-place, O(n) for most recursive solutions.

---

## What It Is

Think of a library with a card catalogue. If the books are sorted alphabetically and you use binary search through the catalogue, the number of steps you take grows only by one each time the library doubles in size. That is logarithmic growth — adding a million books barely affects how long your search takes. Now imagine instead that you had to walk past every book to find yours: that is linear growth. And if you had to compare every book against every other book, that is quadratic growth — and the library very quickly becomes unusable.

Big O notation captures this intuition mathematically. It describes the relationship between the size of the input, usually called n, and the number of elementary operations the algorithm requires. The notation uses capital O with the growth function written inside parentheses. When we write O(n²), we are saying: for large enough inputs, the number of steps is proportional to the square of the input size. The constant of proportionality does not matter — we care about the shape of the curve, not where it starts.

The reason we drop constants and lower-order terms is that they become irrelevant at scale. If algorithm A takes 100n steps and algorithm B takes n² steps, algorithm A is faster for every input larger than 100. At n = 10,000 the difference is between one million and one hundred million operations. Asymptotic analysis — analysis of behaviour as n approaches infinity — is the right lens for choosing between algorithms because real inputs grow, hardware gets faster uniformly, and only the growth rate determines which algorithm wins at scale.

---

## How It Actually Works

Big O is a mathematical notation borrowed from number theory. Formally, f(n) is O(g(n)) if there exist constants c and n₀ such that f(n) ≤ c × g(n) for all n ≥ n₀. In plain terms: beyond some threshold input size, g(n) scaled by some constant is always an upper bound on f(n). This is a worst-case upper bound. Theta notation (Θ) describes a tight bound (both upper and lower), and Omega notation (Ω) describes a lower bound — but in practice, most engineers use Big O for all three, meaning "roughly grows like this."

Amortized analysis handles data structures where most operations are cheap but occasional operations are expensive. Python's list `append` is the canonical example: the list over-allocates capacity, so most appends are O(1). When the capacity is exhausted, Python allocates a new array roughly twice the size and copies all existing elements — that single append is O(n). But because the expensive copy only happens after n cheap appends, the average (amortized) cost per append is still O(1). The total cost for n appends is O(n), so the amortized cost per operation is O(1).

```python
import sys
import timeit

# Demonstrate growth rates empirically
def o_1_example(lst):
    return lst[0]  # constant: index lookup

def o_n_example(lst, target):
    for item in lst:  # linear: scan every element
        if item == target:
            return True
    return False

def o_n2_example(lst):
    count = 0
    for i in lst:          # quadratic: every pair
        for j in lst:
            count += 1
    return count

# Amortized O(1) append — see occasional resize cost
lst = []
for i in range(10):
    old_size = sys.getsizeof(lst)
    lst.append(i)
    new_size = sys.getsizeof(lst)
    if new_size != old_size:
        print(f"Resize at len={len(lst)}: {old_size} -> {new_size} bytes")

# Common Python operation complexities
data = list(range(1000))
d = {i: i for i in range(1000)}

# O(1): index access, dict lookup, list append, set membership
_ = data[500]          # O(1)
_ = d[500]             # O(1) average
_ = 500 in set(data)   # O(1)

# O(n): list search, list insert at position 0, list delete
_ = 500 in data        # O(n)
data.insert(0, -1)     # O(n) — shifts all elements right
data.pop(0)            # O(n) — shifts all elements left

# O(n log n): sorting
sorted_data = sorted(data)  # O(n log n) — Timsort
```

---

## How It Connects

Understanding Big O is a prerequisite for every other data structure note. When we say a hash table offers O(1) lookup, or a heap offers O(log n) push, those claims are only meaningful if you understand what the notation promises and where it breaks down under worst-case conditions.

The hash table's O(1) average and O(n) worst case is a direct consequence of hash collisions — the collision behaviour determines when the average-case and worst-case diverge.

[[hash-tables|Hash Tables]]

The difference between O(log n) and O(n) search is the entire motivation for binary search trees and balanced trees — seeing Big O as a decision-making tool is what makes choosing the right data structure possible.

[[binary-search-trees|Binary Search Trees]]

---

## Common Misconceptions

Misconception 1: "O(1) means the operation is instant or negligible."
Reality: O(1) means the operation's cost does not grow with input size. A constant-time operation could still take milliseconds — it just takes the same amount of time whether n is 10 or 10,000,000.

Misconception 2: "The best-case complexity is what matters for well-written code."
Reality: Best-case analysis is almost never useful. We choose algorithms based on average or worst-case behaviour because we cannot control what inputs we receive in production. An algorithm that is O(1) in the best case but O(n²) in the worst case is an O(n²) algorithm for planning purposes.

Misconception 3: "O(n log n) is close to O(n), so it doesn't matter much."
Reality: For large n, the difference is meaningful. At n = 1,000,000, O(n) is one million operations while O(n log n) is roughly twenty million. For sorting, this is unavoidable — but for search, using a hash table's O(1) instead of O(n log n) binary-searched sorted list makes a measurable difference.

---

## Why It Matters in Practice

When a service starts handling ten times the traffic, algorithms that worked fine at small scale begin to fail. A quadratic algorithm that ran in 10ms on 100 items takes 10 seconds on 10,000 items — the same growth that took years of load increase to reveal. Big O gives engineers a vocabulary to reason about these scaling cliffs before they happen, during design and code review.

In Python specifically, knowing the complexity of built-in operations prevents common performance traps. Using `list.pop(0)` instead of `deque.popleft()` turns a queue implementation from O(1) per dequeue to O(n), and under production load that difference causes queue processing to grind to a halt. These are not theoretical concerns — they appear regularly in profiler output and postmortems.

---

## Interview Angle

Common question forms:
- "What is the time complexity of your solution?"
- "Can you do better than O(n²)?"
- "What is the space complexity of this approach?"
- "Why is Python's list append O(1) amortized rather than O(1)?"

Answer frame:
State the complexity class, name the dominant operation or loop structure that drives it, and explain what n represents in context. Then address space separately. For amortized questions, describe the occasional expensive operation and the averaging argument. Always mention whether you are describing average or worst case, because interviewers may be testing whether you know the distinction.

---

## Related Notes

- [[arrays|Arrays]]
- [[hash-tables|Hash Tables]]
- [[binary-search-trees|Binary Search Trees]]
