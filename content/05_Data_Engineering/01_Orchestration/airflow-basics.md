---
title: 01 - Apache Airflow Basics
description: "Apache Airflow is a platform for programmatically authoring, scheduling, and monitoring data workflows as Directed Acyclic Graphs of tasks written in Python."
tags: [airflow, orchestration, scheduler, dag, workflow, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Apache Airflow Basics

> Airflow is the industry-standard Python workflow orchestrator  -  it turns data pipelines into versioned, observable, retryable code rather than cron jobs and shell scripts.

---

## Quick Reference

**Core idea:**
- Airflow defines workflows as Python code: a DAG (Directed Acyclic Graph) file describes task dependencies
- Core components: Scheduler, Webserver (UI), Worker(s), Metadata Database (PostgreSQL/MySQL), Message Broker (Redis/RabbitMQ for Celery executor)
- Every workflow is a `DAG` object; tasks are instances of `BaseOperator` subclasses or Python functions decorated with `@task`
- Scheduler reads DAG files, evaluates when to run, creates `DagRun` and `TaskInstance` records in the metadata DB
- Task states: `queued`, `running`, `success`, `failed`, `skipped`, `up_for_retry`, `upstream_failed`
- Execution date vs schedule interval: Airflow is time-partition oriented  -  each DagRun corresponds to a logical time interval

**Tricky points:**
- Airflow DAGs are not real-time streaming  -  they are batch scheduling; minimum practical interval is around 1 minute
- The "execution date" in Airflow refers to the **start** of the scheduled interval, not the actual time the run started
- DAG files are evaluated frequently by the scheduler  -  never put expensive or side-effectful code at module level in a DAG file
- Tasks are isolated: do not pass large data between tasks via return values (XCom is for small metadata, not DataFrames)
- Default `max_active_runs=16` and `max_active_tasks=16`  -  tune these to avoid overloading downstream systems

---

## What It Is

Think about the production line in a car factory. Building a car requires hundreds of steps: weld the frame, install the engine, attach doors, paint, test each system. These steps must happen in a specific order  -  you cannot install doors before the frame exists  -  but many steps can happen at the same time (painting one car while welding another). A supervisor tracks which steps are done, which are waiting, which have failed, and decides what can start next. If a step fails, the supervisor knows exactly which car it happened to and can restart just that step without scrapping the whole batch. Apache Airflow is that supervisor for data pipelines.

Airflow allows data engineers to describe their entire pipeline as Python code: which tasks exist, which tasks must complete before others can start, when the pipeline should run, and what to do if a task fails. Instead of managing a collection of cron jobs and shell scripts scattered across servers  -  where "what happened last Tuesday?" requires digging through log files  -  Airflow gives you a web interface that shows every pipeline run, the status of every task, the logs from every execution, and the ability to rerun any failed task with one click.

The central concept is the DAG  -  Directed Acyclic Graph. "Directed" means tasks have a defined direction: task A must complete before task B starts. "Acyclic" means there are no loops  -  a task cannot depend on itself either directly or transitively. "Graph" means multiple dependencies are allowed: task C can wait for both task A and task B. This graph structure is exactly what makes Airflow more powerful than cron: cron can run scripts on a schedule, but it cannot express "run this script only after these three other scripts finish successfully."

---

## How It Actually Works

Airflow's architecture has three mandatory components and one optional one. The Metadata Database (PostgreSQL in production) is the source of truth for everything: which DAGs exist, which DagRuns have been created, the current state of every TaskInstance, XCom values, and configuration. The Scheduler continuously reads DAG files from the filesystem (every 30-60 seconds by default), updates internal state, and submits task instances that are ready to run to the executor. The Webserver serves the UI (and the Airflow REST API). The Executor  -  `LocalExecutor`, `CeleryExecutor`, or `KubernetesExecutor`  -  determines how tasks are actually run: locally in subprocesses, on a pool of Celery workers, or as individual Kubernetes pods.

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta

default_args = {
    "owner": "data-team",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": True,
}

with DAG(
    dag_id="sales_pipeline",
    schedule="0 6 * * *",          # daily at 6 AM UTC
    start_date=datetime(2024, 1, 1),
    catchup=False,                  # don't backfill old runs
    default_args=default_args,
    tags=["sales", "production"],
) as dag:

    extract = BashOperator(
        task_id="extract_raw_data",
        bash_command="python /jobs/extract.py --date {{ ds }}",
    )

    def transform(**context):
        ds = context["ds"]   # execution date string YYYY-MM-DD
        print(f"Transforming data for {ds}")

    transform_task = PythonOperator(
        task_id="transform_data",
        python_callable=transform,
    )

    load = BashOperator(
        task_id="load_to_warehouse",
        bash_command="python /jobs/load.py --date {{ ds }}",
    )

    extract >> transform_task >> load    # define dependency order
```

The scheduler's heartbeat loop evaluates every active DAG against the current time and any pending DagRuns. For a DAG with `schedule="0 6 * * *"`, at 6:00 AM each day, the scheduler creates a `DagRun` with the logical execution date set to the previous midnight (the start of the interval). It then evaluates the DAG's task dependencies, finds tasks with no incomplete upstream dependencies, and sends their `TaskInstance` records to the executor. The executor launches each task in isolation (a subprocess, a Celery worker message, or a Kubernetes pod). When a task finishes, its state is written back to the metadata database, and the scheduler's next heartbeat picks up the new state and advances the DAG.

---

## How It Connects

Airflow DAGs are the top-level container for workflow logic; understanding the DAG object's properties, scheduling semantics, and execution model is essential before digging into operators, sensors, and the TaskFlow API.

[[airflow-dags|Airflow DAGs]]

The specific actions tasks perform are implemented by operators  -  BashOperator, PythonOperator, and hundreds of community-contributed operators for databases, cloud services, and ML platforms.

[[airflow-operators|Airflow Operators]]

ETL patterns describe the design-level concepts (extract, transform, load; incremental vs full refresh) that Airflow implements at the scheduling and orchestration level.

[[etl-patterns|ETL Patterns]]

---

## Common Misconceptions

Misconception 1: "Airflow is a data processing engine  -  it runs my transformations."
Reality: Airflow is an orchestrator. It schedules and monitors tasks but does not process data itself. A task might call a Python function that uses Pandas, or a BashOperator that runs a Spark job, or a `SnowflakeOperator` that executes a SQL query. Airflow manages the when and the if, not the how.

Misconception 2: "I can pass a Pandas DataFrame from one task to the next using XCom."
Reality: XCom (cross-communication) is stored in the metadata database and is designed for small values  -  task IDs, file paths, counts. Pushing a large DataFrame through XCom creates enormous metadata DB load and defeats the architecture. Pass file paths or database table references between tasks; let the actual data stay in storage.

Misconception 3: "Airflow can handle real-time or near-real-time event-driven pipelines."
Reality: Airflow's scheduler polls at intervals (seconds to minutes) and is designed for batch workflows. For event-driven pipelines responding in milliseconds or seconds, use a streaming tool (Kafka, Faust) or a workflow engine designed for event-driven execution (Prefect, Temporal).

---

## Why It Matters in Practice

Airflow is the workflow orchestration tool used by the majority of large data engineering teams. It solves a real coordination problem: as pipelines grow beyond a few scripts, manual scheduling becomes unreliable and opaque. Airflow provides dependency management (task B runs only if task A succeeded), retry logic (failed tasks retry automatically), backfilling (re-run historical dates after fixing a bug), observability (the UI shows exactly what ran, when, and what failed), and alerting (email or Slack on failure). These features are not nice-to-haves for production data pipelines  -  they are the baseline requirements.

Understanding Airflow architecture also prevents a class of common operational mistakes: running expensive Python at DAG parse time (breaks the scheduler), using XCom for large data transfers (fills the metadata database), using `catchup=True` without thinking (spawns hundreds of historical DagRuns simultaneously), and not setting `max_active_runs` (allows unbounded concurrent runs that overwhelm downstream systems).

---

## Interview Angle

Common question forms:
- "What is Airflow and what problem does it solve?"
- "Explain the main components of Airflow's architecture."
- "What is the difference between the execution date and the actual run time in Airflow?"

Answer frame:
Airflow is a batch workflow orchestrator: pipelines are Python DAGs, the scheduler creates runs on a time schedule, tasks are executed by the executor, and all state is persisted in the metadata database. Components: Scheduler (evaluates DAGs, creates TaskInstances), Webserver (UI and API), Executor (runs tasks  -  Local/Celery/Kubernetes), Metadata DB (PostgreSQL). Execution date vs run time: execution date is the logical time interval the run covers (e.g., yesterday's data), not the wall clock when the job ran  -  this supports backfilling where you re-run yesterday's logic on yesterday's data today.

---

## Related Notes

- [[airflow-dags|Airflow DAGs]]
- [[airflow-operators|Airflow Operators]]
- [[airflow-sensors|Airflow Sensors]]
- [[airflow-taskflow|Airflow TaskFlow API]]
- [[etl-patterns|ETL Patterns]]
