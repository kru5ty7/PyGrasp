---
title: 47 - Cycle Detection
description: Algorithms for determining whether a graph or linked list contains a cycle, with different approaches required for undirected graphs, directed graphs, and linked lists.
tags: [dsa, layer-10, cycle-detection, dfs, floyd]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Cycle Detection

> Cycle detection determines whether a structure contains a loop — whether in a graph, a linked list, or a dependency chain — and developers must know it because cycles represent invalid states in build systems, deadlocks in resource allocation, and corrupted data in linked structures.

---

## Quick Reference

**Core idea:**
- Undirected graphs: DFS with a visited set — a cycle exists if you reach a visited node through a non-parent edge
- Directed graphs: DFS with three states (unvisited / in-stack / done) — a cycle exists if you reach an in-stack node
- Linked lists: Floyd's tortoise and hare — two pointers at different speeds meet if and only if a cycle exists
- Union-Find: for undirected graphs in Kruskal's MST — union fails if both endpoints are already connected
- Floyd's algorithm: O(n) time, O(1) space — optimal for linked lists
- Kahn's topological sort: if output length < V, the graph has a cycle (for directed graphs)

**Tricky points:**
- In undirected graph DFS, the parent node must be tracked to avoid treating the edge back to the parent as a cycle
- In directed graph DFS, a grey (in-stack) node signals a back edge (cycle), but a black (done) node does not — this is the critical distinction
- Floyd's algorithm detects a cycle but does not immediately tell you where it starts — a second phase is needed for that
- Union-Find cycle detection only works for undirected graphs — directed graph cycles require DFS or topological sort
- The three-state DFS also serves as the cycle detection step inside topological sort (DFS-based)

---

## Complexity

| Case | Time | Space |
|---|---|---|
| DFS cycle detection (undirected or directed) | O(V + E) | O(V) |
| Union-Find cycle detection (undirected) | O(E × α(V)) ≈ O(E) | O(V) |
| Floyd's tortoise and hare (linked list) | O(n) | O(1) |
| Kahn's cycle detection (directed, via topological sort) | O(V + E) | O(V) |

---

## What It Is

Think of a treasure hunt where each clue tells you the location of the next clue. Normally, following the chain leads you to the treasure. But imagine a mischievous puzzle-setter who made clue 7 point back to clue 3 — now the chain loops and the treasure is unreachable. Cycle detection is the process of discovering that you are walking in circles rather than making progress toward a destination. It applies to any structure where elements refer to other elements: linked lists (nodes pointing to nodes), graphs (vertices connected by edges), and dependency systems (packages requiring packages).

The challenge is that cycles are invisible from any local vantage point. Any individual node looks identical whether it is part of a linear chain or a cycle. Detection requires a global perspective — either remembering every location you have ever visited, or using a clever speed-difference trick that exploits the mathematics of circular motion.

The speed-difference trick is Floyd's tortoise and hare algorithm. Two pointers start at the beginning of a linked list. The slow pointer moves one step at a time; the fast pointer moves two steps. If there is no cycle, the fast pointer reaches the end and the algorithm terminates. If there is a cycle, the fast pointer laps the slow pointer and they meet at some node inside the cycle. The proof is elegant: once both pointers are inside the cycle, the fast pointer gains one position per step relative to the slow pointer, so the gap between them decreases by one each step until it reaches zero. They must meet within at most one full cycle traversal. The critical advantage over a visited-set approach is space: O(1) extra memory instead of O(n), because no record of visited nodes is maintained.

---

## How It Actually Works

For undirected graphs, DFS uses a visited set. When visiting a node u through an edge from its parent p, if u is already visited, a cycle is confirmed — but the edge back to p must be excluded, because revisiting the parent is not a cycle in an undirected graph. The parent is tracked as a parameter (or by recording the edge used to arrive at each node) and excluded from the cycle check.

For directed graphs, three states are needed because the concept of "visited but not yet finished" matters. An edge back to a node that is currently on the DFS call stack (in-progress, or "grey") means a directed cycle exists. An edge to a node that has already finished its DFS (done, or "black") is a cross edge or forward edge — not a cycle. Using only two states (visited/unvisited) would confuse these two cases and produce false positives for directed graphs.

```python
from collections import defaultdict, deque
from typing import Dict, List, Optional, Set


# ============================================================
# 1. Undirected Graph: DFS with parent tracking
# ============================================================
def has_cycle_undirected(num_vertices: int, edges: List[tuple]) -> bool:
    adj: Dict[int, List[int]] = defaultdict(list)
    for u, v in edges:
        adj[u].append(v)
        adj[v].append(u)   # undirected: add both directions

    visited: Set[int] = set()

    def dfs(node: int, parent: int) -> bool:
        visited.add(node)
        for neighbour in adj[node]:
            if neighbour == parent:
                continue   # skip the edge we came from
            if neighbour in visited:
                return True   # visited through a different path: cycle
            if dfs(neighbour, node):
                return True
        return False

    for v in range(num_vertices):
        if v not in visited:
            if dfs(v, -1):
                return True
    return False


# ============================================================
# 2. Directed Graph: DFS with three states
# ============================================================
def has_cycle_directed(num_vertices: int, edges: List[tuple]) -> bool:
    adj: Dict[int, List[int]] = defaultdict(list)
    for u, v in edges:
        adj[u].append(v)   # directed: one direction only

    # 0=unvisited, 1=in-stack (grey), 2=done (black)
    state = [0] * num_vertices

    def dfs(node: int) -> bool:
        state[node] = 1   # mark in-stack
        for neighbour in adj[node]:
            if state[neighbour] == 1:
                return True   # back edge: directed cycle
            if state[neighbour] == 0:
                if dfs(neighbour):
                    return True
        state[node] = 2   # mark done
        return False

    for v in range(num_vertices):
        if state[v] == 0:
            if dfs(v):
                return True
    return False


# ============================================================
# 3. Linked List: Floyd's Tortoise and Hare
# ============================================================
class ListNode:
    def __init__(self, val: int = 0, next_node=None):
        self.val = val
        self.next = next_node

def has_cycle_linked_list(head: Optional[ListNode]) -> bool:
    slow = head
    fast = head
    while fast and fast.next:
        slow = slow.next        # one step
        fast = fast.next.next   # two steps
        if slow is fast:        # they meet: cycle confirmed
            return True
    return False   # fast reached the end: no cycle


def find_cycle_start(head: Optional[ListNode]) -> Optional[ListNode]:
    """
    If a cycle exists, return the node where the cycle begins.
    Uses Floyd's algorithm phase 2: after detection, one pointer starts
    over from the head; both advance one step at a time — they meet at
    the cycle start.
    """
    slow = head
    fast = head
    # Phase 1: detect
    while fast and fast.next:
        slow = slow.next
        fast = fast.next.next
        if slow is fast:
            break
    else:
        return None   # no cycle

    # Phase 2: locate cycle start
    slow = head
    while slow is not fast:
        slow = slow.next
        fast = fast.next
    return slow   # meeting point is the cycle start


# ============================================================
# 4. Union-Find: cycle detection in undirected graphs
# ============================================================
def has_cycle_union_find(num_vertices: int, edges: List[tuple]) -> bool:
    parent = list(range(num_vertices))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]  # path halving
            x = parent[x]
        return x

    def union(x: int, y: int) -> bool:
        """Returns False if x and y are already in the same component."""
        rx, ry = find(x), find(y)
        if rx == ry:
            return False   # same component: adding this edge creates a cycle
        parent[rx] = ry
        return True

    for u, v in edges:
        if not union(u, v):
            return True   # cycle detected
    return False


# ============================================================
# Demonstrations
# ============================================================
print(has_cycle_undirected(4, [(0,1),(1,2),(2,3),(3,1)]))  # True
print(has_cycle_undirected(3, [(0,1),(1,2)]))               # False

print(has_cycle_directed(4, [(0,1),(1,2),(2,0)]))           # True (0->1->2->0)
print(has_cycle_directed(4, [(0,1),(1,2),(2,3)]))           # False

# Build a linked list 1->2->3->4->2 (cycle at node 2)
n1, n2, n3, n4 = ListNode(1), ListNode(2), ListNode(3), ListNode(4)
n1.next, n2.next, n3.next, n4.next = n2, n3, n4, n2   # cycle
print(has_cycle_linked_list(n1))           # True
print(find_cycle_start(n1).val)            # 2
```

---

## Visualizer

<iframe src="/static/visualizers/cycle-detection.html" style="width:100%;height:460px;border:none;border-radius:8px;" title="Cycle Detection Visualizer"></iframe>

---

## How It Connects

Cycle detection is a prerequisite for topological sort: a DAG has a topological ordering if and only if it contains no directed cycle. Kahn's topological sort algorithm doubles as a cycle detector — if the output contains fewer vertices than the graph, unprocessed vertices form one or more cycles. The three-state DFS cycle detection is also the cycle-detection component of the DFS-based topological sort algorithm.

Union-Find cycle detection is used inside Kruskal's MST algorithm: before adding an edge, check whether both endpoints are already connected. If yes, adding the edge would create a cycle and it is skipped. Understanding cycle detection in this context makes both Union-Find and Kruskal's clearer.

[[graphs|Graphs]]
[[dfs|Depth-First Search]]
[[topological-sort|Topological Sort]]
[[disjoint-sets|Disjoint Sets]]
[[minimum-spanning-tree|Minimum Spanning Tree]]

---

## Common Misconceptions

Misconception 1: The same DFS cycle detection algorithm works for both directed and undirected graphs.
Reality: The algorithms look similar but differ critically. For undirected graphs, revisiting any already-visited non-parent node signals a cycle. For directed graphs, revisiting a node that is currently on the call stack (in-stack state) signals a cycle, but revisiting a node that has already finished processing does not — that node was reached via a different path, not via a back edge. Using the undirected algorithm on a directed graph produces false positives for cross edges.

Misconception 2: Floyd's algorithm can only tell you whether a cycle exists, not where it starts.
Reality: Floyd's two-phase algorithm also finds the cycle start. After the tortoise and hare meet, reset one pointer to the head and advance both one step at a time. They will meet at the cycle start. The mathematical proof relies on the fact that the distance from the head to the cycle start equals the distance from the meeting point to the cycle start (modulo cycle length). This second phase runs in O(n) time and uses O(1) space.

---

## Why It Matters in Practice

Cycle detection appears in several practical contexts. Deadlock detection in operating systems models processes and resources as a graph; a cycle indicates a deadlock. Build systems detect circular dependencies (A requires B, B requires A) as directed cycles. Python's import system raises `ImportError` for circular imports, which are cycles in the module dependency graph. Database query planners detect cycles in join graphs. Any time you have a system of dependencies or references that could contain loops, cycle detection is the algorithmic tool that identifies the problem.

In interviews, cycle detection appears both directly ("does this graph contain a cycle?") and as a sub-problem within larger algorithms (topological sort feasibility, MST construction with Union-Find). Understanding all four variants — undirected DFS, directed three-state DFS, Floyd's linked-list algorithm, and Union-Find — and knowing which to apply in which context is the complete skill set.

---

## Interview Angle

Common question forms:
- "Determine if a directed / undirected graph contains a cycle."
- "Determine if a linked list has a cycle, and if so, find where it starts."
- "Given a list of course prerequisites, can you finish all courses?" (cycle detection in disguise)

Answer frame:
Identify the data structure (linked list vs graph) and the graph type (directed vs undirected). For linked lists, name Floyd's algorithm and its O(n)/O(1) advantage. For directed graphs, name the three-state DFS approach. For undirected graphs, name DFS with parent tracking or Union-Find. Implement the relevant algorithm. State time and space complexity.

---

## Related Notes

- [[graphs|Graphs]]
- [[dfs|Depth-First Search]]
- [[linked-lists|Linked Lists]]
- [[topological-sort|Topological Sort]]
- [[disjoint-sets|Disjoint Sets]]
- [[minimum-spanning-tree|Minimum Spanning Tree]]
