---
title: 30 - EC2 Auto Scaling Groups
description: An Auto Scaling Group automatically maintains a desired number of EC2 instances, replaces unhealthy ones, and scales capacity up or down in response to demand - making it the foundation of resilient, cost-efficient production deployments.
tags: [aws, cloud, layer-11, ec2, auto-scaling, scaling]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# EC2 Auto Scaling Groups

> Auto Scaling Groups turn EC2 from manual instance management into an autonomous, self-healing compute fleet - the infrastructure layer that makes your application resilient to both failures and traffic spikes without human intervention.

---

## Quick Reference

**Core idea:**
- An ASG maintains a fleet of EC2 instances between a minimum and maximum capacity, targeting a desired count
- When an instance fails a health check, the ASG terminates it and launches a replacement automatically
- Scaling policies adjust the desired capacity based on metrics (CPU, request count) or a schedule
- Launch templates define the instance configuration used for new instances - AMI, instance type, security groups, IAM role, user data
- ASGs are VPC-aware - spreading instances across multiple Availability Zones provides automatic fault tolerance

**Tricky points:**
- Scaling out (adding instances) has a cooldown period to prevent oscillation - new instances need time to start and pass health checks before the next scale-out decision
- ELB health checks in the ASG are stricter than EC2 health checks - an instance that passes the EC2 check (is it running?) but fails the ELB check (does the application respond to HTTP GET /) will be replaced
- The desired capacity can be updated manually, via scaling policy, or via scheduled action - all three can conflict
- Instance warm-up period: new instances should not receive traffic until their user data has run and the application is ready; the warm-up period tells the ASG to wait before counting new instances toward scaling metrics
- Lifecycle hooks let you run code during scale-out (before instance enters service) or scale-in (before instance is terminated) - used for draining connections, registering with configuration management, or deregistering from load balancers

---

## What It Is

Imagine managing a fleet of taxis for a city. During rush hour you need 50 taxis; at 3am you need 5. If a taxi breaks down, you dispatch a replacement immediately. You do not want the fleet to respond to every minor traffic fluctuation - if it rains for five minutes, you do not want to call in 20 extra taxis only to send them home when the rain stops. You want a controller that monitors demand, smooths out short-term fluctuations, and adjusts the fleet size based on sustained trends.

An Auto Scaling Group is that controller. It observes metrics like CPU utilisation, request count, or queue depth. When the metric indicates that demand exceeds the current capacity, the ASG increases the desired count and launches new instances using the configured launch template. When demand drops, the ASG decreases the desired count and terminates excess instances. The minimum and maximum capacity bounds ensure the fleet never shrinks below what you need for availability (even at zero load) and never grows beyond what your budget allows.

The health monitoring aspect is equally important. Production instances fail - disk fills up, memory leaks exhaust RAM, application processes crash and do not restart. Without an ASG, a failed instance stays failed until someone notices and manually replaces it. With an ASG, health checks run continuously. Any instance that fails an EC2 health check (is the hypervisor responsive?) or an ELB health check (does the application respond to an HTTP request?) is immediately terminated and replaced with a fresh instance built from the launch template. Self-healing infrastructure means your on-call engineer is not paged at 3am for a single instance failure.

---

## How It Actually Works

The launch template is the blueprint for every instance the ASG creates. It contains all the parameters from `run_instances`: the AMI ID, instance type, key pair, security groups, IAM instance profile, user data, storage configuration, and tags. Launch templates support versioning - you update the template and specify which version the ASG should use. A common deployment workflow is: build a new AMI, create a new launch template version pointing to the new AMI, then trigger an instance refresh on the ASG to gradually replace all old instances with new ones.

Scaling policies come in three types. Target tracking policies maintain a target metric value - for example, "keep average CPU utilisation at 50%." The ASG automatically calculates how many instances are needed to hit the target and adjusts. Step scaling policies define thresholds and step adjustments - if CPU is between 60-80% add 2 instances, if CPU is above 80% add 4. Scheduled scaling sets the desired count at specific times - scale up to 20 instances at 8am Monday-Friday, scale down to 5 at 8pm.

```bash
# Create a launch template
aws ec2 create-launch-template \
    --launch-template-name my-app-template \
    --version-description "v1.0" \
    --launch-template-data file://launch-template-data.json

# Create an Auto Scaling Group
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name my-app-asg \
    --launch-template LaunchTemplateName=my-app-template,Version='$Latest' \
    --min-size 2 \
    --max-size 10 \
    --desired-capacity 2 \
    --vpc-zone-identifier "subnet-abc123,subnet-def456,subnet-ghi789" \
    --target-group-arns arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/my-app/abc123 \
    --health-check-type ELB \
    --health-check-grace-period 300

# Add a target tracking scaling policy (maintain 50% average CPU)
aws autoscaling put-scaling-policy \
    --auto-scaling-group-name my-app-asg \
    --policy-name cpu-target-tracking \
    --policy-type TargetTrackingScaling \
    --target-tracking-configuration file://target-tracking-config.json

# Trigger an instance refresh (rolling replacement with new launch template version)
aws autoscaling start-instance-refresh \
    --auto-scaling-group-name my-app-asg \
    --preferences '{"MinHealthyPercentage": 80, "InstanceWarmup": 300}'

# Check ASG status
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names my-app-asg \
    --query "AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize,Instances[*].[InstanceId,HealthStatus]]"
```

```python
import boto3

autoscaling = boto3.client("autoscaling")
ec2 = boto3.client("ec2")

# Create a launch template
ec2.create_launch_template(
    LaunchTemplateName="my-app-template",
    VersionDescription="Initial version",
    LaunchTemplateData={
        "ImageId": "ami-0abcdef1234567890",
        "InstanceType": "m6i.large",
        "KeyName": "my-key",
        "SecurityGroupIds": ["sg-0123456789abcdef0"],
        "IamInstanceProfile": {"Name": "MyAppInstanceProfile"},
        "UserData": "IyEvYmluL2Jhc2g=",   # base64-encoded bootstrap script
        "TagSpecifications": [{
            "ResourceType": "instance",
            "Tags": [{"Key": "Environment", "Value": "production"}],
        }],
    },
)

# Create the ASG
autoscaling.create_auto_scaling_group(
    AutoScalingGroupName="my-app-asg",
    LaunchTemplate={"LaunchTemplateName": "my-app-template", "Version": "$Latest"},
    MinSize=2,
    MaxSize=10,
    DesiredCapacity=2,
    VPCZoneIdentifier="subnet-abc123,subnet-def456,subnet-ghi789",
    TargetGroupARNs=[
        "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/my-app/abc123"
    ],
    HealthCheckType="ELB",
    HealthCheckGracePeriod=300,  # seconds before ELB health checks start
    Tags=[
        {"Key": "Name", "Value": "my-app-instance",
         "PropagateAtLaunch": True},
    ],
)

# Add target tracking scaling policy
autoscaling.put_scaling_policy(
    AutoScalingGroupName="my-app-asg",
    PolicyName="cpu-target-tracking",
    PolicyType="TargetTrackingScaling",
    TargetTrackingConfiguration={
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "ASGAverageCPUUtilization",
        },
        "TargetValue": 50.0,
        "ScaleInCooldown": 300,
        "ScaleOutCooldown": 60,
    },
)

# Trigger a rolling replacement (instance refresh)
autoscaling.start_instance_refresh(
    AutoScalingGroupName="my-app-asg",
    Strategy="Rolling",
    Preferences={
        "MinHealthyPercentage": 80,   # keep 80% healthy during refresh
        "InstanceWarmup": 300,        # wait 5 minutes before counting new instances
    },
)

# Get ASG details
response = autoscaling.describe_auto_scaling_groups(
    AutoScalingGroupNames=["my-app-asg"]
)
asg = response["AutoScalingGroups"][0]
print(f"Desired: {asg['DesiredCapacity']}  Min: {asg['MinSize']}  Max: {asg['MaxSize']}")
for instance in asg["Instances"]:
    print(f"  {instance['InstanceId']} {instance['LifecycleState']} {instance['HealthStatus']}")
```

---

## How It Connects

Auto Scaling Groups work in conjunction with Elastic Load Balancers to form the standard scalable web application architecture. The ALB distributes traffic across ASG instances and performs health checks - instances that fail the ALB health check are marked unhealthy and replaced by the ASG.

[[ec2-elb|Elastic Load Balancer]] - the ALB target group is attached to the ASG; health check results from the ALB determine which instances the ASG considers healthy; understanding the interaction prevents the "healthy to EC2 but unhealthy to ELB" replacement loop.

Launch templates drive the instance configuration for every ASG-launched instance. Building and versioning launch templates is the prerequisite for rolling deployments via instance refresh.

[[ec2-launch|Launching EC2 Instances]] - launch templates are the production-grade evolution of `run_instances` parameters; the instance configuration choices made at launch directly determine how ASG instances behave.

---

## Common Misconceptions

Misconception 1: Setting `DesiredCapacity=5` means there will always be exactly 5 healthy instances serving traffic.
Reality: `DesiredCapacity` is a target, not a guarantee. During a scale-out event, new instances take time to launch, run user data, and pass health checks - there may be fewer than 5 healthy instances during this window. During an instance refresh, instances are replaced one by one; with `MinHealthyPercentage=80`, the ASG maintains at least 4 healthy instances while replacing the fifth. Relying on exactly N instances at all times requires designing for the transition period.

Misconception 2: Terminating an instance in an ASG removes it from the ASG permanently.
Reality: If the ASG's desired capacity is 5 and you terminate one of its instances, the ASG automatically launches a replacement to bring the count back to 5. The ASG is designed to self-heal - it treats any instance falling below the desired count as a deficit to be corrected. To permanently reduce the ASG size, you must update the desired capacity first, then allow the ASG to terminate instances normally via scale-in.

---

## Why It Matters in Practice

Auto Scaling Groups are the production standard for running stateless Python web applications on EC2. Without an ASG, a single instance failure causes an outage. Without scaling policies, a traffic spike causes degraded performance or downtime. The combination of multi-AZ deployment, ELB health checks, and target tracking scaling gives a Python web application self-healing, automatic scaling, and zero-downtime deployments through instance refresh.

The instance refresh mechanism specifically solves the deployment problem: how do you update 20 running EC2 instances to a new application version without downtime? The answer is to create a new AMI with the new application version, update the launch template to reference it, and trigger an instance refresh. The ASG replaces old instances with new ones gradually, ensuring the minimum healthy percentage stays above the threshold throughout.

---

## What Breaks in Production

**Health check grace period too short, causing a replacement loop.** If the grace period is shorter than the time needed for user data to complete and the application to start, new instances fail the ELB health check immediately, are terminated as unhealthy, and replaced - creating an endless loop of launching and terminating instances.

```bash
# Diagnose: check ASG activity history for rapid launch/terminate cycles
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name my-app-asg \
    --query "Activities[*].[StartTime,StatusCode,Description]" \
    --max-items 20

# Fix: increase health check grace period to cover full bootstrap time
aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name my-app-asg \
    --health-check-grace-period 600  # increase to 10 minutes if needed
```

**Scaling policy cooldown too short, causing oscillation.** If the scale-in cooldown is shorter than the time for traffic to rebalance after removing an instance, the ASG scales back out immediately after scaling in.

```python
# Set adequate cooldowns in the target tracking policy
autoscaling.put_scaling_policy(
    AutoScalingGroupName="my-app-asg",
    PolicyName="cpu-target-tracking",
    PolicyType="TargetTrackingScaling",
    TargetTrackingConfiguration={
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "ASGAverageCPUUtilization"},
        "TargetValue": 50.0,
        "ScaleInCooldown": 600,   # 10 minutes - allow traffic to settle after scale-in
        "ScaleOutCooldown": 120,  # 2 minutes - scale out faster than scale in
    },
)
```

---

## Interview Angle

Common question forms:
- "How does an Auto Scaling Group achieve high availability?"
- "What is the difference between EC2 health checks and ELB health checks in an ASG?"
- "How would you deploy a new version of an application to a running ASG without downtime?"

Answer frame:
For high availability: multi-AZ placement; failed instances are automatically replaced; scaling policies maintain capacity under load. For health check types: EC2 check = is the hypervisor responding; ELB check = does the application respond to HTTP GET /; ELB is stricter and the correct choice for web applications. For zero-downtime deployment: new AMI → new launch template version → instance refresh with MinHealthyPercentage=80.

---

## Related Notes

- [[ec2-overview|EC2 Overview]]
- [[ec2-launch|Launching EC2 Instances]]
- [[ec2-elb|Elastic Load Balancer]]
- [[ec2-python|Managing EC2 with Python (boto3)]]
- [[ec2-python-deployment|Deploying Python Apps on EC2]]
