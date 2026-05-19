---
title: 08 - IAM Policies
description: IAM policies are JSON documents that define what actions are allowed or denied on which AWS resources - they are the mechanism by which every permission in AWS is granted or restricted.
tags: [aws, cloud, layer-11, iam, policies, permissions]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# IAM Policies

> IAM policies are the permission language of AWS - every access control decision reduces to evaluating a set of JSON policy documents, and the ability to read, write, and debug policies is the core IAM skill.

---

## Quick Reference

**Core idea:**
- A policy is a JSON document containing a `Version` and a list of `Statement` objects
- Each statement has: `Effect` (Allow or Deny), `Action` (list of API actions), `Resource` (ARN of target), optional `Condition`
- Policy types: identity-based (attached to user/group/role), resource-based (attached to S3 bucket, SQS queue, etc.), permission boundaries, and Session Policies
- Evaluation order: explicit Deny wins → SCP restricts → explicit Allow succeeds → default Deny
- AWS managed policies (maintained by AWS, e.g., `AmazonS3ReadOnlyAccess`) vs customer managed policies (you define and maintain)
- ARN wildcard: `arn:aws:s3:::my-bucket/*` matches all objects in the bucket; `*` alone matches all resources of any type

**Tricky points:**
- `"Action": "s3:*"` is not the same as `"Action": "*"` - the first is all S3 actions, the second is all actions on all services
- Resource-based policies can allow cross-account access without an assume-role flow - this is both powerful and dangerous if misconfigured
- An IAM user with no policies attached can still make `sts:GetCallerIdentity` calls - there is a small set of actions that are allowed by default for authenticated users
- Inline policies are tightly coupled to the entity they are attached to - deleting the entity deletes the policy; use customer managed policies instead
- The Condition block supports over 40 condition operators; the most commonly used are `StringEquals`, `StringLike`, `ArnLike`, `IpAddress`, and `Bool`

---

## What It Is

Think of an IAM policy as a detailed terms-of-access contract. A visitor to a secure facility signs a contract that lists exactly which rooms they may enter (the Resource), what they are permitted to do in those rooms (the Action), and under what conditions (the Condition). The contract also specifies what they are explicitly prohibited from doing (Deny). The security desk holds a copy of every active contract for every visitor and checks the relevant contracts every time someone tries to open a door. If no contract mentions a particular door, entry is refused - not because it is explicitly prohibited, but because it is not explicitly permitted.

AWS managed policies are pre-written contracts maintained by Amazon. `AmazonS3ReadOnlyAccess` is a policy that AWS writes, updates when the S3 API changes, and makes available to attach to any user, group, or role in your account. They are convenient for common use cases but are rarely minimal - `AmazonS3ReadOnlyAccess` grants `s3:GetObject` on `*`, meaning all objects in all buckets in all accounts you have access to, which is broader than most applications need. Customer managed policies are contracts you write yourself, allowing you to scope permissions to specific buckets, specific prefixes, or specific conditions.

The Condition block in a policy statement is one of the most powerful and underused features. It allows permissions to be context-sensitive - allowing an action only from specific IP addresses, only when MFA is active, only when the request targets a resource with a specific tag, or only during business hours. A policy that grants `s3:DeleteObject` only when the condition `aws:MultiFactorAuthPresent: true` is set requires MFA authentication before destructive operations can proceed. Conditions are the mechanism for fine-grained, contextual access control that goes beyond simple allow-all-or-deny-all decisions.

---

## How It Actually Works

When an API call arrives at AWS, the IAM policy evaluation engine collects all applicable policies in a specific order. First, it checks whether AWS Organizations Service Control Policies (SCPs) allow the action - if an SCP denies it, evaluation stops. Then it checks all identity-based policies attached to the calling entity (user, role, or federated identity) and all resource-based policies on the target resource. The engine applies the logic: if any applicable policy has an explicit `Deny` matching the action and resource, the call is denied. If at least one policy has an explicit `Allow` and no `Deny` exists, the call is allowed. If no policy mentions the action at all, the default implicit deny applies.

The `Resource` element uses Amazon Resource Names (ARNs). ARNs follow the pattern `arn:partition:service:region:account-id:resource`. For IAM policies, `*` in the resource field matches any resource. Resource-level restrictions are one of the most effective ways to implement least privilege - instead of allowing `s3:GetObject` on `*`, specify `arn:aws:s3:::specific-bucket/*` to restrict access to one bucket. Not all AWS services support resource-level permissions for all actions - for some actions, you must use `"Resource": "*"` because the service does not accept more specific ARNs.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadWrite",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-app-bucket",
        "arn:aws:s3:::my-app-bucket/*"
      ]
    },
    {
      "Sid": "DenyDeletionWithoutMFA",
      "Effect": "Deny",
      "Action": "s3:DeleteObject",
      "Resource": "arn:aws:s3:::my-app-bucket/*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }
  ]
}
```

```bash
# Create a customer managed policy from a JSON file
aws iam create-policy \
  --policy-name MyS3AppPolicy \
  --policy-document file://s3-policy.json

# Attach it to a role
aws iam attach-role-policy \
  --role-name my-lambda-role \
  --policy-arn arn:aws:iam::123456789012:policy/MyS3AppPolicy

# List all versions of a customer managed policy
aws iam list-policy-versions \
  --policy-arn arn:aws:iam::123456789012:policy/MyS3AppPolicy

# Simulate what policies allow (IAM Policy Simulator via CLI)
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/my-role \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::my-bucket/test.txt \
  --output table

# Get the effective policy attached to a role
aws iam get-role-policy \
  --role-name my-lambda-role \
  --policy-name MyInlinePolicy

# List all policies in the account
aws iam list-policies --scope Local --output table  # Local = customer managed only
```

```python
import boto3
import json

iam = boto3.client('iam')

# Create a customer managed policy programmatically
policy_document = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject"],
            "Resource": f"arn:aws:s3:::my-app-bucket/*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::my-app-bucket"
        }
    ]
}

response = iam.create_policy(
    PolicyName='MyAppS3Policy',
    PolicyDocument=json.dumps(policy_document),
    Description='Grants read/write access to the application S3 bucket'
)
policy_arn = response['Policy']['Arn']
print(f"Created policy: {policy_arn}")

# Simulate permissions before deploying (IAM policy simulator API)
sts = boto3.client('sts')
account_id = sts.get_caller_identity()['Account']

sim_result = iam.simulate_principal_policy(
    PolicySourceArn=f'arn:aws:iam::{account_id}:role/my-lambda-role',
    ActionNames=['s3:GetObject', 's3:DeleteBucket'],
    ResourceArns=['arn:aws:s3:::my-app-bucket/test.txt']
)

for result in sim_result['EvaluationResults']:
    print(f"{result['EvalActionName']}: {result['EvalDecision']}")
# s3:GetObject: allowed
# s3:DeleteBucket: implicitDeny
```

---

## How It Connects

Policies define the permission boundary for every IAM entity - users, groups, and roles are only meaningful in combination with the policies attached to them. Policy evaluation is what determines whether any boto3 call or CLI command succeeds.

[[iam-overview|IAM Overview]] - the broader IAM model that policies fit into; the evaluation logic described here applies to every API call in AWS.

[[iam-roles|IAM Roles]] - roles are the entities that policies are most commonly attached to for application code; understanding policy structure is required to configure roles correctly.

The principle of least privilege is the design philosophy that guides how policies should be written - start with no permissions and add the minimum set required.

[[iam-least-privilege|Principle of Least Privilege]] - the practice of writing minimal policies rather than broad ones; applies to every policy you write.

---

## Common Misconceptions

Misconception 1: "If I have AdministratorAccess attached, no Deny can stop me."
Reality: An explicit Deny in a resource-based policy, a permission boundary, or a Service Control Policy (SCP) overrides AdministratorAccess. If an S3 bucket has a resource-based policy that denies access from your account, even an IAM user with AdministratorAccess cannot access it. SCPs in AWS Organizations can restrict even accounts with AdministratorAccess from performing certain actions. The explicit Deny hierarchy applies at every level, including above identity-based policies.

Misconception 2: "Attaching multiple policies with the same Allow is redundant but harmless - the permissions just stack."
Reality: Policies do stack - each additional Allow policy adds to the effective permissions. The risk is not redundancy but over-permissioning. Each AWS managed policy grants more than most applications need, and attaching multiple managed policies accumulates permissions that exceed what the application requires. This is a least-privilege violation and expands the blast radius if the identity is compromised.

Misconception 3: "Inline policies are more secure than managed policies because they cannot be accidentally attached to other entities."
Reality: Inline policies are not more secure - they are less manageable. An inline policy is deleted when its entity is deleted (which can cause silent permission loss), cannot be reused across entities, cannot be version-controlled independently, and is harder to audit because it does not appear in the managed policy list. Customer managed policies, properly named and described, are the better practice: reusable, version-controlled, and visible in the policy catalogue.

---

## Why It Matters in Practice

Every "Access Denied" error in a Python application running on AWS is a policy problem. The ability to read an IAM policy and predict what it allows and denies - without running the code - is what separates debugging in minutes from debugging in hours. A developer who sees `ClientError: An error occurred (AccessDenied) when calling the PutObject operation` and knows to check the Lambda execution role's policies, the S3 bucket policy, and whether any SCPs apply will resolve the issue quickly. A developer who does not understand policy evaluation will chase the wrong leads.

Poorly written policies are also a security liability. Granting `s3:*` on `*` for a Lambda function that only needs to read from one specific bucket is a policy that allows that Lambda to delete every object in every bucket it can reach, overwrite objects in other teams' buckets, and modify bucket policies. If the Lambda is ever compromised (through a dependency vulnerability, code injection, or SSRF), the attacker has those same permissions. Policy design is application security.

---

## What Breaks in Production

**Scenario 1: Policy grants access to bucket but not to objects within it - `ListBucket` and `GetObject` require separate resource ARNs.**

```json
// Wrong: only covers the bucket itself, not objects
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": "arn:aws:s3:::my-bucket"
}

// Right: bucket-level actions need the bucket ARN,
// object-level actions need the bucket/* ARN
{
  "Effect": "Allow",
  "Action": "s3:ListBucket",
  "Resource": "arn:aws:s3:::my-bucket"
},
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::my-bucket/*"
}
```

**Scenario 2: Condition key typo silently has no effect.**

```bash
# Wrong: typo in condition key - 'aws:sourceIp' should be 'aws:SourceIp'
# IAM condition keys are case-insensitive for AWS global keys,
# but service-specific keys ARE case-sensitive
# Verify policies with the simulator before deploying

aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/my-role \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::my-bucket/test.txt \
  --context-entries Key=aws:SourceIp,Type=IP,Values=10.0.0.1 \
  --output table
```

**Scenario 3: Customer managed policy not updated when S3 API adds new required action.**

```python
# When a new AWS feature requires a new IAM action, old policies silently deny it.
# Example: S3 Object Lock required new actions not in older policies.

# Check what actions are being denied in CloudTrail
import boto3

cloudtrail = boto3.client('cloudtrail', region_name='us-east-1')
response = cloudtrail.lookup_events(
    LookupAttributes=[
        {'AttributeKey': 'EventName', 'AttributeValue': 'PutObjectLegalHold'}
    ],
    MaxResults=10
)
for event in response['Events']:
    print(event['EventName'], event['Username'], event.get('ErrorCode'))
```

---

## Interview Angle

Common question forms:
- "Walk me through how AWS evaluates an IAM policy."
- "What is the difference between identity-based and resource-based policies?"
- "How would you write a policy that allows S3 access only from within a VPC?"

Answer frame:
Evaluation: default deny → SCPs → explicit deny wins → explicit allow wins → implicit deny. Identity-based policies travel with the identity (user/role); resource-based policies travel with the resource (S3 bucket, SQS queue) and can permit cross-account access. For VPC-restricted access, use the `aws:SourceVpc` or `aws:SourceVpce` condition key in the bucket policy. Demonstrate understanding of the resource ARN format and the requirement to specify bucket and object ARNs separately for S3.

---

## Related Notes

- [[iam-overview|IAM Overview]]
- [[iam-roles|IAM Roles]]
- [[iam-users-groups|IAM Users and Groups]]
- [[iam-least-privilege|Principle of Least Privilege]]
- [[s3-permissions|S3 Permissions]]
