---
title: 09 - Dagster
description: "Dagster is a data orchestrator that centers its model on assets  -  named, typed data products  -  rather than tasks, enabling lineage tracking, freshness policies, and declarative pipeline management."
tags: [dagster, orchestration, assets, software-defined-assets, lineage, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Dagster

> Dagster inverts the orchestration mental model  -  instead of asking "what tasks should run?", it asks "what data assets should be fresh?"  -  and derives the execution plan from that declaration.

---

## Quick Reference

**Core idea:**
- `@asset` decorator: defines a data asset (table, file, model) as a Python function that produces it
- `@op` (operation) and `@job` (graph of ops): the lower-level task/workflow abstraction (equivalent to Airflow tasks/DAGs)
- `AssetMaterialization`: the act of running an asset's function and updating the produced data
- `IOManager`: handles reading and writing asset values to storage (filesystem, S3, database)
- `Definitions`: top-level object that registers all assets, jobs, schedules, and sensors for a deployment
- `dagster dev` runs a local development server with the UI at `localhost:3000`

**Tricky points:**
- Software-Defined Assets (SDA) are the recommended modern Dagster abstraction  -  prefer `@asset` over `@op`/`@job` for new pipelines
- Asset dependencies are inferred from function parameter names matching other asset names  -  `def downstream(upstream: dict)` auto-detects a dependency on the `upstream` asset
- `@asset` functions should be idempotent  -  Dagster may rematerialize them at any time; side effects in assets cause correctness problems
- `partitions` in Dagster allow time-based or categorical materialization of asset subsets  -  similar to Airflow's execution date but more explicit
- Dagster's type system (`DagsterType`) validates asset inputs and outputs  -  mismatched types raise at materialization time, not at definition time

---

## What It Is

Imagine a supply chain manager responsible for a warehouse full of products. The manager does not think in terms of "what machines should I turn on today?"  -  they think in terms of "which products need to be restocked?" The answer to the second question implies the first: to restock Product C, you need Parts A and B, which means starting Machine 1 and Machine 2. The manager declares which products should be available and when; the factory figures out the execution plan. Dagster applies this supply chain manager mindset to data. Instead of defining tasks ("run the transform script"), you define assets ("this is the `clean_sales` table, and it is produced from `raw_sales`"). Dagster's scheduler figures out what computations must run to keep your declared assets fresh.

An "asset" in Dagster is any named piece of data: a database table, a file in S3, a machine learning model, a dashboard. You define an asset by writing the Python function that creates or updates it, decorating it with `@asset`, and specifying what inputs it needs (which are other assets). Dagster builds a "data lineage graph" from these declarations  -  a visual map showing exactly how every asset in your organization's data platform was produced, from raw sources through every transformation step to final reports. This lineage graph is not a side effect of running the pipeline  -  it is the central artifact of the pipeline definition.

This asset-centric model provides capabilities that task-centric orchestrators like Airflow cannot match without substantial custom tooling. Freshness policies: Dagster can monitor asset staleness and alert or automatically rematerialize assets that are older than their policy allows. Selective materialization: because Dagster knows the lineage, it can rematerialize just the assets that depend on changed code or changed upstream data  -  a feature analogous to `dbt`'s `--select` model targeting. Cross-team collaboration: assets are named entities that can be owned by different teams, with clearly declared dependencies between them.

---

## How It Actually Works

A Dagster `@asset`-decorated function takes upstream assets as keyword arguments (Dagster resolves them from storage using the configured `IOManager`) and returns the value of the produced asset (which Dagster stores via the `IOManager`).

```python
from dagster import asset, AssetIn, Definitions, ScheduleDefinition, define_asset_job
import pandas as pd

@asset(group_name="raw")
def raw_sales() -> pd.DataFrame:
    """Fetches raw sales data from the source API."""
    # In production, fetch from an API or database
    return pd.DataFrame({
        "order_id": [1, 2, 3, 4, 5],
        "amount": [100.0, 50.0, 200.0, 75.0, 300.0],
        "region": ["North", "South", "North", "East", "South"],
        "date": ["2024-01-15"] * 5,
    })

@asset(group_name="transformed")
def clean_sales(raw_sales: pd.DataFrame) -> pd.DataFrame:
    """Removes rows with invalid amounts and adds a revenue bucket."""
    df = raw_sales[raw_sales["amount"] > 0].copy()
    df["bucket"] = pd.cut(df["amount"], bins=[0, 100, 250, float("inf")],
                          labels=["small", "medium", "large"])
    return df

@asset(group_name="aggregated")
def regional_summary(clean_sales: pd.DataFrame) -> pd.DataFrame:
    """Aggregates cleaned sales by region."""
    return (
        clean_sales
        .groupby("region")
        .agg(total=("amount", "sum"), count=("order_id", "count"))
        .reset_index()
    )

# Define the job (all three assets in execution order)
sales_job = define_asset_job("sales_job", selection="*")

# Schedule: run daily at 7 AM
daily_schedule = ScheduleDefinition(
    job=sales_job,
    cron_schedule="0 7 * * *",
)

# Register everything with Dagster
defs = Definitions(
    assets=[raw_sales, clean_sales, regional_summary],
    jobs=[sales_job],
    schedules=[daily_schedule],
)
```

The `Definitions` object is the single entry point for Dagster's deployment infrastructure. All assets, jobs, schedules, sensors, resources, and IO managers are registered in one `Definitions` instance. Dagster's `dagster dev` command reads this object, builds the lineage graph, and serves the UI. The `dagster-cloud` or `dagster-daemon` process reads the same `Definitions` to schedule and execute jobs.

`IOManager` is Dagster's abstraction for asset storage. By default, assets are stored as pickle files in a local directory. Custom `IOManagers` let you store assets in S3 (as Parquet), a database (as tables), or MLflow (as model artifacts). The clean separation between computation (what an asset is) and storage (where it lives) makes it possible to change storage backends without changing asset logic  -  a development environment uses local files while production uses S3.

Partitioned assets extend the model to time series and categorical slices. A partitioned `@asset` with a `DailyPartitionsDefinition` can materialize one partition (one day's data) independently of others  -  Dagster tracks which partitions are materialized and which are stale, enabling surgical reprocessing of specific date ranges without running the entire pipeline.

---

## How It Connects

Dagster assets and dbt models are directly complementary: dbt handles SQL-based transformations on a warehouse, while Dagster orchestrates the end-to-end pipeline including Python steps before and after dbt. Dagster has a first-class `dagster-dbt` integration that imports dbt models as Dagster assets, enabling a unified lineage graph.

[[dbt-basics|dbt Basics]]

ETL patterns describe the conceptual extract-transform-load flow; Dagster's asset model is a declarative way to express the same patterns, with the pipeline structure inferred from asset dependencies rather than explicitly coded task graphs.

[[etl-patterns|ETL Patterns]]

---

## Common Misconceptions

Misconception 1: "Dagster is just Airflow with a nicer UI  -  the core concepts are the same."
Reality: Dagster's fundamental unit is a data asset (a named data product), not a task (an action). The lineage graph is computed from declared asset dependencies; Airflow's DAG is explicitly authored task-by-task. Dagster supports automatic freshness monitoring, selective materialization, and cross-job asset tracking  -  capabilities that require significant custom tooling in Airflow.

Misconception 2: "I should use `@op` and `@job` for all Dagster pipelines because they give me more control."
Reality: `@op`/`@job` is the lower-level Dagster abstraction and predates the Software-Defined Assets model. For modern Dagster development, `@asset` is the recommended approach for most use cases. `@op`/`@job` is appropriate for workflows that do not produce named persistent data artifacts (e.g., sending notifications, running tests).

Misconception 3: "Dagster's asset model is only useful for analytics/warehouse pipelines  -  not for ETL."
Reality: Any data transformation that produces a named, persistent, reusable output is an asset  -  this includes raw extracts from APIs, intermediate cleaned tables, feature stores, trained models, and final reports. The asset model applies across the entire data engineering stack.

---

## Why It Matters in Practice

Dagster's asset-centric model addresses a real problem that grows with data platform complexity: at scale, nobody knows where data comes from or which jobs produce which tables. Data lineage becomes a manual documentation project, and when a source changes, it is unclear which downstream assets are affected. Dagster makes lineage the primary artifact  -  you cannot define an asset without implicitly declaring its dependencies, so lineage is always current.

The operational benefit of "freshness policies" is also underappreciated. Instead of an on-call engineer manually checking whether nightly jobs completed, Dagster can alert when an asset is stale beyond its policy and trigger automatic rematerialization. This shifts the operational model from "react to failures" to "declare expectations and let the system enforce them."

---

## Interview Angle

Common question forms:
- "What is a Software-Defined Asset in Dagster and how does it differ from an Airflow task?"
- "How does Dagster handle data lineage?"
- "When would you choose Dagster over Airflow or Prefect?"

Answer frame:
Software-Defined Asset: a `@asset`-decorated function that declares what data it produces and what data it depends on. Lineage is inferred from parameter names matching other asset names  -  Dagster builds the dependency graph automatically. Vs Airflow task: an asset is a named persistent data product; a task is an action. Airflow models "what runs"; Dagster models "what exists." Dagster for lineage: the UI shows a complete asset lineage graph from raw sources to final outputs, with materialization history and staleness status per asset. Choose Dagster when: data lineage observability is a priority, cross-team asset ownership needs to be explicit, or you want declarative freshness policies.

---

## Related Notes

- [[airflow-basics|Apache Airflow Basics]]
- [[etl-patterns|ETL Patterns]]
- [[dbt-basics|dbt Basics]]
