---
title: 04 - CD with Docker
description: "A Docker-based CD pipeline builds an image in CI, pushes it to a container registry like GHCR, then executes a deploy step that updates the running application  -  with secrets managed through CI environment variables, never in the Dockerfile."
tags: [cd, docker, github-actions, ghcr, deployment, secrets, registry, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# CD with Docker

> Continuous deployment with Docker means: CI builds and tests the code, a successful CI run builds a Docker image tagged with the commit SHA, the image is pushed to a registry, and a deploy step updates the running application to pull the new image  -  automating the full path from merged code to running software.

---

## Quick Reference

**Core idea:**
- Build image in CI: `docker build -t ghcr.io/org/app:$SHA .`
- Push to GitHub Container Registry: `docker push ghcr.io/org/app:$SHA`
- Tag as `latest` for the most recent main-branch build
- Secrets (registry credentials, deployment tokens) go in GitHub Actions secrets, never in the Dockerfile
- `docker/build-push-action` handles multi-platform builds, registry login, and push in one step
- Deploy step: SSH to server and `docker pull && docker run`, or `kubectl set image`, or trigger a Kubernetes CD tool (ArgoCD, Flux)

**Tricky points:**
- Image tags should include the git SHA for traceability  -  `app:abc1234` identifies exactly which commit is deployed
- `latest` tag is useful as a human-readable reference but should not be relied upon for deployments  -  it points to whatever was pushed most recently and can be surprising in parallel builds
- The build and push should use the layer cache from the previous build  -  `cache-from: type=registry,ref=ghcr.io/org/app:cache` avoids rebuilding unchanged layers in CI
- `GITHUB_TOKEN` has permission to push to GHCR for the same repository without additional setup (must be enabled in repository settings)
- Build secrets (build-time credentials, not runtime) can be passed to `docker build` with `--secret` (BuildKit) without persisting them in image layers

---

## What It Is

Continuous deployment with Docker is the practice of automating the path from a merged pull request to a running update in production. The "continuous" part means this path is automated and triggered by the CI pipeline succeeding  -  a developer merges code, CI validates it, and if validation passes, the deployment happens automatically without manual steps.

The Docker image is the deployment artifact. Unlike deploying code directly to a server (where the deployment environment must have the right Python version, virtualenv, and system packages), deploying a Docker image means deploying a self-contained filesystem. The image built in CI is identical to what runs in production  -  same Python version, same packages, same configuration. The deployment server only needs a container runtime; all application dependencies travel inside the image.

The registry is the intermediary storage layer. The CI system cannot directly transfer an image to the deployment target  -  the image might be 100MB and the deployment target might be a Kubernetes cluster with 50 nodes. Instead, CI pushes the image to a registry (GitHub Container Registry, Docker Hub, AWS ECR), and deployment targets pull from the registry. Each pull is incremental  -  only the changed layers are downloaded, because registries store layers by content hash.

---

## How It Actually Works

A complete CD workflow that builds, pushes, and deploys:

```yaml
# .github/workflows/cd.yml
name: CD

on:
  push:
    branches: [main]    # Only deploy on main branch merges

jobs:
  # CI runs first (as a separate workflow or as a required check)
  # This CD workflow assumes CI has already passed

  build-and-push:
    name: Build and Push Docker Image
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write   # Required to push to GHCR

    outputs:
      image: ${{ steps.meta.outputs.tags }}    # Pass image tag to deploy job

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3     # Required for cache and multi-platform

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }} # Automatic; no setup needed

      - name: Extract metadata (tags, labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha,prefix=sha-       # ghcr.io/org/app:sha-abc1234
            type=raw,value=latest      # ghcr.io/org/app:latest

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=registry,ref=ghcr.io/${{ github.repository }}:cache
          cache-to: type=registry,ref=ghcr.io/${{ github.repository }}:cache,mode=max

  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: build-and-push
    environment: staging   # Requires approval if configured in GitHub settings

    steps:
      - name: Deploy to Kubernetes (staging)
        run: |
          # Update the Deployment to use the new image
          kubectl set image deployment/myapp \
            app=ghcr.io/${{ github.repository }}:sha-${{ github.sha }} \
            --namespace staging
          kubectl rollout status deployment/myapp --namespace staging
        env:
          KUBECONFIG: ${{ secrets.KUBECONFIG_STAGING }}

  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: deploy-staging
    environment: production  # Requires manual approval in GitHub settings
    if: github.ref == 'refs/heads/main'

    steps:
      - name: Deploy to Kubernetes (production)
        run: |
          kubectl set image deployment/myapp \
            app=ghcr.io/${{ github.repository }}:sha-${{ github.sha }} \
            --namespace production
          kubectl rollout status deployment/myapp --namespace production
        env:
          KUBECONFIG: ${{ secrets.KUBECONFIG_PRODUCTION }}
```

**Secrets management in Docker builds:**

Runtime secrets (database passwords, API keys) must never be in the Dockerfile or image layers. They are injected at runtime through environment variables or Kubernetes Secrets. Build-time secrets (e.g., a private PyPI token to install a private package) can be passed using BuildKit's `--secret` mount:

```dockerfile
# Dockerfile
RUN --mount=type=secret,id=pip_token \
    pip install --extra-index-url https://$(cat /run/secrets/pip_token)@private.registry.example.com/simple/ myprivatepkg
```

```yaml
# GitHub Actions step
- name: Build with secret
  uses: docker/build-push-action@v5
  with:
    context: .
    secrets: |
      pip_token=${{ secrets.PIP_TOKEN }}
```

The secret is mounted as a file inside the build container but is not stored in any layer  -  it is not visible in the image history.

**Simple deployment without Kubernetes** (SSH to a VM):

```yaml
- name: Deploy to VM
  uses: appleboy/ssh-action@v1
  with:
    host: ${{ secrets.DEPLOY_HOST }}
    username: deploy
    key: ${{ secrets.DEPLOY_SSH_KEY }}
    script: |
      docker pull ghcr.io/${{ github.repository }}:latest
      docker stop myapp || true
      docker rm myapp || true
      docker run -d \
        --name myapp \
        --restart unless-stopped \
        -p 8000:8000 \
        -e DATABASE_URL=${{ secrets.DATABASE_URL }} \
        ghcr.io/${{ github.repository }}:latest
```

---

## How It Connects

The CD pipeline runs after CI validates the code  -  understanding the CI pipeline structure clarifies when CD triggers.

[[ci-testing-pipeline|CI Testing Pipeline]]

The Docker image being pushed was built from a Dockerfile  -  layer caching in the build-push-action uses the same layer cache principles as local builds.

[[docker-layers|Docker Layers and Caching]]

The Kubernetes deploy step updates the Deployment resource  -  rolling updates and probe gating apply here.

[[kubernetes-deployments|Kubernetes Deployments]]

---

## Common Misconceptions

Misconception 1: "The `latest` tag is reliable for identifying what version is running."
Reality: `latest` points to the most recently pushed image, which changes with every main branch merge. If two merges happen in quick succession, `latest` moves before both deployments complete. Using the git SHA tag (`sha-abc1234`) for deployments provides unambiguous traceability: you can always determine which commit hash is running in production by inspecting the running container's image tag.

Misconception 2: "Secrets passed as `ARG` or `ENV` in Dockerfiles are safe because they are not in the source code."
Reality: `ARG` and `ENV` values are stored in the image's layer history and are visible in `docker history IMAGE` or `docker inspect IMAGE`. Anyone with pull access to the image can read them. Use BuildKit's `--secret` mount for build-time credentials; use runtime environment variables (not baked into the image) for runtime credentials.

Misconception 3: "CD should always deploy automatically without any human approval step."
Reality: For production deployments, many organizations require at least one manual approval. GitHub Actions' `environment:` concept with "required reviewers" implements this gate  -  the deployment job waits for a human to click "Approve" in the GitHub UI before proceeding. This is not a failure of CD; it is the appropriate application of automation for the risk profile of a production change.

---

## Why It Matters in Practice

Automated CD eliminates deployment friction that otherwise causes infrequent, high-risk releases. When deploying requires a developer to manually build an image, push it, SSH into servers, pull the image, and restart services  -  all steps where a mistake means downtime  -  teams deploy infrequently to avoid the ceremony. When deployment is automated and triggered by a merge, teams deploy many times per day. Each individual deployment is smaller, lower risk, and easier to debug if it causes a problem.

The SHA-tagged image is the key artifact that connects the entire pipeline. A production incident can be traced back to: "the image running is `sha-abc1234`" -> "that SHA is commit message `X`" -> "that was merged in PR `#123`" -> "these are the exact file changes." Full traceability from incident to diff, with no manual bookkeeping.

---

## Interview Angle

Common question forms:
- "How would you set up a deployment pipeline for a Dockerized Python application?"
- "How do you manage secrets in a Docker-based CI/CD pipeline?"

Answer frame:
Describe the three-step CD flow: build image -> push to registry -> deploy. Explain SHA tagging for traceability. Explain that runtime secrets are injected at runtime (environment variables, Kubernetes Secrets), never baked into the image. Describe the build cache pattern (`cache-from: type=registry`) for fast CI builds. Mention the staging -> production gate (manual approval) for production safety.

---

## Related Notes

- [[ci-testing-pipeline|CI Testing Pipeline]]
- [[github-actions-basics|GitHub Actions Basics]]
- [[docker-layers|Docker Layers and Caching]]
- [[multi-stage-builds|Multi-Stage Docker Builds]]
- [[kubernetes-deployments|Kubernetes Deployments]]
- [[semantic-versioning|Semantic Versioning]]
