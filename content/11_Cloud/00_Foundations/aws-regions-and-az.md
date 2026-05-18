---
title: 02 - AWS Regions and Availability Zones
description: AWS infrastructure is divided into Regions (geographic areas) and Availability Zones (isolated data centres within a region), and deploying across AZs is the primary mechanism for high availability.
tags: [aws, cloud, layer-11, regions, availability-zones]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# AWS Regions and Availability Zones

> AWS organises its global infrastructure into Regions and Availability Zones — understanding this model is the prerequisite for designing systems that remain available when hardware fails.

---

## Quick Reference

**Core idea:**
- A Region is a geographic area (e.g., `us-east-1` in Northern Virginia, `eu-west-1` in Ireland) — currently 30+ regions globally
- Each Region contains 2–6 Availability Zones (AZs), each a physically separate data centre with independent power and networking
- AZs within a Region are connected by low-latency (<2 ms), high-bandwidth private fibre links
- Most AWS services are regional — a Lambda function or RDS instance in `us-east-1` is completely separate from one in `eu-west-1`
- Global services (IAM, Route 53, CloudFront, WAF) are not tied to any region
- Resource ARNs (Amazon Resource Names) embed the region: `arn:aws:s3:::my-bucket` (S3 is global) vs `arn:aws:lambda:us-east-1:123456789:function:my-func`

**Tricky points:**
- S3 bucket names are globally unique but buckets exist in a specific region — requests are routed to that region even though the namespace is global
- An EC2 instance in `us-east-1a` cannot directly reference a subnet in `us-east-1b` — resources reference AZ-specific constructs
- `us-east-1` is the oldest region and the first to receive new services — building everything there creates a dependency on a single region for new feature availability
- AZ names (`us-east-1a`) are not consistent across accounts — AWS shuffles the mapping to distribute load, so your `us-east-1a` may map to a different physical AZ than another account's `us-east-1a`

---

## What It Is

Think of AWS Regions as cities around the world — London, New York, Tokyo, Sydney. Each city operates independently: local laws apply, local businesses serve local customers, and a problem in Tokyo does not shut down London. AWS Regions work the same way: data in `eu-west-1` stays in Europe unless you explicitly copy it elsewhere, latency to European users is low, and an outage affecting `us-east-1` does not affect `eu-west-1`. Choosing a Region is like choosing which city to open your business in — it affects who you can serve efficiently and which regulations apply.

Within each city, imagine that critical infrastructure — power, water, the internet exchange — is distributed across several distinct districts. If a transformer fire knocks out one district's power grid, the other districts continue operating. These districts are Availability Zones. Each AZ is a separate physical data centre (or cluster of data centres) with its own power supply, cooling systems, and network connections. They are close enough to communicate in microseconds but isolated enough that a flood, fire, or power failure in one AZ does not cascade into another. When you deploy a web application across three AZs and one fails, two-thirds of your capacity continues serving traffic.

For a Python developer, this model has direct consequences for how you write and deploy code. A database in a single AZ goes offline during an AZ outage — an RDS instance with Multi-AZ enabled has a standby in a second AZ and fails over automatically. A Python web application running on a single EC2 instance is unavailable if that instance's AZ fails — running instances in two AZs behind a load balancer keeps the application up. The Region and AZ model is not an abstract infrastructure concept; it directly determines what `try/except` blocks you need and what "high availability" actually costs.

---

## How It Actually Works

When you create an AWS resource, you choose a Region either explicitly or via your CLI/SDK configuration. The resource is then provisioned within that Region's infrastructure. For resources that are AZ-specific (EC2 instances, EBS volumes, RDS instances), you also specify or accept a default AZ. AWS distributes resources across AZs automatically when you use managed services like Auto Scaling Groups or Multi-AZ RDS — otherwise you must explicitly place resources across AZs yourself.

The AZ identifier scheme is important for production deployments. The physical AZ IDs (`use1-az1`, `use1-az2`, `use1-az3`) are stable across accounts, but the human-readable names (`us-east-1a`, `us-east-1b`) are shuffled per account to prevent all customers from concentrating in the same physical facility. When coordinating across accounts (e.g., in a multi-account organisation), use AZ IDs rather than names to ensure you are referring to the same physical location.

```bash
# List all available regions
aws ec2 describe-regions --output table

# List Availability Zones in a specific region
aws ec2 describe-availability-zones \
  --region us-east-1 \
  --output table

# Get the stable AZ IDs (not just names) to identify physical locations
aws ec2 describe-availability-zones \
  --region us-east-1 \
  --query 'AvailabilityZones[*].{Name:ZoneName,ID:ZoneId,State:State}' \
  --output table

# Check which services are available in a region
aws ssm get-parameters-by-path \
  --path /aws/service/global-infrastructure/regions/us-east-1/services \
  --query 'Parameters[*].Name'
```

```python
import boto3

# List all regions
ec2 = boto3.client('ec2', region_name='us-east-1')
regions = ec2.describe_regions()
for r in regions['Regions']:
    print(r['RegionName'], r['OptInStatus'])

# List AZs in the current region with their stable IDs
response = ec2.describe_availability_zones(
    Filters=[{'Name': 'state', 'Values': ['available']}]
)
for az in response['AvailabilityZones']:
    print(f"{az['ZoneName']} -> {az['ZoneId']} ({az['State']})")

# Create clients for multiple regions
regions_to_check = ['us-east-1', 'eu-west-1', 'ap-southeast-1']
clients = {r: boto3.client('ec2', region_name=r) for r in regions_to_check}
```

---

## How It Connects

The AWS overview establishes what services exist; the Region and AZ model establishes where they live and how to design for their failure. Every service interaction happens within a regional context.

[[aws-overview|AWS Overview]] — the service catalogue and mental model that this infrastructure model supports.

EC2 instances are AZ-specific resources — understanding AZ placement is required before launching instances for production use.

[[ec2-overview|EC2 Overview]] — compute resources that are placed in specific AZs and require AZ-aware deployment for high availability.

IAM is one of the few truly global services — IAM users, roles, and policies apply across all Regions in your account without any regional configuration.

[[iam-overview|IAM Overview]] — the one major AWS service that transcends the regional model.

---

## Common Misconceptions

Misconception 1: "Deploying to multiple AZs means I have a backup in case something goes wrong."
Reality: Multiple AZs is not a backup strategy — it is a high-availability strategy. If you accidentally delete your database, all AZs reflect that deletion immediately. Multi-AZ protects against infrastructure failure (hardware, power, network within one AZ), not against application errors, data corruption, or accidental deletion. Backups (RDS automated snapshots, S3 versioning) address data loss scenarios — AZ distribution addresses infrastructure failure scenarios.

Misconception 2: "All AWS regions have the same services."
Reality: AWS releases services in waves, typically starting with us-east-1. Some newer services take months or years to reach all regions. Some regions (GovCloud, China) are isolated and require separate accounts. If your architecture depends on a specific service, verify it is available in your target region before committing to that region.

Misconception 3: "Low latency between AZs means I can treat them as the same location."
Reality: While AZ-to-AZ latency is low (under 2 ms), synchronous cross-AZ calls add latency to every request in a tightly coupled architecture. Cross-AZ data transfer also incurs costs — approximately $0.01 per GB in most regions. For high-throughput systems, placing tightly coupled components in the same AZ while keeping separate components spread across AZs is a deliberate cost and latency optimisation.

---

## Why It Matters in Practice

Production systems fail. Hardware breaks, data centres lose power, fibre cables get cut. The Region and AZ model is AWS's answer to these realities — but it only helps if you deliberately design around it. A Python web application deployed as a single EC2 instance in a single AZ has the same availability characteristics as a server under a desk: when the hardware has a problem, the application goes down. Adding a second AZ doubles the infrastructure that must fail simultaneously before the application becomes unavailable.

Region selection also has compliance consequences. GDPR requires that personal data of EU residents be processed in ways that comply with EU law, and for many interpretations, storing that data in an AWS region outside the EU creates legal exposure. Healthcare applications in the United States may have HIPAA requirements that influence region and service selection. These are not concerns a Python developer can defer to an infrastructure team — they affect which boto3 client region you configure and which bucket you write to in your application code.

---

## What Breaks in Production

**Scenario 1: Application hardcodes a single AZ subnet, preventing multi-AZ deployment.**

```bash
# Wrong: hardcoding a single subnet (AZ-specific)
aws ec2 run-instances \
  --image-id ami-12345678 \
  --subnet-id subnet-az1only  # tied to one AZ

# Right: use Auto Scaling Group across multiple subnets
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name my-asg \
  --vpc-zone-identifier "subnet-az1,subnet-az2,subnet-az3" \
  --min-size 2 --max-size 10 --desired-capacity 3
```

**Scenario 2: RDS deployed single-AZ goes offline during AZ maintenance.**

```bash
# Check if your RDS instance is Multi-AZ
aws rds describe-db-instances \
  --query 'DBInstances[*].{ID:DBInstanceIdentifier,MultiAZ:MultiAZ}' \
  --output table

# Enable Multi-AZ on an existing instance (triggers failover window)
aws rds modify-db-instance \
  --db-instance-identifier my-db \
  --multi-az \
  --apply-immediately
```

**Scenario 3: Python code assumes a specific region without reading from environment, breaks in new deployment.**

```python
import boto3
import os

# Wrong: assumes us-east-1 even when deployed to eu-west-1
s3 = boto3.client('s3', region_name='us-east-1')

# Right: respect the environment's configured region
session = boto3.session.Session()
region = session.region_name or os.environ.get('AWS_DEFAULT_REGION', 'us-east-1')
s3 = boto3.client('s3', region_name=region)
print(f"Operating in region: {region}")
```

---

## Interview Angle

Common question forms:
- "How do you design for high availability on AWS?"
- "What is the difference between a Region and an Availability Zone?"
- "Why might you deploy to multiple regions?"

Answer frame:
Distinguish between AZ-level HA (single region, protects against hardware failure in one data centre) and region-level DR (multiple regions, protects against regional outages or data residency requirements). For most applications, multi-AZ within one region is the right starting point — use an ALB with EC2 Auto Scaling across AZs, RDS Multi-AZ, and Lambda (which is inherently multi-AZ). Multi-region adds significant operational complexity and should be reserved for applications with strict SLAs or data sovereignty requirements.

---

## Related Notes

- [[aws-overview|AWS Overview]]
- [[ec2-overview|EC2 Overview]]
- [[iam-overview|IAM Overview]]
- [[aws-pricing-model|AWS Pricing Model]]
