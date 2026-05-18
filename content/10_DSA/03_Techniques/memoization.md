---
title: 36 - Memoization
description: The top-down dynamic programming technique that caches the result of each recursive call so the same subproblem is never computed more than once.
tags: [dsa, layer-10, memoization, dynamic-programming, caching]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Memoization

> Memoization turns a recursive solution with exponential branching into a linear or polynomial one by remembering every answer you have already calculated — any developer working on recursive algorithms must understand it as the simplest path from a correct but slow solution to a correct and fast one.

---

## Quick Reference

**Core idea:**
- Cache the return value of each unique call; on repeated calls, return the cached value immediately
- Python's `functools.lru_cache` and `functools.cache` add memoization to any function with a single decorator
- Transforms the call tree from an exponential branching structure into a DAG where each node is visited once
- Space tradeoff: O(number of distinct states) memory for the cache
- "Top-down" because you start at the original problem and recurse down, caching as you go
- Only computes subproblems that are actually reachable from the top (lazy evaluation)

**Tricky points:**
- Function arguments must be hashable to serve as cache keys — lists and dicts cannot be used directly
- `lru_cache` stores strong references to all cached results; in a long-running process, cache growth can become a memory issue
- `lru_cache(maxsize=None)` is equivalent to the newer `functools.cache` (Python 3.9+)
- Clearing the cache: `func.cache_clear()` resets it; useful in tests or when inputs change
- Memoization only helps when the same arguments recur — if every call has unique arguments, caching wastes space with no time benefit

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Fibonacci (naive) | O(2ⁿ) | O(n) stack |
| Fibonacci (memoized) | O(n) | O(n) cache + O(n) stack |
| Coin change (memoized) | O(n × amount) | O(amount) cache |
| General DP with k states | O(k × work per state) | O(k) cache |

---

## What It Is

Imagine you are a student working through a long proof that requires several intermediate lemmas. Each time you need a lemma, you could re-derive it from first principles — but any mathematician would tell you that is absurd: write the lemma down once, clearly labelled, and simply reference it whenever it is needed later. The proof takes the same logical structure whether you re-derive lemmas or look them up, but the work involved is vastly different. Memoization is that notepad of labelled lemmas applied to recursive computation.

The insight is that a pure function (same inputs always produce the same output, no side effects) is exactly like a mathematical lemma: its result depends entirely on its arguments, so there is never a reason to compute the same call twice. When you memoize a function, you attach an invisible lookup table to it. The first time it is called with argument n, it computes the result, stores it under the key n, and returns it. Every subsequent call with the same n skips the computation entirely and returns the stored value. The function behaves identically from the outside; only the internal execution path changes.

The structural transformation is dramatic. A naive recursive Fibonacci function builds a call tree that branches at every node: to compute F(n) you need F(n-1) and F(n-2), each of which branches again, producing exponential growth. With memoization, the tree becomes a directed acyclic graph: F(38) may appear in thousands of branches of the original tree, but in the memoized version it is computed once and every branch that would have computed it instead reads the cached value. The depth of the recursion is still O(n), but the total number of unique computations is also O(n), not O(2ⁿ).

---

## How It Actually Works

At the implementation level, memoization is a cache keyed by the function's argument tuple. In Python, `functools.lru_cache` wraps a function and maintains an internal dictionary mapping argument tuples to return values. The decorator pattern means you can add memoization to any pure recursive function without modifying its logic — the cache management is entirely outside the function body.

A manual dict-based cache gives you more control: you can inspect the cache, clear specific entries, or pass the cache as a parameter to share it across multiple functions. The `lru_cache` approach is cleaner for single functions. When you need a shared cache across a class hierarchy or between two mutually recursive functions, a manual `dict` passed as a parameter or stored as an instance variable is the right tool.

```python
from functools import lru_cache, cache
from typing import List


# --- Decorator approach: one line to memoize ---
@cache  # equivalent to @lru_cache(maxsize=None), Python 3.9+
def fib(n: int) -> int:
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

print(fib(100))   # 354224848179261915075 — instant
print(fib.cache_info())  # CacheInfo(hits=98, misses=101, ...)


# --- Manual dict cache: more control ---
def coin_change_memo(coins: List[int], amount: int) -> int:
    memo: dict[int, int] = {}

    def dp(remaining: int) -> int:
        if remaining == 0:
            return 0
        if remaining < 0:
            return float('inf')
        if remaining in memo:
            return memo[remaining]   # cache hit — skip computation

        best = float('inf')
        for coin in coins:
            result = dp(remaining - coin)
            if result + 1 < best:
                best = result + 1

        memo[remaining] = best       # store before returning
        return best

    answer = dp(amount)
    return answer if answer != float('inf') else -1


# --- Converting a naive recursive function to memoized ---
# Before: exponential
def lcs_naive(s1: str, s2: str, i: int, j: int) -> int:
    if i == 0 or j == 0:
        return 0
    if s1[i - 1] == s2[j - 1]:
        return 1 + lcs_naive(s1, s2, i - 1, j - 1)
    return max(lcs_naive(s1, s2, i - 1, j), lcs_naive(s1, s2, i, j - 1))

# After: memoized — identical logic, cache added
@lru_cache(maxsize=None)
def lcs_memo(s1: str, s2: str, i: int, j: int) -> int:
    if i == 0 or j == 0:
        return 0
    if s1[i - 1] == s2[j - 1]:
        return 1 + lcs_memo(s1, s2, i - 1, j - 1)
    return max(lcs_memo(s1, s2, i - 1, j), lcs_memo(s1, s2, i, j - 1))

print(lcs_memo("AGGTAB", "GXTXAYB", 6, 7))  # 4


# --- Cache clearing ---
fib.cache_clear()   # resets all cached values
```

---

## How It Connects

Memoization is the top-down implementation of dynamic programming. It preserves the natural recursive structure of the solution — the code looks almost identical to a brute-force recursive solution — while achieving the same asymptotic complexity as bottom-up tabulation. For problems where only a subset of subproblems are actually needed, memoization can be faster than tabulation in practice, because tabulation always fills the entire table.

The `functools` module is the Python-native home for memoization. `lru_cache` is the workhorse; `cache` is the simplified version for unbounded caches. Understanding how these decorators work — wrapping a function to intercept calls and check a dictionary before executing the body — is also a good exercise in Python's decorator and closure mechanics.

[[dynamic-programming|Dynamic Programming]]
[[tabulation|Tabulation]]
[[functools|functools]]
[[recursion|Recursion]]

---

## Common Misconceptions

Misconception 1: Memoization and caching are the same concept.
Reality: Memoization is a specific form of caching applied to pure functions in recursive algorithms. General caching can involve eviction policies, distributed stores, TTLs, and impure data sources. Memoization assumes the function is pure — same arguments always yield the same result — so cached values are always valid and never need expiry logic.

Misconception 2: Adding `@lru_cache` always makes a function faster.
Reality: `lru_cache` adds a dictionary lookup on every call, even on the first call. If the function is called with many unique arguments and never with repeated ones (such as generating random numbers), the cache never hits and the overhead from hashing arguments and inserting into the dictionary makes the function slightly slower. Memoization is only beneficial when repeated calls with identical arguments actually occur.

---

## Why It Matters in Practice

Memoization is one of the fastest routes from a correct but unusably slow recursive solution to a correct and fast one. In a competitive programming or interview setting, you can often derive the recursive structure of a DP solution intuitively, verify it on small examples, then apply `@lru_cache` to make it efficient. This workflow — write the recursion, memoize it, convert to tabulation if needed — is a reliable problem-solving pattern.

In production Python, `functools.lru_cache` is used beyond DP: any function that is computationally expensive and called repeatedly with the same arguments benefits from it. Database query result caching, file system metadata lookups, and compiled regular expression caching are all examples where the memoization idea (cache by argument) appears in real applications.

---

## Interview Angle

Common question forms:
- "Implement Fibonacci / coin change / word break using recursion." (Expected follow-up: add memoization.)
- "Why is your recursive solution slow? How would you improve it?"
- "Convert your top-down solution to bottom-up."

Answer frame:
Start with the naive recursion to show understanding of the structure. Identify that subproblems overlap. Add `@lru_cache` or a manual memo dict. State that the call tree transforms from exponential branching to a DAG with O(states) unique nodes. Note the space cost of the cache and mention that tabulation eliminates the stack overhead if recursion depth is a concern.

---

## Related Notes

- [[dynamic-programming|Dynamic Programming]]
- [[tabulation|Tabulation]]
- [[recursion|Recursion]]
- [[functools|functools]]
- [[divide-and-conquer|Divide and Conquer]]
