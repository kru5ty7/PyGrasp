---
title: Lambda IAM Execution Role
description: Every Lambda function assumes an IAM execution role at runtime — this role is the sole source of permissions for all AWS API calls the function makes.
tags: [aws, cloud, layer-11, lambda, iam, execution-role]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Lambda IAM Execution Role

> The execution role is the identity Lambda assumes when your function runs — it is the only lever that controls what AWS services your code can call, and scoping it correctly is non-negotiable in production.

---

## Quick Reference

**Core idea:**
- Every Lambda function has exactly one IAM execution role
- The role must have a trust policy allowing `lambda.amazonaws.com` to assume it
- The minimum viable policy is `AWSLambdaBasicExecutionRole` (CloudWatch Logs writes only)
- Add resource-specific statements for every AWS service the function calls (S3, DynamoDB, SQS, etc.)
- Resource-based policy on the Lambda function itself: controls who can invoke the function (separate from the execution role)
- Least privilege: scope permissions to specific resource ARNs, not `*`

**Tricky points:**
- The execution role governs what the function can do; the resource-based policy on the function governs who can trigger it — these are two different IAM constructs
- VPC-attached Lambda functions need `AWSLambdaVPCAccessExecutionRole` (ENI creation permissions) or the equivalent inline policy
- Permission boundary on the execution role limits the maximum permissions — useful in multi-team accounts
- IAM policy changes propagate within seconds but the function's existing warm execution environments may hold a cached credential session; restart the function to force a re-assumption
- `AccessDenied` errors in Lambda logs almost always trace to a missing execution role permission, not a bug in the function code

---

## What It Is

The IAM execution role is like a building access badge issued to a contractor. When the contractor (your Lambda function) is called in to do a job, they clip on their badge (assume the execution role) and the badge determines which doors they can open: the S3 room, the DynamoDB room, the Secrets Manager safe. The badge does not belong to the contractor — it belongs to the role, and the role is issued by the organisation (your AWS account). When the contractor leaves (the function exits), they hand the badge back. Every time they return (each invocation), they get a fresh, time-limited badge from IAM's Security Token Service.

This is materially different from how a long-running server gets its credentials. An EC2 instance assumes an instance profile once and uses its credentials for all operations. A Lambda function assumes its execution role on every cold start and gets a fresh set of temporary credentials (access key, secret key, session token) valid for the life of the execution environment. Those credentials are made available to your Python code automatically — when you call `boto3.client("s3")` without specifying credentials explicitly, boto3 reads them from the environment variables Lambda injects (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`). You never manage key rotation; IAM rotates the credentials automatically as part of the STS AssumeRole mechanism.

The execution role and the resource-based policy on the function itself are two separate IAM planes that beginners routinely conflate. The execution role answers the question "what can my function do?" The resource-based policy on the function answers "who is allowed to invoke my function?" S3 triggering a Lambda function requires a resource-based permission on the Lambda function allowing `s3.amazonaws.com` to call `lambda:InvokeFunction`. It does not require any change to the execution role. Conversely, if your function needs to read from an S3 bucket, that permission belongs in the execution role, not in the resource-based policy.

---

## How It Actually Works

Creating a minimal execution role and attaching it to a function involves three steps: create the role with a Lambda trust policy, attach the necessary permission policies, and reference the role ARN when creating the function.

```python
import boto3
import json

iam = boto3.client("iam")
lambda_client = boto3.client("lambda", region_name="us-east-1")

# Step 1: Create the execution role with a Lambda trust policy
trust_policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole",
        }
    ],
}

role_response = iam.create_role(
    RoleName="my-lambda-exec-role",
    AssumeRolePolicyDocument=json.dumps(trust_policy),
    Description="Execution role for my-function",
)
role_arn = role_response["Role"]["Arn"]

# Step 2a: Attach the managed policy for CloudWatch Logs (minimum viable)
iam.attach_role_policy(
    RoleName="my-lambda-exec-role",
    PolicyArn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
)

# Step 2b: Add an inline policy scoped to specific resources (least privilege)
s3_policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject"],
            "Resource": "arn:aws:s3:::my-data-bucket/uploads/*",
        },
        {
            "Effect": "Allow",
            "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
            "Resource": "arn:aws:sqs:us-east-1:123456789012:my-processing-queue",
        },
    ],
}

iam.put_role_policy(
    RoleName="my-lambda-exec-role",
    PolicyName="my-function-permissions",
    PolicyDocument=json.dumps(s3_policy),
)
```

Adding a resource-based policy to the Lambda function to allow S3 to invoke it:

```bash
aws lambda add-permission \
    --function-name my-function \
    --statement-id s3-invoke-permission \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::my-data-bucket \
    --source-account 123456789012
```

Verifying the execution role a function uses and examining its policies:

```bash
# Check which role the function uses
aws lambda get-function-configuration \
    --function-name my-function \
    --query "Role"

# List all policies attached to that role
aws iam list-attached-role-policies --role-name my-lambda-exec-role
aws iam list-role-policies --role-name my-lambda-exec-role  # inline policies
```

---

## How It Connects

The execution role is the Lambda-specific application of the broader IAM role model. The underlying mechanics — trust policies, permission policies, STS AssumeRole, temporary credentials — are the same across all AWS services.

[[iam-roles|IAM Roles]] — the foundational note on how roles, trust policies, and permission policies work together in AWS; the execution role is an instance of this pattern.

Applying least privilege to Lambda execution roles means knowing exactly which S3 buckets, DynamoDB tables, and queue ARNs the function should access. The least-privilege principle note covers the patterns for scoping policies correctly.

[[iam-least-privilege|IAM Least Privilege]] — covers condition keys, resource ARN scoping, and the IAM Access Analyzer tool for identifying over-permissive policies.

---

## Common Misconceptions

Misconception 1: You can give a Lambda function broad permissions temporarily for debugging, then tighten them later.
Reality: "Later" rarely arrives. Over-permissive execution roles that start as "temporary" tend to persist. An execution role with `s3:*` on `*` means a bug in the function — or a compromised execution environment — can read, overwrite, or delete any object in any bucket in the account. Applying least privilege from the first deploy is far less costly than remediating an incident caused by an over-permissive role.

Misconception 2: Adding a permission to the Lambda function's resource-based policy gives the function access to other services.
Reality: The resource-based policy on a Lambda function controls who can invoke the function, not what the function can do. To give the function the ability to read from DynamoDB, add a statement to the execution role's permission policy. The resource-based policy is only relevant when you want an external service (S3, API Gateway, EventBridge) to be allowed to call `lambda:InvokeFunction`.

---

## Why It Matters in Production

Execution role misconfiguration is the most common source of `AccessDenied` errors in Lambda. A function that cannot write to CloudWatch Logs (missing the basic execution policy) produces silent failures with no debugging trail. A function granted `s3:*` on `*` violates the principle of least privilege and creates unnecessary blast radius if the function is ever compromised. Getting the execution role right — minimal permissions, resource-scoped statements, CloudWatch Logs guaranteed — is foundational to both functional and secure Lambda deployments.

---

## What Breaks in Production

**Scenario 1: Function silently fails to log because CloudWatch Logs permission is missing**

```bash
# Mistake: attaching a custom policy that includes S3 and DynamoDB but forgetting CloudWatch Logs
# Result: function executes but writes no logs — debugging is impossible

# Fix: always attach AWSLambdaBasicExecutionRole or include these permissions
{
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ],
  "Resource": "arn:aws:logs:*:*:*"
}
```

**Scenario 2: S3 trigger fires but function never executes**

The execution role has S3 read permissions, but no resource-based policy was added to the function.

```bash
# Mistake: assuming S3 can invoke the function because the execution role has S3 permissions
# The execution role controls what the function can DO, not who can INVOKE it

# Fix: add a resource-based permission allowing S3 to invoke the function
aws lambda add-permission \
    --function-name my-function \
    --statement-id s3-invoke \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::my-trigger-bucket \
    --source-account 123456789012
```

---

## Interview Angle

Common question forms:
- "What is the Lambda execution role and what does it control?"
- "How is the execution role different from the Lambda function's resource-based policy?"
- "How would you debug an AccessDenied error in a Lambda function?"

Answer frame:
Clearly separate the two IAM planes: execution role (function → AWS services) versus resource-based policy (external principal → function invocation). Describe the STS AssumeRole mechanism and temporary credentials. Walk through least-privilege scoping with specific resource ARNs. For debugging AccessDenied: check the execution role policies, check CloudTrail for the denied API call, and use IAM Access Analyzer or the policy simulator.

---

## Related Notes

- [[iam-roles|IAM Roles]]
- [[iam-policies|IAM Policies]]
- [[iam-least-privilege|IAM Least Privilege]]
- [[lambda-overview|Lambda Overview]]
- [[lambda-environment|Lambda Environment Variables]]
