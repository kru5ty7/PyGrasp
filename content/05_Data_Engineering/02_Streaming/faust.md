---
title: 06 - Faust (Streaming with Python)
description: "Faust is a Python stream processing library that turns Kafka topics into async Python agents — combining Kafka's durability with Python's expressiveness for stateful, real-time data transformation."
tags: [faust, streaming, kafka, asyncio, stream-processing, agents, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Faust (Streaming with Python)

> Faust brings Kafka Streams-style stateful stream processing to Python — asyncio-native, type-annotated, and opinionated about how to model continuous data transformation as Python code.

---

## Quick Reference

**Core idea:**
- Faust is a Python library (not a framework server) — you write a regular Python app that Faust runs with `faust worker -l info`
- `app = faust.App("app-id", broker="kafka://localhost:9092")` — the central application object
- `topic = app.topic("my-topic", value_type=MyModel)` — typed topic binding with optional Avro/JSON codec
- `@app.agent(topic)` — decorates an async generator function that processes the stream
- `app.Table("name", default=int)` — a distributed, changelog-backed key-value store for stateful operations
- Windowed tables: `app.Table("clicks", default=int).tumbling(60.0)` — 60-second tumbling window

**Tricky points:**
- Faust requires Python 3.6+ and uses asyncio throughout — all agent functions must be `async def` with `async for`
- `faust-streaming` (maintained fork) should be used instead of the original Robinhood `faust` which is no longer maintained
- Each partition maps to one Faust agent instance — stateful operations that require cross-partition aggregation are not directly supported
- `Table` state is stored in RocksDB by default (requires `python-rocksdb`) — on new deployments, state must be rebuilt from the changelog topic
- Faust's `faust worker` starts one process — for multi-process parallelism, run multiple workers; Kafka handles partition assignment via consumer groups

---

## What It Is

Think about a newspaper editor who continuously receives news stories over a wire service. Instead of waiting for all stories to arrive and then sorting them, the editor processes each story as it arrives: routes financial news to the business desk, assigns a reporter, adds it to the front page queue if important enough. The editor maintains running counts — "how many sports stories have arrived this hour?" — and can look up context ("what have we published about this company before?"). The process is continuous, stateful, and event-driven. Faust is the framework for building this kind of continuous processing pipeline, where the wire service is Kafka and the editor's desk logic is Python.

Faust was built by Robinhood to process millions of financial events per second in Python, modeled on the Apache Kafka Streams Java library but designed for Python's asyncio ecosystem. The core concept is an "agent" — an async generator function decorated with `@app.agent(topic)` that receives a stream of events and processes them one by one. Each event triggers an `await` point, making the processing non-blocking: while waiting for a database write or an HTTP call, the asyncio event loop can process other events. This cooperative concurrency model means a single Faust worker can process events from multiple partitions simultaneously without threads.

The distinction between Faust and a simple Kafka consumer loop is stateful processing. A Kafka consumer loop processes each event in isolation — it cannot easily ask "how many times has this user clicked in the last 5 minutes?" without external storage. Faust provides `Tables` — distributed key-value stores backed by a Kafka changelog topic and stored locally in RocksDB — that persist across restarts and automatically replicate their state across worker instances. This brings stream-processing capabilities (windowing, aggregation, enrichment) directly into Python without needing to run a separate Kafka Streams or Flink cluster.

---

## How It Actually Works

A Faust application is a Python module that creates a `faust.App` object, defines topics and agents, and runs with `faust worker`. Internally, `faust worker` starts an asyncio event loop, connects to Kafka as a consumer group (using the `app.id` as the `group.id`), and runs all agents concurrently in the event loop. Each agent is an async generator: `yield` yields control to the event loop between events; `async for event in stream:` receives events one at a time from the assigned partition.

```python
import faust
from datetime import timedelta

app = faust.App(
    "click-counter",
    broker="kafka://localhost:9092",
    value_serializer="json",
    store="rocksdb://",                   # local state in RocksDB
)

# Define message schema
class ClickEvent(faust.Record, serializer="json"):
    user_id: int
    url: str
    timestamp: float

# Define typed topic
click_topic = app.topic("user-clicks", value_type=ClickEvent)

# Stateful table: count clicks per user (no windowing)
click_counts = app.Table("click-counts", default=int)

# Windowed table: count clicks per user per 1-minute window
windowed_clicks = app.Table(
    "windowed-clicks",
    default=int,
).tumbling(60.0, expires=timedelta(hours=1))

# Simple stateless agent
@app.agent(click_topic)
async def process_click(clicks):
    async for click in clicks:
        # Each event is a ClickEvent instance
        click_counts[click.user_id] += 1
        windowed_clicks[click.user_id] += 1

        if click_counts[click.user_id] % 100 == 0:
            print(f"User {click.user_id} reached {click_counts[click.user_id]} clicks")

# Agent with filtering and forwarding to another topic
enriched_topic = app.topic("enriched-clicks", value_type=ClickEvent)

@app.agent(click_topic)
async def enrich_and_forward(clicks):
    async for click in clicks.filter(lambda e: e.url.startswith("/checkout")):
        # This agent only sees checkout-page clicks
        await enriched_topic.send(value=click)

# Run with: faust -A mymodule worker -l info
# Or programmatically:
# if __name__ == "__main__":
#     app.main()
```

Faust `Tables` are changelog-backed key-value stores. When you write `click_counts[user_id] += 1`, Faust appends a change record to a Kafka topic named `{app_id}-{table_name}-changelog`. This makes the table's state recoverable — if a worker restarts, it replays the changelog from its last committed offset to reconstruct the local RocksDB state. When a partition rebalance moves a partition from one worker to another, the receiving worker replays the changelog partition for the assigned keys. This is the same mechanism Kafka Streams uses for its `KTable` abstraction.

Windowed tables (tumbling, hopping, and sliding windows) maintain separate counts per time window. A tumbling window of 60 seconds means the count for user X resets to zero every 60 seconds. Behind the scenes, Faust creates separate table entries per window boundary: `(user_id, window_start)` as the key. Expired windows are cleaned up based on the `expires` parameter. The `.current()` method returns the count for the current window; `.previous()` returns the previous window's count — useful for comparing current period to previous period without additional joins.

---

## How It Connects

Faust is built on top of Kafka consumer groups — each Faust worker participates in a consumer group, and partition assignment determines which events each worker processes. Understanding Kafka consumer group rebalancing explains why Faust workers pause briefly when a new worker joins.

[[kafka-consumer-groups|Kafka Consumer Groups]]

Asyncio is the execution model that Faust uses — all agents are async generators running in a shared event loop. Understanding Python's asyncio event loop, cooperative multitasking, and `async for` is prerequisite to writing correct Faust agents.

[[asyncio|Asyncio]]

Kafka basics — topics, partitions, offsets, and the producer API — underpin every Faust operation; Faust is a high-level abstraction that does not hide the need to understand these fundamentals.

[[kafka-basics|Apache Kafka Basics]]

---

## Common Misconceptions

Misconception 1: "Faust processes events in parallel across multiple partitions — I get concurrency for free."
Reality: Faust runs all agents in a single asyncio event loop within one worker process. Concurrency is cooperative — agents yield between events. True parallel processing requires running multiple `faust worker` processes (which Kafka manages via consumer group partition assignment). A single worker with a 12-partition topic assigns 12 partition consumers to the same event loop — cooperative, not truly parallel.

Misconception 2: "Faust Tables are just a dictionary — I can store anything large in them."
Reality: Table values are stored in RocksDB on local disk. Every write also produces a record to the changelog Kafka topic. Large values (binary blobs, serialized models) create large changelog messages, high disk I/O, and slow state recovery after a restart. Keep table values small — counts, timestamps, small structs — and use external storage (S3, Redis) for large objects.

Misconception 3: "The original Robinhood `faust` package is production-ready for current Python versions."
Reality: The Robinhood `faust` package is no longer maintained and has compatibility issues with Python 3.10+ and current Kafka client versions. Use `faust-streaming` (the community fork at `faust-streaming/faust`) which has ongoing maintenance and Python 3.11+ compatibility.

---

## Why It Matters in Practice

Faust fills a specific gap in the Python streaming ecosystem: stateful stream processing without leaving Python or standing up a JVM-based Kafka Streams or Flink deployment. For teams that need simple aggregations, windowed counts, and event enrichment pipelines in Python, Faust provides exactly the right level of abstraction — higher than a raw consumer loop, lower than a full-blown distributed streaming framework.

The asyncio-native design also makes Faust composable with other asyncio libraries: an agent can `await` an async HTTP call (aiohttp), an async database write (asyncpg), or an async cache lookup (aioredis) without blocking the event loop for other events. This composability is what makes Faust practical for enrichment pipelines where each event needs to be augmented with data from external systems.

---

## Interview Angle

Common question forms:
- "What is Faust and how does it differ from a plain Kafka consumer?"
- "How does Faust handle stateful stream processing?"
- "What are the limitations of Faust for high-throughput production use?"

Answer frame:
Faust vs plain consumer: Faust adds `Tables` (stateful, changelog-backed KV stores), windowed aggregations, and a declarative agent model on top of Kafka consumption. Stateful processing: `app.Table()` stores state in local RocksDB, backed by a Kafka changelog topic — state survives restarts by replaying the changelog; windowed tables maintain per-window counts. Limitations: single-process event loop (true parallelism requires multiple workers); `faust-streaming` fork needed for modern Python; complex exactly-once semantics require careful offset and state coordination; not suitable for massive scale without significant operational tuning.

---

## Related Notes

- [[kafka-basics|Apache Kafka Basics]]
- [[kafka-consumer-groups|Kafka Consumer Groups]]
- [[kafka-python|Kafka with Python]]
- [[asyncio|Asyncio]]
