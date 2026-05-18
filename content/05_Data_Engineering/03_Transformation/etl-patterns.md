---
title: 07 - ETL Patterns
description: "ETL (Extract, Transform, Load) patterns are the foundational design choices for data pipelines  -  full refresh versus incremental, append versus upsert, and idempotency determine correctness, cost, and recoverability."
tags: [etl, data-pipeline, incremental, upsert, idempotency, full-refresh, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# ETL Patterns

> ETL patterns are the design vocabulary for data pipelines  -  the choice between full refresh and incremental loading, append and upsert, EL+T and classic ETL determines whether a pipeline is correct under failures, cost-efficient at scale, and maintainable over time.

---

## Quick Reference

**Core idea:**
- **Full refresh**: truncate-and-reload the target table on every run  -  simple, correct, expensive at scale
- **Incremental load**: only process new/changed records since the last run  -  efficient, requires careful state tracking
- **Append-only**: new records appended, no updates to existing records  -  suited for immutable event streams
- **Upsert (MERGE)**: insert new records, update existing ones  -  requires a unique key; handles late-arriving changes
- **EL+T (Extract-Load-Transform)**: raw data loaded to the warehouse first, then transformed in-place  -  the modern data stack pattern
- **Idempotency**: running a pipeline multiple times produces the same result as running it once  -  required for safe retries

**Tricky points:**
- Incremental pipelines need a reliable "high-water mark"  -  a column that reliably identifies new/changed records (e.g., `updated_at`); systems that update rows without changing `updated_at` break the pattern silently
- Full refresh is safer but not always feasible at scale  -  a 10 TB table cannot be truncated and reloaded in a nightly batch window
- Upsert requires a unique key  -  tables without natural keys cannot use MERGE without a surrogate key strategy
- Late-arriving data breaks simple incremental pipelines  -  include a lookback window (e.g., re-process the last 3 days) to catch late records
- Soft deletes (marking records as `deleted = true` instead of removing them) require additional logic in downstream joins to exclude logically deleted rows

---

## What It Is

Imagine a bank that needs to update its main ledger from thousands of branch offices each night. One approach: every night, collect all records from every branch, clear the main ledger, and rewrite it from scratch with everything collected. This is reliable  -  the ledger is always a complete picture  -  but takes the entire night and requires collecting all data from all branches even if most of it hasn't changed. Another approach: each branch sends only the transactions from the past 24 hours, and the main ledger is updated by applying those changes. This is faster, but requires that every branch reliably flags what changed, that the ledger system can apply changes without corrupting records that were not touched, and that nothing is lost if the update process crashes halfway through. These are the two fundamental approaches to updating any data store from a source  -  full refresh and incremental loading.

ETL (Extract-Transform-Load) is the classic pattern: extract raw data from sources, transform it into the required shape in a staging area, then load the result to the target warehouse. ELT (Extract-Load-Transform) inverts the last two steps: extract raw data, load it to the warehouse as-is, then transform it in the warehouse using SQL. The modern data stack (dbt + cloud warehouses) almost exclusively uses ELT  -  raw data in the warehouse is cheap to store, warehouse compute is elastic, and SQL is the lingua franca of analysts and engineers alike. Classic ETL is still used when data must be scrubbed (PII removal, GDPR compliance) before it reaches the warehouse, or when the transformation requires Python logic that cannot be expressed in SQL.

Idempotency is the property that separates robust pipelines from fragile ones. An idempotent pipeline produces identical results whether it runs once, twice, or ten times against the same source data. This matters because pipelines crash. Schedulers have bugs. Cloud services have transient failures. A non-idempotent pipeline  -  one that appends to a table without checking for duplicates, or one whose output depends on when it ran rather than what data it processed  -  will produce wrong results after any retry. Building idempotency in means: either use MERGE/upsert semantics that overwrite by unique key, or use full-replace-by-partition semantics that overwrite a specific time slice, or use append-only tables designed around deduplication at read time.

---

## How It Actually Works

**Full Refresh Pattern:**
```python
import pandas as pd
from sqlalchemy import create_engine

engine = create_engine("postgresql://user:pass@host/db")

def full_refresh_load(source_query: str, target_table: str):
    """Read all source data, replace target table completely."""
    df = pd.read_sql(source_query, source_engine)
    df.to_sql(
        target_table,
        engine,
        if_exists="replace",    # drop and recreate  -  fully idempotent
        index=False,
        method="multi",
        chunksize=10000,
    )
```

**Incremental Pattern with High-Water Mark:**
```python
from datetime import datetime, timedelta

def incremental_load(source_table: str, target_table: str, high_water_mark_col: str):
    """Load only records newer than the last successful run."""
    # Read the high-water mark from the target
    last_load_result = engine.execute(
        f"SELECT MAX({high_water_mark_col}) FROM {target_table}"
    ).fetchone()
    last_load = last_load_result[0] or datetime(2000, 1, 1)

    # Extract only new/changed records (with 3-day lookback for late arrivals)
    lookback = last_load - timedelta(days=3)
    df = pd.read_sql(f"""
        SELECT * FROM {source_table}
        WHERE {high_water_mark_col} > '{lookback}'
    """, source_engine)

    if df.empty:
        return 0

    # Upsert  -  insert new rows, update existing ones on conflict
    df.to_sql(target_table + "_staging", engine, if_exists="replace", index=False)
    engine.execute(f"""
        INSERT INTO {target_table}
        SELECT * FROM {target_table}_staging
        ON CONFLICT (primary_key)
        DO UPDATE SET
            {high_water_mark_col} = EXCLUDED.{high_water_mark_col},
            -- ... other columns
    """)
    return len(df)
```

**Partition-Replace Pattern (recommended for large fact tables):**
```python
# Overwrite exactly the date partitions covered by the current run
# Idempotent: re-running for the same date range produces the same data

def partition_replace_load(ds: str):
    """Load one day's data, replacing that partition atomically."""
    df = extract_for_date(ds)
    transform(df)
    # In Spark:
    df.write \
      .mode("overwrite") \
      .partitionBy("order_date") \
      .parquet(f"s3://bucket/fct_orders/")
    # Only the partitions covered by df's order_date values are overwritten
    # Historical partitions are untouched
```

The three-day lookback in incremental pipelines is a common and important pattern. Late-arriving data  -  records that appear in the source system hours or days after their event timestamp  -  is endemic in real-world data systems. An API that batches events, a mobile app that syncs when connectivity is available, a payments processor with delayed settlement  -  all produce data that arrives in the source after the incremental window has already closed. A lookback window re-processes the recent past on every run, catching these late records at the cost of reprocessing a small additional amount of data.

---

## How It Connects

dbt implements ETL patterns in SQL  -  incremental materialization is dbt's implementation of the incremental load pattern, and `dbt build` provides idempotent, dependency-ordered execution.

[[dbt-basics|dbt Basics]]

Airflow DAGs orchestrate ETL pipelines  -  the scheduling, retry, and backfill features of Airflow directly address the operational concerns (retries, idempotency, late-arriving data) described in ETL patterns.

[[airflow-basics|Apache Airflow Basics]]

PySpark is the execution engine for large-scale ETL  -  understanding Spark's partition-replace write mode and MERGE operations is essential for implementing ETL patterns at terabyte scale.

[[pyspark-basics|PySpark Basics]]

---

## Common Misconceptions

Misconception 1: "Incremental loading is always better than full refresh  -  it's faster and more efficient."
Reality: Incremental loading is more complex and has more failure modes: missed records if the high-water mark column is unreliable, duplicate records if upsert logic has bugs, stale data if the lookback window is too small. For tables under a few gigabytes that can be reloaded in under a minute, full refresh is simpler, more reliable, and the right choice.

Misconception 2: "My pipeline is idempotent because I use `INSERT IF NOT EXISTS`."
Reality: `INSERT IF NOT EXISTS` (or `INSERT IGNORE`) may skip updates to existing records. An idempotent upsert must also update existing records if source data has changed. True idempotency means: the same source data always produces the same target state, regardless of how many times the pipeline runs or whether the target was previously populated.

Misconception 3: "ELT means we skip the Transform step  -  load raw data to the warehouse and query it directly."
Reality: In ELT, the Transform happens inside the warehouse (using SQL, dbt, or Snowpark) rather than in a staging area outside it. The Transform step is not optional  -  it is just done differently. Querying raw, untransformed data for business decisions without a transformation layer produces brittle, slow, inconsistent analysis.

---

## Why It Matters in Practice

The incremental vs full-refresh decision and idempotency design are the most consequential choices in data pipeline design. A full-refresh pipeline on a 5 TB table takes hours, costs thousands in warehouse credits, and blocks dependent transformations. An incremental pipeline on that same table takes minutes and costs proportionally  -  but only if the high-water mark is reliable and the late-arrival handling is correct. Getting this wrong means either wasted compute (unnecessary full refreshes) or missing data (incremental pipelines that drop late records).

Idempotency is not a nice-to-have  -  it is the property that makes a pipeline safe to operate. A scheduler that runs a job twice (due to a network partition or a restart), a developer who manually re-runs a failed job, a backfill operation that re-processes historical dates  -  all of these are safe with an idempotent pipeline and potentially catastrophic (duplicate rows, wrong aggregations) without one.

---

## Interview Angle

Common question forms:
- "What is the difference between a full-refresh and an incremental data pipeline?"
- "What does idempotency mean for a data pipeline and why does it matter?"
- "How would you handle late-arriving data in an incremental pipeline?"

Answer frame:
Full refresh: truncate and reload on every run  -  simple, correct, expensive for large tables. Incremental: process only records newer than the last run  -  efficient, requires reliable change detection (high-water mark column, CDC). Idempotency: running the pipeline multiple times with the same source data produces identical target state  -  achieved via MERGE/upsert (overwrite by key) or partition-replace (overwrite by date partition). Late-arriving data: add a lookback window  -  re-process the last N days on each incremental run to catch records whose source timestamp is older than their arrival time.

---

## Related Notes

- [[dbt-basics|dbt Basics]]
- [[airflow-basics|Apache Airflow Basics]]
- [[pyspark-basics|PySpark Basics]]
- [[data-pipeline-design|Data Pipeline Design]]
