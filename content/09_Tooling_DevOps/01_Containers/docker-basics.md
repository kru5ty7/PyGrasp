---
title: 01 - Docker Basics
description: "Docker is a containerization platform that packages applications and their dependencies into isolated containers — which are processes using Linux namespaces for isolation and cgroups for resource limits, not virtual machines."
tags: [docker, containers, namespaces, cgroups, images, linux, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Docker Basics

> A Docker container is not a virtual machine — it is a Linux process isolated from the host using kernel namespaces (network, PID, filesystem, user) and constrained by cgroups (CPU, memory), sharing the host's kernel but seeing its own isolated world.

---

## Quick Reference

**Core idea:**
- `docker build -t myapp:latest .` — build an image from the Dockerfile in the current directory
- `docker run -p 8080:80 myapp:latest` — start a container, mapping host port 8080 to container port 80
- `docker exec -it CONTAINER_ID bash` — open an interactive shell inside a running container
- `docker logs CONTAINER_ID` — stream container stdout/stderr
- `docker stop CONTAINER_ID` — gracefully stop a container (sends SIGTERM, then SIGKILL after timeout)
- `docker ps` / `docker ps -a` — list running / all containers

**Tricky points:**
- Images are read-only; containers are images plus a writable layer — destroying the container loses any changes not written to a volume
- Port mapping is required to access container services from the host: `-p host_port:container_port`
- Containers are not persistent by default — write persistent data to volumes (`-v`) or bind mounts, not inside the container filesystem
- The Docker daemon runs as root on the host — this has security implications; rootless Docker and user namespaces address this
- `docker run` creates a new container each time; to reuse a stopped container, use `docker start`

---

## What It Is

To understand Docker, it helps to first understand the problem it solves and why the solution is not a virtual machine. Virtual machines solve the isolation problem by emulating an entire computer — the hypervisor gives each VM its own kernel, virtual CPU, virtual memory, and virtual devices. This is complete isolation, but it is expensive: each VM needs hundreds of megabytes for its own OS kernel, takes tens of seconds to start, and imposes significant CPU overhead for the virtualization layer.

Containers solve the same isolation problem using a different mechanism that Linux has supported for years: namespaces and cgroups. A container is a process (or group of processes) running directly on the host kernel, but in a restricted view of the system. The kernel's namespace feature can give a process its own isolated view of: the filesystem (`mount` namespace), the network stack (`network` namespace), the process table (`pid` namespace), user IDs (`user` namespace), and the hostname (`uts` namespace). From inside the container, these feel like an entirely separate machine. But they are not — they are the same host kernel, just with a filtered view.

Docker is the tooling layer on top of these kernel features. It packages the Linux namespace and cgroup configuration into a user-friendly CLI, defines the image format (the portable filesystem snapshot that becomes the container's root filesystem), and provides the daemon that manages container lifecycle. When a developer runs `docker run`, Docker is essentially doing: set up a new set of Linux namespaces, unpack the image's filesystem into the container's mount namespace, apply cgroup resource limits, and exec the specified command as PID 1 inside those namespaces.

---

## How It Actually Works

The Docker architecture has three components: the Docker CLI (client), the Docker daemon (`dockerd`), and the container runtime (typically containerd + runc). The CLI sends commands to the daemon over a Unix socket. The daemon manages images, containers, networks, and volumes. The actual container process is started by runc, which sets up namespaces and cgroups as specified.

Images are layered filesystems. Each `RUN`, `COPY`, and `ADD` instruction in a Dockerfile creates a read-only layer. When a container starts, Docker stacks these layers using a union filesystem (OverlayFS) and adds a thin writable layer on top for any runtime file changes. The key implication: images are immutable and shareable. Two containers from the same image share all the read-only layers; only their writable layers differ.

```bash
# Build: reads Dockerfile, creates image layers
docker build -t myapp:1.0 .

# Run: creates container from image, maps port, runs in background
docker run -d -p 8000:8000 --name webapp myapp:1.0

# Inspect running container
docker ps
docker logs webapp
docker exec -it webapp sh

# Stop and remove
docker stop webapp
docker rm webapp

# Remove the image
docker rmi myapp:1.0
```

Networking: each container gets its own network namespace with a virtual ethernet interface. By default, containers can reach the internet (via NAT through the host network), but the host cannot reach the container unless ports are explicitly published (`-p`). Docker creates a bridge network (`docker0`) and connects container virtual interfaces to it.

Volumes persist data beyond container lifecycle:

```bash
# Named volume (managed by Docker)
docker run -v mydata:/app/data myapp:1.0

# Bind mount (host directory mounted into container)
docker run -v /host/path:/container/path myapp:1.0
```

---

## How It Connects

Writing a Dockerfile correctly requires understanding what Docker layers are and how the build cache works — the Dockerfile is the source for the image that becomes the container.

[[dockerfile-python|Writing a Dockerfile for Python]]

Docker Compose orchestrates multiple containers as a single application — it is the standard next step after understanding single-container Docker.

[[docker-compose|Docker Compose]]

Understanding Docker layers and caching explains why Dockerfile instruction order matters enormously for build performance.

[[docker-layers|Docker Layers and Caching]]

---

## Common Misconceptions

Misconception 1: "Containers are like lightweight VMs."
Reality: Containers are processes, not machines. They share the host kernel — there is no separate kernel booted inside a container. The isolation comes from Linux namespaces, not virtualization. This means a Linux container cannot run on a Windows kernel without a Linux VM underneath (which is exactly what Docker Desktop provides on macOS and Windows — a hidden Linux VM that hosts the container processes).

Misconception 2: "Once I write data inside a container, it persists."
Reality: A container's writable layer is destroyed when the container is removed. Any files written inside the container (outside of mounted volumes) are gone. Use Docker volumes (`-v myvolume:/data`) or bind mounts (`-v /host/path:/container/path`) for any data that must survive container restarts or removals.

Misconception 3: "I need to SSH into a container."
Reality: `docker exec -it CONTAINER_ID bash` (or `sh` if bash is not installed) opens a shell directly inside a running container without SSH. SSH is typically not installed or running in containers — `docker exec` uses the daemon's direct access to the container's namespaces.

---

## Why It Matters in Practice

The portable image format is Docker's central value. An image built on a developer's macOS machine and pushed to a registry runs identically in a Linux CI runner, in a staging server, and in a production Kubernetes pod. The dependency hell of "it works on my machine" — different OS versions, different Python versions, different library installations — is solved because the image carries all of its dependencies. The container runtime on the host only needs to provide the kernel; everything above that is in the image.

For Python applications specifically, Docker eliminates the problem of Python version and virtual environment management on deployment targets. The Dockerfile pins the exact Python version (`FROM python:3.12-slim`), installs exact dependency versions, and the resulting image runs without any host Python configuration.

---

## Interview Angle

Common question forms:
- "What is the difference between a Docker image and a container?"
- "How are containers different from virtual machines?"

Answer frame:
The key insight to communicate: containers are processes using Linux namespaces for isolation and cgroups for resource limits — not VMs, not separate kernels. An image is the static, layered filesystem snapshot (read-only). A container is a running instance of an image with an added writable layer. The daemon manages lifecycle; the CLI talks to the daemon. Mention that data in the writable layer is lost when the container is removed — volumes are the solution.

---

## Related Notes

- [[dockerfile-python|Writing a Dockerfile for Python]]
- [[docker-layers|Docker Layers and Caching]]
- [[docker-compose|Docker Compose]]
- [[multi-stage-builds|Multi-Stage Docker Builds]]
- [[kubernetes-basics|Kubernetes Basics]]
