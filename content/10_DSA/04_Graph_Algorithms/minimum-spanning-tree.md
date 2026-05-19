---
title: 46 - Minimum Spanning Tree
description: A spanning tree of a weighted undirected graph that connects all vertices with the minimum possible total edge weight, using exactly V-1 edges and no cycles.
tags: [dsa, layer-10, mst, kruskal, prim]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Minimum Spanning Tree

> A minimum spanning tree connects all vertices of a weighted undirected graph using the cheapest possible edges - developers must understand it because it underlies network infrastructure design, cluster analysis, and approximation algorithms for NP-hard problems.

---

## Quick Reference

**Core idea:**
- A spanning tree is a connected, acyclic subgraph containing all V vertices - it always has exactly V-1 edges
- An MST is the spanning tree with the smallest total edge weight
- Kruskal's: sort all edges by weight, greedily add edges that do not form a cycle (Union-Find detects cycles)
- Prim's: start from any vertex, greedily add the cheapest edge connecting the MST to a new vertex (min-heap)
- Both are greedy algorithms; both produce the same total weight (though possibly different trees if ties exist)
- Applications: network cabling, cluster analysis, approximation for TSP

**Tricky points:**
- MST is for undirected graphs only - directed graph minimum spanning arborescences require Edmonds' algorithm
- A graph may have multiple MSTs if edge weights are not all distinct
- Kruskal's is better for sparse graphs (fewer edges to sort); Prim's with a heap is better for dense graphs
- Union-Find with path compression and union by rank makes Kruskal's O(E log E) - the sort dominates
- Prim's without a heap is O(V²) - acceptable for dense graphs but worse than heap-based for sparse ones

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Kruskal's (Union-Find with rank + path compression) | O(E log E) | O(V) |
| Prim's (binary heap) | O(E log V) | O(V + E) |
| Prim's (adjacency matrix, no heap) | O(V²) | O(V) |

---

## What It Is

Imagine you are a city planner tasked with connecting ten remote villages with roads, given a fixed budget. You have a list of every possible road between any two villages with a construction cost for each. Your goal is to ensure that any village can reach any other village - possibly via intermediate villages - while spending the minimum total amount on construction. You do not need a direct road between every pair; you just need the network to be connected. The minimum spanning tree is the cheapest set of roads that achieves this connectivity.

Two greedy strategies can solve this problem. The first, Kruskal's approach, looks at all possible roads sorted from cheapest to most expensive. It greedily builds the road network by adding each road in order, as long as the road connects two villages that are not already connected to each other (i.e., it does not create a redundant loop in the network). The second, Prim's approach, grows the network from a single starting village outward. At each step, it identifies the cheapest road that adds exactly one new unconnected village to the existing connected network, and adds that village.

Both strategies work because of the cut property of minimum spanning trees. A cut is any partition of the graph's vertices into two non-empty sets. For any cut, the minimum-weight edge crossing that cut - the cheapest road connecting the two groups of villages - must belong to some MST. This property is what justifies the greedy choices in both algorithms: Kruskal's adds the cheapest available edge that crosses some cut (connecting two previously disconnected components); Prim's adds the cheapest edge crossing the cut between the current MST component and all remaining vertices.

---

## How It Actually Works

Kruskal's algorithm requires a Union-Find (Disjoint Set Union) data structure to efficiently detect whether two vertices are already in the same connected component. Union-Find with path compression and union by rank performs near-O(1) per operation (technically O(α(V)) where α is the inverse Ackermann function, effectively a constant for all practical inputs). Kruskal's sorts all edges once (O(E log E)) and then processes each edge in O(α(V)) - the sort dominates.

Prim's algorithm uses a min-heap to track the cheapest edge connecting each unincluded vertex to the current MST. When a vertex is added to the MST, all its edges to unincluded neighbours are pushed onto the heap. The algorithm pops the minimum and adds the corresponding vertex if it has not been included yet. This is structurally identical to Dijkstra's algorithm, with the key difference that Prim's heap key is the edge weight to the MST (not the total path length from the source).

```python
import heapq
from typing import Dict, List, Tuple


# --- Union-Find for Kruskal's ---
class UnionFind:
    def __init__(self, n: int):
        self.parent = list(range(n))
        self.rank = [0] * n

    def find(self, x: int) -> int:
        if self.parent[x] != x:
            self.parent[x] = self.find(self.parent[x])  # path compression
        return self.parent[x]

    def union(self, x: int, y: int) -> bool:
        """Union x and y. Returns False if already in same component."""
        rx, ry = self.find(x), self.find(y)
        if rx == ry:
            return False   # same component - adding this edge creates a cycle
        if self.rank[rx] < self.rank[ry]:
            rx, ry = ry, rx
        self.parent[ry] = rx
        if self.rank[rx] == self.rank[ry]:
            self.rank[rx] += 1
        return True


# --- Kruskal's Algorithm ---
def kruskal(
    num_vertices: int,
    edges: List[Tuple[float, int, int]]   # (weight, u, v)
) -> Tuple[List[Tuple[float, int, int]], float]:
    """
    Returns:
        mst_edges: list of (weight, u, v) in the MST
        total_weight: sum of MST edge weights
    """
    edges_sorted = sorted(edges)   # sort by weight (first tuple element)
    uf = UnionFind(num_vertices)
    mst_edges = []
    total_weight = 0.0

    for weight, u, v in edges_sorted:
        if uf.union(u, v):     # adds edge only if it does not create a cycle
            mst_edges.append((weight, u, v))
            total_weight += weight
        if len(mst_edges) == num_vertices - 1:
            break   # MST is complete: V-1 edges collected

    return mst_edges, total_weight


# --- Prim's Algorithm ---
Graph = Dict[int, List[Tuple[float, int]]]   # vertex -> [(weight, neighbour)]

def prim(
    graph: Graph,
    start: int,
    num_vertices: int
) -> Tuple[List[Tuple[float, int, int]], float]:
    """
    Returns:
        mst_edges: list of (weight, from, to) in the MST
        total_weight: sum of MST edge weights
    """
    in_mst = set()
    in_mst.add(start)

    # min-heap: (edge_weight, from_vertex, to_vertex)
    heap: List[Tuple[float, int, int]] = []
    for weight, neighbour in graph.get(start, []):
        heapq.heappush(heap, (weight, start, neighbour))

    mst_edges = []
    total_weight = 0.0

    while heap and len(in_mst) < num_vertices:
        weight, u, v = heapq.heappop(heap)
        if v in in_mst:
            continue   # v already in MST - skip
        in_mst.add(v)
        mst_edges.append((weight, u, v))
        total_weight += weight
        for next_weight, next_v in graph.get(v, []):
            if next_v not in in_mst:
                heapq.heappush(heap, (next_weight, v, next_v))

    return mst_edges, total_weight


# --- Demonstration ---
# Graph with 5 vertices
n = 5
kruskal_edges = [
    (2, 0, 1), (3, 0, 3), (6, 1, 2), (8, 1, 3),
    (5, 2, 4), (7, 3, 4), (9, 1, 4), (4, 0, 4),
]
mst, weight = kruskal(n, kruskal_edges)
print(f"Kruskal MST weight: {weight}")   # 14
for e in mst:
    print(e)

prim_graph: Graph = {
    0: [(2, 1), (3, 3), (4, 4)],
    1: [(2, 0), (6, 2), (8, 3), (9, 4)],
    2: [(6, 1), (5, 4)],
    3: [(3, 0), (8, 1), (7, 4)],
    4: [(4, 0), (9, 1), (5, 2), (7, 3)],
}
mst_p, weight_p = prim(prim_graph, start=0, num_vertices=n)
print(f"Prim MST weight: {weight_p}")    # 14
```

---

## Visualizer

<iframe src="/static/visualizers/mst.html" style="width:100%;height:460px;border:none;border-radius:8px;" title="Minimum Spanning Tree Visualizer"></iframe>

---

## How It Connects

Both Kruskal's and Prim's are greedy algorithms justified by the cut property. Kruskal's uses Union-Find as its core data structure - making it also an excellent application of the Disjoint Set data structure. Prim's uses a min-heap and is structurally similar to Dijkstra's algorithm, the key difference being that Prim's tracks the minimum edge cost into the MST rather than the minimum path length from a source.

The Union-Find data structure is independently important and appears in many other contexts: checking graph connectivity, detecting cycles in undirected graphs (Kruskal's uses exactly this), and implementing Kruskal's MST efficiently. Understanding Union-Find as a component of Kruskal's is the standard way to learn both simultaneously.

[[graphs|Graphs]]
[[greedy-algorithms|Greedy Algorithms]]
[[disjoint-sets|Disjoint Sets]]
[[dijkstra|Dijkstra's Algorithm]]

---

## Common Misconceptions

Misconception 1: The MST is unique for any given graph.
Reality: If multiple edges have the same weight, there may be several spanning trees with the same minimum total weight. The MST is unique in total weight (all MSTs of a graph have the same total weight) but not necessarily in which edges are chosen. When all edge weights are distinct, the MST is unique.

Misconception 2: Kruskal's and Prim's algorithms always produce the same MST.
Reality: When edge weights are distinct, both algorithms produce the unique MST, so the same tree results. When ties exist, the two algorithms may select different edges (still with the same total weight), producing different spanning trees that are both minimum spanning trees.

---

## Why It Matters in Practice

Minimum spanning trees model a class of real infrastructure problems: laying fibre-optic cable to connect data centres with minimum total cable length, designing irrigation networks, and routing electrical grids. The MST problem is also a subroutine in approximation algorithms for NP-hard problems - a 2-approximation for the metric travelling salesman problem uses an MST as its foundation. In machine learning, the MST is used in single-linkage hierarchical clustering, where the MST determines how clusters are merged.

For interviews, MST problems are common at hard difficulty and often combine Union-Find and greedy reasoning. Understanding Kruskal's algorithm completely - sort edges, Union-Find to check connectivity, add V-1 non-cycle edges - gives you a clean, implementable solution. Kruskal's also double-duties as a cycle detection algorithm for undirected graphs: if all edges are processed and some union attempts fail (because both vertices are already in the same component), the graph contains cycles.

---

## Interview Angle

Common question forms:
- "Find the minimum cost to connect all cities."
- "Find the minimum number of cables to connect all computers in a network."
- "Remove the maximum number of redundant connections while keeping the graph connected."

Answer frame:
State that the problem is finding a minimum spanning tree. Choose Kruskal's (simpler to implement) or Prim's (better for dense graphs). For Kruskal's: sort edges by weight, implement Union-Find, greedily add edges that do not create cycles, stop when V-1 edges are collected. State O(E log E) time from the sort. Mention that if the graph is not connected, an MST spanning all vertices does not exist - you get a minimum spanning forest instead.

---

## Related Notes

- [[graphs|Graphs]]
- [[disjoint-sets|Disjoint Sets]]
- [[greedy-algorithms|Greedy Algorithms]]
- [[dijkstra|Dijkstra's Algorithm]]
- [[cycle-detection|Cycle Detection]]
