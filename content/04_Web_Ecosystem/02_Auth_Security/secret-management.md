---
title: 09 - Secret Management
description: "Secret management is the practice of keeping credentials, API keys, and sensitive configuration out of source code and securely delivering them to running applications via environment variables or dedicated secret stores."
tags: [secrets, security, environment-variables, pydantic-settings, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# Secret Management

> A secret in source code is a public secret  -  commit it once and it exists in git history forever; proper secret management delivers credentials to running applications without ever writing them to disk in a readable form.

---

## Quick Reference

**Core idea:**
- Never hardcode secrets in source code, `.env` files committed to git, Docker images, or CI/CD logs
- Twelve-factor app principle: configuration (including secrets) via environment variables
- `os.environ['SECRET_KEY']` reads a variable; `os.environ.get('API_KEY', default)` provides a fallback
- `pydantic-settings` `BaseSettings` reads env vars and `.env` files with type validation at startup
- Production secret stores: AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager  -  fetch secrets at startup, not hardcoded

**Tricky points:**
- `.env` files for local development are fine  -  but `.env` must be in `.gitignore` permanently; even an empty `.env` committed to git is a future risk when developers add secrets to it
- `os.environ['KEY']` raises `KeyError` if absent  -  intentional, it fails loudly; `os.environ.get('KEY')` returns `None` silently  -  can cause subtle bugs where missing secrets cause unexpected behavior later
- Secret rotation: applications that load secrets at startup and cache them for the process lifetime do not automatically pick up rotated secrets without a restart  -  lazy loading patterns enable rotation without restart
- AWS Secrets Manager charges per secret per month and per API call  -  for high-frequency reads, cache the secret value with a short TTL rather than calling the API on every request
- Docker build arguments (`ARG`) are visible in the image layer history  -  never pass secrets as build args

---

## What It Is

A database password hardcoded in a Python file is like writing your house key combination in the margin of a book you plan to publish. Even if you remove it later, the original version exists somewhere. In a git repository, any secret ever committed is visible to anyone who can read the repository history  -  even after deletion from the latest commit. Public repositories have exposed credentials this way countless times, often leading to immediate unauthorized access or cloud infrastructure abuse.

The fundamental principle of secret management is separation: the code that uses a secret should be entirely separate from the value of that secret. Code lives in version control; secrets do not. When code is deployed, the runtime environment supplies the secrets, and the application reads them from that environment at startup. The mechanism is environment variables  -  key/value pairs set in the process environment by the operating system, a container orchestrator, or a CI/CD system, never written to disk by the application code.

For local development, a `.env` file is a convenient way to set environment variables without polluting the shell. The file stays on the developer's machine, is listed in `.gitignore`, and is loaded by the application using a library like `python-dotenv` or `pydantic-settings`. In production, the same environment variables are injected by Kubernetes secrets, AWS Parameter Store, or a service mesh  -  the application code does not change, only the delivery mechanism.

---

## How It Actually Works

`pydantic-settings` `BaseSettings` is the standard Python pattern for reading configuration with validation. It reads from environment variables first, then from a `.env` file, and validates all values at startup  -  failing fast with a clear error if required secrets are absent.

```python
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import SecretStr

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # Required  -  raises ValidationError on startup if absent
    database_url: str
    secret_key: SecretStr

    # Optional with defaults
    debug: bool = False
    allowed_hosts: list[str] = ["localhost"]
    redis_url: str = "redis://localhost:6379/0"

# Application-wide singleton  -  validated once at import time
settings = Settings()

# SecretStr hides the value in logs and repr
# Use .get_secret_value() to access the actual string
db_url = settings.database_url
secret = settings.secret_key.get_secret_value()
```

For production secret stores, fetching at startup with a short TTL cache enables rotation without restart. AWS Secrets Manager example:

```python
import boto3
import json
import time
from functools import lru_cache

_secret_cache = {}
_secret_ttl = 300  # 5 minutes

def get_secret(secret_name: str) -> dict:
    now = time.time()
    if secret_name in _secret_cache:
        value, fetched_at = _secret_cache[secret_name]
        if now - fetched_at < _secret_ttl:
            return value

    client = boto3.client("secretsmanager", region_name="us-east-1")
    response = client.get_secret_value(SecretId=secret_name)
    value = json.loads(response["SecretString"])
    _secret_cache[secret_name] = (value, now)
    return value

# Usage
db_creds = get_secret("prod/myapp/database")
db_url = f"postgresql://{db_creds['username']}:{db_creds['password']}@{db_creds['host']}/mydb"
```

Never log secrets. `pydantic-settings`'s `SecretStr` type prevents accidental logging by overriding `__repr__` and `__str__` to return `'**********'`. Validate this pattern is in use before any secret value could appear in application logs.

A minimal `.gitignore` entry for every Python project:

```
# Never commit these
.env
.env.*
!.env.example    # example file with placeholder values is safe to commit
*.key
secrets.json
```

---

## How It Connects

`pydantic-settings` is built on Pydantic  -  the same validation engine used for FastAPI request/response schemas applies to configuration management.

[[pydantic|Pydantic]]

FastAPI reads its configuration from settings objects  -  understanding how `BaseSettings` works is directly applicable to FastAPI application setup.

[[fastapi|FastAPI]]

---

## Common Misconceptions

Misconception 1: "If I delete the commit with the secret, it's gone from git history."
Reality: Deleting a file or reverting a commit does not remove the secret from git history. The original commit still exists and is visible with `git log`. Properly removing a secret from git history requires rewriting history with tools like `git-filter-repo` or BFG Repo Cleaner  -  and even then, anyone who has cloned or forked the repository already has the secret. When a secret is exposed in git, the correct response is to rotate (invalidate and replace) it immediately.

Misconception 2: "Environment variables are secure because other processes can't read them."
Reality: On Linux, environment variables of running processes can be read by the same user via `/proc/<pid>/environ`. In containerized environments, environment variables are visible in the container configuration and sometimes in orchestrator logs. For high-security applications, a secrets store that delivers secrets via files with restricted permissions (Kubernetes secrets mounted as files) or an in-memory API call is more secure than environment variables.

---

## Why It Matters in Practice

Secret leakage is one of the most common causes of security incidents in web applications. AWS API keys committed to public GitHub repositories are typically found and abused within minutes by automated scanners. Knowing how to use `pydantic-settings` for validated configuration, how to use AWS Secrets Manager for production secrets, and how to structure a project so that secrets can never accidentally end up in version control is foundational security knowledge for any Python developer.

---

## Interview Angle

Common question forms:
- "How do you manage secrets in a production Python application?"
- "What is the twelve-factor app approach to configuration?"
- "What is `pydantic-settings` and how does it help with secret management?"

Answer frame:
Twelve-factor: configuration via environment variables  -  code is the same across environments, only the env vars differ. `pydantic-settings` `BaseSettings` reads env vars and `.env` files with type validation at startup  -  fails fast if required secrets are missing. Production: AWS Secrets Manager or HashiCorp Vault  -  fetch at startup, cache with TTL to support rotation. Never hardcode, never commit `.env` files. `SecretStr` prevents accidental logging.

---

## Related Notes

- [[pydantic|Pydantic]]
- [[fastapi|FastAPI]]
- [[authentication-vs-authorization|Authentication vs Authorization]]
- [[rate-limiting|Rate Limiting]]
