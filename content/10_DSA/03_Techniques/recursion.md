---
title: 33 - Recursion
description: A function that calls itself with a smaller input until it reaches a base case, enabling elegant solutions to problems with self-similar structure.
tags: [dsa, layer-10, recursion, call-stack]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Recursion

> Recursion is a function that calls itself with progressively smaller inputs until it reaches a base case — every developer must understand it because it is the foundation for tree traversal, divide-and-conquer, backtracking, and dynamic programming.

---

## Quick Reference

**Core idea:**
- A recursive function has two parts: a base case (stop condition) and a recursive case (self-call with reduced input)
- Each call creates a new frame on the call stack with its own local variables
- Python's default recursion limit is 1000 (`sys.getrecursionlimit()`)
- The three questions: what is the base case? what does one step do? what does the function return?
- Python does not optimise tail recursion — deep recursion risks a `RecursionError`
- `sys.setrecursionlimit(n)` raises the limit, but the real fix is usually an iterative approach

**Tricky points:**
- Forgetting the base case causes infinite recursion and a stack overflow
- The return value must be passed back explicitly — forgetting `return` in the recursive case silently returns `None`
- Each call gets its own copy of local variables; shared state requires explicit passing or a mutable container
- Python's overhead per call (frame creation) makes recursion noticeably slower than loops for performance-critical code
- Mutual recursion (f calls g, g calls f) is valid but doubles the depth pressure

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Linear recursion (factorial) | O(n) | O(n) stack frames |
| Binary recursion (naive Fibonacci) | O(2ⁿ) | O(n) stack depth |
| Binary search (recursive) | O(log n) | O(log n) stack frames |

---

## What It Is

Think of recursion like a set of Russian nesting dolls. When you open the outermost doll you find a smaller but identical doll inside, and inside that another, and so on — until you reach the smallest doll that contains nothing. That innermost doll is the base case. You didn't need a different technique to open each doll; you used exactly the same action at every level. Recursion works the same way: the function does not need to know how deep the nesting goes — it only needs to know how to handle one level and when to stop.

A cleaner mental model is to think in terms of trust. When writing a recursive function, you trust that the recursive call will correctly solve the smaller version of the problem. Your only job is to handle the current step and hand off everything else. This is called the recursive leap of faith and it is what makes recursive solutions readable: `factorial(n)` is defined as `n * factorial(n - 1)` because you trust that `factorial(n - 1)` will return the correct value. You do not need to trace through the entire call chain to convince yourself the function is correct.

Every time a function calls itself, Python adds a new frame to the call stack. That frame stores the local variables, parameters, and the return address for that particular call. When the base case is reached, the frames begin unwinding — each one returns its value to the frame that called it, collapsing the stack back down to the original caller. This unwinding is where the actual computation often happens; in factorial, all the multiplications occur on the way back up, not on the way down.

---

## How It Actually Works

The mechanics rest entirely on the call stack. When `factorial(5)` is called, Python creates a frame for it. That frame calls `factorial(4)`, creating another frame. This continues down to `factorial(0)`, which hits the base case and returns 1 without making another call. From that point, each frame receives the return value from the call it made, performs its multiplication, and returns upward. The entire chain of frames exists simultaneously on the stack — that is why deep recursion consumes memory proportional to the depth, not to the total number of operations.

Python enforces a hard limit on this stack depth (default 1000 frames) to prevent unbounded memory consumption from a missing base case. For problems with recursion depth much smaller than 1000 (tree traversals, divide-and-conquer on moderate inputs) this limit is not a practical concern. For problems where depth scales with n (linear recursion on large n), the iterative version is the correct choice in production Python code. The `sys.setrecursionlimit()` function adjusts the limit but does not eliminate the underlying stack growth; it only moves the failure point.

```python
import sys

# Standard recursive factorial
def factorial(n: int) -> int:
    # Base case: stop condition
    if n == 0:
        return 1
    # Recursive case: trust factorial(n-1) is correct
    return n * factorial(n - 1)


# Naive recursive Fibonacci — exponential time, avoid for large n
def fib_naive(n: int) -> int:
    if n <= 1:
        return n
    return fib_naive(n - 1) + fib_naive(n - 2)


# Recursive binary search — O(log n) depth
def binary_search(arr: list, target: int, lo: int, hi: int) -> int:
    if lo > hi:
        return -1
    mid = (lo + hi) // 2
    if arr[mid] == target:
        return mid
    elif arr[mid] < target:
        return binary_search(arr, target, mid + 1, hi)
    else:
        return binary_search(arr, target, lo, mid - 1)


# Check current and adjust recursion limit
print(sys.getrecursionlimit())   # 1000 by default
sys.setrecursionlimit(2000)      # use sparingly
```

---

## Visualizer

<iframe src="/static/visualizers/recursion.html" style="width:100%;height:440px;border:none;border-radius:8px;" title="Recursion Visualizer"></iframe>

---

## How It Connects

Recursion is not merely a technique — it is the mechanism underlying most of the important algorithms in this layer. Divide and conquer splits a problem and recurses on each half; dynamic programming memoises recursive calls to avoid redundant work; backtracking recurses through a decision tree and unwinds when a path fails. Understanding the call stack and the recursive trust model is a prerequisite for all of them.

The call stack itself is a concrete data structure — a last-in, first-out stack — and every recursive function is implicitly managing one. Iterative solutions to inherently recursive problems (tree traversal, depth-first search) work by making that stack explicit using a `collections.deque` or a list.

[[call-stack|Call Stack]]
[[divide-and-conquer|Divide and Conquer]]
[[dynamic-programming|Dynamic Programming]]
[[backtracking|Backtracking]]

---

## Common Misconceptions

Misconception 1: Recursion is always more elegant and should be preferred over loops.
Reality: Recursion is the right tool when the problem is naturally self-similar (trees, divide-and-conquer, combinatorics). For linear iteration over a flat sequence, a loop is faster, uses constant stack space, and is easier to read. Python specifically does not optimise tail calls, so a recursive loop alternative always carries frame-creation overhead.

Misconception 2: If a recursive function returns the right answer on small inputs, it will work on large inputs.
Reality: Correctness and scalability are separate concerns. A naive recursive Fibonacci is correct but collapses at n=40 due to exponential branching. A deeply recursive linear function is correct but raises `RecursionError` at depth 1001. Always reason about both the time complexity of the call tree and the maximum stack depth before using a recursive solution.

---

## Why It Matters in Practice

Recursion appears throughout real codebases wherever data has hierarchical or self-similar structure: parsing nested JSON, traversing file system trees, evaluating abstract syntax trees in compilers, implementing depth-first search on graphs. It is not an academic construct — it is the natural expression of algorithms that would require explicit stack management to express iteratively.

In interviews, recursion is the entry point to a large class of problems. Understanding the three questions (base case, step, return value) and the leap-of-faith model lets you design recursive solutions quickly. Knowing when to convert to iteration or add memoisation separates a correct solution from a production-ready one.

---

## Interview Angle

Common question forms:
- "Implement factorial / Fibonacci / binary search recursively."
- "Given a recursive function, convert it to an iterative one."
- "Why might this recursive solution cause a problem in Python?"

Answer frame:
State the base case first, then the recursive case. Mention Python's recursion limit when discussing depth. If the problem has overlapping subproblems, flag that memoisation or tabulation would improve time complexity. If asked about iterative conversion, explain the explicit stack approach.

---

## Related Notes

- [[call-stack|Call Stack]]
- [[divide-and-conquer|Divide and Conquer]]
- [[dynamic-programming|Dynamic Programming]]
- [[backtracking|Backtracking]]
- [[memoization|Memoization]]
- [[binary-search|Binary Search]]
