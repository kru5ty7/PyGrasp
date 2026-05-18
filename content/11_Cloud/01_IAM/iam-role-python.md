---
title: IAM Roles with Python (boto3)
description: When Python code runs on Lambda, EC2, or ECS with an IAM role attached, boto3 automatically retrieves temporary credentials from the execution environment — no access keys in code or environment variables required.
tags: [aws, cloud, layer-11, iam, boto3, roles]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# IAM Roles with Python (boto3)

> The combination of IAM roles and boto3's automatic credential resolution means your Python application code never needs to handle AWS credentials directly — understanding this mechanism is what allows you to write secure, environment-portable AWS code.

---

## Quick Reference

**Core idea:**
- boto3 credential resolution order: explicit params → env vars (`AWS_ACCESS_KEY_ID` etc.) → `~/.aws/credentials` → AWS SSO → instance metadata (IMDS) → ECS task metadata → Lambda environment
- On Lambda: credentials injected via `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` environment variables automatically
- On EC2: credentials served at `http://169.254.169.254/latest/meta-data/iam/security-credentials/` (IMDS)
- `aws sts get-caller-identity` — verify which identity boto3 is using before debugging
- Never hardcode credentials; never commit `.env` files with credentials; never log credentials
- Use `boto3.Session(profile_name='my-profile')` for local multi-account development

**Tricky points:**
- If `AWS_ACCESS_KEY_ID` is set in the environment, it overrides the IAM role — a leftover local env var silently prevents the production role from being used during local testing
- Lambda refreshes credentials automatically when they expire — you do not need to handle `ExpiredTokenException` from the role; if you see it, your function has been running longer than the session duration
- The `AWS_SESSION_TOKEN` from an assumed role is required — a boto3 client created without it will fail even if the access key and secret are correct
- ECS task roles and EC2 instance profiles are different mechanisms for the same concept — both provide temporary credentials via metadata endpoints that boto3 queries automatically

---

## What It Is

Imagine writing a Python application that needs to send emails. Instead of embedding your email password in the source code, the server you deploy to already has a configured outgoing mail relay — your application just calls `send_mail()` without knowing any credentials. The server's operating environment handles the authentication. IAM roles work the same way for AWS. Your Python code calls `boto3.client('s3')` and makes API calls. The execution environment (Lambda, EC2, ECS) has already obtained temporary AWS credentials from IAM and made them available to your process. boto3 finds those credentials automatically. Your application code is decoupled from credential management entirely.

This decoupling is not merely convenient — it is architecturally significant. Code that does not contain credentials cannot leak them. A Lambda function's source code, when deployed to GitHub, contains no secrets. The IAM role that grants the function its permissions is configured separately in AWS infrastructure, outside the code repository. An attacker who reads the code learns nothing about the credentials, because the credentials do not exist until the function is invoked and are different every time. Compare this to a pattern where access keys are stored in environment variables: the keys are static, visible in the deployment configuration, and valid until manually rotated.

For local development, boto3 follows the same credential resolution order but falls through to different sources. On a developer's laptop, there is no Lambda execution environment and no EC2 instance metadata service. boto3 looks first at environment variables, then at the `~/.aws/credentials` file (populated by `aws configure`), then at named profiles. This means the same Python code works locally (using developer credentials) and in production (using an IAM role) without any code changes — only the credentials source changes.

---

## How It Actually Works

boto3 uses a credential provider chain — a sequence of locations it checks in order until it finds valid credentials. The full chain, in priority order, is: explicit parameters passed to the `Session` or `client` constructor → environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) → the `~/.aws/credentials` file → the `~/.aws/config` file → SSO credentials → assume role with web identity (for EKS/OIDC) → EC2 instance metadata (IMDS) → ECS task metadata. The first source that provides credentials wins.

On Lambda, AWS injects the execution role's temporary credentials directly into the function's environment variables before invocation. boto3 reads `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` from the environment and uses them. The Lambda runtime rotates these credentials before they expire and updates the environment variables — your function code never sees expired credentials unless it caches them in a module-level variable and the module stays alive across a credential rotation (a rare but real issue for long-running warm functions).

On EC2, credentials are served by the Instance Metadata Service at a well-known link-local address. boto3 queries this endpoint automatically when no higher-priority credential source is available. The endpoint responds with temporary credentials that expire in approximately one hour, along with an expiry timestamp. boto3 caches the credentials and re-queries the endpoint a few minutes before expiry.

```python
import boto3
from botocore.exceptions import NoCredentialsError, ClientError

# This code works identically on Lambda (uses role), EC2 (uses instance profile),
# and locally (uses ~/.aws/credentials or env vars)
s3 = boto3.client('s3')

# Verify which identity is being used — useful for debugging
sts = boto3.client('sts')
identity = sts.get_caller_identity()
print(f"Account: {identity['Account']}")
print(f"Identity ARN: {identity['Arn']}")
# On Lambda: arn:aws:sts::123456789012:assumed-role/my-lambda-role/function-name
# Locally: arn:aws:iam::123456789012:user/developer-alice

# Explicit Session for local multi-account development
session_dev = boto3.Session(profile_name='dev-account')
session_prod = boto3.Session(profile_name='prod-account-readonly')
s3_dev = session_dev.client('s3')
s3_prod = session_prod.client('s3')

# Check the resolved credentials (for debugging — never log these in production)
credentials = boto3.Session().get_credentials()
resolved = credentials.resolve()
print(f"Credential method: {type(resolved).__name__}")
# On Lambda: AssumedRoleCredential
# Locally: SharedCredentialProvider or EnvProvider

# Guard against missing credentials in scripts
try:
    sts.get_caller_identity()
except NoCredentialsError:
    raise SystemExit(
        "No AWS credentials found. Run 'aws configure' or attach an IAM role."
    )
```

```bash
# Verify the active identity before running a deployment script
aws sts get-caller-identity

# Switch profile for a single command
AWS_PROFILE=prod-account aws s3 ls

# Verify the Lambda function's execution role
aws lambda get-function-configuration \
  --function-name my-function \
  --query 'Role'

# Check if a Lambda function can reach S3 (simulate from the role)
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/my-lambda-role \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::my-bucket/test.txt \
  --output table

# List the policies on the Lambda execution role
aws iam list-attached-role-policies \
  --role-name my-lambda-role \
  --output table
```

---

## How It Connects

This note describes the practical behaviour of boto3 on AWS infrastructure. The IAM roles note explains the IAM model; this note explains what boto3 does with it. Both are required for a complete understanding.

[[iam-roles|IAM Roles]] — the IAM entity that boto3 uses when running on AWS; the trust policy and permissions policy that make automatic credential resolution possible.

[[boto3-basics|boto3 Basics]] — the full credential resolution chain and general boto3 patterns; this note is a specialisation of boto3 basics focused on the IAM role scenario.

When you need to assume a role explicitly from Python code (for cross-account access or targeted privilege escalation), that is a different mechanism covered in the STS note.

[[iam-assume-role|Assuming IAM Roles (STS)]] — explicit role assumption from Python code, distinct from the automatic role pickup that happens on Lambda and EC2.

---

## Common Misconceptions

Misconception 1: "I need to pass credentials to boto3 for it to work on Lambda."
Reality: On Lambda with an execution role attached, boto3 automatically reads temporary credentials from the environment variables that AWS injects. Passing explicit credentials to boto3 on Lambda is not only unnecessary but counterproductive — it hardcodes credentials that expire while the role credentials are automatically rotated. `boto3.client('s3')` with no arguments is the correct pattern on Lambda.

Misconception 2: "My code works locally with my developer credentials, so it will work the same way in Lambda."
Reality: The permissions attached to your personal IAM user (used locally) are different from the permissions attached to the Lambda execution role. Code that reads from an S3 bucket successfully on your laptop (because your developer IAM user has S3 access) may fail on Lambda if the execution role does not have the same S3 permissions. Always test against the actual Lambda execution role's permissions, not your personal permissions.

Misconception 3: "Setting `AWS_ACCESS_KEY_ID` in a Lambda function's environment variables is a valid way to provide credentials."
Reality: Setting static access key environment variables on a Lambda function overrides the execution role's temporary credentials, defeats automatic credential rotation, and creates a long-lived credential that requires manual management. If you see `AWS_ACCESS_KEY_ID` in a Lambda's environment variables (not the runtime-injected ones, but manually configured ones), that is a security anti-pattern. The execution role is the correct mechanism.

---

## Why It Matters in Practice

The automatic credential resolution mechanism is what allows Python code to be deployed to multiple environments — development, staging, production — without environment-specific credential configuration. A function that calls `boto3.client('s3')` without any configuration picks up the right credentials in every environment because each environment has the appropriate credentials source (personal credentials file locally, IAM role in AWS). Breaking this pattern by hardcoding credentials or setting them explicitly creates an environment-specific code path that must be maintained separately.

The credential resolution order also determines the security incident surface. If an attacker compromises a Lambda function, they can read the function's environment variables and find the injected temporary credentials. These credentials expire within the session duration. If the same function had been configured with static access key environment variables, those credentials would remain valid until manually rotated — giving the attacker persistent access long after the initial compromise is discovered and patched.

---

## What Breaks in Production

**Scenario 1: Cached boto3 client holds expired credentials from a previous invocation — fails after long Lambda function idle periods.**

```python
# Wrong: module-level client with no credential refresh handling
# Fine for short-lived functions but credentials can expire across very long warm periods
s3 = boto3.client('s3')  # credentials captured at module load time

def handler(event, context):
    return s3.list_buckets()  # may use expired credentials after 12+ hours warm

# Right: boto3 handles this automatically for most cases, but if you cache
# the credentials object itself, refresh explicitly
import boto3

def handler(event, context):
    # boto3.client() at the module level is actually fine — boto3 refreshes
    # credentials automatically. Never cache credentials.resolve() or the
    # raw credentials dict at module level.
    s3 = boto3.client('s3')  # re-uses cached client with auto-refreshed creds
    return s3.list_buckets()
```

**Scenario 2: Local env var `AWS_ACCESS_KEY_ID` overrides Lambda execution role during testing.**

```python
import os
import boto3

# Detect if running locally vs in Lambda
def is_running_in_lambda() -> bool:
    return bool(os.environ.get('AWS_LAMBDA_FUNCTION_NAME'))

# Check what credentials are being used before a test run
sts = boto3.client('sts')
identity = sts.get_caller_identity()
arn = identity['Arn']

if 'assumed-role' not in arn and not is_running_in_lambda():
    print(f"WARNING: Running as {arn} (not a Lambda execution role)")
    print("Local credentials may differ from production role permissions")
```

**Scenario 3: Lambda function in VPC cannot reach IMDS to refresh credentials.**

```bash
# Lambda in a VPC needs either:
# 1. A VPC endpoint for STS (preferred — keeps traffic private)
# 2. A NAT Gateway with internet access to reach the public STS endpoint

# Create VPC endpoint for STS to allow credential refresh without internet
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345678 \
  --service-name com.amazonaws.us-east-1.sts \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-az1 subnet-az2 \
  --security-group-ids sg-lambda

# Lambda functions in VPC use environment variable credentials (not IMDS)
# but still need to call STS to refresh them — VPC endpoint ensures this works
```

---

## Interview Angle

Common question forms:
- "How does boto3 find AWS credentials when running on Lambda?"
- "What is the credential resolution order in boto3?"
- "How do you test Lambda permissions locally?"

Answer frame:
On Lambda, AWS injects temporary IAM role credentials as environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`). boto3 reads these automatically from the environment. The full resolution order is explicit params → env vars → credentials file → instance metadata. To test Lambda permissions locally, use `aws iam simulate-principal-policy` with the Lambda role's ARN to verify each required action is allowed, then test with `AWS_PROFILE` pointing to credentials that mimic the role's permissions.

---

## Related Notes

- [[iam-roles|IAM Roles]]
- [[boto3-basics|boto3 Basics]]
- [[iam-assume-role|Assuming IAM Roles (STS)]]
- [[iam-instance-profile|EC2 Instance Profiles]]
- [[lambda-iam|Lambda IAM]]
