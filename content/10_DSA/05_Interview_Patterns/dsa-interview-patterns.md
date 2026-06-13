---
title: 53 - DSA Interview Patterns
description: Most coding interview problems reduce to one of about ten recurring patterns - learn the pattern and its template, and unfamiliar problems become recognizable on sight.
tags: [dsa, layer-10, interviews, patterns, two-pointers, sliding-window, dynamic-programming]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-06-13
---

# DSA Interview Patterns

> Coding interviews recycle about ten structural patterns endlessly - learn the pattern and its template, not the problem, and any variation becomes solvable on sight.

---

## Quick Reference

**Core idea:**
- The vast majority of coding interview questions are variations of ~10 canonical patterns
- Each pattern has a reusable template that adapts to the specific problem
- Recognizing the pattern is the hard part; writing the template code is mechanical once recognized
- Many patterns combine (e.g. sliding window + hash map, DFS + memoization = top-down DP)
- Stating the pattern name out loud ("this is a top-K problem, I'll use a heap") signals strong fundamentals to an interviewer

**Tricky points:**
- Sliding window has two flavors - fixed-size and variable-size - and the loop invariant differs between them
- Two pointers requires sorted input (or sortable in O(n log n)) - using it on unsorted data without sorting first is a common silent bug
- "Top K" almost always means a **min-heap of size K** for the K largest, not a max-heap - this trips people up because it feels backwards
- DP problems often have an O(n) or O(1)-space rolling-array optimization once the O(n*m) table version works - mention it even if you don't implement it
- Backtracking solutions must "undo" state (pop from path, unmark visited) on the way back up, or sibling branches see corrupted state

---

## What It Is

Imagine a locksmith who has seen thousands of locks. A new lock looks unfamiliar at first glance, but the locksmith doesn't start from first principles - they recognize the pin configuration as a variant of a mechanism they've picked a hundred times before, and they reach for the right tool immediately. Coding interviews work the same way. The 500+ problems on a site like LeetCode look like 500 different problems, but they are overwhelmingly built from the same ~10 underlying structural patterns: two pointers, sliding window, fast/slow pointers, merge intervals, top-K via heap, binary search on an answer space, BFS/DFS traversal, backtracking over subsets/permutations, the 0/1 knapsack DP family, and topological sort / union-find for dependency graphs.

A candidate who has internalized these patterns reads a new problem, identifies which pattern (or combination of patterns) it maps to, states that recognition out loud, and then writes the adapted template. A candidate without this framework re-derives an approach from scratch under time pressure - which is slower, more error-prone, and reads as weaker to an interviewer even when the candidate eventually arrives at a correct solution.

This note is not a substitute for the dedicated notes on each technique - it is the index that maps "the kind of problem you'll be handed" to "the template you reach for", with the templates collected in one place for quick review before an interview.

---

## How It Actually Works

**Pattern 1 - Two Pointers**

Use two indices that move through a sorted (or sortable) sequence, converging or moving in tandem, to avoid an O(n^2) nested loop.

```python
def two_sum_sorted(nums: list[int], target: int) -> tuple[int, int] | None:
    left, right = 0, len(nums) - 1
    while left < right:
        total = nums[left] + nums[right]
        if total == target:
            return left, right
        if total < target:
            left += 1
        else:
            right -= 1
    return None
```

Variants: removing duplicates in place, partitioning an array around a pivot (Dutch national flag), checking palindromes from both ends.

---

**Pattern 2 - Sliding Window**

Maintain a contiguous window over an array or string, expanding the right edge and shrinking the left edge based on a constraint, to avoid recomputing a property from scratch for every window.

```python
def longest_substring_k_distinct(s: str, k: int) -> int:
    counts: dict[str, int] = {}
    left = best = 0
    for right, ch in enumerate(s):
        counts[ch] = counts.get(ch, 0) + 1
        while len(counts) > k:
            counts[s[left]] -= 1
            if counts[s[left]] == 0:
                del counts[s[left]]
            left += 1
        best = max(best, right - left + 1)
    return best
```

Fixed-size windows (e.g. "max sum of any 5 consecutive elements") use a simpler invariant: add the new element, subtract the element leaving the window, no inner `while` loop needed.

---

**Pattern 3 - Fast & Slow Pointers**

Two pointers moving through a linked structure at different speeds, used for cycle detection and finding midpoints without a second pass.

```python
def has_cycle(head: "ListNode | None") -> bool:
    slow = fast = head
    while fast and fast.next:
        slow = slow.next
        fast = fast.next.next
        if slow is fast:
            return True
    return False
```

Once a cycle is detected, resetting one pointer to `head` and advancing both one step at a time finds the cycle's start node - this is Floyd's algorithm.

---

**Pattern 4 - Merge Intervals**

Sort intervals by start time, then walk through them merging any interval whose start is within the current merged interval's end.

```python
def merge_intervals(intervals: list[list[int]]) -> list[list[int]]:
    intervals.sort(key=lambda iv: iv[0])
    merged: list[list[int]] = []
    for start, end in intervals:
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return merged
```

The sort is what makes this O(n log n) instead of O(n^2) - without it, you'd need to compare every interval against every other interval.

---

**Pattern 5 - Top-K Elements (Heap)**

Maintain a heap of size K to track the K largest (or smallest) elements seen so far without sorting the entire collection.

```python
import heapq
from collections import Counter

def top_k_frequent(nums: list[int], k: int) -> list[int]:
    counts = Counter(nums)
    return heapq.nlargest(k, counts.keys(), key=counts.get)

def kth_largest_in_stream(stream: list[int], k: int) -> int:
    heap: list[int] = []
    for num in stream:
        heapq.heappush(heap, num)
        if len(heap) > k:
            heapq.heappop(heap)
    return heap[0]  # smallest element in the heap = kth largest overall
```

For "K largest", use a **min-heap of size K** (pop the smallest when the heap overflows). This is the most common point of confusion - it feels backwards but it's correct.

---

**Pattern 6 - Modified Binary Search (search on the answer space)**

When the question asks for the minimum/maximum value satisfying some condition, and that condition is monotonic, binary search over the *answer* rather than over an array index.

```python
def min_eating_speed(piles: list[int], hours: int) -> int:
    def hours_needed(speed: int) -> int:
        return sum(-(-pile // speed) for pile in piles)  # ceiling division

    low, high = 1, max(piles)
    while low < high:
        mid = (low + high) // 2
        if hours_needed(mid) <= hours:
            high = mid
        else:
            low = mid + 1
    return low
```

The signal that this pattern applies: the problem says "minimum X such that Y is possible" or "maximum X such that Y is possible", and Y becomes easier (or impossible) monotonically as X increases.

---

**Pattern 7 - Tree/Graph BFS & DFS Templates**

BFS with a queue for level-by-level traversal (shortest path in unweighted graphs, level order); DFS with recursion or an explicit stack for path-based problems.

```python
from collections import deque

def level_order(root) -> list[list[int]]:
    if not root:
        return []
    result, queue = [], deque([root])
    while queue:
        level = []
        for _ in range(len(queue)):
            node = queue.popleft()
            level.append(node.val)
            for child in (node.left, node.right):
                if child:
                    queue.append(child)
        result.append(level)
    return result

def path_sum(node, target, path=None) -> list[list[int]]:
    path = (path or []) + [node.val]
    if not node.left and not node.right:
        return [path] if sum(path) == target else []
    paths = []
    if node.left:
        paths += path_sum(node.left, target, path)
    if node.right:
        paths += path_sum(node.right, target, path)
    return paths
```

For graphs (vs. trees), track a `visited` set to avoid infinite loops on cycles.

---

**Pattern 8 - Subsets/Permutations via Backtracking**

Recursively build a partial solution, recurse on the remaining choices, then undo the choice ("backtrack") before trying the next one.

```python
def subsets(nums: list[int]) -> list[list[int]]:
    result: list[list[int]] = []

    def backtrack(start: int, path: list[int]) -> None:
        result.append(path[:])
        for i in range(start, len(nums)):
            path.append(nums[i])
            backtrack(i + 1, path)
            path.pop()  # undo - critical for correctness

    backtrack(0, [])
    return result
```

The `path.pop()` after the recursive call is what makes this backtracking rather than a one-shot recursive descent - without it, every branch shares a mutated `path`.

---

**Pattern 9 - 0/1 Knapsack DP Family**

A class of DP problems where each item is either included or excluded, and the state is "best result using the first i items with capacity/target j". Subset-sum, partition, and longest-common-subsequence are all variations.

```python
def can_partition(nums: list[int]) -> bool:
    total = sum(nums)
    if total % 2:
        return False
    target = total // 2
    dp = [False] * (target + 1)
    dp[0] = True
    for num in nums:
        for s in range(target, num - 1, -1):  # iterate downward - 0/1, not unbounded
            dp[s] = dp[s] or dp[s - num]
    return dp[target]

def longest_common_subsequence(a: str, b: str) -> int:
    dp = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
    for i in range(1, len(a) + 1):
        for j in range(1, len(b) + 1):
            if a[i - 1] == b[j - 1]:
                dp[i][j] = dp[i - 1][j - 1] + 1
            else:
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
    return dp[-1][-1]
```

Iterating the capacity dimension **downward** in `can_partition` is what enforces "each item used at most once" (0/1 knapsack); iterating upward would allow reuse (unbounded knapsack, like coin change with unlimited coins).

---

**Pattern 10 - Topological Sort / Union-Find**

For "dependency ordering" problems (course prerequisites, build order), use Kahn's algorithm (BFS with in-degrees). For "are these two things connected / merge these groups" problems, use union-find.

```python
from collections import deque, defaultdict

def topo_order(num_nodes: int, edges: list[tuple[int, int]]) -> list[int]:
    graph = defaultdict(list)
    indegree = [0] * num_nodes
    for src, dst in edges:
        graph[src].append(dst)
        indegree[dst] += 1

    queue = deque(n for n in range(num_nodes) if indegree[n] == 0)
    order: list[int] = []
    while queue:
        node = queue.popleft()
        order.append(node)
        for nxt in graph[node]:
            indegree[nxt] -= 1
            if indegree[nxt] == 0:
                queue.append(nxt)
    return order if len(order) == num_nodes else []  # shorter result => cycle


class UnionFind:
    def __init__(self, n: int) -> None:
        self.parent = list(range(n))

    def find(self, x: int) -> int:
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]  # path compression
            x = self.parent[x]
        return x

    def union(self, a: int, b: int) -> bool:
        ra, rb = self.find(a), self.find(b)
        if ra == rb:
            return False  # already connected
        self.parent[ra] = rb
        return True
```

`len(order) < num_nodes` after Kahn's algorithm is the standard way to detect a cycle (e.g. a circular course prerequisite) without a separate DFS-based cycle check.

---

## How It Connects

The two-pointers and sliding-window patterns are specific applications of the general two-pointers technique - understanding the loop invariant (what must be true about the window at every iteration) is the prerequisite for both.

[[two-pointers|Two Pointers Technique]]
[[sliding-window|Sliding Window Technique]]

The 0/1 knapsack pattern is one entry point into dynamic programming generally - recognizing the "include or exclude item i" state transition is the gateway to recognizing DP problems that don't look like knapsack on the surface.

[[dynamic-programming|Dynamic Programming]]

BFS and DFS are the two traversal primitives that patterns 3, 7, and 10 all build on - level-order BFS, path-based DFS, and Kahn's algorithm (BFS variant) all reuse the same queue/recursion templates.

[[bfs|Breadth-First Search]]
[[dfs|Depth-First Search]]

Backtracking (pattern 8) and topological sort / union-find (pattern 10) both depend on graph or tree representations and traversal order - [[backtracking|Backtracking]] and [[topological-sort|Topological Sort]] cover the underlying mechanics in depth.

[[disjoint-sets|Disjoint Sets]]

---

## Common Misconceptions

Misconception 1: "Memorizing more problems makes you better prepared."
Reality: Interviewers deliberately pick problems that are *variations* of well-known problems specifically to test whether a candidate recognizes the underlying pattern or has only memorized a specific solution. A candidate who memorized "Two Sum" but doesn't recognize that "Two Sum II (sorted input)" calls for two pointers instead of a hash map will struggle. Pattern recognition transfers; memorized solutions don't.

Misconception 2: "Two pointers and sliding window only work on arrays."
Reality: Two pointers applies to linked lists (fast/slow for cycle detection), strings (palindrome checks), and even two separate arrays simultaneously (merging sorted arrays). Sliding window applies to strings just as often as arrays. The pattern is about the *relationship between two indices/pointers*, not the data type.

Misconception 3: "DP problems require a 2D table."
Reality: Many DP problems start with an O(n*m) 2D table for clarity, but once the recurrence is correct, most reduce to O(n) (one rolling array) or even O(1) (a few scalar variables) because the recurrence only depends on the previous row or previous few values. Mentioning this optimization - even without fully implementing it - signals deeper understanding.

---

## Why It Matters in Practice

These patterns aren't just interview trivia - they show up directly in production code. Sliding window underlies rate limiters and "requests per time window" logic. Topological sort is how build systems (Make, Bazel) and package managers (pip's dependency resolver) determine valid execution order. Union-find powers connected-component analysis in clustering, network connectivity checks, and Kruskal's minimum spanning tree algorithm. A developer who recognizes "this is a top-K problem" reaches for `heapq.nlargest` instead of sorting an entire multi-million-row dataset to take the top 10 - the difference between O(n log k) and O(n log n) at scale.

Beyond the interview, the discipline of "name the pattern before writing code" also improves code review: a reviewer who sees a nested loop over pairs can ask "could this be two pointers if the input were sorted?" and suggest a concrete, well-understood optimization rather than a vague "this could be faster".

---

## Common Pitfalls

- Diving into code immediately instead of stating the approach, its time/space complexity, and confirming it with the interviewer first - even a correct solution written too hastily reads as a weaker signal than a well-communicated one.
- Off-by-one errors in window/pointer bounds: `right - left` vs. `right - left + 1` for window size, `<` vs. `<=` in the two-pointer loop condition.
- Forgetting edge cases: empty input, single-element input, all-duplicate input, and (for trees/graphs) a `None`/empty root.
- Mutating a list while iterating over it by index (e.g., removing elements during a `for i in range(len(nums))` loop), which silently skips or repeats elements.
- In backtracking, forgetting to undo a mutation (`path.pop()`, unmark a visited cell) before returning from a branch - this corrupts the state seen by sibling branches.
- Reaching for a heap or sort when a single pass with a hash map would do (and vice versa) - know the complexity of your chosen approach, not just that it "works".

---

## Interview Angle

Common question forms:
- "Can you optimize this O(n^2) brute-force solution?"
- "Which approach would you use here, and why?"
- "What's the time and space complexity of your solution?"
- "Can you do this in O(1) extra space?"

Answer frame: State which of the ~10 patterns the problem maps to before writing any code ("this looks like a sliding window problem because we need a contiguous subarray satisfying a constraint"). Give the time/space complexity of the naive approach and the pattern-based approach. Walk through one example by hand before coding. While coding, narrate edge cases (empty input, single element) and how the template handles them. After coding, state the final complexity and mention any further optimization (e.g., DP space reduction) even if you don't implement it.

**Sample Q&A:**

Q: "Given an array of integers, find if there exist two numbers whose sum equals a target value. What's your approach, and does it change if the array isn't sorted?"
A: If the array is sorted (or can be cheaply sorted and the question only needs the *values*, not original indices), two pointers from both ends gives O(n) after an O(n log n) sort, with O(1) extra space. If the array is unsorted and the question needs the original *indices* (the classic "Two Sum"), sorting destroys index information, so a hash map from value to index gives O(n) time and O(n) space in a single pass: for each number, check if `target - number` is already in the map before inserting the current number. The choice hinges on whether indices matter and whether O(n) extra space is acceptable.

Q: "How would you find the length of the longest substring without repeating characters?"
A: Sliding window with a hash map (or set) tracking the last-seen index of each character. Expand the right edge one character at a time; if the character is already in the window, move the left edge past its previous occurrence. Track the maximum window size seen. This is O(n) time because each character is visited a bounded number of times, and O(min(n, alphabet size)) space for the map.

Q: "You're processing a stream of numbers and need the Kth largest value at any point in time. What's your approach and why not just sort?"
A: Maintain a min-heap of size K. For each incoming number, push it onto the heap; if the heap size exceeds K, pop the smallest. The root of the heap is always the Kth largest seen so far. Each insertion is O(log K), so processing n numbers is O(n log K) - far better than re-sorting the entire stream (O(n log n)) every time a query comes in, especially when K is small relative to n. A min-heap (not max-heap) is used because we want to efficiently discard the *smallest* element once the heap exceeds size K.

---

## Practice Prompts

Each maps to a pattern above - work through them with a timer and narrate your pattern recognition out loud before coding:

- Two Sum: https://leetcode.com/problems/two-sum/
- Container With Most Water (two pointers): https://leetcode.com/problems/container-with-most-water/
- Longest Substring Without Repeating Characters (sliding window): https://leetcode.com/problems/longest-substring-without-repeating-characters/
- Linked List Cycle (fast/slow pointers): https://leetcode.com/problems/linked-list-cycle/
- Merge Intervals: https://leetcode.com/problems/merge-intervals/
- Kth Largest Element in an Array (heap): https://leetcode.com/problems/kth-largest-element-in-an-array/
- Koko Eating Bananas (binary search on answer): https://leetcode.com/problems/koko-eating-bananas/
- Binary Tree Level Order Traversal (BFS): https://leetcode.com/problems/binary-tree-level-order-traversal/
- Subsets (backtracking): https://leetcode.com/problems/subsets/
- Partition Equal Subset Sum (0/1 knapsack): https://leetcode.com/problems/partition-equal-subset-sum/
- Course Schedule (topological sort): https://leetcode.com/problems/course-schedule/
- Number of Provinces (union-find): https://leetcode.com/problems/number-of-provinces/

---

## Related Notes

- [[two-pointers|Two Pointers Technique]]
- [[sliding-window|Sliding Window Technique]]
- [[linked-lists|Linked Lists]]
- [[heaps|Heaps]]
- [[binary-search-variations|Binary Search Variations]]
- [[bfs|Breadth-First Search]]
- [[dfs|Depth-First Search]]
- [[backtracking|Backtracking]]
- [[dynamic-programming|Dynamic Programming]]
- [[topological-sort|Topological Sort]]
- [[disjoint-sets|Disjoint Sets]]
- [[big-o-notation|Big-O Notation]]
