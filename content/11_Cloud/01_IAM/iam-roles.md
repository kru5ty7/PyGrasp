---
title: 09 - IAM Roles
description: IAM roles provide temporary credentials to AWS services, applications, and cross-account identities — they are the preferred alternative to long-term access keys for any code running on AWS.
tags: [aws, cloud, layer-11, iam, roles]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# IAM Roles

> IAM roles are temporary, assumable identities — understanding them is what allows you to write AWS-integrated Python code that works securely in any environment without a single hardcoded credential.

---

## Quick Reference

**Core idea:**
- A role is an IAM identity with no permanent credentials — it issues temporary credentials (15 min to 12 hours) via STS when assumed
- Every role has two policies: a trust policy (who can assume it) and a permissions policy (what the role can do)
- AWS services (Lambda, EC2, ECS, Glue) assume roles automatically — boto3 picks up the temporary credentials with no configuration
- `sts:AssumeRole` is the API action called when any entity assumes a role
- Trust policies use `Principal` to specify who is allowed to assume the role: `"Service": "lambda.amazonaws.com"`, `"AWS": "arn:aws:iam::123456789:user/alice"`
- The assumed role's credentials include an `AccessKeyId`, `SecretAccessKey`, and `SessionToken` — all three are required

**Tricky points:**
- A role cannot assume itself — circular role assumptions are not permitted
- Session duration for role assumption defaults to 1 hour but can be set up to the role's `MaxSessionDuration` (default 1 hour, max 12 hours)
- The `SessionToken` from an assumed role is required in boto3; omitting it causes `InvalidClientTokenId` errors
- Cross-account role assumption requires explicit permission in both the trust policy (on the role) and an IAM policy on the assuming entity
- Lambda execution roles cannot be changed while the function is running — changes take effect on the next cold start (within seconds for most cases)

---

## What It Is

Think of an IAM role as a temporary security badge dispensed by a kiosk at the entrance to a facility. Unlike a permanent employee badge that belongs to a specific person, this kiosk badge is generic — it grants access to a defined set of rooms for a limited time, after which it expires and becomes worthless. The kiosk only issues the badge to visitors who present the right invitation (the trust policy determines who qualifies). A contractor who needs access to the server room for three hours gets a badge that expires in three hours. When the badge expires, they cannot get in again until they return to the kiosk and the kiosk issues a new one — and the kiosk keeps records of every issuance.

The critical insight about roles is that there are no static credentials to steal or rotate. When a Lambda function assumes its execution role, the credentials it receives are valid for at most 12 hours and are automatically refreshed. If an attacker extracts these credentials from a running Lambda function, they have a limited window before the credentials expire and new credentials are issued with a different access key ID. This is fundamentally more secure than a static access key that remains valid indefinitely until someone manually rotates it. The credential lifecycle is managed by AWS, not by you, and that automation is the security benefit.

For Python developers, roles eliminate the credential management problem entirely for code running on AWS. A Lambda function, EC2 instance, or ECS task does not need an access key in its environment variables or configuration files. It assumes a role, and boto3 automatically retrieves the temporary credentials from the instance metadata service or the Lambda environment. The Python code is identical whether it runs on a developer's laptop (where it might use a personal credentials file) or in production (where it uses an IAM role) — the credential resolution logic in boto3 handles the difference transparently.

---

## How It Actually Works

Every IAM role stores two policy documents: the trust policy and the permissions policy. The trust policy (also called the assume role policy) defines who is allowed to call `sts:AssumeRole` for this role. The `Principal` field in the trust policy specifies the allowed principals: an AWS service (`"Service": "lambda.amazonaws.com"`), a specific IAM user or role (`"AWS": "arn:aws:iam::123456789:user/alice"`), or an entire AWS account (`"AWS": "arn:aws:iam::123456789012:root"`). The permissions policy attached to the role defines what actions the role can take once assumed — it works identically to permissions attached to a user.

When an AWS service like Lambda assumes a role, it calls `sts:AssumeRole` on behalf of the function during its execution environment setup. The returned credentials are stored in the Lambda execution environment and exposed via environment variables that boto3 reads automatically. For EC2, the assumed-role credentials are available at the Instance Metadata Service (IMDS) endpoint `http://169.254.254.254/latest/meta-data/iam/security-credentials/ROLE-NAME`. boto3 polls this endpoint to refresh credentials before they expire — your code does not need to handle this.

```bash
# Create a trust policy document for a Lambda role
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role with the trust policy
aws iam create-role \
  --role-name my-lambda-role \
  --assume-role-policy-document file://trust-policy.json \
  --description "Execution role for my Lambda function"

# Attach an AWS managed policy
aws iam attach-role-policy \
  --role-name my-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Attach a customer managed policy for S3 access
aws iam attach-role-policy \
  --role-name my-lambda-role \
  --policy-arn arn:aws:iam::123456789012:policy/MyS3AppPolicy

# List all policies attached to the role
aws iam list-attached-role-policies --role-name my-lambda-role --output table

# View the full role including trust policy
aws iam get-role --role-name my-lambda-role

# Assign the role to an existing Lambda function
aws lambda update-function-configuration \
  --function-name my-function \
  --role arn:aws:iam::123456789012:role/my-lambda-role

# Verify the role can be assumed (check trust policy is correct)
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/my-lambda-role \
  --role-session-name test-session
# If trust policy only allows lambda.amazonaws.com, this CLI call will fail
# with "is not authorised to assume role" — that is correct and expected
```

```python
import boto3
import json

iam = boto3.client('iam')

# Create a role with its trust policy programmatically
trust_policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}

role_response = iam.create_role(
    RoleName='my-app-lambda-role',
    AssumeRolePolicyDocument=json.dumps(trust_policy),
    Description='Execution role for my application Lambda function',
    MaxSessionDuration=3600  # 1 hour (default)
)
role_arn = role_response['Role']['Arn']
print(f"Created role: {role_arn}")

# Attach the Lambda basic execution policy (for CloudWatch Logs)
iam.attach_role_policy(
    RoleName='my-app-lambda-role',
    PolicyArn='arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'
)

# Create and attach a custom S3 policy
s3_policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject"],
            "Resource": "arn:aws:s3:::my-app-bucket/*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::my-app-bucket"
        }
    ]
}

policy_response = iam.create_policy(
    PolicyName='my-app-s3-policy',
    PolicyDocument=json.dumps(s3_policy)
)
iam.attach_role_policy(
    RoleName='my-app-lambda-role',
    PolicyArn=policy_response['Policy']['Arn']
)

# When running on Lambda, boto3 uses the role automatically — no configuration needed
s3 = boto3.client('s3')  # credentials come from Lambda's execution role
response = s3.list_objects_v2(Bucket='my-app-bucket')
```

---

## How It Connects

Roles are the mechanism by which all IAM policies become useful for application code. The note on how boto3 uses roles explains the practical behaviour — how boto3 picks up the role credentials automatically without configuration.

[[iam-role-python|IAM Roles with Python (boto3)]] — the concrete behaviour of boto3 when running on Lambda, EC2, or ECS with an attached IAM role; the practical implementation of what this note explains conceptually.

Assuming a role from Python code — for cross-account access or privilege escalation — uses the STS `AssumeRole` API, which is a separate operation from the automatic role assumption that Lambda and EC2 do.

[[iam-assume-role|Assuming IAM Roles (STS)]] — how to explicitly assume a role from Python code using STS, for cross-account and manual privilege scenarios.

IAM policies define what the role can do once assumed. A role without a permissions policy can be assumed but cannot perform any actions.

[[iam-policies|IAM Policies]] — the permission documents attached to roles that define what an assumed role is authorised to do.

---

## Common Misconceptions

Misconception 1: "An IAM role is like an IAM user — it has its own access keys that I manage."
Reality: Roles have no permanent credentials. They have no password and no static access key. When a role is assumed, STS generates temporary credentials with an expiry time. These credentials cannot be viewed in the IAM console, cannot be rotated by you, and expire automatically. The permanent credentials for a role consist only of the role's ARN and the trust policy defining who may assume it.

Misconception 2: "The permissions policy on the role is the only thing that controls what it can do."
Reality: The permissions policy on the role defines the maximum permissions. But the effective permissions are further constrained by permission boundaries (if any are set on the role), Session Policies (if passed during AssumeRole), and Service Control Policies from AWS Organizations. A permissions policy that grants `AdministratorAccess` on a role with a permission boundary of `AmazonS3ReadOnlyAccess` results in effective permissions of only S3 read access.

Misconception 3: "I can create one generic Lambda role for all my Lambda functions to simplify management."
Reality: Sharing a single role across all Lambda functions violates least privilege. If one Lambda function's code is compromised (through a dependency vulnerability or injection), the attacker has the permissions of the shared role — which includes permissions for functions that should not have been accessible. Each Lambda function should have its own role with exactly the permissions it needs.

---

## Why It Matters in Practice

The shift from access keys to IAM roles is not a stylistic preference — it is a security architecture decision. In every major AWS security incident involving credential theft, the stolen credentials were long-term access keys, not temporary IAM role credentials. This is not a coincidence: long-term keys persist after they are stolen, can be used from anywhere in the world, and remain valid until manually rotated. Temporary credentials from IAM roles expire, are bound to the execution environment (through STS session information), and are automatically refreshed.

For Python developers, roles also simplify deployment. Code that uses IAM roles works the same way in every environment where boto3 can find credentials — on a developer's machine using a named profile, in a CI/CD pipeline using an assumed role, and in production on Lambda or EC2 using the attached role. There is no need for environment-specific configuration of credentials, no need to manage credential rotation, and no risk of credentials appearing in application logs or error messages.

---

## What Breaks in Production

**Scenario 1: Lambda function missing a required IAM action — discovered only in production.**

```bash
# Test the exact permissions of a role before deploying
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/my-lambda-role \
  --action-names s3:GetObject s3:PutObject lambda:InvokeFunction sqs:SendMessage \
  --resource-arns \
    arn:aws:s3:::my-bucket/test.txt \
    arn:aws:lambda:us-east-1:123456789012:function:downstream-function \
    arn:aws:sqs:us-east-1:123456789012:my-queue \
  --output table
```

**Scenario 2: Trust policy missing allows a service to assume role, Lambda gets "not authorised" error.**

```python
import boto3
import json

iam = boto3.client('iam')

# Check the current trust policy
role = iam.get_role(RoleName='my-lambda-role')
trust_policy = role['Role']['AssumeRolePolicyDocument']
print(json.dumps(trust_policy, indent=2))

# If lambda.amazonaws.com is missing from Principal.Service, add it
trust_policy['Statement'][0]['Principal']['Service'] = 'lambda.amazonaws.com'

iam.update_assume_role_policy(
    RoleName='my-lambda-role',
    PolicyDocument=json.dumps(trust_policy)
)
```

**Scenario 3: Role assumed in one region used to call a service in a different region — region mismatch.**

```python
import boto3

sts = boto3.client('sts', region_name='us-east-1')
creds = sts.assume_role(
    RoleArn='arn:aws:iam::123456789012:role/cross-region-role',
    RoleSessionName='migration-task'
)['Credentials']

# Wrong: client region defaults to the region where the role was assumed
s3_wrong = boto3.client(
    's3',
    aws_access_key_id=creds['AccessKeyId'],
    aws_secret_access_key=creds['SecretAccessKey'],
    aws_session_token=creds['SessionToken']
    # no region_name — may default to us-east-1 when bucket is in eu-west-1
)

# Right: always specify the target region explicitly
s3_correct = boto3.client(
    's3',
    region_name='eu-west-1',  # explicit region for the target resource
    aws_access_key_id=creds['AccessKeyId'],
    aws_secret_access_key=creds['SecretAccessKey'],
    aws_session_token=creds['SessionToken']
)
```

---

## Interview Angle

Common question forms:
- "What is the difference between an IAM role and an IAM user?"
- "How do you give a Lambda function permission to access S3?"
- "Explain the trust policy and why it is needed."

Answer frame:
Users have permanent credentials; roles have temporary credentials issued per-assumption. A role has two policies: the trust policy (who can call AssumeRole for this role — e.g., `lambda.amazonaws.com`) and the permissions policy (what actions the role may take). For Lambda and S3: create a role with `lambda.amazonaws.com` in the trust policy and an S3-scoped permissions policy, then assign it as the Lambda execution role. boto3 picks up the role's temporary credentials automatically from the Lambda execution environment.

---

## Related Notes

- [[iam-overview|IAM Overview]]
- [[iam-policies|IAM Policies]]
- [[iam-role-python|IAM Roles with Python (boto3)]]
- [[iam-assume-role|Assuming IAM Roles (STS)]]
- [[iam-instance-profile|EC2 Instance Profiles]]
- [[iam-least-privilege|Principle of Least Privilege]]
