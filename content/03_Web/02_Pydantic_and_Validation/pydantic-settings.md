---
title: 03 - Pydantic Settings
description: "`pydantic-settings` provides `BaseSettings` — a Pydantic model that reads values from environment variables, `.env` files, and other sources automatically; used for application configuration with type validation and IDE support."
tags: [pydantic-settings, BaseSettings, environment-variables, dotenv, configuration, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# Pydantic Settings

> `pydantic-settings` provides `BaseSettings` — a Pydantic model that reads values from environment variables, `.env` files, and other sources automatically; used for application configuration with type validation and IDE support.

---

## Quick Reference

**Core idea:**
- `from pydantic_settings import BaseSettings` — requires `pip install pydantic-settings`
- Fields are populated from environment variables by default (uppercase match: `DATABASE_URL` env var → `database_url` field)
- `model_config = SettingsConfigDict(env_file=".env")` — also read from `.env` file
- Field types are validated — if `PORT=abc` but `port: int`, validation fails with `ValidationError`
- `@lru_cache` on a `get_settings()` factory — reads env vars once, caches for the app lifetime

**Tricky points:**
- Environment variable names are case-insensitive by default — `DATABASE_URL` and `database_url` both map to `database_url` field
- `.env` file is NOT loaded automatically unless `env_file` is specified in `SettingsConfigDict`
- Nested models: `SMTP__HOST=localhost` (double underscore) maps to `smtp.host` if `smtp` is a nested `BaseModel` — configure with `env_nested_delimiter="__"`
- `BaseSettings` reads environment at instantiation time — use `@lru_cache` to avoid re-reading on every call
- Secrets: `secrets_dir="/run/secrets"` reads from Docker secrets files (one secret per file, filename = field name)

---

## What It Is

Application configuration — database URLs, API keys, feature flags, ports — should come from the environment, not be hardcoded. `BaseSettings` is the Pydantic way to do this: define your settings as a model, and the values are automatically read from environment variables (and optionally `.env` files), type-validated, and accessible as typed Python attributes.

Without `BaseSettings`, you call `os.getenv("PORT", "8000")` and cast manually. With `BaseSettings`, you declare `port: int = 8000` and get automatic environment variable lookup, type coercion, and validation.

---

## How It Actually Works

```python
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import SecretStr
from functools import lru_cache

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )
    
    app_name: str = "MyApp"
    debug: bool = False
    port: int = 8000
    database_url: str
    secret_key: SecretStr  # SecretStr hides value in repr/logs
    allowed_origins: list[str] = ["http://localhost:3000"]

@lru_cache
def get_settings() -> Settings:
    return Settings()

# Usage in FastAPI:
from fastapi import Depends

@app.get("/info")
async def info(settings: Settings = Depends(get_settings)):
    return {"app": settings.app_name, "debug": settings.debug}
```

`.env` file:
```
DATABASE_URL=postgresql://user:pass@localhost/mydb
SECRET_KEY=supersecretkey
DEBUG=true
PORT=8080
```

Nested settings with delimiter:
```python
class SmtpSettings(BaseModel):
    host: str = "localhost"
    port: int = 587

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_nested_delimiter="__")
    smtp: SmtpSettings = SmtpSettings()

# Set via: SMTP__HOST=mail.example.com SMTP__PORT=465
```

---

## How It Connects

`pydantic-settings` extends Pydantic's `BaseModel` — all Pydantic validation features (validators, type coercion) apply to settings fields.
[[pydantic|Pydantic]]

In FastAPI, settings are commonly injected via `Depends(get_settings)` — the dependency injection system ensures the same cached instance is used everywhere.
[[fastapi-dependencies|FastAPI Dependencies]]

---

## Common Misconceptions

Misconception 1: "`BaseSettings` reads `.env` files automatically."
Reality: `.env` file loading requires explicit configuration: `SettingsConfigDict(env_file=".env")`. Without this, only actual environment variables (set in the shell) are read.

Misconception 2: "Environment variables are re-read on every `Settings()` call."
Reality: `Settings()` reads the environment at instantiation. If environment changes after the first `Settings()` call, the second call picks up the new values. The `@lru_cache` pattern prevents re-reading by caching the first result — but it also means environment changes are invisible after the first call (usually desired behavior for a running app).

---

## Why It Matters in Practice

Twelve-Factor App methodology: configuration should come from the environment, not the code. `BaseSettings` implements this with:
- Type safety: `DATABASE_URL` not set → `ValidationError` at startup (fail fast, not at first use)
- Secrets: `SecretStr` fields hide values in logs and `repr()`
- Testing: override settings by setting environment variables before running tests
- `.env` files: development-local config without modifying environment permanently

```python
# In tests — override settings cleanly:
import os
os.environ["DATABASE_URL"] = "sqlite:///test.db"
get_settings.cache_clear()  # clear lru_cache
settings = get_settings()
```

---

## Interview Angle

Common question forms:
- "How do you manage application configuration in FastAPI?"
- "How do you read environment variables with type validation?"

Answer frame: `pydantic-settings.BaseSettings` — declare fields with types; values come from environment variables automatically. Add `SettingsConfigDict(env_file=".env")` for `.env` file support. Use `@lru_cache` on a factory function for singleton behavior. `SecretStr` hides sensitive values. Fail-fast: missing required env vars raise `ValidationError` at startup.

---

## Related Notes

- [[pydantic|Pydantic]]
- [[pydantic-validators|Pydantic Validators]]
- [[fastapi-dependencies|FastAPI Dependencies]]
- [[fastapi|FastAPI]]
