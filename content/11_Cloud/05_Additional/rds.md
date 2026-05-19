---
title: 45 - RDS
description: RDS is AWS's managed relational database service - it handles OS patching, automated backups, and Multi-AZ failover while you focus on schema design and query performance.
tags: [aws, cloud, layer-11, rds, database, managed]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# RDS

> RDS removes the operational burden of running a relational database - AWS manages the OS, patching, backups, and failover, leaving you responsible for schema design, query performance, and connection management.

---

## Quick Reference

**Core idea:**
- Supported engines: PostgreSQL, MySQL, MariaDB, Oracle, SQL Server, and Aurora (AWS-native MySQL/PostgreSQL-compatible)
- Multi-AZ deployment: synchronous standby replica in a second AZ, automatic failover in 60–120 seconds
- Automated backups: daily snapshots + transaction log backup, point-in-time recovery up to the retention window (1–35 days)
- RDS Proxy: connection pooler between application and RDS - critical for Lambda workloads
- Read replicas: asynchronous replication to scale read traffic horizontally
- Instance classes: `db.t3.micro` (dev/test) to `db.r6g.16xlarge` (memory-optimised production)

**Tricky points:**
- Connecting from Lambda without RDS Proxy: each Lambda execution environment opens a new database connection - at high concurrency, this exhausts the database's connection limit
- Multi-AZ is for high availability (failover), not read scaling - read replicas serve read scaling
- Automated backups are enabled by default but deleted when you delete the RDS instance unless a final snapshot is taken
- The database runs inside a VPC; Lambda must also be VPC-attached (or use RDS Proxy with IAM auth from outside the VPC) to reach it
- Storage autoscaling can be enabled to grow the storage volume automatically - enable it for production

---

## What It Is

RDS is like hiring a property management company to run an apartment building. You designed the floor plan (the schema), you choose what appliances go in each unit (the instance class and engine), and you collect the rent (run queries). The property manager handles everything else: building maintenance (OS patching), security inspections (automated backups), insurance (Multi-AZ standby), and emergency repairs (failover). You could self-manage the building on a bare EC2 instance - install PostgreSQL yourself, write cron jobs for backups, configure streaming replication manually - but the property manager does it for less effort at a predictable cost.

What RDS does not manage is worth enumerating. AWS handles the host OS and the database engine's process management, but you own the schema design, index strategy, query performance tuning, connection pool configuration, and application-level data access patterns. A poorly indexed table on RDS is just as slow as a poorly indexed table on a self-managed PostgreSQL server. RDS does not magically make bad SQL fast.

The connection exhaustion problem is the most important RDS operational concern for Python developers deploying to Lambda. A PostgreSQL instance on a `db.t3.medium` supports roughly 170 concurrent connections before performance degrades. A Lambda function at 1000 concurrent executions each holding one database connection would require 1000 connections - instantly overwhelming any standard RDS instance. RDS Proxy is the purpose-built solution: it sits between Lambda and RDS, maintains a warm pool of database connections, and multiplexes thousands of Lambda connections onto a small pool of actual database connections. Using RDS Proxy is not optional for Lambda-to-RDS workloads at any meaningful scale.

---

## How It Actually Works

The boto3 RDS client provides a full API for creating and managing database instances. For production deployments, use a Multi-AZ instance (RDS automatically creates and manages the standby). Connecting from Python uses standard database drivers - `psycopg2` or `psycopg` for PostgreSQL, `PyMySQL` for MySQL. When connecting through RDS Proxy with IAM authentication, you generate a temporary authentication token using boto3 and use it as the database password.

```python
import boto3
import psycopg2
import os

# --- Connecting to RDS directly (suitable for non-Lambda, non-high-concurrency contexts) ---
def get_direct_connection():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=5,
        sslmode="require",        # always use SSL in production
    )


# --- Connecting to RDS through RDS Proxy with IAM authentication ---
# The Lambda execution role needs rds-db:connect permission
def get_rds_proxy_connection():
    rds_client = boto3.client("rds", region_name=os.environ["AWS_REGION"])

    # Generate a temporary IAM auth token (valid for 15 minutes)
    auth_token = rds_client.generate_db_auth_token(
        DBHostname=os.environ["DB_PROXY_ENDPOINT"],
        Port=5432,
        DBUsername=os.environ["DB_USER"],
    )

    return psycopg2.connect(
        host=os.environ["DB_PROXY_ENDPOINT"],
        port=5432,
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=auth_token,      # IAM auth token used as the password
        sslmode="require",
        sslrootcert="/opt/global-bundle.pem",  # AWS RDS CA certificate
    )


# --- Module-level connection (Lambda cold-start initialisation) ---
# Connection is created once per execution environment and reused across warm invocations
_connection = None

def get_connection():
    global _connection
    if _connection is None or _connection.closed:
        _connection = get_rds_proxy_connection()
    return _connection


def handler(event, context):
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM orders WHERE status = %s", ("pending",))
        count = cur.fetchone()[0]
    return {"statusCode": 200, "body": str(count)}
```

Creating an RDS PostgreSQL Multi-AZ instance via the CLI:

```bash
aws rds create-db-instance \
    --db-instance-identifier prod-postgres \
    --db-instance-class db.r6g.large \
    --engine postgres \
    --engine-version "16.2" \
    --master-username admin \
    --master-user-password "$(aws secretsmanager get-secret-value \
        --secret-id prod/rds/master-password \
        --query SecretString --output text | python3 -c 'import sys,json; print(json.load(sys.stdin)["password"])')" \
    --allocated-storage 100 \
    --storage-type gp3 \
    --storage-encrypted \
    --multi-az \
    --vpc-security-group-ids sg-0abc123 \
    --db-subnet-group-name prod-db-subnet-group \
    --backup-retention-period 7 \
    --enable-performance-insights \
    --no-publicly-accessible
```

---

## How It Connects

RDS is typically accessed through a connection pooler - RDS Proxy for Lambda workloads, or PgBouncer for ECS/EC2 workloads. The connection exhaustion problem is especially acute with Lambda because each execution environment opens a fresh connection.

[[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]] - Lambda's concurrency model (one execution environment per concurrent invocation) is what makes connection pooling via RDS Proxy non-optional for Lambda-to-RDS architectures.

RDS in a VPC requires Lambda functions to be VPC-attached to reach the database endpoint. This adds cold-start latency to Lambda functions. The cold start note discusses this trade-off.

[[lambda-cold-start|Lambda Cold Starts]] - VPC attachment for Lambda-to-RDS access adds ENI provisioning overhead to cold starts; the cold start note explains the magnitude and mitigations.

---

## Common Misconceptions

Misconception 1: Multi-AZ provides read scaling by distributing queries across the primary and standby.
Reality: Multi-AZ is a high-availability feature. The standby replica is synchronously replicated but does not serve any read traffic - it exists only to take over if the primary fails. To scale read traffic, you create read replicas (asynchronously replicated, separate endpoints, can serve SELECT queries). Multi-AZ and read replicas solve different problems and can be used together.

Misconception 2: Automated backups mean you can restore to any point in time indefinitely.
Reality: Automated backups are retained for a configurable window of 1–35 days. After that window, the backups are deleted. Point-in-time recovery is only available within the retention window. For longer-term archival, take manual DB snapshots (which persist until explicitly deleted) and store them for compliance or disaster recovery purposes.

---

## Why It Matters in Practice

RDS is the default choice for relational workloads in AWS because the managed service removes a significant operational surface area. The backup and Multi-AZ features alone justify the managed service premium for most teams. For Python developers, the most actionable knowledge is the connection pooling requirement (RDS Proxy for Lambda), the credential management pattern (Secrets Manager rotation, not hardcoded passwords), and the VPC placement requirement that creates a dependency with Lambda networking configuration.

---

## What Breaks in Production

**Scenario 1: Lambda exhausts RDS connection limit**

```python
# Mistake: opening a new connection on every Lambda invocation (in the handler)
def handler(event, context):
    conn = psycopg2.connect(host=DB_HOST, ...)  # new connection every invocation
    # At 500 concurrent Lambda executions → 500 open database connections
    # RDS connection limit on db.t3.medium is ~170 → connection refused

# Fix: move connection to module level AND use RDS Proxy
conn = None  # module level

def handler(event, context):
    global conn
    if conn is None or conn.closed:
        conn = get_rds_proxy_connection()  # RDS Proxy multiplexes onto a small pool
```

**Scenario 2: Deleting an RDS instance without a final snapshot**

```bash
# Mistake: deleting without a final snapshot during environment cleanup
aws rds delete-db-instance \
    --db-instance-identifier staging-postgres \
    --skip-final-snapshot
# Automated backups are deleted with the instance - data is permanently lost

# Fix: always take a final snapshot for non-dev instances
aws rds delete-db-instance \
    --db-instance-identifier staging-postgres \
    --final-db-snapshot-identifier staging-postgres-final-20260518
```

---

## Interview Angle

Common question forms:
- "What is the difference between Multi-AZ and read replicas in RDS?"
- "How do you connect Lambda functions to RDS without exhausting database connections?"
- "How do you manage RDS credentials in a Python application?"

Answer frame:
Distinguish Multi-AZ (HA, failover) from read replicas (read scaling). Explain the Lambda connection exhaustion problem and RDS Proxy as the solution. For credential management: Secrets Manager with automatic rotation, fetched at cold start and cached, IAM authentication via `generate_db_auth_token` as the alternative to password-based auth.

---

## Related Notes

- [[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]]
- [[lambda-cold-start|Lambda Cold Starts]]
- [[secret-management|Secret Management]]
- [[database-replication|Database Replication]]
- [[iam-roles|IAM Roles]]
