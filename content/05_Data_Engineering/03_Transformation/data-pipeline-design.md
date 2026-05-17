---
title: 08 - Data Pipeline Design
description: "Data pipeline design is the practice of making architectural decisions — about orchestration, storage formats, error handling, and observability — that determine whether a pipeline is maintainable, reliable, and cost-efficient in production."
tags: [data-pipeline, design, architecture, observability, fault-tolerance, data-quality, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Data Pipeline Design

> A data pipeline that works on Tuesday and fails silently on Thursday — producing no errors but wrong numbers — is worse than one that fails loudly, because nobody knows to fix it until someone notices the dashboard.

---

## Quick Reference

**Core idea:**
- The three dimensions of pipeline quality: **correctness** (right data), **reliability** (runs on schedule), **efficiency** (acceptable cost and latency)
- Design principles: idempotency, observability, fault isolation, schema enforcement, data quality assertions
- Storage format determines downstream capability: Parquet for analytics, JSON/Avro for streaming, Delta/Iceberg for ACID transactions
- Metadata: row counts, checksums, processing time, data freshness timestamps — emit these as pipeline outputs, not just logs
- Circuit breakers: if row count drops by 80%, stop and alert rather than loading a nearly empty table to production
- "Defensive extraction": validate source data schema and row count before processing; fail fast on schema drift

**Tricky points:**
- Silent data quality degradation is harder to detect than job failures — add data quality checks at each stage
- Schema drift (source system silently adding, renaming, or removing columns) breaks pipelines without raising exceptions if you use `SELECT *`
- Over-engineering is a real failure mode — a pipeline that requires a PhD to operate will not be maintained correctly
- Cost monitoring is a design concern, not an afterthought — unbounded Spark clusters and unrestricted warehouse queries have caused six-figure cloud bills
- Fan-out pipelines (one source feeding many consumers) need to consider backpressure — a slow consumer should not block or corrupt faster consumers

---

## What It Is

Think of a water treatment facility. Water enters from rivers and groundwater (sources), flows through a series of filtration stages (transformations), is tested at multiple checkpoints for purity (data quality), and is delivered to homes and businesses (consumers). If a filtration stage fails, the facility does not send untreated water to consumers — it stops and alerts operators. If a sensor detects abnormal chemistry, it does not just log a warning — it triggers a shutdown. The system is designed with the assumption that failures will happen and that the consequences of delivering contaminated water (wrong data) are far worse than the inconvenience of a temporary supply interruption (pipeline downtime). Data pipeline design applies this same safety-first mindset.

A data pipeline is a sequence of steps that moves and transforms data from sources to consumers. Simple pipelines — a daily Pandas script that reads a CSV and appends rows to a database — are easy to understand but fragile: they have no retry logic, no data quality checks, no observability, and no safe restart capability. Complex pipelines — multi-stage Spark jobs with Kafka inputs, dbt transformations, and Airflow orchestration — have all of these properties but require significant expertise to build and operate. The art of data pipeline design is finding the simplest architecture that meets the reliability, correctness, and efficiency requirements for the specific use case.

The most underinvested area in pipeline design is observability. Most data engineers focus on correctness (does the pipeline produce the right output?) and reliability (does it run without crashing?) while treating observability as a log file to check when things go wrong. In practice, the most insidious pipeline failures are not crashes — they are silent correctness degradations: row counts that are 20% lower than expected, timestamps that are off by one day due to a timezone bug, amounts that are systematically inflated because a deduplication step was accidentally removed. These failures produce no exceptions and no alerts; they produce wrong dashboards that nobody checks against ground truth until a major business decision is made on bad data.

---

## How It Actually Works

**Layered Pipeline Architecture:**
```
[Sources] → [Raw/Bronze] → [Cleaned/Silver] → [Aggregated/Gold]
                ↑                 ↑                  ↑
              ingest            validate           business
              validate          transform          publish
              deduplicate       enrich
```

This "medallion architecture" (raw → silver → gold) is the standard pattern for data lake architectures. Each layer has a clear responsibility and a clear definition of quality. Raw (Bronze) is append-only, never modified — the source of truth for replaying transformations. Silver applies cleaning, type casting, deduplication, and standardization — every row in Silver is valid and deduplicated. Gold contains business-aggregated, publication-ready tables — the layer that dashboards and analysts query.

```python
# Pipeline with defensive extraction and quality gates
import pandas as pd
from typing import Optional
import logging

logger = logging.getLogger(__name__)

class DataQualityError(Exception):
    """Raised when data fails quality checks — pipeline should stop."""
    pass

def extract_with_validation(
    source: str,
    expected_min_rows: int = 1000,
    expected_schema: Optional[dict] = None,
) -> pd.DataFrame:
    """Extract data and fail fast on schema drift or empty results."""
    df = pd.read_parquet(source)

    # Row count check — defend against empty source
    if len(df) < expected_min_rows:
        raise DataQualityError(
            f"Source has {len(df)} rows, expected at least {expected_min_rows}. "
            "Possible extraction failure or upstream data issue."
        )

    # Schema check — detect drift before transforming
    if expected_schema:
        missing = set(expected_schema.keys()) - set(df.columns)
        if missing:
            raise DataQualityError(f"Schema drift detected. Missing columns: {missing}")

        for col, expected_dtype in expected_schema.items():
            if col in df.columns and str(df[col].dtype) != expected_dtype:
                logger.warning(f"Column {col}: expected {expected_dtype}, got {df[col].dtype}")

    logger.info(f"Extracted {len(df)} rows from {source}")
    return df

def transform_with_metadata(df: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    """Transform data and emit quality metadata."""
    original_count = len(df)
    df = df.dropna(subset=["order_id", "customer_id"])
    df = df.drop_duplicates(subset=["order_id"])
    df["amount_usd"] = df["amount_cents"] / 100.0
    df["processed_at"] = pd.Timestamp.utcnow()

    metadata = {
        "input_rows": original_count,
        "output_rows": len(df),
        "null_dropped": original_count - len(df.dropna(subset=["order_id", "customer_id"])),
        "dup_dropped": len(df.dropna(subset=["order_id", "customer_id"])) - len(df),
        "processing_time": pd.Timestamp.utcnow().isoformat(),
    }

    # Circuit breaker: if we're dropping more than 5% of rows, something is wrong
    drop_rate = (original_count - len(df)) / original_count
    if drop_rate > 0.05:
        raise DataQualityError(
            f"Drop rate {drop_rate:.1%} exceeds 5% threshold. "
            f"Check source data quality."
        )

    return df, metadata

def load_idempotent(df: pd.DataFrame, target_table: str, partition_col: str):
    """Load data using partition-replace semantics — safe to retry."""
    partitions = df[partition_col].unique()
    for partition in partitions:
        partition_df = df[df[partition_col] == partition]
        # Write atomically: delete existing partition, write new data
        # In production: use DeltaTable.merge() or warehouse MERGE INTO
        logger.info(f"Loading partition {partition}: {len(partition_df)} rows")
```

**Observability Design:**

Every pipeline run should emit a structured metadata record: input row count, output row count, processing duration, data freshness (max timestamp in the output), and a list of any quality check warnings. These records are themselves pipeline outputs, not just log lines. Storing them in a monitoring table enables trend detection: "row count for this pipeline has been declining 3% per week" is a signal that appears in a monitoring dashboard, not in a log grep.

Dead letter queues are the streaming equivalent of error tables: messages that cannot be processed (due to schema violations, business rule failures, or unexpected formats) are routed to a dead letter topic or table rather than causing the pipeline to halt. Operations can inspect and replay dead letters once the root cause is fixed, without losing the original data.

---

## How It Connects

ETL patterns provide the specific loading strategies (full refresh, incremental, upsert) that data pipeline design uses as building blocks for the transformation and loading phases.

[[etl-patterns|ETL Patterns]]

Airflow DAGs are the orchestration mechanism for managing the execution, retry, and scheduling of pipeline stages — the monitoring and alerting concerns in pipeline design map directly to Airflow's on_failure_callback, SLA tracking, and sensor-based wait logic.

[[airflow-basics|Apache Airflow Basics]]

dbt Models implement the transformation layer of ELT pipelines with built-in testing and lineage — the Silver and Gold layer design pattern maps naturally to dbt's staging and mart model layers.

[[dbt-basics|dbt Basics]]

---

## Common Misconceptions

Misconception 1: "A pipeline that runs without errors is a working pipeline."
Reality: A pipeline can run to completion, log "success," and produce systematically wrong data. A row count that is 30% lower than expected, a join that silently produces duplicates, an incremental load that is missing 3 days of data — all of these are "successful" jobs that are producing wrong results. Correctness assertions (row count checks, statistical validation, reconciliation against source) are separate from job success.

Misconception 2: "I should add retry logic everywhere to make my pipeline resilient."
Reality: Retrying a non-idempotent operation makes things worse. If a pipeline appends to a table on each run and you retry it after a crash, you get duplicate rows. Resilience comes from idempotent design first, then retries. Retrying an idempotent operation is safe; retrying a non-idempotent one amplifies the failure.

Misconception 3: "Logging everything means I have good observability."
Reality: Log lines are for debugging. Observability is about understanding the health of the system from the outside without reading individual log lines. Structured metrics (row counts, latency, freshness, error rates) stored in queryable tables or time-series databases provide observability. Log lines tell you what happened after something went wrong; metrics tell you that something is going wrong before it becomes a crisis.

---

## Why It Matters in Practice

Data pipeline reliability is directly proportional to organizational trust in data. A BI tool that produces wrong numbers — even once, even a small amount — takes months to regain analyst trust. Engineers who design pipelines with strong quality gates, clear idempotency, and observable metadata metrics build platforms that teams trust and use. Engineers who build fragile pipelines that occasionally produce wrong numbers build platforms that analysts work around with their own Excel spreadsheets.

The technical debt of poorly designed pipelines compounds quickly. A pipeline without schema validation breaks when the source system adds a column. A pipeline without row count monitoring goes unnoticed when a source outage cuts ingest volume by 90%. A pipeline without idempotency produces doubled data after every retry. These are not hypothetical edge cases — they are the standard failure modes of real production pipelines.

---

## Interview Angle

Common question forms:
- "What makes a data pipeline production-ready?"
- "How would you design a data pipeline that is safe to retry?"
- "What is observability in the context of data engineering?"

Answer frame:
Production-ready pipeline: idempotent (safe to retry — MERGE or partition-replace), schema-validated (detects source drift before processing), row-count checked (circuit breaker for anomalous drops), structured metadata output (row counts, freshness, processing time as first-class outputs, not just logs), tested (dbt tests or equivalent assertions at each layer), orchestrated with alerting (Airflow with on_failure callbacks). Safe-to-retry: MERGE or INSERT ON CONFLICT (upsert by key) or partition-replace (overwrite specific date range). Observability: structured metrics queryable in dashboards — not log files; track input/output row counts per run, data freshness (max timestamp), p99 processing latency.

---

## Related Notes

- [[etl-patterns|ETL Patterns]]
- [[airflow-basics|Apache Airflow Basics]]
- [[dbt-basics|dbt Basics]]
- [[pyspark-basics|PySpark Basics]]
- [[parquet|Parquet Format]]
