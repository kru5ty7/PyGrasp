---
title: 06 - Latency vs Throughput
description: "Latency measures how long a single request takes; throughput measures how many requests a system handles per second  -  they trade off in non-obvious ways."
tags: [latency, throughput, performance, p99, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Latency vs Throughput

> Latency and throughput are both measures of performance, but optimizing one can harm the other, and confusing them leads to chasing the wrong metric entirely.

---

## Quick Reference

**Core idea:**
- Latency: the time from a request being sent to a response being received (per-request duration)
- Throughput: the number of requests completed per unit of time (system-wide rate)
- P50/P95/P99 percentiles describe the distribution of latency across all requests
- Little's Law: N = λW  -  the average number of requests in a system equals arrival rate times average latency
- Higher concurrency can increase throughput at the cost of increased latency per request

**Tricky points:**
- Average latency is almost always the wrong metric  -  tail latency (P99, P999) affects the most users
- Increasing parallelism (more threads, more workers) increases throughput but also increases average latency
- Batching increases throughput at the cost of latency for individual items
- A system can have high throughput and terrible latency simultaneously (slow but handles many requests)
- Bandwidth is throughput for data volume; latency is separate (high bandwidth does not mean low latency)

---

## What It Is

Imagine a toll booth on a highway. Latency is how long it takes one car to pass through the booth from the moment it arrives. Throughput is how many cars per hour the booth processes. A highly efficient single booth might process one car every 30 seconds  -  that is low latency. But only 120 cars per hour pass through. Add ten booths in parallel: now 1,200 cars per hour can pass through, but if all ten booths have a queue, each car waits in line and individual latency increases. High throughput and low latency are not the same thing, and they are often in tension.

In software systems, latency is the elapsed time between a client sending a request and receiving the response. It is measured for individual requests. A database query that takes 5 milliseconds has a latency of 5ms. Throughput is the rate at which the system processes requests  -  10,000 requests per second, for example. A system can have high throughput with high latency if it is processing many requests simultaneously, each of which takes a long time. A system can have low throughput with low latency if it processes requests serially but very quickly.

The most important insight about latency is that averages lie. If 99% of your requests take 1 millisecond and 1% take 10 seconds, your average is about 110 milliseconds  -  but one in a hundred users is having a terrible experience. This is why engineers use percentile metrics. P50 (the 50th percentile) is the median  -  half of requests are faster than this. P95 means 95% of requests are faster than this value. P99 means only 1 in 100 requests is slower. P99.9 means only 1 in 1,000 is slower. Tail latency  -  P99 and beyond  -  is often caused by garbage collection pauses, lock contention, or slow downstream dependencies. In distributed systems, the "slowest call wins" problem means that a request touching five services is as slow as the slowest service at its worst percentile.

Throughput is typically measured in requests per second (RPS), transactions per second (TPS), or messages per second. It represents the system's total processing capacity. Throughput is increased by adding parallelism: more workers, more threads, more service instances. But each new worker also adds scheduling overhead, memory usage, and contention on shared resources, which can increase per-request latency even as overall throughput climbs.

---

## How It Actually Works

Little's Law formalizes the relationship between latency, throughput, and concurrency. It states: the average number of items in a system (N) equals the average arrival rate (λ) multiplied by the average time an item spends in the system (W). Written as an equation: N = λW. This law is remarkable because it applies to any stable queuing system  -  a database connection pool, a web server thread pool, a message queue, or a checkout line.

The practical implication is bidirectional. If you know that your system has 100 concurrent requests in flight (N=100) and your throughput is 1,000 requests per second (λ=1,000), then the average latency is W = N/λ = 100/1,000 = 0.1 seconds = 100ms. If your target is 50ms average latency and your throughput is 1,000 RPS, then N should be capped at 50. If your connection pool allows 200 concurrent connections but you want 50ms latency at 1,000 RPS, something is queueing up more than it should.

Tail latency in practice is dominated by a few predictable causes. The first is garbage collection: languages with GC (including Python's reference counting plus cyclic GC, and certainly Java/Go) have pauses that can last tens to hundreds of milliseconds. During a GC pause, all in-flight requests see increased latency. The second is lock contention: when many threads compete for the same lock, some wait while others proceed, creating latency spikes. The third is stragglers in distributed calls: a request that fans out to ten microservices must wait for all ten; the slowest determines the total latency.

```python
import time
import statistics
from typing import Callable, List

def measure_percentiles(func: Callable, n_requests: int = 1000) -> dict:
    """Measure latency percentiles for a function."""
    latencies = []
    for _ in range(n_requests):
        start = time.perf_counter()
        func()
        elapsed_ms = (time.perf_counter() - start) * 1000
        latencies.append(elapsed_ms)

    latencies.sort()
    return {
        "p50": latencies[int(0.50 * n_requests)],
        "p95": latencies[int(0.95 * n_requests)],
        "p99": latencies[int(0.99 * n_requests)],
        "p999": latencies[int(0.999 * n_requests)] if n_requests >= 1000 else None,
        "mean": statistics.mean(latencies),
    }
```

Batching is a classic throughput-latency tradeoff. Kafka, for example, buffers producer messages and sends them in batches. A batch of 100 messages sent once is far more efficient than 100 individual sends. But the first message in the batch waits until the batch is full or a timer expires  -  adding latency. The `linger.ms` setting in Kafka producers controls this tradeoff directly. Increasing it increases throughput and latency; decreasing it reduces latency and throughput.

---

## How It Connects

Throughput and latency are the metrics that make "scalable" concrete. A system that maintains low P99 latency as throughput grows is genuinely scalable.

[[scalability-basics|Scalability Basics]]

Back-of-the-envelope estimation uses rough latency numbers for common operations to reason about system behavior without building it first.

[[back-of-the-envelope|Back of the Envelope Estimation]]

Load balancers can route requests to the least-busy server, which directly reduces tail latency by preventing individual servers from becoming overloaded while others are idle.

[[load-balancing-algorithms|Load Balancing Algorithms]]

---

## Common Misconceptions

Misconception 1: "Average latency is a good way to understand system performance."
Reality: Average latency hides the distribution. A system with P50 of 10ms and P99 of 5,000ms has an average around 60ms, which sounds acceptable. But 1% of your users wait 5 seconds. SLAs should always be specified in percentiles: "P99 latency must be under 200ms" is a meaningful commitment. "Average latency under 50ms" is not.

Misconception 2: "High throughput means low latency."
Reality: Throughput and latency can move in opposite directions. Batching increases throughput by delaying individual items. Adding more concurrent workers can increase total throughput while increasing P99 latency due to head-of-line blocking and lock contention. A message queue with 10,000 messages per second throughput can have individual message latency of several seconds.

Misconception 3: "Latency is just network speed."
Reality: End-to-end latency includes propagation delay (physics, unavoidable), transmission delay (bandwidth), queuing delay (waiting for a slot), and processing delay (computation). For many web applications, the dominant component is queuing delay and processing time, not network speed. A server that is 70% utilized adds significant queuing delay; one that is 20% utilized processes the same request in a fraction of the time.

---

## Why It Matters in Practice

SLAs (Service Level Agreements) and SLOs (Service Level Objectives) are defined in percentile latency terms. "99.9% of requests must complete in under 500ms" is the kind of target engineering teams are responsible for. Achieving this requires understanding where tail latency comes from  -  GC pauses, lock contention, downstream dependencies  -  and instrumenting the system to measure it. Without P99/P999 metrics in your observability stack, you cannot know whether you are meeting your SLO.

For Python engineers specifically, the Global Interpreter Lock (GIL) creates an interesting throughput-latency dynamic. For I/O-bound work, asyncio or thread pools increase throughput without significantly affecting per-request latency. For CPU-bound work, the GIL means multiple threads do not actually run in parallel  -  multiprocessing is required to increase throughput, with added communication overhead affecting latency.

---

## Interview Angle

Common question forms:
- "How would you measure and improve P99 latency in a high-traffic service?"
- "What's the difference between latency and throughput? Can you have both?"
- "Design a system that needs to handle 100,000 requests per second with P99 under 100ms."

Answer frame:
Define latency (per-request time) and throughput (system rate) clearly. Explain that they trade off  -  batching improves throughput at the cost of latency; parallelism improves throughput but can increase tail latency. Explain Little's Law and show how to use it to size concurrency. Discuss what causes tail latency (GC, contention, slow dependencies) and how to address each. Emphasize percentile metrics over averages.

---

## Related Notes

- [[scalability-basics|Scalability Basics]]
- [[back-of-the-envelope|Back of the Envelope Estimation]]
- [[load-balancing|Load Balancing]]
- [[caching-basics|Caching Basics]]
