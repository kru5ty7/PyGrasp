---
title: 45 - Topological Sort
description: A linear ordering of vertices in a DAG such that every directed edge u→v places u before v, enabling dependency resolution for tasks, builds, and imports.
tags: [dsa, layer-10, topological-sort, dag, dfs]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Topological Sort

> Topological sort orders a directed acyclic graph so that every dependency comes before the thing that depends on it — developers working on build systems, task schedulers, or package managers must know it because it is the algorithm that determines what order to process things when order matters.

---

## Quick Reference

**Core idea:**
- Only defined for DAGs (Directed Acyclic Graphs) — if a cycle exists, no valid ordering is possible
- Kahn's algorithm: repeatedly remove vertices with no incoming edges (in-degree zero) using a queue
- DFS-based: complete a DFS, push each vertex to a stack when all its descendants are processed; the stack reversed is the topological order
- Kahn's algorithm naturally detects cycles: if the output has fewer vertices than the graph, a cycle prevents completion
- Applications: build systems (make, Gradle), task scheduling, course prerequisite ordering, import resolution
- A graph may have multiple valid topological orderings — any valid one is acceptable unless a specific order is required

**Tricky points:**
- Topological sort requires a directed graph — undirected graph cycles are handled differently
- Kahn's algorithm processes vertices in BFS order; DFS-based gives a different valid ordering — both are correct
- Computing in-degrees correctly requires scanning all edges, not just the adjacency lists
- If a vertex has zero in-degree but multiple valid successor orderings, Kahn's queue may produce any of them — to get the lexicographically smallest, use a min-heap instead of a queue
- The detected "cycle" in Kahn's algorithm is not located — it only tells you a cycle exists somewhere in the remaining unprocessed vertices

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Kahn's algorithm | O(V + E) | O(V) |
| DFS-based | O(V + E) | O(V) call stack + O(V) output |
| Both on dense graph (E = V²) | O(V²) | O(V) |

---

## What It Is

Imagine you are a new chef at a restaurant trying to learn the recipe for a complex dish. The recipe has steps: you cannot garnish until the dish is plated, you cannot plate until cooking is done, you cannot cook until the ingredients are prepared, and you cannot prepare some ingredients until others are ready. This web of dependencies defines an order — certain steps must come before others — but the recipe never says you cannot prepare the vegetables while the sauce simmers. The topological sort finds a valid linear order for all steps that respects every "must come before" constraint.

The formal setting is a directed acyclic graph, or DAG. Each vertex is a task (or a course, or a file, or a package), and each directed edge u→v means "u must be completed before v." Topological sort produces a linear sequence of all vertices such that every edge points forward in the sequence — no vertex appears before something it depends on. The acyclic requirement is non-negotiable: if task A depends on task B and task B depends on task A, no valid ordering exists. Any build system that fails with a "circular dependency" error is detecting exactly this condition.

There is an intuitive way to derive the topological order. Look for a task with no prerequisites — it can be done first. Remove it from the graph. Now look for tasks with no remaining prerequisites. Repeat. This is Kahn's algorithm. The queue holds tasks that are "ready" (no remaining dependencies), and the algorithm drains it by processing one ready task, decrementing the prerequisite count for all tasks it unlocks, and adding newly unblocked tasks to the queue. If at the end there are unprocessed tasks, they form a cycle — each one still depends on another unprocessed task, and that dependency can never be satisfied.

---

## How It Actually Works

Kahn's algorithm requires computing the in-degree of each vertex (the number of directed edges pointing to it) as a preprocessing step. Vertices with in-degree zero are added to the queue. Each time a vertex is removed from the queue, its outgoing edges are "removed" by decrementing the in-degree of each neighbour. Any neighbour whose in-degree drops to zero is added to the queue. The output list accumulates vertices in the order they are removed from the queue.

The DFS-based approach works differently. Run DFS on the graph, and when a vertex's DFS call finishes (after all its successors have been recursively processed), push it onto a stack. After all vertices have been visited, the stack contains the topological order from top to bottom. This works because a vertex is pushed only after all vertices reachable from it have been pushed — so in the final order (stack reversed), it appears before all of them.

```python
from collections import deque, defaultdict
from typing import Dict, List, Optional


# --- Kahn's Algorithm (BFS-based, with cycle detection) ---
def topological_sort_kahn(
    num_vertices: int,
    edges: List[tuple]    # list of (u, v) meaning u must come before v
) -> Optional[List[int]]:
    """
    Returns topological order, or None if a cycle is detected.
    """
    in_degree = [0] * num_vertices
    adj: Dict[int, List[int]] = defaultdict(list)

    for u, v in edges:
        adj[u].append(v)
        in_degree[v] += 1

    # Start with all zero-in-degree vertices
    queue: deque[int] = deque()
    for v in range(num_vertices):
        if in_degree[v] == 0:
            queue.append(v)

    order = []
    while queue:
        u = queue.popleft()
        order.append(u)
        for v in adj[u]:
            in_degree[v] -= 1
            if in_degree[v] == 0:
                queue.append(v)

    # If not all vertices were processed, a cycle exists
    if len(order) != num_vertices:
        return None   # cycle detected

    return order


# --- DFS-based Topological Sort ---
def topological_sort_dfs(
    num_vertices: int,
    edges: List[tuple]
) -> Optional[List[int]]:
    """
    Returns topological order, or None if a cycle is detected.
    Uses 3-colour DFS: 0=unvisited, 1=in-stack, 2=done.
    """
    adj: Dict[int, List[int]] = defaultdict(list)
    for u, v in edges:
        adj[u].append(v)

    state = [0] * num_vertices   # 0=unvisited, 1=in-progress, 2=done
    result = []
    has_cycle = False

    def dfs(u: int) -> None:
        nonlocal has_cycle
        if has_cycle:
            return
        state[u] = 1   # mark as in-progress (on current DFS path)
        for v in adj[u]:
            if state[v] == 1:
                has_cycle = True  # back edge found: cycle
                return
            if state[v] == 0:
                dfs(v)
        state[u] = 2   # mark as done
        result.append(u)  # push after all descendants are processed

    for v in range(num_vertices):
        if state[v] == 0:
            dfs(v)

    if has_cycle:
        return None

    result.reverse()   # reverse gives topological order
    return result


# --- Course Schedule: can you complete all courses? ---
def can_finish(num_courses: int, prerequisites: List[List[int]]) -> bool:
    """
    Each prerequisite [a, b] means b must be taken before a.
    Returns True if a valid course order exists (no cycles).
    """
    result = topological_sort_kahn(num_courses, [(b, a) for a, b in prerequisites])
    return result is not None


# Demonstrations
edges = [(5, 2), (5, 0), (4, 0), (4, 1), (2, 3), (3, 1)]
print(topological_sort_kahn(6, edges))   # e.g. [4, 5, 0, 2, 3, 1]
print(topological_sort_dfs(6, edges))   # a different valid ordering

print(can_finish(4, [[1, 0], [2, 0], [3, 1], [3, 2]]))  # True
print(can_finish(2, [[1, 0], [0, 1]]))                   # False (cycle)
```

---

## How It Connects

Topological sort is fundamentally DFS with a post-order collection step, or BFS with in-degree tracking. Understanding it solidifies both DFS and BFS patterns. The cycle detection embedded in Kahn's algorithm — output length shorter than vertex count — is a clean, practical technique that appears as a sub-step in many graph problems.

Cycle detection in directed graphs using three-state DFS (unvisited, in-stack, done) is related but distinct from the topological sort itself. The three-state pattern ensures that a back edge (an edge to an in-stack ancestor) is correctly identified as a cycle indicator, while cross edges (to already-completed vertices) are not.

[[graphs|Graphs]]
[[dfs|Depth-First Search]]
[[bfs|BFS]]
[[cycle-detection|Cycle Detection]]

---

## Common Misconceptions

Misconception 1: Any directed graph has a topological sort.
Reality: Only DAGs have a topological sort. If the graph contains any directed cycle, it is impossible to order the vertices such that every edge points forward — the cycle vertices would need to appear both before and after each other simultaneously. This is why cycle detection and topological sort are closely linked: a topological sort that fails (Kahn's output is shorter than the vertex count) is simultaneously a cycle detector.

Misconception 2: The topological sort of a graph is unique.
Reality: Most graphs have multiple valid topological orderings. The ordering produced by Kahn's algorithm depends on which zero-in-degree vertex is dequeued first, which depends on the queue's order. Replacing the queue with a min-heap gives the lexicographically smallest topological ordering. For most applications (build systems, task scheduling), any valid ordering is acceptable.

---

## Why It Matters in Practice

Topological sort is the algorithm at the core of every build system. GNU Make, Gradle, Bazel, and Webpack all use topological ordering to determine in which order to compile, link, or bundle files. Package managers (npm, pip, cargo) use it to determine the installation order for dependencies. Python's import system resolves circular imports by detecting cycles in the module dependency graph. Any time you have tasks with dependencies and want to process them in a valid order, topological sort is the right algorithm.

In interviews, topological sort problems frequently appear as "course schedule" variants — can you complete all courses given prerequisites? — or as "task ordering" problems. The expected solution is Kahn's algorithm with cycle detection, and the implementation is concise enough to write from scratch in an interview.

---

## Interview Angle

Common question forms:
- "Given a list of course prerequisites, determine if you can finish all courses."
- "Find a valid order to complete all tasks given dependencies."
- "Given a set of build dependencies, output a valid build order."

Answer frame:
Identify the problem as topological sort on a DAG. Build the adjacency list and in-degree array from the dependency list. Run Kahn's algorithm (queue of zero-in-degree vertices, decrement neighbours, enqueue when zero). If output length equals V, return the order; otherwise, report a cycle. State O(V + E) time and O(V) space.

---

## Related Notes

- [[graphs|Graphs]]
- [[dfs|Depth-First Search]]
- [[bfs|BFS]]
- [[cycle-detection|Cycle Detection]]
- [[graph-representations|Graph Representations]]
