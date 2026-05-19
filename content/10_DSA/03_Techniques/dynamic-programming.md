---
title: 35 - Dynamic Programming
description: A technique for solving problems with overlapping subproblems and optimal substructure by storing intermediate results to avoid recomputation.
tags: [dsa, layer-10, dynamic-programming, memoization, tabulation]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Dynamic Programming

> Dynamic programming converts exponential brute-force into polynomial time by storing the answer to each subproblem exactly once — every developer targeting algorithmic roles must master it because it underlies the hardest class of interview problems.

---

## Quick Reference

**Core idea:**
- Two necessary conditions: optimal substructure and overlapping subproblems
- Two implementation styles: top-down (memoization) and bottom-up (tabulation)
- The state is the minimum information needed to characterise a subproblem uniquely
- Recurrence relation expresses how a larger state is built from smaller states
- Time complexity is (number of distinct states) × (work per state)
- Classic problems: Fibonacci, coin change, longest common subsequence, knapsack, edit distance

**Tricky points:**
- Identifying the state is the hard part — the recurrence is usually derivable once states are clear
- Not every optimisation problem is DP; the greedy choice property means greedy is sufficient
- Optimal substructure means the global optimum can be assembled from optimal sub-solutions — this must be proved, not assumed
- Overlapping subproblems is what separates DP from divide and conquer (which also has optimal substructure)
- Space optimisation (rolling array) is often possible when only the previous row of the DP table is needed

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Fibonacci (naive recursion) | O(2ⁿ) | O(n) stack |
| Fibonacci (DP) | O(n) | O(n) or O(1) |
| Coin change | O(n × amount) | O(amount) |
| Longest common subsequence | O(m × n) | O(m × n) or O(n) |

---

## What It Is

Consider how you would manually compute the 40th Fibonacci number. You might recall that you need F(39) and F(38), and to get F(39) you need F(38) and F(37), and so on — and you immediately notice that F(38) appears in both branches. A naive approach computes it twice, and F(37) appears four times, and F(36) eight times. By the time you reach the base cases you have performed over a billion operations. Now suppose instead you write each answer on a notepad as you compute it. The next time F(38) is needed, you look it up rather than recalculating. Suddenly the entire chain requires only 40 lookups. That notepad is the essence of dynamic programming: it is not a new way to think about the problem, but a discipline of remembering answers you have already worked hard to find.

Dynamic programming applies when a problem has two properties. The first is optimal substructure: the optimal answer to the whole problem can be assembled from optimal answers to subproblems. For the shortest path problem, the optimal path from A to C through B consists of the optimal path from A to B and the optimal path from B to C. If either segment were suboptimal, you could replace it and get a better total path, contradicting the assumption that the whole path was optimal. This property is what makes local solutions globally composable.

The second property is overlapping subproblems: the same subproblems are encountered repeatedly during the computation. This is the defining difference from divide and conquer. Merge sort also has optimal substructure (a sorted array is built from two sorted halves), but the two halves never share elements — there is no overlap, so caching provides no benefit. In the Fibonacci sequence, every level of the recursion tree revisits the same values, so caching converts a tree of exponential size into a linear chain of 40 unique calculations.

The shift in thinking that makes DP hard to learn is the move away from "what should I choose at each step" (greedy thinking) toward "what are all possible states and how does the optimal answer for each state relate to the answers for smaller states." Defining the state precisely, writing the recurrence relation, handling base cases, and deciding on a traversal order (top-down vs bottom-up) are the four steps in any DP solution.

---

## How It Actually Works

The two implementation styles are top-down (recursion with memoization) and bottom-up (iterative tabulation). Top-down starts from the original problem and recurses downward, caching results as it goes. It only computes subproblems that are actually reached. Bottom-up starts from the base cases and fills a table in dependency order, guaranteeing that when a state is computed, all states it depends on are already in the table. Both produce identical answers; the choice between them is about code clarity, recursion depth concerns, and whether you need all subproblems or only a subset.

The coin change problem illustrates a 1D DP table. The state is `dp[amount]` = the minimum number of coins needed to make that amount. The recurrence is: for each coin denomination c, `dp[amount] = min(dp[amount], 1 + dp[amount - c])`. Base case: `dp[0] = 0`. Fill the table from amount = 1 up to the target.

```python
from functools import lru_cache
from typing import List


# --- Top-down: Fibonacci with memoization ---
@lru_cache(maxsize=None)
def fib(n: int) -> int:
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)


# --- Bottom-up: Fibonacci with tabulation ---
def fib_tab(n: int) -> int:
    if n <= 1:
        return n
    dp = [0] * (n + 1)
    dp[1] = 1
    for i in range(2, n + 1):
        dp[i] = dp[i - 1] + dp[i - 2]
    return dp[n]


# --- Coin Change: bottom-up tabulation ---
def coin_change(coins: List[int], amount: int) -> int:
    INF = float('inf')
    dp = [INF] * (amount + 1)
    dp[0] = 0  # base case: 0 coins to make amount 0

    for a in range(1, amount + 1):
        for c in coins:
            if c <= a and dp[a - c] + 1 < dp[a]:
                dp[a] = dp[a - c] + 1

    return dp[amount] if dp[amount] != INF else -1


# --- Longest Common Subsequence: 2D tabulation ---
def lcs(s1: str, s2: str) -> int:
    m, n = len(s1), len(s2)
    dp = [[0] * (n + 1) for _ in range(m + 1)]

    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if s1[i - 1] == s2[j - 1]:
                dp[i][j] = dp[i - 1][j - 1] + 1
            else:
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])

    return dp[m][n]


print(fib(50))                         # 12586269025
print(coin_change([1, 5, 10, 25], 41)) # 4 (25+10+5+1)
print(lcs("abcde", "ace"))             # 3
```

---

## Visualizer

<iframe src="/static/visualizers/dynamic-programming.html" style="width:100%;height:460px;border:none;border-radius:8px;" title="Dynamic Programming Visualizer"></iframe>

---

## How It Connects

Dynamic programming is the resolution of a tension between two earlier ideas: recursion (which naturally expresses the structure of overlapping subproblems) and the observation that recomputing the same values is wasteful. Memoization solves this by caching recursive calls; tabulation solves it by computing in dependency order without recursion at all. Both are implementations of the same DP idea, just approached from opposite directions.

Greedy algorithms share the optimal substructure requirement but skip the overlapping subproblems requirement — they commit to one choice at each step without reconsidering. Understanding when greedy works (coin change with standard denominations) and when it fails (coin change with non-standard denominations) requires understanding what DP protects against: the case where the locally best choice is not globally best.

[[memoization|Memoization]]
[[tabulation|Tabulation]]
[[greedy-algorithms|Greedy Algorithms]]
[[divide-and-conquer|Divide and Conquer]]
[[recursion|Recursion]]

---

## Common Misconceptions

Misconception 1: Dynamic programming means filling a 2D table.
Reality: Many DP problems use a 1D table (coin change, climbing stairs, house robber). The number of dimensions in the table equals the number of independent state variables needed to characterise a subproblem. The table shape is a consequence of the state definition, not a requirement of DP itself.

Misconception 2: If a problem involves optimisation, dynamic programming will solve it.
Reality: DP requires both optimal substructure and overlapping subproblems. Many optimisation problems have optimal substructure but no overlapping subproblems — they are solved by divide and conquer. Others have optimal substructure and can be solved greedily because the greedy choice is always part of the optimum. DP is the right tool when both conditions are present and greedy is not provably correct.

---

## Why It Matters in Practice

Dynamic programming is arguably the single most tested topic in algorithm interviews at major software companies. Problems that appear intractable at first glance — minimum edit distance between strings (used in spell checkers and DNA sequence alignment), optimal resource allocation, shortest paths with constraints — all reduce to DP once the state and recurrence are identified. The pattern recognition skill — spotting that a problem has optimal substructure and overlapping subproblems — is the core competency being tested.

Beyond interviews, DP algorithms appear in real systems: the Viterbi algorithm in speech recognition and hidden Markov models, the Smith-Waterman algorithm in bioinformatics, the CYK algorithm in natural language parsing, and the Unix `diff` utility's line-difference algorithm all rest on DP foundations. Learning DP trains you to see when a problem's complexity comes from redundant computation rather than from intrinsic difficulty.

---

## Interview Angle

Common question forms:
- "Find the minimum cost / maximum profit / longest length given a sequence or grid."
- "Count the number of ways to reach a target."
- "Is it possible to achieve a target with given constraints?"

Answer frame:
Define the state (what dp[i] or dp[i][j] represents). Write the recurrence relation. Identify the base cases. Decide top-down or bottom-up and implement. State the time and space complexity as (states × work per state). Mention possible space optimisation if only adjacent rows are needed.

---

## Related Notes

- [[memoization|Memoization]]
- [[tabulation|Tabulation]]
- [[greedy-algorithms|Greedy Algorithms]]
- [[divide-and-conquer|Divide and Conquer]]
- [[recursion|Recursion]]
- [[functools|functools]]
