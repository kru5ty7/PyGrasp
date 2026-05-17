---
title: 07 - Thread-Safe Queues
description: "Python's `queue.Queue` is a thread-safe FIFO data structure — its `put()` and `get()` operations use internal locks and condition variables to safely coordinate producer and consumer threads; `task_done()` and `join()` enable completion signaling for pipeline patterns."
tags: [queue, thread-safe, producer-consumer, Queue, LifoQueue, PriorityQueue, layer-2, concurrency]
status: draft
difficulty: beginner
layer: 2
domain: concurrency
created: 2026-05-17
---

# Thread-Safe Queues

> Python's `queue.Queue` is a thread-safe FIFO data structure — its `put()` and `get()` operations use internal locks and condition variables to safely coordinate producer and consumer threads; `task_done()` and `join()` enable completion signaling for pipeline patterns.

---

## Quick Reference

**Core idea:**
- `queue.Queue(maxsize=0)` — FIFO queue; `maxsize=0` means unlimited; positive `maxsize` blocks `put()` when full
- `q.put(item)` — adds item; blocks if queue is full (`maxsize > 0`)
- `q.get()` — removes and returns item; blocks if queue is empty
- `q.put_nowait(item)` / `q.get_nowait()` — raise `queue.Full` / `queue.Empty` if blocked; non-blocking versions
- `q.task_done()` — signal that a previously `get()`-ted item has been processed
- `q.join()` — blocks until all items have been `get()`-ted and `task_done()` called for each
- `queue.LifoQueue` — LIFO (stack); `queue.PriorityQueue` — lowest-value item is retrieved first

**Tricky points:**
- `queue.Queue` is the recommended way to communicate between threads — it eliminates the need for explicit locking in producer-consumer patterns
- A `sentinel` value (e.g., `None`) is the standard way to signal worker threads to stop: producer puts `None`, consumer exits when it receives `None`
- `task_done()` must be called exactly once per `get()` — calling it more times raises `ValueError`; not calling it causes `q.join()` to block forever
- `q.empty()` is unreliable in a multithreaded context — another thread can add or remove items between the check and the subsequent `get()` — always use `get()` with exception handling instead of `empty()` + `get()`
- `collections.deque.appendleft`/`pop` is thread-safe for single operations but not for sequences — use `queue.Queue` for coordinated producer-consumer patterns

---

## What It Is

Think of a conveyor belt in a factory. Workers upstream (producers) place items on the belt. Workers downstream (consumers) pick items off the belt and process them. The belt buffers the items — producers don't need to wait for a consumer to be ready, and consumers don't need to wait for a producer to finish. The belt handles the coordination: "is there room to add?" and "is there something to take?" A thread-safe queue is this conveyor belt.

Without a thread-safe queue, a producer-consumer pattern requires explicit locking around a shared list, condition variables for "not empty" and "not full" signaling, and careful management of all edge cases. `queue.Queue` encapsulates all of this. The producer calls `put()` and the consumer calls `get()` — thread safety is handled internally.

---

## How It Actually Works

`queue.Queue` internals (simplified):

```python
class Queue:
    def __init__(self, maxsize=0):
        self._queue = collections.deque()
        self._mutex = threading.Lock()
        self._not_empty = threading.Condition(self._mutex)
        self._not_full = threading.Condition(self._mutex)
        self._all_tasks_done = threading.Condition(self._mutex)
        self.unfinished_tasks = 0
    
    def put(self, item):
        with self._not_full:
            while len(self._queue) >= self.maxsize and self.maxsize > 0:
                self._not_full.wait()
            self._queue.append(item)
            self.unfinished_tasks += 1
            self._not_empty.notify()
    
    def get(self):
        with self._not_empty:
            while not self._queue:
                self._not_empty.wait()
            item = self._queue.popleft()
            self._not_full.notify()
            return item
    
    def task_done(self):
        with self._all_tasks_done:
            self.unfinished_tasks -= 1
            if self.unfinished_tasks == 0:
                self._all_tasks_done.notify_all()
    
    def join(self):
        with self._all_tasks_done:
            while self.unfinished_tasks:
                self._all_tasks_done.wait()
```

Producer-consumer with shutdown signaling:

```python
from queue import Queue
import threading

q = Queue()
SENTINEL = None

def producer():
    for item in data_source():
        q.put(item)
    q.put(SENTINEL)  # signal workers to stop

def consumer():
    while True:
        item = q.get()
        if item is SENTINEL:
            q.put(SENTINEL)  # re-put for other consumers
            break
        process(item)
        q.task_done()
```

---

## How It Connects

`queue.Queue` is built on `threading.Condition` (which uses `threading.Lock`) — it is the practical high-level tool that replaces manual lock management for producer-consumer patterns.
[[locks|Locks]]

`concurrent.futures.ThreadPoolExecutor` uses a queue internally to distribute tasks to worker threads — understanding `queue.Queue` explains how thread pools coordinate work.
[[thread-pool-executor|ThreadPoolExecutor]]

---

## Common Misconceptions

Misconception 1: "Using `q.empty()` before `q.get()` is safe."
Reality: `q.empty()` checks the queue state and returns, then `q.get()` is called — between these two operations, another thread may have `get()`-ted the last item. Use `q.get(block=True)` (default) and let it block, or `q.get(block=False)` with a `try/except queue.Empty`.

Misconception 2: "`queue.Queue` is slower than a list with a lock."
Reality: For typical use patterns, `queue.Queue` is more correct and its overhead is acceptable. The internal `collections.deque` provides O(1) append and popleft. The lock overhead is the same as you would implement manually. The condition variable signaling (blocking producer when full, blocking consumer when empty) is more efficient than busy-waiting.

---

## Why It Matters in Practice

The producer-consumer pipeline is the dominant pattern for thread coordination. A main thread reads data (producer) and posts items to a queue; worker threads consume from the queue and process items. `queue.Queue` with `maxsize` provides backpressure — the producer naturally slows down when workers cannot keep up.

`q.join()` is the clean shutdown mechanism: the main thread does `q.join()` after all items are put, and it blocks until all workers have called `task_done()` for each item. This ensures no items are left unprocessed before the program exits.

Multiple queues: complex pipelines have multiple stages connected by queues. Stage 1 produces to Queue1; Stage 2 consumes Queue1 and produces to Queue2; Stage 3 consumes Queue2. Each stage is a pool of worker threads. `queue.Queue` connects the stages with buffering and backpressure.

---

## Interview Angle

Common question forms:
- "How do you communicate between threads in Python?"
- "What is `task_done()` for?"

Answer frame: `queue.Queue` is the standard thread-safe communication channel between threads. `put()` adds (blocks if full); `get()` removes (blocks if empty). `task_done()` signals that a `get()`-ted item was processed; `q.join()` blocks until all items are `task_done()`. Use `None` (or a sentinel object) to signal worker threads to shut down. Avoid `q.empty()` checks — use blocking `get()` and catch `queue.Empty` for non-blocking access.

---

## Related Notes

- [[locks|Locks]]
- [[race-conditions|Race Conditions]]
- [[thread-pool-executor|ThreadPoolExecutor]]
- [[asyncio-queues|Asyncio Queues]]
