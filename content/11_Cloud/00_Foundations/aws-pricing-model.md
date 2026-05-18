---
title: 05 - AWS Pricing Model
description: AWS charges on a pay-as-you-go basis across multiple dimensions — compute time, storage, API requests, and data transfer — and understanding these dimensions prevents unexpected bills that derail projects.
tags: [aws, cloud, layer-11, pricing, cost]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# AWS Pricing Model

> AWS pricing is multidimensional and pay-as-you-go — every architectural decision has a cost consequence, and the engineers who design systems without understanding pricing create bills that surprise everyone including themselves.

---

## Quick Reference

**Core idea:**
- Pay-as-you-go: you pay for what you use, no upfront commitment for on-demand pricing
- Compute (EC2): billed per second (minimum 60 seconds) by instance type and OS
- Storage (S3): per GB per month stored + per 1000 requests (GET, PUT priced differently)
- Data transfer: ingress (into AWS) is free; egress (out of AWS) costs ~$0.09/GB after the first 100 GB/month
- Lambda: first 1M requests/month free always; compute priced per GB-second of execution
- Free tier: 12-month new-account tier + always-free tier (Lambda, DynamoDB, CloudWatch)
- Reserved Instances: 1 or 3-year commitment gives up to 72% discount over on-demand

**Tricky points:**
- Data egress is the most commonly underestimated cost — transferring large datasets out of S3 to the internet or to another region is not free
- NAT Gateway has both an hourly charge (~$0.045/hr) and a per-GB data processing charge — high-traffic private subnets can cost more in NAT Gateway fees than in EC2 costs
- Cross-AZ data transfer is not free (~$0.01/GB) — tightly coupled services that communicate frequently across AZs accumulate costs
- Spot Instances can be interrupted with 2-minute warning — they are not suitable for stateful long-running jobs without a checkpoint/resume strategy
- The AWS Pricing Calculator estimates do not include data transfer until you explicitly add it — add it deliberately

---

## What It Is

Think of AWS pricing like a city's utility system, not a flat monthly rent. Water costs more when you use more of it. Electricity costs more during peak hours. And the city charges you to pump water out to neighbouring cities but not to pump water in from them. AWS pricing works on the same metered model. You pay for the compute time you actually use, the storage space you actually occupy, the API calls you actually make, and the data that actually leaves the network. When you stop using a service, the meter stops. When you need more, you do not negotiate a new contract — you simply use more.

The asymmetry between ingress and egress pricing is the single most important pricing concept to internalise. Sending data into AWS — uploading files to S3, writing logs to CloudWatch, pushing container images to ECR — costs nothing. Data leaving AWS — downloading files from S3 to a user's browser, calling external APIs from a Lambda function that returns large responses, or transferring data between AWS regions — incurs egress fees. At small scale this is invisible. At production scale, a service that streams video from S3 to users, or an analytics pipeline that exports query results to an on-premises system, can have egress costs that dwarf all other AWS spending. Architecture decisions that keep data within AWS (using CloudFront as a CDN rather than serving directly from S3, using SQS instead of polling from outside AWS) are often driven by this pricing asymmetry.

The free tier is real but bounded, and its boundaries are per-service and per-action. The always-free tier (Lambda's 1 million requests and 400,000 GB-seconds per month, DynamoDB's 25 GB of storage) persists indefinitely regardless of account age. The 12-month free tier (EC2 t2.micro for 750 hours per month, S3's 5 GB standard storage) expires one year after account creation. The common mistake is treating the free tier as a safety net — it is a promotion, not a budget. Set billing alerts before experimenting with new services, because the free tier for one service does not protect you from charges in another.

---

## How It Actually Works

AWS billing is calculated per service per region and aggregated monthly. The detailed billing data is available in the Cost and Usage Report (CUR), which exports CSV files to S3 with line-item detail for every API call and resource. For real-time visibility, AWS Cost Explorer provides filterable charts and forecasts. AWS Budgets lets you set threshold alerts (by email or SNS) when spending or usage exceeds defined levels.

Pricing varies by region. The same EC2 instance type costs different amounts in `us-east-1`, `eu-west-1`, and `ap-southeast-1`. `us-east-1` is typically among the cheapest regions. When optimising costs, the first step is always to verify that you are running in the most cost-efficient region that meets your latency and compliance requirements.

```bash
# Check current month's estimated charges
aws ce get-cost-and-usage \
  --time-period Start=2026-05-01,End=2026-05-18 \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --output table

# Get cost by service
aws ce get-cost-and-usage \
  --time-period Start=2026-05-01,End=2026-05-18 \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output table

# Create a billing alert (CloudWatch + SNS)
# Step 1: Create SNS topic for notifications
aws sns create-topic --name billing-alerts --region us-east-1

# Step 2: Subscribe your email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:billing-alerts \
  --protocol email \
  --notification-endpoint your@email.com \
  --region us-east-1

# Step 3: Create CloudWatch alarm (billing metrics only available in us-east-1)
aws cloudwatch put-metric-alarm \
  --alarm-name "EstimatedCharges-50USD" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:billing-alerts \
  --region us-east-1

# List EC2 savings plan and reserved instance utilisation
aws ce get-savings-plans-utilization \
  --time-period Start=2026-05-01,End=2026-05-18
```

```python
import boto3
from datetime import datetime, timedelta

# Query Cost Explorer for this month's spend by service
ce = boto3.client('ce', region_name='us-east-1')

today = datetime.today()
start = today.replace(day=1).strftime('%Y-%m-%d')
end = today.strftime('%Y-%m-%d')

response = ce.get_cost_and_usage(
    TimePeriod={'Start': start, 'End': end},
    Granularity='MONTHLY',
    Metrics=['BlendedCost'],
    GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
)

for group in response['ResultsByTime'][0]['Groups']:
    service = group['Keys'][0]
    cost = group['Metrics']['BlendedCost']['Amount']
    unit = group['Metrics']['BlendedCost']['Unit']
    if float(cost) > 0:
        print(f"{service}: {float(cost):.4f} {unit}")

# Get Lambda invocation count to verify free-tier usage
cw = boto3.client('cloudwatch', region_name='us-east-1')
response = cw.get_metric_statistics(
    Namespace='AWS/Lambda',
    MetricName='Invocations',
    Dimensions=[],
    StartTime=datetime.utcnow() - timedelta(days=30),
    EndTime=datetime.utcnow(),
    Period=2592000,  # 30 days in seconds
    Statistics=['Sum']
)
if response['Datapoints']:
    total = response['Datapoints'][0]['Sum']
    print(f"Lambda invocations this month: {total:,.0f} (free tier: 1,000,000)")
```

---

## How It Connects

Pricing awareness influences architecture decisions at every level. The choice between storing data in S3 versus EBS, or using NAT Gateway versus a NAT instance, is partly a cost decision. Understanding pricing before building prevents expensive rewrites.

[[aws-overview|AWS Overview]] — the service catalogue that this pricing model applies to; every service has its own pricing dimensions.

Lambda has a unique pricing model — pay per invocation and per GB-second — that makes it extremely cost-effective for low-to-medium throughput workloads and surprisingly expensive at high concurrency without optimisation.

[[lambda-overview|Lambda Overview]] — the serverless compute service with the most distinctive pricing model in the AWS catalogue.

Data egress costs accumulate between S3 and the internet, between S3 and EC2 in different regions, and between any services when data crosses region boundaries. S3 storage decisions directly affect monthly bills.

[[s3-overview|S3 Overview]] — object storage with storage costs, request costs, and egress costs that interact in non-obvious ways.

---

## Common Misconceptions

Misconception 1: "I am on the free tier so I will not be charged."
Reality: The free tier is a per-service allowance, not an account-wide protection. Running an EC2 t2.micro within the 750-hour monthly free tier does not protect you from charges for a NAT Gateway, data egress, or a second EC2 instance. Always verify which specific free-tier limits apply to the services you are using, and set billing alerts regardless of tier status.

Misconception 2: "Stopped EC2 instances do not cost anything."
Reality: Stopped EC2 instances do not incur compute charges, but EBS volumes attached to them continue to accrue storage costs. An `io1` EBS volume costs approximately $0.125/GB/month in us-east-1 — a stopped instance with a 500 GB root volume costs ~$62/month in storage alone. Terminate instances you no longer need; do not rely on stopping them to eliminate costs entirely.

Misconception 3: "Spot Instances are always worth using because they are so much cheaper."
Reality: Spot Instances offer up to 90% discount but can be interrupted with 2 minutes notice when EC2 capacity is reclaimed. They are ideal for fault-tolerant, stateless, or checkpointable workloads (batch processing, CI runners, data transformation). They are inappropriate for stateful applications, databases, or anything that cannot handle sudden termination. Using Spot for the wrong workload does not save money — it creates incidents.

---

## Why It Matters in Practice

AWS bills are one of the most common causes of startups running out of money. An architecture that works perfectly in development and staging can generate thousands of dollars per month in production due to data transfer costs, oversized instances, or services left running after testing. The engineers who write the code are often the last to see the bill — and by the time it arrives, the architecture is in production and expensive to change.

Understanding pricing also enables better architectural decisions in the moment. Knowing that NAT Gateway charges per GB processed makes a VPC endpoint (which routes traffic over the private AWS network, avoiding NAT Gateway) an obvious choice for high-volume S3 access from private subnets. Knowing that Lambda charges per GB-second of memory means that right-sizing Lambda memory (which also affects CPU allocation) is a cost and performance optimisation simultaneously. These decisions are invisible without pricing knowledge and obvious with it.

---

## What Breaks in Production

**Scenario 1: Lambda function allocated maximum memory "for safety," multiplying costs.**

```python
# In Lambda configuration: memory set to 3008 MB "to be safe"
# A function running for 1 second at 3008 MB costs:
# 3008 MB * 1s = 3008 GB-seconds * $0.0000166667 = $0.0000501/invocation
# At 10M invocations/month: $501/month

# Right: profile memory usage and set to actual peak + 20% headroom
# Run the function with AWS Lambda Power Tuning (open source tool)
# or test with different memory settings using CLI:
aws lambda update-function-configuration \
  --function-name my-function \
  --memory-size 256  # start here, increase only if needed
```

**Scenario 2: High-volume S3 access from private subnet routed through NAT Gateway.**

```bash
# Wrong: all S3 traffic flows through NAT Gateway, paying per-GB charges
# Private subnet → NAT Gateway ($0.045/hr + $0.045/GB) → S3

# Right: create a VPC endpoint for S3 (free, routes via private network)
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345678 \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids rtb-12345678
# Now private subnet S3 traffic bypasses NAT Gateway entirely
```

**Scenario 3: Test resources left running after a sprint, accumulating costs silently.**

```python
# Tag all resources with an expiry indicator at creation time
ec2 = boto3.client('ec2', region_name='us-east-1')
ec2.create_tags(
    Resources=['i-1234567890abcdef0'],
    Tags=[
        {'Key': 'Environment', 'Value': 'test'},
        {'Key': 'ExpiryDate', 'Value': '2026-05-25'},
        {'Key': 'Owner', 'Value': 'dev-team'}
    ]
)

# Query for old test resources using Cost Explorer tags
ce = boto3.client('ce', region_name='us-east-1')
response = ce.get_tags(
    SearchString='test',
    TimePeriod={'Start': '2026-05-01', 'End': '2026-05-18'},
    TagKey='Environment'
)
```

---

## Interview Angle

Common question forms:
- "How do you manage and optimise AWS costs in a production environment?"
- "What is the most expensive mistake you have seen in AWS architectures?"
- "Explain the different EC2 pricing models."

Answer frame:
Start with the three EC2 tiers: on-demand (full price, no commitment, maximum flexibility), reserved (1 or 3 year, up to 72% discount, for predictable baseline load), spot (up to 90% discount, interruptible, for fault-tolerant batch workloads). Then address the less-obvious costs: data egress, NAT Gateway, cross-AZ transfer, and request pricing on S3. Demonstrate familiarity with Cost Explorer, billing alerts, and resource tagging as the operational tools for visibility.

---

## Related Notes

- [[aws-overview|AWS Overview]]
- [[lambda-overview|Lambda Overview]]
- [[s3-overview|S3 Overview]]
- [[ec2-overview|EC2 Overview]]
- [[aws-regions-and-az|AWS Regions and Availability Zones]]
