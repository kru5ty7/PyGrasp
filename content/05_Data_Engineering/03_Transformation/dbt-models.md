---
title: 02 - dbt Models
description: "dbt models are SQL SELECT statements organized in a layered architecture — staging, intermediate, and marts — where each layer has a clear responsibility and models reference each other via `ref()`."
tags: [dbt, models, ref, materialization, jinja, staging, marts, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# dbt Models

> A dbt model is just a SELECT statement, but the discipline of how you name it, layer it, and configure it determines whether your data warehouse becomes a coherent data platform or a pile of tables nobody trusts.

---

## Quick Reference

**Core idea:**
- A model = one `.sql` file containing one SELECT statement that dbt wraps in `CREATE TABLE/VIEW AS ...`
- The recommended layer structure: `staging/` → `intermediate/` (optional) → `marts/`
- `{{ ref('model_name') }}` creates both a dependency and a correct schema-qualified table reference
- `{{ config(materialized='table', schema='reporting') }}` — per-model config in the file header
- `dbt_project.yml` can set materialization defaults by directory path
- Jinja2 macros (`{% set %}`, `{% for %}`, `{{ macro_name() }}`) allow reusable SQL generation

**Tricky points:**
- Models in `staging/` should have a 1:1 relationship with source tables — no joins, just renaming and light cleaning
- `unique_key` in incremental models must identify rows uniquely — non-unique keys cause duplicate rows after MERGE
- `ephemeral` models cannot be queried directly in the warehouse — they are inlined as CTEs in referencing models
- Changing a model's schema in `config` does not rename the existing table — dbt does not manage schema migrations
- Running `dbt run --select stg_orders` runs only that model; `+stg_orders` includes all upstream models; `stg_orders+` includes all downstream

---

## What It Is

A well-organized library has a clear system: books are grouped by genre, then by author, then by title. A history book about Napoleon belongs in history, not filed randomly under "interesting reads." Anyone who knows the system can find any book instantly. A library where books are shelved by when they arrived, or by how a particular librarian felt that day, frustrates every visitor. Data warehouses built without a naming and layering convention look like the second library: tables named `final_v3_REAL`, `orders_temp_backup`, `james_test_nov`, and `marketing_numbers`. dbt's model layering conventions are the Dewey Decimal System for warehouse tables.

The dbt community has converged on a three-layer architecture: staging, intermediate, and marts. Staging models sit closest to the raw data. Each staging model corresponds exactly to one source table and does nothing but rename columns to consistent conventions, cast types, and filter obviously invalid rows. No business logic, no joins. If the source table `raw_orders` has a column called `order_amt`, the staging model renames it `amount` and ensures it is a `NUMERIC` type — nothing more. The staging layer is the translation layer that insulates downstream models from source system naming chaos.

The marts layer sits at the other end: fact and dimension tables shaped for business consumption. `fct_orders` contains one row per order with all the attributes analysts need. `dim_customers` contains one row per customer. These tables follow dimensional modeling conventions and are the tables that BI tools, dashboards, and analysts query directly. The intermediate layer, when present, contains models that compute business logic building blocks used by multiple marts — a deduplication model, a session stitching model, a complex revenue calculation — that are too complicated for staging but too reusable to duplicate in every mart.

---

## How It Actually Works

dbt's compilation step processes every model's `.sql` file through Jinja2 before sending SQL to the warehouse. `{{ ref('stg_orders') }}` is a Jinja function call that dbt resolves to the fully qualified table name in the target schema — e.g., `mydb.dbt_staging.stg_orders`. This resolution is also what registers the DAG dependency. `{{ source('raw', 'orders') }}` resolves to the raw table name and registers a source freshness check obligation. The compiled SQL is exactly what gets executed: you can inspect it with `dbt compile` to see what SQL will run before executing it.

```sql
-- models/staging/stg_orders.sql
WITH source AS (
    SELECT * FROM {{ source('ecommerce', 'raw_orders') }}
),

cleaned AS (
    SELECT
        order_id::VARCHAR        AS order_id,
        customer_id::INTEGER     AS customer_id,
        order_date::DATE         AS order_date,
        UPPER(status)            AS status,
        amount_cents / 100.0     AS amount_usd,
        CURRENT_TIMESTAMP        AS _loaded_at
    FROM source
    WHERE order_id IS NOT NULL
      AND amount_cents > 0
)

SELECT * FROM cleaned
```

```sql
-- models/marts/fct_daily_revenue.sql
{{
  config(
    materialized='incremental',
    unique_key='order_date',
    on_schema_change='append_new_columns',
  )
}}

WITH orders AS (
    SELECT * FROM {{ ref('stg_orders') }}
    WHERE status = 'completed'
    {% if is_incremental() %}
        AND order_date >= (SELECT MAX(order_date) - INTERVAL '3 days' FROM {{ this }})
        -- Lookback 3 days to catch late-arriving records
    {% endif %}
),

daily_agg AS (
    SELECT
        order_date,
        COUNT(order_id)       AS order_count,
        SUM(amount_usd)       AS revenue_usd,
        AVG(amount_usd)       AS avg_order_value
    FROM orders
    GROUP BY 1
)

SELECT * FROM daily_agg
```

Jinja macros enable DRY SQL. A common use case is standardizing column computations across models:

```sql
-- macros/safe_divide.sql
{% macro safe_divide(numerator, denominator) %}
    CASE WHEN {{ denominator }} = 0 THEN NULL
         ELSE {{ numerator }} / {{ denominator }}
    END
{% endmacro %}

-- Usage in a model:
-- {{ safe_divide('revenue', 'order_count') }} AS avg_order_value
```

The `dbt_project.yml` allows setting config defaults by directory path, avoiding repetitive per-file config blocks:

```yaml
# dbt_project.yml
models:
  my_project:
    staging:
      +materialized: view          # all staging models are views
      +schema: staging
    marts:
      +materialized: table         # all mart models are tables
      +schema: reporting
      +tags: ["production"]
```

---

## How It Connects

dbt Tests validate the outputs of models — understanding model structure (primary keys, foreign keys, expected value sets) makes the test configuration natural.

[[dbt-tests|dbt Tests]]

dbt Basics establishes the fundamental concepts; dbt Models goes deeper into the layering conventions, incremental patterns, and Jinja templating that make up day-to-day dbt development.

[[dbt-basics|dbt Basics]]

---

## Common Misconceptions

Misconception 1: "I can put any SQL logic in a staging model — it's just the first step in my pipeline."
Reality: Staging models should be source-faithful — renaming, casting, and deduplication only. No joins, no business logic, no aggregations. Breaking this convention means downstream models depend on business logic baked into staging, making it impossible to reuse staging models without carrying unwanted transformations.

Misconception 2: "Incremental models always run faster than table models."
Reality: Incremental models run faster only when the filter correctly limits the rows processed to a small recent subset. An incremental model with a poorly written `is_incremental()` filter — or a filter on a non-indexed column that requires a full table scan — can be slower than a simple `table` materialization because it adds MERGE logic on top of the full scan.

Misconception 3: "`ephemeral` materialization is like a table but faster — good for all small intermediate models."
Reality: Ephemeral models are inlined as CTEs in every model that references them. If three models reference the same ephemeral model, that ephemeral model's SQL runs three times (once as a CTE in each referencing model). For models that are referenced multiple times, `view` materialization is more efficient — the SQL runs once per query.

---

## Why It Matters in Practice

The layering convention (staging → marts) is not bureaucratic overhead — it is the only reliable way to prevent a warehouse from becoming unmanageable at scale. Teams that skip staging and write joins and business logic directly on raw source tables find themselves refactoring ten downstream models every time a source system renames a column. The investment in a clean staging layer pays back every time a source system changes.

The `ref()` function's dual role — dependency tracking and table reference — is what makes dbt's lineage and `--select` targeting work. Teams that concatenate table names as strings (`SELECT * FROM raw.orders`) instead of using `ref()` break both lineage tracking and environment-specific schema routing (the feature where `dbt run --target dev` builds tables in the dev schema without any code changes).

---

## Interview Angle

Common question forms:
- "What is the recommended layer architecture for dbt models?"
- "How do you write an incremental dbt model correctly?"
- "What is the difference between `view`, `table`, and `ephemeral` materializations?"

Answer frame:
Layer architecture: staging (1:1 with sources, rename/cast only), intermediate (optional, reusable business logic), marts (fact and dimension tables for consumption). Incremental model: use `{{ config(materialized='incremental', unique_key='...') }}`, wrap the WHERE clause in `{% if is_incremental() %}...{% endif %}` to filter only new rows; `{{ this }}` references the current table for max-date comparisons. Materializations: `view` — no storage, SQL runs on each query; `table` — stored result, rebuilt on each `dbt run`; `ephemeral` — CTE inlined into referencing models, no warehouse object created; `incremental` — stored result, appends/merges new rows only.

---

## Related Notes

- [[dbt-basics|dbt Basics]]
- [[dbt-tests|dbt Tests]]
- [[etl-patterns|ETL Patterns]]
