---
title: 06 - Airflow Connections and Hooks
description: "Airflow Connections store credentials centrally in the metadata database, and Hooks are the library classes that use those connections to interact with external systems  -  together they keep secrets out of DAG code."
tags: [airflow, connections, hooks, credentials, secrets, providers, layer-5, data-engineering]
status: draft
difficulty: intermediate
layer: 5
domain: data-engineering
created: 2026-05-18
---

# Airflow Connections and Hooks

> Connections are credential records stored in Airflow's metadata database; Hooks are typed Python clients that fetch those credentials and provide a clean API for external systems  -  the separation keeps secrets out of code and centralizes credential management.

---

## Quick Reference

**Core idea:**
- `Connection` stores: `conn_id` (the lookup key), `conn_type`, `host`, `port`, `login`, `password`, `schema`, `extra` (JSON blob)
- Hooks inherit from `BaseHook`; the primary method is `get_conn()` which returns a client or connection object
- `BaseHook.get_connection(conn_id)` retrieves the `Connection` from the metadata DB or environment variable
- Environment variable override: `AIRFLOW_CONN_{CONN_ID_UPPERCASE}`  -  URI format or JSON format
- Common hooks: `PostgresHook`, `S3Hook`, `HttpHook`, `SlackWebhookHook`, `SnowflakeHook`
- Secrets backends: Airflow can retrieve connections from AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager instead of the metadata DB

**Tricky points:**
- `conn_id` is case-sensitive and must match exactly  -  typos silently fail at task runtime, not at DAG parse time
- `extra` field accepts JSON  -  custom connection parameters (e.g., AWS region, Snowflake account, SSL options) go here
- Hooks are instantiated inside task callables, not at DAG parse time  -  keeps connection objects out of the scheduler process
- The same `conn_id` can be overridden per-environment via environment variables  -  dev uses a dev DB, prod uses prod DB without code changes
- `HttpHook` is often used for API calls but lacks retry/backoff logic  -  add it manually or use a dedicated provider

---

## What It Is

Think of a keychain in an office building. Instead of every employee carrying copies of every key they need, a secure keychain hangs by the front desk, labeled with what each key opens: "server room," "supply closet," "executive suite." When an employee needs access to the server room, they check out the server room key, use it, and return it. The building manager can change any key without notifying each individual employee  -  just replace it on the keychain. Apache Airflow's Connection system is that keychain. Every external system  -  a database, a cloud bucket, a REST API  -  has a corresponding Connection entry identified by a short name. Any task that needs to talk to that system asks for its connection by name, never by storing credentials in the code.

A Connection record contains everything needed to establish a connection: host, port, username, password, database name, and an `extra` JSON field for system-specific options. Connections are stored in Airflow's metadata database and managed through the Airflow UI (Admin -> Connections), the CLI (`airflow connections add`), or environment variables. In production environments, the metadata DB connection store is often replaced with a secrets backend  -  AWS Secrets Manager, HashiCorp Vault, or GCP Secret Manager  -  so that credentials are stored in an audited, encrypted vault rather than an application database.

Hooks are the Python counterpart to Connections. A Hook is a client class that knows how to use a specific type of Connection. `PostgresHook` knows how to create a `psycopg2` connection from a Postgres `Connection` record. `S3Hook` knows how to create a `boto3` session from an AWS `Connection` record. The hook fetches the connection from the registry, handles authentication, and exposes a clean API: `PostgresHook.get_pandas_df(sql)`, `S3Hook.read_key(key, bucket)`. Operators use Hooks internally  -  `PostgresOperator` creates a `PostgresHook` under the hood. When you write a custom operator or sensor, you use the appropriate Hook rather than instantiating the client library directly.

---

## How It Actually Works

`BaseHook.get_connection(conn_id)` checks multiple sources in order: first the environment variable `AIRFLOW_CONN_{CONN_ID}` (converted to uppercase with `://` URI or JSON format), then the configured secrets backend if one is set, then the metadata database. This lookup order means that environment variables always override the database  -  a critical feature for deploying the same DAG code to development and production environments with different credentials.

```python
# Custom Hook example
from airflow.hooks.base import BaseHook
import requests

class MyApiHook(BaseHook):
    conn_name_attr = "my_api_conn_id"
    default_conn_name = "my_api_default"
    conn_type = "http"
    hook_name = "My API"

    def __init__(self, conn_id: str = default_conn_name):
        super().__init__()
        self.conn_id = conn_id

    def get_conn(self):
        conn = self.get_connection(self.conn_id)
        return requests.Session()  # could configure headers from conn.extra

    def get_data(self, endpoint: str) -> dict:
        conn = self.get_connection(self.conn_id)
        base_url = f"https://{conn.host}:{conn.port}"
        session = self.get_conn()
        resp = session.get(f"{base_url}/{endpoint}", headers={
            "Authorization": f"Bearer {conn.password}"
        })
        resp.raise_for_status()
        return resp.json()

# Using existing hooks in a task
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.decorators import task

@task()
def query_database() -> list:
    hook = PostgresHook(postgres_conn_id="my_postgres")
    records = hook.get_records("SELECT id, name FROM users WHERE active = true")
    return [{"id": r[0], "name": r[1]} for r in records]  # keep XCom small

# Setting up a connection via environment variable (for testing/CI)
# AIRFLOW_CONN_MY_POSTGRES=postgresql://user:pass@localhost:5432/mydb
```

The `extra` field in a Connection is a JSON string that holds provider-specific parameters. For a Snowflake connection, `extra` might contain `{"account": "mycompany.us-east-1", "warehouse": "COMPUTE_WH", "role": "ANALYST"}`. For an AWS connection, it might contain `{"region_name": "us-east-1", "aws_session_token": "..."}`. Each provider's Hook class knows which `extra` fields to extract. The `extra` field is also encrypted at rest if Airflow's `fernet_key` is configured  -  all password fields and `extra` are encrypted in the metadata database.

Secrets backends change the source of truth for Connections entirely. When configured (in `airflow.cfg` or `AIRFLOW__SECRETS__BACKEND`), `BaseHook.get_connection()` calls the secrets backend's `get_conn_uri()` method instead of querying the database. The AWS Secrets Manager backend, for example, looks up the secret named `airflow/connections/{conn_id}` and parses it as a connection URI. This approach provides centralized secret rotation (change the secret in Secrets Manager; every new Airflow task immediately uses the new credentials), audit logging, and access control  -  none of which the metadata database provides.

---

## How It Connects

Operators use Hooks internally to talk to external systems  -  every provider operator (`PostgresOperator`, `S3FileTransformOperator`, etc.) creates a Hook in its `execute()` method. Understanding how Hooks work explains why provider operators are preferred over custom `BashOperator` scripts.

[[airflow-operators|Airflow Operators]]

Sensors that check external conditions (S3KeySensor, SqlSensor) also use Hooks internally  -  an S3KeySensor creates an `S3Hook` to check for the key's existence.

[[airflow-sensors|Airflow Sensors]]

---

## Common Misconceptions

Misconception 1: "I can store credentials in my DAG file as Python variables  -  it's fine because the DAG file isn't public."
Reality: DAG files are parsed repeatedly by the scheduler, logged by the scheduler process, and stored in version control. Credentials in DAG files will eventually appear in logs, git history, or be exposed when team members get access to the repository. Use Connections and the secrets backend  -  that is exactly what they exist for.

Misconception 2: "I should create the Hook at DAG parse time (module level) so the connection is reused between tasks."
Reality: Hooks create live connections to external systems. Creating them at parse time means the scheduler process holds database connections open and receives connection errors if the remote system is unavailable  -  which can crash the scheduler. Always instantiate Hooks inside task callables (`execute()` or the `@task` function body).

Misconception 3: "Changing a Connection in the Airflow UI takes effect only for new DAG deployments."
Reality: Connections are read at task execution time from the metadata DB (or secrets backend). A connection change takes effect for the next task execution  -  no code change or deployment is required.

---

## Why It Matters in Practice

The Connection and Hook system is the security and operational backbone of any production Airflow deployment. Without it, credentials scattered across DAG files, shell scripts, and environment variables in various formats become unmanageable as the number of external systems grows. A secrets backend integration means that rotating a database password requires one change in Vault or Secrets Manager  -  not a search through every DAG file that uses that database.

Understanding Hooks also matters when debugging provider operators. When a `PostgresOperator` fails with a connection error, the root cause is always a misconfigured Connection record (wrong host, wrong port, missing extra parameters). Knowing that the operator creates a `PostgresHook`, which calls `get_connection(conn_id)`, which retrieves the `Connection` object, gives you a clear diagnostic path: check the Connection record, test it with `airflow connections test`, fix the misconfiguration.

---

## Interview Angle

Common question forms:
- "How does Airflow manage credentials for external systems?"
- "What is the difference between a Connection and a Hook in Airflow?"
- "How would you configure Airflow to use a secrets manager instead of the metadata database for credentials?"

Answer frame:
Connections are records (host, port, username, password, extra JSON) stored in the metadata DB, identified by `conn_id`. Hooks are client classes that retrieve a Connection by `conn_id` and use it to create a typed client (psycopg2 connection, boto3 session). Operators use Hooks internally. For secrets manager: configure `AIRFLOW__SECRETS__BACKEND` to the backend class (e.g., `airflow.providers.amazon.aws.secrets.secrets_manager.SecretsManagerBackend`), set the prefix path, and Airflow reads connections from the secret manager instead of the DB  -  supports rotation without code changes.

---

## Related Notes

- [[airflow-basics|Apache Airflow Basics]]
- [[airflow-operators|Airflow Operators]]
- [[airflow-sensors|Airflow Sensors]]
