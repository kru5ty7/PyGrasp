---
title: 38 - Greedy Algorithms
description: A class of algorithms that make the locally optimal choice at each step, relying on the greedy choice property to guarantee a globally optimal solution.
tags: [dsa, layer-10, greedy, optimization]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Greedy Algorithms

> A greedy algorithm commits to the best-looking choice at each step without reconsidering — developers must know it because it produces provably optimal solutions for a specific class of problems and is the natural first candidate to evaluate before reaching for dynamic programming.

---

## Quick Reference

**Core idea:**
- Make the locally optimal choice at every step and never backtrack
- Correct when the greedy choice property holds: a locally optimal choice is always part of some globally optimal solution
- Also requires optimal substructure (same requirement as dynamic programming)
- Classic examples: activity selection (pick earliest-ending), Huffman encoding, Dijkstra's algorithm, minimum spanning tree
- Proving correctness requires an exchange argument: assume an optimal solution differs from greedy, show swapping produces an equal or better solution
- When greedy fails: coin change with non-standard denominations (US coins work; denominations like {1, 3, 4} do not)

**Tricky points:**
- The greedy choice property is problem-specific — it must be proved, not assumed
- Greedy never reconsiders past choices; one wrong choice can make the rest of the solution suboptimal
- The distinction from DP: greedy never explores multiple options; DP explores all and picks the best
- Activity selection greedy works by end time, not start time or duration — always verify which ordering is correct
- Greedy algorithms are typically O(n log n) due to an initial sort step, not O(n²) like naive DP

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Activity selection (sort + scan) | O(n log n) | O(1) extra |
| Huffman encoding | O(n log n) | O(n) |
| Dijkstra (binary heap) | O((V + E) log V) | O(V) |
| Coin change (standard denominations) | O(n) | O(1) |

---

## What It Is

Imagine you are hiking to the top of a mountain in dense fog with no map. At each fork in the path, your strategy is always to take whichever branch seems to go most directly uphill. This is the greedy strategy: always pick the option that looks best right now and never turn around. On a simple hill with a single peak, this strategy guarantees you reach the summit. On a landscape with multiple peaks and valleys, it can trap you on a local high point that is nowhere near the tallest summit. Whether the greedy strategy works depends entirely on the shape of the landscape — the structure of the problem.

Greedy algorithms formalise this intuition. At each decision point, a greedy algorithm applies a selection criterion — some measure of "best" in the local context — and commits irrevocably to that choice. The algorithm never backtracks to reconsider. For this to produce a globally optimal result, the problem must have the greedy choice property: there must always exist an optimal solution that includes the greedy choice. If you can prove that picking the locally best option never closes the door on the globally best outcome, the algorithm is correct. If you cannot, you need dynamic programming, which considers all options and finds the best combination.

The activity selection problem is the clearest illustration of why the greedy strategy works when it works. You have a set of meetings with start and end times, and a single room, and you want to schedule as many non-overlapping meetings as possible. Greedy says: always pick the meeting that ends earliest. Why? Because picking the earliest-ending meeting leaves the maximum remaining time for future meetings. Any other choice leaves the same or less remaining time. An exchange argument makes this rigorous: take any optimal solution that does not use the earliest-ending meeting, and swap that meeting out for the earliest-ending one. The resulting schedule is still valid and has the same or better coverage. Therefore the greedy choice is always safe.

---

## How It Actually Works

The typical structure of a greedy algorithm is: sort the input by the selection criterion (or use a priority queue for online processing), then iterate through the sorted input and greedily accept or reject each item. The sorting step usually dominates the running time. The per-item decision is O(1) or O(log n) depending on whether a heap is involved.

The coin change problem with standard US denominations (1, 5, 10, 25 cents) works greedily: always pick the largest coin that fits. With non-standard denominations like {1, 3, 4}, greedy fails for amount = 6: it picks 4 + 1 + 1 (3 coins) when 3 + 3 (2 coins) is better. The problem has optimal substructure but lacks the greedy choice property for arbitrary denominations, so dynamic programming is required in the general case.

```python
from heapq import heappush, heappop
from typing import List, Tuple


# --- Activity Selection: greedily pick earliest-ending meetings ---
def activity_selection(activities: List[Tuple[int, int]]) -> List[Tuple[int, int]]:
    # Sort by end time — this is the greedy ordering
    sorted_acts = sorted(activities, key=lambda x: x[1])
    selected = []
    last_end = -1

    for start, end in sorted_acts:
        if start >= last_end:  # no overlap with last selected
            selected.append((start, end))
            last_end = end

    return selected


# --- Coin Change (greedy — only correct for canonical coin systems) ---
def coin_change_greedy(coins: List[int], amount: int) -> List[int]:
    coins_sorted = sorted(coins, reverse=True)
    result = []
    for coin in coins_sorted:
        while amount >= coin:
            result.append(coin)
            amount -= coin
    return result if amount == 0 else []  # empty = no solution


# --- Huffman Encoding: greedy via min-heap ---
def huffman_codes(frequencies: dict) -> dict:
    # Each entry: (frequency, symbol)
    heap = [[freq, [sym, ""]] for sym, freq in frequencies.items()]
    import heapq
    heapq.heapify(heap)

    while len(heap) > 1:
        lo = heapq.heappop(heap)
        hi = heapq.heappop(heap)
        # Assign 0 to the lower-frequency branch, 1 to higher
        for pair in lo[1:]:
            pair[1] = '0' + pair[1]
        for pair in hi[1:]:
            pair[1] = '1' + pair[1]
        heapq.heappush(heap, [lo[0] + hi[0]] + lo[1:] + hi[1:])

    return {item[0]: item[1] for item in heap[0][1:]}


# --- Fractional Knapsack: greedy by value-per-weight ratio ---
def fractional_knapsack(
    items: List[Tuple[float, float]],  # (value, weight)
    capacity: float
) -> float:
    # Sort by value/weight ratio descending
    sorted_items = sorted(items, key=lambda x: x[0] / x[1], reverse=True)
    total_value = 0.0
    remaining = capacity

    for value, weight in sorted_items:
        if weight <= remaining:
            total_value += value
            remaining -= weight
        else:
            # Take a fraction of this item
            total_value += value * (remaining / weight)
            break

    return total_value


# Demonstration
meetings = [(1, 4), (3, 5), (0, 6), (5, 7), (3, 9), (5, 9), (6, 10), (8, 11)]
print(activity_selection(meetings))  # [(1,4), (5,7), (8,11)] or similar

print(coin_change_greedy([25, 10, 5, 1], 41))  # [25, 10, 5, 1]
```

---

## How It Connects

Greedy algorithms sit at the simpler end of the optimisation spectrum. When a greedy algorithm is correct, it is almost always faster and simpler than the DP solution for the same problem. The progression to understand is: if a locally optimal choice is always globally safe, use greedy; if subproblems overlap and you cannot guarantee local optimality is sufficient, use dynamic programming; if the problem requires exploring all possible configurations, use backtracking.

Dijkstra's shortest path algorithm is greedy: it always processes the vertex with the currently smallest known distance. This greedy choice is correct because edge weights are non-negative, guaranteeing that the current best distance to a vertex will never improve once it is processed. With negative edge weights, this guarantee breaks down, and the non-greedy Bellman-Ford algorithm is required.

[[dynamic-programming|Dynamic Programming]]
[[dijkstra|Dijkstra's Algorithm]]
[[minimum-spanning-tree|Minimum Spanning Tree]]
[[backtracking|Backtracking]]

---

## Common Misconceptions

Misconception 1: If a greedy algorithm gives the correct answer on the examples you tested, it is correct in general.
Reality: Greedy correctness must be proved, not validated empirically. Coin change with {1, 3, 4} gives the correct answer for most small amounts but fails at amount = 6. Testing cannot reveal failure cases for all inputs; only a proof (typically an exchange argument) guarantees correctness for all valid inputs.

Misconception 2: Greedy and dynamic programming are competing approaches and one is always better.
Reality: They solve different problems. Greedy is applicable only when the greedy choice property holds; in those cases it is typically faster and simpler. DP is required when the greedy choice can lead to suboptimal outcomes and you must compare multiple options. Many algorithms contain both: Dijkstra uses a greedy selection criterion but maintains a table of distances that gets updated as better paths are found.

---

## Why It Matters in Practice

Greedy algorithms underlie some of the most important practical algorithms in computer science: Dijkstra's routing protocol, Huffman compression (used in JPEG, MP3, and HTTP/2), Prim's and Kruskal's minimum spanning tree algorithms (used in network design), and task scheduling. Their efficiency — typically O(n log n) — makes them suitable for real-time and large-scale applications where DP's polynomial but potentially quadratic complexity is too slow.

Recognising when a greedy approach is valid is a high-value skill. The questions to ask are: does always taking the locally best option leave all future options at least as good as any other choice would? If yes, greedy is provably correct. Developing this intuition through practice with canonical problems (activity selection, fractional knapsack, Huffman encoding) gives you the pattern-matching to apply it quickly in novel situations.

---

## Interview Angle

Common question forms:
- "What is the minimum number of meeting rooms needed for these intervals?"
- "Schedule tasks to minimise the number of late completions."
- "Select items to maximise value within a weight limit." (Note: integer knapsack requires DP, fractional is greedy.)

Answer frame:
State the greedy criterion (the selection rule). Justify why it is correct — ideally an exchange argument sketch. Sort by the criterion and iterate, tracking the relevant state. State time complexity as O(n log n) for the sort. Compare to the DP solution and explain why greedy suffices here.

---

## Related Notes

- [[dynamic-programming|Dynamic Programming]]
- [[dijkstra|Dijkstra's Algorithm]]
- [[minimum-spanning-tree|Minimum Spanning Tree]]
- [[backtracking|Backtracking]]
- [[divide-and-conquer|Divide and Conquer]]
