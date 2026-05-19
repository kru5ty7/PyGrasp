---
title: 24 - EC2 Instance Types
description: EC2 instance types encode the CPU, memory, network, and storage characteristics of a virtual machine - choosing the right type is the primary cost and performance decision when deploying Python applications on EC2.
tags: [aws, cloud, layer-11, ec2, instance-types]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# EC2 Instance Types

> EC2 instance types let you pick exactly the CPU, memory, and network characteristics your workload needs - choosing the wrong type means either overpaying for unused resources or degrading performance through throttling.

---

## Quick Reference

**Core idea:**
- Instance type naming: `<family><generation>.<size>` (e.g. `m6i.large` = general purpose, 6th gen, Intel, large)
- Families: t (burstable), m (general purpose), c (compute), r (memory), g/p (GPU), i (storage), x (high memory)
- Sizes: nano, micro, small, medium, large, xlarge, 2xlarge, 4xlarge, … 48xlarge, metal
- Each doubling in size roughly doubles the vCPUs and memory - and the price
- For Python web services: t3.micro (dev), t3.small/medium (light traffic), m6i.large+ (production)

**Tricky points:**
- The t family uses CPU credits - sustained high CPU on a t3.micro causes throttling when credits are exhausted
- Processor variants matter for consistent benchmark results: `i` suffix = Intel, `a` suffix = AMD, `g` suffix = AWS Graviton (ARM)
- The same family across generations has different price/performance ratios - newer generations (m7i vs m5) are usually better value
- `xlarge` = 4 vCPUs / 16GB RAM (for m family); `2xlarge` = 8 vCPUs / 32GB; size labels are not universal across families
- Network bandwidth and EBS throughput increase with instance size - a t3.micro has 5 Gbps network; an m6i.4xlarge has 12.5 Gbps

---

## What It Is

Think of EC2 instance types as a menu of pre-configured computers. Just as a car manufacturer offers the same model body with different engine options - a 1.4L economical engine or a 3.5L performance engine - AWS offers the same virtualisation platform with different CPU, memory, network, and storage configurations. The instance type names encode those configurations concisely once you learn the naming convention.

The naming scheme follows a consistent pattern. The family letter indicates the primary optimisation: `t` for general-purpose burstable, `m` for general-purpose balanced, `c` for compute-optimised (more CPU per dollar), `r` for memory-optimised (more RAM per dollar), `g` and `p` for GPU instances (ML training and inference), and `i` for storage-optimised (NVMe SSDs with high IOPS). The generation number tells you which hardware generation the instance runs on - higher is newer, generally faster, and often cheaper per unit of compute. The processor suffix (`i` for Intel Xeon, `a` for AMD EPYC, `g` for AWS Graviton ARM) matters for applications with architecture-specific dependencies or licensing concerns. The size (nano through 48xlarge) determines how many vCPUs and how much memory the instance gets.

The `t` family deserves special explanation because its behaviour surprises developers. Unlike `m` or `c` instances, which provide consistent CPU access, `t` instances operate on a credit system. Each vCPU earns credits when it runs below its baseline utilisation (e.g., 20% for t3.micro). Credits accumulate up to a maximum. When the CPU needs to burst above baseline - during a deployment, a request spike, or heavy application startup - it spends credits. When credits run out, the CPU is throttled back to the baseline. A t3.micro left running a CPU-intensive task for hours will eventually plateau at 20% CPU and degrade application response times, with no error message - just slow code.

---

## How It Actually Works

AWS publishes detailed specifications for every instance type at the EC2 instance types page and via the API. Each instance type has guaranteed vCPUs, memory in GiB, network bandwidth in Gbps, and EBS throughput in MB/s. For `t` instances, the baseline CPU percentage, credit earn rate, and maximum credit balance are also published.

For Python web applications, the practical sizing exercise goes as follows. Start with the expected concurrent request rate and the average response time under load. Multiply to get the average CPU seconds per second needed. Add headroom for spikes. Select an instance type with enough vCPUs to handle that load at under 60% average CPU utilisation, leaving room for traffic spikes and background work. Memory is typically secondary for Python web apps (Django/Flask processes use 50-200MB each), unless the application caches large datasets in memory.

```bash
# List all available instance types in a region
aws ec2 describe-instance-types \
    --query "InstanceTypes[*].[InstanceType,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB]" \
    --output table | head -50

# Filter for specific family
aws ec2 describe-instance-types \
    --filters "Name=instance-type,Values=m6i.*" \
    --query "InstanceTypes[*].[InstanceType,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB,NetworkInfo.NetworkPerformance]" \
    --output table

# Get current CPU credit balance for a t-type instance (CloudWatch metric)
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUCreditBalance \
    --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
    --start-time 2026-05-18T00:00:00Z \
    --end-time 2026-05-18T23:59:59Z \
    --period 3600 \
    --statistics Average
```

```python
import boto3

ec2 = boto3.client("ec2")

# List all m6i instance types with their vCPU and memory specs
response = ec2.describe_instance_types(
    Filters=[{"Name": "instance-type", "Values": ["m6i.*"]}]
)
for it in sorted(response["InstanceTypes"], key=lambda x: x["MemoryInfo"]["SizeInMiB"]):
    print(
        f"{it['InstanceType']:20} "
        f"vCPUs: {it['VCpuInfo']['DefaultVCpus']:3}  "
        f"Memory: {it['MemoryInfo']['SizeInMiB']:7} MiB  "
        f"Network: {it['NetworkInfo']['NetworkPerformance']}"
    )

# Check if an instance is t-family (subject to CPU credits)
def is_burstable(instance_type: str) -> bool:
    return instance_type.startswith("t")

# Get the current instance type from within an EC2 instance
# (using the instance metadata service)
import urllib.request
token_request = urllib.request.Request(
    "http://169.254.169.254/latest/api/token",
    headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
    method="PUT",
)
token = urllib.request.urlopen(token_request).read().decode()
meta_request = urllib.request.Request(
    "http://169.254.169.254/latest/meta-data/instance-type",
    headers={"X-aws-ec2-metadata-token": token},
)
instance_type = urllib.request.urlopen(meta_request).read().decode()
print("Running on:", instance_type)
```

---

## How It Connects

Instance types interact directly with pricing - the compute cost per hour varies widely between families, generations, and sizes. Choosing between a t3.medium and an m6i.large for a production web server can differ by 3x in hourly cost, which compounds significantly at scale.

[[aws-pricing-model|AWS Pricing Model]] - on-demand, reserved, and spot pricing for EC2 instances; how instance type choice and pricing model interact for cost optimisation.

For auto-scaling groups, the instance type specified in the launch template determines the pool of capacity available for scaling. Mixing instance types (using multiple instance types in a mixed instances policy) improves availability and reduces cost.

[[ec2-auto-scaling|EC2 Auto Scaling Groups]] - how instance types are specified in launch templates and how mixed instance policies enable cost-optimised scaling using spot instances alongside on-demand.

---

## Common Misconceptions

Misconception 1: A t3.micro with 2 vCPUs means the application always has 2 full CPU cores available.
Reality: The `t3.micro` baseline is 10% CPU utilisation across its 2 vCPUs - effectively 0.2 vCPUs of sustained compute. The instance can burst to 100% using accumulated CPU credits, but once credits are exhausted, performance drops back to 10%. Long-running CPU-intensive tasks will be throttled. For sustained CPU work, use a fixed-performance instance type (m, c, r families).

Misconception 2: Newer generation instances always cost more.
Reality: AWS typically prices newer generation instances at the same price as or lower than the equivalent older generation, while offering better performance. An m6i.large is generally the same price or cheaper than an m5.large and provides better CPU performance, more network bandwidth, and better EBS throughput. When choosing between generations for the same family and size, the newest generation is almost always the better choice.

---

## Why It Matters in Practice

Instance type selection is the first cost lever in any EC2 deployment. A Python data pipeline that processes batch jobs could run on a c6i.2xlarge (compute-optimised) for faster data transformation, or an r6i.large (memory-optimised) for keeping a large dataset in memory, or a general-purpose m6i.large if the workload is balanced. The wrong choice means paying for resources the application does not use or experiencing performance degradation.

For Python web applications specifically, the t3 family is the pragmatic choice for development and staging (cheap, adequate for low sustained load), but production APIs under real traffic need fixed-performance instances to avoid CPU credit exhaustion causing latency spikes at the worst possible time - during traffic peaks.

---

## What Breaks in Production

**Running a Python web application on a t3.micro in production and experiencing latency spikes under load.** The spikes correspond to CPU credit exhaustion, not application bugs.

```bash
# Check CPU credit balance to confirm credit exhaustion
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUCreditBalance \
    --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
    --start-time 2026-05-17T00:00:00Z \
    --end-time 2026-05-18T00:00:00Z \
    --period 3600 --statistics Minimum

# Fix: upgrade to a fixed-performance instance type
aws ec2 stop-instances --instance-ids i-0123456789abcdef0
# Wait for stopped state, then modify
aws ec2 modify-instance-attribute \
    --instance-id i-0123456789abcdef0 \
    --instance-type '{"Value": "m6i.large"}'
aws ec2 start-instances --instance-ids i-0123456789abcdef0
```

**Deploying to an ARM-based Graviton instance (`m7g`, `t4g`) and getting import errors for Python packages with native C extensions compiled for x86.** Some packages install architecture-specific wheels; if the wheel is not available for ARM, pip falls back to source compilation (which may fail if build tools are missing) or installs an incompatible wheel.

```bash
# Verify architecture before deploying
python3 -c "import platform; print(platform.machine())"
# aarch64 = ARM (Graviton)
# x86_64 = Intel/AMD

# When installing packages on Graviton, ensure build tools are available
# in case source compilation is needed
sudo dnf install -y gcc python3-devel
pip install some-native-package
```

---

## Interview Angle

Common question forms:
- "What would you choose between a t3.large and an m6i.large for a production Python API?"
- "Explain the EC2 CPU credit system."
- "What instance family would you use for a memory-intensive Python data processing job?"

Answer frame:
For t3 vs m6i: t3 uses CPU credits and will throttle under sustained load - wrong for a production API. m6i provides consistent CPU access. For credits: baseline + burst model, credits earned at idle, spent at high CPU, throttle when exhausted. For memory-intensive: r family - memory-optimised, more GiB per dollar than m or c.

---

## Related Notes

- [[ec2-overview|EC2 Overview]]
- [[ec2-launch|Launching EC2 Instances]]
- [[ec2-auto-scaling|EC2 Auto Scaling Groups]]
- [[aws-pricing-model|AWS Pricing Model]]
