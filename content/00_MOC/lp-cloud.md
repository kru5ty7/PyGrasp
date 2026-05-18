---
title: Learning Path — Cloud (AWS)
description: AWS fundamentals, IAM, S3, EC2, Lambda, and additional services — with boto3 code, architecture diagrams, and "What Breaks in Production" sections.
tags: [moc, learning-path, cloud, aws, layer-11]
---

# Learning Path — Cloud (AWS)

> AWS from first principles. Assumes Layer 13 (containers) and some HLD knowledge. Every note includes architecture diagrams, boto3 code, and a "What Breaks in Production" section.

---

## Layer 11a — AWS Foundations

1. [[aws-overview|AWS Overview]]
2. [[aws-regions-and-az|AWS Regions and Availability Zones]]
3. [[aws-cli|AWS CLI]]
4. [[boto3-basics|boto3 Basics]]
5. [[aws-pricing-model|AWS Pricing Model]]

---

## Layer 11b — IAM (Identity and Access Management)

1. [[iam-overview|IAM Overview]]
2. [[iam-users-groups|IAM Users and Groups]]
3. [[iam-policies|IAM Policies]]
4. [[iam-roles|IAM Roles]]
5. [[iam-role-python|IAM Roles with Python (boto3)]]
6. [[iam-assume-role|Assuming IAM Roles (STS)]]
7. [[iam-least-privilege|Principle of Least Privilege]]
8. [[iam-instance-profile|EC2 Instance Profiles]]

---

## Layer 11c — S3

1. [[s3-overview|S3 Overview]]
2. [[s3-buckets|S3 Buckets and Objects]]
3. [[s3-python|S3 with Python (boto3)]]
4. [[s3-permissions|S3 Bucket Policies and ACLs]]
5. [[s3-presigned-urls|S3 Presigned URLs]]
6. [[s3-storage-classes|S3 Storage Classes]]
7. [[s3-versioning|S3 Versioning]]
8. [[s3-event-notifications|S3 Event Notifications]]
9. [[s3-multipart-upload|S3 Multipart Upload]]

---

## Layer 11d — EC2

1. [[ec2-overview|EC2 Overview]]
2. [[ec2-instance-types|EC2 Instance Types]]
3. [[ec2-launch|Launching EC2 Instances]]
4. [[ec2-security-groups|EC2 Security Groups]]
5. [[ec2-key-pairs|EC2 Key Pairs and SSH]]
6. [[ec2-user-data|EC2 User Data Scripts]]
7. [[ec2-python|Managing EC2 with Python (boto3)]]
8. [[ec2-auto-scaling|EC2 Auto Scaling Groups]]
9. [[ec2-elb|Elastic Load Balancer]]
10. [[ec2-python-deployment|Deploying Python Apps on EC2]]

---

## Layer 11e — Lambda

1. [[lambda-overview|Lambda Overview]]
2. [[lambda-python|Lambda with Python]]
3. [[lambda-handlers|Lambda Handlers]]
4. [[lambda-layers|Lambda Layers]]
5. [[lambda-environment|Lambda Environment Variables]]
6. [[lambda-iam|Lambda IAM Execution Role]]
7. [[lambda-triggers|Lambda Triggers (S3, API Gateway, SQS)]]
8. [[lambda-cold-start|Lambda Cold Starts]]
9. [[lambda-concurrency|Lambda Concurrency and Scaling]]
10. [[lambda-container|Lambda with Container Images]]

---

## Layer 11f — Additional AWS Services

1. [[sqs|SQS (Simple Queue Service)]]
2. [[sns|SNS (Simple Notification Service)]]
3. [[rds|RDS]]
4. [[cloudwatch|CloudWatch]]
5. [[api-gateway-aws|AWS API Gateway]]
6. [[ecr|ECR (Elastic Container Registry)]]
7. [[ecs|ECS (Elastic Container Service)]]
