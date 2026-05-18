---
title: 17 - Disjoint Sets (Union-Find)
description: Union-Find tracks which elements belong to which group, supporting near-O(1) find and union operations through path compression and union by rank.
tags: [dsa, layer-10, union-find, disjoint-set]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Disjoint Sets (Union-Find)

> Union-Find answers one of the most practical questions in graph theory — "are these two elements in the same group?" — in near-constant time, making it the engine behind Kruskal's MST algorithm and undirected cycle detection.

---

## Quick Reference

**Core idea:**
- Maintains a collection of non-overlapping (disjoint) sets with two operations: `find` (which set does element x belong to?) and `union` (merge the sets containing x and y)
- Path compression: during `find`, make every visited node point directly to the root — flattens the tree for future queries
- Union by rank (or size): always attach the smaller tree under the larger tree — prevents tall trees
- Combined optimisations give amortized near-O(1) per operation: O(α(n)) where α is the inverse Ackermann function — effectively constant for all practical n
- Applications: Kruskal's MST, undirected cycle detection, network connectivity, image segmentation

**Tricky points:**
- The `find` operation with path compression mutates the parent array as a side effect — this is intentional and correct
- Union by rank uses height as a proxy; union by size uses subtree node count — both give the same asymptotic complexity
- Checking if two elements are in the same set: `find(x) == find(y)` — if their roots are the same, they share a set
- Adding a new edge (u, v) to an undirected graph creates a cycle if and only if `find(u) == find(y)` before the union
- The `parent` array is initialised with `parent[i] = i` — every element starts as its own root

---

## Complexity

| Operation | Amortized (with both optimisations) | Worst (no optimisations) |
|---|---|---|
| Find | O(α(n)) ≈ O(1) | O(n) |
| Union | O(α(n)) ≈ O(1) | O(n) |
| Make Set (initialise n elements) | O(n) | O(n) |

Space complexity: O(n) for parent and rank/size arrays.

Note: α(n) is the inverse Ackermann function. For all practical n (including n = 10⁸⁰, the estimated number of atoms in the observable universe), α(n) ≤ 5. It is treated as a constant.

---

## What It Is

Imagine a social circle network at a large university. Each student starts as their own social group. When two students become friends, their groups merge. Over time, clusters of mutual friends form. The question "are Alice and Bob in the same social circle?" should be answerable quickly, even after thousands of friendships have formed and groups have merged.

A naive approach would maintain an explicit list of group members and scan lists on every query — O(n) per query. A better approach represents each group by one representative member (the "root" of the group). To find which group someone belongs to, follow the chain of references up to the root. To merge two groups, simply point one root to the other. This is Union-Find without optimisations — O(n) in the worst case if the chain grows long.

Path compression and union by rank are the two optimisations that make this structure nearly magical in practice. Path compression says: the next time you follow a chain to the root, rewire every node you visited to point directly to the root. The tree flattens itself. Union by rank says: when merging two groups, always attach the shorter tree under the taller one — the root of the smaller group becomes a child of the root of the larger group. The tree stays shallow. Together, these two rules make the amortised cost per operation so close to O(1) that the theoretical bound — the inverse Ackermann function — is the only function that grows even more slowly.

---

## How It Actually Works

The data structure is stored in two arrays: `parent` and `rank` (or `size`). `parent[i]` is the parent of element i in its tree. When `parent[i] == i`, element i is a root. Initially, every element is its own root: `parent[i] = i` for all i.

`find(x)` traverses from x up to the root by following parent pointers. With path compression, it then sets `parent[x]` directly to the root (for the next call to be O(1)), and also does the same for every node on the path — using a recursive one-pass or iterative two-pass approach.

`union(x, y)` calls `find` on both x and y to get their roots. If the roots are the same, x and y are already in the same set — no action needed (and this signals a cycle in graph problems). If the roots differ, one root becomes a child of the other. Union by rank attaches the tree with lower rank under the tree with higher rank. If ranks are equal, either attachment is valid, and the rank of the new root is incremented by 1.

```python
class UnionFind:
    def __init__(self, n):
        """Initialise n elements, each in its own set."""
        self.parent = list(range(n))   # parent[i] = i means i is a root
        self.rank = [0] * n            # tree height upper bound
        self.count = n                 # number of disjoint sets

    def find(self, x):
        """Return the root of x's set. Path compression flattens the tree."""
        if self.parent[x] != x:
            self.parent[x] = self.find(self.parent[x])  # path compression
        return self.parent[x]

    def union(self, x, y):
        """Merge the sets containing x and y. Returns False if already in same set."""
        root_x = self.find(x)
        root_y = self.find(y)
        if root_x == root_y:
            return False   # already in the same set (cycle detected in graph context)

        # Union by rank: attach smaller tree under larger
        if self.rank[root_x] < self.rank[root_y]:
            self.parent[root_x] = root_y
        elif self.rank[root_x] > self.rank[root_y]:
            self.parent[root_y] = root_x
        else:
            self.parent[root_y] = root_x
            self.rank[root_x] += 1   # only increment when ranks are equal

        self.count -= 1   # one fewer disjoint set
        return True

    def connected(self, x, y):
        """Return True if x and y are in the same set."""
        return self.find(x) == self.find(y)

    def num_components(self):
        return self.count


# ---- Application 1: cycle detection in undirected graph ----
def has_cycle(num_vertices, edges):
    """
    An edge (u, v) creates a cycle if u and v are already connected.
    """
    uf = UnionFind(num_vertices)
    for u, v in edges:
        if not uf.union(u, v):
            return True    # union returned False — already in same set
    return False

# Path graph: no cycle
print("Path graph has cycle:", has_cycle(5, [(0,1),(1,2),(2,3),(3,4)]))  # False
# Adding back edge: cycle
print("Cyclic graph has cycle:", has_cycle(5, [(0,1),(1,2),(2,3),(3,4),(1,3)]))  # True


# ---- Application 2: Kruskal's Minimum Spanning Tree ----
def kruskal_mst(num_vertices, edges):
    """
    Kruskal's MST: sort edges by weight, add each edge if it doesn't create a cycle.
    O(E log E) for sorting + O(E × α(V)) for union-find operations.
    """
    sorted_edges = sorted(edges, key=lambda e: e[2])  # sort by weight
    uf = UnionFind(num_vertices)
    mst = []
    total_weight = 0

    for u, v, weight in sorted_edges:
        if uf.union(u, v):   # no cycle — safe to add
            mst.append((u, v, weight))
            total_weight += weight
            if len(mst) == num_vertices - 1:
                break    # MST is complete (n-1 edges)

    return mst, total_weight

# Weighted undirected graph
edges = [
    (0, 1, 4), (0, 2, 1), (0, 3, 4),
    (1, 3, 2), (2, 3, 3), (2, 4, 5),
    (3, 4, 7)
]
mst, weight = kruskal_mst(5, edges)
print("MST edges:", mst)
print("MST total weight:", weight)  # Minimum spanning tree weight


# ---- Application 3: number of connected components ----
def count_components(num_vertices, edges):
    uf = UnionFind(num_vertices)
    for u, v in edges:
        uf.union(u, v)
    return uf.num_components()

print("Components:", count_components(7, [(0,1),(1,2),(3,4),(5,6)]))  # 3 components


# ---- Iterative find (avoids recursion limit for very large n) ----
class UnionFindIterative:
    def __init__(self, n):
        self.parent = list(range(n))
        self.size = [1] * n   # union by size instead of rank

    def find(self, x):
        # Two-pass path compression
        root = x
        while self.parent[root] != root:
            root = self.parent[root]
        # Path halving on the way back
        while self.parent[x] != root:
            next_x = self.parent[x]
            self.parent[x] = root
            x = next_x
        return root

    def union(self, x, y):
        root_x = self.find(x)
        root_y = self.find(y)
        if root_x == root_y:
            return False
        # Union by size: attach smaller under larger
        if self.size[root_x] < self.size[root_y]:
            root_x, root_y = root_y, root_x
        self.parent[root_y] = root_x
        self.size[root_x] += self.size[root_y]
        return True
```

---

## How It Connects

Kruskal's MST algorithm processes edges in order of weight and adds each edge if it does not create a cycle. The cycle check is `find(u) == find(v)`. Without Union-Find, each cycle check would require a BFS or DFS — O(V) per edge, making Kruskal's O(EV). With Union-Find, the cycle check is O(α(V)) ≈ O(1), and Kruskal's total complexity is dominated by the O(E log E) sort.

[[graphs|Graphs]]

Graph representations determine how edges are stored and iterated. Kruskal's algorithm works directly from an edge list — one of the three standard representations. Understanding when an edge list is appropriate (algorithm needs all edges sorted, no per-vertex neighbour iteration needed) is a practical representation decision.

[[graph-representations|Graph Representations]]

---

## Common Misconceptions

Misconception 1: "Path compression changes the logical structure of the Union-Find — elements move between sets."
Reality: Path compression only changes which node is the direct parent pointer target. The root of each set remains the same, and every element still finds the same root after compression. The sets are identical; only the internal tree shape (the pointer structure) changes to be flatter. `find(x)` always returns the same root before and after compression.

Misconception 2: "Union-Find can only be used for integers 0 to n−1."
Reality: Union-Find is typically implemented with integer indices for performance, but it can support arbitrary keys by adding a mapping layer (a dict from key to integer index). For interview purposes, the integer implementation is standard. For production code with string or object keys, maintain a separate `{key: index}` dict alongside the arrays.

Misconception 3: "The O(α(n)) complexity means Union-Find is only slightly better than O(log n)."
Reality: α(n) grows astronomically slowly — more slowly than any iterated logarithm. α(2⁶⁵⁵³⁶) = 4. For any dataset you will ever encounter in computing, α(n) ≤ 5. This means Union-Find operations are essentially constant time — not "almost" constant, but constant to every significant digit for all practical purposes.

---

## Why It Matters in Practice

Union-Find is the standard solution for any "group membership" or "connectivity" problem that involves incremental merging. Network connectivity monitoring — tracking which servers in a distributed system are reachable from which others as links go up and down — is a real-time Union-Find problem. Image segmentation algorithms use Union-Find to merge adjacent pixels of similar colour into connected regions. Percolation simulations (is there a connected path from top to bottom in a grid?) are Union-Find problems. Social network friend-of-friend analysis is Union-Find.

In competitive programming and interviews, Union-Find appears in problems phrased as "number of connected components after adding edges," "detect cycle in undirected graph," or "group elements by equivalence class." Recognising that incremental merging of groups with fast connectivity queries is the Union-Find pattern — rather than rebuilding a BFS or DFS on every query — is the key insight.

---

## Interview Angle

Common question forms:
- "Number of provinces (connected components)."
- "Redundant connection — find the edge that creates a cycle."
- "Accounts merge — group email accounts that share an email address."
- "Most stones removed — connected components in a grid."
- "Detect cycle in an undirected graph."

Answer frame:
For any "group by connectivity" or "cycle detection in undirected graph" problem, immediately name Union-Find. State the two operations: `find` with path compression, `union` with union by rank. For cycle detection: iterate edges; if `find(u) == find(v)` before calling union, that edge is redundant (cycle). For connected components: count the number of distinct roots after all unions — this equals the number of disjoint sets. For accounts merge, explain mapping email strings to integer IDs, then unioning all emails in each account.

---

## Related Notes

- [[graphs|Graphs]]
- [[graph-representations|Graph Representations]]
- [[big-o-notation|Big O Notation]]
