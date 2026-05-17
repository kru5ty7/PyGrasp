---
title: 04 - Docker Layers and Caching
description: "Docker images are stacks of read-only layers created by Dockerfile instructions, stored by content hash in a shared cache — when a layer's inputs are unchanged, Docker reuses it, making build speed almost entirely a function of cache hit rate."
tags: [docker, layers, caching, overlayfs, build-cache, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Docker Layers and Caching

> Docker images are composed of stacked read-only filesystem layers, each created by a Dockerfile instruction — the build cache reuses unchanged layers, so instruction order in a Dockerfile is an optimization decision: put rarely-changing instructions first, frequently-changing ones last.

---

## Quick Reference

**Core idea:**
- Every `RUN`, `COPY`, and `ADD` instruction creates a new immutable layer
- `FROM` selects a base image (which is itself a stack of layers)
- A cache hit skips rebuilding that layer and all subsequent layers are also eligible for cache
- Cache is invalidated when: the instruction text changes, or a `COPY`/`ADD` source file changes
- `docker build --no-cache` bypasses the cache entirely
- `docker history IMAGE` — shows all layers in an image with their sizes

**Tricky points:**
- Cache is invalidated sequentially — if layer N is invalidated, all layers N+1 through the end must be rebuilt, even if their own inputs have not changed
- `RUN apt-get update` in isolation is a cache antipattern — always combine with `apt-get install -y` in the same `RUN` command to avoid stale package lists
- The `COPY . .` instruction is invalidated by any file change in the current directory, including `.git/` changes — use `.dockerignore` to exclude irrelevant files
- Layer size counts even for deleted files — `RUN rm -rf /tmp/large-file` does not reduce image size if the file was added in a previous layer; cleanup must happen in the same `RUN` that created the file
- Multi-stage builds allow discarding layers entirely rather than trying to clean up after them

---

## What It Is

Imagine building a sandwich by adding ingredients one layer at a time, photographing the sandwich after each addition, and pinning those photos on a wall. When you want a particular sandwich, you do not make it from scratch — you find the photo where it was last at the state you want, and continue from there. Docker layers work the same way: each instruction in a Dockerfile creates a snapshot of the filesystem at that point, and Docker caches that snapshot. When you rebuild, Docker compares each instruction to the cached snapshot — if nothing changed, it uses the snapshot rather than re-executing the instruction.

This layer model serves two purposes. First, it makes builds fast: if you change one Python file in a project with 50 dependencies, Docker reuses the cached layer where all 50 packages were installed, and only rebuilds the layer where your code was copied in. Second, it enables efficient storage and distribution: layers are stored by content hash, and the same layer used in a hundred different images is stored only once on disk and pulled only once from a registry. Two images that share a Python 3.12-slim base image share all of those base layers — no duplication.

The storage mechanism is a union filesystem, specifically OverlayFS on modern Linux systems. OverlayFS stacks multiple filesystem directories (the layers) so that they appear as a single unified filesystem. When a file exists in multiple layers, the uppermost layer wins. When a file is deleted, OverlayFS adds a "whiteout" file in the upper layer that hides the file in lower layers — the file still exists in the lower layer, occupying space, but is invisible. This is why deleting a file in a later layer does not reduce image size.

---

## How It Actually Works

The sequence of layers created by a Dockerfile determines build performance:

```dockerfile
# Layer 1: Base OS and Python runtime (pulled from registry, rarely changes)
FROM python:3.12-slim

# Layer 2: System packages (changes only when requirements change)
RUN apt-get update && apt-get install -y \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Layer 3: Python dependencies (changes when requirements.txt changes)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Layer 4: Application code (changes frequently — every commit)
COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

When a developer changes `main.py` and rebuilds:
- Layer 1: cache hit (base image unchanged)
- Layer 2: cache hit (apt packages unchanged)
- Layer 3 (COPY requirements.txt): cache hit (requirements.txt unchanged)
- Layer 3 (pip install): cache hit (requirements.txt unchanged)
- Layer 4 (COPY . .): cache miss (main.py changed — this instruction sees a different input)
- Re-execute: `COPY . .` and `CMD` (trivial)

The entire pip install — which might take 2 minutes — is skipped. Without the deliberate ordering, placing `COPY . .` before `pip install` would make every code change trigger a full reinstall:

```dockerfile
# WRONG ORDER: cache-busting antipattern
FROM python:3.12-slim
WORKDIR /app
COPY . .                               # Any file change invalidates here
RUN pip install -r requirements.txt    # Reinstalls on every build
```

The `.dockerignore` file is as important as the Dockerfile for cache behavior. Files listed in `.dockerignore` are excluded from `COPY . .` — they do not appear to Docker at all. A change to an excluded file does not invalidate the `COPY . .` layer.

```
# .dockerignore
.git
.venv
__pycache__
*.pyc
.pytest_cache
tests/
*.md
.env
```

The `apt-get update && apt-get install -y` combination pattern is required because of how layer caching interacts with package indices. If `RUN apt-get update` and `RUN apt-get install -y libpq-dev` are separate layers, a cached `apt-get update` layer may have a stale package index when the install layer runs — resulting in "package not found" errors. Combining them ensures the package index is always fresh when packages are installed.

---

## How It Connects

Multi-stage builds solve the problem that layer deletion does not reclaim space — instead of cleaning up within layers, the build-stage layers are simply discarded entirely.

[[multi-stage-builds|Multi-Stage Docker Builds]]

The layer model is what makes a well-ordered Dockerfile fast in CI/CD — the same ordering principles that matter locally are critical when CI rebuilds an image on every push.

[[cd-docker|CD with Docker]]

Understanding layers is prerequisite to understanding why copying requirements before code is the canonical Python Dockerfile pattern.

[[dockerfile-python|Writing a Dockerfile for Python]]

---

## Common Misconceptions

Misconception 1: "Deleting a file in a RUN instruction removes it from the image."
Reality: If a file is added in layer N and deleted in layer N+1, the file still exists in layer N and contributes to the total image size. OverlayFS records the deletion as a "whiteout" entry in layer N+1, but the underlying content is still there. To truly remove a file, the deletion must happen in the same `RUN` instruction that created it: `RUN wget large-file.tar.gz && tar -xf large-file.tar.gz && rm large-file.tar.gz`.

Misconception 2: "The build cache persists forever and is always reliable."
Reality: The build cache is local to the Docker daemon running the build. On a fresh CI runner (a new machine for each CI job), the cache is empty and every layer must be rebuilt. Persisting the Docker build cache between CI runs requires explicit configuration — either a registry-based cache (using `--cache-from` with a pushed cache image) or CI-platform-specific cache mechanisms.

Misconception 3: "More layers means a larger image."
Reality: Image size is determined by the total bytes in all layers, not the number of layers. A single large `RUN` instruction and many small ones containing the same files result in the same total size. The number of layers matters for performance (more layers means more OverlayFS stacking overhead at runtime) but the typical difference is negligible. What matters for size is what data is in the layers, not how many layers there are.

---

## Why It Matters in Practice

In a fast-moving development team, a poorly ordered Dockerfile turns every code change into a 2–5 minute wait for `pip install`. A well-ordered Dockerfile reduces that to under 10 seconds because the dependency layer is cached. At dozens of builds per day per developer, the compounding cost of a cache-busting Dockerfile is substantial.

In CI, the cache situation is more complex because CI runners are often ephemeral. The solution is to push the image to a registry after each build and pull it as the cache source for the next build (`docker build --cache-from myapp:latest`). This simulates a warm local cache in a stateless CI environment.

---

## Interview Angle

Common question forms:
- "Why do you copy `requirements.txt` before your application code in a Dockerfile?"
- "How does Docker's layer cache work?"

Answer frame:
The answer should explain: layers are created by Dockerfile instructions, each layer is cached by content hash, changing a layer's input invalidates that layer and all subsequent layers. Therefore `COPY requirements.txt` + `RUN pip install` must come before `COPY . .` — otherwise any code change invalidates the pip install layer. Mention `.dockerignore` as the complement (prevents irrelevant file changes from invalidating layers).

---

## Related Notes

- [[dockerfile-python|Writing a Dockerfile for Python]]
- [[multi-stage-builds|Multi-Stage Docker Builds]]
- [[docker-basics|Docker Basics]]
- [[docker-compose|Docker Compose]]
