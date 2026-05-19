---
title: 03 - Linked Lists
description: A linked list is a chain of nodes where each node holds a value and a pointer to the next node, enabling O(1) insertion without shifting.
tags: [dsa, layer-10, linked-list, pointers]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Linked Lists

> Linked lists sacrifice random access to gain cheap insertion and deletion - a fundamental trade-off that determines when they are the right tool.

---

## Quick Reference

**Core idea:**
- Each node stores a value and a `next` pointer to the following node
- Nodes are allocated independently on the heap - no contiguous memory requirement
- Insert or delete at a known position: O(1) - just rewire pointers
- Access element by index: O(n) - must traverse from head
- No index arithmetic is possible because nodes are not adjacent in memory

**Tricky points:**
- Insert/delete is O(1) only if you already have a reference to the node - finding it first is O(n)
- Forgetting to update the tail pointer during insertion causes silent bugs
- Linked lists have poor cache performance - each node access is a pointer dereference to a random heap location
- Python does not have a built-in singly linked list; `collections.deque` uses a doubly linked list internally
- Off-by-one errors are common when implementing reverse or cycle detection

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Access by index | O(n) | O(n) |
| Search | O(n) | O(n) |
| Insert at head | O(1) | O(1) |
| Insert at tail (no tail pointer) | O(n) | O(n) |
| Insert at tail (with tail pointer) | O(1) | O(1) |
| Delete at known node | O(1) | O(1) |
| Delete by value | O(n) | O(n) |

Space complexity: O(n)

---

## What It Is

Picture a treasure hunt where each clue tells you where the next clue is hidden, but gives you no information about any clue beyond the next one. To reach the fifth clue, you must start at clue one, read where clue two is, go there, read where clue three is, and so on. You cannot jump directly to clue five - there is no map of all locations. This is exactly how a linked list works: each element knows only about the one that follows it, and getting to any particular element requires starting from the beginning and following the chain.

The advantage of this design appears when you need to add a new clue between clue three and clue four. In a treasure hunt book (an array), you would need to physically renumber and rewrite every clue from four onward to make room. In the linked treasure hunt, you simply write a new clue, update clue three to point to it, and write in the new clue the location of the original clue four. Two changes - done. The length of the hunt is irrelevant to how long that insertion takes.

This trade-off shapes every situation where linked lists appear. They are not universally better or worse than arrays - they are specifically better at insertion and deletion when you already know the position, and specifically worse at positional access and iteration. Real-world uses include implementing other structures (stacks, queues, LRU caches) and scenarios where the order of a collection changes frequently and random access is rare.

---

## How It Actually Works

A singly linked list is composed of node objects, each containing two fields: the data (the value stored) and a reference to the next node. The list itself maintains a `head` reference pointing to the first node, and optionally a `tail` reference pointing to the last node. The last node's `next` reference is `None`, signalling the end of the list.

Insertion at the head is the cheapest operation: create a new node, set its `next` to the current head, and update `head` to point to the new node. This is O(1) regardless of list length. Insertion at the tail with a tail pointer is also O(1): create a new node, set the current tail's `next` to it, and update `tail`. Insertion in the middle requires traversal to the predecessor node, then a pointer rewire - the traversal is O(n), but the actual insertion is O(1). Deletion follows the same pattern: find the predecessor, point it to the node after the one being deleted, and discard the deleted node.

```python
class Node:
    def __init__(self, value):
        self.value = value
        self.next = None


class LinkedList:
    def __init__(self):
        self.head = None
        self.tail = None
        self._length = 0

    def append(self, value):
        """Insert at tail - O(1) with tail pointer."""
        node = Node(value)
        if self.tail is None:
            self.head = self.tail = node
        else:
            self.tail.next = node
            self.tail = node
        self._length += 1

    def prepend(self, value):
        """Insert at head - O(1)."""
        node = Node(value)
        node.next = self.head
        self.head = node
        if self.tail is None:
            self.tail = node
        self._length += 1

    def delete(self, value):
        """Delete first occurrence - O(n) to find, O(1) to remove."""
        if self.head is None:
            return
        if self.head.value == value:
            self.head = self.head.next
            if self.head is None:
                self.tail = None
            self._length -= 1
            return
        current = self.head
        while current.next:
            if current.next.value == value:
                if current.next is self.tail:
                    self.tail = current
                current.next = current.next.next
                self._length -= 1
                return
            current = current.next

    def reverse(self):
        """Reverse in place - O(n)."""
        prev = None
        current = self.head
        self.tail = self.head
        while current:
            next_node = current.next
            current.next = prev
            prev = current
            current = next_node
        self.head = prev

    def to_list(self):
        result = []
        current = self.head
        while current:
            result.append(current.value)
            current = current.next
        return result

    def __len__(self):
        return self._length


# Usage
ll = LinkedList()
ll.append(1)
ll.append(2)
ll.append(3)
ll.prepend(0)
print(ll.to_list())   # [0, 1, 2, 3]

ll.delete(2)
print(ll.to_list())   # [0, 1, 3]

ll.reverse()
print(ll.to_list())   # [3, 1, 0]
```

---

## Visualizer

<iframe src="/static/visualizers/linked-list.html" style="width:100%;height:380px;border:none;border-radius:8px;" title="Linked List Visualizer"></iframe>

---

## How It Connects

Arrays and linked lists are the two foundational sequential data structures, and their contrasting trade-offs explain why every other sequential structure exists. Understanding where arrays excel (random access, cache locality) and where linked lists excel (insertion at known positions) is the foundation for choosing the right structure.

[[arrays|Arrays]]

Doubly linked lists extend the singly linked list with a backward pointer on every node. This single change unlocks O(1) deletion of a known node without needing to traverse to the predecessor - a capability that is essential for LRU cache implementations.

[[doubly-linked-lists|Doubly Linked Lists]]

---

## Common Misconceptions

Misconception 1: "Linked lists are faster than arrays for insertion."
Reality: Linked list insertion is O(1) only at the point of insertion, and only when you already hold a reference to that position. If you must first search for where to insert, the search is O(n) - the same as the O(n) shift cost in an array. The linked list wins only when you already have the node reference.

Misconception 2: "Linked lists use less memory than arrays."
Reality: Linked lists use more memory per element than arrays. Each node stores the value plus one (or two, for doubly linked) pointer fields. An array of integers stores only the integers. The heap allocation overhead per node also adds up. Arrays are typically more memory-efficient.

Misconception 3: "Python's `list` is a linked list."
Reality: Python's `list` is a dynamic array - a contiguous block of object pointers that resizes on demand. It is not a linked list. The Python standard library's linked-list implementation is `collections.deque`, which is a doubly linked list of fixed-size blocks.

---

## Why It Matters in Practice

Linked lists appear directly in interview problems - reversing a list, detecting cycles (Floyd's algorithm), finding the middle node, and merging sorted lists are all standard questions. More importantly, they are the structural foundation for stacks, queues, and more complex structures like LRU caches. Understanding pointer manipulation at this level builds the mental model needed for every pointer-based structure that follows.

In Python, you will rarely implement a singly linked list in production code. The practical takeaway is understanding why `collections.deque` should be used for queue operations instead of `list`, and why the deque's performance guarantees come from its linked structure. The concept transfers directly.

---

## Interview Angle

Common question forms:
- "Reverse a linked list in place."
- "Detect a cycle in a linked list."
- "Find the middle of a linked list in one pass."
- "Merge two sorted linked lists."
- "Remove the nth node from the end."

Answer frame:
For pointer manipulation questions, always draw the before/after state for a small example before writing code. Establish your pointer variables (`prev`, `current`, `next_node`) and trace through two or three iterations manually. For cycle detection, name Floyd's algorithm and explain the two-pointer approach. For the "remove nth from end" problem, describe the two-pointer technique with a gap of n between them.

---

## Related Notes

- [[arrays|Arrays]]
- [[doubly-linked-lists|Doubly Linked Lists]]
- [[stacks|Stacks]]
