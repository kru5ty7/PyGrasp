---
title: 39 - Two Pointers Technique
description: A technique that uses two indices moving through an array to reduce many O(n²) brute-force problems to O(n) by exploiting sorted order or structural properties.
tags: [dsa, layer-10, two-pointers, arrays]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Two Pointers Technique

> Two pointers places a left and right index into an array and moves them toward each other (or at different speeds) based on a comparison, turning O(n²) brute-force pair-checking into O(n) linear scans — it is one of the most frequently used interview techniques for array and linked list problems.

---

## Quick Reference

**Core idea:**
- Two indices traverse a data structure, typically from opposite ends or at different speeds
- Opposite-ends variant: left starts at 0, right starts at end; move based on a comparison with a target
- Fast/slow pointer variant: both start at the same position; one advances two steps, one advances one step
- Sorted input is usually a prerequisite for the opposite-ends variant
- Reduces O(n²) nested-loop pair enumeration to O(n) single-pass
- Problems that fit: two-sum on sorted array, remove duplicates in-place, palindrome check, cycle detection

**Tricky points:**
- Two pointers only works when you can infer which pointer to move from the current state — this usually requires sorted order
- In-place modification problems (remove duplicates, move zeros) need a slow "write" pointer and a fast "read" pointer, not left-right pointers
- Avoid crossing pointers — the loop condition `left < right` prevents processing the same element twice
- Three-sum extends two-sum by fixing one element and running two pointers on the remainder — sort first, skip duplicates carefully
- Floyd's cycle detection (fast/slow on linked lists) does not require sorted order; it exploits the mathematical property that two pointers in a cycle must eventually meet

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Two-sum in sorted array | O(n) | O(1) |
| Three-sum | O(n²) | O(1) extra (ignoring output) |
| Remove duplicates in-place | O(n) | O(1) |
| Floyd's cycle detection | O(n) | O(1) |

---

## What It Is

Picture a tug-of-war rope stretched between two people. To find whether any two people on a sorted team roster add up to a target total weight, one person starts reading names from the lightest end and the other from the heaviest end. If the sum of the two weights they are pointing to is too large, the person at the heavy end steps inward (toward lighter weights). If the sum is too small, the person at the light end steps inward (toward heavier weights). If the sum is exactly right, they have found their pair. The key insight is that every inward step logically eliminates an entire set of combinations without checking them explicitly — the sorted order makes each comparison informative enough to rule out a direction.

This is the essence of the opposite-ends two pointers pattern. Sorted order means you know exactly which direction to move: if the current pair sum is too large, making the right element smaller can only help; making the left element larger can only hurt. You never need to revisit a combination you have passed. Over the full scan, the left pointer and right pointer together traverse at most n positions, giving O(n) total work compared to O(n²) for exhaustively checking all pairs.

The fast/slow pointer variant, also called Floyd's tortoise and hare algorithm, operates on a different principle. Imagine a circular running track. If two runners start at the same point — one running twice as fast as the other — the faster runner will always eventually lap the slower one and they will be at the same position again. If the track has no loop, the faster runner simply reaches the end first and there is no meeting. This property is the basis for cycle detection in linked lists: the slow pointer moves one step at a time, the fast pointer moves two steps, and if they ever point to the same node, a cycle is confirmed. The beauty is that this requires no extra memory — no visited set, no hash table — just two pointers.

---

## How It Actually Works

For the opposite-ends two-pointer pattern, the implementation requires three things: sorted input, a loop condition that stops when the pointers cross, and a rule for which pointer to move based on the current comparison. For two-sum, the rule is symmetric and deterministic: sum too large means move right pointer left, sum too small means move left pointer right. For problems like "container with most water," the rule is to move the pointer at the shorter wall inward, because that is the only direction that could increase the contained water.

The slow/fast pointer for in-place array modification uses a different structure: the slow pointer marks the position of the next valid write location, while the fast pointer scans forward through all elements. When the fast pointer finds a valid element (e.g., one that is not a duplicate), it writes it to the slow pointer's position and advances the slow pointer. This turns a two-pass algorithm (find valid elements, then compact) into a single pass.

```python
from typing import List, Optional


# --- Two-sum in sorted array (opposite ends) ---
def two_sum_sorted(numbers: List[int], target: int) -> List[int]:
    left, right = 0, len(numbers) - 1
    while left < right:
        current = numbers[left] + numbers[right]
        if current == target:
            return [left + 1, right + 1]  # 1-indexed per LeetCode convention
        elif current < target:
            left += 1   # sum too small: increase left
        else:
            right -= 1  # sum too large: decrease right
    return []


# --- Valid palindrome (opposite ends) ---
def is_palindrome(s: str) -> bool:
    cleaned = [c.lower() for c in s if c.isalnum()]
    left, right = 0, len(cleaned) - 1
    while left < right:
        if cleaned[left] != cleaned[right]:
            return False
        left += 1
        right -= 1
    return True


# --- Remove duplicates in-place (slow/fast pointers) ---
def remove_duplicates(nums: List[int]) -> int:
    if not nums:
        return 0
    slow = 0  # marks the tail of the unique section
    for fast in range(1, len(nums)):
        if nums[fast] != nums[slow]:
            slow += 1
            nums[slow] = nums[fast]
    return slow + 1  # count of unique elements


# --- Three-sum: fix one element, run two pointers on the rest ---
def three_sum(nums: List[int]) -> List[List[int]]:
    nums.sort()
    result = []
    for i in range(len(nums) - 2):
        if i > 0 and nums[i] == nums[i - 1]:
            continue  # skip duplicate starting element
        left, right = i + 1, len(nums) - 1
        while left < right:
            total = nums[i] + nums[left] + nums[right]
            if total == 0:
                result.append([nums[i], nums[left], nums[right]])
                while left < right and nums[left] == nums[left + 1]:
                    left += 1   # skip duplicates
                while left < right and nums[right] == nums[right - 1]:
                    right -= 1  # skip duplicates
                left += 1
                right -= 1
            elif total < 0:
                left += 1
            else:
                right -= 1
    return result


# --- Floyd's cycle detection on a linked list ---
class ListNode:
    def __init__(self, val: int = 0, next=None):
        self.val = val
        self.next = next

def has_cycle(head: Optional[ListNode]) -> bool:
    slow = head
    fast = head
    while fast and fast.next:
        slow = slow.next        # one step
        fast = fast.next.next   # two steps
        if slow is fast:        # pointers meet: cycle confirmed
            return True
    return False  # fast reached end: no cycle
```

## Visualizer

<iframe src="/visualizers/two-pointers.html" style="width:100%;height:400px;border:none;border-radius:8px;" title="Two Pointers Visualizer"></iframe>

---

## How It Connects

The two pointers technique is most powerful when applied to sorted arrays, which is why binary search and two pointers are often considered together. Binary search narrows a search space by repeatedly halving it; two pointers narrow it by converging from both ends. Both achieve O(log n) or O(n) from what would otherwise be O(n²) or O(n log n) brute force.

The fast/slow pointer variant is the standard approach for cycle detection in linked lists and is also used to find the midpoint of a list (stop when fast reaches the end — slow is at the midpoint) and to find the start of a cycle (a classic follow-up problem). These pointer manipulation techniques on linked lists form a separate cluster of important interview patterns.

[[arrays|Arrays]]
[[linked-lists|Linked Lists]]
[[binary-search|Binary Search]]
[[sliding-window|Sliding Window Technique]]

---

## Common Misconceptions

Misconception 1: Two pointers always requires a sorted array.
Reality: The opposite-ends variant requires sorted order to make each comparison informative. The slow/fast pointer variant for in-place array modification does not — it simply compacts valid elements to the front. Floyd's cycle detection does not require sorted order at all. The requirement depends on which variant you are using.

Misconception 2: Two pointers and sliding window are the same technique.
Reality: Both use two indices, but with different behaviours. Two pointers (opposite ends) move toward each other; sliding window always moves both pointers in the same direction. The purpose also differs: two pointers finds a pair satisfying a condition, while sliding window finds a contiguous subarray satisfying a constraint. They solve overlapping but distinct problem types.

---

## Why It Matters in Practice

Two pointers appears in a wide range of interview problems at every level of difficulty, from easy (valid palindrome, remove duplicates) through medium (three-sum, container with most water) to hard (trapping rain water, minimum window substring's extension with two-pass logic). Its O(n) time and O(1) space make it optimal for problems where sorting is either given or acceptable.

In production code, the fast/slow pointer technique for cycle detection is used in linked list implementations, and the slow/fast read-write pattern for in-place array compaction appears in filtering operations. Understanding both variants and when each applies makes you fluent in the pointer-manipulation patterns that underlie many low-level data structure operations.

---

## Interview Angle

Common question forms:
- "Given a sorted array, find two numbers that sum to a target."
- "Remove duplicates from a sorted array in-place."
- "Determine if a linked list has a cycle."
- "Given an array, find three numbers that sum to zero."

Answer frame:
State whether the input needs to be sorted (and sort it if not). Initialise the pointers. State the loop condition and the move rule for each pointer. Trace through one example to verify. Confirm O(n) time and O(1) space. For three-sum, mention the outer loop and the two-pointer inner loop and the duplicate-skipping logic.

---

## Related Notes

- [[arrays|Arrays]]
- [[linked-lists|Linked Lists]]
- [[binary-search|Binary Search]]
- [[sliding-window|Sliding Window Technique]]
- [[cycle-detection|Cycle Detection]]
