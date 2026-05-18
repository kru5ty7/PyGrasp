---
title: 08 - Prefect
description: "Prefect is a modern Python workflow orchestrator that uses decorators to turn regular Python functions into observable, retriable, scheduled flows without requiring DAG file conventions or a separate scheduler process for local development."
tags: [prefect, orchestration, flows, tasks, deployments, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Prefect

> Prefect turns regular Python code into observable, retriable workflows using decorators  -  the developer experience prioritizes Python-first design over the XML/config-centric patterns of older orchestrators.

---

## Quick Reference

**Core idea:**
- `@flow` decorator wraps a Python function as a Prefect flow (top-level unit of orchestration)
- `@task` decorator wraps a function as a retriable, observable task within a flow
- Flows can be run locally with `flow_fn()`  -  no separate infrastructure required for development
- `Deployment` or `flow.serve()` publishes a flow for remote scheduling and execution
- Prefect Cloud / Prefect Server: the orchestration backend; manages flow run state, logs, and work queues
- `Blocks` store external credentials and configuration (equivalent to Airflow Connections)

**Tricky points:**
- A `@flow` can call another `@flow` (subflows)  -  unlike Airflow DAGs, nested flows are natively supported
- Task caching: `@task(cache_key_fn=task_input_hash, cache_expiration=timedelta(hours=1))`  -  avoids re-running identical inputs
- `@task` without `@flow` is valid Python but provides no orchestration context  -  always call tasks from within a flow
- Prefect 2.x (current) is a complete rewrite from Prefect 1.x  -  APIs are incompatible; ignore 1.x examples
- `Workers` and `Work Pools` replaced Prefect 1.x's `Agents`  -  work pool type determines execution environment (process, Docker, Kubernetes)

---

## What It Is

Imagine you have a set of Python scripts that together form a data pipeline: one script downloads data, another cleans it, a third loads it to a database. Running them in order manually works fine on your laptop. The problems appear in production: what happens when the download fails halfway through  -  do you start over from scratch? How do you know what ran yesterday? How do you schedule this to run every morning without logging in and typing commands? How do you get a notification if it fails at 3 AM? Prefect answers all of these questions by wrapping your existing Python functions in two decorators  -  `@flow` and `@task`  -  and connecting them to an orchestration server that handles scheduling, state tracking, retries, and alerting.

The key design principle of Prefect is "Python-first." A Prefect flow is a regular Python function. A Prefect task is a regular Python function. You can run a Prefect flow by calling the function: `my_pipeline()`. No DAG file conventions, no separate scheduler process to start, no special Python environment required for local testing. The orchestration layer is optional and additive  -  you get full observability and scheduling when you connect to Prefect Cloud or run a local Prefect server, but your code works as vanilla Python even without it. This is a deliberate departure from Airflow's design, where running a DAG requires the full Airflow stack.

Prefect's state model is also more expressive than Airflow's. Every flow run and task run has a state: `Pending`, `Running`, `Completed`, `Failed`, `Cancelled`, `Crashed`, `Paused`, `Scheduling`. State transitions trigger hooks  -  functions that run automatically when a flow or task enters a specific state. A `Failed` state triggers retry logic if `retries` is configured; it also triggers any `on_failure` hook you register. The state machine is visible in real time in the Prefect UI, with the full task log available alongside it.

---

## How It Actually Works

When you decorate a function with `@flow`, Prefect wraps it in a `Flow` object. Calling the wrapped function creates a `FlowRun` record (locally in memory, or in the Prefect server if connected), runs the function body, and records the final state. Within the function body, every call to a `@task`-decorated function creates a `TaskRun` record, executes the function, and stores the result for caching and observability.

```python
from prefect import flow, task
from prefect.tasks import task_input_hash
from datetime import timedelta
import httpx

@task(
    retries=3,
    retry_delay_seconds=30,
    cache_key_fn=task_input_hash,
    cache_expiration=timedelta(hours=1),
    log_prints=True,
)
def fetch_data(url: str) -> dict:
    response = httpx.get(url, timeout=30)
    response.raise_for_status()
    print(f"Fetched {len(response.content)} bytes from {url}")
    return response.json()

@task(retries=1)
def transform(data: dict) -> list[dict]:
    return [
        {"id": item["id"], "value": item["value"] * 2}
        for item in data.get("items", [])
        if item.get("active")
    ]

@task()
def load(records: list[dict], destination: str) -> int:
    # Write to database
    print(f"Loading {len(records)} records to {destination}")
    return len(records)

@flow(
    name="daily-sales-pipeline",
    description="Fetch, transform, and load sales data",
    log_prints=True,
)
def sales_pipeline(date: str, api_url: str = "https://api.example.com/sales"):
    raw = fetch_data(f"{api_url}?date={date}")
    cleaned = transform(raw)
    count = load(cleaned, destination="sales_table")
    return count

# Run locally  -  no server required
if __name__ == "__main__":
    result = sales_pipeline(date="2024-01-15")
    print(f"Loaded {result} records")

# Deploy to Prefect Cloud / Server
# sales_pipeline.serve(name="daily-run", cron="0 6 * * *")
```

Prefect's task runner controls how tasks execute. The default `ConcurrentTaskRunner` uses `asyncio` to run tasks concurrently when possible (tasks with no interdependency). The `DaskTaskRunner` distributes tasks across a Dask cluster. The `RayTaskRunner` distributes tasks across a Ray cluster. The runner is configured at the flow level: `@flow(task_runner=DaskTaskRunner())`. This makes Prefect composable with distributed compute frameworks in a way Airflow is not without custom operators.

Prefect `Blocks` are the credential and configuration management system, analogous to Airflow Connections. A `Block` is a Pydantic model whose fields are stored (with secret fields encrypted) in the Prefect server. Common blocks: `Secret` (arbitrary secret string), `S3Bucket` (AWS S3 credentials + bucket name), `SnowflakeCredentials`, `SlackWebhook`. You create a Block once via the UI or API, reference it in code as `S3Bucket.load("my-bucket")`, and the credentials are fetched at task execution time.

---

## How It Connects

Prefect and Airflow are direct competitors addressing the same orchestration problem with different philosophies  -  Airflow is DAG-file-centric with broad operator ecosystem; Prefect is Python-first with simpler local development. Understanding both helps you choose based on team skill set, existing infrastructure, and scale requirements.

[[airflow-basics|Apache Airflow Basics]]

ETL patterns describe the design-level concepts (extract, transform, load; incremental loading; idempotency) that Prefect flows implement  -  the `@task` decorator makes these patterns explicit at the function level.

[[etl-patterns|ETL Patterns]]

---

## Common Misconceptions

Misconception 1: "Prefect is just Airflow with a nicer API  -  the underlying concepts are the same."
Reality: Prefect has fundamentally different execution semantics. Prefect flows run as regular Python function calls; Airflow DAGs are serialized to JSON and executed by remote workers. Prefect supports subflows natively; Airflow cross-DAG dependencies require `ExternalTaskSensor`. Prefect tasks can return any Python object within a flow run; Airflow tasks communicate only through XCom. They solve similar problems but with different architecture.

Misconception 2: "I need to run a Prefect server to test my flows locally."
Reality: Prefect flows run as plain Python  -  `flow_fn()` runs the flow in-process without any server. You only need a Prefect server (or Prefect Cloud) for scheduling, remote execution, and the observability UI. This is one of Prefect's key design advantages for development iteration speed.

Misconception 3: "Prefect's `@task` retries are the same as simply wrapping a function in a try/except retry loop."
Reality: Prefect retries are managed by the orchestration engine  -  they respect state transitions, can be observed in the UI, and do not block the flow runner thread between attempts (the task is rescheduled). A try/except loop in user code is blocking and invisible to the orchestration layer.

---

## Why It Matters in Practice

Prefect's Python-first design dramatically shortens the development cycle for data engineers who are building pipelines iteratively. Testing an Airflow DAG requires the full Airflow stack running, DAG files in the correct directory, and waiting for the scheduler to pick up the new file. Testing a Prefect flow requires calling a function. This iteration speed advantage is real and material for teams building complex pipelines.

Prefect Cloud's managed offering also eliminates the operational burden of running an Airflow cluster  -  no scheduler to maintain, no metadata database to tune, no broker to monitor. For teams that primarily need scheduling, observability, and retries without complex operator ecosystems, Prefect is often the lower total-cost option.

---

## Interview Angle

Common question forms:
- "How does Prefect differ from Airflow as a workflow orchestrator?"
- "What is a Prefect flow and how does it relate to Prefect tasks?"
- "What is the advantage of Prefect's Python-first design for development?"

Answer frame:
Flows are `@flow`-decorated Python functions  -  the top-level orchestration unit. Tasks are `@task`-decorated functions  -  the retriable, observable work units called from within flows. Vs Airflow: Prefect is Python-first (flows run as functions, no DAG file convention), supports subflows natively, has per-task result caching, and uses Blocks instead of Connections. Key advantage: flows run as plain Python locally  -  no server required for testing. Airflow advantage: mature operator ecosystem, more customizable executors, wider industry adoption.

---

## Related Notes

- [[airflow-basics|Apache Airflow Basics]]
- [[etl-patterns|ETL Patterns]]

<!-- MISSING_NOTE: dagster -->
