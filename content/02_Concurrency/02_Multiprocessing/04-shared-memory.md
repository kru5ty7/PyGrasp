---
title: Shared Memory
description: "Python's `multiprocessing.shared_memory` (3.8+) allows multiple processes to access the same memory block without pickling — a `SharedMemory` object wraps a named OS shared memory segment that any process can attach to; used with NumPy arrays for zero-copy data sharing between worker processes."
tags: [shared-memory, multiprocessing, SharedMemory, numpy, zero-copy, layer-2, concurrency]
status: draft
difficulty: advanced
layer: 2
domain: concurrency
created: 2026-05-17
---

# Shared Memory

> Python's `multiprocessing.shared_memory` (3.8+) allows multiple processes to access the same memory block without pickling — a `SharedMemory` object wraps a named OS shared memory segment that any process can attach to; used with NumPy arrays for zero-copy data sharing between worker processes.

---

## Quick Reference

**Core idea:**
- `shm = shared_memory.SharedMemory(create=True, size=n_bytes)` — creates a named shared memory block
- `shm.name` — the OS-level name; pass to child processes so they can attach to the same block
- `shm_child = shared_memory.SharedMemory(name=shm.name, create=False)` — attach to existing block in another process
- `shm.buf` — a `memoryview` of the raw bytes; wrap with `numpy.ndarray(shape, dtype, buffer=shm.buf)` for array access
- `shm.close()` — detach from the block; `shm.unlink()` — delete the OS block (only by the creator)
- `multiprocessing.managers.SharedMemoryManager` — context manager that tracks and cleans up all shared memory blocks

**Tricky points:**
- Shared memory is **not protected by any lock** — concurrent writes from multiple processes cause data corruption; use a `multiprocessing.Lock` or `Value.get_lock()` for synchronized access
- The creator must call `shm.unlink()` after all processes have detached — otherwise the OS block persists until reboot (a resource leak)
- `shared_memory.SharedMemory` (Python 3.8+) is process-safe but not thread-safe for the management operations (create/close/unlink) — the buffer access is direct memory access with no Python overhead
- `multiprocessing.Value('d', 0.0)` and `Array('d', n)` are older shared memory interfaces — simpler but only support ctypes scalar types and fixed-size arrays; `shared_memory` supports arbitrary memory layouts
- On Windows, shared memory names must not start with `/`; on Linux they are files in `/dev/shm`; `SharedMemory` abstracts this difference

---

## What It Is

Think of a whiteboard in a shared conference room. Instead of photocopying a document and distributing it to everyone's office (pickling), you write the data on the whiteboard once and anyone can walk into the conference room to read or update it. Shared memory is that whiteboard: a single memory region accessible by multiple processes without copying.

For large NumPy arrays, pickling is prohibitively slow. A 1 GB array takes seconds to pickle and unpickle, and the data must be copied twice (once to serialize, once to deserialize). With shared memory, the array is allocated once in shared memory; all worker processes attach and access the same underlying bytes — no copy, no pickle, O(1) setup.

The tradeoff is explicit lifecycle management (unlike regular Python objects, shared memory does not use reference counting) and the absence of automatic synchronization (unlike `Queue`, which serializes access).

---

## How It Actually Works

`shared_memory.SharedMemory(create=True, size=n_bytes)`:
- Creates an OS-level shared memory segment (POSIX `shm_open` + `mmap` on Linux/macOS; `CreateFileMapping` on Windows)
- Returns a Python object wrapping the segment with a `buf` (memoryview) attribute
- `shm.name` is an auto-generated name (e.g., `psm_7a3f5b2d`) — can be passed to other processes

NumPy integration:

```python
# In the parent process:
import numpy as np
from multiprocessing import shared_memory

arr = np.array([1.0, 2.0, 3.0, 4.0])
shm = shared_memory.SharedMemory(create=True, size=arr.nbytes)
shared_arr = np.ndarray(arr.shape, dtype=arr.dtype, buffer=shm.buf)
shared_arr[:] = arr[:]  # copy data into shared memory

# Pass shm.name and arr.shape/arr.dtype to workers

# In worker processes:
def worker(shm_name, shape, dtype):
    shm = shared_memory.SharedMemory(name=shm_name, create=False)
    arr = np.ndarray(shape, dtype=dtype, buffer=shm.buf)
    result = np.sum(arr)  # zero-copy read
    shm.close()
    return result

# Cleanup in parent:
shm.close()
shm.unlink()
```

`SharedMemoryManager`:
```python
from multiprocessing.managers import SharedMemoryManager

with SharedMemoryManager() as smm:
    shm = smm.SharedMemory(size=1024)
    # All blocks allocated via smm are automatically cleaned up
    run_workers(shm.name)
```

---

## How It Connects

`multiprocessing.Value` and `Array` are the older shared memory primitives — `shared_memory` is more flexible for arbitrary data layouts.
[[inter-process-communication|Inter-Process Communication]]

Using shared memory with a process pool avoids the pickle overhead that `Pool.map()` incurs for large array arguments.
[[process-pool|Process Pool]]

---

## Common Misconceptions

Misconception 1: "Shared memory automatically synchronizes access between processes."
Reality: Shared memory provides zero-copy data sharing but no synchronization. Multiple processes writing to overlapping regions simultaneously cause data corruption. Use a `multiprocessing.Lock`, `multiprocessing.Value.get_lock()`, or partition the array so each process writes to a non-overlapping region.

Misconception 2: "Forgetting `shm.unlink()` is a minor issue — the OS cleans it up."
Reality: On Linux, POSIX shared memory objects persist in `/dev/shm` until explicitly deleted with `unlink()` or the system reboots. Leaking shared memory blocks accumulates `/dev/shm` usage, eventually filling the tmpfs filesystem. Always call `unlink()` in the creating process, or use `SharedMemoryManager` to handle cleanup automatically.

---

## Why It Matters in Practice

Machine learning preprocessing: a large training dataset (100 MB–10 GB NumPy array) can be loaded into shared memory once, then all worker processes access it without copying. `Pool.map(train_batch, batch_indices)` with the array in shared memory gives each worker direct access.

Read-many, write-once pattern: the parent loads data into shared memory, workers read-only process it in parallel. Since no worker writes to the shared array, no locks are needed. This is the safest and most common use pattern.

Write partitioning: split the output array into `n` non-overlapping partitions, one per worker. Each worker writes only to its partition — no locks needed since writes are to separate memory regions. Workers write results directly to shared output memory, avoiding result pickling entirely.

---

## Interview Angle

Common question forms:
- "How do you share large arrays between processes without copying?"
- "What is `multiprocessing.shared_memory`?"

Answer frame: `shared_memory.SharedMemory` creates an OS shared memory segment accessible by multiple processes without pickling. The creator passes `shm.name` to workers; workers attach with `SharedMemory(name=..., create=False)`. Wrap `shm.buf` with `numpy.ndarray` for array access — zero-copy. Always protect concurrent writes with a `multiprocessing.Lock` — shared memory has no built-in synchronization. Always call `unlink()` in the creator to release the OS resource.

---

## Related Notes

- [[inter-process-communication|Inter-Process Communication]]
- [[process-pool|Process Pool]]
- [[multiprocessing-module|The multiprocessing Module]]
