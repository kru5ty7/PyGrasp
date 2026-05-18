---
title: 01 - dbt Basics
description: "dbt (data build tool) is a SQL-first transformation framework that turns SELECT statements into versioned, tested, documented data models deployed to a data warehouse."
tags: [dbt, transformation, sql, data-warehouse, data-modeling, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# dbt Basics

> dbt applies software engineering practices  -  version control, testing, documentation, modular composition  -  to SQL-based data transformation, turning ad-hoc warehouse scripts into a maintainable, observable data platform.

---

## Quick Reference

**Core idea:**
- dbt compiles `.sql` model files into SQL `CREATE TABLE` or `CREATE VIEW` statements executed against a warehouse
- Core commands: `dbt run` (execute models), `dbt test` (validate data quality), `dbt docs generate && dbt docs serve` (documentation)
- Model references: `{{ ref('model_name') }}` resolves to the fully qualified table name and establishes a dependency edge in the DAG
- Materialization types: `view` (default), `table`, `incremental`, `ephemeral` (CTE, never persisted)
- Sources: `{{ source('raw_data', 'orders') }}` references raw warehouse tables with freshness checks
- Profiles: `profiles.yml` (outside the project) stores warehouse credentials  -  never commit it

**Tricky points:**
- `{{ ref() }}` is not just string interpolation  -  it registers a DAG dependency that dbt uses for run ordering and lineage
- `incremental` materialization requires an `is_incremental()` macro to write the correct WHERE clause  -  forgetting this causes a full re-scan on every run
- The `dbt` command-line tool runs SQL on the warehouse  -  it does not process data in Python; all computation happens in the warehouse
- `dbt test` runs SQL assertions  -  failing tests do not stop a `dbt run` by default; use `--select` and severity levels for blocking tests
- Schema changes (column additions) in incremental models require `--full-refresh` to rebuild the table

---

## What It Is

Imagine a large kitchen with dozens of cooks, all working from the same cookbook. The cookbook contains recipes: each recipe takes specific ingredients (inputs) and produces a dish (output). A complex dinner requires multiple recipes, each using the outputs of earlier recipes. If you update a recipe, you want to know which other recipes depend on it. You want a checklist to verify every dish meets quality standards. And you want the cookbook to be the single source of truth  -  not scattered handwritten notes on sticky pads around the kitchen. dbt is that cookbook for data transformations in a warehouse.

dbt centers on "models"  -  SQL SELECT statements that define how data should be structured. Each model is a `.sql` file that ends with a SELECT. dbt wraps that SELECT in a CREATE TABLE or CREATE VIEW statement and executes it in the target warehouse (Snowflake, BigQuery, Redshift, Databricks, PostgreSQL, and others). The model's filename becomes the table name. When model B needs data from model A, model B's SQL contains `{{ ref('model_a') }}`, which dbt resolves to the actual schema-qualified table name. This `ref()` function is what builds dbt's DAG  -  dbt knows model B depends on model A and must run A before B.

Before dbt, a common data engineering workflow was: write SQL scripts, schedule them with cron, store them in git (maybe), run tests occasionally (usually not), and maintain documentation manually (almost never). dbt makes all of these practices structural and enforced. Running `dbt run` compiles the DAG, executes models in dependency order, and produces a structured log. Running `dbt test` executes a suite of SQL assertions. Running `dbt docs generate` produces an interactive HTML documentation site from the model SQL and YAML descriptions. These are not optional add-ons  -  they are the standard workflow, which is why dbt spread rapidly once data teams tried it.

---

## How It Actually Works

A dbt project is a directory with a `dbt_project.yml` file at the root, a `models/` directory containing `.sql` files, and optionally `macros/`, `tests/`, `seeds/`, and `snapshots/` directories. `dbt_project.yml` configures the project name, profile (which warehouse to use), and model defaults (materialization type, schema). Running `dbt run` invokes the following sequence: parse all `.sql` files, resolve `{{ ref() }}` and `{{ source() }}` calls to build the DAG, topologically sort the DAG, compile each model's SQL (Jinja2 templating), and execute each model's CREATE statement against the warehouse.

```sql
-- models/staging/stg_orders.sql
-- Selects from a raw source table and renames columns

WITH source AS (
    SELECT * FROM {{ source('raw', 'orders') }}  -- raw warehouse table
),

renamed AS (
    SELECT
        order_id,
        customer_id,
        created_at AS order_date,
        total_amount_usd AS amount,
        status
    FROM source
    WHERE status != 'cancelled_test'
)

SELECT * FROM renamed
```

```sql
-- models/marts/fct_orders.sql
-- Business-logic model referencing the staging model

WITH orders AS (
    SELECT * FROM {{ ref('stg_orders') }}  -- dependency on stg_orders
),

customers AS (
    SELECT * FROM {{ ref('stg_customers') }}  -- another dependency
),

final AS (
    SELECT
        o.order_id,
        o.order_date,
        o.amount,
        c.customer_name,
        c.customer_region,
        DATEDIFF('day', c.signup_date, o.order_date) AS days_since_signup
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.customer_id
)

SELECT * FROM final
```

```yaml
# models/marts/schema.yml  -  documentation and tests
version: 2

models:
  - name: fct_orders
    description: "One row per order with customer and product enrichment"
    columns:
      - name: order_id
        description: "Primary key"
        tests:
          - unique
          - not_null
      - name: customer_region
        tests:
          - accepted_values:
              values: ["North", "South", "East", "West"]
```

The incremental materialization is dbt's mechanism for efficient updates to large tables. On the first run (`dbt run --full-refresh`), dbt builds the full table. On subsequent runs, dbt adds only new rows using the `is_incremental()` macro to filter the source data:

```sql
-- models/fct_events.sql
{{
  config(materialized='incremental', unique_key='event_id')
}}

SELECT
    event_id,
    user_id,
    event_type,
    created_at
FROM {{ source('raw', 'events') }}
{% if is_incremental() %}
    WHERE created_at > (SELECT MAX(created_at) FROM {{ this }})
{% endif %}
```

`{{ this }}` refers to the current model's table, allowing the incremental filter to check the latest timestamp already loaded. Without `is_incremental()`, the model would scan the full source table on every run  -  expensive for billion-row event tables.

---

## How It Connects

dbt produces tables and views in a data warehouse, but it does not move data into the warehouse  -  that is the "Extract and Load" (E+L) phase done by tools like Fivetran, Airbyte, or custom Python pipelines. Understanding ETL patterns provides the design context for where dbt fits.

[[etl-patterns|ETL Patterns]]

Airflow and Dagster both have first-class dbt integrations: dbt models appear as Dagster assets or Airflow operators. Understanding both the orchestration layer and dbt's model execution helps you design the full end-to-end pipeline.

[[airflow-basics|Apache Airflow Basics]]

Snowflake is one of the most common dbt targets  -  understanding Snowflake's virtual warehouse architecture, billing model, and query execution helps you write dbt models that are both correct and cost-efficient.

[[snowflake-python|Snowflake with Python]]

---

## Common Misconceptions

Misconception 1: "dbt processes data with Python  -  I can run Python transformations inside dbt models."
Reality: dbt executes SQL against a warehouse  -  it is a compilation and orchestration tool for SQL. All data processing happens in the warehouse's compute engine (Snowflake, BigQuery, etc.). dbt does not run Python code for transformations by default. (dbt Labs has experimental support for Python models in some adapters, but SQL is the primary model type.)

Misconception 2: "Setting a model to `incremental` materialization automatically makes it efficient on every run."
Reality: Incremental materialization is only efficient if the model correctly implements the `is_incremental()` filter to select only new/changed rows. An incremental model without this filter scans the full source on every run  -  identical cost to a `table` materialization, but with the additional overhead of a MERGE or INSERT.

Misconception 3: "`dbt test` failing means my `dbt run` stopped and nothing was loaded."
Reality: By default, `dbt test` is a separate command from `dbt run`. Running `dbt run` executes models; `dbt test` validates them. Tests do not block runs unless you configure `dbt build` (which runs models and tests together) and set test severity levels. Failed tests produce exit code 1 in `dbt test` but models already ran.

---

## Why It Matters in Practice

dbt has become the standard SQL transformation tool in the modern data stack because it solves the "analytics engineering" problem systematically. Before dbt, SQL transformations in data warehouses were poorly tracked, rarely tested, and undocumented  -  making data quality uncertain and onboarding new team members difficult. dbt brings the same practices that make software teams productive (version control, CI/CD, testing, documentation) to the data warehouse.

The `ref()` function deserves special attention as a force multiplier. Because every model dependency is declared with `ref()`, dbt always knows the full data lineage  -  which models depend on which raw tables, which business metrics depend on which intermediate models. This lineage is rendered in the docs UI and enables `dbt run --select +fct_orders+` to run just `fct_orders` and all its upstream and downstream models, rather than all models in the project.

---

## Interview Angle

Common question forms:
- "What is dbt and what problem does it solve in a data platform?"
- "What is the difference between `view`, `table`, and `incremental` materializations in dbt?"
- "How does dbt manage model dependencies?"

Answer frame:
dbt is a SQL transformation framework that compiles `.sql` model files into warehouse statements, manages execution order via a DAG, and provides testing and documentation tooling. Problem it solves: ad-hoc warehouse SQL scripts with no tests, no lineage tracking, and no documentation. Materializations: `view` (SQL re-executed each query, no storage cost), `table` (materialized to disk on each run), `incremental` (append/merge new rows only  -  requires `is_incremental()` filter), `ephemeral` (CTE inlined into referencing models, never a real table). Dependencies: `{{ ref('model_name') }}` compiles to the table name AND registers a DAG edge  -  dbt topologically sorts and runs models in dependency order.

---

## Related Notes

- [[dbt-models|dbt Models]]
- [[dbt-tests|dbt Tests]]
- [[etl-patterns|ETL Patterns]]
- [[snowflake-python|Snowflake with Python]]
- [[airflow-basics|Apache Airflow Basics]]
