---
title: 29 - Managing EC2 with Python (boto3)
description: The core boto3 patterns for EC2 management - describing, launching, stopping, and tagging instances, handling pagination, and using waiters for state transitions.
tags: [aws, cloud, layer-11, ec2, boto3, python]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Managing EC2 with Python (boto3)

> boto3's EC2 client gives Python code full programmatic control over the instance lifecycle - from launching and tagging instances to automating scheduled stop/start for cost savings and building self-healing infrastructure tooling.

---

## Quick Reference

**Core idea:**
- `describe_instances` returns a nested structure: `Reservations[*].Instances[*]` - always iterate both levels
- `run_instances` launches instances; `stop_instances` / `start_instances` / `terminate_instances` change their state
- Waiters (`instance_running`, `instance_stopped`, `instance_terminated`) poll for state transitions without manual sleep loops
- `describe_instances` with `Filters` is the standard way to find instances by tag, state, or VPC
- `create_image` creates an AMI snapshot from a running or stopped instance

**Tricky points:**
- `describe_instances` is paginated - for accounts with many instances, use a paginator
- The nested `Reservations → Instances` structure means you need two loops to reach individual instance objects
- `stop_instances` for a spot instance does not stop it - it terminates it; there is no stop for spot instances
- Instance state transitions are asynchronous - always wait using a waiter or polling before acting on the new state
- `create_tags` is a separate call - tags are not part of `run_instances` (use `TagSpecifications` instead to tag at launch)

---

## What It Is

Think of the boto3 EC2 client as a remote control for an infinite bank of virtual machines. Every operation you might perform in the AWS console - finding instances by tag, stopping overnight to save costs, launching identical copies for load testing, taking a snapshot for deployment - is available as a function call in Python. This programmability is what enables infrastructure automation: cost-saving scripts that stop dev instances at 7pm, self-healing health monitors that replace unhealthy instances, and deployment pipelines that launch new instances, wait for them to pass health checks, and then deregister the old ones from the load balancer.

The EC2 API is built around the concept of resource IDs. Every resource has an ID: instances have `i-*`, security groups have `sg-*`, AMIs have `ami-*`, snapshots have `snap-*`. Almost all API calls reference resources by these IDs. The exception is the filter system, which lets you find resources by their attributes (tags, state, VPC, instance type) without knowing the ID in advance.

The response structure of `describe_instances` is the most commonly confusing aspect of the EC2 API. When you launch instances, AWS groups them into "reservations" - a historical concept that groups instances launched together in a single `run_instances` call. Each reservation contains one or more instances. So `describe_instances` always returns `Reservations`, each with an `Instances` list. For a single instance, the structure is `response["Reservations"][0]["Instances"][0]`. For all instances, you must iterate over both the reservations list and the instances list within each reservation.

---

## How It Actually Works

boto3 communicates with the EC2 API endpoint in the specified region. The default region is taken from the `AWS_DEFAULT_REGION` environment variable or the `~/.aws/config` file. For multi-region operations, you create separate client objects per region. All AWS credentials come from the standard credential chain - environment variables, config file, or instance metadata on EC2.

Waiters are a critical boto3 feature for EC2. Because state transitions (instance starting, stopping, terminating) are asynchronous, calling `stop_instances` and then immediately calling `describe_instances` will likely still show `running` state. Waiters abstract the polling loop - they call `describe_instances` every 15 seconds (configurable) until the desired state is reached, then return. The built-in EC2 waiters are `instance_exists`, `instance_running`, `instance_stopped`, `instance_terminated`, `instance_status_ok`, `system_status_ok`.

```bash
# Describe instances filtered by tag
aws ec2 describe-instances \
    --filters "Name=tag:Environment,Values=production" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[*].[InstanceId,InstanceType,PublicIpAddress]" \
    --output table

# Stop instances by tag (all production instances named 'dev-server')
aws ec2 stop-instances \
    --instance-ids $(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=dev-server" \
                  "Name=instance-state-name,Values=running" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text)

# Create an AMI from an instance
aws ec2 create-image \
    --instance-id i-0123456789abcdef0 \
    --name "my-app-v2.1-$(date +%Y%m%d)" \
    --no-reboot
```

```python
import boto3
from typing import Generator

ec2 = boto3.client("ec2", region_name="eu-west-1")

# --- Describing instances ---

def get_instances(filters: list[dict] | None = None) -> Generator[dict, None, None]:
    """Yield all instances matching the given filters, handling pagination."""
    paginator = ec2.get_paginator("describe_instances")
    params = {}
    if filters:
        params["Filters"] = filters
    for page in paginator.paginate(**params):
        for reservation in page["Reservations"]:
            yield from reservation["Instances"]

# Find all running instances tagged Environment=production
for instance in get_instances([
    {"Name": "instance-state-name", "Values": ["running"]},
    {"Name": "tag:Environment", "Values": ["production"]},
]):
    name = next(
        (tag["Value"] for tag in instance.get("Tags", []) if tag["Key"] == "Name"),
        "unnamed"
    )
    print(f"{instance['InstanceId']} {instance['InstanceType']} "
          f"{instance.get('PublicIpAddress', 'no-ip')} {name}")

# --- State transitions ---

def stop_instances(instance_ids: list[str]) -> None:
    ec2.stop_instances(InstanceIds=instance_ids)
    waiter = ec2.get_waiter("instance_stopped")
    waiter.wait(InstanceIds=instance_ids)
    print(f"Stopped: {instance_ids}")

def start_instances(instance_ids: list[str]) -> None:
    ec2.start_instances(InstanceIds=instance_ids)
    waiter = ec2.get_waiter("instance_running")
    waiter.wait(InstanceIds=instance_ids)
    # Wait for OS to fully boot (status checks pass)
    waiter2 = ec2.get_waiter("instance_status_ok")
    waiter2.wait(InstanceIds=instance_ids)
    print(f"Started and ready: {instance_ids}")

def terminate_instances(instance_ids: list[str]) -> None:
    ec2.terminate_instances(InstanceIds=instance_ids)
    waiter = ec2.get_waiter("instance_terminated")
    waiter.wait(InstanceIds=instance_ids)
    print(f"Terminated: {instance_ids}")

# --- Tagging ---

# Add or update tags on an instance
ec2.create_tags(
    Resources=["i-0123456789abcdef0"],
    Tags=[
        {"Key": "DeployedAt", "Value": "2026-05-18T12:00:00Z"},
        {"Key": "Version", "Value": "2.1.0"},
    ],
)

# --- AMI creation (snapshot for deployment) ---

def create_ami_from_instance(instance_id: str, name: str) -> str:
    response = ec2.create_image(
        InstanceId=instance_id,
        Name=name,
        NoReboot=True,  # do not reboot the instance before snapshotting
        Description=f"AMI created from {instance_id} for deployment",
        TagSpecifications=[{
            "ResourceType": "image",
            "Tags": [
                {"Key": "Name", "Value": name},
                {"Key": "SourceInstance", "Value": instance_id},
            ],
        }],
    )
    ami_id = response["ImageId"]
    # Wait for the AMI to become available
    waiter = ec2.get_waiter("image_available")
    waiter.wait(ImageIds=[ami_id])
    print(f"AMI ready: {ami_id}")
    return ami_id

# --- Scheduled stop/start for cost savings (Lambda + EventBridge) ---

def lambda_handler(event, context):
    """Lambda handler triggered by EventBridge on a schedule.
    Stops all instances tagged AutoStop=true at 7pm, starts them at 9am.
    """
    import datetime
    action = event.get("action")  # "stop" or "start"

    target_instances = list(get_instances([
        {"Name": "tag:AutoStop", "Values": ["true"]},
        {"Name": "instance-state-name",
         "Values": ["running"] if action == "stop" else ["stopped"]},
    ]))
    instance_ids = [i["InstanceId"] for i in target_instances]

    if not instance_ids:
        print(f"No instances to {action}")
        return

    if action == "stop":
        ec2.stop_instances(InstanceIds=instance_ids)
        print(f"Stopping {len(instance_ids)} instances: {instance_ids}")
    elif action == "start":
        ec2.start_instances(InstanceIds=instance_ids)
        print(f"Starting {len(instance_ids)} instances: {instance_ids}")

    return {"action": action, "instances": instance_ids}

# --- Get public IP of an existing instance ---

def get_public_ip(instance_id: str) -> str | None:
    response = ec2.describe_instances(InstanceIds=[instance_id])
    return response["Reservations"][0]["Instances"][0].get("PublicIpAddress")
```

---

## How It Connects

EC2 instance management with boto3 is the programmatic layer on top of the EC2 concepts described in the overview and launch notes. Understanding the instance lifecycle (pending / running / stopping / stopped / terminated) and the nested response structure is the prerequisite for writing reliable automation.

[[ec2-launch|Launching EC2 Instances]] - `run_instances` is the most complex EC2 call; the launch note covers the full parameter set including AMI selection, instance profile, and user data.

For automation that modifies instance state on a schedule (stopping dev instances at night, scaling based on custom metrics), EventBridge triggers Lambda functions containing boto3 EC2 calls. The Lambda execution role must have EC2 permissions.

[[iam-roles|IAM Roles]] - Lambda functions and EC2 automation scripts need IAM roles with specific EC2 permissions (`ec2:DescribeInstances`, `ec2:StopInstances`, etc.); understanding role construction is necessary for secure automation.

---

## Common Misconceptions

Misconception 1: The response from `describe_instances` is a flat list of instance objects.
Reality: The response has two levels of nesting. The top-level key is `Reservations` - a list of reservation objects. Each reservation has an `Instances` key containing a list of instance objects. A single `describe_instances` call for one instance ID returns `response["Reservations"][0]["Instances"][0]` - you must traverse both levels. Using `response["Instances"]` directly will raise a `KeyError`.

Misconception 2: Calling `stop_instances` and immediately reading the instance state will show `stopped`.
Reality: `stop_instances` is asynchronous - it submits the stop request and returns immediately, while the actual shutdown happens in the background. The instance state after the call will be `stopping`, not `stopped`. Always use the `instance_stopped` waiter before performing any operation that depends on the instance being fully stopped.

---

## Why It Matters in Practice

Programmatic EC2 management unlocks a range of operational capabilities that are impractical with manual console operations. Automated instance scheduling (stop at night, start in the morning) can cut EC2 costs by 60% for development environments. Automated AMI creation before each deployment creates a rollback point. Automated health monitoring that detects unresponsive instances and replaces them implements self-healing without manual intervention.

The filter-based `describe_instances` pattern is particularly powerful for large environments. Rather than maintaining lists of instance IDs, you tag instances with metadata (`Environment=production`, `Role=web-server`, `AutoStop=true`) and query by tag. This means automation scripts work correctly for fleets of any size without modification.

---

## What Breaks in Production

**Forgetting the double loop over Reservations and Instances, causing only the first reservation's instances to be processed.**

```python
# Bad - only processes instances from the first reservation
response = ec2.describe_instances()
for instance in response["Reservations"][0]["Instances"]:  # wrong: only first reservation
    print(instance["InstanceId"])

# Good - processes all instances across all reservations
for reservation in response["Reservations"]:
    for instance in reservation["Instances"]:
        print(instance["InstanceId"])
```

**Not using a paginator for large accounts, silently missing instances beyond the first page.** `describe_instances` returns at most 1000 instances per call.

```python
# Bad - misses instances beyond the first 1000
response = ec2.describe_instances(Filters=[...])
instances = [i for r in response["Reservations"] for i in r["Instances"]]

# Good - paginator handles continuation automatically
paginator = ec2.get_paginator("describe_instances")
instances = [
    i
    for page in paginator.paginate(Filters=[...])
    for r in page["Reservations"]
    for i in r["Instances"]
]
```

---

## Interview Angle

Common question forms:
- "How do you find all running EC2 instances with a specific tag using boto3?"
- "Write a script that stops all EC2 instances tagged with `AutoStop=true`."
- "What is the response structure of `describe_instances` and why does it have nested loops?"

Answer frame:
For tagged instances: `describe_instances` with `Filters` for tag name/value and instance state; paginator for large fleets; double loop over Reservations and Instances. For stop script: filter, extract instance IDs, call `stop_instances`, use `instance_stopped` waiter. For nested structure: historical Reservation concept groups instances from a single `run_instances` call; always need two levels of iteration.

---

## Related Notes

- [[ec2-overview|EC2 Overview]]
- [[ec2-launch|Launching EC2 Instances]]
- [[ec2-auto-scaling|EC2 Auto Scaling Groups]]
- [[boto3-basics|boto3 Basics]]
- [[iam-roles|IAM Roles]]
