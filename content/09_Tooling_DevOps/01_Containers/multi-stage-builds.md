---
title: 05 - Multi-Stage Docker Builds
description: "Multi-stage Docker builds use multiple FROM instructions in one Dockerfile to separate build-time tools from runtime artifacts, dramatically reducing final image size by discarding compiler toolchains and intermediate files from the production image."
tags: [docker, multi-stage, build-optimization, image-size, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Multi-Stage Docker Builds

> Multi-stage builds use multiple FROM stages in a single Dockerfile so that build tools (compilers, package managers, test runners) exist only in intermediate stages — the final production image copies only the compiled artifacts, shrinking image size by eliminating everything not needed at runtime.

---

## Quick Reference

**Core idea:**
- Multiple `FROM` instructions in one Dockerfile, each starting a new stage
- `AS name` labels a stage so later stages can reference it
- `COPY --from=builder /src/path /dst/path` — copies files from a named stage into the current stage
- The final `FROM` determines the runtime image — only its layers become the pushed image
- Earlier stages are used during build but not included in the final image
- Significant size reduction: a build image with gcc, pip, and source might be 800MB; the runtime image carrying only the installed packages might be 80MB

**Tricky points:**
- Python projects often use multi-stage builds to install compiled packages (needing gcc) in a builder stage, then copy only `site-packages` to a slim runtime image without gcc
- `COPY --from=builder` copies files, not layers — the build stage's layer history is not included in the final image
- Each stage inherits only what it explicitly copies from previous stages — it starts from its `FROM` image fresh
- Stages can reference each other: `COPY --from=builder`, `COPY --from=0` (by index), or `COPY --from=python:3.12` (from a registry image directly)
- `docker build --target builder .` builds only up to the named stage — useful for testing or caching intermediate stages in CI

---

## What It Is

The classic problem with Python Docker images: some dependencies require compilation. A package like `psycopg2` (PostgreSQL driver) needs `libpq-dev` header files and `gcc` to compile its C extension. These tools are large — adding them to a production Python image can balloon its size from 70MB to 600MB. But they are only needed during installation, not at runtime. Once the `.so` file is compiled, gcc is never touched again.

Multi-stage builds solve this cleanly. The build stage is a full environment with all the tools needed to compile and install. The runtime stage is a minimal environment containing only what runs the application. Between the two stages, a `COPY --from=builder` statement transfers only the installed packages (or compiled binaries) from the build stage to the runtime stage. The build stage's layers — including gcc, libpq-dev, and all the intermediate compilation artifacts — are simply discarded. They are not included in the final image.

The analogy is a factory floor and a showroom. On the factory floor there are welding machines, lathes, and spray booths — tools needed to make the product. The showroom has only the finished product, polished and ready to deliver. A customer receives the product, not the factory. Multi-stage builds are the container equivalent: the final image is the showroom, not the factory.

---

## How It Actually Works

A Python application with compiled dependencies:

```dockerfile
# ============= STAGE 1: Builder =============
FROM python:3.12-slim AS builder

# Install build tools needed for compiled packages
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .

# Install into a specific directory for easy copying
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ============= STAGE 2: Runtime =============
FROM python:3.12-slim AS runtime

# Install only the runtime shared libraries (not the -dev headers)
RUN apt-get update && apt-get install -y \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy only the installed packages from the builder stage
COPY --from=builder /install /usr/local

# Copy application code
COPY . .

# Non-root user
RUN adduser --system --group appuser
USER appuser

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

The `--prefix=/install` flag to pip installs packages into `/install/lib/python3.12/site-packages/` instead of the system Python path. This makes the installed packages easy to copy as a unit with `COPY --from=builder /install /usr/local`.

For Python projects using uv, the pattern is even cleaner:

```dockerfile
FROM python:3.12-slim AS builder

RUN pip install uv

WORKDIR /app
COPY pyproject.toml uv.lock ./

# Install dependencies into a venv
RUN uv venv /app/venv && \
    uv sync --frozen --no-dev

FROM python:3.12-slim AS runtime

WORKDIR /app

# Copy the entire virtualenv from builder
COPY --from=builder /app/venv /app/venv

# Copy application code
COPY src/ ./src/

ENV PATH="/app/venv/bin:$PATH"

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

For compiled Go or Rust tools bundled with a Python application:

```dockerfile
FROM golang:1.22 AS go-builder
WORKDIR /src
COPY tools/ .
RUN go build -o /bin/mytool ./cmd/mytool

FROM python:3.12-slim AS runtime
COPY --from=go-builder /bin/mytool /usr/local/bin/mytool
COPY --from=python-builder /install /usr/local
COPY . .
CMD ["python", "app.py"]
```

---

## How It Connects

Understanding Docker layers explains why deleting files in the same image does not save space — multi-stage builds are the correct solution to images bloated by build tools that single-stage cleanup cannot remove from the layer history.

[[docker-layers|Docker Layers and Caching]]

The final runtime stage should follow all the conventions of a well-written Python Dockerfile: slim base, non-root user, correct CMD vs ENTRYPOINT.

[[dockerfile-python|Writing a Dockerfile for Python]]

In CD pipelines, the multi-stage build is run in CI to produce the production image — the pipeline builds once, pushes the runtime image to the registry, and subsequent deployments pull only the lean final image.

[[cd-docker|CD with Docker]]

---

## Common Misconceptions

Misconception 1: "Multi-stage builds make the build slower because they run more steps."
Reality: While multi-stage builds do execute more Dockerfile instructions, the final image push and pull is dramatically faster due to the reduced size. More importantly, the build stage layers are cached independently — if the compiler tools layer is cached, the full build cost is only paid once. The net effect is usually faster end-to-end CI/CD time due to faster image transfers, despite a slightly longer local build on first run.

Misconception 2: "I need to install runtime system packages in the builder stage so they're available at runtime."
Reality: The runtime stage starts fresh from its `FROM` image. It does not inherit the builder stage's installed system packages (only `COPY --from=builder` files are transferred). Runtime system libraries (e.g., `libpq5`, the runtime PostgreSQL library, vs `libpq-dev`, the development headers) must be installed in the runtime stage with `apt-get install`.

Misconception 3: "Multi-stage builds are only useful for compiled languages."
Reality: For Python, multi-stage builds serve two purposes: eliminating compile-time tools from the runtime image (as described above), and creating separate testing stages. A test stage can run pytest against the installed application, and the build fails if tests fail — without including test dependencies in the production image.

---

## Why It Matters in Practice

Image size has direct operational consequences. A 60MB Python image vs a 600MB image is the difference between a 10-second and a 90-second registry pull on a typical production server. Across a fleet of 100 servers receiving a rolling deployment, this compounds significantly. Smaller images also mean faster container start times in Kubernetes, where images are pulled on scheduling and must be available before the pod becomes ready.

Security scanning also benefits from smaller images — fewer installed packages means a smaller attack surface and fewer CVEs for security scanners to flag. A production image that contains gcc has many more potential vulnerabilities than one that contains only the Python runtime and application packages.

---

## Interview Angle

Common question forms:
- "How do you reduce Docker image size for Python applications?"
- "What are multi-stage Docker builds and when would you use them?"

Answer frame:
Explain the two-stage pattern: a builder stage with compilation tools, a runtime stage with only the application. Describe `COPY --from=builder` as the mechanism for transferring artifacts. Give a concrete Python example: gcc needed to compile psycopg2, but only libpq5 needed at runtime — multi-stage removes gcc from the final image. Mention image size benefits: security surface, pull speed, storage cost.

---

## Related Notes

- [[docker-layers|Docker Layers and Caching]]
- [[dockerfile-python|Writing a Dockerfile for Python]]
- [[docker-basics|Docker Basics]]
- [[cd-docker|CD with Docker]]
