---
title: 40 - Sliding Window Technique
description: A technique that maintains a contiguous subarray (the window) and slides it through the array by expanding or shrinking based on a constraint, converting O(n²) subarray problems to O(n).
tags: [dsa, layer-10, sliding-window, arrays, subarray]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Sliding Window Technique

> The sliding window maintains a subarray defined by two pointers moving in the same direction, expanding or contracting to satisfy a constraint — every developer working with array or string problems must know it because it reduces O(n²) brute-force subarray scanning to O(n).

---

## Quick Reference

**Core idea:**
- Two pointers (left and right) both move forward, defining a window `arr[left:right+1]`
- Fixed window: right advances one step, left follows at a fixed distance — used when window size k is given
- Variable window: right expands until constraint is violated, then left shrinks until constraint is restored
- The window invariant is the property the window must always satisfy
- Python `collections.defaultdict` and `collections.deque` are the standard window state containers
- Each element is added to the window exactly once and removed at most once — total O(n) operations

**Tricky points:**
- The window invariant must be identified before writing code — it is the key to knowing when to expand and when to shrink
- Off-by-one between `right - left` and `right - left + 1` for window length is the most common bug
- Some problems require tracking the maximum/minimum in the window — use a monotonic deque for O(1) per step
- Variable windows where the left pointer can jump (not just increment by one) are valid but need careful state management
- Problems asking for the longest window that satisfies a condition use a different loop structure than those asking for the shortest

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Fixed window sum/average | O(n) | O(1) |
| Longest substring without repeats | O(n) | O(alphabet size) |
| Minimum window substring | O(n) | O(alphabet size) |
| Sliding window maximum (monotonic deque) | O(n) | O(k) |

---

## What It Is

Imagine reading a novel one page at a time through a physical frame that shows exactly five pages at a time. To know the average sentiment of every five-page passage, you could pick up the book, read pages 1–5, write down the score, read pages 2–6, write down the score, and so on. This is the brute-force approach: re-read the entire window from scratch for each position. Now imagine instead that you simply slide the frame one page to the right each time: you remove the contribution of the page that just left the frame and add the contribution of the page that just entered. You do a constant amount of work per slide. The frame — the window — slides through the book, and you maintain a running tally rather than computing from scratch each time. That is the sliding window technique for fixed-size windows.

Variable-size windows are the more interesting and more common case in interviews. Here you do not know the window size in advance; instead, you have a constraint (e.g., "the window must contain at most two distinct characters") and you want to find the largest or smallest window that satisfies it. The right pointer grows the window by including new elements; whenever the constraint is violated, the left pointer shrinks the window by excluding elements from the left until the constraint is satisfied again. The current window always satisfies the constraint; the best window seen so far is tracked separately.

The critical concept is the window invariant — the property that the window must satisfy at all times. Before writing any code, ask: "What condition must always be true about the elements currently in the window?" For "longest substring without repeating characters," the invariant is that all characters in the window are distinct. For "minimum window substring," the invariant is that the window may or may not contain all required characters (you grow until it does, then shrink to find the minimum). Naming the invariant explicitly makes it clear when to expand (the invariant holds and you want to try including more) and when to contract (the invariant is violated and you need to restore it).

---

## How It Actually Works

The implementation structure for a variable sliding window is a while-inside-for loop (or equivalently two nested pointers). The outer loop advances the right pointer, adding the new element to the window's state. The inner while loop advances the left pointer, removing elements from the window's state, until the invariant is restored. After the inner loop, the window is valid, and you update the best result seen so far.

The window state is the data structure you maintain to know whether the invariant holds. For character frequency problems, a `dict` or `Counter` tracking character counts serves as the state. For maximum-in-window problems, a monotonic deque (where elements are stored in decreasing order) gives the window's maximum in O(1). Identifying the right state representation is the design challenge; the loop structure is always the same.

```python
from collections import defaultdict, deque
from typing import List


# --- Fixed window: maximum sum of k consecutive elements ---
def max_sum_fixed(arr: List[int], k: int) -> int:
    if len(arr) < k:
        return 0
    window_sum = sum(arr[:k])
    best = window_sum
    for i in range(k, len(arr)):
        window_sum += arr[i] - arr[i - k]  # slide: add new, remove old
        best = max(best, window_sum)
    return best


# --- Variable window: longest substring without repeating characters ---
def length_of_longest_substring(s: str) -> int:
    char_count: dict[str, int] = defaultdict(int)
    left = 0
    best = 0
    for right in range(len(s)):
        char_count[s[right]] += 1
        # Shrink window while invariant is violated (duplicate exists)
        while char_count[s[right]] > 1:
            char_count[s[left]] -= 1
            if char_count[s[left]] == 0:
                del char_count[s[left]]
            left += 1
        best = max(best, right - left + 1)
    return best


# --- Variable window: minimum window containing all required characters ---
def min_window(s: str, t: str) -> str:
    if not t or not s:
        return ""

    need: dict[str, int] = defaultdict(int)
    for c in t:
        need[c] += 1

    have: dict[str, int] = defaultdict(int)
    formed = 0                     # count of characters meeting their required frequency
    required = len(need)           # number of distinct characters needed

    left = 0
    best_len = float('inf')
    best_left = 0

    for right in range(len(s)):
        c = s[right]
        have[c] += 1
        if c in need and have[c] == need[c]:
            formed += 1

        # Shrink from the left while the window contains all required chars
        while formed == required:
            if right - left + 1 < best_len:
                best_len = right - left + 1
                best_left = left
            lc = s[left]
            have[lc] -= 1
            if lc in need and have[lc] < need[lc]:
                formed -= 1
            left += 1

    return s[best_left:best_left + best_len] if best_len != float('inf') else ""


# --- Sliding window maximum: monotonic deque ---
def sliding_window_max(nums: List[int], k: int) -> List[int]:
    dq: deque[int] = deque()  # stores indices; front is always the maximum
    result = []

    for right in range(len(nums)):
        # Remove elements outside the current window
        while dq and dq[0] < right - k + 1:
            dq.popleft()
        # Maintain decreasing order: remove smaller elements from the back
        while dq and nums[dq[-1]] < nums[right]:
            dq.pop()
        dq.append(right)
        # Window is full once right >= k - 1
        if right >= k - 1:
            result.append(nums[dq[0]])

    return result


# Quick tests
print(max_sum_fixed([2, 1, 5, 1, 3, 2], 3))           # 9
print(length_of_longest_substring("abcabcbb"))         # 3
print(min_window("ADOBECODEBANC", "ABC"))              # "BANC"
print(sliding_window_max([1, 3, -1, -3, 5, 3, 6, 7], 3))  # [3,3,5,5,6,7]
```

---

## How It Connects

The sliding window technique is closely related to two pointers: both use a left and right index on an array. The key structural difference is that sliding window moves both pointers in the same direction (always advancing through the array), while the opposite-ends two pointers variant converges toward the centre. Both achieve O(n) by avoiding redundant work through the observation that each element is processed a constant number of times.

The monotonic deque pattern used for sliding window maximum is a general technique for maintaining range minimum/maximum queries in O(1) per element. It appears in other problems (jump game, largest rectangle in histogram) and is worth understanding as a standalone building block.

[[arrays|Arrays]]
[[two-pointers|Two Pointers Technique]]
[[hash-tables|Hash Tables]]
[[deques|Deques]]

---

## Common Misconceptions

Misconception 1: Sliding window always produces an O(n) solution because the right pointer only moves forward.
Reality: The time complexity is O(n) total for pointer movements, but the window state maintenance can add a multiplier. If the state is a sorted structure (like a balanced BST for order statistics), each update is O(log n), giving O(n log n) overall. The O(n) guarantee applies when state updates are O(1) — which is the case for hash-based counters and monotonic deques, but not for all window state types.

Misconception 2: Sliding window and dynamic programming are interchangeable for subarray problems.
Reality: Sliding window is applicable when the problem has a monotonic property — adding elements to the window makes it "more valid" in a way that adding more elements cannot undo (or vice versa). DP is needed when the optimal subarray at position i depends on choices made at non-adjacent earlier positions. If the constraint is not monotone (e.g., the window sum must equal exactly k), sliding window typically does not apply and DP or prefix sums are required.

---

## Why It Matters in Practice

The sliding window technique converts a broad class of "find the best subarray" problems from quadratic to linear time. In text processing — finding the shortest passage containing a set of keywords, detecting repeated substrings, computing moving averages in time series data — the sliding window is the natural and efficient solution. Understanding it cleanly separates developers who reach for nested loops from those who recognise the linear structure.

In streaming data systems, the fixed-size sliding window (last k elements) is the fundamental model for rolling statistics: moving averages, rolling maximum drawdown in financial data, sliding window rate limiters in API design. The conceptual model carries directly from the algorithmic pattern to the systems design pattern.

---

## Interview Angle

Common question forms:
- "Find the longest substring with at most k distinct characters."
- "Find the minimum contiguous subarray with sum at least target."
- "Find the maximum average of any subarray of length k."

Answer frame:
Identify whether the window is fixed or variable. Name the window invariant — what property the window must satisfy. Describe the expand (right pointer) and shrink (left pointer) conditions. Choose the window state data structure. State O(n) time and the space used by the state. Trace one example.

---

## Related Notes

- [[arrays|Arrays]]
- [[two-pointers|Two Pointers Technique]]
- [[hash-tables|Hash Tables]]
- [[deques|Deques]]
- [[dynamic-programming|Dynamic Programming]]
