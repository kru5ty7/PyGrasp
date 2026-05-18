---
title: Lambda Layers
description: Lambda layers are versioned ZIP archives of shared code or dependencies mounted at /opt, allowing multiple functions to share libraries without duplicating deployment packages.
tags: [aws, cloud, layer-11, lambda, layers, dependencies]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda Layers

> Lambda layers let you share common Python dependencies — numpy, pandas, requests, database drivers — across multiple functions without bundling the same files into every deployment package.

---

## Quick Reference

**Core idea:**
- A layer is a ZIP archive published to Lambda with its own version number
- Layers are mounted at `/opt` in the execution environment; Python packages go under `/opt/python/`
- Up to 5 layers per function; total unzipped size (function + layers) must not exceed 250MB
- Single layer: 50MB zipped, 250MB unzipped
- Layer versions are immutable — updating a layer creates a new version; functions pin to a specific version
- AWS and third parties publish public layers (AWS Data Wrangler, AWS SDK for Pandas, Powertools for Lambda)

**Tricky points:**
- Lambda automatically adds `/opt/python` to `sys.path` for Python runtimes — no `PYTHONPATH` fiddling needed
- Layers are region-specific — a layer published in `us-east-1` cannot be used by a function in `eu-west-1`
- The 250MB unzipped total limit includes the function code itself — large ML libraries hit this quickly
- Sharing a layer across accounts requires updating the layer's resource-based policy
- For dependencies exceeding 250MB unzipped, container images are the correct path

---

## What It Is

Think of Lambda layers as shared shelving in a workshop. Each workbench (function) in the shop can hold its own tools, but some tools — a large power drill, a specialty saw — are expensive to duplicate at every workbench. Instead, you put those tools on shared shelves in the middle of the room, and any workbench can reach over and grab them. The shared shelves are the layers. Each function still works independently; it just knows where to look for the common tools.

Before layers existed, every Lambda function had to bundle all its dependencies in its own deployment ZIP. If ten functions all needed pandas and numpy, you shipped ten copies of pandas and numpy. Each deploy of any one function required rebuilding and re-uploading a 40MB package. Layers changed this: you publish pandas and numpy as a single layer once, attach that layer to all ten functions, and each function's deployment package shrinks to just its own code. Deployments become faster, package sizes become manageable, and dependency updates become a single publish-and-reattach operation.

The tradeoff is version coupling. When you update a layer, every function that references it must be updated to point to the new version. This is intentional — Lambda layers are versioned and immutable, so a function always runs against the exact library version it was tested with. It also means that a dependency security patch requires touching every function that uses the affected layer, which adds operational overhead for large function fleets.

---

## How It Actually Works

Python packages in a layer must be placed under a `python/` directory inside the ZIP archive. Lambda's Python runtime adds `/opt/python` to `sys.path` automatically, so any package installed there is importable as if it were installed in the function's own virtual environment. For packages with native extensions (compiled C code), they must be compiled for the Lambda execution environment's architecture and OS. The standard approach is to install dependencies on Amazon Linux 2023 or to use the `--platform manylinux` flags with pip.

```bash
# Build a layer for requests and boto3-stubs
mkdir -p python
pip install requests boto3-stubs[essential] -t python/

# Zip the layer
zip -r my-deps-layer.zip python/

# Publish the layer to Lambda
aws lambda publish-layer-version \
    --layer-name my-python-deps \
    --description "requests and type stubs" \
    --zip-file fileb://my-deps-layer.zip \
    --compatible-runtimes python3.11 python3.12 \
    --compatible-architectures x86_64 arm64
```

The output includes the `LayerVersionArn`. Use that ARN when creating or updating a function:

```bash
aws lambda update-function-configuration \
    --function-name my-function \
    --layers arn:aws:lambda:us-east-1:123456789012:layer:my-python-deps:3
```

The equivalent operation via boto3:

```python
import boto3

lambda_client = boto3.client("lambda", region_name="us-east-1")

# Publish a new layer version from a local ZIP
with open("my-deps-layer.zip", "rb") as f:
    response = lambda_client.publish_layer_version(
        LayerName="my-python-deps",
        Description="requests and type stubs v2",
        Content={"ZipFile": f.read()},
        CompatibleRuntimes=["python3.11", "python3.12"],
    )

layer_arn = response["LayerVersionArn"]
print(f"Published: {layer_arn}")

# Attach the new layer version to a function
lambda_client.update_function_configuration(
    FunctionName="my-function",
    Layers=[layer_arn],
)
```

For cross-account layer sharing, add a permission to the layer's resource policy:

```bash
aws lambda add-layer-version-permission \
    --layer-name my-python-deps \
    --version-number 3 \
    --statement-id allow-account-456 \
    --action lambda:GetLayerVersion \
    --principal 456789012345
```

---

## How It Connects

Layers are most useful in the context of large dependency trees — data science libraries, database drivers, internal shared utilities. When the dependency tree grows beyond 250MB unzipped, container images take over as the deployment mechanism.

[[lambda-container|Lambda with Container Images]] — explains the container image deployment path, which removes the 250MB limit and is the correct choice for heavy ML or data science workloads.

Lambda Powertools for Python is distributed as a public Lambda layer and provides structured logging, tracing, and metrics patterns that complement the handler patterns described in the handlers note.

[[lambda-handlers|Lambda Handlers]] — covers initialisation patterns and structured logging, which are the primary consumers of shared layer libraries in production functions.

---

## Common Misconceptions

Misconception 1: You can modify a layer version after publishing it.
Reality: Layer versions are immutable. Publishing a new version creates version N+1 with a new ARN. Functions continue to use their pinned version until you explicitly update the function configuration to reference the new ARN. This immutability is a feature — it prevents silent dependency drift across functions.

Misconception 2: Layers are the right solution for all large dependencies.
Reality: The 250MB total unzipped limit (function + all layers combined) rules out heavy ML frameworks. PyTorch's CPU-only package exceeds 600MB unzipped. For those use cases, the Lambda container image deployment path (up to 10GB) is the correct approach. Layers are optimally suited for moderate-sized shared libraries: HTTP clients, database drivers, utility packages, and internal shared code.

---

## Why It Matters in Practice

Layers reduce deployment friction and enforce dependency consistency across a Lambda function fleet. A team with twenty Python Lambda functions sharing a common database driver or internal utility library benefits immediately: one layer publish propagates the change to all functions without rebuilding twenty ZIP packages. The layer version pinning model also makes dependency auditing tractable — you can query which functions use which layer version and systematically roll out security patches.

---

## What Breaks in Production

**Scenario 1: Native extension compiled for wrong architecture**

A layer is built on a developer's macOS machine with `pip install numpy -t python/`. When Lambda tries to import numpy, it raises `ImportError: ... incompatible architecture`.

```bash
# Mistake: building native dependencies on a non-Linux machine
pip install numpy -t python/

# Fix: build on Amazon Linux 2023 or use the manylinux wheel
pip install numpy \
    --platform manylinux2014_x86_64 \
    --only-binary=:all: \
    --python-version 3.12 \
    -t python/
```

**Scenario 2: Exceeding the 250MB unzipped total limit**

A function uses a layer with pandas (50MB) and a second layer with scipy (80MB), plus its own code (30MB). Adding a third layer with a 100MB ML library hits the limit.

```bash
# Check current total unzipped size
aws lambda get-function-configuration \
    --function-name my-function \
    --query "Layers"
# If approaching 250MB, switch to a container image deployment
```

---

## Interview Angle

Common question forms:
- "How do you share Python libraries across multiple Lambda functions?"
- "What are the limits of Lambda layers, and when would you use a container image instead?"
- "How does Lambda find Python packages installed in a layer?"

Answer frame:
Explain the `/opt/python` mount path and automatic `sys.path` inclusion. Describe the 250MB total limit and 5-layer cap. Contrast layers (shared libraries, moderate size) with container images (large dependencies, full control over the environment). Mention immutable versioning and the cross-account sharing model.

---

## Related Notes

- [[lambda-overview|Lambda Overview]]
- [[lambda-container|Lambda with Container Images]]
- [[lambda-python|Lambda with Python]]
- [[lambda-handlers|Lambda Handlers]]
