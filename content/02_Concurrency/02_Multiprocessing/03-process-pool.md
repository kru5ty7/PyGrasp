---
title: Process Pool
description: "A process pool is a pre-created set of worker processes that accept tasks from a queue — `multiprocessing.Pool` provides `map`, `apply_async`, and `starmap` to distribute work; worker startup cost is paid once, making pools efficient for many short tasks compared to creating a new process per task."
tags: [process-pool, multiprocessing, Pool, map, apply_async, starmap, layer-2, concurrency]
status: draft
difficulty: intermediate
layer: 2
domain: concurrency
created: 2026-05-17
---

# Process Pool

> A process pool is a pre-created set of worker processes that accept tasks from a queue — `multiprocessing.Pool` provides `map`, `apply_async`, and `starmap` to distribute work; worker startup cost is paid once, making pools efficient for many short tasks compared to creating a new process per task.

---

## Quick Reference

**Core idea:**
- `Pool(n)` — creates `n` worker processes; default `n = os.cpu_count()`
- `pool.map(fn, items)` — apply `fn` to each item, in parallel, return results in order (blocks until all done)
- `pool.starmap(fn, pairs)` — like `map` but unpacks each argument tuple: `fn(*pair)` for each pair
- `pool.apply_async(fn, args)` — submit one task asynchronously; returns `AsyncResult`; `.get()` retrieves result
- `pool.imap(fn, items)` — lazy iterator version of `map`; yields results as they complete (ordered); efficient for large iterables
- `pool.close()` → `pool.join()` — clean shutdown: no new tasks, wait for current tasks to finish

**Tricky points:**
- `pool.map()` chunks the input and sends chunks to workers — `chunksize` parameter controls chunking; larger chunks reduce IPC overhead but reduce parallelism granularity
- Worker initializer: `Pool(initializer=setup, initargs=(config,))` — `setup(config)` is called once in each worker process at startup; use to set up DB connections, load models, etc.
- `pool.terminate()` sends SIGTERM to workers immediately (no graceful finish) — use in `except` blocks or on error, not for normal shutdown
- The `with Pool(n) as pool:` context manager calls `pool.terminate()` on exit, not `pool.close()`+`pool.join()` — careful with unfinished tasks on exception
- `map_async().get(timeout)` raises `multiprocessing.TimeoutError` if workers don't finish in time; `.ready()` checks without blocking; `.successful()` checks if it completed without exception

---

## What It Is

Think of a task-based factory floor. Setting up a new station (starting a new process) takes time — moving equipment, configuring tools, briefing the worker. A pool is a factory floor where all stations are already set up. When a new order (task) arrives, an available station takes it immediately. The setup cost is paid once at factory opening (pool creation), not per order.

Creating a new `multiprocessing.Process` for every task incurs setup overhead (spawn: start a Python interpreter and import modules; fork: copy process memory). For a thousand small tasks, creating a thousand processes is wasteful. A pool of `cpu_count()` workers keeps processes alive and reuses them across tasks, amortizing the startup cost.

---

## How It Actually Works

`Pool(n)` implementation:
1. Creates `n` worker processes (via the platform start method)
2. Each worker runs an internal task loop: receive task from IPC queue, execute, send result back
3. The pool maintains an input task queue and a result queue

`pool.map(fn, items, chunksize=None)`:
- If `chunksize` is not specified, computed as `max(1, len(items) // (4 * n_workers))` — balances parallelism and overhead
- Items are pickled in chunks and sent to worker processes
- Workers pickle results and send back
- Results are collected and unpickled in order

`pool.apply_async(fn, args, callback=None, error_callback=None)`:
```python
result = pool.apply_async(fn, (arg,), callback=on_success, error_callback=on_error)
# Do other work...
value = result.get()  # blocks if not ready; raises exception if worker raised
```

Worker initializer pattern:
```python
def init_worker(db_url):
    global db_conn
    db_conn = connect(db_url)

def process_record(record):
    return db_conn.query(record)  # uses per-worker connection

with Pool(4, initializer=init_worker, initargs=(DB_URL,)) as pool:
    results = pool.map(process_record, records)
```

`imap` and `imap_unordered` for memory-efficient processing:
```python
with Pool(4) as pool:
    for result in pool.imap(process, large_iterable):
        save(result)  # processes results as they arrive
```

---

## How It Connects

`Pool` is built on `multiprocessing.Process` — each pool worker is a `Process`; the pool manages their lifecycle and task distribution.
[[multiprocessing-module|The multiprocessing Module]]

`concurrent.futures.ProcessPoolExecutor` wraps process pool functionality with a futures-based API — the modern alternative to `multiprocessing.Pool` for many use cases.
[[concurrent-futures|concurrent.futures]]

---

## Common Misconceptions

Misconception 1: "`Pool(os.cpu_count())` always gives maximum speedup."
Reality: Maximum speedup requires that: (1) work is CPU-bound, (2) the task is large enough to amortize pickling overhead, (3) there is enough work to keep all workers busy, and (4) the sequential portion (Amdahl's law) is small. For I/O-bound work, a process pool has more overhead than threads or asyncio with minimal benefit.

Misconception 2: "Pool workers can access the parent process's global variables."
Reality: Workers are separate processes — they do not share memory with the parent. Global variables set in the parent before `Pool()` creation are inherited via `fork` (Linux only) or must be passed explicitly. Changes to globals in workers are invisible to the parent. Use return values, `Queue`, or `Manager` for result communication.

---

## Why It Matters in Practice

Batch processing pattern: `pool.map(transform, large_list)` is the canonical one-liner for parallel batch processing. For very large lists, use `pool.imap(transform, large_list)` to process lazily without loading all results into memory simultaneously.

Chunksize tuning: the default chunksize may be suboptimal. For tasks with high IPC overhead (large arguments/results), larger chunks reduce overhead. For tasks with high variance in execution time, smaller chunks improve load balancing. Benchmark with `chunksize=1, 10, 100, 1000` and pick the winner.

Worker-level resources (DB connections, ML model loading): the initializer pattern avoids loading a resource in the parent and pickling it (often impossible) — instead, each worker loads its own copy at startup. Set with `Pool(4, initializer=setup, initargs=(config,))`.

---

## Interview Angle

Common question forms:
- "What is a process pool?"
- "What is the difference between `pool.map()` and `pool.apply_async()`?"

Answer frame: A process pool pre-creates worker processes to amortize startup cost across many tasks. `Pool.map(fn, items)` distributes items to workers and returns results in order (blocking). `apply_async` submits one task and returns a `AsyncResult` for non-blocking access. `imap` yields results lazily. Specify `chunksize` to tune IPC vs parallelism tradeoff. Use `initializer` to set up per-worker resources (DB connections, ML models). `close() + join()` for clean shutdown; `terminate()` for immediate halt.

---

## Related Notes

- [[multiprocessing-module|The multiprocessing Module]]
- [[concurrent-futures|concurrent.futures]]
- [[inter-process-communication|Inter-Process Communication]]
- [[thread-pool-executor|ThreadPoolExecutor]]
