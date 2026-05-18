---
title: Binary Search Trees
description: A BST is a binary tree with an ordering property that enables O(log n) average search, insert, and delete.
tags: [dsa, layer-10, bst, binary-search-tree]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Binary Search Trees

> A binary search tree applies the logic of binary search to a dynamic data structure — you can insert and delete while still searching in O(log n) average time.

---

## Quick Reference

**Core idea:**
- BST property: for every node N, all values in N's left subtree are less than N, and all values in N's right subtree are greater
- Search, insert, and delete are all O(log n) average — proportional to height
- Inorder traversal of a BST yields all values in sorted order
- Deletion is the most complex operation: three cases depending on how many children the deleted node has
- Degenerate BST: inserting already-sorted data creates a linear chain — O(n) height, O(n) all operations

**Tricky points:**
- "O(log n)" holds only for a balanced tree; a degenerate BST can be O(n) for all operations
- The deletion case where the target has two children requires finding the inorder successor (or predecessor)
- A BST does not maintain balance automatically — that is the job of AVL trees and Red-Black trees
- Duplicate handling is not standardised: choose "left for equal", "right for equal", or "no duplicates" and be consistent
- Reconstructing a BST from its inorder traversal alone is not possible — inorder of a BST is always sorted, so any balanced BST structure fits

---

## Complexity

| Operation | Average | Worst (degenerate) |
|---|---|---|
| Search | O(log n) | O(n) |
| Insert | O(log n) | O(n) |
| Delete | O(log n) | O(n) |
| Inorder traversal | O(n) | O(n) |
| Min / Max | O(log n) | O(n) |

Space complexity: O(n) storage; O(h) call stack for recursive operations where h is height.

---

## What It Is

Think of a guessing game. You think of a number between 1 and 100, and your friend asks "Is it higher or lower than 50?" If you say higher, they ask about 75. If lower, they ask about 25. Each question eliminates roughly half the remaining possibilities. In ten questions, they can find any number from 1 to 1000. A binary search tree organises data so that every search decision is exactly this: go left if the target is smaller than the current node, go right if it is larger.

The crucial advantage over a sorted array is that a BST supports efficient insertion and deletion while maintaining the ordering property. In a sorted array, inserting a new element requires shifting all larger elements to make room — O(n). In a BST, inserting a new element follows the search path and attaches it as a leaf at the correct position — O(log n) average. The tree's structure naturally accommodates growth and shrinkage without requiring reorganisation of all existing elements.

The degenerate case is the BST's fundamental vulnerability. If you insert the values 1, 2, 3, 4, 5 in that order, each new value is larger than all existing values, so it is always inserted as the rightmost child. The result is a chain — a linked list in tree clothing. Every search must traverse the entire chain. This is why BSTs are often described with the caveat "O(log n) average" and why balanced tree variants exist: to enforce the O(log n) height guarantee regardless of insertion order.

---

## How It Actually Works

Search follows a straightforward recursive descent. At each node, compare the target to the current value. If equal, found. If target is less, recurse on the left subtree. If target is greater, recurse on the right subtree. If a `None` node is reached, the value is not present.

Insertion finds the correct leaf position using the same descent and attaches a new node there. The BST property is maintained automatically: a node inserted into the left subtree is smaller than its ancestors, and one inserted into the right subtree is larger.

Deletion is the complex operation. If the target is a leaf, remove it directly. If it has one child, replace it with that child. If it has two children, the deleted node cannot be replaced by either child without violating the BST property for the other subtree. The solution is to find the inorder successor — the smallest value in the right subtree (the leftmost node of the right subtree) — copy its value into the deleted node's position, and then delete the inorder successor (which has at most one child, since it has no left child by definition).

```python
class BSTNode:
    def __init__(self, value):
        self.value = value
        self.left = None
        self.right = None


class BST:
    def __init__(self):
        self.root = None

    def insert(self, value):
        self.root = self._insert(self.root, value)

    def _insert(self, node, value):
        if node is None:
            return BSTNode(value)
        if value < node.value:
            node.left = self._insert(node.left, value)
        elif value > node.value:
            node.right = self._insert(node.right, value)
        # Equal: do nothing (no duplicates in this implementation)
        return node

    def search(self, value):
        return self._search(self.root, value)

    def _search(self, node, value):
        if node is None:
            return False
        if value == node.value:
            return True
        if value < node.value:
            return self._search(node.left, value)
        return self._search(node.right, value)

    def delete(self, value):
        self.root = self._delete(self.root, value)

    def _delete(self, node, value):
        if node is None:
            return None
        if value < node.value:
            node.left = self._delete(node.left, value)
        elif value > node.value:
            node.right = self._delete(node.right, value)
        else:
            # Node to delete found
            if node.left is None:
                return node.right    # Case 1 & 2: zero or one child
            if node.right is None:
                return node.left
            # Case 3: two children — replace with inorder successor
            successor = self._min_node(node.right)
            node.value = successor.value
            node.right = self._delete(node.right, successor.value)
        return node

    def _min_node(self, node):
        """Leftmost node — minimum value in subtree."""
        while node.left:
            node = node.left
        return node

    def inorder(self):
        result = []
        self._inorder(self.root, result)
        return result

    def _inorder(self, node, result):
        if node is None:
            return
        self._inorder(node.left, result)
        result.append(node.value)
        self._inorder(node.right, result)

    def height(self):
        return self._height(self.root)

    def _height(self, node):
        if node is None:
            return -1
        return 1 + max(self._height(node.left), self._height(node.right))


# Demonstration
bst = BST()
for value in [5, 3, 7, 1, 4, 6, 8]:
    bst.insert(value)

print("Inorder (sorted):", bst.inorder())  # [1, 3, 4, 5, 6, 7, 8]
print("Search 4:", bst.search(4))          # True
print("Search 9:", bst.search(9))          # False
print("Height:", bst.height())             # 2

bst.delete(5)  # node with two children — replaced by inorder successor (6)
print("After deleting 5:", bst.inorder())  # [1, 3, 4, 6, 7, 8]

bst.delete(1)  # leaf node
print("After deleting 1:", bst.inorder())  # [3, 4, 6, 7, 8]

bst.delete(7)  # node with one child (8)
print("After deleting 7:", bst.inorder())  # [3, 4, 6, 8]


# Degenerate case: inserting sorted data
degenerate = BST()
for i in range(1, 8):       # 1, 2, 3, 4, 5, 6, 7
    degenerate.insert(i)
print("Degenerate height:", degenerate.height())  # 6 — a linked list, not log(7)=2

balanced = BST()
for i in [4, 2, 6, 1, 3, 5, 7]:   # insert in balanced order
    balanced.insert(i)
print("Balanced height:", balanced.height())      # 2
```

---

## How It Connects

Binary trees define the structural foundation for BSTs — the parent/child/leaf vocabulary, traversal orders, and height analysis all come from the general binary tree. The BST adds only the ordering constraint, but that single constraint changes the complexity of search from O(n) to O(log n) on average.

[[binary-trees|Binary Trees]]

The degenerate BST case — O(n) height when keys are inserted in sorted order — is the direct motivation for balanced trees. AVL trees and Red-Black trees are BSTs with automatic rebalancing mechanisms that guarantee O(log n) height regardless of insertion order.

[[balanced-trees|Balanced Trees (AVL, Red-Black)]]

---

## Common Misconceptions

Misconception 1: "A BST is always O(log n) for search."
Reality: A BST is O(log n) average only when the tree is reasonably balanced. In the worst case — when keys are inserted in sorted or reverse-sorted order — the tree degenerates into a linear chain and all operations are O(n). The O(log n) guarantee requires either random insertion order (on average) or an explicit balancing mechanism.

Misconception 2: "Inorder traversal of a BST proves the data is sorted."
Reality: Inorder traversal of any correctly built BST produces sorted output. This is not an interesting property to verify — it is a mathematical consequence of the BST definition. What is interesting is using inorder traversal to extract sorted data from a BST without an explicit sort operation.

Misconception 3: "Deletion from a BST is symmetric — you can always replace with either the inorder predecessor or successor."
Reality: Both are valid and produce a correct BST. Using the inorder predecessor (largest in left subtree) or inorder successor (smallest in right subtree) both maintain the BST property. However, always choosing the same side can lead to imbalance over many deletions, which is why balanced trees use rotation-based rebalancing rather than simple replacement.

---

## Why It Matters in Practice

BSTs are the conceptual foundation for a family of data structures that appear in every programming language's standard library. Python's `sortedcontainers.SortedList` and `SortedDict` use a B-tree variant. Java's `TreeMap` and `TreeSet` use Red-Black trees. C++'s `std::map` and `std::set` use Red-Black trees. When you need a collection that supports sorted iteration, range queries, or finding the nearest element to a value — and you also need dynamic insertions and deletions — some form of balanced BST is the standard solution.

Understanding the degenerate case is important for security. A web application that builds a BST from user-controlled input (for example, sorting submitted form fields) could be subject to a denial-of-service attack where the attacker submits fields in sorted order, forcing O(n) insert times and O(n) search times for all subsequent queries.

---

## Interview Angle

Common question forms:
- "Validate whether a given binary tree is a valid BST."
- "Find the kth smallest element in a BST."
- "Convert a sorted array to a height-balanced BST."
- "Find the lowest common ancestor of two nodes in a BST."
- "Describe BST delete for a node with two children."

Answer frame:
For BST validation, describe the min/max bound approach rather than simply checking `node.left.value < node.value` — the left subtree comparison fails for descendants: pass lower and upper bounds down the recursion. For kth smallest, describe inorder traversal with an early-exit counter. For the two-children delete, name the inorder successor, explain why it has at most one child (no left child, by the property of being the leftmost node of the right subtree), and describe the two-step process: copy value, delete successor.

---

## Related Notes

- [[binary-trees|Binary Trees]]
- [[balanced-trees|Balanced Trees (AVL, Red-Black)]]
- [[binary-search|Binary Search]]
