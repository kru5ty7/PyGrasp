---
title: 03 - Producer Consumer Pattern
description: The Producer-Consumer pattern decouples data production from data consumption using a thread-safe queue, allowing producers and consumers to operate at different speeds without blocking each other.
tags: [concurrency, producer-consumer, queue, threading, layer-7, lld]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# Producer Consumer Pattern

> The Producer-Consumer pattern uses a shared queue to decouple producers (who generate work) from consumers (who process it), allowing them to operate independently and at different speeds.

---

## Quick Reference

**Core idea:**
- **Producers** generate data/tasks and put them on a **shared queue**
- **Consumers** pull from the queue and process items independently
- The queue acts as a buffer: producers do not wait for consumers, consumers do not wait for producers
- `queue.Queue` in Python is thread-safe - no external locking needed
- The **poison pill** (sentinel value) signals consumers to shut down gracefully

**Tricky points:**
- Unbounded queues can consume unlimited memory if producers are faster than consumers - use `maxsize` to apply backpressure
- `queue.Queue.join()` blocks until all items are marked as done via `task_done()` - forgetting `task_done()` causes hangs
- Multiple producers and multiple consumers scale independently
- For asyncio, use `asyncio.Queue` instead of `queue.Queue`

---

## What It Is

Think of a restaurant kitchen. Waiters (producers) take orders and clip them to the order rail (queue). Cooks (consumers) pull orders from the rail and prepare meals. Waiters do not wait for cooks to finish before taking new orders. Cooks do not wait for waiters to place orders before starting on the current one. The rail decouples them. If three waiters place orders quickly, the rail holds the backlog. If cooks are fast, they wait for the next order to appear.

The Producer-Consumer pattern is the software equivalent. One or more producer threads generate work items (log entries, web requests, data records) and place them on a thread-safe queue. One or more consumer threads pull items from the queue and process them. The queue provides built-in synchronization: producers block when the queue is full (backpressure), consumers block when the queue is empty (waiting for work).

This pattern is the foundation of work distribution systems: task queues (Celery), log processors, data pipelines, and event-driven architectures. It naturally parallelizes work and handles speed mismatches between production and consumption.

---

## How It Actually Works

Python's `queue.Queue` is a thread-safe FIFO queue backed by `collections.deque` with a `threading.Lock` and `threading.Condition` for synchronization. `put()` adds an item (blocks if full). `get()` retrieves an item (blocks if empty). `task_done()` signals that a retrieved item has been fully processed. `join()` blocks until all items have been processed.

```python
import queue
import threading
import time
import random
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from typing import Any


SENTINEL = object()  # poison pill to signal shutdown


@dataclass
class Task:
    id: int
    data: str


def producer(q: queue.Queue, producer_id: int, num_tasks: int) -> None:
    """Generates tasks and puts them on the queue."""
    for i in range(num_tasks):
        task = Task(id=producer_id * 1000 + i, data=f"data-{i}")
        q.put(task)
        print(f"[P{producer_id}] Produced task {task.id}")
        time.sleep(random.uniform(0.01, 0.05))  # simulate work

    print(f"[P{producer_id}] Done producing")


def consumer(q: queue.Queue, consumer_id: int) -> int:
    """Pulls tasks from the queue and processes them."""
    processed = 0
    while True:
        task = q.get()  # blocks until item available

        if task is SENTINEL:
            q.task_done()
            print(f"[C{consumer_id}] Received shutdown signal")
            break

        # Process the task
        time.sleep(random.uniform(0.02, 0.08))  # simulate processing
        print(f"[C{consumer_id}] Processed task {task.id}")
        processed += 1
        q.task_done()  # signal completion

    return processed


# Multiple producers, multiple consumers
work_queue: queue.Queue = queue.Queue(maxsize=10)  # backpressure at 10 items
num_producers = 2
num_consumers = 3
tasks_per_producer = 5

producer_threads = []
consumer_threads = []

# Start consumers first (they block waiting for work)
for i in range(num_consumers):
    t = threading.Thread(target=consumer, args=(work_queue, i))
    t.start()
    consumer_threads.append(t)

# Start producers
for i in range(num_producers):
    t = threading.Thread(target=producer, args=(work_queue, i, tasks_per_producer))
    t.start()
    producer_threads.append(t)

# Wait for all producers to finish
for t in producer_threads:
    t.join()

# Send shutdown sentinel for each consumer
for _ in range(num_consumers):
    work_queue.put(SENTINEL)

# Wait for all consumers to finish
for t in consumer_threads:
    t.join()

print("All work complete")


# Real-world: log processing pipeline
class LogProcessor:
    def __init__(self, num_workers: int = 4, queue_size: int = 1000):
        self._queue: queue.Queue = queue.Queue(maxsize=queue_size)
        self._workers: list[threading.Thread] = []
        self._num_workers = num_workers

    def start(self) -> None:
        for i in range(self._num_workers):
            t = threading.Thread(target=self._worker, args=(i,), daemon=True)
            t.start()
            self._workers.append(t)

    def submit(self, log_entry: str) -> None:
        """Called by application code to submit logs."""
        self._queue.put(log_entry)

    def _worker(self, worker_id: int) -> None:
        while True:
            entry = self._queue.get()
            if entry is SENTINEL:
                self._queue.task_done()
                break
            # Process: parse, filter, write to storage
            print(f"[Worker {worker_id}] {entry}")
            self._queue.task_done()

    def shutdown(self) -> None:
        for _ in self._workers:
            self._queue.put(SENTINEL)
        self._queue.join()
        for t in self._workers:
            t.join()

processor = LogProcessor(num_workers=2)
processor.start()
for i in range(5):
    processor.submit(f"Log entry {i}: request processed")
processor.shutdown()
```

---

<iframe src="/static/visualizers/producer-consumer-pattern.html" width="100%" height="440px" style="border:none;border-radius:6px;"></iframe>

---

## How It Connects

The Producer-Consumer pattern relies on thread-safe queues for synchronization. Understanding `queue.Queue`'s blocking behavior is essential.

[[thread-safe-queues|Thread Safe Queues]]

[[thread-safety-basics|Thread Safety Basics]]

The pattern decouples producers from consumers, following the same principle as the Observer pattern (event source does not know about event handlers) but with a queue as an intermediary buffer.

[[observer-pattern|Observer Pattern]]

For async applications, `asyncio.Queue` provides the same pattern for coroutines instead of threads.

[[asyncio-queues|Asyncio Queues]]

---

## Common Misconceptions

Misconception 1: "Producers and consumers must run at the same speed."
Reality: The queue absorbs speed differences. Fast producers fill the queue; slow consumers drain it. `maxsize` provides backpressure: when the queue is full, producers block until consumers make room. This self-regulating behavior is one of the pattern's key benefits.

Misconception 2: "You need complex synchronization to implement Producer-Consumer."
Reality: In Python, `queue.Queue` handles all the synchronization internally. You call `put()` and `get()`. No manual locking, no condition variables, no semaphores. The complexity is encapsulated inside the queue implementation.

---

## Why It Matters in Practice

Producer-Consumer is the foundation of Celery, RQ, and every task queue system. Web requests (producers) generate tasks, and workers (consumers) process them asynchronously. Log aggregation systems use this pattern: application code produces log entries, and background workers consume them to write to Elasticsearch or S3.

Understanding this pattern also helps you design data pipelines. A pipeline is a chain of producer-consumer stages: stage 1 produces parsed data, stage 2 consumes and transforms it, producing enriched data for stage 3 to consume and store.

---

## Interview Angle

Common question forms:
- "Explain the Producer-Consumer pattern."
- "How do you gracefully shut down a producer-consumer system?"
- "What happens if producers are faster than consumers?"

Answer frame:
Define the pattern: producers -> queue -> consumers. Show `queue.Queue` with `put()`, `get()`, `task_done()`. Explain the poison pill for shutdown. Discuss backpressure via `maxsize`. Mention real-world uses (Celery, log processors). Connect to thread-safe queues as the enabling mechanism.

---

## Related Notes

- [[thread-safe-queues|Thread Safe Queues]]
- [[thread-safety-basics|Thread Safety Basics]]
- [[observer-pattern|Observer Pattern]]
- [[asyncio-queues|Asyncio Queues]]
- [[design-patterns-overview|Design Patterns Overview]]
