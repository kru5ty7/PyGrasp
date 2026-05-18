---
title: 04 - Airflow Sensors
description: "Airflow Sensors are operators that repeatedly poll for a condition to be met before succeeding  -  their `mode` setting determines whether they occupy a worker slot the whole time or yield it between checks."
tags: [airflow, sensors, poking, reschedule, sensor-mode, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Airflow Sensors

> A Sensor is a task that waits  -  and the `mode` parameter determines whether it waits by occupying a worker forever or by politely stepping aside between checks, which is the difference between blocking your pipeline and clogging your entire Airflow cluster.

---

## Quick Reference

**Core idea:**
- Sensors inherit from `BaseSensorOperator` and override `poke(context)`  -  returns `True` when condition is met, `False` to keep waiting
- `mode="poke"` (default): sensor occupies a worker slot continuously, sleeping `poke_interval` seconds between checks
- `mode="reschedule"`: sensor releases its worker slot between checks  -  task is rescheduled by the Airflow scheduler
- `timeout` sets the maximum wall-clock seconds before the sensor marks itself as failed
- Common sensors: `FileSensor`, `S3KeySensor`, `HttpSensor`, `SqlSensor`, `ExternalTaskSensor`, `TimeDeltaSensor`
- `soft_fail=True`: sensor marks as `skipped` instead of `failed` on timeout  -  useful for optional dependencies

**Tricky points:**
- In `poke` mode, each sensor holds a worker slot for its entire duration  -  10 sensors with 1-hour waits occupies 10 worker slots for an hour; set `mode="reschedule"` for long-wait sensors
- `poke_interval` defaults to 60 seconds  -  reduce for time-sensitive pipelines, increase to reduce scheduler load for hour-long waits
- `ExternalTaskSensor` checks the state of a task or DAG in another DAG run  -  it is the canonical way to create cross-DAG dependencies without merging them
- `timeout` counts from when the sensor starts, not from the DAG run's start  -  a delayed upstream task can eat into the sensor's effective timeout
- Sensors in `reschedule` mode cannot share state between pokes  -  `poke()` must re-read state from an external source every call

---

## What It Is

Think of a factory assembly line waiting for a parts delivery. One worker could stand at the loading dock and stare at the empty parking lot all day, refusing to do anything else until the truck arrives. That worker is occupied and contributes nothing for the whole wait. Alternatively, the worker could check the dock every fifteen minutes between doing other jobs, returning to their workstation in between. The delivery gets noticed within fifteen minutes of arrival, and the worker contributes productive time between checks. Airflow sensors have both modes, and choosing the wrong one is like assigning every waiting worker the first approach  -  all workers end up staring at empty parking lots.

A Sensor is an Airflow operator specialized for waiting. Instead of performing work immediately when its upstream tasks finish, a Sensor repeatedly checks whether some external condition has become true: a file has appeared in an S3 bucket, a SQL query returns rows, an HTTP endpoint returns a success status, or another Airflow DAG run has completed. The sensor returns success only when the condition is met, letting downstream tasks proceed. If the condition is not met within the `timeout` duration, the sensor marks itself as failed and (by default) the downstream tasks are marked `upstream_failed`.

The `mode` parameter is the most important operational choice when using a Sensor. `mode="poke"` is the default and is appropriate for short waits (seconds to a few minutes): the sensor holds its worker slot, sleeps for `poke_interval` seconds, calls `poke()` again, and repeats. `mode="reschedule"` is essential for long waits: after each failed `poke()`, the sensor task releases its worker slot and asks the Airflow scheduler to reschedule it after `poke_interval` seconds. The worker is free to run other tasks in the meantime. For a cluster with 10 worker slots and 5 sensors each waiting up to an hour, `mode="poke"` means 5 workers are occupied for an hour; `mode="reschedule"` means those 5 worker slots are available for other tasks between pokes.

---

## How It Actually Works

`BaseSensorOperator.execute()` is a loop. It calls `self.poke(context)` and, if that returns `False`, either sleeps for `poke_interval` (in `poke` mode) or raises `AirflowRescheduleException` (in `reschedule` mode), which signals the executor to release the worker slot and schedule a reschedule. In `reschedule` mode, Airflow writes the scheduled next-poke time to the `task_reschedule` table in the metadata database, and the scheduler creates a new task execution when that time arrives.

```python
from airflow import DAG
from airflow.sensors.filesystem import FileSensor
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

with DAG(
    "data_ingestion",
    schedule="@hourly",
    start_date=datetime(2024, 1, 1),
    catchup=False,
) as dag:

    # Wait for a file to appear  -  reschedule mode for longer waits
    wait_for_file = FileSensor(
        task_id="wait_for_input_file",
        filepath="/data/input/{{ ds }}/data.csv",
        fs_conn_id="local_fs",
        poke_interval=60,           # check every minute
        timeout=3600,               # give up after 1 hour
        mode="reschedule",          # don't hog a worker slot
        soft_fail=False,            # fail the DAG if file never arrives
    )

    # Wait for an S3 object
    wait_for_s3 = S3KeySensor(
        task_id="wait_for_s3_upload",
        bucket_name="my-data-bucket",
        bucket_key="uploads/{{ ds }}/report.parquet",
        aws_conn_id="aws_default",
        poke_interval=30,
        timeout=7200,
        mode="reschedule",
    )

    # Cross-DAG dependency: wait for upstream DAG's extract task to succeed
    wait_for_upstream = ExternalTaskSensor(
        task_id="wait_for_upstream",
        external_dag_id="upstream_pipeline",
        external_task_id="extract_done",
        execution_delta=timedelta(hours=1),   # upstream runs 1 hour earlier
        mode="reschedule",
        timeout=3600,
    )

    def process(**context):
        print(f"Processing data for {context['ds']}")

    process_task = PythonOperator(
        task_id="process",
        python_callable=process,
    )

    [wait_for_file, wait_for_s3] >> wait_for_upstream >> process_task
```

Writing a custom sensor requires subclassing `BaseSensorOperator` and implementing `poke(self, context)`:

```python
from airflow.sensors.base import BaseSensorOperator

class RowCountSensor(BaseSensorOperator):
    template_fields = ("table", "ds")

    def __init__(self, table: str, min_rows: int, conn_id: str, **kwargs):
        super().__init__(**kwargs)
        self.table = table
        self.min_rows = min_rows
        self.conn_id = conn_id

    def poke(self, context) -> bool:
        from airflow.providers.postgres.hooks.postgres import PostgresHook
        hook = PostgresHook(self.conn_id)
        count = hook.get_first(f"SELECT COUNT(*) FROM {self.table}")[0]
        self.log.info("Found %d rows, need %d", count, self.min_rows)
        return count >= self.min_rows
```

`ExternalTaskSensor` is the only Airflow-native mechanism for cross-DAG dependencies. It queries the metadata database for the state of a specific task or DAG run in another DAG. The `execution_delta` or `execution_date_fn` argument handles the case where the upstream and downstream DAGs run on different schedules or with a time offset. Without this sensor, cross-DAG dependencies are typically managed by the `TriggerDagRunOperator` (push model) or by sharing a flag in external storage (file, database table), but `ExternalTaskSensor` provides observable, retry-aware dependencies in the Airflow UI.

---

## How It Connects

Sensors are specialized operators  -  they share the same `BaseOperator` inheritance and are configured like any task in a DAG. Understanding operator trigger rules matters for sensors too: a downstream task's `trigger_rule` determines whether it runs if the sensor times out with `soft_fail=True`.

[[airflow-operators|Airflow Operators]]

Connections and Hooks provide the credentials and connection management that most sensors use internally  -  a `FileSensor` uses a filesystem connection, an `S3KeySensor` uses an AWS connection.

[[airflow-connections|Airflow Connections and Hooks]]

---

## Common Misconceptions

Misconception 1: "Sensors in `poke` mode are fine  -  they're just waiting, not doing real work, so they don't consume resources."
Reality: In `poke` mode, a sensor holds a worker slot for its entire duration. A Celery executor configured with 10 workers and 10 sensors all in `poke` mode leaves zero worker slots for actual processing tasks. Use `mode="reschedule"` for any sensor with a `poke_interval` longer than a few seconds.

Misconception 2: "`ExternalTaskSensor` can only sense the current execution date's matching run in the upstream DAG."
Reality: By default, `ExternalTaskSensor` checks for the upstream task at the same execution date as the current DAG run. Use `execution_delta=timedelta(hours=1)` to check for a run that happened one hour earlier, or `execution_date_fn=some_function` for custom alignment logic. Getting this alignment wrong is the most common `ExternalTaskSensor` bug.

Misconception 3: "`timeout` on a Sensor means the pipeline waits up to that many seconds before continuing with downstream tasks."
Reality: When a Sensor times out, it raises `AirflowSensorTimeout` and the task state becomes `failed` (or `skipped` if `soft_fail=True`). Downstream tasks become `upstream_failed` or `skipped`. The pipeline does not continue normally  -  it stops at the failed sensor. Design pipelines with appropriate `timeout` values and handle the timeout case explicitly.

---

## Why It Matters in Practice

Sensors are the glue between external systems and Airflow's internal dependency model. Without sensors, a pipeline that depends on an upstream data source (a file from a vendor, an S3 upload from an IoT device, another team's DAG completing) must either hardcode a fixed delay (unreliable) or be triggered externally (loses Airflow's dependency visualization). Sensors provide observable, retry-aware, alerting-capable waiting behavior that is far more operationally robust than either alternative.

The `mode="reschedule"` setting is not optional at scale. In a cluster where multiple pipelines all have sensors waiting for hourly data deliveries, `poke` mode will eventually cause a sensor deadlock  -  all worker slots occupied by waiting sensors, no workers available to actually run tasks, the entire cluster grinding to a halt.

---

## Interview Angle

Common question forms:
- "What is the difference between `mode='poke'` and `mode='reschedule'` in Airflow sensors?"
- "When would you use `ExternalTaskSensor` and what are the gotchas?"
- "How do you create cross-DAG dependencies in Airflow?"

Answer frame:
`poke` mode holds a worker slot continuously  -  appropriate for sub-minute waits. `reschedule` mode releases the slot between pokes  -  required for waits of minutes to hours to avoid worker slot exhaustion. `ExternalTaskSensor` reads another DAG/task's state from the metadata DB  -  the main gotcha is `execution_delta` alignment: if the upstream DAG runs at a different time, you must configure the delta correctly or the sensor will never find a matching run. Cross-DAG dependencies: `ExternalTaskSensor` (pull, observable), `TriggerDagRunOperator` (push), or external flag in S3/database.

---

## Related Notes

- [[airflow-basics|Apache Airflow Basics]]
- [[airflow-operators|Airflow Operators]]
- [[airflow-connections|Airflow Connections and Hooks]]
