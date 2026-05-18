---
title: 02 - Writing a Dockerfile for Python
description: "A Python Dockerfile starts from a slim base image, copies requirements before application code to leverage layer caching, installs dependencies as a non-root user, and distinguishes CMD (overridable default) from ENTRYPOINT (fixed executable) for correct runtime behavior."
tags: [dockerfile, python, docker, base-image, entrypoint, cmd, non-root, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Writing a Dockerfile for Python

> A Dockerfile is a script of instructions that builds a Docker image layer by layer  -  and for Python specifically, the order of those instructions determines both image size and how fast repeated builds are, making instruction sequence a first-class design decision.

---

## Quick Reference

**Core idea:**
- `FROM python:3.12-slim`  -  minimal Debian-based Python image; `-slim` is 40-60MB vs the full 900MB+
- `WORKDIR /app`  -  sets the working directory for all subsequent commands in the container
- `COPY requirements.txt .` then `RUN pip install`  -  copy requirements first, then code, to maximize cache hits
- `COPY . .`  -  copy application code after dependencies are installed
- `CMD ["uvicorn", "main:app"]`  -  default command, overridable at `docker run` time
- `ENTRYPOINT ["python"]` combined with `CMD ["app.py"]`  -  fixed executable, overridable arguments

**Tricky points:**
- `CMD` vs `ENTRYPOINT`: CMD is fully overridden by `docker run IMAGE command`; ENTRYPOINT is the executable, CMD is its default arguments  -  `docker run IMAGE alt.py` replaces CMD but appends to ENTRYPOINT
- Running as root inside a container is a security risk  -  use `USER` instruction after install to drop to a non-root user
- Each `RUN` creates a new layer  -  chain commands with `&&` to reduce layer count and combine cleanup in the same RUN
- `COPY . .` placed before `RUN pip install` causes every code change to invalidate the pip install layer  -  always install dependencies before copying code
- `python:3.12-slim` lacks some system packages (git, gcc); `python:3.12-slim-bookworm` is the Debian Bookworm variant; `python:3.12-alpine` is even smaller but uses musl libc which can cause issues with compiled packages

---

## What It Is

A Dockerfile is the source code for a Docker image. Just as source code compiles to a binary, a Dockerfile is processed by `docker build` to produce an image. Each instruction in the Dockerfile corresponds to a layer in the image filesystem  -  a set of files added, modified, or removed relative to the previous layer. The resulting image is a stack of these layers, and the container that runs from the image adds one more writable layer on top.

For Python applications, writing a correct Dockerfile means making several choices that have significant consequences: which base image to use (full vs slim vs alpine), how to structure dependency installation vs code copying (affects build cache efficiency), whether to run as root or a non-root user (security), and how to configure the entry point (affects how the container behaves as a building block in orchestration systems). These are not arbitrary style choices  -  each has a concrete reason rooted in how Docker builds and runs containers.

The base image choice is the most impactful for image size. The official `python:3.12` image is Debian full, roughly 900MB  -  it includes compilers, development headers, and tools that are useful for building Python packages but unnecessary for running them. The `python:3.12-slim` variant strips most of those tools, reducing size to around 40-70MB. The trade-off: some Python packages with compiled C extensions cannot install on the slim image without additional system packages. The standard practice is to start with slim, add only what compilation requires, and consider multi-stage builds to eliminate the build tools from the final image.

---

## How It Actually Works

A production-quality Python Dockerfile for a FastAPI application:

```dockerfile
# syntax=docker/dockerfile:1

# Stage: runtime image
FROM python:3.12-slim

# Set working directory for all subsequent instructions
WORKDIR /app

# Create a non-root user for security
RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup appuser

# Copy only requirements file first  -  maximizes layer cache
COPY requirements.txt .

# Install dependencies as root (needs to write to site-packages)
# Combine into one RUN to minimize layers; use --no-cache-dir to reduce image size
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code (invalidates cache only when code changes)
COPY . .

# Switch to non-root user before running
USER appuser

# Expose the port the app runs on (documentation only  -  does not publish)
EXPOSE 8000

# CMD: default command; overridable with docker run IMAGE <command>
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

The ordering of `COPY requirements.txt` before `COPY . .` is critical for build performance. Docker builds layers sequentially and caches each layer. If a layer's inputs have not changed, Docker reuses the cached layer without rebuilding. By copying requirements before code, a developer can change Python files without invalidating the `pip install` layer  -  only the `COPY . .` layer and subsequent layers are rebuilt. Without this ordering, every code change triggers a full `pip install`.

`ENTRYPOINT` vs `CMD` is the most commonly confused distinction:

```dockerfile
# CMD alone: the entire command is overridable
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
# docker run myapp python manage.py migrate  -> works, overrides CMD

# ENTRYPOINT + CMD: entrypoint is fixed, CMD is default arguments
ENTRYPOINT ["uvicorn"]
CMD ["main:app", "--host", "0.0.0.0", "--port", "8000"]
# docker run myapp other_app:app  -> runs "uvicorn other_app:app"
# docker run --entrypoint="" myapp python manage.py  -> overrides entrypoint
```

For most Python web services, `CMD` alone is more flexible. `ENTRYPOINT` is useful when the image is designed to function as a specific executable  -  for example, an image that wraps a CLI tool.

---

## How It Connects

Docker layer caching is the mechanism that makes instruction ordering in the Dockerfile consequential  -  understanding layers explains why requirements must be copied before code.

[[docker-layers|Docker Layers and Caching]]

Multi-stage builds extend the Dockerfile pattern to separate build-time and runtime stages, dramatically reducing image size by discarding compiler toolchains.

[[multi-stage-builds|Multi-Stage Docker Builds]]

Docker Compose references the Dockerfile via the `build:` directive  -  a Compose service can build its image from the local Dockerfile automatically.

[[docker-compose|Docker Compose]]

---

## Common Misconceptions

Misconception 1: "EXPOSE makes the container's port accessible from the host."
Reality: `EXPOSE` is documentation only  -  it records which port the container intends to use but does not actually publish it. To make a port accessible from the host, use the `-p` flag in `docker run`: `docker run -p 8000:8000 myapp`. In Docker Compose, use the `ports:` section.

Misconception 2: "Running as root inside a container is safe because the container is isolated."
Reality: Docker's namespace isolation is not perfect  -  container escapes (vulnerabilities that allow a process to break out of namespace isolation and access the host) do exist. Running as a non-root user inside the container means that even if an exploit allows code execution in the container, it runs without root privileges. Use the `USER` instruction to drop to a non-root user after installing dependencies.

Misconception 3: "I should put `COPY . .` at the top of the Dockerfile to make code changes available early."
Reality: Placing `COPY . .` before `RUN pip install` means every code change invalidates the pip layer  -  every build reruns `pip install` even if requirements.txt did not change. Always copy requirements and install dependencies before copying application code.

---

## Why It Matters in Practice

A well-written Dockerfile has compound benefits. Small images (`-slim` base + multi-stage builds) transfer faster from registries to deployment targets  -  a 50MB image vs a 900MB image is the difference between a 5-second and a 90-second deploy pull time at typical bandwidth. Cached pip install layers mean developer iteration cycles are fast  -  changing a `.py` file triggers only the `COPY . .` and later layers, not a reinstall. Non-root users reduce the blast radius of container security vulnerabilities.

These are not theoretical concerns. In high-frequency deployment environments (deploying dozens of times per day), image size and build cache effectiveness directly determine deployment velocity.

---

## Interview Angle

Common question forms:
- "How do you write a Dockerfile for a Python application?"
- "Why does instruction order in a Dockerfile matter?"

Answer frame:
Walk through the key decisions: slim base image for size, copy requirements before code for cache efficiency, install without `--cache-dir` to keep image lean, drop to a non-root user for security, and distinguish CMD (overridable default command) from ENTRYPOINT (fixed executable). The cache efficiency explanation  -  why `COPY requirements.txt .` before `COPY . .`  -  is a strong signal of practical experience.

---

## Related Notes

- [[docker-basics|Docker Basics]]
- [[docker-layers|Docker Layers and Caching]]
- [[multi-stage-builds|Multi-Stage Docker Builds]]
- [[docker-compose|Docker Compose]]
