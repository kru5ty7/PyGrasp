---
title: 37 - Tabulation
description: The bottom-up dynamic programming approach that fills a table iteratively from base cases to the answer, eliminating recursion entirely.
tags: [dsa, layer-10, tabulation, dynamic-programming]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Tabulation

> Tabulation is the iterative, bottom-up form of dynamic programming — it fills a table from known base cases up to the target, avoiding recursion and stack overhead entirely — developers who master it can solve the hardest DP problems without hitting Python's recursion limit.

---

## Quick Reference

**Core idea:**
- Build a table (array or 2D grid) starting from base cases and fill in dependency order
- No recursion, no stack frames, no `RecursionError` risk
- Table dimensions equal the number of independent state variables
- Each cell is computed from previously filled cells — ordering must respect dependencies
- Space optimisation: if only the previous row or element is needed, reduce the table
- Preferred when all subproblems will be needed or when recursion depth is a concern

**Tricky points:**
- Getting the fill order wrong causes reads from uninitialised cells — always trace the dependency direction
- Off-by-one errors in table size are common: a table for amounts 0..n needs n+1 cells
- Space optimisation can make code harder to read; prefer clarity unless space is a hard constraint
- Tabulation always computes every subproblem; memoization only computes reachable ones — memoization can be faster for sparse problems
- 2D table initialisation with `[[0]*cols for _ in range(rows)]` — never use `[[0]*cols]*rows` (aliased rows)

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Fibonacci (tabulation) | O(n) | O(n) → O(1) with optimisation |
| Coin change | O(n × amount) | O(amount) |
| Edit distance (full table) | O(m × n) | O(m × n) → O(n) with optimisation |
| 0/1 Knapsack | O(n × W) | O(n × W) → O(W) with optimisation |

---

## What It Is

Think of tabulation as filling out a tax form by following the instruction booklet. The booklet says: "First complete Line 7. Then compute Line 12 using Line 7. Then compute Line 23 using Lines 12 and 15." Each line depends only on lines you have already completed. You never skip ahead or jump backward. By the time you reach the final line, every value you need has been computed and written down in a specific cell of the form. The tax form is the DP table, and the instruction order is the fill order that respects dependencies.

This is the opposite of how memoization works. Memoization starts from the question you want to answer and recurses downward until it reaches base cases, then unwinds. Tabulation starts from the base cases — the smallest, simplest sub-answers you already know — and builds upward until it reaches the answer you want. Neither approach re-computes anything; both are correct implementations of dynamic programming. The difference is direction and mechanism.

The practical advantage of tabulation in Python is the absence of recursion. Every recursive call in memoization creates a stack frame; for problems where the recursion depth is O(n), this means n frames on the call stack simultaneously. Python's default limit of 1000 frames caps this. Tabulation uses a simple loop — the Python interpreter handles it as a flat iteration with no stack growth. For large inputs, tabulation is the only safe option in standard Python. A secondary advantage is memory access pattern: iterating through a contiguous array in order is cache-friendly and can be meaningfully faster on modern hardware than the pointer-chasing involved in recursive calls.

---

## How It Actually Works

The implementation pattern for tabulation is always the same. Define what `dp[i]` (or `dp[i][j]`) represents — this is the state. Write the recurrence relation — the formula expressing how `dp[i]` is computed from previous entries. Identify the base cases and initialise those cells. Fill the table in the order that ensures all dependencies are ready. Return the cell corresponding to the original question.

For Fibonacci, the state is `dp[i]` = the ith Fibonacci number. The recurrence is `dp[i] = dp[i-1] + dp[i-2]`. Base cases: `dp[0] = 0`, `dp[1] = 1`. Fill order: left to right from index 2. Space optimisation: since each cell only needs the two previous values, two variables replace the entire array.

For edit distance (the number of single-character operations needed to transform one string into another), the state is `dp[i][j]` = the edit distance between the first i characters of s1 and the first j characters of s2. This is a canonical 2D tabulation problem. The space optimisation reduces the O(m×n) table to two rows (current and previous), because each cell only looks one row up and one column left.

```python
from typing import List


# --- Fibonacci: 1D tabulation ---
def fib(n: int) -> int:
    if n <= 1:
        return n
    dp = [0] * (n + 1)
    dp[1] = 1
    for i in range(2, n + 1):
        dp[i] = dp[i - 1] + dp[i - 2]
    return dp[n]

# Space-optimised Fibonacci: O(1) space
def fib_optimised(n: int) -> int:
    if n <= 1:
        return n
    prev2, prev1 = 0, 1
    for _ in range(2, n + 1):
        prev2, prev1 = prev1, prev1 + prev2
    return prev1


# --- Coin Change: 1D tabulation ---
def coin_change(coins: List[int], amount: int) -> int:
    INF = float('inf')
    dp = [INF] * (amount + 1)
    dp[0] = 0  # base case

    for a in range(1, amount + 1):
        for coin in coins:
            if coin <= a:
                dp[a] = min(dp[a], dp[a - coin] + 1)

    return dp[amount] if dp[amount] != INF else -1


# --- Edit Distance: 2D tabulation ---
def edit_distance(s1: str, s2: str) -> int:
    m, n = len(s1), len(s2)
    # dp[i][j] = edit distance between s1[:i] and s2[:j]
    dp = [[0] * (n + 1) for _ in range(m + 1)]

    # Base cases: transforming to/from empty string
    for i in range(m + 1):
        dp[i][0] = i  # delete all characters
    for j in range(n + 1):
        dp[0][j] = j  # insert all characters

    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if s1[i - 1] == s2[j - 1]:
                dp[i][j] = dp[i - 1][j - 1]   # characters match: free
            else:
                dp[i][j] = 1 + min(
                    dp[i - 1][j],    # delete from s1
                    dp[i][j - 1],    # insert into s1
                    dp[i - 1][j - 1] # replace
                )

    return dp[m][n]


# Space-optimised edit distance: O(n) space using two rows
def edit_distance_optimised(s1: str, s2: str) -> int:
    m, n = len(s1), len(s2)
    prev = list(range(n + 1))

    for i in range(1, m + 1):
        curr = [i] + [0] * n
        for j in range(1, n + 1):
            if s1[i - 1] == s2[j - 1]:
                curr[j] = prev[j - 1]
            else:
                curr[j] = 1 + min(prev[j], curr[j - 1], prev[j - 1])
        prev = curr

    return prev[n]


print(fib(50))                           # 12586269025
print(coin_change([1, 5, 10, 25], 41))   # 4
print(edit_distance("intention", "execution"))  # 5
```

---

## Visualizer

<iframe src="/static/visualizers/tabulation.html" style="width:100%;height:480px;border:none;border-radius:8px;" title="Tabulation Visualizer"></iframe>

---

## How It Connects

Tabulation and memoization are two implementations of the same dynamic programming idea. Choosing between them is a matter of practicality: memoization preserves the recursive structure and is easier to derive, while tabulation avoids recursion overhead and is more memory-friendly when space optimisation is applied. For problems where only a fraction of subproblems are reachable, memoization avoids computing unused cells; for problems where all cells are needed and inputs are large, tabulation is the safer choice in Python.

The space optimisation pattern — reducing a 2D table to two 1D arrays, or a 1D array to two scalar variables — appears in many interview solutions and is worth practising. It requires careful thought about which cells each new cell depends on, but the payoff in space complexity is often the difference between an acceptable and an optimal solution.

[[dynamic-programming|Dynamic Programming]]
[[memoization|Memoization]]
[[greedy-algorithms|Greedy Algorithms]]

---

## Common Misconceptions

Misconception 1: Tabulation is always faster than memoization.
Reality: Tabulation computes every cell in the table, even those that would never be reached from the original problem. Memoization with a lazy cache only computes reachable subproblems. For sparse DP problems where many states are unreachable, memoization can perform significantly fewer computations. Tabulation has lower per-operation overhead (no hash lookups, no function call overhead) but may do more total work.

Misconception 2: Space optimisation is always worth applying.
Reality: Rolling a 2D table down to a 1D array or two variables makes the code harder to read, debug, and extend. The original full table often makes the state transitions self-documenting. Apply space optimisation only when memory is actually a constraint or when the interviewer explicitly asks for an optimal-space solution. In all other cases, clarity should be the default.

---

## Why It Matters in Practice

Tabulation is the production-ready form of dynamic programming in Python. It does not risk hitting the recursion limit, its memory access patterns are cache-friendly, and space optimisation techniques can reduce its footprint dramatically. Interview problems that involve filling a grid, counting paths, or computing minimum costs over sequences are almost always best expressed as tabulation once the state and recurrence are identified.

The edit distance algorithm underpins Unix `diff`, spell checkers, and DNA sequence alignment tools. Knapsack variants model resource allocation and scheduling. Shortest path problems in graphs can be reformulated as DP. Understanding tabulation as a general pattern — define state, write recurrence, fill in order, return target cell — gives you a systematic attack on a large class of problems that would otherwise seem to require case-by-case insight.

---

## Interview Angle

Common question forms:
- "Implement edit distance / coin change / longest common subsequence."
- "Can you optimise the space complexity of your DP solution?"
- "What is the difference between your memoized solution and a bottom-up table?"

Answer frame:
Define what each cell of the table represents. Write the recurrence. Identify base cases and initialisation. Describe fill order (left-to-right, top-to-bottom, or a custom order). State time and space complexity. Mention the space optimisation if the table has a simple rolling dependency and the interviewer asks for improvement.

---

## Related Notes

- [[dynamic-programming|Dynamic Programming]]
- [[memoization|Memoization]]
- [[greedy-algorithms|Greedy Algorithms]]
- [[recursion|Recursion]]
- [[lists|Lists]]
