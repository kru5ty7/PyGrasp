---
title: EC2 Overview
description: EC2 (Elastic Compute Cloud) provides on-demand virtual machines on AWS — the foundation for running Python web applications, data pipelines, and any workload that needs full control over the OS and runtime environment.
tags: [aws, cloud, layer-11, ec2, compute]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# EC2 Overview

> EC2 is AWS's virtual machine service — every Python developer who deploys to AWS needs to understand how instances are launched, billed, and managed, even if they eventually move to higher-level services like ECS or Lambda.

---

## Quick Reference

**Core idea:**
- An EC2 instance is a virtual machine with a chosen OS (via AMI), CPU/RAM profile (instance type), storage, and networking
- Instances are billed per second (Linux) or per hour (Windows) while in the running state — stopped instances do not incur compute charges
- Stopping an instance preserves its EBS root volume (data survives); terminating destroys the root volume by default
- AMI (Amazon Machine Image) is the blueprint used to launch an instance — contains the OS, pre-installed software, and initial disk state
- The instance lifecycle: pending → running → stopping → stopped → shutting-down → terminated

**Tricky points:**
- A stopped instance still incurs charges for its attached EBS volume — only termination stops all persistent charges
- The public IP address changes when you stop and start an instance — use an Elastic IP for a persistent public address
- The root EBS volume is deleted on termination by default — additional volumes are not; check `DeleteOnTermination` for all attached volumes
- Instance metadata (including IAM credentials from the instance profile) is accessible from within the instance at `169.254.169.254`
- Burstable instance types (t series) earn and spend CPU credits — running at 100% CPU for extended periods on a t3.micro can exhaust credits and throttle the instance

---

## What It Is

Think of an EC2 instance as renting a computer from a data centre, except that the rental starts in 30 seconds, lasts for as long as you want, and you choose every hardware specification from a menu. You pick the operating system (Amazon Linux, Ubuntu, Windows), the amount of CPU and RAM (instance type), the amount and type of storage, and the network rules. AWS provides the physical machine, the hypervisor, the network, and the data centre — you provide everything above the hypervisor: the application code, the runtime, the configuration.

The key distinction from traditional hosting is elasticity. You do not buy a server and wait for it to arrive. You call the API (or click the console) and an instance is available within minutes. When you no longer need it, you terminate it. The cost stops. If your application suddenly needs ten times more capacity, you launch ten more instances in parallel. This elasticity is the core value proposition of cloud computing, and EC2 is the most fundamental expression of it in AWS.

The AMI (Amazon Machine Image) is the snapshot that defines the starting state of an instance. AWS provides a catalogue of official AMIs for Amazon Linux, Ubuntu, Windows Server, and others. You can also create your own AMIs from running instances — capturing your application's entire disk state as a reusable template. This is the foundation of immutable infrastructure: you build a configured instance, snapshot it as an AMI, and use that AMI to launch multiple identical instances. Any configuration drift or debugging is done in a new instance built from the same AMI, never in a running production instance.

---

## How It Actually Works

EC2 instances run on physical host machines in AWS data centres. The hypervisor (AWS uses a custom KVM-based hypervisor called Nitro) divides the physical host's resources among multiple instances. Each instance believes it has dedicated CPU and memory, though the underlying resources are shared. Nitro-based instances (which includes most modern instance types) offload networking and storage to dedicated hardware, improving both performance and isolation.

Instance storage comes in two types. EBS (Elastic Block Store) volumes are network-attached block devices — they persist independently of the instance lifecycle and can be detached and reattached. The root volume (where the OS lives) is an EBS volume by default, and its `DeleteOnTermination` attribute controls whether it is deleted when the instance terminates. Instance store volumes (available on certain instance types) are physically attached SSDs that provide extremely fast I/O but are ephemeral — their contents are lost when the instance stops or terminates.

```bash
# List running instances
aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[*].[InstanceId,InstanceType,PublicIpAddress,State.Name]" \
    --output table

# Stop an instance (data preserved, compute billing stops)
aws ec2 stop-instances --instance-ids i-0123456789abcdef0

# Start a previously stopped instance
aws ec2 start-instances --instance-ids i-0123456789abcdef0

# Terminate an instance (permanently destroys root EBS by default)
aws ec2 terminate-instances --instance-ids i-0123456789abcdef0

# Get instance lifecycle state
aws ec2 describe-instance-status \
    --instance-ids i-0123456789abcdef0 \
    --query "InstanceStatuses[0].InstanceState.Name"
```

```python
import boto3

ec2 = boto3.client("ec2")

# Describe all running instances
response = ec2.describe_instances(
    Filters=[{"Name": "instance-state-name", "Values": ["running"]}]
)
for reservation in response["Reservations"]:
    for instance in reservation["Instances"]:
        print(instance["InstanceId"], instance["InstanceType"],
              instance.get("PublicIpAddress", "no-public-ip"))

# Stop an instance
ec2.stop_instances(InstanceIds=["i-0123456789abcdef0"])

# Wait for the instance to reach the stopped state
waiter = ec2.get_waiter("instance_stopped")
waiter.wait(InstanceIds=["i-0123456789abcdef0"])
print("Instance is stopped")

# Terminate an instance
ec2.terminate_instances(InstanceIds=["i-0123456789abcdef0"])
```

---

## How It Connects

EC2 instances need IAM roles (attached as instance profiles) to make AWS API calls without embedding credentials in the instance. Every production EC2 instance should have an IAM role attached at launch that grants only the permissions the running application needs.

[[iam-instance-profile|IAM Instance Profile]] — the mechanism for attaching an IAM role to an EC2 instance so that Python code running on the instance can call AWS APIs without hardcoded credentials.

Understanding EC2 security groups is the prerequisite for any network access to the instance — SSH connections, HTTP traffic, and database connections all depend on security group rules.

[[ec2-security-groups|EC2 Security Groups]] — the virtual firewall that controls which ports and IP ranges can reach your EC2 instance.

---

## Common Misconceptions

Misconception 1: Stopping an instance stops all billing for that instance.
Reality: Stopping an instance stops compute billing (per second for CPU and RAM), but the attached EBS volumes continue to incur storage charges. A stopped instance with a 100GB EBS root volume still costs approximately $8-10 per month in storage. Only terminating the instance (which deletes the root EBS volume by default) stops all charges.

Misconception 2: The instance ID is stable — I can use it as a permanent identifier for a server.
Reality: An instance ID is permanent for the lifetime of that specific instance. But instances are terminated and replaced — especially in Auto Scaling Groups, spot fleet deployments, or after AMI upgrades. Systems that rely on a hardcoded instance ID break when the instance is replaced. Use tags, load balancer target groups, or service discovery instead of instance IDs for long-lived references.

---

## Why It Matters in Practice

EC2 is the lowest-level building block for running application code on AWS. Even developers who primarily use Lambda or ECS encounter EC2 when setting up build servers, running batch jobs, debugging network issues, or hosting databases. Understanding the instance lifecycle — particularly the difference between stopping and terminating, the EBS billing implications, and the AMI-based deployment model — prevents expensive mistakes and data loss.

EC2 is also the substrate for many higher-level AWS services. ECS clusters, EKS node groups, and EMR clusters all run on EC2 instances. Understanding EC2 fundamentals makes these managed services far less opaque.

---

## What Breaks in Production

**Terminating an instance assuming data is preserved because it was on "the instance disk."** The root EBS volume is deleted on termination by default. Any data written to the root volume that is not backed up to S3 or another EBS volume is permanently lost.

```bash
# Check DeleteOnTermination for all volumes on an instance
aws ec2 describe-instances --instance-ids i-0123456789abcdef0 \
    --query "Reservations[0].Instances[0].BlockDeviceMappings[*].[DeviceName,Ebs.DeleteOnTermination]"

# Disable DeleteOnTermination for the root volume while the instance is running
aws ec2 modify-instance-attribute \
    --instance-id i-0123456789abcdef0 \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"DeleteOnTermination":false}}]'
```

**Relying on the dynamic public IP for SSH access after a stop/start cycle.** The public IP changes on each stop/start, causing SSH connections and IP-based firewall rules to break.

```bash
# Allocate an Elastic IP and associate it with the instance
aws ec2 allocate-address --domain vpc
aws ec2 associate-address \
    --instance-id i-0123456789abcdef0 \
    --allocation-id eipalloc-0123456789abcdef0
# The Elastic IP persists across stop/start cycles
```

---

## Interview Angle

Common question forms:
- "What is the difference between stopping and terminating an EC2 instance?"
- "What is an AMI and how is it used in EC2?"
- "How do EC2 instances get AWS credentials to call services like S3?"

Answer frame:
For stop vs terminate: stop preserves the EBS root volume and incurs EBS storage charges; terminate deletes the root EBS by default (configurable) and ends all billing for the instance. For AMI: snapshot of OS + software + disk state used to launch identical instances — enables immutable infrastructure. For credentials: IAM instance profile attached at launch; boto3 automatically retrieves temporary credentials from the instance metadata service at 169.254.169.254.

---

## Related Notes

- [[ec2-instance-types|EC2 Instance Types]]
- [[ec2-launch|Launching EC2 Instances]]
- [[ec2-security-groups|EC2 Security Groups]]
- [[iam-instance-profile|IAM Instance Profile]]
- [[aws-overview|AWS Overview]]
