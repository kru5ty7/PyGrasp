---
title: 03 - Docker Compose
description: "Docker Compose defines and runs multi-container applications from a single YAML file, orchestrating services, networks, and volumes with dependency ordering and environment configuration for local development and integration testing."
tags: [docker-compose, multi-container, orchestration, services, volumes, networks, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Docker Compose

> Docker Compose is a tool for defining and running multi-container applications  -  a single `docker-compose.yml` file declares all services (web app, database, cache), their networks, volumes, and startup order, so `docker compose up` brings the entire application stack to life with one command.

---

## Quick Reference

**Core idea:**
- `docker compose up`  -  starts all services defined in `docker-compose.yml`
- `docker compose up -d`  -  starts in detached mode (background); `docker compose logs -f` to stream logs
- `docker compose down`  -  stops and removes containers and default network (volumes persist unless `--volumes` is passed)
- `docker compose build`  -  rebuilds images for services with a `build:` directive
- `docker compose exec SERVICE COMMAND`  -  run a command in a running service container
- `docker compose ps`  -  show status of all services

**Tricky points:**
- `depends_on` controls startup order but not readiness  -  a service starts after its dependency container starts, not after the dependency is ready to accept connections; use health checks or retry logic in the application
- Environment variables in `docker-compose.yml` can be sourced from a `.env` file in the same directory  -  `.env` is loaded automatically without specifying it
- Service names become DNS hostnames within the Compose network  -  the web service reaches the database at `db:5432`, not `localhost:5432`
- `docker compose down --volumes` removes named volumes  -  this deletes database data; omit `--volumes` to preserve data between restarts
- Override files (`docker-compose.override.yml`) are merged automatically  -  useful for local development overrides that are not committed to source control

---

## What It Is

A real application rarely runs as a single container. A web application needs a database, a message queue, a cache, perhaps a background worker, and in development maybe a local SMTP server. Without Docker Compose, running this stack locally requires starting each container with the right `docker run` command, network configuration, volume mounts, and environment variables  -  then remembering the correct tear-down sequence. With Docker Compose, all of that configuration lives in one file, and the entire stack starts with a single command.

Docker Compose is best understood as the "developer-local orchestrator"  -  it handles the same multi-service coordination concerns that Kubernetes handles in production, but optimized for simplicity and developer ergonomics rather than horizontal scale and high availability. The two tools have different scope: Compose runs one stack on one machine; Kubernetes runs many stacks across many machines. For local development and integration testing, Compose is the right tool.

The `docker-compose.yml` file is a declarative specification of desired state. It says "I want a service named `web` built from the local Dockerfile, a service named `db` from the postgres image, and a named volume `pgdata` attached to the database." Docker Compose reads this and brings the actual state of running containers into alignment with the declared state, creating networks and volumes that do not yet exist, starting containers that are declared but not running, and wiring them together.

---

## How It Actually Works

A `docker-compose.yml` for a FastAPI application with PostgreSQL and Redis:

```yaml
version: "3.9"

services:
  web:
    build: .                          # Build from local Dockerfile
    ports:
      - "8000:8000"                   # Host:container port mapping
    environment:
      DATABASE_URL: postgresql://postgres:secret@db:5432/appdb
      REDIS_URL: redis://cache:6379/0
    volumes:
      - .:/app                        # Bind mount for hot reload in dev
    depends_on:
      db:
        condition: service_healthy    # Wait for health check (Compose v3.9+)
      cache:
        condition: service_started

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secret
    volumes:
      - pgdata:/var/lib/postgresql/data  # Named volume persists data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  cache:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  pgdata:            # Declares the named volume

networks:            # Explicit network (optional; Compose creates one by default)
  default:
    name: appnet
```

Compose automatically creates a default bridge network for all services in the file. Within this network, each service is reachable by its service name as the DNS hostname. The `web` service connects to the database at `db:5432`  -  not `localhost:5432`. This is a key difference from running without Compose: each container has its own network namespace, and `localhost` inside a container refers to that container itself, not other services.

Override files allow environment-specific configuration without modifying the base file:

```yaml
# docker-compose.override.yml (for local dev, not committed)
services:
  web:
    command: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
    volumes:
      - .:/app
  db:
    ports:
      - "5432:5432"  # Expose DB port for local tools (DataGrip, etc.)
```

Docker Compose automatically merges `docker-compose.override.yml` with `docker-compose.yml` when present. For CI or production, run `docker compose -f docker-compose.yml up` to use only the base file.

---

## How It Connects

Docker Compose uses Dockerfiles to build service images  -  understanding how to write an efficient Dockerfile is a prerequisite for Compose's `build:` directive to produce useful results.

[[dockerfile-python|Writing a Dockerfile for Python]]

In CI/CD pipelines, Compose is commonly used to spin up integration test environments  -  starting a database and application together to test their interaction.

[[ci-testing-pipeline|CI Testing Pipeline]]

Kubernetes Deployments and Services perform the same multi-service orchestration as Compose, but across a cluster  -  understanding Compose's model makes Kubernetes concepts more approachable.

[[kubernetes-deployments|Kubernetes Deployments]]

---

## Common Misconceptions

Misconception 1: "`depends_on` ensures the database is ready before my app starts."
Reality: `depends_on` with `condition: service_started` (the default) only waits until the database container has started  -  not until PostgreSQL is accepting connections. The database process takes a few seconds to initialize after the container starts. Applications must implement retry logic for the initial database connection, or use `condition: service_healthy` with a health check defined on the database service.

Misconception 2: "Each service runs on `localhost` relative to other services."
Reality: Each service runs in its own network namespace. `localhost` inside the `web` container refers only to the `web` container. Other services are reachable by their service name: `db`, `cache`, etc. Compose sets up DNS resolution within the default network so that service names resolve to the correct container IP addresses.

Misconception 3: "`docker compose down` deletes my database data."
Reality: `docker compose down` stops and removes containers but leaves named volumes intact. Running `docker compose up` again will start a fresh container that re-attaches to the existing volume with existing data. Only `docker compose down --volumes` removes the volumes. This distinction matters: it is safe to restart the stack without losing data.

---

## Why It Matters in Practice

Local development with Docker Compose means every developer has an identical environment regardless of their host OS. The "it works on my machine" problem is eliminated for anything in the Compose stack. New team members run `docker compose up` and have a working development environment within minutes, without installing PostgreSQL, Redis, or any other service directly on their machine.

In CI, Compose serves a critical role in integration testing. Tests that require a real database  -  not a mock  -  can run against a Compose stack started at the beginning of the CI job and torn down at the end. The test environment is clean, reproducible, and identical to what developers test against locally.

---

## Interview Angle

Common question forms:
- "How do you run a multi-service application locally?"
- "How does service networking work in Docker Compose?"

Answer frame:
Describe the three main sections: `services` (application components), `volumes` (persistent storage), `networks` (connectivity). Explain that service names are DNS hostnames within the Compose network  -  `db:5432` not `localhost:5432`. Address the `depends_on` caveat (starts after container starts, not after service is ready) and how to handle it with health checks. Mention override files for dev-specific configuration.

---

## Related Notes

- [[docker-basics|Docker Basics]]
- [[dockerfile-python|Writing a Dockerfile for Python]]
- [[docker-layers|Docker Layers and Caching]]
- [[kubernetes-basics|Kubernetes Basics]]
