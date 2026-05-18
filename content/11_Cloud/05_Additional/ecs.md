---
title: ECS (Elastic Container Service)
description: ECS is AWS's managed container orchestration service — it runs Docker containers at scale without Kubernetes complexity, using Fargate (serverless compute) or EC2 (managed instances) as the backing infrastructure.
tags: [aws, cloud, layer-11, ecs, containers, fargate]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# ECS (Elastic Container Service)

> ECS runs your Docker containers in production without requiring you to manage Kubernetes — Fargate removes even the EC2 instances, leaving you to manage only the container definition and service configuration.

---

## Quick Reference

**Core idea:**
- Two launch types: Fargate (serverless — AWS provisions compute per task) and EC2 (you manage EC2 instances in the cluster)
- Core objects: Cluster → Service → Task Definition → Task (running container)
- Task definition: specifies image (ECR URI), CPU/memory, environment variables, ports, log configuration
- Service: maintains N running tasks, handles rolling deploys, integrates with ALB for load balancing
- Fargate billing: per vCPU-second and per GB-second of task duration
- ECS vs EKS vs Lambda: ECS for containerised services without Kubernetes; EKS for teams that need Kubernetes; Lambda for short event-driven tasks

**Tricky points:**
- Task definition revisions are immutable — creating a new revision is required for any change; services are updated to point to the new revision
- Fargate requires tasks to be in a VPC with a subnet that can reach ECR (public subnet or ECR VPC endpoint)
- The task execution role (for pulling images and writing logs) is separate from the task role (for your application's AWS API calls)
- ECS service rolling deployment: by default, ECS deploys new tasks before stopping old ones (`minimumHealthyPercent` and `maximumPercent`)
- Container environment variables in task definitions are plaintext — use Secrets Manager or SSM Parameter Store references for sensitive values

---

## What It Is

ECS is the general contractor who builds and manages a fleet of identical apartments (containers) for you. You give the contractor the blueprint (task definition): what the unit looks like (the Docker image), how many rooms it needs (CPU and memory), what utilities it requires (environment variables and port mappings), and how to track usage (log configuration). The contractor builds and runs as many units as you specify, replaces any that break down, and connects them to the building's main entrance (an Application Load Balancer). With Fargate, the contractor also owns the land the building sits on — you do not see or manage the physical servers underneath.

The comparison with Lambda is important because Python developers regularly face the choice between the two. Lambda is purpose-built for short-lived, event-driven tasks: process a message, respond to an HTTP request, react to a file upload. ECS is purpose-built for long-running services: an API server that must handle steady traffic, a background worker that runs continuously, a data pipeline that processes streaming data for hours. Lambda has a 15-minute execution cap; ECS tasks run as long as the container stays alive. Lambda charges per invocation and per GB-second of execution; ECS charges per vCPU-second and per GB-second of task duration while the task is running, regardless of utilisation. For a service that runs 24 hours a day at consistent load, ECS Fargate is typically cheaper than Lambda. For a webhook handler that fires 100 times per day for 200ms each, Lambda is dramatically cheaper.

The Kubernetes comparison is equally important. Amazon EKS (Elastic Kubernetes Service) runs managed Kubernetes clusters. ECS is not Kubernetes — it is a simpler, AWS-proprietary orchestration system. EKS gives you the full Kubernetes API, ecosystem, and portability at the cost of Kubernetes operational complexity. ECS gives you straightforward container orchestration with a smaller operational surface area but no portability outside AWS. Teams with Kubernetes expertise and multi-cloud requirements choose EKS. Teams that want to run containers on AWS with minimal orchestration overhead choose ECS.

---

## How It Actually Works

The deployment workflow for a Python service on ECS Fargate involves creating a task definition (the container blueprint), creating a service that runs that task definition on a cluster, and optionally wiring the service to an Application Load Balancer for HTTP traffic. Updates to the application are deployed by registering a new task definition revision and updating the service to use it — ECS handles the rolling replacement.

```python
import boto3
import json

ecs = boto3.client("ecs", region_name="us-east-1")

AWS_ACCOUNT_ID = "123456789012"
REGION = "us-east-1"
ECR_URI = f"{AWS_ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com/my-python-service"


# --- Register a task definition ---
def register_task_definition(image_tag: str) -> str:
    response = ecs.register_task_definition(
        family="my-python-service",
        networkMode="awsvpc",          # required for Fargate
        requiresCompatibilities=["FARGATE"],
        cpu="512",                     # 0.5 vCPU (256, 512, 1024, 2048, 4096)
        memory="1024",                 # 1GB
        executionRoleArn=f"arn:aws:iam::{AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
        taskRoleArn=f"arn:aws:iam::{AWS_ACCOUNT_ID}:role/my-service-task-role",
        containerDefinitions=[
            {
                "name": "my-python-service",
                "image": f"{ECR_URI}:{image_tag}",
                "essential": True,
                "portMappings": [{"containerPort": 8000, "protocol": "tcp"}],
                "environment": [
                    {"name": "STAGE", "value": "production"},
                    {"name": "LOG_LEVEL", "value": "WARNING"},
                ],
                # Reference secrets from Secrets Manager or SSM Parameter Store
                "secrets": [
                    {
                        "name": "DATABASE_URL",
                        "valueFrom": f"arn:aws:secretsmanager:{REGION}:{AWS_ACCOUNT_ID}:secret:prod/db-url",
                    },
                ],
                "logConfiguration": {
                    "logDriver": "awslogs",
                    "options": {
                        "awslogs-group": "/ecs/my-python-service",
                        "awslogs-region": REGION,
                        "awslogs-stream-prefix": "ecs",
                    },
                },
                "healthCheck": {
                    "command": ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"],
                    "interval": 30,
                    "timeout": 5,
                    "retries": 3,
                    "startPeriod": 10,
                },
            }
        ],
    )
    revision = response["taskDefinition"]["revision"]
    return f"my-python-service:{revision}"


# --- Deploy a new image version ---
def deploy_new_version(image_tag: str):
    # Register the new task definition revision
    task_def_revision = register_task_definition(image_tag)
    print(f"Registered task definition: {task_def_revision}")

    # Update the service to use the new revision (triggers rolling deployment)
    ecs.update_service(
        cluster="production",
        service="my-python-service",
        taskDefinition=task_def_revision,
        forceNewDeployment=True,
    )
    print(f"Service updated to {task_def_revision} — rolling deployment started")


# --- Check deployment status ---
def get_service_status() -> dict:
    response = ecs.describe_services(
        cluster="production",
        services=["my-python-service"],
    )
    service = response["services"][0]
    return {
        "desired": service["desiredCount"],
        "running": service["runningCount"],
        "pending": service["pendingCount"],
        "deployments": [
            {
                "status": d["status"],
                "task_def": d["taskDefinition"].split("/")[-1],
                "running": d["runningCount"],
                "desired": d["desiredCount"],
            }
            for d in service["deployments"]
        ],
    }
```

Creating the cluster and service via CLI:

```bash
# Create a cluster
aws ecs create-cluster --cluster-name production

# Create the service (assumes task definition and ALB target group already exist)
aws ecs create-service \
    --cluster production \
    --service-name my-python-service \
    --task-definition my-python-service:1 \
    --desired-count 2 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[subnet-abc,subnet-def],securityGroups=[sg-service],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/my-service/abc,containerName=my-python-service,containerPort=8000" \
    --deployment-configuration "minimumHealthyPercent=50,maximumPercent=200"
```

---

## How It Connects

ECS pulls container images from ECR at task launch. Understanding the ECR push workflow, authentication model, and lifecycle policies is prerequisite knowledge for ECS operations.

[[ecr|ECR (Elastic Container Registry)]] — the ECR repository stores the Docker images that ECS task definitions reference; the two services are used together in every ECS container deployment workflow.

The task execution role and the task role are two separate IAM roles that ECS Fargate uses. The execution role is for ECS infrastructure operations (pull image from ECR, write logs to CloudWatch); the task role is for your application's AWS API calls (read from S3, write to DynamoDB).

[[iam-roles|IAM Roles]] — the task execution role vs task role distinction is an instance of the IAM roles model; the separation of infrastructure permissions from application permissions is the same principle as Lambda's execution role.

---

## Common Misconceptions

Misconception 1: ECS Fargate is always more expensive than running on EC2.
Reality: Fargate eliminates EC2 instance management overhead and bills only for the CPU and memory consumed by running tasks. For workloads with variable or unpredictable task counts, Fargate often costs less than maintaining a fleet of EC2 instances sized for peak load. For workloads with sustained high concurrency, EC2-backed ECS with Reserved Instances is typically cheaper than Fargate, because Reserved Instance discounts (up to 72%) are unavailable on Fargate.

Misconception 2: Updating the Docker image with the same tag automatically redeploys the ECS service.
Reality: ECS services do not monitor ECR for image changes. The service continues running the exact image digest that was resolved when the current task definition was registered. To deploy a new image, you must register a new task definition revision (which resolves the tag to the current digest) and then update the service to use the new revision. This is by design — it prevents unexpected deployments when the underlying image is updated.

---

## Why It Matters in Practice

ECS Fargate is the default choice for Python services that need to run continuously, handle sustained traffic, or exceed Lambda's 15-minute execution limit. A FastAPI application, a background Celery worker, or a long-running data processing pipeline are all natural fits for ECS Fargate. The task definition model — image, CPU, memory, environment variables, secrets, health check — maps cleanly to how Python services are configured in other environments, making it approachable for developers who are already comfortable with Docker.

---

## What Breaks in Production

**Scenario 1: Task fails to start because execution role lacks ECR pull permission**

```bash
# Mistake: creating a task definition with a custom execution role that lacks ECR permissions
# ECS stops the task with "CannotPullContainerError"

# Fix: attach the AWS-managed policy to the execution role
aws iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
# This policy includes ecr:GetDownloadUrlForLayer, ecr:BatchGetImage, logs:CreateLogStream, etc.
```

**Scenario 2: Application cannot access AWS services because task role is not set**

```python
# Mistake: the task definition has an executionRoleArn but no taskRoleArn
# The container runs, but boto3 calls to S3 or DynamoDB fail with NoCredentialsError

# Fix: set taskRoleArn in the task definition to a role with the needed permissions
# The executionRoleArn is for ECS infrastructure; taskRoleArn is for your application code

# In Python code inside the container — this works when taskRoleArn is set correctly:
import boto3
s3 = boto3.client("s3")  # credentials come from the task IAM role automatically
response = s3.list_objects_v2(Bucket="my-data-bucket")
```

---

## Interview Angle

Common question forms:
- "When would you choose ECS over Lambda for a Python service?"
- "What is the difference between the task execution role and the task role in ECS?"
- "How do rolling deployments work in ECS?"

Answer frame:
Lead with the runtime duration constraint (Lambda 15-minute cap vs ECS long-running) and the traffic pattern distinction (spiky/event-driven → Lambda; sustained/continuous → ECS). Clearly separate task execution role (ECS infrastructure permissions: pull image, write logs) from task role (application permissions: S3, DynamoDB). Describe rolling deployments: new task definition revision → service update → ECS launches new tasks, waits for health check, terminates old tasks.

---

## Related Notes

- [[ecr|ECR (Elastic Container Registry)]]
- [[lambda-overview|Lambda Overview]]
- [[lambda-container|Lambda with Container Images]]
- [[iam-roles|IAM Roles]]
- [[cloudwatch|CloudWatch]]
- [[docker-basics|Docker Basics]]
