---
title: 07 - Data Warehousing
description: "OLAP vs OLTP, columnar storage, star schema, and why Snowflake and BigQuery are architected completely differently from your production database."
tags: [data-warehousing, olap, oltp, columnar, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Data Warehousing

> Your production database is optimized for transactions; your data warehouse is optimized for questions — and understanding this difference explains why running analytics on your production database is always a bad idea.

---

## Quick Reference

**Core idea:**
- OLTP (Online Transaction Processing): row-oriented, optimized for point lookups and single-row updates
- OLAP (Online Analytical Processing): column-oriented, optimized for aggregating large amounts of data
- Star schema: fact tables (events/transactions) surrounded by dimension tables (users, products, dates)
- Columnar storage reads only the columns a query touches, enabling massive compression and fast aggregation
- Modern cloud data warehouses (BigQuery, Snowflake, Redshift) separate storage from compute for elastic scaling

**Tricky points:**
- Running analytics queries on your production OLTP database slows it down for normal users
- ETL (Extract, Transform, Load) moves data from OLTP to the warehouse — it is not real-time by default
- ELT (Extract, Load, Transform) loads raw data first, then transforms it in the warehouse using SQL
- Columnar storage is bad for OLTP: inserting one row requires writing to every column file
- A data warehouse is not a backup of your production database — it is a separate system for a different purpose

---

## What It Is

Think about the difference between a restaurant and a research kitchen. The restaurant (your production database) is optimized for speed: a customer orders, the kitchen produces one meal quickly, the order is recorded, the bill is printed. The whole system is tuned for many small, fast transactions. The research kitchen (your data warehouse) asks different questions: "Which dishes were most popular last year?", "How did the introduction of the new menu affect average order size?", "Which ingredients correlate with higher tip percentages?" These questions require looking at thousands of orders simultaneously, aggregating values, and joining multiple datasets.

A data warehouse is a database system optimized for analytical queries rather than transactional operations. The distinction is deep enough that OLTP and OLAP systems use fundamentally different storage architectures. Your production PostgreSQL database stores data in rows: each row's columns are stored contiguously on disk. To read the `total_price` column of 10 million orders, the database must read all 10 million rows — including all the columns you do not care about (customer name, delivery address, payment method). For a transaction processing 5 columns of one row, this is fine. For an aggregate query that needs 1 column of 10 million rows, it is wasteful.

A columnar storage engine stores each column's values contiguously. To aggregate `total_price` across 10 million orders, the query engine reads only the `total_price` column file — skipping all other columns entirely. Additionally, columnar storage achieves dramatic compression ratios because the same column type and similar values are stored together. The `status` column on an orders table might have only five distinct values ('pending', 'processing', 'shipped', 'delivered', 'cancelled'). Run-length encoding compresses millions of 'delivered' entries into a handful of bytes. Query engines can also vectorize operations — applying SIMD CPU instructions to process many values simultaneously — when data is stored contiguously.

The data warehouse receives data from production systems through ETL (Extract, Transform, Load) or ELT (Extract, Load, Transform) pipelines. ETL extracts data from production, transforms it into the desired format, and loads it into the warehouse. ELT extracts raw data directly into the warehouse's cheap storage, then uses the warehouse's powerful compute to transform it in place with SQL. Modern cloud warehouses favor ELT because storage is cheap and compute is elastic.

---

## How It Actually Works

The star schema is the canonical data warehouse design pattern. At the center is the fact table, which records events: every order, every page view, every transaction. Each row in the fact table records one event with its measurable metrics (order total, quantity, revenue). Surrounding the fact table are dimension tables: customers, products, dates, geographies. A dimension table holds descriptive attributes — the product's name, category, brand, price. Fact and dimension tables are joined at query time to answer questions like "total revenue by product category by month."

Star schema denormalization is intentional. In a star schema, the `products` dimension table might contain columns that would be split across three normalized tables in an OLTP database. The redundancy is accepted because reads dominate and the queries are known (aggregating fact table rows joined to dimensions). Joins between fact and dimension tables in a columnar store are efficient because both tables can be read columnarly.

BigQuery (Google Cloud) and Snowflake separate storage from compute. Data is stored in a managed object store (Google Cloud Storage, S3, respectively) in columnar compressed format. Compute clusters are provisioned on-demand for queries. A query against a 10 TB dataset spins up a large cluster, processes the query in parallel across thousands of cores, and the cluster is released when the query finishes. You pay for compute time and storage separately. This makes OLAP economically practical: you do not need always-on compute infrastructure.

```python
# BigQuery Python client — analytical queries on massive datasets
from google.cloud import bigquery

client = bigquery.Client(project="my-project")

# Query that would kill a production OLTP database:
# scanning 5 years of orders, aggregating by product category and month
query = """
    SELECT
        p.category,
        DATE_TRUNC(o.created_at, MONTH) AS month,
        COUNT(*) AS order_count,
        SUM(oi.quantity * oi.unit_price) AS revenue,
        AVG(o.total) AS avg_order_value
    FROM `my-project.warehouse.orders` o
    JOIN `my-project.warehouse.order_items` oi ON o.id = oi.order_id
    JOIN `my-project.warehouse.products` p ON oi.product_id = p.id
    WHERE o.created_at >= '2021-01-01'
    GROUP BY 1, 2
    ORDER BY 2 DESC, 4 DESC
"""

query_job = client.query(query)
results = query_job.result()

for row in results:
    print(f"{row.month}: {row.category} — ${row.revenue:,.2f} ({row.order_count} orders)")

# ETL pattern: load from production DB to BigQuery
import pandas as pd
from sqlalchemy import create_engine

def daily_etl_load(date: str):
    """Extract yesterday's orders from production, load to BigQuery."""
    prod_engine = create_engine("postgresql://user:pass@prod-db/app")
    
    df = pd.read_sql(
        f"SELECT * FROM orders WHERE DATE(created_at) = '{date}'",
        prod_engine
    )
    
    # Minimal transformation: normalize types, rename columns
    df['created_at'] = pd.to_datetime(df['created_at'])
    df = df.rename(columns={'id': 'order_id'})
    
    # Load to BigQuery
    df.to_gbq(
        destination_table=f"warehouse.orders${date.replace('-', '')}",
        project_id="my-project",
        if_exists="replace"
    )
```

The ETL/ELT pipeline is a system design concern in itself. Data freshness (how recent is the warehouse data?) depends on pipeline frequency. A nightly ETL run means reports are always at least one day stale. Streaming ETL using Change Data Capture (CDC) can bring latency down to seconds or minutes, but adds operational complexity. The right freshness depends on how decisions are made from the data — daily reports need daily freshness; real-time dashboards need streaming ETL.

---

## How It Connects

The data warehouse typically stores historical snapshots of data from the production OLTP database. Understanding how that data flows — via ETL or CDC pipelines — requires understanding the outbox pattern and Change Data Capture.

[[outbox-pattern|Outbox Pattern]]

Analytics queries that are too heavy for even a dedicated read replica are offloaded to the data warehouse. The read replica provides recent, low-latency reads; the warehouse provides historical, large-scale analysis.

[[read-replicas|Read Replicas]]

The event-driven architecture that produces business events also produces the raw data that flows into a data warehouse. Understanding how event streams are captured and stored is foundational to data engineering.

[[event-driven-architecture|Event-Driven Architecture]]

---

## Common Misconceptions

Misconception 1: "My data warehouse is a backup of my production database."
Reality: A data warehouse is optimized for analytical queries, not for point-in-time recovery. It typically stores transformed, denormalized data in a star schema — not the raw relational tables of the production database. If the production database is lost, the warehouse cannot restore it. These are separate concerns: data warehousing is for analytics; database backup is a separate operational practice.

Misconception 2: "I can run my analytics queries on a read replica instead of a warehouse."
Reality: Analytics queries that scan large historical datasets block the replica's ability to apply replication from the primary, causing replication lag. They also consume resources that should serve application reads. A dedicated analytics replica helps, but the fundamental issue is that row-oriented storage makes aggregation queries over billions of rows slow. A columnar data warehouse processes the same queries orders of magnitude faster.

Misconception 3: "Data warehouses are real-time."
Reality: Most data warehouses process data in batches — hourly, nightly, or on-demand loads. Real-time analytics requires a streaming architecture (Kafka feeding a streaming OLAP database like Apache Pinot, Druid, or ClickHouse). Traditional data warehouses like BigQuery and Redshift support streaming inserts, but the cost and architecture differ from batch loading.

---

## Why It Matters in Practice

For Python developers working on data-intensive applications, the data warehouse is where business questions get answered. A product manager who wants to know "how many users completed the onboarding flow last month, broken down by acquisition channel" is asking a warehouse question, not a production database question. Knowing how to design ETL pipelines, create star schema models, and write analytical SQL transforms this question from "we'll get to it next sprint" to "run this query and you have an answer in 30 seconds."

The architectural decision is: what data belongs in the warehouse versus the production database? Transactional data with integrity constraints lives in the production database. Historical analytics data with complex aggregation needs lives in the warehouse. Event data that needs both real-time access and long-term analysis may need both — a streaming pipeline feeds the warehouse while also powering real-time features.

---

## Interview Angle

Common question forms:
- "What is the difference between OLTP and OLAP?"
- "Why would you use BigQuery instead of running analytics on your production database?"
- "What is a star schema and why is it used in data warehouses?"

Answer frame:
Define OLTP (row-oriented, transactional, optimized for point reads and writes) vs OLAP (columnar, analytical, optimized for aggregations over large datasets). Explain why running analytics on OLTP hurts production: resource contention, row-oriented scan inefficiency. Describe columnar storage benefits: only read touched columns, compression, vectorized execution. Explain star schema: fact tables record events, dimension tables hold descriptive attributes. Describe BigQuery/Snowflake architecture: storage separate from compute, pay per query.

---

## Related Notes

- [[sql-vs-nosql|SQL vs NoSQL]]
- [[read-replicas|Read Replicas]]
- [[time-series-databases|Time Series Databases]]
- [[kafka-system-design|Kafka in System Design]]
- [[event-driven-architecture|Event-Driven Architecture]]
