---
title: 12 - Balanced Trees (AVL, Red-Black)
description: Balanced trees automatically rebalance after insertions and deletions to guarantee O(log n) height and therefore O(log n) all operations.
tags: [dsa, layer-10, avl-tree, red-black-tree, balanced]
status: draft
difficulty: advanced
layer: 10
domain: dsa
created: 2026-05-18
---

# Balanced Trees (AVL, Red-Black)

> A balanced tree is a self-correcting BST — it watches its own shape and performs rotations to prevent the degenerate linear case from ever occurring.

---

## Quick Reference

**Core idea:**
- AVL tree: the balance factor (height of left subtree − height of right subtree) at every node must be −1, 0, or 1
- Red-Black tree: nodes are coloured red or black; rules about colour relationships limit height to at most 2 × log₂(n+1)
- Both guarantee O(log n) height — and therefore O(log n) search, insert, and delete
- Rebalancing uses rotations: O(1) pointer rewiring that adjusts the tree's shape without changing inorder sequence
- Red-Black trees are preferred in practice (Java TreeMap, C++ std::map, Linux kernel) because they require fewer rotations

**Tricky points:**
- AVL trees are more strictly balanced than Red-Black trees — shorter height, faster lookups — but require more rotations on insert/delete
- Rotations preserve the BST property: the inorder sequence is unchanged
- B-trees are a generalisation for disk storage (each node holds many keys) — used in database index structures
- Python has no built-in balanced BST; `sortedcontainers.SortedList` provides O(log n) operations via a B-tree-like list-of-lists
- The height guarantee is why sorted iteration over a TreeMap is O(n) while iterating a hash map is O(n) but unordered

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Search | O(log n) | O(log n) |
| Insert | O(log n) | O(log n) |
| Delete | O(log n) | O(log n) |
| Min / Max | O(log n) | O(log n) |
| In-order traversal | O(n) | O(n) |

Space complexity: O(n)

---

## What It Is

Imagine a self-levelling bookshelf. Every time you add or remove a book, a mechanical arm adjusts the shelves so that no shelf is more than one level higher than its neighbour. This takes a small amount of extra work on each insertion, but it guarantees that finding any book takes no more than log₂(n) shelf moves — regardless of which order you added the books and regardless of how many you have. A regular BST is a bookshelf with no arm: it works fine when books are added in random order, but if you add them in alphabetical order, every book ends up on a longer and longer rightmost shelf until the whole collection is unusable.

AVL trees (named after Adelson-Velsky and Landis, 1962) were the first self-balancing BSTs. They maintain a balance factor at every node: the difference between the height of the left subtree and the height of the right subtree. If any insertion or deletion causes a node's balance factor to become −2 or +2 (meaning one side is two levels taller than the other), the tree performs one or two rotations at that node to restore balance. Rotations rewire parent-child pointers in O(1) — the BST ordering is preserved, but the shape improves.

Red-Black trees (used in Java's `TreeMap`, C++'s `std::map`, and the Linux kernel's process scheduler) use a colour property instead of explicit height tracking. Each node is coloured red or black, and a set of rules about colour patterns limits the maximum path length in the tree. Red-Black trees allow slightly less strict balance than AVL trees — the longest path may be up to twice the shortest — but this flexibility requires fewer rotations on average, making insertions and deletions faster in practice. For workloads with frequent updates, Red-Black trees outperform AVL trees despite having marginally worse lookup performance.

---

## How It Actually Works

A rotation is a local pointer rewiring between a parent and one of its children. A right rotation at a node P takes P's left child L, moves L to P's position, and makes P the right child of L. P's original right subtree stays with P; L's original right subtree becomes P's new left subtree. The BST inorder property is preserved because L's right subtree contained values between L and P — which is exactly where they belong as P's new left subtree.

AVL rebalancing uses four rotation cases based on the "shape" of the imbalance. A right-right imbalance (the tree is heavy on the right side and the right child is heavy on its own right) requires a single left rotation. A left-left imbalance requires a single right rotation. A right-left imbalance requires a right rotation on the right child followed by a left rotation on the root. A left-right imbalance requires a left rotation on the left child followed by a right rotation on the root.

```python
# AVL Tree implementation

class AVLNode:
    def __init__(self, value):
        self.value = value
        self.left = None
        self.right = None
        self.height = 0   # leaf height = 0

def _height(node):
    return node.height if node else -1

def _update_height(node):
    node.height = 1 + max(_height(node.left), _height(node.right))

def _balance_factor(node):
    return _height(node.left) - _height(node.right)

def _rotate_right(y):
    """Right rotation at y. y's left child becomes the new root."""
    x = y.left
    t2 = x.right
    x.right = y
    y.left = t2
    _update_height(y)
    _update_height(x)
    return x   # new root of this subtree

def _rotate_left(x):
    """Left rotation at x. x's right child becomes the new root."""
    y = x.right
    t2 = y.left
    y.left = x
    x.right = t2
    _update_height(x)
    _update_height(y)
    return y   # new root of this subtree

def _rebalance(node):
    _update_height(node)
    bf = _balance_factor(node)

    # Left-heavy
    if bf > 1:
        if _balance_factor(node.left) < 0:       # Left-Right case
            node.left = _rotate_left(node.left)
        return _rotate_right(node)                # Left-Left case

    # Right-heavy
    if bf < -1:
        if _balance_factor(node.right) > 0:      # Right-Left case
            node.right = _rotate_right(node.right)
        return _rotate_left(node)                 # Right-Right case

    return node   # already balanced

def avl_insert(node, value):
    if node is None:
        return AVLNode(value)
    if value < node.value:
        node.left = avl_insert(node.left, value)
    elif value > node.value:
        node.right = avl_insert(node.right, value)
    else:
        return node   # no duplicates
    return _rebalance(node)

def avl_inorder(node):
    if node is None:
        return []
    return avl_inorder(node.left) + [node.value] + avl_inorder(node.right)

def avl_height(node):
    return _height(node)


# Demonstrate: inserting sorted data into AVL vs plain BST
root = None
for value in [1, 2, 3, 4, 5, 6, 7]:   # sorted — would degenerate a plain BST
    root = avl_insert(root, value)

print("AVL inorder:", avl_inorder(root))   # [1, 2, 3, 4, 5, 6, 7]
print("AVL height:", avl_height(root))     # 2 — maintained at log₂(7) ≈ 2.8

# With a plain BST, sorted insertion gives height 6:
from binary_search_trees_demo import BST  # conceptual import
# degenerate_bst height would be 6 (a linear chain)


# sortedcontainers.SortedList — Python's practical balanced-tree equivalent
# (install: pip install sortedcontainers)
try:
    from sortedcontainers import SortedList
    sl = SortedList()
    for v in [5, 3, 7, 1, 4, 6, 8, 2]:
        sl.add(v)                       # O(log n) insert
    print("SortedList:", list(sl))      # [1, 2, 3, 4, 5, 6, 7, 8] — always sorted
    print("Index 3:", sl[3])            # O(log n) access
    print("Bisect left 4:", sl.bisect_left(4))  # O(log n) range query
    sl.remove(5)                        # O(log n) remove
    print("After remove 5:", list(sl))  # [1, 2, 3, 4, 6, 7, 8]
except ImportError:
    print("Install sortedcontainers for practical balanced tree in Python")
```

---

## Visualizer

<iframe src="/static/visualizers/balanced-tree.html" style="width:100%;height:500px;border:none;border-radius:8px;" title="Balanced Tree Visualizer"></iframe>

---

## How It Connects

The entire motivation for balanced trees comes from the BST's degenerate worst case. The binary search tree note establishes why O(n) height is possible; balanced trees are the solution to that problem. Understanding BST insertion and the inorder sequence property is a prerequisite for understanding why rotations preserve correctness.

[[binary-search-trees|Binary Search Trees]]

Heaps are also tree-based structures with a shape property (complete binary tree), but their ordering constraint (parent ≥ or ≤ children) is weaker than the BST property. Understanding both helps clarify when to use a heap (priority access to min/max) versus a balanced BST (ordered iteration, range queries, arbitrary lookups).

[[heaps|Heaps and Priority Queues]]

---

## Common Misconceptions

Misconception 1: "Rotations change the BST ordering of elements."
Reality: Rotations preserve the inorder sequence exactly. A rotation is a purely structural change — it adjusts the shape of the tree without moving any element to a position where the BST property would be violated. The inorder traversal produces the same sequence before and after a rotation.

Misconception 2: "Red-Black trees are slower than AVL trees because they are less strictly balanced."
Reality: Red-Black trees perform fewer rotations on average during insertions and deletions, making them faster for write-heavy workloads. AVL trees have stricter balance and thus shorter maximum path lengths, giving them slightly faster lookups in read-heavy workloads. Neither is universally faster — the trade-off depends on the access pattern.

Misconception 3: "Python has a built-in balanced BST."
Reality: Python's standard library has no balanced BST. The `sortedcontainers` third-party package provides `SortedList`, `SortedDict`, and `SortedSet` with O(log n) operations. For production use, `sortedcontainers` is the standard recommendation. Implementing a full AVL or Red-Black tree from scratch in Python is primarily a learning exercise.

---

## Why It Matters in Practice

Database indexes are the highest-stakes application of balanced tree structures. B-trees (a generalisation where each node holds many keys, optimised for disk page boundaries) underpin PostgreSQL, MySQL, and SQLite indexes. Every time a SQL query uses an index to find rows in O(log n) rather than O(n) table-scan time, a balanced tree is responsible. Understanding why balanced trees maintain their performance guarantee — and what would cause an index to stop being useful (a very high update rate causing frequent rebalancing, or statistics becoming stale) — is important knowledge for backend engineering.

In Python applications, `sortedcontainers.SortedList` is the appropriate tool when you need a collection that maintains sorted order under dynamic inserts and deletes, supports O(log n) insertion of new elements, and also supports O(log n) range queries (give me all elements between 10 and 50). A plain list with `bisect` gives O(log n) search but O(n) insert; a heap gives O(log n) push/pop but no sorted iteration or range queries. The balanced BST is the only structure that provides all three.

---

## Interview Angle

Common question forms:
- "What is an AVL tree and how does it maintain balance?"
- "Why are Red-Black trees preferred over AVL trees in practice?"
- "What is a tree rotation and does it change the BST property?"
- "What is a B-tree and where is it used?"

Answer frame:
For AVL trees, define the balance factor (height difference ≤ 1 at every node) and name the four rotation cases. For Red-Black vs AVL, give the trade-off: AVL is stricter balance, fewer reads; Red-Black requires fewer rotations, faster writes — which is why it is preferred for general-purpose sorted maps. For rotations, immediately state that they preserve the inorder sequence — then describe the pointer rewiring. For B-trees, say they are balanced trees with high branching factor optimised for disk I/O, used in all major database index implementations.

---

## Related Notes

- [[binary-search-trees|Binary Search Trees]]
- [[heaps|Heaps and Priority Queues]]
- [[big-o-notation|Big O Notation]]
