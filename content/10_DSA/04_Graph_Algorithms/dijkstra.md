---
title: 43 - Dijkstra's Algorithm
description: A greedy shortest-path algorithm that finds the minimum-weight path from a source to all other vertices in a graph with non-negative edge weights.
tags: [dsa, layer-10, dijkstra, shortest-path, weighted-graph]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Dijkstra's Algorithm

> Dijkstra's algorithm finds the shortest path from a source vertex to all others in a weighted graph with non-negative edges — every developer working with networks, maps, or routing must know it because it is the foundation of GPS navigation and network routing protocols.

---

## Quick Reference

**Core idea:**
- Greedy algorithm: always process the unvisited vertex with the smallest known distance
- Uses a min-heap (priority queue) to efficiently select the next vertex
- Maintains a `dist` array where `dist[v]` = shortest known distance from source to v
- Initialise: `dist[source] = 0`, all others `= infinity`
- When a shorter path to a neighbour is found, push `(new_dist, neighbour)` to the heap
- Fails with negative edge weights — use Bellman-Ford instead

**Tricky points:**
- A vertex may be pushed to the heap multiple times with different distances — skip stale entries when popped
- The visited set (or distance check) prevents re-processing a vertex after its shortest path is finalised
- Extracting the actual path requires tracking predecessors, not just distances
- Dense graphs (E close to V²) may benefit from a different heap implementation, but Python's `heapq` (binary heap) is the standard choice
- The algorithm terminates early if you only need the shortest path to a specific target — stop when that vertex is popped

---

## Complexity

| Case | Time | Space |
|---|---|---|
| Binary heap implementation | O((V + E) log V) | O(V + E) |
| Dense graph (V² edges) with binary heap | O(V² log V) | O(V²) |
| Fibonacci heap (theoretical) | O(E + V log V) | O(V + E) |

---

## What It Is

Imagine exploring a city where each road has a different travel time. You start at your hotel and want to know the fastest route to every other landmark. A sensible strategy is to always explore the nearest unvisited landmark next. Once you have reached a landmark and recorded its shortest travel time, that record is final: any other route to that landmark would have to pass through an unvisited intermediate point, which by definition has an equal or greater travel time, meaning the path through it cannot be shorter. Each confirmed landmark acts as a relay point for discovering new routes to its neighbours.

This is Dijkstra's algorithm. The key insight that makes it correct — and that also makes it fail with negative edge weights — is the greedy argument above. When you extract the vertex with the smallest known distance from the priority queue, that distance is guaranteed to be final. No future discovery can improve it, because all future paths must pass through at least one unprocessed vertex, and all unprocessed vertices have equal or greater distances (since we always process the minimum). With negative edge weights, this guarantee breaks: a longer-looking path might later be reduced by a negative edge, invalidating the "once finalised, always finalised" property.

The priority queue is the data structure that makes the algorithm efficient. Without it, finding the minimum-distance unvisited vertex at each step would require scanning all vertices — O(V) per step, O(V²) total. A min-heap extracts the minimum in O(log n) time, reducing the total cost to O((V + E) log V). Python's `heapq` module implements a min-heap on a list, and tuples are compared lexicographically — so pushing `(distance, vertex)` tuples automatically gives minimum-distance extraction.

---

## How It Actually Works

The Python implementation pushes `(distance, vertex)` tuples onto the heap. When a vertex is popped, the popped distance is compared against the current best known distance. If the popped distance is greater than the recorded best (a stale entry from an earlier, now-superseded push), the vertex is skipped. This lazy deletion approach avoids the need for a decrease-key operation, which Python's `heapq` does not support efficiently.

The predecessor map enables path reconstruction. Each time a vertex's best distance is updated, record which vertex caused the update. Once the algorithm terminates, walk backward from the target through the predecessor map to reconstruct the full path.

```python
import heapq
from collections import defaultdict
from typing import Dict, List, Optional, Tuple


Graph = Dict[int, List[Tuple[int, int]]]  # vertex -> [(neighbour, weight)]


def dijkstra(
    graph: Graph,
    source: int
) -> Tuple[Dict[int, float], Dict[int, Optional[int]]]:
    """
    Returns:
        dist: shortest distance from source to every reachable vertex
        prev: predecessor map for path reconstruction
    """
    dist: Dict[int, float] = defaultdict(lambda: float('inf'))
    prev: Dict[int, Optional[int]] = {}
    dist[source] = 0

    # Min-heap: (distance, vertex)
    heap: List[Tuple[float, int]] = [(0, source)]

    while heap:
        d, u = heapq.heappop(heap)

        # Skip stale entries — a shorter path was already found
        if d > dist[u]:
            continue

        for v, weight in graph.get(u, []):
            new_dist = dist[u] + weight
            if new_dist < dist[v]:
                dist[v] = new_dist
                prev[v] = u
                heapq.heappush(heap, (new_dist, v))

    return dict(dist), prev


def reconstruct_path(
    prev: Dict[int, Optional[int]],
    source: int,
    target: int
) -> List[int]:
    """Walk the predecessor map backward from target to source."""
    path = []
    current = target
    while current != source:
        if current not in prev:
            return []  # no path exists
        path.append(current)
        current = prev[current]
    path.append(source)
    path.reverse()
    return path


# --- Example: weighted directed graph ---
# 0 -> 1 (weight 4), 0 -> 2 (weight 1)
# 2 -> 1 (weight 2), 1 -> 3 (weight 1)
g: Graph = {
    0: [(1, 4), (2, 1)],
    2: [(1, 2)],
    1: [(3, 1)],
    3: []
}

distances, predecessors = dijkstra(g, source=0)
print(distances)    # {0: 0, 1: 3, 2: 1, 3: 4}
print(reconstruct_path(predecessors, 0, 3))  # [0, 2, 1, 3]

# Early termination: stop once target is finalised
def dijkstra_to_target(
    graph: Graph,
    source: int,
    target: int
) -> float:
    dist: Dict[int, float] = defaultdict(lambda: float('inf'))
    dist[source] = 0
    heap = [(0, source)]

    while heap:
        d, u = heapq.heappop(heap)
        if u == target:
            return d   # target finalised — stop
        if d > dist[u]:
            continue
        for v, w in graph.get(u, []):
            nd = dist[u] + w
            if nd < dist[v]:
                dist[v] = nd
                heapq.heappush(heap, (nd, v))

    return float('inf')
```

---

## How It Connects

Dijkstra's algorithm is a greedy algorithm: at each step, it makes the locally optimal choice (process the nearest vertex) and that choice turns out to be globally correct under the assumption of non-negative weights. Understanding why the greedy choice is correct here, and why it fails with negative weights, is the bridge to understanding when Bellman-Ford is required instead.

The algorithm also uses a heap as its core data structure. Performance is directly tied to the heap operations: each vertex is extracted once and each edge may trigger a push — giving the (V + E) log V bound. Recognising the min-heap pattern (always process the minimum) is the key to identifying Dijkstra-like structure in novel problems.

[[graphs|Graphs]]
[[graph-representations|Graph Representations]]
[[heaps|Heaps]]
[[bellman-ford|Bellman-Ford Algorithm]]
[[greedy-algorithms|Greedy Algorithms]]

---

## Common Misconceptions

Misconception 1: Dijkstra's algorithm fails on graphs with zero-weight edges.
Reality: Dijkstra's algorithm requires non-negative edge weights, not strictly positive ones. Zero-weight edges are handled correctly — they simply do not increase the distance to a neighbour. The algorithm only breaks when edge weights are negative, because a negative edge can make a longer-looking path actually shorter, violating the finalisation guarantee.

Misconception 2: To find the shortest path between two specific vertices, Dijkstra must run to completion.
Reality: Dijkstra can terminate as soon as the target vertex is popped from the heap. At that moment, its distance is finalised — no future extraction can improve it. For point-to-point queries on large graphs, this early termination can save significant computation. Real-world GPS systems use bidirectional Dijkstra and A* (which adds a heuristic to guide the search) for further efficiency.

---

## Why It Matters in Practice

Dijkstra's algorithm is the basis for OSPF (Open Shortest Path First), the routing protocol used inside most internet backbone routers to determine how to forward packets. GPS navigation systems run variants of Dijkstra on road network graphs to compute fastest routes. Social networks use shortest-path algorithms to measure closeness between users. Any system that needs to find optimal paths through a weighted network is implementing — directly or in a modified form — the ideas behind Dijkstra's algorithm.

For interviews, Dijkstra problems are common at medium and hard difficulty and often appear disguised: "minimum cost to reach a destination," "cheapest flight with at most k stops," or "minimum time to spread information through a network." Recognising these as shortest-path problems and applying Dijkstra — with the heap, the distance array, and the stale-entry check — is the expected solution approach.

---

## Interview Angle

Common question forms:
- "Find the shortest path from source to all other nodes in a weighted graph."
- "Find the cheapest flight from city A to city B."
- "What is the minimum time for a signal to reach all nodes in a network?"

Answer frame:
Identify the problem as single-source shortest path with non-negative weights. Initialise dist array with infinity, source with zero. Use a min-heap of (distance, vertex) tuples. On each extraction, skip stale entries. For each neighbour, relax the edge. State O((V + E) log V) time. If negative weights are possible, flag that Bellman-Ford is required instead.

---

## Related Notes

- [[graphs|Graphs]]
- [[graph-representations|Graph Representations]]
- [[heaps|Heaps]]
- [[bellman-ford|Bellman-Ford Algorithm]]
- [[greedy-algorithms|Greedy Algorithms]]
- [[bfs|BFS]]
