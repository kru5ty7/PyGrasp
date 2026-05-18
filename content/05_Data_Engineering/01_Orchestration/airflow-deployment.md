---
title: 07 - Airflow Deployment
description: "Deploying Airflow in production requires choosing an executor, configuring the metadata database, deploying DAG files, and understanding the operational tradeoffs between LocalExecutor, CeleryExecutor, and KubernetesExecutor."
tags: [airflow, deployment, executor, celery, kubernetes, docker, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Airflow Deployment

> The executor choice is the most consequential Airflow deployment decision  -  it determines task isolation, scalability, resource consumption, and operational complexity.

---

## Quick Reference

**Core idea:**
- Executors: `SequentialExecutor` (single process, dev only), `LocalExecutor` (subprocess on scheduler host), `CeleryExecutor` (distributed workers + broker), `KubernetesExecutor` (one pod per task)
- Metadata DB: PostgreSQL (production requirement); SQLite is dev-only; proper indexing and connection pooling via PgBouncer for scale
- DAG sync methods: shared filesystem (NFS), `git-sync` sidecar, baked-into-image, GCS/S3 sync script
- Environment: all Airflow components must share the same Python environment, the same `AIRFLOW_HOME`, and the same DAG files
- `AIRFLOW__CORE__EXECUTOR`, `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN`, `AIRFLOW__CORE__DAGS_FOLDER`  -  the three foundational config settings
- Managed Airflow: AWS MWAA, Google Cloud Composer, Astronomer  -  managed services handle infrastructure; you manage DAG code

**Tricky points:**
- All workers and the scheduler must have identical Python package versions  -  mismatches cause silent task failures
- CeleryExecutor requires a message broker (Redis or RabbitMQ) in addition to the metadata DB
- KubernetesExecutor starts a new pod per task  -  cold start latency (5-30 seconds) makes it unsuitable for high-frequency small tasks
- DAG files must be available on **both** the scheduler and the workers  -  a DAG on the scheduler but not on workers causes deserialization errors
- `airflow db migrate` (formerly `airflow db upgrade`) must run before starting the scheduler after any Airflow version upgrade

---

## What It Is

Running Airflow in development is straightforward: `pip install apache-airflow` and `airflow standalone` spins up everything in one process on your laptop. Production is a different environment entirely. A production Airflow deployment needs to process hundreds of task executions per hour, survive component failures without losing state, isolate tasks so one failing task cannot crash others, scale worker capacity up and down based on load, and provide a clear operational picture of what is running and what has failed. Achieving this requires making intentional architectural decisions about how tasks run, how DAG files are distributed, and how all components stay synchronized.

The executor is the core architectural decision. It answers one question: when Airflow decides a task should run, how does it actually start that task? The `LocalExecutor` spawns a subprocess on the machine running the scheduler  -  simple, no extra infrastructure, but limited to one machine's CPU and memory. The `CeleryExecutor` sends task messages to a broker (Redis or RabbitMQ), which are picked up by Celery worker processes that can run on any number of machines  -  this is the traditional scaling solution, but it requires operating the broker as an additional production dependency. The `KubernetesExecutor` creates a new Kubernetes pod for every task  -  perfect isolation, inherent autoscaling with the cluster, but significant latency per task and requires a Kubernetes cluster.

Deploying DAG files is a distribution problem with no single right answer. In small teams on a single machine, a shared NFS mount works. In Kubernetes-based deployments, the `git-sync` sidecar container pattern polls a git repository and syncs DAG files to a shared volume  -  enabling GitOps-style pipeline deployment where merging a PR deploys a DAG change automatically. Baking DAGs into the Docker image creates a complete deployment artifact (image + DAGs + dependencies in one container) at the cost of requiring image rebuilds for every DAG change. Managed services like AWS MWAA sync DAGs from an S3 bucket.

---

## How It Actually Works

A production Airflow deployment consists of at minimum: a PostgreSQL metadata database, a Scheduler process, a Webserver process, and one or more Worker processes (if using Celery). All components share two external resources: the metadata database (all state) and the DAG files (the pipeline definitions). The scheduler reads DAG files, creates `DagRun` and `TaskInstance` records in the database, and submits ready tasks to the executor. The executor distributes those tasks to worker processes. Workers execute the tasks and write results (success/failure state, XCom) back to the database. The webserver reads the database to serve the UI.

```yaml
# docker-compose.yml (abbreviated) for CeleryExecutor deployment
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow

  redis:
    image: redis:7          # Celery broker

  airflow-common: &airflow-common
    image: apache/airflow:2.9.0
    environment:
      AIRFLOW__CORE__EXECUTOR: CeleryExecutor
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
      AIRFLOW__CELERY__RESULT_BACKEND: db+postgresql://airflow:airflow@postgres/airflow
      AIRFLOW__CELERY__BROKER_URL: redis://:@redis:6379/0
      AIRFLOW__CORE__FERNET_KEY: ''       # set for encryption
      AIRFLOW__CORE__DAGS_FOLDER: /opt/airflow/dags
    volumes:
      - ./dags:/opt/airflow/dags          # DAG files from local mount
      - ./logs:/opt/airflow/logs

  scheduler:
    <<: *airflow-common
    command: scheduler

  webserver:
    <<: *airflow-common
    command: webserver
    ports:
      - "8080:8080"

  worker:
    <<: *airflow-common
    command: celery worker
    # Scale: docker-compose up --scale worker=4
```

For Kubernetes deployments, the official Helm chart (`apache-airflow/airflow`) manages the scheduler, webserver, and workers as Kubernetes Deployments, with ConfigMaps for airflow.cfg and Secrets for sensitive configuration. `KubernetesExecutor` creates a `TaskInstance`-specific Pod specification on demand, launches the pod, waits for it to complete, and reads the result from the metadata DB. The pod runs an `airflow tasks run` command with the specific DAG ID, task ID, and execution date. Each task pod requires the same Docker image as the scheduler  -  containing both the Airflow install and the task's Python dependencies  -  which is why dependency management becomes image management in Kubernetes deployments.

The `AIRFLOW__CORE__PARALLELISM` (global task concurrency), `AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG` (per-DAG task concurrency), and `pools` (resource-gated concurrency slots) are the three levers for controlling how many tasks run simultaneously and preventing downstream system overload.

---

## How It Connects

Deployment configuration directly determines how operators and sensors execute  -  LocalExecutor tasks run in subprocesses on one machine while KubernetesExecutor tasks run in isolated pods. Understanding the execution model affects how you write operators (what shared state is available, what environment variables are set).

[[airflow-operators|Airflow Operators]]

Connections and Hooks must be available to whatever process runs the task  -  in distributed deployments, this means the credentials must be in the metadata database or secrets backend, not on a specific machine's filesystem.

[[airflow-connections|Airflow Connections and Hooks]]

---

## Common Misconceptions

Misconception 1: "`CeleryExecutor` always outperforms `LocalExecutor` for production use."
Reality: `LocalExecutor` with a properly sized machine handles hundreds of tasks per hour and is operationally far simpler. `CeleryExecutor` adds the broker (Redis/RabbitMQ) as a production dependency  -  another service to monitor, back up, and troubleshoot. Use `CeleryExecutor` only when you have outgrown a single-machine `LocalExecutor` deployment or need geographic distribution of workers.

Misconception 2: "I only need to deploy DAG files to the scheduler machine."
Reality: Workers also need access to DAG files to deserialize the task and import the operator class. In `CeleryExecutor` deployments, every worker process must have the same DAG files as the scheduler, via shared filesystem, git-sync, or built-in Docker image. A worker with missing or out-of-date DAG files will fail to import the task and mark the `TaskInstance` as failed.

Misconception 3: "`KubernetesExecutor` gives me task isolation so I don't need to worry about Python dependency conflicts."
Reality: `KubernetesExecutor` provides process isolation (each task in its own pod), but the pod still runs from the same Docker image unless you specify pod overrides. If two tasks need conflicting library versions, you still need separate images or virtual environments  -  the executor alone does not solve dependency conflicts.

---

## Why It Matters in Practice

The most common production Airflow failure mode is not in the DAG code  -  it is in the deployment infrastructure. Metadata DB connection pool exhaustion (too many scheduler, worker, and webserver connections competing), DAG file distribution lag (workers running stale DAG versions), and Celery broker backlogs (workers offline with tasks accumulating in the queue) are the top operational issues. Understanding the architecture helps diagnose these: if tasks are queued but not starting, check worker processes and broker connectivity. If tasks suddenly fail with ImportError, check DAG file synchronization between scheduler and workers.

Managed services (MWAA, Composer, Astronomer) eliminate much of this operational burden at a significant cost premium. For teams with dedicated DevOps support, the self-managed Kubernetes-based deployment provides more control. For smaller teams, a well-configured `LocalExecutor` deployment on a single large virtual machine is often the right tradeoff.

---

## Interview Angle

Common question forms:
- "What is the difference between LocalExecutor, CeleryExecutor, and KubernetesExecutor?"
- "What components are required for a production Airflow deployment?"
- "How do DAG files get distributed to workers in a distributed Airflow deployment?"

Answer frame:
Executors: LocalExecutor (subprocess on scheduler host, one machine, simple), CeleryExecutor (Celery workers + Redis/RabbitMQ broker, multi-machine, requires broker management), KubernetesExecutor (one pod per task, maximum isolation, K8s cluster required, higher task latency). Production components: PostgreSQL metadata DB, Scheduler, Webserver, Workers (for Celery), and optional Flower monitoring UI. DAG distribution: all workers must have identical DAG files  -  achieved via shared NFS, git-sync sidecar, baked Docker images, or managed service S3 sync. All workers must also have identical Python environments.

---

## Related Notes

- [[airflow-basics|Apache Airflow Basics]]
- [[airflow-dags|Airflow DAGs]]
- [[airflow-operators|Airflow Operators]]
- [[airflow-connections|Airflow Connections and Hooks]]
