---
title: 06 - Queues
description: A queue is a FIFO (First In, First Out) structure where elements are added at the back and removed from the front.
tags: [dsa, layer-10, queue, fifo]
status: draft
difficulty: beginner
layer: 10
domain: dsa
created: 2026-05-18
---

# Queues

> A queue enforces fairness — the first element to arrive is the first to be served, making it the natural model for any waiting-line problem in computing.

---

## Quick Reference

**Core idea:**
- FIFO: elements are dequeued in the same order they were enqueued
- Enqueue: add to the back. Dequeue: remove from the front.
- Use `collections.deque` in Python — O(1) both ends
- Never use `list.pop(0)` for a queue — it is O(n) due to element shifting
- `queue.Queue` provides the same structure with thread-safety for producer-consumer patterns

**Tricky points:**
- `list.pop(0)` is O(n), not O(1) — a common performance bug when building queues with lists
- `collections.deque` is O(n) for index access — do not use it if you need random access
- Priority queue is not a FIFO queue — it dequeues the highest priority element first
- Python's `heapq` is a min-heap; to simulate a max-heap, store negated priorities
- `queue.Queue` blocks by default when empty (for thread synchronisation) — use `get(block=False)` or `get(timeout=...)` when you want non-blocking behaviour

---

## Complexity

| Operation | Average | Worst |
|---|---|---|
| Enqueue (appendright) | O(1) | O(1) |
| Dequeue (popleft) | O(1) | O(1) |
| Peek front | O(1) | O(1) |
| Search | O(n) | O(n) |
| Access by index | O(n) | O(n) |

Space complexity: O(n)

---

## What It Is

Imagine a queue at a bank. The first person to arrive stands at the front; each new arrival joins the back. The teller calls the person at the front, serves them, and they leave. No matter how long the queue grows, everyone is guaranteed to be served in the order they arrived. The person who has waited longest is always served first. This fairness property — first come, first served — is exactly what a queue data structure enforces.

This pattern appears throughout computing wherever tasks or messages need to be processed in arrival order. When a web server receives multiple simultaneous requests, it places them in a queue and processes them one at a time. When print jobs are sent to a shared printer, they queue up and print in the order they were submitted. When a CPU is managing multiple runnable processes, a scheduling queue determines who runs next. In every case, the FIFO property ensures that no request is indefinitely skipped over in favour of later arrivals.

A priority queue is a generalisation where arrival order is replaced by priority level. The highest-priority element is dequeued first, regardless of when it arrived. A hospital triage system is the intuitive model: patients are not seen strictly in arrival order but in urgency order. In Python, `heapq` implements a priority queue using a min-heap — the smallest value is always dequeued first. Combining a priority with a timestamp (as a tiebreaker in the heap tuple) gives a structure that is both priority-aware and FIFO within each priority level.

---

## How It Actually Works

The key requirement for a queue is O(1) at both the enqueue (back) and dequeue (front) ends. A Python `list` satisfies O(1) append at the back but requires O(n) removal from the front because `list.pop(0)` shifts every remaining element one position to the left. `collections.deque` solves this by using a doubly linked list of fixed-size blocks. Its `append` method adds to the right in O(1), and its `popleft` method removes from the left in O(1) — exactly what a queue needs.

The `heapq` module provides a priority queue built on a list that is maintained in heap order. `heapq.heappush(heap, item)` adds an item in O(log n), and `heapq.heappop(heap)` removes and returns the smallest item in O(log n). Because Python's heapq is a min-heap, the element with the lowest value (or the lowest first element in a tuple) is always dequeued first. Storing tuples of `(priority, item)` is the standard pattern.

```python
from collections import deque
import heapq
import queue

# ---- Standard FIFO queue using deque ----
q = deque()
q.append("first")       # enqueue — O(1)
q.append("second")
q.append("third")

front = q[0]            # peek front — O(1) for deque ends, O(n) for middle
print(front)            # "first"

item = q.popleft()      # dequeue — O(1)
print(item)             # "first"
print(q)                # deque(['second', 'third'])


# ---- Why list.pop(0) is wrong for queues ----
lst = [1, 2, 3, 4, 5]
lst.pop(0)  # O(n) — shifts every remaining element left; never use as dequeue


# ---- BFS using a queue ----
def bfs(graph, start):
    visited = set([start])
    q = deque([start])
    order = []
    while q:
        node = q.popleft()      # dequeue from front
        order.append(node)
        for neighbour in graph.get(node, []):
            if neighbour not in visited:
                visited.add(neighbour)
                q.append(neighbour)  # enqueue at back
    return order

graph = {0: [1, 2], 1: [3, 4], 2: [5], 3: [], 4: [], 5: []}
print(bfs(graph, 0))  # [0, 1, 2, 3, 4, 5]


# ---- Priority queue using heapq (min-heap) ----
pq = []
heapq.heappush(pq, (3, "low priority"))
heapq.heappush(pq, (1, "high priority"))
heapq.heappush(pq, (2, "medium priority"))

while pq:
    priority, task = heapq.heappop(pq)   # always returns minimum priority
    print(f"Processing: {task} (priority {priority})")
# high priority (1), medium priority (2), low priority (3)


# ---- Priority queue with FIFO tiebreaker ----
import itertools
counter = itertools.count()  # unique sequence numbers

pq2 = []
heapq.heappush(pq2, (2, next(counter), "task A"))
heapq.heappush(pq2, (2, next(counter), "task B"))  # same priority as A
heapq.heappush(pq2, (1, next(counter), "task C"))

while pq2:
    pri, seq, task = heapq.heappop(pq2)
    print(f"{task} (priority={pri}, seq={seq})")
# task C (priority=1), task A (priority=2, arrived first), task B (priority=2)


# ---- Thread-safe queue for producer-consumer ----
import threading

task_queue = queue.Queue(maxsize=5)

def producer():
    for i in range(10):
        task_queue.put(f"task-{i}")   # blocks if queue is full

def consumer():
    while True:
        task = task_queue.get()       # blocks if queue is empty
        if task is None:
            break
        print(f"Consumed: {task}")
        task_queue.task_done()

t_consumer = threading.Thread(target=consumer, daemon=True)
t_consumer.start()

producer_thread = threading.Thread(target=producer)
producer_thread.start()
producer_thread.join()

task_queue.put(None)  # sentinel to stop consumer
task_queue.join()
```

---

## Visualizer

<iframe src="/visualizers/queue.html" style="width:100%;height:380px;border:none;border-radius:8px;" title="Queue Visualizer"></iframe>

---

## How It Connects

BFS (breadth-first search) is the algorithm most directly tied to the queue data structure — its correctness depends on visiting nodes in the order they are discovered, which is exactly the FIFO guarantee. Without a queue, BFS becomes DFS or an incorrect mixed traversal.

[[bfs|Breadth-First Search]]

Deques are a superset of queues — a deque supports O(1) operations at both ends, making it usable as both a queue and a stack. Understanding queues as the restricted single-direction case makes the deque's additional power clear.

[[deques|Deques]]

---

## Common Misconceptions

Misconception 1: "I can use a list as a queue in Python — it's simpler."
Reality: Using `list.append` for enqueue and `list.pop(0)` for dequeue appears to work correctly but is O(n) per dequeue. At scale, this turns a queue-based algorithm from O(n) to O(n²). `collections.deque` is the correct choice and is not meaningfully more complex to use.

Misconception 2: "A priority queue is a type of FIFO queue."
Reality: A priority queue abandons FIFO ordering entirely. Elements are dequeued based on priority, not insertion order. It is called a "queue" because it has the same enqueue/dequeue interface, but its ordering semantics are completely different.

Misconception 3: "`queue.Queue` is faster than `collections.deque` for single-threaded code."
Reality: `queue.Queue` adds locking overhead for thread safety, making it slower in single-threaded scenarios. Use `collections.deque` for single-threaded queue operations and `queue.Queue` only when multiple threads share the queue.

---

## Why It Matters in Practice

Queues are the backbone of asynchronous systems. Message brokers (RabbitMQ, Kafka, AWS SQS) are essentially distributed queues at massive scale. Task queues (Celery, RQ) allow web servers to offload time-consuming work to background workers while immediately returning a response to the user. Rate limiters and request buffers in API gateways are queues. The FIFO property ensures fairness and order preservation across all of these systems.

In algorithms, BFS — which underpins shortest-path finding in unweighted graphs, level-order tree traversal, and connectivity analysis — is correctly implemented only with a true queue. The performance difference between using `deque.popleft()` (O(1)) and `list.pop(0)` (O(n)) becomes the difference between an O(V + E) BFS and an O(V² + E) one.

---

## Interview Angle

Common question forms:
- "Implement a queue using two stacks."
- "Implement BFS on a graph."
- "Find the shortest path in an unweighted graph."
- "What Python data structure should you use to implement a queue, and why?"
- "Implement a task scheduler with priority levels."

Answer frame:
For the two-stacks queue, describe the lazy-transfer approach: enqueue always pushes to stack-one; dequeue pops from stack-two, and when stack-two is empty, pops all of stack-one onto stack-two (reversing the order). Amortized O(1) per operation. For the Python queue question, immediately name `collections.deque` and explain the O(n) cost of `list.pop(0)`. For BFS, sketch the loop: dequeue a node, process it, enqueue all unvisited neighbours.

---

## Related Notes

- [[stacks|Stacks]]
- [[deques|Deques]]
- [[bfs|Breadth-First Search]]
- [[heaps|Heaps and Priority Queues]]
