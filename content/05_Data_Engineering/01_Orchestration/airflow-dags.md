---
title: 02 - Airflow DAGs
description: "An Airflow DAG is a Python object that defines the structure, schedule, and defaults for a workflow  -  its configuration choices determine correctness, performance, and operational behavior."
tags: [airflow, dag, schedule, catchup, start-date, default-args, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Airflow DAGs

> The DAG object is the blueprint for an Airflow workflow  -  its scheduling semantics, catchup behavior, and default arguments are the levers that determine whether your pipeline runs correctly in production.

---

## Quick Reference

**Core idea:**
- `DAG(dag_id, schedule, start_date, catchup)`  -  the four most important constructor arguments
- `schedule` accepts cron strings (`"0 6 * * *"`), timedelta (`timedelta(hours=1)`), or timetable objects
- `catchup=True` (default) creates DagRuns for all missed intervals since `start_date`  -  usually dangerous in production
- `default_args` dict is merged into every task's constructor as keyword defaults
- Template variables: `{{ ds }}` (execution date YYYY-MM-DD), `{{ ts }}` (ISO timestamp), `{{ next_ds }}`, `{{ prev_ds }}`
- DAG-level params: `max_active_runs` (concurrent DagRun cap), `max_active_tasks` (concurrent task cap within a run)

**Tricky points:**
- DAG files are imported and evaluated by the scheduler every 30-60 seconds  -  heavy imports or DB calls at module level slow the entire scheduler
- `start_date` must be a fixed datetime in the past  -  using `datetime.now()` as `start_date` is a common mistake that creates scheduling drift
- The first DagRun's execution date is `start_date`  -  for a daily DAG starting on Jan 1, the first run happens at Jan 2 with execution_date=Jan 1 (interval-end semantics)
- Setting `depends_on_past=True` in `default_args` means each task instance waits for its previous-execution counterpart  -  easy to create deadlocks with `catchup=True`
- Tags are cosmetic (for UI filtering)  -  they have no effect on execution behavior

---

## What It Is

A construction blueprint describes a building: the rooms, how they connect, what materials to use, and when certain work must happen before other work can start. It does not build the building  -  it describes what should be built, and the contractor follows it. An Airflow DAG is that blueprint for a data workflow. The DAG file describes what tasks exist, how they depend on each other, and when the workflow should run. Airflow's scheduler reads the blueprint on a regular cadence and decides when to actually start building  -  creating concrete runs at the scheduled times.

The DAG object has two distinct concerns: structure and scheduling. Structure means the tasks and their dependency graph  -  which task must finish before the next one starts. Scheduling means when Airflow should instantiate that graph: every day at 6 AM, every hour, every fifteen minutes. The DAG object also carries default arguments that flow down to every task unless a task overrides them  -  things like retry counts, retry delay, and alert email addresses. This default_args pattern lets you set consistent operational behavior once at the DAG level rather than repeating it on every task.

One of the most important and frequently misunderstood aspects of Airflow scheduling is that runs are time-partition-oriented. Each DagRun covers a logical time interval and carries an execution date that marks the start of that interval. A daily DAG scheduled at midnight with `start_date=2024-01-01` does not run at midnight on January 1  -  it runs at midnight on January 2, covering the interval from January 1 to January 2. This is intentional: the run is meant to process data for the January 1 interval, and Airflow assumes that interval's data is available at its end (midnight January 2). Understanding this one-interval-behind semantics is essential for writing correct date-parameterized queries inside tasks.

---

## How It Actually Works

Airflow's scheduler parses DAG files using the `DagBag` loader, which imports every Python file in the `dags/` directory using `importlib`. The scheduler runs this parse cycle every `dag_dir_list_interval` seconds (default 5 minutes for file system changes; individual DAG re-evaluation is more frequent). This means every DAG file is Python code that runs in the scheduler's process. Objects created at module level, function calls made at import time, and database queries in the global scope all execute repeatedly in the scheduler's event loop  -  a common source of scheduler instability when DAG authors treat DAG files like application code.

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

# WRONG: expensive import at module level  -  runs every parse cycle
# import pandas as pd    # slow; runs in scheduler process
# df = pd.read_csv(...)  # NEVER do this at DAG module level

with DAG(
    dag_id="my_pipeline",
    schedule="@daily",                    # preset alias for "0 0 * * *"
    start_date=datetime(2024, 1, 1),      # fixed date in the past  -  not datetime.now()
    catchup=False,                        # don't create historical runs
    max_active_runs=1,                    # only one DagRun at a time
    default_args={
        "owner": "data-team",
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
        "execution_timeout": timedelta(hours=2),
    },
    tags=["sales"],
) as dag:

    def process(**context):
        # Access template variables via context dict
        execution_date = context["ds"]        # "2024-01-15"
        next_ds = context["next_ds"]          # "2024-01-16"
        print(f"Processing interval {execution_date} to {next_ds}")

    task = PythonOperator(
        task_id="process",
        python_callable=process,
    )
```

`catchup=False` is one of the most important production settings. With `catchup=True` (the default), if you deploy a DAG with `start_date=datetime(2020, 1, 1)` today in 2024, Airflow will immediately create over 1,400 DagRuns to "catch up" on the missed years. This can overwhelm the scheduler, the executor's worker pool, and any downstream systems the tasks touch. Setting `catchup=False` means only the most recent scheduled interval is created, which is the correct default for production pipelines that process today's data. Backfilling specific date ranges when needed is the explicit `airflow dags backfill` CLI command  -  a controlled operation rather than an automatic cascade.

The template engine in Airflow DAGs uses Jinja2. Template variables like `{{ ds }}`, `{{ ts }}`, and `{{ next_ds }}` are expanded at task execution time, not at DAG parse time. This allows task commands and SQL queries to reference the execution date dynamically. `{{ ds }}` is the execution date in YYYY-MM-DD format; `{{ ts }}` is the full ISO 8601 timestamp including time; `{{ macros.ds_add(ds, 7) }}` adds days to a date string. Custom variables can be passed via the DAG's `params` argument and accessed as `{{ params.my_variable }}`.

---

## How It Connects

The DAG object is the container; operators are the units of work that fill it. Understanding how task dependencies are set (using `>>` and `<<` operators or `set_upstream`/`set_downstream` methods) builds directly on understanding the DAG's directed acyclic structure.

[[airflow-operators|Airflow Operators]]

The TaskFlow API is an alternative way to define DAGs that uses Python decorators instead of explicit operator instantiation  -  it is built on top of the same DAG object but provides a cleaner syntax for Python-heavy workflows.

[[airflow-taskflow|Airflow TaskFlow API]]

---

## Common Misconceptions

Misconception 1: "I can use `datetime.now()` as the `start_date` so the DAG always starts from today."
Reality: `start_date` is evaluated at DAG parse time (which happens repeatedly in the scheduler process), not at run time. Using `datetime.now()` means the start date changes every few minutes as the scheduler re-parses the file, causing scheduling drift and unpredictable run creation. Always use a fixed, static datetime.

Misconception 2: "Setting `catchup=False` means Airflow will never run missed intervals."
Reality: `catchup=False` prevents automatic backfilling at deploy time. If your Airflow scheduler goes down for 3 days and comes back up with `catchup=False`, it creates only the most recent scheduled run  -  it skips the 3 days of missed runs. Use the `airflow dags backfill` command explicitly when you want to re-process missed intervals.

Misconception 3: "I can safely import my ETL library at the top of a DAG file."
Reality: DAG files are imported by the scheduler process every few minutes. Heavy imports (pandas, tensorflow, spark) that take seconds delay the scheduler's parse cycle and can cause task submissions to lag. Move heavy imports inside the callable function body so they happen only when the task actually executes, not at parse time.

---

## Why It Matters in Practice

DAG configuration mistakes are the most common source of operational incidents in Airflow deployments. `catchup=True` with a historical `start_date` creates DagRun storms that fill the executor queue and starve running pipelines. `depends_on_past=True` with `catchup=True` can deadlock a DAG  -  each run waits for the previous run's task to succeed, but if any past run is in a failed state, no future run can proceed. Heavy module-level code in DAG files degrades the scheduler's parse cycle, causing task submission delays that cascade into late-running pipelines.

Getting these settings right is a matter of understanding the architecture  -  the scheduler repeatedly imports your DAG file, executes the DagRun creation logic on a schedule, and tracks all state in a single database. Every DAG-level configuration choice has a concrete architectural consequence.

---

## Interview Angle

Common question forms:
- "What does `catchup=False` do in an Airflow DAG and when would you use it?"
- "Why should you avoid heavy imports at the module level of a DAG file?"
- "How do template variables like `{{ ds }}` work in Airflow?"

Answer frame:
For `catchup=False`: prevents automatic creation of DagRuns for every past scheduled interval between `start_date` and today  -  critical for production deploys with historical start dates. For heavy imports: DAG files run in the scheduler process on every parse cycle (every few minutes); expensive imports block the parse cycle and delay task scheduling across all DAGs. For templates: Jinja2 template strings in operator arguments are rendered at task execution time using the DagRun's execution date context  -  they let task commands reference the logical date of each run dynamically without hardcoding dates.

---

## Related Notes

- [[airflow-basics|Apache Airflow Basics]]
- [[airflow-operators|Airflow Operators]]
- [[airflow-taskflow|Airflow TaskFlow API]]
- [[airflow-sensors|Airflow Sensors]]
