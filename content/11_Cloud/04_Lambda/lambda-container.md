---
title: 42 - Lambda with Container Images
description: Lambda container image deployment removes the 250MB package size limit, enabling ML models and large dependency trees to run serverlessly - at the cost of larger cold starts and additional ECR infrastructure.
tags: [aws, cloud, layer-11, lambda, containers, docker]
status: draft
difficulty: advanced
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda with Container Images

> Lambda container images allow you to package a function with up to 10GB of dependencies - the correct deployment path for ML models, large data science stacks, and workloads where reproducible environments matter more than minimal cold starts.

---

## Quick Reference

**Core idea:**
- Container images can be up to 10GB (vs 250MB unzipped for ZIP deployments)
- Must be stored in Amazon ECR - DockerHub images are not directly supported
- The image must implement the Lambda Runtime Interface Client (RIC); AWS base images include it
- Lambda Runtime Interface Emulator (RIE) enables local testing of container images
- Cold starts are longer for container images - image layer caching at the host level partially mitigates this
- Use cases: PyTorch/TensorFlow models, heavy scipy/numpy stacks, reproducible ML inference environments

**Tricky points:**
- The container must listen on port 8080 for the Lambda runtime API - AWS base images handle this automatically
- Non-AWS base images require manually installing the Lambda RIC (`pip install awslambdaric`)
- Image layers are cached at the Lambda host level but the first invocation on a new host still downloads uncached layers
- ECR image URIs include the digest - Lambda pins to the exact image digest, not a mutable tag like `latest`
- The Lambda execution role must have `ecr:GetDownloadUrlForLayer` and related ECR permissions if using a private ECR repository in a different account

---

## What It Is

Lambda container images are the answer to a fundamental packaging problem. Think of ZIP deployments as carrying your lunch in a small bento box - it is efficient, light, and fast to pick up, but the compartments are limited in size. Container images are like checking luggage on a flight: far more capacity, significantly more overhead, but the only way to bring things that simply will not fit in a bento box. A 600MB PyTorch installation, a fine-tuned language model, and a stack of scientific Python libraries cannot fit in a 250MB ZIP archive. They fit comfortably in a 5GB container image.

The container image deployment path also solves the environment reproducibility problem that has frustrated ML practitioners since the beginning of the field. When you build a Docker image with a specific Python version, specific library versions, and a specific compiled binary, you know exactly what will run in Lambda. The same image that passes your local test suite is the image that executes in production. There is no gap between local development and the Lambda execution environment - they are the same thing. This matters enormously for ML inference workloads where model output can change subtly between library versions.

The tradeoff is real. Container images have longer cold starts than ZIP deployments because Lambda must retrieve and decompress image layers before the runtime can start. AWS mitigates this through an optimised image loading mechanism (SOCI snapshotter and pre-fetched layer caching at the host level), but a 5GB image will always have a longer cold start than a 5MB ZIP. For latency-sensitive APIs, this tradeoff requires deliberate analysis. For background inference workloads, batch processing, or scheduled jobs where cold start latency is irrelevant, container images are often the best choice.

---

## How It Actually Works

The workflow is: write a standard Lambda handler, package it in a Dockerfile that uses an AWS Lambda base image, build and push the image to ECR, and create or update the Lambda function to reference the ECR image URI. AWS Lambda base images for Python (`public.ecr.aws/lambda/python:3.12`) ship with the Lambda Runtime Interface Client pre-installed, so no additional plumbing is required. The `CMD` in the Dockerfile specifies the handler in the familiar `module.function` format.

```dockerfile
# Dockerfile for a Lambda function using the AWS base image
FROM public.ecr.aws/lambda/python:3.12

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy function code
COPY main.py .

# Set the Lambda handler (module.function_name)
CMD ["main.handler"]
```

```python
# main.py - standard Lambda handler, no container-specific code required
import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Module-level initialisation - runs once per cold start
# For ML models, load the model here
import torch  # noqa: E402 - imported here because it is the container deployment that enables this

MODEL_PATH = os.environ.get("MODEL_PATH", "/opt/model/model.pt")
model = None  # lazy-loaded on first invocation to avoid timeout on provisioned concurrency initialisation


def handler(event, context):
    global model
    if model is None:
        logger.info("Loading model (first warm invocation or cold start)")
        model = torch.jit.load(MODEL_PATH)
        model.eval()

    body = json.loads(event.get("body") or "{}")
    inputs = body.get("inputs", [])

    with torch.no_grad():
        tensor = torch.tensor(inputs)
        output = model(tensor)

    return {
        "statusCode": 200,
        "body": json.dumps({"predictions": output.tolist()}),
        "headers": {"Content-Type": "application/json"},
    }
```

Building, pushing to ECR, and creating the Lambda function:

```bash
# Authenticate Docker to ECR
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-1

aws ecr get-login-password --region $AWS_REGION \
    | docker login --username AWS --password-stdin \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Create the ECR repository (once)
aws ecr create-repository --repository-name my-lambda-ml --region $AWS_REGION

# Build, tag, and push
docker build -t my-lambda-ml .
docker tag my-lambda-ml:latest \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/my-lambda-ml:latest
docker push \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/my-lambda-ml:latest

# Create the Lambda function from the ECR image
aws lambda create-function \
    --function-name my-ml-inference \
    --package-type Image \
    --code ImageUri=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/my-lambda-ml:latest \
    --role arn:aws:iam::$AWS_ACCOUNT_ID:role/lambda-exec-role \
    --timeout 60 \
    --memory-size 3008  # ML inference benefits from more memory/CPU
```

Testing locally with the Lambda Runtime Interface Emulator (RIE):

```bash
# The AWS base image ships with the RIE - start the container and invoke it locally
docker run -p 9000:8080 my-lambda-ml:latest

# In another terminal, invoke the local function
curl -X POST http://localhost:9000/2015-03-31/functions/function/invocations \
    -H "Content-Type: application/json" \
    -d '{"body": "{\"inputs\": [1.0, 2.0, 3.0]}"}'
```

---

## How It Connects

Container images are stored in ECR before Lambda can use them. Understanding ECR's authentication model, lifecycle policies, and image scanning is prerequisite operational knowledge for teams deploying Lambda container images.

[[ecr|ECR (Elastic Container Registry)]] - covers ECR authentication, image tagging, lifecycle policies, and the push/pull workflow that feeds Lambda container deployments.

Container image deployments for Lambda are in direct comparison with ECS Fargate for containerised Python services. The choice between Lambda containers and ECS depends on maximum execution time, traffic pattern (spiky vs sustained), and the need for inter-process state.

[[ecs|ECS (Elastic Container Service)]] - describes ECS Fargate and EC2 launch types; the comparison with Lambda containers is a common architectural decision point.

---

## Common Misconceptions

Misconception 1: Using a container image eliminates cold starts.
Reality: Container images do not eliminate cold starts - they can extend them. Lambda still must provision an execution environment, pull and decompress image layers, start the Python runtime, and run module-level initialisation. A large image with a heavy module-level import (loading a PyTorch model) can produce a cold start of 10–30 seconds. Provisioned Concurrency is the mechanism that eliminates cold starts regardless of deployment format.

Misconception 2: Any Docker image can be used as a Lambda container image.
Reality: The image must implement the Lambda Runtime Interface - specifically, it must run an HTTP server on port 8080 that implements the Lambda Runtime API protocol. AWS Lambda base images handle this automatically. A generic nginx container or a Flask application server image does not implement this protocol and will not work as a Lambda container image without modification.

---

## Why It Matters in Practice

ML inference on Lambda was largely impractical before container image support because SciPy alone exceeds the ZIP package limit. Container images changed this. Teams can now deploy a fine-tuned model, its tokenizer, and its full dependency stack as a Lambda function and pay only for inference time - no idle GPU costs, no EC2 instance management. The deployment workflow (build, push to ECR, update function) integrates cleanly with CI/CD pipelines and is materially simpler than provisioning SageMaker endpoints for low-traffic inference use cases.

---

## What Breaks in Production

**Scenario 1: Using a mutable tag causes unexpected behaviour after image update**

```bash
# Mistake: Lambda function points to :latest tag
aws lambda update-function-code \
    --function-name my-ml-inference \
    --image-uri 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-lambda-ml:latest
# AWS resolves :latest to a specific digest at update time - the function pins to that digest
# Pushing a new :latest does NOT automatically update the function

# Fix: explicitly update the function after each push
# Or use image digests for deterministic deployments
IMAGE_DIGEST=$(aws ecr describe-images \
    --repository-name my-lambda-ml \
    --query "imageDetails[0].imageDigest" \
    --output text)
aws lambda update-function-code \
    --function-name my-ml-inference \
    --image-uri 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-lambda-ml@$IMAGE_DIGEST
```

**Scenario 2: Non-root user in Dockerfile breaks Lambda execution**

```dockerfile
# Mistake: following Docker security best practice of non-root user
USER nonroot
CMD ["main.handler"]
# Lambda runtime requires write access to /tmp - this may fail with permission errors

# Fix: Lambda base images already handle the user model correctly
# Avoid USER directives in Lambda-targeted Dockerfiles
```

---

## Interview Angle

Common question forms:
- "When would you use Lambda container images instead of ZIP deployments?"
- "What are the requirements for a Docker image to work as a Lambda function?"
- "How do container images affect Lambda cold start behaviour?"

Answer frame:
Lead with the size constraint - 250MB ZIP vs 10GB container - and when it matters (ML models, heavy data science stacks). Describe the Lambda Runtime Interface requirement and how AWS base images satisfy it automatically. Explain that container images do not eliminate cold starts and can extend them; Provisioned Concurrency is still required if cold starts are unacceptable. Walk through the ECR push workflow and local testing with the RIE.

---

## Related Notes

- [[lambda-overview|Lambda Overview]]
- [[lambda-cold-start|Lambda Cold Starts]]
- [[lambda-layers|Lambda Layers]]
- [[ecr|ECR (Elastic Container Registry)]]
- [[ecs|ECS (Elastic Container Service)]]
- [[docker-basics|Docker Basics]]
