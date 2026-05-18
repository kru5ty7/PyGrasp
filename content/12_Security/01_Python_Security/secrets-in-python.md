---
title: 03 - Handling Secrets in Python
description: "Handling secrets correctly means keeping credentials, API keys, and private keys out of source code, version control, and logs  -  using environment variables, secret management services, and structured configuration to load them at runtime."
tags: [secrets, environment-variables, configuration, security, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-05-18
---

# Handling Secrets in Python

> A secret hardcoded in source code is not a secret  -  it is an exposed credential waiting to be discovered in version control history, a container image, or a log file.

---

## Quick Reference

**Core idea:**
- Never hardcode secrets (API keys, passwords, tokens, private keys) in source code  -  they will end up in version control
- Load secrets at runtime from environment variables, `.env` files (development only), or secret management services (production)
- `python-dotenv` loads `.env` into `os.environ`; `pydantic-settings` provides typed, validated settings from environment variables
- Production-grade secret management: AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager  -  credentials are fetched at startup, not stored in the environment
- Secrets in logs are a silent failure: logging a request object, an exception with a full stack trace, or a configuration object can expose secrets to anyone with log access

**Tricky points:**
- `.env` files should never be committed  -  add `.env` to `.gitignore` immediately; include `.env.example` with dummy values as documentation
- `os.environ` is not encrypted  -  any code in the process can read it, and it can appear in process listings on some systems
- AWS Lambda and other serverless environments have their own mechanisms for injecting secrets at execution time  -  do not bake secrets into the deployment package
- Secret rotation requires that the application can reload secrets without restart  -  hardcoded or startup-loaded secrets require redeployment to rotate
- `pydantic-settings` `BaseSettings` reads from environment and `.env` files, validates types, and raises clear errors on missing required fields  -  preferable to raw `os.environ.get()`

---

## What It Is

A secret is any value that grants access to a protected resource: a database password, an API key for a paid service, a private key used for signing, a JWT secret, an OAuth client secret. These values are the keys to locks. If the key is visible to anyone  -  stored in a file anyone can read, committed to a repository anyone can clone, printed in logs anyone with log access can view  -  the lock provides no protection.

The most common way secrets end up in source code is that a developer is working quickly, needs a database connection to test something, and types `DATABASE_URL = "postgresql://user:password@localhost/mydb"` directly into the code. The code works, the test passes, the code gets committed, and the password is now in the repository's git history forever. Even if the developer later removes the line, `git log` and `git blame` can retrieve it. GitHub's secret scanning detects many common patterns (API key formats, AWS key prefixes) and alerts repository owners, but it cannot catch every custom credential format, and it only helps if the repository is on GitHub.

The environment variable pattern separates the secret from the code by a layer of indirection. The code reads `DATABASE_URL` from the environment, and the value of `DATABASE_URL` is injected into the process's environment by whatever is running the application  -  a Docker Compose file, a Kubernetes Secret, a systemd unit file, or a CI/CD pipeline. The code that handles database connections is identical in development and production; only the environment variable values differ. No secret ever appears in the source code.

---

## How It Actually Works

The development workflow uses `python-dotenv` to load a `.env` file into the environment before the application reads it:

```
# .env (NEVER commit this file)
DATABASE_URL=postgresql://user:devpassword@localhost/mydb
SECRET_KEY=dev-secret-key-not-for-production
OPENAI_API_KEY=sk-...
```

```python
from dotenv import load_dotenv
import os

load_dotenv()  # reads .env file, sets os.environ

DATABASE_URL = os.environ["DATABASE_URL"]  # raises KeyError if missing
```

`pydantic-settings` provides a more robust pattern  -  it reads from environment variables (and optionally `.env`), validates types, and raises descriptive errors if required settings are missing:

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    secret_key: str
    openai_api_key: str
    debug: bool = False
    allowed_hosts: list[str] = ["localhost"]

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()  # Raises ValidationError if database_url or secret_key missing
```

If `DATABASE_URL` is not set in the environment or `.env`, `pydantic-settings` raises a clear error at startup rather than failing silently at the point of first use. This fail-fast behavior is important: a misconfigured application that starts without its secrets might serve traffic before hitting the error, potentially in an insecure degraded state.

In production, the pattern shifts from environment variables to secret management services. AWS Secrets Manager stores secrets as JSON and provides an API to fetch them. The application fetches secrets at startup (or on demand) and holds them in memory:

```python
import boto3
import json

def get_secret(secret_name: str) -> dict:
    client = boto3.client("secretsmanager", region_name="us-east-1")
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])

# At application startup
db_creds = get_secret("prod/myapp/database")
DATABASE_URL = f"postgresql://{db_creds['username']}:{db_creds['password']}@{db_creds['host']}/mydb"
```

This pattern enables secret rotation without redeployment: the secret is updated in Secrets Manager, and the next fetch returns the new value. Applications that support graceful restart or that re-fetch secrets periodically can rotate credentials with no downtime.

The logging failure mode is subtle and common. Python's default exception handler and many logging configurations will log `repr()` of objects, which can include their attributes:

```python
# This logs the full request object, which may include Authorization headers
logger.error("Request failed", extra={"request": request})

# This logs the settings object, which contains all secrets
logger.info("Application configured", extra={"settings": settings.dict()})

# A database URL in an exception traceback
# "could not connect to server: postgresql://user:password@host/db"
```

The defense is to never log objects that may contain secrets, to implement `__repr__` methods on settings classes that redact sensitive fields, and to audit log output for credential patterns before deploying to shared logging infrastructure.

---

## How It Connects

Pydantic settings is the recommended way to handle application configuration in FastAPI applications  -  understanding how it integrates with the secret-loading pattern is practical context.

[[fastapi|FastAPI]]

SSRF can expose secrets from the cloud metadata service  -  understanding how those secrets flow into applications makes the attack impact concrete.

[[ssrf|Server-Side Request Forgery]]

---

## Common Misconceptions

Misconception 1: "I removed the secret from the code before committing, so it's fine."
Reality: If the secret was ever committed  -  even in a single commit that was immediately reverted  -  it is in the repository's history. Anyone with access to the repository can run `git log -p` or `git show <commit-hash>` and see the committed secret. If the repository is or ever becomes public, that secret is public. The correct remediation is to rotate the secret (invalidate the old one, generate a new one) and, if necessary, use `git filter-repo` to purge the commit history.

Misconception 2: "Environment variables are secure."
Reality: Environment variables are better than hardcoded secrets, but they are not encrypted. On Linux, `/proc/<pid>/environ` exposes all environment variables of a running process to any user with sufficient permissions. Environment variables are passed to child processes by default, potentially exposing them to subprocesses that do not need them. In container environments, environment variables can appear in container inspection outputs. Use environment variables as a transport mechanism for secrets, not as a secure vault.

Misconception 3: "We use a private repository, so hardcoded secrets are acceptable for internal tools."
Reality: Private repository access has expanded far beyond what developers typically expect: all past and present employees, third-party CI/CD services (GitHub Actions, CircleCI), secret scanning bots, code search tools, and anyone whose account is compromised all have access to the repository. "Private" is a weaker protection than it appears, and hardcoded secrets in any repository  -  private or public  -  should be treated as compromised.

---

## Why It Matters in Practice

Exposed credentials are the leading cause of cloud account compromise. Research from cloud security firms consistently shows that a significant percentage of AWS access keys leaked to public GitHub repositories are accessed by automated scanners within minutes of the commit. The scanners search GitHub continuously for credential patterns, find a key, and immediately begin using it  -  provisioning EC2 instances for cryptocurrency mining, exfiltrating S3 data, or escalating privileges across the AWS account.

The operational implications extend beyond the initial exposure: secrets committed to version control must be rotated immediately (the old value is compromised, not just the new one), any resource the credential accessed must be audited for unauthorized use, and the incident may require disclosure under data protection regulations if customer data was accessible. The operational cost of a single secret exposure vastly exceeds the cost of implementing proper secret management from the start.

---

## Interview Angle

Common question forms:
- "How do you manage secrets in a Python application?"
- "What is the difference between using environment variables and a secret management service?"
- "How would you prevent secrets from appearing in logs?"

Answer frame:
A strong answer describes the three environments: development (`.env` + python-dotenv), staging/production (environment variables injected by the orchestration layer), and production-grade (Secrets Manager / Vault for rotation and audit logging). It mentions `pydantic-settings` as the typed validation layer. It addresses the logging risk specifically  -  logging objects that contain secrets  -  and mentions the remediation for already-committed secrets (rotate + git history purge).

---

## Related Notes

- [[dependency-scanning|Dependency Vulnerability Scanning]]
- [[bandit|Bandit (Python Security Linter)]]
- [[cryptography-python|Cryptography with Python]]
- [[fastapi|FastAPI]]
- [[ssrf|Server-Side Request Forgery]]
