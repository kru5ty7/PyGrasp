---
title: 31 - Depth-First Search
description: DFS explores a graph by going as deep as possible along each branch before backtracking, using a stack (implicitly via recursion) to track the exploration path.
tags: [dsa, layer-10, dfs, graph-traversal, recursion]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Depth-First Search

> DFS is the exploration algorithm of choice for problems involving reachability, connectivity, and path existence - and it underlies virtually every tree traversal algorithm you have ever used.

---

## Quick Reference

**Core idea:**
- Start from a source node, mark it visited, and immediately recurse into its first unvisited neighbour
- Continue going deeper until you reach a dead end (all neighbours visited), then backtrack to the previous node and try the next unvisited neighbour
- Uses a stack - implicitly via the call stack in recursive DFS, or explicitly in iterative DFS
- Does NOT guarantee shortest path
- O(V + E) time; O(V) space (call stack depth in worst case)
- Essential for: cycle detection, topological sort, connected components, path existence, tree traversals

**Tricky points:**
- Recursive DFS can hit Python's default recursion limit (1000) on deep graphs - use iterative DFS or increase the limit with `sys.setrecursionlimit()` for large inputs
- Iterative DFS (with an explicit stack) does not visit nodes in the same order as recursive DFS - iterative DFS visits in reverse neighbour order because the stack reverses the order
- The visited set must be maintained; without it DFS loops forever on cyclic graphs
- Pre-order, in-order, and post-order tree traversals are all DFS traversals - they differ only in when the node is processed relative to its children
- For directed graphs, DFS is used to detect cycles and produce topological sort; for undirected graphs, it finds connected components

---

## Complexity

| Operation | Time | Space |
|---|---|---|
| Best case | O(1) | O(1) |
| Average case | O(V + E) | O(V) |
| Worst case (path graph) | O(V + E) | O(V) |

---

## What It Is

Think of exploring a maze with a ball of string. You enter a corridor and keep walking forward, unspooling the string behind you to mark where you have been. When you reach a dead end or a junction where all exits lead to already-visited corridors, you follow the string back to the last junction that had an unexplored exit and try that exit instead. You continue this process until you have explored every reachable corridor. The string is your path record; the act of following it back is backtracking.

DFS embodies this maze-exploration strategy. It commits fully to one path before considering alternatives. Starting from a node, it visits a neighbour, then a neighbour of that neighbour, and keeps going deeper until it reaches a node with no unvisited neighbours. Then it backtracks - returning to the most recent node that still has unexplored neighbours - and explores from there. The exploration order is depth-first: you go as far as you can in one direction before backtracking and trying another.

The mechanism that implements this naturally is recursion. Each recursive call corresponds to moving one step deeper into the maze. The call stack is the ball of string - it records the path from the source to the current node, and returning from a recursive call is the backtrack step. This is why the space complexity of DFS is O(depth), which in the worst case (a path graph) equals O(V). When the depth is large enough to overflow Python's recursion stack, an iterative DFS with an explicit stack achieves the same traversal without recursion.

---

## How It Actually Works

Recursive DFS marks the current node as visited, processes it, and then loops over its neighbours. For each unvisited neighbour, it recurses. When the recursion for a neighbour completes (the entire subgraph reachable through that neighbour has been explored), the loop continues to the next neighbour. When all neighbours are exhausted, the function returns - this is the backtrack. The order in which a node is processed relative to its recursive calls determines whether it is pre-order (before recursing), post-order (after recursing), or in-order (between left and right children, for binary trees).

Iterative DFS replaces the call stack with an explicit stack data structure. Push the source node. Enter a loop: pop the top node, if not visited mark it visited and process it, then push all its unvisited neighbours. The loop exits when the stack is empty. The iteration order differs from recursive DFS because the stack reverses the order in which neighbours are pushed - to match recursive DFS order exactly, push neighbours in reverse order.

```python
# --- Recursive DFS ---
def dfs_recursive(graph: dict, source, visited: set = None) -> list:
    """DFS from source. Returns list of visited nodes in DFS order."""
    if visited is None:
        visited = set()
    visited.add(source)
    result = [source]
    for neighbour in graph[source]:
        if neighbour not in visited:
            result.extend(dfs_recursive(graph, neighbour, visited))
    return result


# --- Iterative DFS ---
def dfs_iterative(graph: dict, source) -> list:
    """Iterative DFS using explicit stack. Note: visits in different order
    from recursive DFS unless neighbours are reversed before pushing."""
    visited = set()
    stack = [source]
    result = []
    while stack:
        node = stack.pop()   # LIFO: pop from top
        if node not in visited:
            visited.add(node)
            result.append(node)
            # Push neighbours in reverse to match recursive DFS order
            for neighbour in reversed(graph[node]):
                if neighbour not in visited:
                    stack.append(neighbour)
    return result


# --- Cycle detection in a directed graph ---
def has_cycle_directed(graph: dict) -> bool:
    """Detect cycle in directed graph using DFS with three-colour marking.
    WHITE=0 (unvisited), GRAY=1 (in current path), BLACK=2 (fully processed)."""
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {node: WHITE for node in graph}

    def dfs(node):
        color[node] = GRAY   # mark as in-progress
        for neighbour in graph[node]:
            if color[neighbour] == GRAY:
                return True  # back edge: cycle found
            if color[neighbour] == WHITE and dfs(neighbour):
                return True
        color[node] = BLACK  # mark as fully processed
        return False

    return any(dfs(node) for node in graph if color[node] == WHITE)


# --- Topological sort (DFS-based) ---
def topological_sort(graph: dict) -> list:
    """Returns nodes in topological order (sources first).
    Assumes directed acyclic graph (DAG). Uses post-order DFS."""
    visited = set()
    result = []

    def dfs(node):
        visited.add(node)
        for neighbour in graph[node]:
            if neighbour not in visited:
                dfs(neighbour)
        result.append(node)   # post-order: add after all descendants

    for node in graph:
        if node not in visited:
            dfs(node)

    return result[::-1]  # reverse post-order = topological order


# --- Tree traversals (pre/in/post order) ---
class TreeNode:
    def __init__(self, val=0, left=None, right=None):
        self.val = val
        self.left = left
        self.right = right

def preorder(root: TreeNode) -> list:
    if not root:
        return []
    return [root.val] + preorder(root.left) + preorder(root.right)

def inorder(root: TreeNode) -> list:
    if not root:
        return []
    return inorder(root.left) + [root.val] + inorder(root.right)

def postorder(root: TreeNode) -> list:
    if not root:
        return []
    return postorder(root.left) + postorder(root.right) + [root.val]


# Example graph
graph = {
    'A': ['B', 'C'],
    'B': ['D', 'E'],
    'C': ['F'],
    'D': [],
    'E': ['F'],
    'F': []
}
print(dfs_recursive(graph, 'A'))   # ['A', 'B', 'D', 'E', 'F', 'C']
print(dfs_iterative(graph, 'A'))   # ['A', 'B', 'D', 'E', 'F', 'C']
```

---

## Visualizer

<iframe src="/static/visualizers/dfs.html" style="width:100%;height:460px;border:none;border-radius:8px;" title="DFS Visualizer"></iframe>

---

## How It Connects

DFS is complementary to BFS: both explore all nodes reachable from a source in O(V + E) time, but DFS uses a stack (depth-first) while BFS uses a queue (breadth-first). The choice between them depends on the structure of the problem. DFS's post-order property - processing a node after all its descendants - is what makes it suitable for topological sort and cycle detection, applications where BFS cannot be directly substituted.

[[bfs|Breadth-First Search]]
[[bfs-vs-dfs|BFS vs DFS]]
[[graphs|Graphs]]
[[recursion|Recursion]]

---

## Common Misconceptions

Misconception 1: "Recursive DFS and iterative DFS always visit nodes in the same order."
Reality: They visit the same set of nodes but not necessarily in the same order. The call stack processes neighbours in the order they are listed; the explicit stack in iterative DFS processes them in reverse order because items pushed last are popped first. To match recursive DFS order in the iterative version, push neighbours in reverse order before processing. For many applications (like cycle detection or connectivity), the order does not matter - but for topological sort or when order is semantically significant, the difference matters.

Misconception 2: "DFS is not suitable for finding paths because it does not guarantee shortest paths."
Reality: DFS finds a valid path between two nodes if one exists - it will not miss a path. It does not find the shortest path, but it does find existence of a path and can reconstruct one specific path. For maze problems where you need any valid solution rather than the optimal one, DFS is a perfectly valid approach and often simpler to implement with backtracking. The limitation is only that the path DFS finds is not guaranteed to be the shortest.

Misconception 3: "DFS always uses O(V) space."
Reality: DFS uses O(d) space where d is the depth of the deepest path explored. For a balanced binary tree, d = O(log V). For a path graph (a line of nodes), d = O(V). For a broad, shallow graph (star topology), d = O(1). The O(V) worst case applies when the graph is a single long path, where every node must be on the call stack simultaneously.

---

## Why It Matters in Practice

DFS appears in an enormous range of applications. Every tree traversal algorithm (pre-order, in-order, post-order) is DFS. Topological sort of a DAG - essential for dependency resolution in build systems, package managers, and task schedulers - uses DFS post-order. Cycle detection in directed graphs uses DFS with three-colour marking. Finding connected components in undirected graphs, detecting strongly connected components (Tarjan's algorithm, Kosaraju's algorithm) - all DFS-based. Solving backtracking problems like sudoku, n-queens, and permutation generation all use the same DFS-with-backtracking pattern.

In Python, the primary concern with recursive DFS on large inputs is the recursion limit. For competitive programming and interview problems where the graph may have hundreds of thousands of nodes, iterative DFS with an explicit stack is the safe choice. For production code with graphs of bounded depth (like abstract syntax trees or dependency graphs of realistic projects), recursive DFS is readable and correct.

---

## Interview Angle

Common question forms:
- "Implement DFS on a graph."
- "Detect a cycle in a directed/undirected graph."
- "Topological sort of a DAG."
- "Number of islands (connected components in a grid)."
- "All paths from source to target in a graph."

Answer frame:
Implement recursive DFS for clarity; mention iterative DFS and the recursion-limit concern for large inputs. For cycle detection: directed graphs use three-colour DFS (gray = in-progress, black = done); undirected graphs check whether a visited neighbour is the parent. For topological sort: post-order DFS and reverse. For connected components: run DFS from each unvisited node, increment count each time a new DFS is started. For all-paths: standard DFS with path tracking and backtracking (remove current node from path before returning).

---

## Related Notes

- [[bfs|Breadth-First Search]]
- [[bfs-vs-dfs|BFS vs DFS]]
- [[graphs|Graphs]]
- [[recursion|Recursion]]
- [[graph-representations|Graph Representations]]
