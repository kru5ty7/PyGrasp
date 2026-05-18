---
title: 07 - Back of the Envelope Estimation
description: "The art of making fast, reasonably accurate estimates about system scale using a handful of memorized numbers and structured reasoning."
tags: [estimation, system-design, performance-numbers, layer-7, system-design-fundamentals]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Back of the Envelope Estimation

> Every system design interview and every real architectural decision requires estimating scale  -  and a developer who can do this quickly and accurately on a whiteboard is far more valuable than one who cannot.

---

## Quick Reference

**Core idea:**
- Memorize key latency numbers: L1 cache ~1ns, main memory ~100ns, SSD ~100μs, disk seek ~10ms, cross-DC ~150ms
- 1 million seconds is roughly 11.5 days; 1 billion is roughly 31.7 years  -  useful for storage estimates
- QPS estimate: DAU × requests/user/day ÷ 86,400 (seconds per day)
- Storage estimate: daily writes × record size × retention days
- Always state your assumptions explicitly  -  the reasoning matters as much as the number

**Tricky points:**
- Powers of 10 are your friend  -  order of magnitude is usually enough
- A "byte" of memory is 8 bits; a "character" in UTF-8 is 1-4 bytes (usually 1 for ASCII)
- Network bandwidth and disk bandwidth are both in bytes/second, but they are very different magnitudes
- Read-heavy systems often have 10:1 or 100:1 read-to-write ratios  -  assumptions should reflect this
- Cache hit rate has an outsized effect on load estimates  -  99% hit rate vs 90% is 10x the origin load

---

## What It Is

Imagine you are asked to plan how many delivery trucks a warehouse needs for next year. You do not know exactly how many orders will come in, but you can estimate: last year there were 100,000 orders, growth was 20% per year, so plan for 120,000. Average order weight is 2 kg, max truck capacity is 10,000 kg, so you need at least 24 truck-loads per year. Given you want to deliver within 24 hours, and you have 8-hour delivery windows, you need at least a few trucks running simultaneously. You got to a useful answer in two minutes using only arithmetic and reasonable assumptions. That is back-of-the-envelope estimation.

In system design, these estimates serve a specific purpose: they tell you whether your proposed architecture is plausible before you commit to it. If you estimate that a feature will generate 50 GB of data per day and your database can store 1 TB total, you know without writing any code that you need a data retention strategy. If you estimate your API will receive 10,000 requests per second and your service can handle 200 per instance, you know you need at least 50 instances  -  plus headroom. Getting these numbers wrong wastes months of engineering.

The key mental model is that numbers in computer systems span about 12 orders of magnitude, from nanoseconds to seconds. Jeff Dean's famous "Numbers Every Programmer Should Know"  -  L1 cache reference at 0.5ns, main memory access at 100ns, SSD random read at 150μs, spinning disk seek at 10ms, network round trip within a datacenter at 500μs, cross-datacenter round trip at 150ms  -  give you the anchor points. With these anchors, you can reason about whether a proposed design can meet its latency requirements without simulation or profiling.

The process has a structure: estimate your traffic, estimate your storage, identify your bottleneck, then check whether your proposed architecture can handle the bottleneck's load. The traffic estimate starts with daily active users (DAU). The storage estimate starts with write rate and average record size. The bottleneck is usually reads per second (for read-heavy systems), writes per second (for write-heavy systems), or raw data volume (for analytics systems).

---

## How It Actually Works

The latency numbers to memorize form a hierarchy of storage tiers. L1 cache access is roughly 1 nanosecond. L2 cache is roughly 10 nanoseconds. Main memory (DRAM) is roughly 100 nanoseconds. A mutex lock/unlock is roughly 25 nanoseconds. Compressing 1 KB with Snappy is roughly 3 microseconds. Reading 1 MB sequentially from memory is roughly 250 microseconds. Reading 1 MB sequentially from SSD is roughly 1 millisecond. A network round trip within the same datacenter is roughly 0.5 milliseconds. Reading 1 MB sequentially from a spinning disk is roughly 20 milliseconds. A cross-datacenter round trip is roughly 150 milliseconds.

These numbers tell you immediately that a service making five sequential calls to an external API  -  each with 150ms latency  -  cannot possibly respond in under 750ms. If you need sub-100ms total latency, you need parallel calls or a cache. They tell you that a service doing ten synchronous database queries per request has at minimum 5ms of database latency plus processing time  -  probably 50 - 200ms in practice. Any latency target must be compatible with the physical latency of the operations involved.

For storage estimation, two conversions are useful. One kilobyte is 1,024 bytes  -  roughly 1,000 for estimation purposes. One gigabyte is approximately one billion bytes. A tweet-sized string is roughly 300 bytes. A user profile record is roughly 1 KB. A photo thumbnail is roughly 100 KB. A raw photo is roughly 3 - 5 MB. A minute of compressed video is roughly 10 - 50 MB. With these anchor points, "100 million users uploading one photo per day" becomes 100 million × 3 MB = 300 TB/day  -  immediately you know you need an object storage solution, not a relational database.

```
# Worked example: Estimate QPS and storage for a URL shortener

# Traffic
Daily Active Users (DAU): 100 million
Short URL reads per user per day: ~1
Short URL creates per user per day: ~0.1 (10:1 read-to-write)

Read QPS:  100M × 1 ÷ 86,400 ≈ 1,200 QPS
Write QPS: 100M × 0.1 ÷ 86,400 ≈ 115 QPS

Peak QPS (assume 2x average): ~2,400 reads, ~230 writes

# Storage
Each URL record: ~500 bytes (original URL + short code + metadata)
Writes per day: ~10 million (100M × 0.1)
5-year retention: 10M × 500 bytes × 365 × 5 ≈ 9 TB

# Verdict
- 9 TB fits comfortably on a single large database, but replicas needed
- 2,400 read QPS: a single cache layer with Redis handles this easily
- Write QPS: 230/s is manageable on a single primary database
```

The most important habit is stating assumptions out loud and justifying them. If you assume a 10:1 read-to-write ratio, say so. If you assume 10 MB average photo size, say why. Interviewers care about your reasoning process, not whether you arrive at precisely correct numbers. An answer that is off by 2x with clear reasoning is better than a "correct" answer with no explanation.

---

## How It Connects

Once you have estimated scale, you need to know whether that scale requires horizontal scaling or whether a single machine can handle it. Vertical vs horizontal scaling decisions follow directly from estimation.

[[horizontal-vs-vertical-scaling|Horizontal vs Vertical Scaling]]

Estimation reveals whether your read load can be absorbed by a cache. The cache hit rate assumption is critical  -  changing it from 99% to 90% changes origin load by 10x.

[[caching-basics|Caching Basics]]

In case study problems, back-of-the-envelope estimation is always the first step before any design decisions. The URL shortener case study walks through this process end-to-end.

[[design-url-shortener|Design a URL Shortener]]

---

## Common Misconceptions

Misconception 1: "I need precise numbers to do useful estimation."
Reality: Order-of-magnitude accuracy is sufficient for architectural decisions. Whether a system needs 1 TB or 2 TB of storage has the same architectural implication (you need a storage solution that scales to multi-TB). Whether it needs 10 TB or 100 TB is the meaningful distinction. Round aggressively and use powers of ten.

Misconception 2: "Estimation is only for interviews, not real engineering."
Reality: Back-of-the-envelope estimation is used constantly in production engineering. Capacity planning, cost forecasting, database sizing, bandwidth provisioning  -  all of these require the same skill. Teams that skip estimation make expensive mistakes: choosing a database that cannot scale to the required load, or over-provisioning by 100x and wasting money.

Misconception 3: "More servers means I can handle any load."
Reality: More servers help with stateless compute, but storage and bandwidth have different scaling curves. If your writes are bottlenecked at the database, more application servers do nothing. If your bottleneck is network bandwidth, more RAM does nothing. Estimation reveals which resource is the bottleneck, and that determines what you need to scale.

---

## Why It Matters in Practice

The most common system design failure mode is building the wrong thing at the wrong scale. Teams build complex distributed systems for loads that a single server could handle, or they build single-server systems that collapse when traffic grows. Estimation prevents both. It is also the foundation of cost engineering: cloud resources cost real money, and every architectural decision translates to a monthly bill. A team that can estimate storage growth, compute needs, and bandwidth requirements can build and defend a cost model for any proposed feature.

In interview settings, estimation serves as a signal for engineering maturity. A candidate who charges immediately into design without sizing the system is showing that they do not think about constraints. A candidate who spends two minutes on estimation before proposing any architecture is showing that they understand how constraints drive design.

---

## Interview Angle

Common question forms:
- "How many requests per second does Twitter's timeline serve?"
- "How much storage does Instagram need per day?"
- "Estimate the number of servers needed to serve Google Search."

Answer frame:
Start with top-level numbers (DAU, requests per user per day, data per request). Convert to per-second rates. State assumptions for peak vs average. Estimate storage as: write rate × record size × retention. Identify which resource is the bottleneck (CPU, storage, bandwidth, connections). Propose the architectural component that addresses that bottleneck. End with a sanity check against known systems.

---

## Related Notes

- [[scalability-basics|Scalability Basics]]
- [[latency-vs-throughput|Latency vs Throughput]]
- [[horizontal-vs-vertical-scaling|Horizontal vs Vertical Scaling]]
- [[design-url-shortener|Design a URL Shortener]]
