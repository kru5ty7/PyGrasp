---
title: 16 - Graph Representations
description: Graph representations determine how a graph is stored in memory, with adjacency lists and adjacency matrices offering fundamentally different performance trade-offs.
tags: [dsa, layer-10, graph, adjacency-list, adjacency-matrix]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Graph Representations

> Choosing between an adjacency list and an adjacency matrix is a concrete engineering decision that affects space usage, edge-check speed, and the practical performance of every graph algorithm you run.

---

## Quick Reference

**Core idea:**
- Adjacency matrix: V×V 2D array where `matrix[u][v] = 1` (or weight) if edge (u, v) exists
- Adjacency list: each vertex maps to the list (or set) of its neighbours
- Adjacency list is O(V + E) space — efficient for sparse graphs (most real-world graphs)
- Adjacency matrix is O(V²) space — efficient for dense graphs or when O(1) edge queries matter
- Edge list: a flat list of (u, v) pairs — simple storage, O(E) space, O(E) edge check

**Tricky points:**
- "Sparse" means E << V² — social networks, road maps, dependency graphs are all sparse
- Adjacency matrix edge check is O(1) but matrix iteration over all neighbours is O(V) — even if the vertex has only 2 neighbours
- Adjacency list neighbour iteration is O(degree(v)) — proportional to actual edges, not total vertices
- For unweighted graphs, a set of neighbours (instead of a list) gives O(1) edge check with O(V + E) space
- Dict of sets is the typical Python representation; NumPy matrix is used for dense numeric graphs

---

## Complexity

| Operation | Adjacency List | Adjacency Matrix |
|---|---|---|
| Space | O(V + E) | O(V²) |
| Add edge | O(1) | O(1) |
| Remove edge | O(degree) | O(1) |
| Check edge (u, v) | O(degree(u)) (list) / O(1) (set) | O(1) |
| Iterate all neighbours of v | O(degree(v)) | O(V) |
| Iterate all edges | O(V + E) | O(V²) |

Space complexity: O(V + E) for adjacency list, O(V²) for adjacency matrix.

---

## What It Is

Imagine mapping which cities are directly connected by flights. One way is a grid: list every city as a row header and every city as a column header. Put a 1 at the intersection if a direct flight exists, 0 if not. Any question of the form "does a direct flight exist between Chicago and Denver?" is answered in O(1) — go to the Chicago row, Denver column, read the cell. But this grid has 400 cells for 20 cities, 10,000 cells for 100 cities, and a million cells for 1000 cities. If only 5% of city pairs have direct flights, 95% of the grid is zeros — wasted space.

The alternative is a contact book. Each city has its own page listing only the cities with direct flights. Chicago's page might list Denver, Houston, and New York — just the three. To check if Chicago flies to Denver, you open Chicago's page and scan it. To check if Chicago flies to Boise, you scan the page and don't find it. The scan cost is proportional to the number of direct connections from Chicago, not the total number of cities. This is the adjacency list: each vertex stores only its actual neighbours.

The real-world graph that matters most in software engineering — the web — has roughly 1.7 billion websites and roughly 80 billion links. A full adjacency matrix would require approximately (1.7 × 10⁹)² bits — an impossibly large amount of storage. The web's link graph is extremely sparse: the average page links to about 50 others. An adjacency list for the web requires storage proportional to 80 billion edges — enormous, but not astronomical. This is why every production graph system — Google's PageRank, Facebook's social graph, road navigation systems — uses an adjacency list or its distributed equivalent.

---

## How It Actually Works

In Python, the adjacency list is most naturally represented as a `dict` mapping each vertex to either a `list` or a `set` of its neighbours. Using a `set` gives O(1) edge checking (at the cost of slightly more memory and no ordering of neighbours); using a `list` gives O(degree) edge checking but preserves insertion order. For most algorithm problems, a `dict` of `list` is standard; for problems requiring frequent edge-existence queries, a `dict` of `set` is better.

The adjacency matrix in Python is represented as a 2D list or a NumPy array. Vertex labels must be mapped to integer indices (using a separate dict) unless the vertices are already integers starting from 0. NumPy matrices are efficient for dense numerical graphs where vectorised operations on the entire matrix are useful (for example, multiplying the adjacency matrix by itself counts paths of length 2).

```python
from collections import defaultdict

# ---- Adjacency list (dict of lists) ----
def build_adjacency_list(edges, directed=False):
    adj = defaultdict(list)
    vertices = set()
    for u, v in edges:
        adj[u].append(v)
        vertices.add(u)
        vertices.add(v)
        if not directed:
            adj[v].append(u)
    # Ensure vertices with no outgoing edges are included
    for v in vertices:
        if v not in adj:
            adj[v] = []
    return dict(adj)

# ---- Adjacency list (dict of sets) for O(1) edge checks ----
def build_adjacency_set(edges, directed=False):
    adj = defaultdict(set)
    for u, v in edges:
        adj[u].add(v)
        if not directed:
            adj[v].add(u)
    return dict(adj)

# ---- Adjacency matrix ----
def build_adjacency_matrix(num_vertices, edges, directed=False, weighted=False):
    INF = float('inf')
    matrix = [[0 if not weighted else INF] * num_vertices
              for _ in range(num_vertices)]
    for _ in range(num_vertices):
        matrix[_][_] = 0   # no self-loop cost

    for edge in edges:
        if weighted:
            u, v, w = edge
            matrix[u][v] = w
            if not directed:
                matrix[v][u] = w
        else:
            u, v = edge
            matrix[u][v] = 1
            if not directed:
                matrix[v][u] = 1
    return matrix

# ---- Demonstration ----
edges = [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)]

adj_list = build_adjacency_list(edges, directed=False)
print("Adjacency list:")
for v in sorted(adj_list):
    print(f"  {v}: {sorted(adj_list[v])}")
# 0: [1, 2]
# 1: [0, 3]
# 2: [0, 3]
# 3: [1, 2, 4]
# 4: [3]

adj_set = build_adjacency_set(edges, directed=False)
print("Edge (0,1) exists:", 1 in adj_set[0])   # O(1)
print("Edge (0,3) exists:", 3 in adj_set[0])   # O(1)

matrix = build_adjacency_matrix(5, edges, directed=False)
print("\nAdjacency matrix:")
for row in matrix:
    print(" ", row)
print("Edge (0,1):", matrix[0][1])   # 1 — O(1)
print("Edge (0,3):", matrix[0][3])   # 0 — O(1)


# ---- Weighted directed graph (adjacency list) ----
weighted_edges = [(0, 1, 4), (0, 2, 1), (2, 1, 2), (1, 3, 1), (2, 3, 5)]
weighted_adj = defaultdict(list)
for u, v, w in weighted_edges:
    weighted_adj[u].append((v, w))   # (neighbour, weight) tuples

print("\nWeighted adjacency list:")
for v in sorted(weighted_adj):
    print(f"  {v}: {weighted_adj[v]}")


# ---- Space comparison for sparse vs dense graphs ----
V = 1000

# Sparse: E = V * 5 (each vertex has ~5 edges)
E_sparse = V * 5
list_space_sparse = V + E_sparse        # O(V + E)
matrix_space = V * V                    # O(V^2)

# Dense: E = V * V * 0.8 (80% of possible edges)
E_dense = int(V * V * 0.8)
list_space_dense = V + E_dense

print(f"\nFor V={V}, sparse (E={E_sparse}):")
print(f"  Adj list entries: {list_space_sparse:,}")
print(f"  Adj matrix cells: {matrix_space:,}")
print(f"  Matrix waste: {(matrix_space - list_space_sparse) / matrix_space:.1%}")

print(f"\nFor V={V}, dense (E={E_dense:,}):")
print(f"  Adj list entries: {list_space_dense:,}")
print(f"  Adj matrix cells: {matrix_space:,}")
print(f"  Matrix overhead: {(matrix_space - list_space_dense) / matrix_space:.1%}")
```

---

## How It Connects

The graph conceptual model — vertices, edges, directed vs undirected, weighted vs unweighted — is established in the graphs note. The representation choice here directly determines the complexity of every algorithm that operates on the graph, from BFS and DFS to Dijkstra and topological sort.

[[graphs|Graphs]]

Dijkstra's algorithm, which finds shortest paths in weighted graphs, iterates over all neighbours of each processed vertex. With an adjacency list, this iteration is O(degree(v)) — proportional to actual edges. With an adjacency matrix, it is O(V) — proportional to total vertices. For sparse graphs, this changes the overall complexity of Dijkstra's from O(V² log V) to O((V + E) log V).

[[dijkstra|Dijkstra's Algorithm]]

---

## Common Misconceptions

Misconception 1: "Adjacency lists are always better than adjacency matrices."
Reality: Adjacency matrices are better when the graph is dense (most pairs of vertices are connected), when O(1) edge existence checking is critical, or when the algorithm involves matrix operations (like Floyd-Warshall all-pairs shortest path, which requires iterating over matrix[u][v] for all u, v). The rule is: use adjacency list for sparse graphs, adjacency matrix for dense graphs or when O(1) edge queries dominate.

Misconception 2: "The adjacency list representation wastes space by storing both directions of an undirected edge."
Reality: For an undirected edge (u, v), storing v in u's list and u in v's list is the correct implementation. This doubles the list entries for undirected edges, but the total space is still O(V + E) — not O(V + 2E), because in Big O notation the constant factor is dropped. The alternative — storing each edge once and searching from both endpoints — complicates every algorithm that iterates a vertex's neighbours.

Misconception 3: "A dict of lists in Python is much slower than a proper adjacency list in another language."
Reality: Python's dict lookup is O(1) average, and list iteration is cache-efficient. For algorithm work and most production graph processing in Python, the dict-of-lists representation is fast enough. For very large production graphs (billions of edges), specialised graph databases or libraries like `networkx`, `igraph`, or `graph-tool` provide optimised representations, but the conceptual model is the same.

---

## Why It Matters in Practice

Every time you write a graph traversal in production code, you are implicitly choosing a representation. Using a nested dict for the adjacency list is the Python standard, but knowing the trade-offs allows informed decisions: if edge existence is queried frequently (as in cycle detection or some connectivity algorithms), switching from dict-of-list to dict-of-set reduces query cost from O(degree) to O(1). For dense graphs — such as social media connections among a small, closed community — a matrix may actually be more efficient.

Build systems, dependency resolvers, and workflow engines all represent their task graphs as adjacency lists. The choice of list vs set vs ordered list affects whether duplicate edges are prevented, whether edge order matters, and how expensive neighbor lookup is. Understanding the representation at this level is what separates a correct graph implementation from an efficient one.

---

## Interview Angle

Common question forms:
- "How would you represent a graph for BFS?"
- "When would you use an adjacency matrix over an adjacency list?"
- "What is the space complexity of your graph representation?"
- "Implement a weighted directed graph."

Answer frame:
Always start by stating which representation you are using and why — "I'll use a dict of lists because the graph is sparse and we need O(V + E) space rather than O(V²)." Then explain the neighbour-iteration cost: O(degree) for adjacency list, O(V) for matrix. For the matrix question, give the dense/O(1)-edge-check use case. For weighted graphs, describe storing `(neighbour, weight)` tuples in the adjacency list.

---

## Related Notes

- [[graphs|Graphs]]
- [[bfs|Breadth-First Search]]
- [[dfs|Depth-First Search]]
- [[dijkstra|Dijkstra's Algorithm]]
