---
title: 12 - Principle of Least Privilege
description: Least privilege means giving every identity only the minimum permissions required for its specific function - it is the foundational security design principle for IAM and the primary defence against credential compromise.
tags: [aws, cloud, layer-11, iam, security, least-privilege]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Principle of Least Privilege

> Least privilege is the practice of granting exactly what is needed and nothing more - every over-permissioned role is a silent risk that becomes a loud incident the moment any credential is compromised.

---

## Quick Reference

**Core idea:**
- Start with no permissions; add only what is demonstrably required
- Scope every permission to the specific resource, not `*` - prefer `arn:aws:s3:::my-bucket/*` over `arn:aws:s3:::*`
- Tools for finding minimal permissions: IAM Access Analyzer, CloudTrail action history, IAM Access Advisor (last-used data)
- Common violations: `AdministratorAccess` on Lambda, `s3:*` on all buckets, wildcard resources on any sensitive action
- Blast radius: the damage from a compromised credential is bounded by its permissions - narrow permissions limit the blast radius
- Permission boundaries are a mechanism for delegating IAM management without granting full IAM admin rights

**Tricky points:**
- AWS's own managed policies (like `AmazonS3FullAccess`) are broader than most applications need - they are starting points, not production policies
- "I'll tighten it later" is one of the most expensive technical debt items in cloud security - tightening permissions in production requires testing each removed permission against real workloads
- IAM Access Advisor shows last-used dates for services but not for specific actions within a service - you may still be granting unused actions within an allowed service
- Some AWS actions have no resource-level constraint support - they require `"Resource": "*"` regardless - check the IAM documentation for each service
- Lambda functions that use `AdministratorAccess` because "it was the easiest way to get it working" are the single most common unnecessary privilege in AWS accounts

---

## What It Is

Think of least privilege like the access control system in a surgery suite. The surgeon can touch everything in the operating room. The anaesthesiologist can access the drug cabinet, the ventilator, and the monitoring equipment, but not the surgical instruments. The scrub technician can handle the sterile field and instruments, but not the drugs. The cleaning staff can enter after the procedure, but not during. None of them have access to the pharmacy, the billing office, or other wards. Each person has exactly what their specific role requires - no more, regardless of seniority or convenience. Giving the cleaning staff full hospital access because it would simplify their master key does not make operational sense, and the same logic applies to IAM.

In practice, least privilege in AWS means three things applied together. First, restrict the actions: instead of `s3:*` (all S3 operations), specify `s3:GetObject, s3:PutObject` (only the operations the code actually performs). Second, restrict the resources: instead of applying those actions to `*` (every resource in every account accessible from this role), specify the exact ARN of the bucket. Third, add conditions where relevant: restrict `s3:DeleteObject` to only succeed when the request originates from within the VPC, or only when the requesting user has completed MFA. Each layer of restriction reduces the possible damage from a compromised credential.

The iterative approach to achieving least privilege is more practical than trying to get it perfect from the start. Begin with a broader policy that allows the code to function, then use AWS tools to observe which permissions are actually used, and tighten from there. IAM Access Advisor (per role, shows which services were accessed and when) provides the service-level view. CloudTrail provides the action-level view - you can search for all API calls made by a specific role over a period and compare them to the role's policy to identify unused permissions. AWS IAM Access Analyzer goes further: it can analyse resource-based policies across your account and flag external access that may not be intended.

---

## How It Actually Works

The tools for applying least privilege form a workflow. When creating a new role, start with the AWS managed policy closest to the required permissions and use it as a template. Observe CloudTrail logs for the role over the next period of representative usage. Use that data to identify every unique API action the role calls and the specific resource ARNs those actions target. Create a customer managed policy that allows exactly those actions on exactly those resources. Replace the managed policy with your customer policy. Run the IAM policy simulator to verify the new policy allows everything required. Monitor CloudTrail for new `AccessDenied` events that indicate a missed permission.

Permission boundaries add a second layer: they define the maximum permissions an identity can have, regardless of what policies are attached. An administrator who needs to allow team members to create IAM roles (for new Lambda functions) but does not want those members to be able to create roles with more permissions than the team should have can set a permission boundary on all roles created within that context. Even if a developer attaches `AdministratorAccess` to a new role, the permission boundary prevents the role from exercising those permissions.

```bash
# IAM Access Advisor - see which services a role last accessed
aws iam generate-service-last-accessed-details \
  --arn arn:aws:iam::123456789012:role/my-lambda-role

# Retrieve the report (polling until ready)
aws iam get-service-last-accessed-details \
  --job-id <job-id-from-above> \
  --output table

# Identify actions taken by a role in CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=my-lambda-role \
  --start-time 2026-05-01 \
  --output table \
  --query 'Events[*].{Time:EventTime,Event:EventName,Resource:Resources[0].ResourceName}'

# Use IAM Access Analyzer to find unintended external access
aws accessanalyzer create-analyzer \
  --analyzer-name account-analyzer \
  --type ACCOUNT

aws accessanalyzer list-findings \
  --analyzer-name account-analyzer \
  --output table

# IAM Policy Simulator - test a policy before deploying
aws iam simulate-custom-policy \
  --policy-input-list file://my-policy.json \
  --action-names s3:GetObject s3:DeleteBucket sqs:DeleteQueue \
  --resource-arns arn:aws:s3:::my-bucket/data.csv \
  --output table
```

```python
import boto3
import json
from datetime import datetime, timezone, timedelta

iam = boto3.client('iam')
cloudtrail = boto3.client('cloudtrail', region_name='us-east-1')

def audit_role_permissions(role_name: str, days: int = 30):
    """
    Identify which IAM actions a role has actually used in the past N days.
    Compares used actions against attached policies to find unused permissions.
    """
    # Get all actions used by this role in CloudTrail
    start_time = datetime.now(timezone.utc) - timedelta(days=days)
    
    used_actions = set()
    paginator = cloudtrail.get_paginator('lookup_events')
    
    for page in paginator.paginate(
        LookupAttributes=[
            {'AttributeKey': 'Username', 'AttributeValue': role_name}
        ],
        StartTime=start_time
    ):
        for event in page['Events']:
            used_actions.add(event['EventName'])
    
    print(f"Actions used by {role_name} in the last {days} days:")
    for action in sorted(used_actions):
        print(f"  {action}")
    
    # Get attached policies to compare
    attached = iam.list_attached_role_policies(RoleName=role_name)
    print(f"\nAttached policies: {[p['PolicyName'] for p in attached['AttachedPolicies']]}")
    print("Cross-reference these policies against the used actions to identify unused permissions")
    
    return used_actions


# Example: create a tightly scoped policy from observed actions
def create_minimal_policy(role_name: str, bucket_name: str) -> dict:
    """
    Create a policy granting only the specific S3 actions used in production.
    """
    used_actions = audit_role_permissions(role_name)
    
    # Filter to only S3 actions
    s3_actions = [f"s3:{a}" for a in used_actions if a.startswith('GetObject') or
                  a.startswith('PutObject') or a.startswith('ListBucket')]
    
    if not s3_actions:
        print("No S3 actions detected - check the role name and time range")
        return {}
    
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "S3ObjectAccess",
                "Effect": "Allow",
                "Action": [a for a in s3_actions if 'Bucket' not in a],
                "Resource": f"arn:aws:s3:::{bucket_name}/*"
            },
            {
                "Sid": "S3BucketAccess",
                "Effect": "Allow",
                "Action": [a for a in s3_actions if 'Bucket' in a or a == 's3:ListBucket'],
                "Resource": f"arn:aws:s3:::{bucket_name}"
            }
        ]
    }
    
    # Remove empty statements
    policy['Statement'] = [s for s in policy['Statement'] if s['Action']]
    return policy
```

---

## How It Connects

Least privilege is the design philosophy that guides every IAM policy decision. It is not a separate system - it is the practice of applying IAM correctly. Every other IAM note in this layer should be read with this principle in mind.

[[iam-policies|IAM Policies]] - the mechanism for implementing least privilege; understanding policy structure is required to write narrow, specific policies rather than broad ones.

[[iam-roles|IAM Roles]] - the primary entity to which least-privilege policies are attached for application code; each Lambda function and EC2 instance role should be narrowly scoped.

The Access Analyzer and CloudTrail are the observability tools for verifying that least privilege is maintained over time as applications evolve.

[[cloudwatch|CloudWatch]] - monitoring and alerting infrastructure that can be configured to alert on unexpected IAM actions, complementing the Access Analyzer for ongoing least-privilege enforcement.

---

## Common Misconceptions

Misconception 1: "I'll start with AdministratorAccess and lock it down once the app is working."
Reality: Permission tightening never happens in practice. The "working" application becomes a production dependency, and removing permissions in production requires testing each removal carefully to avoid breaking live users. Organisations that start with AdministratorAccess remain with it indefinitely. The correct approach is the reverse: start with no permissions, add them one by one as the application is developed and tested, and deploy the production role with only the confirmed-needed permissions.

Misconception 2: "Using `s3:*` on a specific bucket is fine - it is still scoped to one resource."
Reality: `s3:*` on a specific bucket grants not just read and write but also the ability to delete all objects, change the bucket's public access settings, modify the bucket policy, enable cross-account access, and enable public ACLs. Most applications need two or three specific S3 actions. Granting all of them on the bucket exposes operations that could permanently delete data or make the bucket publicly accessible if the role is compromised. Enumerate the specific actions needed: `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` - and nothing else.

Misconception 3: "Least privilege makes development harder - developers should have broad permissions to move fast."
Reality: Developers should have broader permissions in development accounts; production roles should be narrowly scoped. These are different environments with different risk profiles. A CI/CD pipeline deploying to production uses a deployment role scoped to the exact actions needed for that deployment, not a developer's personal broad-access credentials. Least privilege in production does not impede development speed when the principle is applied at the environment boundary rather than at the individual developer level.

---

## Why It Matters in Production

The blast radius concept is why least privilege matters in practice. A compromised credential with `AdministratorAccess` on a Lambda function means an attacker has full control of the AWS account - they can create new IAM users, delete data, access secrets, launch mining instances, and exfiltrate everything. A compromised credential for a Lambda function with `s3:GetObject` on one specific bucket means an attacker can read the contents of that bucket and nothing else. The security posture of the entire account is different, and the incident response is a contained data exposure rather than a full account compromise.

Least privilege also reduces the impact of bugs. A Python application with a bug that accidentally calls `s3:DeleteObject` instead of `s3:GetObject` is stopped by an `AccessDenied` error if the role does not have delete permission. The same bug in a role with `s3:*` succeeds silently and deletes data. Narrow permissions act as a second layer of defence against application errors, not just against security incidents.

---

## What Breaks in Production

**Scenario 1: Lambda function with overly broad permissions exfiltrates data via SSRF vulnerability.**

```bash
# Audit all Lambda execution roles for overly broad permissions
aws lambda list-functions --query 'Functions[*].{Name:FunctionName,Role:Role}' --output table

# For each role, check for broad policies
aws iam list-attached-role-policies \
  --role-name my-overpermissioned-role \
  --output table
# If you see AdministratorAccess, AmazonS3FullAccess, etc. - investigate

# Replace with minimal policy
aws iam detach-role-policy \
  --role-name my-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-role-policy \
  --role-name my-lambda-role \
  --policy-arn arn:aws:iam::123456789012:policy/lambda-minimal-s3-policy
```

**Scenario 2: Wildcard resource in policy allows access to all buckets in all accounts.**

```json
// Wrong: allows s3:GetObject on all objects in all buckets
{
  "Effect": "Allow",
  "Action": "s3:GetObject",
  "Resource": "*"
}

// Right: restrict to specific bucket
{
  "Effect": "Allow",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::my-application-bucket/*"
}
```

```bash
# Find policies with wildcard resources in your account
aws iam list-policies --scope Local --output json | \
  python3 -c "
import sys, json
policies = json.load(sys.stdin)['Policies']
for p in policies:
    print(p['PolicyName'], p['Arn'])
" 
# Then review each policy's document for wildcard resources
```

**Scenario 3: Unused permissions removed in production break an infrequently-called code path.**

```python
# When tightening permissions, simulate all code paths - not just the happy path
# Use the IAM policy simulator for every action the code might call

import boto3

iam = boto3.client('iam')
sts = boto3.client('sts')
account_id = sts.get_caller_identity()['Account']

# Test all actions before removing permissions
actions_to_test = [
    's3:GetObject',
    's3:PutObject',
    's3:ListBucket',
    's3:DeleteObject',   # only used in the cleanup path - verify if needed
    's3:GetBucketAcl',   # may be called by some SDK versions automatically
]

result = iam.simulate_principal_policy(
    PolicySourceArn=f'arn:aws:iam::{account_id}:role/my-lambda-role',
    ActionNames=actions_to_test,
    ResourceArns=['arn:aws:s3:::my-bucket/test.txt']
)

for eval_result in result['EvaluationResults']:
    action = eval_result['EvalActionName']
    decision = eval_result['EvalDecision']
    print(f"{action}: {decision}")
    if decision == 'allowed' and action == 's3:DeleteObject':
        print("  WARNING: delete permission is granted - confirm if required")
```

---

## Interview Angle

Common question forms:
- "How do you apply least privilege in practice when you do not know all the permissions your code needs?"
- "What tools does AWS provide for identifying unused permissions?"
- "How do you balance developer velocity with security?"

Answer frame:
Start broad during development, use CloudTrail and IAM Access Advisor to observe actual usage, then create a customer managed policy with only the observed actions scoped to specific resources. For ongoing enforcement: IAM Access Analyzer detects external access and overly permissive resource policies; permission boundaries prevent privilege escalation even when IAM management is delegated. For balancing velocity and security: broad permissions in development accounts, narrow permissions in production, enforced through separate accounts and deployment pipelines.

---

## Related Notes

- [[iam-policies|IAM Policies]]
- [[iam-roles|IAM Roles]]
- [[iam-overview|IAM Overview]]
- [[iam-users-groups|IAM Users and Groups]]
- [[secret-management|Secret Management]]
