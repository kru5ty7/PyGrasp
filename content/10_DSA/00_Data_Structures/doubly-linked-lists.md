---
title: Doubly Linked Lists
description: A doubly linked list extends the singly linked list with backward pointers, enabling O(1) deletion of any known node.
tags: [dsa, layer-10, linked-list, doubly-linked]
status: draft
difficulty: intermediate
layer: 10
domain: dsa
created: 2026-05-18
---

# Doubly Linked Lists

> Adding a single backward pointer to each node transforms a linked list from a one-way street into a two-way road — and that change makes O(1) deletion of known nodes possible.

---

## Quick Reference

**Core idea:**
- Each node holds a value, a `next` pointer, and a `prev` pointer
- O(1) delete of a known node — `prev` pointer eliminates the need to find the predecessor
- O(1) insert and delete at both head and tail with sentinel nodes or head/tail pointers
- Python's `collections.deque` is implemented as a doubly linked list of fixed-size blocks
- Essential for LRU cache: move a node to the front in O(1) by splicing it out and reinserting

**Tricky points:**
- Every insertion and deletion must update both `next` and `prev` — missing one creates a corrupted list
- Sentinel (dummy) head and tail nodes eliminate special-case handling for empty lists and boundary operations
- Memory cost is higher than singly linked — two pointers per node instead of one
- Traversal in reverse is O(n) but does not require a second pass from the head
- `collections.deque` does not expose individual node references — its O(1) deletion applies internally, not to Python-level objects

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Access by index | O(n) | O(n) |
| Search | O(n) | O(n) |
| Insert at head | O(1) | O(1) |
| Insert at tail | O(1) | O(1) |
| Insert at known position | O(1) | O(1) |
| Delete at known node | O(1) | O(1) |
| Delete by value | O(n) | O(n) |

Space complexity: O(n)

---

## What It Is

Imagine a train where each carriage has a door at both ends. To remove carriage number five, a conductor on a singly-linked train would have to start at the front, move through carriages one through four, and only then could reach the carriage before the one being removed — they need carriage four's front door to access carriage six. On a doubly-linked train, every carriage has a label showing exactly which carriage is directly in front and directly behind it. Removing carriage five means walking to it directly (if you already know where it is), reading "carriage four is behind me, carriage six is in front of me," disconnecting the appropriate doors, and rejoining four to six. No traversal from the front required.

This change might seem minor, but its practical consequences are significant. The most important use case is an LRU (Least Recently Used) cache. An LRU cache needs two capabilities: O(1) lookup (satisfied by a hash table) and O(1) "move this item to the most-recently-used position" (satisfied by a doubly linked list). When an item is accessed, you already have a reference to its node from the hash table, so you can splice it out of its current position and insert it at the head of the list — both operations O(1) because you have `prev` and `next` references without any search.

Doubly linked lists also underpin undo/redo systems and browser history. Both require navigating backward through a sequence — the `prev` pointer enables constant-time backward navigation. In an undo stack, when you undo an action, you step backward through the list; when you redo, you step forward. The list never needs to be traversed from scratch to find where you currently are.

---

## How It Actually Works

The structural addition is minimal: each node gains a `prev` field that points to the node before it in the sequence. The head node's `prev` is `None` (or points to a sentinel), and the tail node's `next` is `None` (or points to a sentinel). Every insertion and deletion must maintain both the `next` and `prev` links of the affected nodes and their immediate neighbours.

The sentinel node pattern is a clean way to eliminate boundary condition checks. Two dummy nodes — a sentinel head and a sentinel tail — are created at initialisation and never removed. Real nodes are always inserted between the two sentinels. This means that every real node always has a non-None `prev` and `next`, simplifying all insertion and deletion code to the same four-line pointer update: point the new node's neighbours at it, and point it at its neighbours.

```python
class Node:
    def __init__(self, key=None, value=None):
        self.key = key
        self.value = value
        self.prev = None
        self.next = None


class DoublyLinkedList:
    """Doubly linked list with sentinel head and tail nodes."""

    def __init__(self):
        # Sentinels — never hold real data
        self.head = Node()
        self.tail = Node()
        self.head.next = self.tail
        self.tail.prev = self.head
        self._length = 0

    def _insert_after(self, node, new_node):
        """Insert new_node immediately after node — O(1)."""
        new_node.prev = node
        new_node.next = node.next
        node.next.prev = new_node
        node.next = new_node
        self._length += 1

    def _remove(self, node):
        """Remove node from list — O(1). Caller must hold a reference to node."""
        node.prev.next = node.next
        node.next.prev = node.prev
        node.prev = None
        node.next = None
        self._length -= 1

    def append_front(self, key, value):
        """Add new node at front (after sentinel head) — O(1)."""
        new_node = Node(key, value)
        self._insert_after(self.head, new_node)
        return new_node

    def remove_back(self):
        """Remove and return the last real node (before sentinel tail) — O(1)."""
        if self._length == 0:
            return None
        last = self.tail.prev
        self._remove(last)
        return last

    def move_to_front(self, node):
        """Move an existing node to the front — O(1)."""
        self._remove(node)
        self._insert_after(self.head, node)
        self._length += 1  # _remove decremented; readd

    def to_list(self):
        result = []
        current = self.head.next
        while current is not self.tail:
            result.append((current.key, current.value))
            current = current.next
        return result


# LRU Cache using doubly linked list + hash table
class LRUCache:
    def __init__(self, capacity):
        self.capacity = capacity
        self.map = {}          # key -> Node
        self.dll = DoublyLinkedList()

    def get(self, key):
        if key not in self.map:
            return -1
        node = self.map[key]
        self.dll.move_to_front(node)
        return node.value

    def put(self, key, value):
        if key in self.map:
            node = self.map[key]
            node.value = value
            self.dll.move_to_front(node)
        else:
            if len(self.map) == self.capacity:
                evicted = self.dll.remove_back()
                del self.map[evicted.key]
            node = self.dll.append_front(key, value)
            self.map[key] = node


# Demonstration
cache = LRUCache(3)
cache.put(1, "one")
cache.put(2, "two")
cache.put(3, "three")
print(cache.dll.to_list())    # [(1, 'one'), (2, 'two'), (3, 'three')] — oldest at back

cache.get(1)                  # access key 1 — moves to front
print(cache.dll.to_list())    # [(1, 'one'), (3, 'three'), (2, 'two')]

cache.put(4, "four")          # evicts least recently used: key 2
print(cache.dll.to_list())    # [(4, 'four'), (1, 'one'), (3, 'three')]
```

---

## How It Connects

The singly linked list is the direct predecessor. Understanding why singly linked lists require O(n) deletion (must find the predecessor) makes the purpose of the `prev` pointer immediately clear — it is the specific, minimal addition that resolves that one weakness.

[[linked-lists|Linked Lists]]

Deques are the practical Python manifestation of doubly linked lists. `collections.deque` is implemented as a doubly linked list of fixed-size blocks, giving O(1) append and pop at both ends. Knowing the internal structure explains why deques have O(n) index access despite O(1) end operations.

[[deques|Deques]]

---

## Common Misconceptions

Misconception 1: "Doubly linked lists are twice as fast as singly linked lists."
Reality: The extra `prev` pointer does not speed up traversal or search — those remain O(n). The only operations that improve are deletion of a known node (which drops from O(n) to O(1)) and backward traversal (which becomes possible without restarting). The doubly linked list trades memory for that specific capability.

Misconception 2: "Python's `collections.deque` lets you delete arbitrary elements in O(1)."
Reality: `collections.deque` does not expose its internal nodes to Python code. You can remove by value with `deque.remove(x)`, but that is O(n) — it scans the list. The O(1) deletion that a doubly linked list enables is only accessible if you implement the list yourself and maintain node references directly, as in the LRU cache pattern above.

Misconception 3: "Using a doubly linked list always wastes too much memory to be practical."
Reality: Each extra pointer is one machine word (8 bytes on 64-bit). For structures that genuinely need O(1) arbitrary deletion — like an LRU cache tracking thousands of entries — the memory cost per node is negligible compared to the value being cached. The overhead is proportional to n and is factored into the O(n) space complexity.

---

## Why It Matters in Practice

The LRU cache is the canonical production use case. It appears in database buffer managers, CPU caches, CDN edge nodes, and application-level caching layers. Implementing it correctly requires a doubly linked list combined with a hash table — the hash table provides O(1) lookup of the node, and the doubly linked list provides O(1) repositioning. Any other combination degrades to O(n) for one of the two operations.

Operating system kernels use doubly linked lists pervasively to manage process queues, free-memory lists, and I/O buffers. The Linux kernel's `list_head` structure is one of the most widely used data structures in systems programming. In Python application code, the pattern surfaces in caching middleware, session management, and anywhere an ordered collection with O(1) removal of arbitrary elements is needed.

---

## Interview Angle

Common question forms:
- "Implement an LRU cache."
- "How would you implement O(1) deletion of an arbitrary element from a list?"
- "What is the difference between a singly and doubly linked list?"
- "Why does `collections.deque` have O(1) popleft but a Python list does not?"

Answer frame:
For the LRU cache question, immediately name the two components: a hash map for O(1) lookup and a doubly linked list for O(1) reordering. Describe the sentinel node pattern. Draw the node structure with `prev` and `next`, and trace through a `get` and `put` operation. For deletion questions, explain that the `prev` pointer eliminates the need to find the predecessor — the crux of why the doubly linked version is necessary.

---

## Related Notes

- [[linked-lists|Linked Lists]]
- [[deques|Deques]]
- [[hash-tables|Hash Tables]]
