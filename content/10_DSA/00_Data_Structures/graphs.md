---
title: 15 - Graphs
description: A graph is a set of vertices connected by edges, making it the most general structure for modelling relationships and networks.
tags: [dsa, layer-10, graph, directed, undirected]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Graphs

> Graphs are the data structure that models the world — every network, map, dependency chain, and social connection is a graph, and the algorithms that operate on graphs are among the most impactful in computer science.

---

## Quick Reference

**Core idea:**
- A graph G = (V, E) consists of a set of vertices V (nodes) and a set of edges E (connections between vertices)
- Directed graph (digraph): edges have a direction — edge (u, v) goes from u to v but not necessarily v to u
- Undirected graph: edges have no direction — edge (u, v) implies both u→v and v→u
- Weighted graph: each edge carries a numeric weight (cost, distance, capacity)
- DAG (directed acyclic graph): directed graph with no cycles — used for dependency resolution, topological sort

**Tricky points:**
- Trees are a special case of graphs: connected, undirected, acyclic — exactly n−1 edges for n vertices
- A graph can have self-loops (edge from a vertex to itself) and multiple edges between the same two vertices
- Sparse graphs (few edges) and dense graphs (many edges) call for different representations
- Connected (undirected): there is a path between every pair of vertices. Strongly connected (directed): there is a directed path between every ordered pair.
- Cycle detection in undirected graphs uses DFS with a visited set; in directed graphs it requires tracking "currently in recursion stack" nodes

---

## Complexity

| Property | Value |
|---|---|
| Max edges (directed) | V × (V − 1) |
| Max edges (undirected) | V × (V − 1) / 2 |
| Complexity | Depends on representation — see graph-representations |

Space complexity: O(V + E) for adjacency list, O(V²) for adjacency matrix.

---

## What It Is

Consider a city's road network. Intersections are vertices and roads are edges. Each road may be one-way (directed) or two-way (undirected). Road segments have lengths (weights). The question "what is the shortest route from A to B?" is a shortest-path problem on a weighted undirected graph. This is exactly the problem that every navigation application solves, billions of times per day.

Now consider a social network. People are vertices. A friendship is an undirected edge (Alice is friends with Bob and Bob is friends with Alice). A follower relationship on Twitter is a directed edge (Alice follows Bob but Bob may not follow Alice). "Find all people within 3 degrees of connection from Alice" is a breadth-first search. "Identify communities" is a graph clustering problem. "Suggest new connections" is a link prediction problem. The social network is a graph, and all interesting questions about it are graph algorithm problems.

Dependency management is another pervasive graph problem. In a software build system, package A depends on package B, which depends on package C. This is a directed acyclic graph where edges point from dependents to dependencies. Installing packages in the correct order — so that each package is installed after all its dependencies — is topological sort. Detecting a circular dependency (A depends on B which depends on A) is cycle detection. Package managers (pip, npm, cargo) solve these problems on DAGs millions of times per day.

---

## How It Actually Works

A graph is an abstract structure — its concrete representation in memory is a separate concern covered in the graph-representations note. At the conceptual level, a graph consists of a vertex set and an edge set. Algorithms operate on this abstraction, traversing edges to discover neighbours, accumulating path costs, or marking vertices as visited.

The two fundamental traversal algorithms — BFS and DFS — differ in the order they explore vertices. BFS uses a queue and explores all vertices at distance 1 before distance 2, discovering vertices in order of their distance from the source. DFS uses a stack (or recursion) and follows a path as deep as possible before backtracking. BFS is the right tool for shortest-path problems in unweighted graphs; DFS is the right tool for cycle detection, topological sort, and connectivity analysis.

```python
# Graph represented as adjacency list (dict of sets)
# This is covered in depth in graph-representations.md
# Here: focus on graph concepts and common algorithms

from collections import defaultdict, deque


class Graph:
    """Undirected unweighted graph using adjacency list."""

    def __init__(self):
        self.adj = defaultdict(set)
        self.vertices = set()

    def add_vertex(self, v):
        self.vertices.add(v)
        if v not in self.adj:
            self.adj[v] = set()

    def add_edge(self, u, v):
        self.adj[u].add(v)
        self.adj[v].add(u)   # undirected
        self.vertices.add(u)
        self.vertices.add(v)

    def neighbours(self, v):
        return self.adj[v]

    def is_connected(self):
        """Check if undirected graph is connected — O(V + E)."""
        if not self.vertices:
            return True
        start = next(iter(self.vertices))
        visited = self._bfs_visited(start)
        return visited == self.vertices

    def _bfs_visited(self, start):
        visited = {start}
        queue = deque([start])
        while queue:
            node = queue.popleft()
            for neighbour in self.adj[node]:
                if neighbour not in visited:
                    visited.add(neighbour)
                    queue.append(neighbour)
        return visited

    def has_cycle_undirected(self):
        """Detect cycle in undirected graph using DFS — O(V + E)."""
        visited = set()

        def dfs(v, parent):
            visited.add(v)
            for neighbour in self.adj[v]:
                if neighbour not in visited:
                    if dfs(neighbour, v):
                        return True
                elif neighbour != parent:
                    return True    # visited neighbour that is not parent = cycle
            return False

        for v in self.vertices:
            if v not in visited:
                if dfs(v, None):
                    return True
        return False

    def connected_components(self):
        """Find all connected components — O(V + E)."""
        visited = set()
        components = []
        for v in self.vertices:
            if v not in visited:
                component = self._bfs_visited(v)
                visited |= component
                components.append(component)
        return components


class DirectedGraph:
    """Directed graph with cycle detection via DFS colour marking."""

    def __init__(self):
        self.adj = defaultdict(list)
        self.vertices = set()

    def add_edge(self, u, v):
        self.adj[u].append(v)
        self.vertices.add(u)
        self.vertices.add(v)

    def has_cycle(self):
        """
        Detect cycle in directed graph — O(V + E).
        Uses three-colour DFS: WHITE (unvisited), GRAY (in stack), BLACK (done).
        """
        WHITE, GRAY, BLACK = 0, 1, 2
        colour = {v: WHITE for v in self.vertices}

        def dfs(v):
            colour[v] = GRAY
            for neighbour in self.adj[v]:
                if colour[neighbour] == GRAY:
                    return True    # back edge — cycle found
                if colour[neighbour] == WHITE:
                    if dfs(neighbour):
                        return True
            colour[v] = BLACK
            return False

        for v in self.vertices:
            if colour[v] == WHITE:
                if dfs(v):
                    return True
        return False

    def topological_sort(self):
        """Kahn's algorithm (BFS-based) for topological order — O(V + E)."""
        in_degree = {v: 0 for v in self.vertices}
        for u in self.vertices:
            for v in self.adj[u]:
                in_degree[v] = in_degree.get(v, 0) + 1

        queue = deque([v for v in self.vertices if in_degree[v] == 0])
        order = []
        while queue:
            v = queue.popleft()
            order.append(v)
            for neighbour in self.adj[v]:
                in_degree[neighbour] -= 1
                if in_degree[neighbour] == 0:
                    queue.append(neighbour)

        if len(order) != len(self.vertices):
            return None   # cycle exists — topological sort not possible
        return order


# Undirected graph demonstration
g = Graph()
for u, v in [(0, 1), (1, 2), (2, 3), (3, 4)]:
    g.add_edge(u, v)
print("Connected:", g.is_connected())         # True
print("Has cycle:", g.has_cycle_undirected())  # False (it's a path graph)

g.add_edge(3, 1)   # creates a cycle: 1-2-3-1
print("Has cycle after adding 3-1:", g.has_cycle_undirected())  # True

# Directed graph — dependency example (course prerequisites)
dag = DirectedGraph()
# course A requires B and C; B requires D
for u, v in [("A", "B"), ("A", "C"), ("B", "D")]:
    dag.add_edge(u, v)
print("DAG has cycle:", dag.has_cycle())             # False
print("Topological order:", dag.topological_sort())  # [A, C, B, D] or similar

dag.add_edge("D", "A")  # circular dependency
print("After circular dep, has cycle:", dag.has_cycle())  # True
```

---

## How It Connects

The concrete memory representation of a graph — adjacency list vs adjacency matrix — determines the space and time complexity of all graph operations. The graph abstraction described here is independent of representation; the choice of representation affects performance for specific access patterns.

[[graph-representations|Graph Representations]]

BFS and DFS are the two fundamental graph traversal algorithms. Every graph algorithm — connectivity, cycle detection, shortest path, topological sort — is built on one or both of these traversals. Understanding graphs as the domain makes BFS and DFS immediately purposeful.

[[bfs|Breadth-First Search]]
[[dfs|Depth-First Search]]

---

## Common Misconceptions

Misconception 1: "Trees and graphs are completely different structures."
Reality: A tree is a special case of a graph — specifically, a connected, undirected, acyclic graph with exactly n−1 edges for n vertices. Every tree is a graph; not every graph is a tree. This relationship is important because graph traversal algorithms (BFS, DFS) apply directly to trees, and tree algorithms can often be generalised to graphs.

Misconception 2: "A directed graph can always be topologically sorted."
Reality: Topological sort is only possible on directed acyclic graphs (DAGs). A directed graph with a cycle cannot be topologically ordered because a cycle means there is no vertex that has no dependencies. Kahn's algorithm detects this: if the sorted output does not include all vertices, a cycle exists.

Misconception 3: "Disconnected graphs are uncommon or degenerate cases."
Reality: Many real-world graphs are naturally disconnected. A social network graph is disconnected if there are people who share no mutual acquaintances. A dependency graph becomes disconnected when modules have no common dependencies. Connected components analysis is a standard and frequently used algorithm, not a correction for broken data.

---

## Why It Matters in Practice

Graphs model an extraordinarily wide range of problems. Social network analysis, logistics routing, web crawling, computer network routing, compiler dependency analysis, database query planning, game state space search, fraud detection in financial networks, and recommendation engines all reduce to graph problems. Recognising that a problem has graph structure — and then selecting the appropriate algorithm (BFS for shortest path, DFS for connectivity, Dijkstra for weighted shortest path, topological sort for ordering) — is one of the highest-leverage skills in algorithm design.

In day-to-day Python development, graphs appear in task dependency systems (like build tools or DAG-based workflow engines), in ORM relationship traversal, and in any system where you model "X connects to Y." The `networkx` library provides a comprehensive Python graph toolkit for production use; for algorithm interviews, the standard approach is implementing adjacency lists directly with dicts.

---

## Interview Angle

Common question forms:
- "Find if there is a path between two nodes."
- "Count the number of connected components."
- "Detect a cycle in a directed graph."
- "Find the shortest path in an unweighted graph."
- "Determine if a given set of course prerequisites is satisfiable (i.e., no circular dependency)."

Answer frame:
For path existence, describe BFS or DFS with a visited set. For connected components, describe running BFS/DFS from each unvisited vertex and counting runs. For directed cycle detection, name the three-colour DFS (WHITE/GRAY/BLACK) and explain why GRAY→GRAY is a cycle (you are visiting a node that is already on the current recursion path). For the course schedule problem, identify it as topological sort on a DAG with cycle detection.

---

## Related Notes

- [[graph-representations|Graph Representations]]
- [[bfs|Breadth-First Search]]
- [[dfs|Depth-First Search]]
- [[topological-sort|Topological Sort]]
