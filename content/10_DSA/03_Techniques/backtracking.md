---
title: 41 - Backtracking
description: An exhaustive search with pruning that builds solutions incrementally and abandons partial solutions as soon as they cannot lead to a valid complete solution.
tags: [dsa, layer-10, backtracking, recursion]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Backtracking

> Backtracking explores all possible configurations by building solutions incrementally and pruning dead ends early - every developer targeting algorithmic roles must master it because it is the standard approach for constraint satisfaction, permutation/combination enumeration, and puzzle solving.

---

## Quick Reference

**Core idea:**
- Template: choose → recurse → unchoose (the undo step restores state for the next branch)
- Prunes branches as soon as a partial solution violates a constraint - unlike brute force, which generates all possibilities then filters
- Applies to: all permutations/combinations/subsets, N-Queens, Sudoku, word search in a grid, graph coloring
- The solution space is a decision tree; backtracking is DFS on that tree with early termination
- State modification must be reversible - the unchoose step must perfectly undo what choose did
- Time complexity is hard to state generally; depends on branching factor and pruning effectiveness

**Tricky points:**
- Forgetting the unchoose step corrupts state across branches - the most common backtracking bug
- When building a list of results, append a copy (`result.append(current[:])`) not a reference to the mutable list
- The order of the base case and the constraint check matters - check constraints before recursing, not after
- For subsets/combinations, passing a `start` index prevents duplicate sets (avoids including the same element twice)
- Python's `path.pop()` is the canonical undo step for list-based state; `board[r][c] = '.'` for grid-based state

---

## Complexity

| Case | Time | Space |
|---|---|---|
| All permutations of n elements | O(n × n!) | O(n) stack depth |
| All subsets of n elements | O(2ⁿ) | O(n) stack depth |
| N-Queens | O(n!) | O(n) |
| Sudoku solver | O(9^81) worst case, vastly better with pruning | O(81) = O(1) |

---

## What It Is

Think of backtracking as navigating a maze with a pencil and eraser. You draw your path forward, committing to each corridor as you take it. The moment you reach a dead end - a wall, a locked door, or a constraint you cannot satisfy - you reach back to your most recent decision point, erase the path from there to the dead end, and try a different corridor. You continue this process until you either find the exit or exhaust every possible path. The eraser is the defining feature: without it, you could only follow one path and declare failure if it did not work. With it, you can systematically explore every option.

The decision tree is the formal structure behind this intuition. Each node in the tree represents a partial solution (the choices made so far), and each edge represents one more choice. The leaves represent either complete valid solutions or dead ends where no further extension is possible. Backtracking performs depth-first search on this tree: go as deep as possible along one branch, recognise a dead end, backtrack to the parent, try the next sibling branch. The pruning step - recognising a dead end before reaching the bottom - is what separates backtracking from brute force, which descends all the way to the leaves before checking validity.

The N-Queens problem makes the structure concrete. You are placing n queens on an n×n chessboard such that no two queens attack each other. A brute-force approach would generate all possible ways to place n queens (n^n possibilities), then filter for valid configurations. Backtracking places one queen per row, checking immediately after each placement whether it conflicts with previously placed queens. If a conflict is detected on row 4, the algorithm backtracks to row 4's placement, tries the next column, and never generates the millions of configurations that would follow from the conflicting position. On most boards, backtracking prunes the search space by several orders of magnitude relative to brute force.

---

## How It Actually Works

The template for any backtracking problem is always three steps inside a recursive function: choose (make a decision and update state), recurse (call the function with the updated state), unchoose (undo the update exactly). The base case at the top of the function either records a complete solution or returns immediately if the current state is already invalid (the pruning condition). The recursive call iterates over all available choices, applying the template to each.

The undo step is the part most likely to introduce bugs. For a list-based path (building permutations, combinations), the undo is `path.pop()`. For a grid (word search, Sudoku), the undo restores the cell to its original value. For a boolean visited array, the undo is `visited[i] = False`. The undo must be in the same scope as the choose - use a try/finally pattern if there is any risk of the recursive call raising an exception that bypasses the undo.

```python
from typing import List


# --- All Permutations ---
def permutations(nums: List[int]) -> List[List[int]]:
    result = []

    def backtrack(path: List[int], used: List[bool]) -> None:
        if len(path) == len(nums):
            result.append(path[:])  # copy, not reference
            return
        for i in range(len(nums)):
            if used[i]:
                continue
            # Choose
            path.append(nums[i])
            used[i] = True
            # Recurse
            backtrack(path, used)
            # Unchoose
            path.pop()
            used[i] = False

    backtrack([], [False] * len(nums))
    return result


# --- All Subsets (power set) ---
def subsets(nums: List[int]) -> List[List[int]]:
    result = []

    def backtrack(start: int, current: List[int]) -> None:
        result.append(current[:])  # every partial state is a valid subset
        for i in range(start, len(nums)):
            current.append(nums[i])           # choose
            backtrack(i + 1, current)          # recurse (start=i+1 avoids reuse)
            current.pop()                      # unchoose

    backtrack(0, [])
    return result


# --- N-Queens ---
def n_queens(n: int) -> List[List[str]]:
    result = []
    cols = set()
    diag1 = set()   # row - col
    diag2 = set()   # row + col

    board = [['.' ] * n for _ in range(n)]

    def backtrack(row: int) -> None:
        if row == n:
            result.append([''.join(r) for r in board])
            return
        for col in range(n):
            if col in cols or (row - col) in diag1 or (row + col) in diag2:
                continue  # pruning: invalid placement
            # Choose
            board[row][col] = 'Q'
            cols.add(col)
            diag1.add(row - col)
            diag2.add(row + col)
            # Recurse
            backtrack(row + 1)
            # Unchoose
            board[row][col] = '.'
            cols.remove(col)
            diag1.remove(row - col)
            diag2.remove(row + col)

    backtrack(0)
    return result


# --- Word Search in Grid ---
def word_search(board: List[List[str]], word: str) -> bool:
    rows, cols = len(board), len(board[0])

    def backtrack(r: int, c: int, idx: int) -> bool:
        if idx == len(word):
            return True
        if r < 0 or r >= rows or c < 0 or c >= cols:
            return False
        if board[r][c] != word[idx]:
            return False
        # Choose: mark as visited
        temp = board[r][c]
        board[r][c] = '#'
        # Recurse in all four directions
        found = (backtrack(r + 1, c, idx + 1) or
                 backtrack(r - 1, c, idx + 1) or
                 backtrack(r, c + 1, idx + 1) or
                 backtrack(r, c - 1, idx + 1))
        # Unchoose: restore cell
        board[r][c] = temp
        return found

    for r in range(rows):
        for c in range(cols):
            if backtrack(r, c, 0):
                return True
    return False


print(len(permutations([1, 2, 3])))   # 6
print(len(subsets([1, 2, 3])))        # 8
print(len(n_queens(8)))               # 92
```

---

## How It Connects

Backtracking is depth-first search applied to the implicit decision tree of a problem. Where DFS traverses an explicit graph, backtracking traverses a virtual graph where nodes are partial solutions and edges are choices. The visited-set tracking in DFS corresponds to the used array in permutation backtracking; the graph adjacency list corresponds to the set of available choices at each step.

Recursion is the mechanism: the call stack manages the "memory" of which choices have been made so far. When the function returns (backtracks), the call stack frame is popped and the previous state is restored - but only if the undo step has properly reversed the state mutations made in the current frame. This is why the choose-recurse-unchoose structure must be strictly followed.

[[recursion|Recursion]]
[[dfs|Depth-First Search]]
[[dynamic-programming|Dynamic Programming]]
[[graphs|Graphs]]

---

## Common Misconceptions

Misconception 1: Backtracking and dynamic programming both explore all possibilities, so they are interchangeable.
Reality: Backtracking explores an exponential number of configurations but prunes invalid branches early. It does not store intermediate results and never reuses sub-computations. Dynamic programming avoids recomputing overlapping subproblems by caching results. They solve different problem types: backtracking is for constraint satisfaction and enumeration of all valid configurations; DP is for optimisation over overlapping subproblems.

Misconception 2: If the backtracking solution is too slow, the problem cannot be solved efficiently.
Reality: Backtracking is often the correct approach, and its actual running time on real inputs is much better than the worst-case theoretical bound because pruning eliminates most of the tree. For problems where a polynomial solution exists (like dynamic programming), backtracking is the wrong approach. For problems that are genuinely NP-complete (Sudoku, graph colouring, SAT), backtracking with strong pruning is often the best practical approach, and theoretical exponential worst-case complexity reflects the nature of the problem, not a deficiency of the algorithm.

---

## Why It Matters in Practice

Backtracking underpins constraint satisfaction solvers used in scheduling, configuration management, and automated theorem proving. Sudoku solvers, crossword puzzle generators, and automated test case generators all use variants of backtracking. In compilers and query planners, backtracking-style search is used to find valid execution orderings or plan transformations. Understanding backtracking makes you fluent in the class of problems where you must find configurations satisfying multiple simultaneous constraints.

For interviews, backtracking problems are among the most common at senior-level positions because they test the ability to decompose a search space, identify pruning conditions, and manage state correctly across recursive calls. The choose-recurse-unchoose template gives you a systematic approach to any such problem - the question becomes how to define the state and what the pruning conditions are, not how to structure the code.

---

## Interview Angle

Common question forms:
- "Generate all permutations / combinations / subsets."
- "Solve this Sudoku / N-Queens problem."
- "Find all paths in this grid that spell a given word."

Answer frame:
State the decision tree: what are the choices at each level, and what constitutes a complete solution. Name the base case (complete solution found or invalid state detected). Name the pruning conditions. Implement choose-recurse-unchoose. Discuss time complexity in terms of branching factor and tree depth. Mention the copy-on-append issue for collecting results.

---

## Related Notes

- [[recursion|Recursion]]
- [[dfs|Depth-First Search]]
- [[dynamic-programming|Dynamic Programming]]
- [[graphs|Graphs]]
- [[binary-trees|Binary Trees]]
