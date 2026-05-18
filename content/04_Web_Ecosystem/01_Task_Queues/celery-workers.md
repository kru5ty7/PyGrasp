---
title: 04 - Celery Workers and Concurrency
description: "Celery workers are the processes that consume and execute tasks, with configurable concurrency models  -  prefork for CPU-bound work, gevent or eventlet for I/O-bound tasks  -  and queue-based routing for prioritization."
tags: [celery, workers, concurrency, prefork, gevent, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Celery Workers and Concurrency

> A Celery worker is a long-running process that polls the broker for task messages and executes them  -  choosing the right concurrency model for the task type is the single biggest lever for worker throughput.

---

## Quick Reference

**Core idea:**
- A worker process subscribes to one or more broker queues and executes tasks concurrently via a pool
- `--concurrency N` sets the pool size; default is the number of CPUs (correct for prefork, often wrong for I/O-bound tasks)
- `--pool=prefork` (default): N child processes  -  true parallelism, best for CPU-bound work
- `--pool=gevent` or `--pool=eventlet`: cooperative coroutines  -  thousands of concurrent I/O tasks per worker
- `--queues high_priority,default`: worker subscribes to specific named queues for routing

**Tricky points:**
- prefork workers have separate memory spaces  -  global state changes in one child are not visible in others
- gevent and eventlet monkey-patch the standard library  -  load them before any other imports to avoid partial patching issues
- `CELERYD_MAX_TASKS_PER_CHILD` limits task executions per child process before it is replaced  -  prevents memory leaks in long-running workers
- Increasing `--concurrency` beyond available CPU cores does not help prefork workers and wastes memory from additional processes
- Workers must be restarted to pick up code changes  -  the `celery -A myapp control pool_restart` command does a rolling restart without full process termination

---

## What It Is

When a Celery task message arrives in the broker queue, a worker process is waiting to receive it. The worker's job is to execute as many tasks as possible as quickly as possible, subject to the resource constraints of the machine it runs on. The concurrency model controls how many tasks a worker handles simultaneously and what kind of isolation exists between those concurrent executions.

The prefork pool is the default. It spawns N child processes at startup, where N defaults to the machine's CPU count. Each child handles one task at a time. The parent worker process distributes incoming messages across children, collects results, and communicates with the broker. Because each child is a separate OS process, they benefit from true parallelism on multicore machines  -  CPU-intensive tasks like image processing, report generation, or data transformation run in parallel across cores without the Python GIL interfering.

For tasks that spend most of their time waiting  -  making HTTP requests to external APIs, querying databases, sleeping  -  the prefork model is wasteful. A child process blocked waiting for an HTTP response is idle, consuming memory but doing no useful work. The gevent and eventlet pools replace blocking I/O with cooperative coroutines: when a task would block, it yields control and another task runs in the same thread. A single gevent worker with `--concurrency=1000` can maintain 1000 in-flight HTTP requests simultaneously, handling vastly more throughput than 1000 prefork processes would with proportionally less memory.

---

## How It Actually Works

Queue routing allows different workers to handle different categories of work. A task is routed to a named queue at enqueue time; a worker subscribes to specific queues. This enables priority queues, task isolation, and resource allocation.

```python
# Task with explicit queue
@app.task
def send_critical_alert(message: str):
    pass

# Enqueue to specific queue
send_critical_alert.apply_async(args=["disk full"], queue="high_priority")
```

```bash
# Worker subscribed to specific queues
celery -A myapp worker --queues high_priority --concurrency=4
celery -A myapp worker --queues default --concurrency=8 --pool=gevent
```

`CELERYD_MAX_TASKS_PER_CHILD` (or `worker_max_tasks_per_child` in new-style config) replaces a child process after it has executed N tasks. This is the safest defense against gradual memory growth in tasks that accumulate heap objects without releasing them properly. The child exits cleanly after its Nth task; the parent spawns a replacement.

```python
app.conf.worker_max_tasks_per_child = 100
app.conf.worker_max_memory_per_child = 200000  # kilobytes  -  also available
```

Autoscaling adjusts the pool size dynamically based on queue depth. The `--autoscale=max,min` flag sets bounds.

```bash
celery -A myapp worker --autoscale=10,3
# Scales between 3 (minimum) and 10 (maximum) concurrent workers
```

Inspecting and controlling workers at runtime uses the `celery inspect` and `celery control` commands, which communicate with workers via the broker's control channel.

```bash
celery -A myapp inspect active       # currently executing tasks
celery -A myapp inspect stats        # worker stats including pool type and concurrency
celery -A myapp control shutdown     # gracefully shut down all workers
celery -A myapp control revoke <task_id> terminate=True  # kill a running task
```

---

## How It Connects

The tasks workers execute are defined and decorated with `@app.task` or `@shared_task`  -  worker configuration must be compatible with the task types being executed.

[[celery-tasks|Celery Tasks]]

Flower provides a real-time web dashboard for monitoring worker state, queue depth, and task history without using command-line inspection.

[[celery-monitoring|Monitoring Celery with Flower]]

---

## Common Misconceptions

Misconception 1: "Running one worker with `--concurrency=100` is equivalent to running 100 workers with `--concurrency=1`."
Reality: For prefork (multiprocessing), the number of concurrent tasks is equal to `--concurrency` regardless of how many worker processes exist. For gevent/eventlet, running multiple worker processes across multiple machines provides fault tolerance and horizontal scaling beyond what one machine can support. One machine with one worker and `--concurrency=100` is a single point of failure; ten machines with ten workers each is resilient.

Misconception 2: "I can use `--pool=gevent` for all tasks because it handles more concurrency."
Reality: Gevent uses cooperative multitasking  -  a CPU-intensive task that never yields blocks the entire worker. Pure CPU work (encryption, compression, numerical computation) will starve all other tasks in a gevent worker. Use prefork for CPU-bound tasks and gevent only for tasks dominated by I/O waits.

---

## Why It Matters in Practice

Worker configuration is where Celery performance lives. A production deployment running prefork workers for a task queue full of external API calls will underperform by an order of magnitude compared to the same hardware running gevent workers. Understanding pool types, queue routing, and `MAX_TASKS_PER_CHILD` is what allows a Celery deployment to scale efficiently and remain stable over weeks of continuous operation.

---

## Interview Angle

Common question forms:
- "What concurrency model would you choose for Celery workers handling database queries?"
- "How do you prevent memory leaks in Celery workers?"
- "How does queue routing work in Celery?"

Answer frame:
For I/O-bound tasks use `--pool=gevent` or `--pool=eventlet`  -  cooperative multitasking handles many concurrent waits efficiently. For CPU-bound tasks use `--pool=prefork`  -  true OS-level parallelism across cores. Memory leaks: set `worker_max_tasks_per_child` to replace child processes after N tasks. Queue routing: publish tasks to named queues with `queue='...'` in `apply_async`, and subscribe workers to specific queues with `--queues`. This enables priority lanes and resource isolation.

---

## Related Notes

- [[celery|Celery]]
- [[celery-tasks|Celery Tasks]]
- [[celery-beat|Celery Beat]]
- [[celery-monitoring|Monitoring Celery with Flower]]
