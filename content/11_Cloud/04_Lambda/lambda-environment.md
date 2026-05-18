---
title: 37 - Lambda Environment Variables
description: Lambda environment variables provide per-function runtime configuration — understanding their limits, encryption model, and secure secret management prevents misconfiguration in production.
tags: [aws, cloud, layer-11, lambda, environment-variables, configuration]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda Environment Variables

> Lambda environment variables inject configuration into your function without changing code — but their 4KB limit and plaintext-in-console visibility mean secrets need a more secure home.

---

## Quick Reference

**Core idea:**
- Set key-value pairs on the function; access them in Python via `os.environ`
- Encrypted at rest with KMS (default: AWS-managed key; optional: your own CMK)
- Total size limit: 4KB across all environment variables combined
- Visible in the Lambda console by default — treat them as non-secret configuration
- For secrets (passwords, API keys), use AWS Secrets Manager or SSM Parameter Store
- Environment variables do not change between warm invocations — load them at module level

**Tricky points:**
- All values are strings — always cast numeric, boolean, and JSON values explicitly
- The 4KB limit is per-function and includes both keys and values
- Updating environment variables triggers a function update (new version if versioning is enabled); warm environments see the new values on next cold start only
- KMS encryption protects at-rest storage; the Lambda execution environment decrypts them before injecting — in-memory values are plaintext
- Lambda's own reserved environment variables (`AWS_REGION`, `AWS_LAMBDA_FUNCTION_NAME`, etc.) cannot be overridden

---

## What It Is

Environment variables in Lambda work the same way they do in any Unix process — they are key-value string pairs injected into the process's environment before the code runs. Think of them as a configuration label stuck to the outside of a shipping box: the box (your function code) is identical in every environment, but the label tells it where to deliver itself — dev, staging, or production — without you having to repack the box. The label is cheap to change; the box stays the same.

This separation of configuration from code is a foundational principle of twelve-factor application design. Environment variables let you promote the same deployment package from development to production without modification. The function code reads `os.environ["DATABASE_HOST"]` and works against whatever database is appropriate for that environment. Change the environment variable value in the Lambda console or via IaC, and the behaviour changes without a code deploy.

The practical boundary between environment variables and secrets management is visibility and sensitivity. Environment variables appear in the Lambda console, in CloudTrail API logs, and in any deployment tooling that reads function configuration. That is acceptable for non-sensitive configuration — feature flags, timeouts, table names, API endpoint URLs, log levels. It is not acceptable for database passwords, API keys, signing secrets, or anything that should not be visible to every team member with Lambda console access. Those belong in Secrets Manager or SSM Parameter Store, fetched at runtime with boto3 and cached in module-level variables.

---

## How It Actually Works

Environment variables are set when the function is created or updated. They are decrypted by Lambda before the execution environment starts, so by the time your Python code runs, `os.environ` contains the plaintext values. Reading them at module level (outside the handler) means the read happens once per cold start and the values are reused across all warm invocations, which is the correct pattern for values that do not change.

```python
import json
import os
import logging
import boto3
from functools import lru_cache

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# --- Non-sensitive config: read from environment variables at module level ---
STAGE = os.environ.get("STAGE", "dev")
TABLE_NAME = os.environ["TABLE_NAME"]              # Required — let KeyError surface on cold start
MAX_RETRIES = int(os.environ.get("MAX_RETRIES", "3"))
ENABLE_FEATURE_X = os.environ.get("ENABLE_FEATURE_X", "false").lower() == "true"
ALLOWED_ORIGINS = os.environ.get("ALLOWED_ORIGINS", "").split(",")  # comma-separated list → list


# --- Sensitive config: fetch from Secrets Manager, cached in module scope ---
@lru_cache(maxsize=1)
def get_db_password() -> str:
    """Fetch and cache the database password from Secrets Manager."""
    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    secret = json.loads(response["SecretString"])
    return secret["password"]


def handler(event, context):
    logger.info(json.dumps({
        "stage": STAGE,
        "table": TABLE_NAME,
        "feature_x": ENABLE_FEATURE_X,
    }))

    # Password is fetched once and then served from the lru_cache
    db_password = get_db_password()

    return {"statusCode": 200, "body": json.dumps({"stage": STAGE})}
```

Setting environment variables via the CLI at function creation time:

```bash
aws lambda create-function \
    --function-name my-function \
    --runtime python3.12 \
    --role arn:aws:iam::123456789012:role/lambda-exec-role \
    --handler main.handler \
    --zip-file fileb://function.zip \
    --environment "Variables={STAGE=production,TABLE_NAME=users,LOG_LEVEL=WARNING,DB_SECRET_ARN=arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db-password}"
```

Updating environment variables on an existing function:

```bash
# This replaces ALL existing environment variables — include everything you want to keep
aws lambda update-function-configuration \
    --function-name my-function \
    --environment "Variables={STAGE=production,TABLE_NAME=users,MAX_RETRIES=5,LOG_LEVEL=WARNING,DB_SECRET_ARN=arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/db-password}"
```

Encrypting with a customer-managed KMS key:

```bash
aws lambda update-function-configuration \
    --function-name my-function \
    --kms-key-arn arn:aws:kms:us-east-1:123456789012:key/mrk-abc123
```

---

## How It Connects

Environment variables are one half of configuration management — the non-sensitive half. For secrets, the Lambda execution role must grant permission to Secrets Manager or SSM Parameter Store. The role model that governs those permissions is central to secure Lambda design.

[[lambda-iam|Lambda IAM Execution Role]] — the execution role must include `secretsmanager:GetSecretValue` for the specific secret ARN before the Secrets Manager pattern shown above will work.

Managing secrets across multiple environments is a cross-cutting concern that spans Lambda, EC2, ECS, and other compute types. The dedicated secret management note covers the full pattern.

[[secret-management|Secret Management]] — covers SSM Parameter Store, Secrets Manager, rotation, and the caching patterns used in Lambda and other compute environments.

---

## Common Misconceptions

Misconception 1: Encrypting environment variables with KMS means they are secret.
Reality: KMS encryption protects the values at rest in Lambda's storage and in transit when you call the GetFunctionConfiguration API. However, when the execution environment starts, Lambda decrypts the values and injects them as plaintext into the process environment. Any code running in the function can read them with `os.environ`. They are also visible in the Lambda console to anyone with `lambda:GetFunctionConfiguration` permission. KMS encryption raises the security bar but does not make environment variables equivalent to Secrets Manager in terms of access control and auditability.

Misconception 2: You can store large configuration (JSON config files, certificate chains) in environment variables.
Reality: The 4KB total limit across all key-value pairs is a hard constraint enforced by the Lambda API. Large configuration must be stored in S3 and fetched at cold start, or in SSM Parameter Store (String parameters up to 8KB, SecureString up to 8KB). The Lambda environment variable slot is for lightweight configuration scalars and ARN references.

---

## Why It Matters in Practice

Correctly separating configuration from secrets in Lambda is the difference between a system that is both functional and auditable and one that leaks sensitive data through console access or API call logs. The pattern — non-sensitive configuration in environment variables, sensitive values in Secrets Manager fetched at cold start and cached — is standard practice in production Lambda deployments. Teams that get this right from the start avoid the painful migration of hardcoded credentials later.

---

## What Breaks in Production

**Scenario 1: Numeric environment variable used without casting**

```python
# Mistake: using env var directly in a numeric context
timeout_seconds = os.environ["TIMEOUT"]  # "30" — a string
time.sleep(timeout_seconds)              # TypeError: a float is required

# Fix: cast at load time
TIMEOUT_SECONDS = int(os.environ.get("TIMEOUT", "30"))
```

**Scenario 2: Updating environment variables wipes existing ones**

```bash
# Mistake: partial update via CLI wipes all unspecified vars
aws lambda update-function-configuration \
    --function-name my-function \
    --environment "Variables={LOG_LEVEL=DEBUG}"
# This removes TABLE_NAME, STAGE, and everything else

# Fix: always include all variables in the update
# Better: use IaC (CloudFormation, Terraform, CDK) to manage the full set declaratively
```

**Scenario 3: Secret stored in environment variable leaks in logs**

```python
# Mistake: logging all environment variables for debugging
import os
logger.info(f"Environment: {dict(os.environ)}")
# This logs DATABASE_PASSWORD in plaintext to CloudWatch

# Fix: log only the specific non-sensitive vars you need
logger.info(json.dumps({"stage": os.environ.get("STAGE"), "table": os.environ.get("TABLE_NAME")}))
```

---

## Interview Angle

Common question forms:
- "How do you manage configuration and secrets in a Lambda function?"
- "What is the difference between storing a secret in an environment variable versus Secrets Manager?"
- "How do you avoid re-fetching secrets on every Lambda invocation?"

Answer frame:
Distinguish non-sensitive configuration (environment variables, read at module level) from secrets (Secrets Manager or SSM Parameter Store, fetched at cold start and cached with `lru_cache` or a module-level variable). Explain the 4KB limit. Mention KMS encryption as at-rest protection that does not restrict in-process access.

---

## Related Notes

- [[lambda-overview|Lambda Overview]]
- [[lambda-python|Lambda with Python]]
- [[lambda-iam|Lambda IAM Execution Role]]
- [[secret-management|Secret Management]]
