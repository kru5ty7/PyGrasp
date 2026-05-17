---
title: Inter-Process Communication
description: Inter-process communication (IPC) is how separate processes exchange data — Python's `multiprocessing` provides Queues (FIFO, multi-producer/consumer), Pipes (bidirectional, two-endpoint), and Manager proxies (shared objects); all IPC serializes data with pickle since processes have isolated memory.
tags: [IPC, multiprocessing, Queue, Pipe, Manager, pickle, inter-process, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Inter-Process Communication

> Inter-process communication (IPC) is how separate processes exchange data — Python's `multiprocessing` provides Queues (FIFO, multi-producer/consumer), Pipes (bidirectional, two-endpoint), and Manager proxies (shared objects); all IPC serializes data with pickle since processes have isolated memory.

---

## Quick Reference

**Core idea:**
- `multiprocessing.Queue()` — thread- and process-safe FIFO; `put()` / `get()`; suitable for multiple producers/consumers
- `multiprocessing.Pipe()` — returns `(conn1, conn2)`; `conn.send(obj)` / `conn.recv()`; faster than Queue for point-to-point
- `multiprocessing.Manager()` — creates a server process hosting proxy objects (dict, list, Value, Array); all accesses go through IPC to the server
- `multiprocessing.Value('i', 0)` / `multiprocessing.Array('d', [0.0] * n)` — shared memory objects with a ctypes type
- All IPC mechanisms serialize/deserialize with `pickle` (except shared memory)

**Tricky points:**
- `multiprocessing.Queue` is slower than `threading.Queue` — it uses OS pipes internally and pickle serializes every object
- `Pipe()` connection objects are not thread-safe — only one thread should use each end at a time in a multi-threaded process
- `Manager()` proxy objects are much slower than regular objects — every attribute access or method call involves IPC to the manager server process
- `multiprocessing.Value` / `Array` use shared memory (no pickle) — but require explicit locking for safe concurrent access (they have an internal `get_lock()`)
- Sending large objects via Queue or Pipe copies them — for large NumPy arrays, use `multiprocessing.shared_memory` (Python 3.8+) to avoid copying

---

## What It Is

Think of two offices in different buildings trying to collaborate. They cannot walk into each other's office and use each other's equipment — they have separate spaces. To share information, they must either courier documents (Queue/Pipe — copy the data across), or work on a shared Google Drive (Manager — a central server both access through their browsers), or share a specific filing cabinet placed in a neutral hallway (shared memory). Each method has different speed and complexity tradeoffs.

Python processes have completely isolated memory — one process cannot read another's variables directly. All data exchange requires crossing the process boundary, which involves serialization (pickle), OS pipe or socket transfer, and deserialization on the other side. This is fundamentally different from thread communication, where threads share memory directly and communication is a pointer dereference.

---

## How It Actually Works

`multiprocessing.Queue` internals:
- Built on an OS pipe with a background thread to feed items to the pipe
- `put(obj)`: pickles `obj`, sends bytes through the pipe, increments semaphore
- `get()`: acquires semaphore, reads bytes from pipe, unpickles
- Thread-safe and process-safe (uses OS-level synchronization)

`multiprocessing.Pipe()`:
```python
parent_conn, child_conn = multiprocessing.Pipe()
# Parent process:
parent_conn.send({"data": [1, 2, 3]})
result = parent_conn.recv()

# Child process:
item = child_conn.recv()
child_conn.send(process(item))
```
`Pipe` is lower-level and faster than `Queue` — it has no internal thread, no semaphore. Objects are pickled and sent through an OS pipe. `duplex=True` (default) allows send/recv from both ends; `duplex=False` makes it one-directional.

`multiprocessing.Manager()`:
```python
with multiprocessing.Manager() as mgr:
    shared_dict = mgr.dict()
    shared_list = mgr.list()
    # Pass to child processes — they access via IPC proxies
```
Every operation on `shared_dict` is a remote procedure call to the manager server process. Very flexible (supports arbitrary shared objects) but 100-1000x slower than local operations.

`multiprocessing.shared_memory` (Python 3.8+):
```python
from multiprocessing import shared_memory
import numpy as np

shm = shared_memory.SharedMemory(create=True, size=1000 * 8)
arr = np.ndarray((1000,), dtype=np.float64, buffer=shm.buf)
# Share shm.name with child processes; they attach to the same memory block
```

---

## How It Connects

`multiprocessing.Queue` and `Pipe` are built on the `multiprocessing` module's process management — they are the communication backbone for `Pool.map()` worker coordination.
[[multiprocessing-module|The multiprocessing Module]]

Shared memory avoids pickle overhead for large arrays — relevant when working with NumPy arrays in multiprocessing to avoid copying gigabytes of data.
[[shared-memory|Shared Memory]]

---

## Common Misconceptions

Misconception 1: "`multiprocessing.Queue` is the same as `queue.Queue`."
Reality: `queue.Queue` (threading) uses in-process locking — objects are shared by reference, no serialization. `multiprocessing.Queue` uses OS pipes and pickle — objects are copied via serialization. The APIs look similar, but performance characteristics and object compatibility requirements are very different.

Misconception 2: "`Manager().dict()` is a good general-purpose shared data structure."
Reality: `Manager` proxies have very high overhead — every operation is an IPC call to the manager server process. For small amounts of infrequently updated state, it is acceptable. For high-frequency updates or large data structures, it is a bottleneck. Prefer: shared memory (for arrays), return values from `Pool.map()` (for one-shot computation), or queue-based communication.

---

## Why It Matters in Practice

Choosing the right IPC mechanism:
- Point-to-point, low frequency, complex objects: `Pipe()`
- Multi-producer/multi-consumer, moderate frequency: `Queue()`
- Infrequent shared mutable state: `Manager().dict()`
- Large arrays, high frequency: `shared_memory` + NumPy
- One-shot results: `Pool.map()` return values

Queue-based worker pattern with results:

```python
task_queue = multiprocessing.Queue()
result_queue = multiprocessing.Queue()

def worker(tasks, results):
    for task in iter(tasks.get, SENTINEL):
        results.put(process(task))

workers = [Process(target=worker, args=(task_queue, result_queue)) for _ in range(4)]
```

---

## Interview Angle

Common question forms:
- "How do processes communicate in Python?"
- "What is the difference between Queue and Pipe in multiprocessing?"

Answer frame: Processes have isolated memory — IPC mechanisms serialize data with pickle and transfer via OS pipes. `Queue`: multi-producer/consumer FIFO, slower, higher overhead. `Pipe`: two-endpoint bidirectional, faster for point-to-point. `Manager`: proxy objects hosted in a server process, very flexible but very slow. Shared memory: zero-copy for ctypes arrays and NumPy. All except shared memory pickle objects on send and unpickle on receive.

---

## Related Notes

- [[multiprocessing-module|The multiprocessing Module]]
- [[shared-memory|Shared Memory]]
- [[processes|Processes in Python]]
- [[thread-safe-queues|Thread-Safe Queues]]
