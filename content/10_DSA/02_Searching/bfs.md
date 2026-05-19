---
title: 30 - Breadth-First Search
description: BFS explores a graph or tree level by level using a queue, guaranteeing the shortest path (by edge count) in an unweighted graph and visiting all nodes reachable from the source.
tags: [dsa, layer-10, bfs, graph-traversal, shortest-path]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Breadth-First Search

> BFS is the right tool whenever "closest first" is the correct order of exploration - and the guarantee of shortest path makes it the foundation of network routing, social graph analysis, and countless interview problems.

---

## Quick Reference

**Core idea:**
- Start from a source node, add it to a queue and mark it visited
- Repeatedly dequeue the front node, process it, and enqueue all its unvisited neighbours (marking them visited immediately on enqueue)
- Nodes are visited in order of their distance from the source, measured in number of edges
- Guarantees shortest path in terms of edge count in an unweighted graph
- O(V + E) time; O(V) space for the visited set and queue
- Uses a FIFO queue (Python: `collections.deque`)

**Tricky points:**
- Mark nodes as visited when they are added to the queue, not when they are dequeued - marking on dequeue can add the same node to the queue multiple times
- Without a visited set, BFS loops forever on cyclic graphs
- BFS finds the shortest path by edge count, not by edge weight - Dijkstra's algorithm handles weighted graphs
- Level-order tree traversal is BFS on a tree (no visited set needed because trees have no cycles)
- The visited set for BFS on a grid uses `(row, col)` tuples; for a graph it uses node identifiers

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case | O(1) | O(1) |
| Average case | O(V + E) | O(V) |
| Worst case (fully connected graph) | O(V + E) | O(V) |

---

## What It Is

Imagine dropping a stone into a still pond. The ripple expands outward in a circle, reaching all points one metre from the impact before reaching any point two metres away, and all points two metres away before reaching three metres away. The wave front advances uniformly, level by level, exploring every point at the current distance before moving on to the next distance. BFS is the computational equivalent of this expanding ripple: it explores all nodes at distance 1 from the source before any node at distance 2, all nodes at distance 2 before any node at distance 3, and so on.

This level-by-level property is what gives BFS its shortest-path guarantee. When BFS first visits a node, it has arrived there via the fewest possible edges from the source. This is true because BFS processes nodes in the exact order they were added to the queue, and nodes are added to the queue in order of their distance from the source. The first time a node is dequeued, no shorter path to it could have been found - all shorter paths would have been explored in earlier levels. This reasoning is the correctness proof for BFS as a shortest-path algorithm.

The data structure that makes BFS possible is the queue - specifically a first-in-first-out queue. The queue is what enforces the level-by-level order. Nodes discovered at distance d are enqueued before any node at distance d+1, so they are dequeued and processed first. If you replaced the queue with a stack, you would get depth-first search instead: the exploration would dive deep into one branch before backtracking, losing the level-by-level property and the shortest-path guarantee. The choice of data structure - queue for BFS, stack for DFS - is the single mechanic that distinguishes the two fundamental graph traversal algorithms.

---

## How It Actually Works

The algorithm begins by adding the source node to the queue and marking it as visited. Then it enters a loop: dequeue the front node, process it (record its distance, add it to the path, etc.), then enqueue each of its neighbours that has not yet been visited, marking each as visited immediately. The loop terminates when the queue is empty, meaning all reachable nodes have been processed.

The key implementation detail is when to mark nodes as visited. Marking on enqueue (when the node is added to the queue, not when it is removed) ensures each node appears in the queue at most once. If you mark on dequeue instead, you may enqueue the same node from multiple neighbours before it is processed, leading to redundant work and incorrect distance calculations.

```python
from collections import deque


def bfs(graph: dict, source) -> dict:
    """BFS from source. Returns dict mapping each reachable node to its
    shortest distance (in edges) from source."""
    visited = {source}
    queue = deque([source])
    distances = {source: 0}

    while queue:
        node = queue.popleft()           # FIFO: dequeue from front
        for neighbour in graph[node]:
            if neighbour not in visited:
                visited.add(neighbour)   # mark visited on ENQUEUE
                queue.append(neighbour)
                distances[neighbour] = distances[node] + 1

    return distances


def bfs_shortest_path(graph: dict, source, target) -> list:
    """BFS to find shortest path from source to target.
    Returns path as a list of nodes, or [] if no path exists."""
    if source == target:
        return [source]
    visited = {source}
    queue = deque([[source]])            # queue of paths, not nodes

    while queue:
        path = queue.popleft()
        node = path[-1]
        for neighbour in graph[node]:
            if neighbour not in visited:
                new_path = path + [neighbour]
                if neighbour == target:
                    return new_path
                visited.add(neighbour)
                queue.append(new_path)

    return []  # no path found


# Level-order tree traversal (BFS on a tree - no visited set needed)
class TreeNode:
    def __init__(self, val=0, left=None, right=None):
        self.val = val
        self.left = left
        self.right = right

def level_order(root: TreeNode) -> list:
    """Returns list of lists: each inner list is one level of the tree."""
    if not root:
        return []
    result = []
    queue = deque([root])
    while queue:
        level_size = len(queue)          # number of nodes at current level
        level = []
        for _ in range(level_size):
            node = queue.popleft()
            level.append(node.val)
            if node.left:
                queue.append(node.left)
            if node.right:
                queue.append(node.right)
        result.append(level)
    return result


# BFS on a grid (finding shortest path in a maze)
def bfs_grid(grid: list, start: tuple, end: tuple) -> int:
    """Returns shortest path length (steps) from start to end in a grid.
    Grid cells are 0 (open) or 1 (blocked). Returns -1 if no path."""
    rows, cols = len(grid), len(grid[0])
    directions = [(0,1),(0,-1),(1,0),(-1,0)]
    visited = {start}
    queue = deque([(start, 0)])          # (position, distance)

    while queue:
        (r, c), dist = queue.popleft()
        if (r, c) == end:
            return dist
        for dr, dc in directions:
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols and grid[nr][nc] == 0 and (nr, nc) not in visited:
                visited.add((nr, nc))
                queue.append(((nr, nc), dist + 1))

    return -1


# Example usage
graph = {
    'A': ['B', 'C'],
    'B': ['A', 'D', 'E'],
    'C': ['A', 'F'],
    'D': ['B'],
    'E': ['B', 'F'],
    'F': ['C', 'E']
}
print(bfs(graph, 'A'))
# {'A': 0, 'B': 1, 'C': 1, 'D': 2, 'E': 2, 'F': 2}
print(bfs_shortest_path(graph, 'A', 'F'))
# ['A', 'C', 'F']
```

---

## Visualizer

<iframe src="/static/visualizers/bfs.html" style="width:100%;height:460px;border:none;border-radius:8px;" title="BFS Visualizer"></iframe>

---

## How It Connects

BFS on a graph is the direct generalisation of level-order traversal on a tree - the only difference is the visited set, which is needed for graphs because they can have cycles. Understanding the queue structure is the link between BFS and the abstract concept of FIFO queues. DFS uses a stack instead and explores in depth-first order; comparing the two traversals on the same graph is the best way to understand what each data structure choice implies.

[[queues|Queues]]
[[graphs|Graphs]]
[[dfs|Depth-First Search]]
[[bfs-vs-dfs|BFS vs DFS]]

---

## Common Misconceptions

Misconception 1: "BFS finds the shortest path in any weighted graph."
Reality: BFS finds the shortest path in terms of number of edges, treating all edges as having equal weight. If edges have different weights, BFS does not find the shortest path by total weight. Dijkstra's algorithm is the standard solution for weighted shortest paths with non-negative edge weights. For graphs with negative edges, Bellman-Ford is required. BFS is correct for unweighted graphs (or graphs where all edge weights are equal).

Misconception 2: "The visited set is optional - BFS will terminate naturally."
Reality: Without a visited set, BFS on a graph with cycles will loop forever: it will keep rediscovering already-visited nodes, adding them to the queue again, discovering their neighbours again, and so on. The visited set (marking nodes when they are enqueued) is essential for correctness on any graph that might have cycles. Trees are the one case where no visited set is needed because they are acyclic by definition.

Misconception 3: "BFS uses more memory than DFS."
Reality: This is context-dependent. BFS stores all nodes at the current frontier level in the queue simultaneously - for a wide graph (many nodes close to the root), this can be O(V). DFS stores the current path from source to the current node on the stack, which is O(depth). For a deep, narrow graph, DFS uses more memory. For a shallow, wide graph, BFS uses more memory. Neither is universally more memory-efficient.

---

## Why It Matters in Practice

BFS is a foundational algorithm in networking (routing protocols like OSPF use BFS-like flooding), social networks (finding degrees of separation between users), game AI (finding optimal moves in unweighted state spaces), and web crawlers (exploring links level by level to avoid going too deep too quickly). The grid-based BFS for finding shortest paths in mazes and maps is one of the most common interview problem patterns.

In Python, the key implementation detail is using `collections.deque` rather than a `list` as the queue. Appending to and popping from the right end of a list is O(1), but popping from the left (which is what BFS requires with `list.pop(0)`) is O(n) because all remaining elements must shift. `deque` supports O(1) appends to the right and O(1) pops from the left, making it the correct data structure for BFS queues.

---

## Interview Angle

Common question forms:
- "Implement BFS on a graph."
- "Find the shortest path between two nodes in an unweighted graph."
- "Level-order traversal of a binary tree."
- "Find the shortest path in a grid/maze."
- "How many steps to infect all nodes (rotting oranges, spreading fire)?"

Answer frame:
State the core data structure (deque/queue) and the visited set. Explain mark-on-enqueue explicitly - this is where many candidates make errors. State O(V + E) time and O(V) space. For shortest path: BFS naturally produces shortest paths in unweighted graphs because of the level-by-level order. For grids: translate to graph terms (each cell is a node, each adjacent open cell is an edge) and apply standard BFS. Distinguish from weighted-graph shortest path (Dijkstra needed).

---

## Related Notes

- [[dfs|Depth-First Search]]
- [[bfs-vs-dfs|BFS vs DFS]]
- [[graphs|Graphs]]
- [[queues|Queues]]
- [[graph-representations|Graph Representations]]
