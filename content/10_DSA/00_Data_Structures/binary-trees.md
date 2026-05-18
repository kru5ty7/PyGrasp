---
title: 10 - Binary Trees
description: A binary tree is a hierarchical structure where each node has at most two children, forming the foundation for search trees, heaps, and expression parsers.
tags: [dsa, layer-10, binary-tree, tree]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Binary Trees

> Binary trees introduce hierarchical organisation into data — where arrays and lists are flat sequences, trees express relationships of containment, ordering, and ancestry.

---

## Quick Reference

**Core idea:**
- Each node has at most two children: left and right
- Root: the top node with no parent. Leaf: a node with no children. Height: longest root-to-leaf path.
- Three traversal orders: inorder (L→N→R), preorder (N→L→R), postorder (L→R→N)
- Complete binary tree: all levels full except possibly the last, which is filled from left — used in heaps
- Perfect binary tree: all levels completely full — exactly 2ʰ⁺¹ − 1 nodes for height h

**Tricky points:**
- Height of a single node is 0 (or 1 depending on convention — always clarify in interviews)
- A tree with n nodes has n-1 edges — always
- Inorder traversal of a BST yields sorted output; inorder of a general binary tree has no ordering guarantee
- Recursive traversals implicitly use the call stack — deep trees can cause RecursionError; iterative versions avoid this
- "Balanced" is not a property of general binary trees — it is a property of specific tree types (AVL, Red-Black)

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Access (general tree) | O(n) | O(n) |
| Search (general tree) | O(n) | O(n) |
| Insert (general tree) | O(n) | O(n) |
| Inorder/Preorder/Postorder traversal | O(n) | O(n) |
| Height calculation | O(n) | O(n) |

Space complexity: O(n) for storage; O(h) for recursive traversal call stack where h is the height.

---

## What It Is

Think of a corporate org chart. At the top is the CEO. Below the CEO are two division heads. Below each division head are two managers. Below each manager are individual contributors. Every person has exactly one boss (except the CEO) and at most two direct reports. To find a particular employee, you start at the CEO, ask which division they are in, go to that division head, ask which team, and continue downward. You never need to look at the entire organisation — each decision halves (or at least reduces) the remaining search space.

This hierarchical structure appears across computing wherever data has natural parent-child relationships. File systems are trees: a directory contains files and subdirectories, each of which may contain more files and subdirectories. HTML and XML documents are trees: a `<div>` contains `<p>` elements which contain `<span>` elements. Expression parsers represent arithmetic expressions as trees where operators are internal nodes and operands are leaves — the expression `(3 + 4) * 2` is a tree with `*` at the root, `+` as the left child, and `2` as the right child.

The binary constraint — at most two children — makes binary trees especially tractable for algorithm analysis. With two choices at each level, the depth of a balanced binary tree is O(log n) for n nodes. This logarithmic height is what gives binary search trees, heaps, and balanced tree variants their efficient operations. The difference between O(n) height (a degenerate linear tree) and O(log n) height (a balanced tree) is the entire motivation for balanced tree structures.

---

## How It Actually Works

A binary tree node contains three fields: the stored value, a reference to the left child, and a reference to the right child. A `None` reference indicates the absence of a child. The tree itself is often represented by holding a reference to the root node — there is no additional structure required.

The three depth-first traversal orders differ only in when the current node is processed relative to its children. Inorder processes the left subtree, then the current node, then the right subtree. Preorder processes the current node first, making it useful for serialising a tree (the root appears first in the output, allowing reconstruction). Postorder processes both children before the current node, making it useful for operations that require child results before the parent can be processed (calculating subtree sizes, deleting a tree).

```python
class TreeNode:
    def __init__(self, value):
        self.value = value
        self.left = None
        self.right = None


# Build a small tree:
#        1
#       / \
#      2   3
#     / \   \
#    4   5   6

root = TreeNode(1)
root.left = TreeNode(2)
root.right = TreeNode(3)
root.left.left = TreeNode(4)
root.left.right = TreeNode(5)
root.right.right = TreeNode(6)


# ---- Recursive traversals ----
def inorder(node):
    if node is None:
        return []
    return inorder(node.left) + [node.value] + inorder(node.right)

def preorder(node):
    if node is None:
        return []
    return [node.value] + preorder(node.left) + preorder(node.right)

def postorder(node):
    if node is None:
        return []
    return postorder(node.left) + postorder(node.right) + [node.value]

print("Inorder:  ", inorder(root))    # [4, 2, 5, 1, 3, 6]
print("Preorder: ", preorder(root))   # [1, 2, 4, 5, 3, 6]
print("Postorder:", postorder(root))  # [4, 5, 2, 6, 3, 1]


# ---- Iterative inorder (avoids recursion limit for deep trees) ----
def inorder_iterative(root):
    result = []
    stack = []
    current = root
    while current or stack:
        while current:                  # go as far left as possible
            stack.append(current)
            current = current.left
        current = stack.pop()           # backtrack
        result.append(current.value)    # process node
        current = current.right         # move to right subtree
    return result

print("Iterative inorder:", inorder_iterative(root))  # [4, 2, 5, 1, 3, 6]


# ---- Level-order (BFS) traversal ----
from collections import deque

def level_order(root):
    if root is None:
        return []
    result = []
    queue = deque([root])
    while queue:
        level_size = len(queue)
        level = []
        for _ in range(level_size):
            node = queue.popleft()
            level.append(node.value)
            if node.left:
                queue.append(node.left)
            if node.right:
                queue.append(node.right)
        result.append(level)
    return result

print("Level order:", level_order(root))  # [[1], [2, 3], [4, 5, 6]]


# ---- Tree properties ----
def height(node):
    """Height of a tree. Empty tree has height -1; single node has height 0."""
    if node is None:
        return -1
    return 1 + max(height(node.left), height(node.right))

def count_nodes(node):
    if node is None:
        return 0
    return 1 + count_nodes(node.left) + count_nodes(node.right)

def is_complete(root):
    """Check if tree is complete — all levels full except last, filled left-to-right."""
    if root is None:
        return True
    queue = deque([root])
    found_null = False
    while queue:
        node = queue.popleft()
        for child in (node.left, node.right):
            if child is None:
                found_null = True
            else:
                if found_null:
                    return False   # non-null after null — not complete
                queue.append(child)
    return True

print("Height:", height(root))          # 2
print("Node count:", count_nodes(root)) # 6
print("Is complete:", is_complete(root)) # False (right child of 3 is missing left)
```

---

## Visualizer

<iframe src="/visualizers/binary-tree.html" style="width:100%;height:480px;border:none;border-radius:8px;" title="Binary Tree Visualizer"></iframe>

---

## How It Connects

Binary search trees impose an ordering constraint on top of the binary tree structure. The BST is the most important binary tree variant for search operations, and all its analysis — O(log n) average vs O(n) worst case — is built directly on the height analysis of binary trees.

[[binary-search-trees|Binary Search Trees]]

Heaps are binary trees stored in array form, with the complete binary tree constraint ensuring the array representation is compact. Understanding complete binary trees is a prerequisite for understanding how heaps are stored and why the parent-child index arithmetic works.

[[heaps|Heaps and Priority Queues]]

---

## Common Misconceptions

Misconception 1: "A binary tree and a binary search tree are the same thing."
Reality: A binary tree is any tree where each node has at most two children — there is no ordering constraint. A binary search tree is a binary tree with the specific constraint that left subtree values are less than the node and right subtree values are greater. Heaps are also binary trees but with a different constraint (parent ≥ children). These are distinct structures with different properties.

Misconception 2: "Recursion is the only way to traverse a tree."
Reality: All recursive tree traversals can be implemented iteratively using an explicit stack (for DFS traversals) or a queue (for level-order traversal). Iterative traversals are necessary when tree depth could exceed Python's recursion limit, which defaults to 1000.

Misconception 3: "Height and depth are the same concept."
Reality: Depth is a property of a node — it is the number of edges from the root to that node. Height is a property of a subtree — it is the length of the longest path from a node down to any leaf. The height of the whole tree is the height of the root node. A leaf at the bottom of a tall tree has maximum depth and height 0.

---

## Why It Matters in Practice

Binary trees appear in every domain of software engineering. File system directory traversal is tree traversal. XML and HTML parsers produce parse trees. Compilers convert source code into abstract syntax trees (ASTs) before optimising and generating code. JSON parsing produces trees. Database query planners generate tree-structured execution plans. Decision trees in machine learning are binary trees. Knowing the traversal orders and their appropriate applications — preorder for serialisation, inorder for sorted output, postorder for bottom-up computation, level-order for shortest paths — is foundational knowledge for any software developer.

---

## Interview Angle

Common question forms:
- "Find the maximum depth of a binary tree."
- "Check if a binary tree is symmetric."
- "Serialize and deserialize a binary tree."
- "Find the lowest common ancestor of two nodes."
- "Check if a binary tree is balanced."

Answer frame:
For depth/height problems, immediately set up the recursive structure: base case is `None` returning 0 or -1, recursive case takes the max of left and right depths plus 1. For LCA, describe the recursive approach: if either target is found at the current node, return it; if both subtrees return non-null, the current node is the LCA. For serialisation, describe preorder traversal with a null marker — the preorder root-first property is what allows reconstruction.

---

## Related Notes

- [[binary-search-trees|Binary Search Trees]]
- [[heaps|Heaps and Priority Queues]]
- [[bfs|Breadth-First Search]]
