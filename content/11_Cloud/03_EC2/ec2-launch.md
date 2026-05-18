---
title: Launching EC2 Instances
description: Launching an EC2 instance requires choosing an AMI, instance type, key pair, security group, subnet, and storage — understanding each choice at launch time prevents connectivity failures and data loss later.
tags: [aws, cloud, layer-11, ec2, launch]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# Launching EC2 Instances

> Launching an EC2 instance is a sequence of interdependent decisions — AMI, instance type, key pair, security group, subnet, and IAM role — and getting any one of them wrong at launch time often requires a full replacement rather than a quick fix.

---

## Quick Reference

**Core idea:**
- `run_instances` is the boto3 call to launch one or more instances; it requires at minimum an AMI ID, instance type, and a security group
- Common AMIs: Amazon Linux 2023 (AL2023), Ubuntu 22.04/24.04 — find current AMI IDs via Systems Manager Parameter Store
- The public IP of a new instance is assigned by AWS and changes on stop/start — use an Elastic IP for a stable public address
- User data (bootstrap script) runs once at first launch — used to install dependencies and start services
- IamInstanceProfile must be specified at launch to attach a role — it cannot be added after launch using `run_instances`

**Tricky points:**
- AMI IDs are region-specific — an AMI ID from us-east-1 is not valid in eu-west-1
- `MinCount` and `MaxCount` in `run_instances` are confusing: `MinCount=1, MaxCount=1` launches exactly one instance; `MinCount=1, MaxCount=5` attempts to launch 5 and succeeds if at least 1 launches
- The instance is in the `pending` state briefly before becoming `running` — reading the public IP before the instance is running returns null
- SSH connectivity requires: instance running, SSH port 22 open in security group, correct key pair, correct username (ec2-user for Amazon Linux, ubuntu for Ubuntu)
- Termination protection can be enabled to prevent accidental termination via the API or console

---

## What It Is

Launching an EC2 instance is like ordering a custom-built computer from a configurator where every dropdown selection is interconnected. You pick the operating system image (AMI) — the equivalent of choosing which OS to pre-install. You pick the hardware profile (instance type) — how many CPUs, how much RAM. You configure the network access rules (security groups) — which ports are open to which IP ranges. You specify the SSH key (key pair) — the cryptographic credential you will use to log in. You choose the storage size and type. You optionally provide a bootstrap script (user data) that runs the first time the instance starts.

Once you submit the launch request, AWS allocates a physical host, copies the AMI disk image to a new EBS volume, attaches the security groups, assigns a network interface with a private IP (and optionally a public IP), and starts the virtual machine. The instance moves through the `pending` state before reaching `running`. The entire process typically takes 30-90 seconds, after which the SSH service is available and your application can start receiving traffic.

The AMI selection deserves particular attention. AWS-provided AMIs like Amazon Linux 2023 and Ubuntu receive regular security updates and have AWS-specific tooling pre-installed (the SSM agent, CloudWatch agent, EC2 Instance Connect). Third-party AMIs from the AWS Marketplace often include licensed software pre-installed. The AMI ID (e.g., `ami-0abcdef1234567890`) is region-specific — you cannot use a us-east-1 AMI ID when launching in eu-west-1. The recommended way to find the current AMI ID for a given OS and region is to query AWS Systems Manager Parameter Store, which AWS maintains with up-to-date AMI IDs.

---

## How It Actually Works

`run_instances` is the underlying API call for all instance launches — whether from the console, CLI, or SDK. It returns a response immediately (before the instance reaches the `running` state) containing the instance ID and initial metadata. The public IP address is not assigned until the instance reaches `running`, so you must wait before attempting to use it.

boto3 provides waiters — polling loops that call `describe_instances` or `describe_instance_status` until the desired state is reached. `instance_running` waits until the instance state is `running`; `instance_status_ok` waits until both the EC2 status check and the system status check pass, indicating the OS is fully booted and responsive.

```bash
# Find the current Amazon Linux 2023 AMI ID in eu-west-1
aws ssm get-parameter \
    --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
    --region eu-west-1 \
    --query Parameter.Value --output text

# Launch an instance
aws ec2 run-instances \
    --image-id ami-0abcdef1234567890 \
    --instance-type t3.micro \
    --key-name my-key-pair \
    --security-group-ids sg-0123456789abcdef0 \
    --subnet-id subnet-0123456789abcdef0 \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=my-app-server}]' \
    --user-data file://bootstrap.sh \
    --iam-instance-profile Name=MyInstanceProfile

# Wait until the instance is running
aws ec2 wait instance-running --instance-ids i-0123456789abcdef0

# Get the public IP
aws ec2 describe-instances --instance-ids i-0123456789abcdef0 \
    --query "Reservations[0].Instances[0].PublicIpAddress" --output text

# Allocate and associate an Elastic IP for a persistent public address
aws ec2 allocate-address --domain vpc
aws ec2 associate-address \
    --instance-id i-0123456789abcdef0 \
    --allocation-id eipalloc-0123456789abcdef0
```

```python
import boto3
import time

ec2 = boto3.client("ec2", region_name="eu-west-1")
ssm = boto3.client("ssm", region_name="eu-west-1")

# Get the latest Amazon Linux 2023 AMI ID for the region
ami_param = ssm.get_parameter(
    Name="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
)
ami_id = ami_param["Parameter"]["Value"]
print("Using AMI:", ami_id)

# User data bootstrap script (must be a string, will be base64-encoded by boto3)
user_data_script = """#!/bin/bash
yum update -y
yum install -y python3.11 python3.11-pip nginx
pip3.11 install gunicorn flask
echo "Bootstrap complete" >> /var/log/bootstrap.log
"""

# Launch the instance
response = ec2.run_instances(
    ImageId=ami_id,
    InstanceType="t3.micro",
    KeyName="my-key-pair",
    SecurityGroupIds=["sg-0123456789abcdef0"],
    SubnetId="subnet-0123456789abcdef0",
    MinCount=1,
    MaxCount=1,
    TagSpecifications=[
        {
            "ResourceType": "instance",
            "Tags": [
                {"Key": "Name", "Value": "my-app-server"},
                {"Key": "Environment", "Value": "production"},
            ],
        }
    ],
    UserData=user_data_script,
    IamInstanceProfile={"Name": "MyAppInstanceProfile"},
    BlockDeviceMappings=[
        {
            "DeviceName": "/dev/xvda",
            "Ebs": {
                "VolumeSize": 20,          # GB
                "VolumeType": "gp3",
                "DeleteOnTermination": True,
                "Encrypted": True,
            },
        }
    ],
    DisableApiTermination=False,  # set True to prevent accidental termination
)

instance_id = response["Instances"][0]["InstanceId"]
print("Launched:", instance_id)

# Wait for instance to be running
waiter = ec2.get_waiter("instance_running")
waiter.wait(InstanceIds=[instance_id])
print("Instance is running")

# Wait for status checks to pass (OS fully booted)
waiter = ec2.get_waiter("instance_status_ok")
waiter.wait(InstanceIds=[instance_id])
print("Status checks passed")

# Get the public IP
details = ec2.describe_instances(InstanceIds=[instance_id])
public_ip = details["Reservations"][0]["Instances"][0].get("PublicIpAddress")
print(f"SSH: ssh -i key.pem ec2-user@{public_ip}")
```

---

## How It Connects

A newly launched EC2 instance needs an IAM role (via instance profile) to call AWS services without hardcoded credentials. The role must be created before the instance is launched, because changing the IAM role after launch requires stopping the instance.

[[iam-instance-profile|IAM Instance Profile]] — how to create and attach an IAM role to an EC2 instance, and how Python code on the instance uses those credentials automatically.

The security group specified at launch controls which network traffic can reach the instance. SSH access (port 22) and HTTP access (port 80) must be explicitly allowed in the security group before the instance is reachable.

[[ec2-security-groups|EC2 Security Groups]] — the firewall rules that determine which inbound and outbound traffic is allowed for your EC2 instance.

---

## Common Misconceptions

Misconception 1: `MinCount=2, MaxCount=5` in `run_instances` always launches 5 instances.
Reality: The `MaxCount` is a request, not a guarantee. AWS will try to launch up to `MaxCount` instances. If capacity is constrained, it may launch fewer — but at least `MinCount`. If AWS cannot launch at least `MinCount` instances, the entire call fails. This is relevant for launching spot instances or launching in resource-constrained AZs.

Misconception 2: The public IP address assigned to a new instance is permanent.
Reality: The public IP assigned at launch is a dynamic IP from Amazon's pool. When you stop and start the instance, it gets a different public IP. For a stable public IP, you must allocate an Elastic IP address and associate it with the instance. Elastic IPs are free when associated with a running instance; they incur a small hourly charge when allocated but not associated.

---

## Why It Matters in Practice

The launch configuration determines everything about how the instance behaves. A missing IAM role means the application cannot call AWS services and fails at startup. A misconfigured security group means the instance is unreachable over SSH for debugging or over HTTP for traffic. A missing user data script means the application is not installed and traffic arrives to a blank OS. Getting launch right the first time — or using launch templates to codify the correct configuration — is the foundation of reliable deployments.

Launch templates (a saved set of launch parameters) are the production approach to EC2 launches. They allow versioning of launch configurations and are required for Auto Scaling Groups and EC2 Fleet. Understanding the `run_instances` API directly is essential for understanding what launch templates represent.

---

## What Breaks in Production

**Reading the public IP from the `run_instances` response before the instance is in the running state.** The public IP is null until the instance is running.

```python
# Bad — public IP may be None immediately after launch
response = ec2.run_instances(...)
instance = response["Instances"][0]
public_ip = instance.get("PublicIpAddress")  # likely None
print(f"ssh ec2-user@{public_ip}")  # ssh ec2-user@None

# Good — wait for running state, then re-describe
instance_id = response["Instances"][0]["InstanceId"]
ec2.get_waiter("instance_running").wait(InstanceIds=[instance_id])
details = ec2.describe_instances(InstanceIds=[instance_id])
public_ip = details["Reservations"][0]["Instances"][0]["PublicIpAddress"]
```

**SSH failing because the instance is running but the OS has not finished booting.** The `instance_running` waiter only checks the instance state, not the OS. Use `instance_status_ok` for full OS boot confirmation.

```python
# instance_running = instance state is "running" (hypervisor level)
ec2.get_waiter("instance_running").wait(InstanceIds=[instance_id])

# instance_status_ok = both EC2 and system status checks pass (OS level)
ec2.get_waiter("instance_status_ok").wait(InstanceIds=[instance_id])
# Only after this is SSH guaranteed to be available
```

---

## Interview Angle

Common question forms:
- "Walk me through the process of launching an EC2 instance programmatically."
- "How do you find the current AMI ID for Amazon Linux in a given region?"
- "What is the difference between `instance_running` and `instance_status_ok` waiters?"

Answer frame:
For launching: AMI ID from SSM Parameter Store, `run_instances` with instance type / key pair / security group / subnet / IAM profile / user data, wait for running, re-describe for public IP. For AMI IDs: region-specific, use SSM Parameter Store to avoid hardcoding. For waiters: `instance_running` = hypervisor state; `instance_status_ok` = OS booted and health checks passing.

---

## Related Notes

- [[ec2-overview|EC2 Overview]]
- [[ec2-instance-types|EC2 Instance Types]]
- [[ec2-security-groups|EC2 Security Groups]]
- [[ec2-key-pairs|EC2 Key Pairs and SSH]]
- [[ec2-user-data|EC2 User Data Scripts]]
- [[iam-instance-profile|IAM Instance Profile]]
