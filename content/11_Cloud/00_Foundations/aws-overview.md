---
title: 01 - AWS Overview
description: AWS is Amazon's cloud platform offering compute, storage, networking, and hundreds of other services on a pay-as-you-go model.
tags: [aws, cloud, layer-11, overview]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# AWS Overview

> AWS (Amazon Web Services) is the dominant cloud platform - understanding its service catalogue, service models, and shared responsibility model is the foundation for deploying any Python application to production.

---

## Quick Reference

**Core idea:**
- AWS is ~200+ managed services accessible via API, CLI, and SDK
- Three service models: IaaS (you manage OS and up), PaaS (you manage app and up), SaaS (you use it)
- AWS holds ~32% cloud market share - more tutorials, Stack Overflow answers, and tooling than any competitor
- Core Python-relevant services: EC2 (VMs), Lambda (serverless), S3 (object storage), RDS (managed databases), ECS (containers), SQS/SNS (messaging)
- Shared responsibility model: AWS secures the physical infrastructure; you secure your application, data, and access controls
- All AWS services are accessed through the same underlying REST API - the CLI and boto3 are wrappers around it

**Tricky points:**
- "Managed" does not mean "secure by default" - an S3 bucket created without proper policies is publicly readable until you configure it
- The free tier has both 12-month and always-free tiers; exceeding limits generates real charges
- Region selection affects which services are available, latency, data residency compliance, and pricing - it is not a cosmetic choice
- IAM is a global service; most other services are regional - a Lambda function in us-east-1 does not automatically exist in eu-west-1

---

## What It Is

Think of AWS as a city of specialized warehouses, each offering a different industrial service. One warehouse rents out raw floor space and forklifts - you bring your own staff and processes (IaaS). Another warehouse runs a complete fulfilment operation - you just drop off parcels and tell it where to send them (PaaS). A third warehouse manages everything from receiving to delivery - you only interact through a web portal to track your shipment (SaaS). Amazon built this city of warehouses starting in 2006 and now rents access to it globally. The rent is metered: you pay only for what you use, and you return the space when you are done.

Before cloud platforms existed, a startup that wanted to launch a web application needed to purchase physical servers, co-locate them in a data centre, negotiate bandwidth contracts, and wait weeks for hardware to arrive. AWS changed this to a software problem. You make an API call, and compute capacity appears within seconds. The same call can be made from a Python script, a CI/CD pipeline, or an infrastructure-as-code tool. The underlying physical hardware - power, cooling, networking, hardware failure replacement - is Amazon's problem entirely.

For a Python developer, the relevant mental model is not "which server should I buy" but "which managed service solves my problem." Running background jobs? SQS queues and Lambda functions replace a cron server. Storing user uploads? S3 replaces a file server. User authentication? Cognito replaces a self-hosted auth stack. The discipline is learning which service fits which problem, understanding how to configure it securely, and knowing how to interact with it from Python using boto3.

---

## How It Actually Works

Every AWS service exposes a REST API. When you call `boto3.client('s3').list_buckets()`, boto3 constructs a signed HTTP request using your credentials (via the SigV4 signing algorithm), sends it to `s3.amazonaws.com`, and deserialises the XML or JSON response into a Python dictionary. The AWS CLI does exactly the same thing. This means every action you can take in the AWS Console can be scripted - and should be, for repeatability.

AWS organises services into categories: compute (EC2, Lambda, ECS, Fargate), storage (S3, EBS, EFS, Glacier), databases (RDS, DynamoDB, ElastiCache), networking (VPC, Route 53, CloudFront, Direct Connect), messaging (SQS, SNS, EventBridge), security (IAM, KMS, Secrets Manager, WAF), and developer tools (CodeBuild, CodeDeploy, CodePipeline). Services within a category are often complementary - S3 stores objects, CloudFront distributes them globally, and S3 event notifications trigger Lambda when objects arrive. Building production systems means understanding these integrations.

```bash
# Verify your AWS CLI is configured and authenticated
aws sts get-caller-identity

# List all regions
aws ec2 describe-regions --output table

# List all services available in a region (via service endpoints)
aws ssm get-parameters-by-path --path /aws/service/global-infrastructure/regions/us-east-1/services --output table
```

```python
import boto3

# Check which identity boto3 is using
sts = boto3.client('sts')
identity = sts.get_caller_identity()
print(f"Account: {identity['Account']}")
print(f"ARN: {identity['Arn']}")

# List all S3 buckets - a simple first boto3 call
s3 = boto3.client('s3', region_name='us-east-1')
response = s3.list_buckets()
for bucket in response['Buckets']:
    print(bucket['Name'])
```

---

## How It Connects

Understanding the AWS service catalogue is only useful when you know how to interact with it. The CLI and boto3 are the two main interfaces for Python developers - everything else builds on them.

[[aws-cli|AWS CLI]] - the command-line interface used to script and automate AWS operations, configure credentials, and test API calls interactively.

[[boto3-basics|boto3 Basics]] - the official Python SDK; every service interaction from Python goes through boto3.

IAM controls access to every service listed here. Before any service call succeeds, AWS evaluates whether the calling identity has permission. Understanding IAM is not optional.

[[iam-overview|IAM Overview]] - the access control system that governs every API call in AWS.

The pricing model determines whether your architecture is viable at scale. Services that appear cheap at low volume can become significant costs at production scale.

[[aws-pricing-model|AWS Pricing Model]] - how AWS charges for services and what the common cost surprises are.

---

## Common Misconceptions

Misconception 1: "AWS manages the security of my application."
Reality: The shared responsibility model is explicit. AWS secures the physical infrastructure, hypervisor, and managed service internals. You are responsible for OS patching on EC2, IAM policies, S3 bucket permissions, encryption configuration, application code, and secrets management. "Managed" refers to operational management of the service, not security of your data or access controls.

Misconception 2: "I can pick any region - they are all the same."
Reality: Regions differ in service availability, pricing, network latency to your users, and legal data residency requirements. Some newer AWS services are only available in us-east-1 initially. Pricing for identical EC2 instance types can differ by 10–20% between regions. If your users are in Europe and your application is in us-east-1, every request travels across the Atlantic. GDPR and similar regulations may prohibit storing certain data outside specific regions.

Misconception 3: "The free tier means I will not be charged while learning."
Reality: The free tier has specific per-service limits. A t2.micro EC2 instance running 750 hours per month is free for 12 months - but if you forget to stop it and run two instances, you pay for one. Data egress from S3 beyond 1 GB per month incurs charges. Services not covered by the free tier (like many VPC features or certain data transfer paths) generate charges immediately. Set up billing alerts.

---

## Why It Matters in Practice

A Python developer who understands the AWS service catalogue can make architectural decisions early - before writing code - that determine whether a system can scale, remain available, and stay within budget. Choosing S3 for user uploads instead of local disk is not just about storage; it determines whether your application can run on multiple EC2 instances simultaneously, whether file access survives instance termination, and whether uploads can be served globally via CloudFront.

Without this foundation, developers tend to build on the wrong primitives. Storing session state on a single EC2 instance makes horizontal scaling impossible. Writing files to local disk on Lambda (which has an ephemeral filesystem) leads to silent data loss. Using the root account for API calls is a security incident waiting to happen. The service overview is the map - without it, every architectural decision is navigating blind.

---

## What Breaks in Production

**Scenario 1: Hardcoded region causes service calls to fail in a different environment.**

```python
# Wrong: hardcoded region breaks when deployed to a different region
s3 = boto3.client('s3', region_name='us-east-1')

# Right: read region from environment or instance metadata
import os
region = os.environ.get('AWS_DEFAULT_REGION', 'us-east-1')
s3 = boto3.client('s3', region_name=region)
```

**Scenario 2: No billing alerts set, free tier exceeded silently.**

```bash
# Create a billing alert via CLI
aws cloudwatch put-metric-alarm \
  --alarm-name "BillingAlert-10USD" \
  --alarm-description "Alert when estimated charges exceed $10" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:billing-alerts
```

**Scenario 3: Assuming a managed service handles all failure modes.**

```python
# Wrong: assuming S3 put_object always succeeds
s3.put_object(Bucket='my-bucket', Key='data.json', Body=b'{}')

# Right: handle throttling and transient failures
from botocore.exceptions import ClientError
import time

for attempt in range(3):
    try:
        s3.put_object(Bucket='my-bucket', Key='data.json', Body=b'{}')
        break
    except ClientError as e:
        if e.response['Error']['Code'] == 'SlowDown':
            time.sleep(2 ** attempt)
        else:
            raise
```

---

## Interview Angle

Common question forms:
- "Explain the shared responsibility model."
- "When would you choose Lambda over EC2?"
- "What are the key services for a Python web application on AWS?"

Answer frame:
Start with the shared responsibility model - AWS handles infrastructure, you handle application and data security. Then map service types to use cases: EC2 for persistent, stateful, or long-running workloads; Lambda for event-driven, short-duration tasks; S3 for object storage; RDS for relational databases; SQS/SNS for decoupled messaging. Demonstrate awareness that service selection has implications for scaling, cost, and operations - not just functionality.

---

## Related Notes

- [[aws-cli|AWS CLI]]
- [[boto3-basics|boto3 Basics]]
- [[iam-overview|IAM Overview]]
- [[aws-regions-and-az|AWS Regions and Availability Zones]]
- [[aws-pricing-model|AWS Pricing Model]]
