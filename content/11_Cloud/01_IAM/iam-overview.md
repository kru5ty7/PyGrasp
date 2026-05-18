---
title: 06 - IAM Overview
description: IAM (Identity and Access Management) is AWS's service for controlling who can perform which actions on which resources — every API call in AWS is evaluated against IAM before it executes.
tags: [aws, cloud, layer-11, iam, security]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# IAM Overview

> IAM is the gatekeeper to every service in AWS — understanding its four core entities (users, groups, roles, policies) and its evaluation logic is not optional for anyone deploying applications to AWS.

---

## Quick Reference

**Core idea:**
- IAM has four entity types: users (people), groups (collections of users), roles (temporary identities for services), policies (permission documents)
- IAM is a global service — users, roles, and policies exist across all regions in your account
- Every AWS API call is evaluated by IAM before execution — no explicit Allow means implicit Deny
- The root account (the email used to create the AWS account) has unlimited power and should never be used for daily operations
- Authentication = who you are (credentials); Authorisation = what you can do (policies)
- ARN format for IAM: `arn:aws:iam::123456789012:user/alice`, `arn:aws:iam::123456789012:role/my-role`

**Tricky points:**
- There is no way to grant less than nothing — an explicit Deny in any policy overrides any Allow, regardless of how many Allows exist
- IAM policies do not take effect immediately in all cases — there is eventual consistency in IAM, especially during initial propagation
- The root account cannot be restricted by IAM policies — only by AWS Organizations Service Control Policies (SCPs)
- Access keys for IAM users are long-lived — a leaked key remains valid until explicitly rotated or deleted, unlike IAM role credentials which expire automatically
- IAM is separate from other AWS security services — IAM controls API access; VPC security groups control network access; both are needed for a secure system

---

## What It Is

Think of IAM as a company's security badge system combined with its HR records. Every employee (IAM user) gets a badge (credentials). Employees are organised into departments (groups), and departments are granted access to specific floors and rooms (permissions via policies). Some tasks — auditing the server room at 2am, accessing a client's data for a specific project — require a temporary visitor pass rather than a permanent badge (IAM role). The security desk (IAM) checks every badge before opening any door, and if you are not listed as authorised for that room, you are not getting in, regardless of how many other rooms you have access to.

The "no access by default" principle is the foundational mental model for IAM. When a new IAM user is created, they can authenticate (log in) but cannot do anything — not list S3 buckets, not describe EC2 instances, not even check their own account information. Every permission must be explicitly granted through a policy attachment. This is the opposite of a traditional Unix system where users have broad access until explicitly restricted. In AWS, the default state is no access, and you build up from there. This design means a mistake in one direction (forgetting to add a permission) is safe — the application fails but nothing is exposed. A mistake in the other direction (granting too much permission) is dangerous — a compromised credential has broad access.

IAM operates globally. Unlike EC2 or Lambda, which exist in specific regions, an IAM role or user created in one region is accessible everywhere. A Lambda function in `eu-west-1` can assume an IAM role created via the console in `us-east-1`. This global nature is convenient but also means that a security breach of an IAM credential affects all regions simultaneously — there is no regional isolation for IAM identities.

---

## How It Actually Works

When any AWS API call is made, AWS's authorisation engine collects every applicable policy — the identity-based policies attached to the calling user or role, any resource-based policies on the target resource (like an S3 bucket policy), permission boundaries, and AWS Organizations SCPs. It then evaluates them in a defined order: if any SCP denies the action, it is denied. If any identity or resource policy explicitly denies the action, it is denied. If at least one policy explicitly allows the action and no deny exists, it is allowed. If no policy explicitly allows the action, it is implicitly denied. This evaluation happens in milliseconds, synchronously, on every API call.

IAM integrates with AWS Security Token Service (STS) for temporary credentials. When a Lambda function, EC2 instance, or ECS task is assigned an IAM role, it does not receive static access keys — instead, it receives temporary credentials from STS that expire and are automatically rotated. This is why IAM roles are preferred over long-term access keys for any AWS service: the credentials are ephemeral, they cannot be permanently extracted, and their rotation is managed by AWS.

```bash
# Get the current identity (user, role, or root)
aws sts get-caller-identity

# List all IAM users in the account
aws iam list-users --output table

# List all IAM roles
aws iam list-roles --output table

# List policies attached to a user
aws iam list-attached-user-policies --user-name alice

# List policies attached to a role
aws iam list-attached-role-policies --role-name my-lambda-role

# List groups a user belongs to
aws iam list-groups-for-user --user-name alice

# Create a new IAM user (no permissions until policies are attached)
aws iam create-user --user-name new-developer

# Create access keys for a user (long-term credentials — prefer roles)
aws iam create-access-key --user-name new-developer

# List access keys and their last-used date (for rotation auditing)
aws iam list-access-keys --user-name alice
aws iam get-access-key-last-used --access-key-id AKIA...
```

```python
import boto3
from botocore.exceptions import ClientError

iam = boto3.client('iam')

# List all users
users = []
paginator = iam.get_paginator('list_users')
for page in paginator.paginate():
    users.extend(page['Users'])
print(f"Total users: {len(users)}")

# Get policies attached to a role
role_name = 'my-lambda-role'
response = iam.list_attached_role_policies(RoleName=role_name)
for policy in response['AttachedPolicies']:
    print(f"  {policy['PolicyName']} ({policy['PolicyArn']})")

# Verify the calling identity programmatically
sts = boto3.client('sts')
identity = sts.get_caller_identity()
print(f"Account: {identity['Account']}")
print(f"UserID: {identity['UserId']}")
print(f"ARN: {identity['Arn']}")
```

---

## How It Connects

IAM is the prerequisite for every other AWS service note in this layer. Every boto3 call and every CLI command is an IAM event — before writing application code, you must understand who is allowed to do what.

[[iam-policies|IAM Policies]] — the JSON permission documents that define what each identity can do; understanding policy structure is required to configure any IAM entity correctly.

IAM roles are the correct mechanism for giving AWS services (Lambda, EC2, ECS) permission to call other AWS services. Users and access keys are for humans and local development only.

[[iam-roles|IAM Roles]] — the IAM entity that Lambda functions, EC2 instances, and ECS tasks use to call AWS services without hardcoded credentials.

The AWS CLI and boto3 both operate as IAM identities — every command they execute is evaluated by IAM.

[[aws-cli|AWS CLI]] — the CLI interface that always operates as an IAM identity, making IAM understanding essential for CLI usage.

---

## Common Misconceptions

Misconception 1: "I can use the root account for day-to-day AWS operations — it is the most powerful account."
Reality: The root account's power is the reason to avoid using it. If the root account's credentials are compromised, the attacker has unrestricted access to everything in the account — including the ability to create new IAM users, modify billing, and delete all resources. Create an IAM user with AdministratorAccess policy for daily admin work, enable MFA on the root account, and store the root credentials somewhere secure. Use the root account only for the handful of operations that explicitly require it (e.g., changing account email, cancelling the account).

Misconception 2: "Adding more Allow statements makes IAM more permissive — there is no way to restrict with one policy what another policy allows."
Reality: An explicit Deny always overrides any number of Allows, regardless of which policy they come from. A policy with `"Effect": "Deny", "Action": "s3:DeleteObject"` blocks deletion even if another attached policy has `"Effect": "Allow", "Action": "s3:*"`. This is the mechanism for Service Control Policies and permission boundaries — higher-level restrictions that cannot be overridden by lower-level Allows.

Misconception 3: "IAM and VPC security groups are alternatives — I only need one or the other."
Reality: IAM and security groups operate at different layers and are both required. IAM controls whether a given identity is authorised to make an API call. Security groups control which network traffic can reach an EC2 instance or RDS endpoint. A Lambda function with an IAM role that allows RDS access but without the VPC security group permitting the Lambda's traffic to reach the RDS port will be denied at the network level. Both layers must permit access.

---

## Why It Matters in Practice

Every production incident involving compromised AWS credentials traces back to an IAM misconfiguration — either credentials that were too powerful, credentials that were not rotated, or credentials that were stored insecurely (hardcoded in source code, committed to a repository, set as plain-text environment variables). IAM is the first and most important security control in AWS, and misunderstanding it is the most consequential mistake a developer can make.

The positive case for understanding IAM is equally strong. A developer who understands IAM can write Python code that works correctly in every environment — local, staging, production — by relying on the credential resolution order rather than hardcoded keys. They can give Lambda functions exactly the permissions they need and nothing more, limiting the blast radius of any security event. They can debug "Access Denied" errors in minutes by reading the CloudTrail log and identifying exactly which IAM evaluation denied the call, rather than spending hours guessing.

---

## What Breaks in Production

**Scenario 1: Lambda function uses overly broad AdministratorAccess role, credentials exfiltrated via SSRF.**

```bash
# Wrong: Lambda role with AdministratorAccess
# If the Lambda is vulnerable to SSRF, the attacker can query IMDS and
# get temporary credentials with admin access to the entire account

# Right: scope the role to exactly what the function needs
aws iam create-role \
  --role-name lambda-s3-read-only \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
  --role-name lambda-s3-read-only \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

**Scenario 2: IAM changes not reflected immediately, causing intermittent permission errors.**

```python
import time
import boto3
from botocore.exceptions import ClientError

iam = boto3.client('iam')

# Attach a policy and then immediately try to use the new permission
iam.attach_role_policy(
    RoleName='my-role',
    PolicyArn='arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess'
)

# IAM has eventual consistency — the policy may not be visible immediately
# in all regions or for all API calls. Build in a retry for critical paths.
s3 = boto3.client('s3')
for attempt in range(5):
    try:
        s3.list_buckets()
        print("Permission propagated")
        break
    except ClientError as e:
        if e.response['Error']['Code'] == 'AccessDenied':
            time.sleep(2 ** attempt)  # exponential backoff
        else:
            raise
```

**Scenario 3: Access key leaked in public repository, account compromised.**

```bash
# Immediate response: deactivate (not delete) the leaked key first
aws iam update-access-key \
  --user-name compromised-user \
  --access-key-id AKIA... \
  --status Inactive

# Then check CloudTrail for what was done with the key
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=AKIA... \
  --start-time 2026-05-01 \
  --output table

# Finally, create a new key, update all systems using the old key, then delete it
aws iam delete-access-key \
  --user-name compromised-user \
  --access-key-id AKIA...
```

---

## Interview Angle

Common question forms:
- "Explain the IAM evaluation logic — when is an action allowed?"
- "What is the difference between IAM users, groups, and roles?"
- "How would you secure an AWS account from scratch?"

Answer frame:
IAM evaluation: default deny → collect all applicable policies → any explicit deny? denied → any explicit allow? allowed → denied. Users are for humans (long-term credentials), roles are for services and cross-account access (temporary credentials, preferred). Groups are for organising users and applying policies in bulk. For securing an account from scratch: enable MFA on root, create an admin IAM user, apply least-privilege policies, use roles not access keys for services, enable CloudTrail, set billing alerts.

---

## Related Notes

- [[iam-users-groups|IAM Users and Groups]]
- [[iam-policies|IAM Policies]]
- [[iam-roles|IAM Roles]]
- [[iam-least-privilege|Principle of Least Privilege]]
- [[aws-cli|AWS CLI]]
