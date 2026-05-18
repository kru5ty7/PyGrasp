---
title: 06 - Time Series Databases
description: "Why regular relational databases struggle with time-series data, and how specialized stores like InfluxDB and TimescaleDB solve the problem with retention policies, downsampling, and time-based queries."
tags: [time-series, influxdb, timescale, monitoring, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Time Series Databases

> Time-series data is the most common kind of data in modern software systems  -  metrics, events, logs  -  and most teams use the wrong database for it until they have learned the hard way what the right one is.

---

## Quick Reference

**Core idea:**
- Time-series data is a sequence of values indexed by time  -  metrics, sensor readings, financial ticks
- Time is always the primary index and the most common query dimension
- Retention policies automatically delete data older than a configured age (older data has less value)
- Downsampling stores pre-aggregated data at lower resolution (hourly instead of per-second)
- Time-series databases use specialized storage formats (column-oriented, compressed) for high write throughput

**Tricky points:**
- Regular SQL tables with a `created_at` column are not a time-series database  -  write performance degrades as the table grows
- Time-series data has extremely high cardinality for tags (each hostname, each user_id is a "series")
- Downsampling must be configured explicitly  -  without it, a year of per-second metrics fills terabytes
- InfluxDB data model: measurement + tags (indexed) + fields (not indexed) + timestamp
- TimescaleDB is PostgreSQL with time-series optimizations  -  if you already know PostgreSQL, this is the easiest entry point

---

## What It Is

Imagine recording the temperature in your house every minute for a year. You have 525,600 data points. You rarely need to know the temperature at exactly 3:47 AM on March 15  -  but you frequently want to know the average temperature last Tuesday, whether there was ever a spike above 85 degrees last summer, or how the temperature pattern has changed month-over-month over the past year. These are time-series questions: questions about a stream of timestamped values, asking about ranges, aggregations, and patterns over time.

Every modern software system generates time-series data: CPU utilization sampled every 10 seconds, HTTP request latency recorded per request, user page views logged per visit, database query times captured per query, payment transactions timestamped per second. This data is voluminous, append-only (you never modify a historical measurement), and queried almost exclusively by time ranges.

A time-series database (TSDB) is optimized for exactly this workload. The defining characteristics are: time is always part of the primary key, data is append-only, write throughput is prioritized (millions of data points per second), old data is automatically purged or compressed (retention policies), and aggregation over time windows is a first-class operation.

The oldest approach  -  storing metrics in a regular SQL table with a `created_at` column and a value column  -  breaks down at scale. As the table grows to hundreds of millions of rows, inserts slow down (index maintenance), range queries slow down (B-tree traversal for large ranges), and storage grows linearly with no built-in mechanism for pruning old data. A proper time-series database addresses each of these with specialized architecture.

---

## How It Actually Works

Time-series databases use column-oriented storage for metric data. Instead of storing each row as a contiguous block (row-oriented, typical for relational databases), they store each column's values contiguously. For time-series data with billions of rows and only a handful of columns (timestamp, value, maybe a few tags), this means massive compression ratios: timestamps are stored as deltas from the previous timestamp (most are 10 seconds apart  -  delta encoding compresses 1000 identical deltas dramatically). Values use delta-of-delta encoding. Tags are dictionary-encoded.

InfluxDB (version 1.x) uses a custom storage engine called TSM (Time-Structured Merge Tree), analogous to the LSM-tree used by LevelDB and Cassandra. Writes are first stored in an in-memory buffer (WAL + cache). Periodically, the in-memory data is flushed to immutable TSM files on disk, organized by measurement and tag set. Old TSM files are merged and recompressed in a background compaction process. This architecture supports write rates of millions of data points per second on a single node.

TimescaleDB is a PostgreSQL extension that adds a `hypertable` abstraction on top of regular PostgreSQL tables. A hypertable automatically partitions data by time into "chunks"  -  typically one or a few days of data per chunk. When a query filters by time range, only the relevant chunks are scanned. Old chunks can be compressed (TimescaleDB uses a column-oriented storage format for compressed chunks) or deleted via data retention policies. The benefit is PostgreSQL compatibility: all SQL features, existing tooling, and familiar query patterns work unchanged.

```python
# InfluxDB v2 Python client
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS
from datetime import datetime, timezone

client = InfluxDBClient(
    url="http://influxdb:8086",
    token="my-token",
    org="my-org"
)
write_api = client.write_api(write_options=SYNCHRONOUS)
query_api = client.query_api()

# Writing metrics: measurement + tags (indexed) + fields (value) + timestamp
def record_api_latency(endpoint: str, method: str, latency_ms: float):
    point = (
        Point("api_latency")
        .tag("endpoint", endpoint)    # indexed  -  use for filtering
        .tag("method", method)         # indexed  -  use for filtering
        .field("latency_ms", latency_ms)  # the actual measurement
        .time(datetime.now(timezone.utc))
    )
    write_api.write(bucket="metrics", record=point)

# Querying: Flux query language (InfluxDB 2.x)
# Get average latency per endpoint over the last hour
query = '''
from(bucket: "metrics")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "api_latency")
  |> filter(fn: (r) => r._field == "latency_ms")
  |> group(columns: ["endpoint"])
  |> mean()
'''
tables = query_api.query(query)
for table in tables:
    for record in table.records:
        print(f"Endpoint: {record.values.get('endpoint')}, Avg: {record.get_value():.2f}ms")
```

Downsampling is the mechanism for managing data growth over time. Raw per-second metrics from 1,000 servers generate 1,000 × 86,400 = 86.4 million data points per day. Over a year: 31 billion points. This is terabytes of storage. Downsampling computes aggregates (min, max, mean, sum) over time windows and stores the aggregated values instead of raw points. Per-second data can be downsampled to per-minute after one hour, and to per-hour after one day. A 24-hour window of per-second data (86,400 points) becomes one per-hour data point (1 point)  -  a 86,400x reduction. The raw data beyond one hour is deleted. This trades resolution for storage efficiency.

---

## How It Connects

Time-series databases store observability data  -  metrics, traces, and events  -  that are used to monitor system health and detect problems. They are the data layer for observability infrastructure.

[[latency-vs-throughput|Latency vs Throughput]]

For analytics beyond real-time metrics  -  historical trend analysis, multi-dimensional aggregations, joining metrics with business data  -  time-series databases integrate with or are supplemented by data warehouses.

[[data-warehousing|Data Warehousing]]

High-volume event streams from Kafka often flow into a time-series database for real-time monitoring and alerting. Understanding the event producer/consumer relationship helps design the ingestion pipeline.

[[kafka-system-design|Kafka in System Design]]

---

## Common Misconceptions

Misconception 1: "I can use PostgreSQL with a timestamp column for my metrics  -  it's the same thing."
Reality: For small volumes (millions of rows), a PostgreSQL table with a timestamp index works. As data grows to billions of rows, write throughput degrades as indexes are maintained, range queries slow as B-tree traversal becomes expensive, and storage grows without bound. Time-series databases solve all three problems with specialized storage engines. TimescaleDB is a middle ground  -  if you start with it instead of plain PostgreSQL, migration is painless.

Misconception 2: "More tags means better filtering  -  I should tag everything."
Reality: In InfluxDB, each unique combination of tag values creates a separate "series" stored in a separate index entry. High-cardinality tags  -  user IDs, session IDs, request IDs  -  create millions of unique series, consuming enormous memory for the index. InfluxDB explicitly warns against high-cardinality tags. Fields (non-indexed values) should hold high-cardinality data; tags should hold low-cardinality dimensions you filter on.

Misconception 3: "Time-series databases are only for infrastructure metrics."
Reality: Time-series databases are appropriate for any data that is primarily read by time range and written in an append-only fashion. Business metrics (orders per minute, revenue per hour), application events (user logins, feature usage), financial tick data (stock prices), IoT sensor readings, and machine learning model performance metrics are all time-series data that benefit from specialized storage.

---

## Why It Matters in Practice

Every production Python service generates metrics. Without a time-series store, those metrics either go into a relational database that cannot sustain the write rate, or they are lost entirely. The canonical observability stack for Python services is: Prometheus for metrics collection (or a push-based agent), InfluxDB or TimescaleDB for long-term storage, and Grafana for visualization. Knowing how this stack works  -  what write patterns it expects, how to design metric names and tag sets, how downsampling affects query resolution  -  lets you build observability that actually scales.

The data modeling discipline for time-series  -  keeping tag cardinality low, separating indexed dimensions (tags) from measured values (fields), setting appropriate retention policies  -  is specific to this domain and different from relational data modeling.

---

## Interview Angle

Common question forms:
- "How would you store and query application metrics at scale?"
- "What is a time-series database and why is it better than a regular SQL table for metrics?"
- "What is downsampling and why is it necessary?"

Answer frame:
Describe the time-series data pattern: timestamped, append-only, query by time range. Explain why regular SQL fails at scale: index maintenance degrades insert throughput, no built-in retention. Describe TSDB advantages: column-oriented compression, time-partitioned storage, native downsampling, automatic retention. Walk through InfluxDB's data model: measurement + tags + fields + timestamp. Explain downsampling: trade resolution for storage. Mention TimescaleDB as the PostgreSQL-native option.

---

## Related Notes

- [[database-indexes|Database Indexes]]
- [[data-warehousing|Data Warehousing]]
- [[kafka-system-design|Kafka in System Design]]
- [[latency-vs-throughput|Latency vs Throughput]]
