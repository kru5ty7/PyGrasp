---
title: 44 - Bellman-Ford Algorithm
description: A shortest-path algorithm that handles negative edge weights and detects negative cycles by relaxing all edges V-1 times.
tags: [dsa, layer-10, bellman-ford, shortest-path, negative-weights]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Bellman-Ford Algorithm

> Bellman-Ford finds shortest paths from a source vertex even when edges have negative weights, and it detects negative-weight cycles — developers must know it as the correct algorithm for graphs where Dijkstra's greedy assumption breaks down.

---

## Quick Reference

**Core idea:**
- Relax all edges V-1 times — after k relaxations, shortest paths using at most k edges are correct
- A path in a graph with V vertices uses at most V-1 edges, so V-1 rounds of relaxation suffices
- After V-1 rounds, run one more pass: if any edge can still be relaxed, a negative cycle exists
- O(V × E) time — slower than Dijkstra's O((V + E) log V) but handles the general case
- Use when the graph may contain negative edge weights
- Real-world applications: currency arbitrage detection, distance-vector routing protocols (RIP)

**Tricky points:**
- Initialise all distances to infinity except the source (distance 0) — same as Dijkstra
- Edge relaxation: if `dist[u] + weight < dist[v]`, update `dist[v]`
- The algorithm must iterate over all edges V-1 times — not just once per edge
- Negative cycle detection requires a V-th round of relaxation — not a check during the V-1 rounds
- If a vertex's distance is still infinity after V-1 rounds, it is unreachable from the source (not a negative cycle)

---

## Complexity

| Case | Time | Space |
|---|---|---|
| General case | O(V × E) | O(V) |
| Dense graph (E = V²) | O(V³) | O(V) |
| Sparse graph (E = V) | O(V²) | O(V) |

---

## What It Is

Imagine you are estimating the total cost of a multi-step supply chain. Each step has a cost, but some steps offer discounts — represented as negative weights — because a supplier subsidises part of the route. You want the cheapest total cost from the factory to the customer. The catch is that if a cycle of steps offers a net negative cost (a "money loop"), you could travel around it indefinitely, reducing the cost to negative infinity. Bellman-Ford's job is to find the cheapest routes and also to detect if any such money loops exist.

The algorithm works through a process of gradual refinement. In the first round, it finds all shortest paths that use exactly one edge. In the second round, it finds all shortest paths that use at most two edges. After k rounds, it has found all shortest paths that use at most k edges. Since any simple (cycle-free) path in a graph with V vertices can have at most V-1 edges, V-1 rounds of this refinement process are sufficient to discover all shortest simple paths. This is fundamentally different from Dijkstra's approach, which greedily finalises one vertex per step using the assumption that no future edge can reduce an already-finalised distance.

The negative cycle detection follows naturally from this framework. After V-1 rounds, every shortest simple path has been found. If there is any edge (u, v) with weight w such that `dist[u] + w < dist[v]`, it means there is still a path to v through u that is shorter than the best known path using V-1 edges — which is only possible if that path uses V or more edges, implying a cycle. And since the path is shorter with more edges, the cycle must have net negative weight. This single additional pass reveals the existence of a negative cycle.

---

## How It Actually Works

The implementation iterates over all edges exactly V-1 times in the outer loop, and once more for cycle detection. The edge list representation is the most natural for Bellman-Ford, because the algorithm scans all edges uniformly rather than exploring vertex by vertex. This edge-centric approach is why Bellman-Ford is unaffected by negative weights: it does not commit to a vertex being finalised early, so it continues refining distances even after a vertex has been updated.

Tracking predecessors works the same as in Dijkstra: when `dist[v]` is updated, set `prev[v] = u`. However, if a negative cycle is detected, path reconstruction through the cycle should be skipped or flagged, because no finite shortest path exists for vertices reachable through a negative cycle.

```python
from typing import Dict, List, Optional, Tuple


Edge = Tuple[int, int, float]   # (from, to, weight)


def bellman_ford(
    vertices: List[int],
    edges: List[Edge],
    source: int
) -> Tuple[Dict[int, float], Dict[int, Optional[int]], bool]:
    """
    Returns:
        dist:     shortest distances from source (inf if unreachable)
        prev:     predecessor map for path reconstruction
        has_neg_cycle: True if a negative cycle is reachable from source
    """
    # Initialisation
    dist: Dict[int, float] = {v: float('inf') for v in vertices}
    prev: Dict[int, Optional[int]] = {v: None for v in vertices}
    dist[source] = 0

    V = len(vertices)

    # V-1 relaxation rounds
    for _ in range(V - 1):
        updated = False
        for u, v, w in edges:
            if dist[u] != float('inf') and dist[u] + w < dist[v]:
                dist[v] = dist[u] + w
                prev[v] = u
                updated = True
        if not updated:
            break  # early exit: no update means convergence reached

    # V-th round: negative cycle detection
    has_neg_cycle = False
    for u, v, w in edges:
        if dist[u] != float('inf') and dist[u] + w < dist[v]:
            has_neg_cycle = True
            break

    return dist, prev, has_neg_cycle


def reconstruct_path(
    prev: Dict[int, Optional[int]],
    source: int,
    target: int
) -> List[int]:
    path = []
    current: Optional[int] = target
    while current is not None:
        path.append(current)
        current = prev.get(current)
        if current == source:
            path.append(source)
            break
    path.reverse()
    return path if path[0] == source else []


# --- Example ---
vertices = [0, 1, 2, 3, 4]
edges: List[Edge] = [
    (0, 1, -1),
    (0, 2,  4),
    (1, 2,  3),
    (1, 3,  2),
    (1, 4,  2),
    (3, 2,  5),
    (3, 1,  1),   # this creates a cycle, but not a negative one
    (4, 3, -3),
]

dist, prev, neg_cycle = bellman_ford(vertices, edges, source=0)
print(dist)          # {0:0, 1:-1, 2:2, 3:-2, 4:1}
print(neg_cycle)     # False

# --- Negative cycle example ---
neg_edges: List[Edge] = [
    (0, 1,  1),
    (1, 2, -3),
    (2, 0,  1),   # cycle 0->1->2->0 has total weight -1 (negative!)
]
_, _, has_cycle = bellman_ford([0, 1, 2], neg_edges, source=0)
print(has_cycle)     # True


# --- Currency arbitrage detection ---
# Represent exchange rates as edges with weight = -log(rate)
# A negative cycle means there is a profitable arbitrage loop
import math

def find_arbitrage(currencies: list, rates: list) -> bool:
    """
    currencies: list of currency names (vertices)
    rates: list of (i, j, rate) meaning 1 unit of i buys rate units of j
    """
    n = len(currencies)
    log_edges = [(i, j, -math.log(rate)) for i, j, rate in rates]
    # Add a virtual source with zero-weight edges to all currencies
    virtual_source = n
    all_vertices = list(range(n + 1))
    source_edges = [(virtual_source, v, 0) for v in range(n)]
    all_edges = log_edges + source_edges

    _, _, neg_cycle = bellman_ford(all_vertices, all_edges, virtual_source)
    return neg_cycle
```

---

## Visualizer

<iframe src="/static/visualizers/bellman-ford.html" style="width:100%;height:460px;border:none;border-radius:8px;" title="Bellman-Ford Algorithm Visualizer"></iframe>

---

## How It Connects

Bellman-Ford and Dijkstra solve the same problem (single-source shortest paths) but under different constraints. Dijkstra is faster but requires non-negative edge weights; Bellman-Ford is slower but handles negative weights and detects negative cycles. The correct choice depends entirely on whether negative weights are possible in the input graph.

Both algorithms compute single-source shortest paths, which means they give the shortest path from one source to all other vertices. The all-pairs shortest paths problem — shortest path between every pair of vertices — is solved by Floyd-Warshall, which extends the Bellman-Ford relaxation idea across all possible intermediate vertices.

[[dijkstra|Dijkstra's Algorithm]]
[[graphs|Graphs]]
[[graph-representations|Graph Representations]]

---

## Common Misconceptions

Misconception 1: Bellman-Ford detects all negative cycles in a graph.
Reality: Bellman-Ford run from a single source only detects negative cycles reachable from that source. If there are negative cycles in disconnected parts of the graph, they will not be detected. To detect all negative cycles, run Bellman-Ford from every vertex, or use Floyd-Warshall (which can detect negative cycles on the diagonal of the distance matrix).

Misconception 2: The algorithm must complete all V-1 rounds before results are valid.
Reality: The algorithm can terminate early if a complete round produces no updates — the distances have converged and further rounds would not change anything. This optimisation is valid and can significantly reduce running time on graphs that converge quickly. Many textbook presentations omit this optimisation, but it is standard in production implementations.

---

## Why It Matters in Practice

The distance-vector routing protocol RIP (Routing Information Protocol), used in older network routers, is based directly on Bellman-Ford: each router maintains a distance estimate to every other router, and periodically exchanges estimates with neighbours, triggering updates. The "count to infinity" problem in RIP (where routers can get stuck in a routing loop after a link failure) is a consequence of Bellman-Ford's iterative relaxation applied in a distributed, asynchronous setting.

Currency arbitrage detection is a direct application: model currencies as vertices and exchange rates as directed edges with weight `-log(rate)`. A negative cycle in this graph represents a sequence of currency exchanges that yields a net profit. Detecting this cycle with the Vth-round relaxation check identifies arbitrage opportunities — a use case that has been employed in both academic research and financial systems.

---

## Interview Angle

Common question forms:
- "Find the shortest path in a graph that may have negative edge weights."
- "Detect a negative cycle in a weighted directed graph."
- "Given exchange rates, determine if currency arbitrage is possible."

Answer frame:
State that Dijkstra cannot be used because of negative weights. Initialise dist array (source = 0, others = infinity). Iterate over all edges V-1 times, relaxing each edge. Run one more pass to detect negative cycles. State O(V × E) time and O(V) space. Compare to Dijkstra and explain when each is appropriate.

---

## Related Notes

- [[dijkstra|Dijkstra's Algorithm]]
- [[graphs|Graphs]]
- [[graph-representations|Graph Representations]]
- [[greedy-algorithms|Greedy Algorithms]]
- [[dynamic-programming|Dynamic Programming]]
