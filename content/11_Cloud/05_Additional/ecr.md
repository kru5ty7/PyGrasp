---
title: 48 - ECR (Elastic Container Registry)
description: ECR is AWS's managed Docker container registry — it stores, versions, and secures container images for deployment to Lambda, ECS, EKS, and EC2 within the same AWS account.
tags: [aws, cloud, layer-11, ecr, docker, containers]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# ECR (Elastic Container Registry)

> ECR is AWS's managed container image registry — you push your Docker images here, and ECS, Lambda, and EKS pull them with no cross-registry credential management when everything runs in the same account.

---

## Quick Reference

**Core idea:**
- Two registry types: private (authentication required, within your AWS account) and public (`public.ecr.aws` — share images publicly, AWS manages bandwidth)
- Push workflow: authenticate Docker with `aws ecr get-login-password`, tag image with ECR URI, `docker push`
- Image URI format: `<account_id>.dkr.ecr.<region>.amazonaws.com/<repo-name>:<tag>`
- Image scanning: automatic vulnerability scan on push (Basic scanning free; Enhanced scanning uses Inspector, billed)
- Lifecycle policies: automatically delete images matching rules (e.g. untagged images older than 7 days)
- ECR integrates natively with Lambda container images, ECS task definitions, and EKS pod specs

**Tricky points:**
- Authentication tokens from `aws ecr get-login-password` expire after 12 hours — refresh in CI/CD pipelines
- ECR private registries are region-specific — an image in `us-east-1` ECR cannot be referenced from `eu-west-1` ECS without replication or re-push
- Pulling images from ECR in a VPC with no internet gateway requires a VPC endpoint for ECR (`com.amazonaws.region.ecr.dkr` and `com.amazonaws.region.ecr.api`)
- Lambda container image deployments pin to the image digest at deploy time — pushing a new image with the same tag does not automatically update the function
- ECR stores layer data separately per repository — pushing the same layer (e.g. a Python base image) to two repositories stores it twice

---

## What It Is

ECR is a secure warehouse for your container images. When you build a Docker image, you are assembling a product on your local factory floor — it exists only on your machine. ECR is the warehouse where you ship finished products so that any deployment system in your AWS account can pick them up. The warehouse is managed: AWS handles the physical storage, the access control system (IAM authentication), and the security inspections (image scanning). You are responsible for deciding which products to store, how long to keep them (lifecycle policies), and who gets access.

The closest analogy to a general-purpose container registry is DockerHub, which many developers are familiar with from personal projects. ECR differs in two important ways. First, ECR is private by default — images are accessible only to principals authenticated and authorised within your AWS account. This eliminates the credential management complexity of pulling from a private DockerHub repository: when an ECS task or Lambda function in your account pulls from ECR, it authenticates using the IAM role of the task or function, not a stored Docker credential. Second, ECR is regional and integrated with the AWS network backbone, which means pull times within the same region are fast and there is no egress cost for pulling images within the same region.

The ECR public registry (`public.ecr.aws`) is a separate product for sharing images with the world, and it is also the home of AWS's own base images — including the Lambda Python runtime base images (`public.ecr.aws/lambda/python:3.12`) that the container image deployment note describes. Using AWS base images from the public ECR registry instead of DockerHub reduces pull latency in the Lambda execution environment and avoids DockerHub rate limits in CI/CD pipelines.

---

## How It Actually Works

The standard push workflow involves four commands: create the repository (once), authenticate Docker, tag the image, and push. The authentication step generates a time-limited password that is piped directly into `docker login` — no password storage required.

```bash
# Variables
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-1
REPO_NAME=my-python-app
IMAGE_TAG=1.2.3  # use semantic versions or git SHAs, not "latest", in production

# Step 1: Create the repository (only needed once)
aws ecr create-repository \
    --repository-name $REPO_NAME \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256

# Step 2: Authenticate Docker to ECR (token is valid for 12 hours)
aws ecr get-login-password --region $AWS_REGION \
    | docker login \
        --username AWS \
        --password-stdin \
        $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Step 3: Build, tag, and push
ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME

docker build -t $REPO_NAME:$IMAGE_TAG .
docker tag $REPO_NAME:$IMAGE_TAG $ECR_URI:$IMAGE_TAG
docker push $ECR_URI:$IMAGE_TAG

# Step 4: Update Lambda to use the new image
aws lambda update-function-code \
    --function-name my-python-function \
    --image-uri $ECR_URI:$IMAGE_TAG
```

Setting a lifecycle policy to automatically clean up untagged and old images:

```python
import boto3
import json

ecr = boto3.client("ecr", region_name="us-east-1")

lifecycle_policy = {
    "rules": [
        {
            "rulePriority": 1,
            "description": "Remove untagged images after 7 days",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 7,
            },
            "action": {"type": "expire"},
        },
        {
            "rulePriority": 2,
            "description": "Keep only the 10 most recent tagged images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["v"],  # only affect images tagged like v1.0.0
                "countType": "imageCountMoreThan",
                "countNumber": 10,
            },
            "action": {"type": "expire"},
        },
    ]
}

ecr.put_lifecycle_policy(
    repositoryName="my-python-app",
    lifecyclePolicyText=json.dumps(lifecycle_policy),
)

# List images in a repository with scan findings
response = ecr.describe_images(
    repositoryName="my-python-app",
    filter={"tagStatus": "TAGGED"},
)
for image in response["imageDetails"]:
    scan_summary = image.get("imageScanFindingsSummary", {})
    severity_counts = scan_summary.get("findingSeverityCounts", {})
    print(f"Tag: {image.get('imageTags', ['untagged'])}, "
          f"Critical: {severity_counts.get('CRITICAL', 0)}, "
          f"High: {severity_counts.get('HIGH', 0)}")
```

Cross-account access — allowing a different AWS account to pull from a private repository:

```bash
aws ecr set-repository-policy \
    --repository-name my-python-app \
    --policy-text '{
        "Version": "2012-10-17",
        "Statement": [{
            "Sid": "AllowCrossAccountPull",
            "Effect": "Allow",
            "Principal": {"AWS": "arn:aws:iam::987654321098:root"},
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability"
            ]
        }]
    }'
```

---

## How It Connects

ECR is the prerequisite storage layer for Lambda container image deployments. Every container-based Lambda function must have its image in ECR before the function can be created or updated.

[[lambda-container|Lambda with Container Images]] — the full Lambda container deployment workflow: building with AWS base images, pushing to ECR, and creating the Lambda function pointing to the ECR image URI.

ECR is also the image source for ECS task definitions. ECS Fargate tasks pull their container images from ECR at task launch time, making ECR authentication and image availability critical to ECS service health.

[[ecs|ECS (Elastic Container Service)]] — ECS task definitions reference ECR image URIs; understanding the ECR push workflow and lifecycle policies is foundational to ECS container deployment.

---

## Common Misconceptions

Misconception 1: Pushing a new Docker image with the `latest` tag automatically updates running Lambda functions or ECS services.
Reality: Neither Lambda nor ECS polls ECR for changes. Lambda functions pin to the image digest resolved at the time `update-function-code` or `create-function` was called — the `latest` tag resolves to a digest at that moment, and the function continues using that digest until you explicitly call `update-function-code` again. ECS services similarly run the image digest that was resolved when the task was last deployed. Using `:latest` in production creates confusion because you cannot tell from the running service what code version is deployed.

Misconception 2: ECR images are available across all AWS regions.
Reality: ECR repositories are regional. An image pushed to a repository in `us-east-1` is only accessible from services in `us-east-1` (or cross-region replication, if configured). Deploying the same image in multiple regions requires either replicating the repository with ECR replication rules or pushing the image to each region's ECR separately in your CI/CD pipeline.

---

## Why It Matters in Practice

ECR is the only viable image registry for production container deployments on AWS. It integrates with IAM for authentication (no stored credentials in CI/CD), with ECS and Lambda for seamless pulls, and with AWS Inspector for security scanning. Teams that use ECR lifecycle policies avoid the storage cost accumulation of keeping every build artifact indefinitely. Teams that use semantic version tags rather than `:latest` maintain deployment traceability — every running service can be traced back to an exact image digest, which resolves to an exact commit in source control.

---

## What Breaks in Production

**Scenario 1: Docker authentication token expires in CI/CD pipeline**

```bash
# Mistake: authenticate once at the start of a long pipeline and reuse the token
# Token expires after 12 hours — a long pipeline or retry may fail with "unauthorized"

# Fix: re-authenticate immediately before each push step
aws ecr get-login-password --region us-east-1 \
    | docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.us-east-1.amazonaws.com
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:1.2.3
```

**Scenario 2: ECS task fails to pull image in VPC without ECR VPC endpoint**

```bash
# Mistake: ECS Fargate task in a private subnet with no internet gateway and no ECR VPC endpoint
# Pull fails with "CannotPullContainerError: Error response from daemon"

# Fix: create VPC endpoints for ECR (both endpoints required)
aws ec2 create-vpc-endpoint \
    --vpc-id vpc-abc123 \
    --service-name com.amazonaws.us-east-1.ecr.dkr \
    --vpc-endpoint-type Interface \
    --subnet-ids subnet-abc subnet-def \
    --security-group-ids sg-ecr-endpoint

aws ec2 create-vpc-endpoint \
    --vpc-id vpc-abc123 \
    --service-name com.amazonaws.us-east-1.ecr.api \
    --vpc-endpoint-type Interface \
    --subnet-ids subnet-abc subnet-def \
    --security-group-ids sg-ecr-endpoint
```

---

## Interview Angle

Common question forms:
- "How do you push a Docker image to ECR and use it in Lambda?"
- "What is an ECR lifecycle policy and why would you use one?"
- "How does ECR authentication work, and how is it different from DockerHub?"

Answer frame:
Walk through the four-step push workflow (create repo, authenticate, tag, push). Explain IAM-based authentication via `get-login-password` as the key difference from DockerHub (no stored credentials). Describe lifecycle policies as automated image garbage collection. Mention the 12-hour token expiry and the image digest pinning behaviour.

---

## Related Notes

- [[lambda-container|Lambda with Container Images]]
- [[ecs|ECS (Elastic Container Service)]]
- [[iam-roles|IAM Roles]]
- [[docker-basics|Docker Basics]]
- [[dockerfile-python|Dockerfile for Python]]
