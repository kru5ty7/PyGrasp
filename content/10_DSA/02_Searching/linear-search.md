---
title: 27 - Linear Search
description: Linear search examines each element in sequence until the target is found or the collection is exhausted, making it the universal search for unsorted or unindexed data.
tags: [dsa, layer-10, searching, linear-search]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Linear Search

> Linear search is the baseline search algorithm — it makes no assumptions about the data, works on any collection, and is the search Python uses when you write `if x in my_list`.

---

## Quick Reference

**Core idea:**
- Examine each element in order from first to last
- Return the index (or element) when the target is found; signal failure when the collection is exhausted
- O(n) worst and average case; O(1) best case (target is the first element)
- Works on unsorted data, linked lists, generators, and any iterable
- Python's `in` operator on a list, `list.index()`, and `str.find()` all perform linear search internally

**Tricky points:**
- Linear search is the only option when data is unsorted and building a sorted copy or index is too expensive
- Searching a sorted array with linear search instead of binary search is a common inefficiency in production code
- The `in` operator on a Python `list` is O(n); on a Python `set` or `dict` it is O(1) — these are fundamentally different operations
- `list.index()` raises ValueError on missing elements; `list.find()` does not exist (that is a string method); catching the exception vs using `in` first is a tradeoff
- Sentinel optimisation reduces comparison overhead per iteration: append the target to the end of the array, then loop without a bounds check — the target will always be found, and you check at the end whether it was found within the original array or only at the sentinel

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case (target at index 0) | O(1) | O(1) |
| Average case | O(n) | O(1) |
| Worst case (not found or last element) | O(n) | O(1) |

---

## What It Is

Imagine looking for a specific book in a pile of unsorted books on a desk. You have no choice but to pick up each book, look at the title, put it back if it is not the one you want, and move to the next. If you are lucky, it is the first book you pick up. If you are unlucky, it is the last one, or it is not there at all. This is linear search: a sequential, exhaustive scan with no structural shortcuts.

The lack of assumptions is both linear search's greatest strength and its greatest limitation. It is the greatest strength because it works on literally any collection of comparable elements — unsorted arrays, linked lists, streams of data, files being read line by line, elements produced by a generator. No preprocessing is needed, no sorting, no indexing. The cost of using linear search is always just the cost of looking at elements, one at a time. This makes it correct and universally applicable.

The limitation is that "looking at elements one at a time" is inherently proportional to the size of the collection. If the collection has a million elements and the target is not present, you must examine all million. Binary search can find the same element or determine it is absent in about 20 comparisons — but only if the data is sorted. Linear search and binary search represent the two ends of the search algorithm spectrum: maximum generality with linear cost, versus strong precondition (sorted data) with logarithmic cost. Every search technique is a point on this tradeoff curve.

---

## How It Actually Works

The basic implementation loops from index 0 to n-1, comparing each element to the target. It returns the index immediately when a match is found and returns -1 (or raises an exception, or returns None) after exhausting the array without finding the target. The early return on success is what gives the O(1) best case and the O(n/2) expected case for a random target in a random array.

The sentinel optimisation eliminates the bounds check from the inner loop. By appending the target itself to the end of the array before searching, you guarantee that the loop will always terminate by finding the target — either at its true location or at the sentinel position. After the loop, a single check determines whether the found position was within the original array or at the sentinel. This saves one comparison per iteration (no `i < n` check), which can matter in tight loops over large arrays, though modern compilers often optimise this automatically.

```python
def linear_search(arr: list, target) -> int:
    """Linear search: returns index of target, or -1 if not found."""
    for i, val in enumerate(arr):
        if val == target:
            return i
    return -1


def linear_search_sentinel(arr: list, target) -> int:
    """Sentinel optimisation: removes bounds check from inner loop."""
    arr = arr + [target]  # append sentinel (work on a copy)
    i = 0
    while arr[i] != target:
        i += 1
    # Check if found within original array or only at sentinel
    return i if i < len(arr) - 1 else -1


# Python built-in equivalents
data = [4, 2, 7, 1, 9, 3]

# 'in' operator — O(n) for list, O(1) for set
print(7 in data)           # True
print(5 in data)           # False

# index() — returns first match, raises ValueError if absent
print(data.index(7))       # 2
try:
    data.index(5)
except ValueError:
    print("not found")     # not found

# Safe lookup pattern: check before indexing
if 7 in data:
    print(data.index(7))   # 2  (two passes — O(2n) but readable)

# String linear search
text = "hello world"
print(text.find("world"))  # 6 (returns -1 if not found)
print(text.index("world")) # 6 (raises ValueError if not found)

# Searching a linked list — must use linear search (no random access)
class Node:
    def __init__(self, val):
        self.val = val
        self.next = None

def search_linked_list(head: Node, target) -> bool:
    current = head
    while current:
        if current.val == target:
            return True
        current = current.next
    return False
```

---

## How It Connects

Linear search's O(n) cost is the motivating problem for binary search: if we accept the constraint that the data must be sorted, we can search in O(log n). Understanding linear search thoroughly — why it is slow, when it cannot be improved upon, and when it is the right choice — makes the value of binary search concrete. Linear search is also the inner operation in selection sort's minimum-finding loop, which reveals why selection sort is O(n²).

[[binary-search|Binary Search]]
[[selection-sort|Selection Sort]]
[[arrays|Arrays]]

---

## Common Misconceptions

Misconception 1: "The `in` operator in Python always performs a linear search."
Reality: The `in` operator dispatches to the `__contains__` method of the collection. For a `list`, `__contains__` is O(n) linear search. For a `set` or `frozenset`, `__contains__` is O(1) hash lookup. For a `dict`, `in` checks keys in O(1). For a sorted `list` used with `bisect`, there is no built-in `__contains__` override — you still get O(n). The cost of `in` depends entirely on the type of the collection, not on the operator itself.

Misconception 2: "You should always use index() with a try/except instead of checking with in first."
Reality: Whether to use `try/except` around `index()` or to use `if target in arr` before `arr.index(target)` is a style and performance tradeoff, not a correctness question. The `try/except` approach makes a single pass; the `in`-then-`index` approach makes two passes (both O(n)). For performance-sensitive code with frequent misses, `try/except` is faster. For readable code where misses are rare, `in`-then-`index` is clearer. Python's "ask forgiveness, not permission" idiom favours `try/except`, but both are correct.

Misconception 3: "Linear search on a sorted array is still O(n)."
Reality: In the worst case, yes. But for the case of searching for a target that is not present, a linear search on a sorted array can exit early: if the current element is already greater than the target, the target cannot be present. This reduces the average case for a miss from n/2 to n/4 comparisons on a sorted array. However, this is still O(n) — it does not change the asymptotic complexity. Binary search is still the correct choice for sorted data at any reasonable scale.

---

## Why It Matters in Practice

Linear search is the correct choice more often than its O(n) complexity suggests. For small collections (fewer than 20-30 elements), linear search is faster than binary search in practice because of lower overhead — no midpoint calculation, no conditional branching, simple sequential memory access. Python's `list.__contains__` and `list.index()` are implemented in C as optimised linear scans, and they are fast for small lists. For lists that are unsorted and infrequently searched, the O(n log n) cost of sorting to enable binary search exceeds the cost of the linear searches. For linked lists, generators, and streams, linear search is the only option.

The important engineering decision is recognising when to stop using linear search. If you are searching the same list many times, sorting once and using binary search (or converting to a set for O(1) membership tests) will pay off quickly. The break-even point depends on the size of the collection and the number of searches, but as a rule of thumb: if you search the same unsorted list more than O(log n) times, sort it or convert it.

---

## Interview Angle

Common question forms:
- "What is the time complexity of searching a list in Python?"
- "When is linear search the correct choice over binary search?"
- "What does Python's `in` operator do on a list vs a set?"

Answer frame:
State O(n) worst and average case, O(1) best case. Clarify that Python's `in` on a list is O(n) while `in` on a set is O(1) — this distinction trips up many candidates. Describe when linear search is appropriate: unsorted data, data structures without random access (linked lists), small collections where the overhead of sorting or indexing is not worth it. Conclude by saying the practical fix for repeated searches is either sorting (enables binary search) or hashing (enables O(1) lookup).

---

## Related Notes

- [[binary-search|Binary Search]]
- [[arrays|Arrays]]
- [[linked-lists|Linked Lists]]
- [[collections-module|Collections Module]]
