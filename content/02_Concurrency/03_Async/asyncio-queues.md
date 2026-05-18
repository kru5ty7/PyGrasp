---
title: 11 - Asyncio Queues
description: "`asyncio.Queue` is a coroutine-friendly FIFO data structure  -  `await queue.put(item)` and `await queue.get()` yield to the event loop instead of blocking OS threads; used for producer-consumer patterns within asyncio programs; `LifoQueue` and `PriorityQueue` are available as well."
tags: [asyncio, Queue, LifoQueue, PriorityQueue, producer-consumer, async-queue, layer-2, concurrency]
status: draft
difficulty: beginner
layer: 2
domain: concurrency
created: 2026-05-17
---

# Asyncio Queues

> `asyncio.Queue` is a coroutine-friendly FIFO data structure  -  `await queue.put(item)` and `await queue.get()` yield to the event loop instead of blocking OS threads; used for producer-consumer patterns within asyncio programs; `LifoQueue` and `PriorityQueue` are available as well.

---

## Quick Reference

**Core idea:**
- `queue = asyncio.Queue(maxsize=0)`  -  FIFO queue; `maxsize=0` means unlimited
- `await queue.put(item)`  -  adds item; if queue is full, yields to event loop until space is available
- `await queue.get()`  -  removes and returns item; if queue is empty, yields to event loop until item is available
- `queue.put_nowait(item)` / `queue.get_nowait()`  -  non-blocking; raise `asyncio.QueueFull` / `asyncio.QueueEmpty` if blocked
- `queue.task_done()` / `await queue.join()`  -  signal completion and wait for all items to be processed

**Tricky points:**
- `asyncio.Queue` is NOT thread-safe  -  only use it within an asyncio event loop; do not `put()`/`get()` from different OS threads; for cross-thread communication use `loop.call_soon_threadsafe()` or `asyncio.run_coroutine_threadsafe()`
- `queue.join()` blocks the current coroutine until `task_done()` has been called for every `get()`-ted item; not calling `task_done()` exactly once per `get()` causes `join()` to hang or raises `ValueError`
- Unlike `threading.Queue`, `asyncio.Queue.put()` returns a coroutine and must be `await`-ed  -  forgetting `await` does nothing and silently drops the item
- `queue.empty()` and `queue.full()` are unreliable in concurrent code  -  another coroutine may change the state between the check and the action; always use `get_nowait()`/`put_nowait()` with exception handling for non-blocking access

---

## What It Is

Think of `asyncio.Queue` as a conveyor belt in an async kitchen. The chef (producer coroutine) places dishes on the belt  -  if the belt is full, the chef waits (yields to event loop). The waiter (consumer coroutine) picks up dishes from the belt  -  if the belt is empty, the waiter waits (yields). Unlike `threading.Queue`, where waiting blocks an OS thread, `asyncio.Queue` waiting yields cooperative control to the event loop, allowing other coroutines to run.

The key distinction from `queue.Queue` (threading): `threading.Queue.get()` blocks an OS thread. `asyncio.Queue.get()` suspends a coroutine and lets the event loop run other coroutines. The first is O(1 thread) during the wait; the second is O(0 threads) during the wait.

---

## How It Actually Works

`asyncio.Queue` internals:

```python
class Queue:
    def __init__(self, maxsize=0):
        self._queue = collections.deque()
        self._getters = collections.deque()  # waiting get() coroutines
        self._putters = collections.deque()  # waiting put() coroutines
        self._unfinished_tasks = 0
        self._finished = asyncio.Event()
    
    async def put(self, item):
        while self.full():
            putter = self._loop.create_future()
            self._putters.append(putter)
            await putter  # yields until space is available
        self._put(item)
        self._notify_getters()
    
    async def get(self):
        while self.empty():
            getter = self._loop.create_future()
            self._getters.append(getter)
            await getter  # yields until item available
        return self._get()
```

When `put()` adds an item and there are waiting `get()` calls (futures in `_getters`), it sets the oldest getter's result, which schedules the waiting `get()` to resume in the next event loop iteration.

Producer-consumer with `asyncio.Queue`:

```python
async def producer(queue, items):
    for item in items:
        await queue.put(item)
        await asyncio.sleep(0)  # cooperative yield

async def consumer(queue):
    while True:
        item = await queue.get()
        if item is None:
            break
        await process(item)
        queue.task_done()

async def main():
    queue = asyncio.Queue(maxsize=10)
    await asyncio.gather(
        producer(queue, data),
        consumer(queue),
        consumer(queue),  # multiple consumers
    )
```

---

## How It Connects

`asyncio.Queue` is the async counterpart to `threading.Queue`  -  same producer-consumer pattern, but with coroutines instead of threads.
[[thread-safe-queues|Thread-Safe Queues]]

Asyncio Queues are often used in conjunction with `asyncio.gather` to run producer and consumer coroutines concurrently.
[[asyncio-gather|asyncio.gather and asyncio.wait]]

---

## Common Misconceptions

Misconception 1: "`asyncio.Queue` can be used across threads."
Reality: `asyncio.Queue` is only safe to use from coroutines running on the same event loop. Calling `await queue.put()` from a different OS thread will fail or cause race conditions  -  the queue's internal state is not protected by OS-level locks. For cross-thread communication, use `loop.call_soon_threadsafe(queue.put_nowait, item)` to schedule the put from the event loop's thread.

Misconception 2: "`asyncio.Queue.put()` without `await` silently works."
Reality: `queue.put(item)` returns a coroutine object without scheduling anything. Not `await`-ing it means the item is never added to the queue  -  the call does nothing. The coroutine object is created and immediately garbage collected. Always `await queue.put(item)`.

---

## Why It Matters in Practice

Rate-limited web scraping:
```python
async def scraper(url_queue, result_queue):
    while True:
        url = await url_queue.get()
        if url is None:
            break
        result = await fetch(url)
        await result_queue.put(result)
        url_queue.task_done()

async def main():
    url_queue = asyncio.Queue()
    result_queue = asyncio.Queue()
    
    for url in urls:
        await url_queue.put(url)
    for _ in range(5):
        await url_queue.put(None)  # sentinel for 5 workers
    
    await asyncio.gather(
        *[scraper(url_queue, result_queue) for _ in range(5)],
        collect_results(result_queue),
    )
```

5 consumer coroutines drain the URL queue concurrently  -  the `maxsize` of `url_queue` provides backpressure.

---

## Interview Angle

Common question forms:
- "What is `asyncio.Queue` and how does it differ from `queue.Queue`?"

Answer frame: `asyncio.Queue` is a coroutine-safe FIFO queue  -  `await queue.put()` and `await queue.get()` yield to the event loop when blocked (full/empty), rather than blocking an OS thread. It is NOT thread-safe (use `loop.call_soon_threadsafe` for cross-thread puts). Pattern: producer coroutines put items; consumer coroutines get and process; `queue.task_done()` + `await queue.join()` for completion signaling. `asyncio.LifoQueue` and `asyncio.PriorityQueue` are also available.

---

## Related Notes

- [[thread-safe-queues|Thread-Safe Queues]]
- [[asyncio-tasks|Asyncio Tasks]]
- [[asyncio-gather|asyncio.gather and asyncio.wait]]
- [[asyncio|Asyncio]]
