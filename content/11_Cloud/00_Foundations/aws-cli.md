---
title: AWS CLI
description: The AWS CLI is the command-line interface for interacting with AWS services — essential for scripting, automation, and verifying what your Python code does.
tags: [aws, cloud, layer-11, cli, tooling]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# AWS CLI

> The AWS CLI translates terminal commands into signed API calls — every operation you can perform in the AWS Console can be scripted, and fluency with the CLI is what separates developers who guess at their deployments from those who verify them.

---

## Quick Reference

**Core idea:**
- Install: `pip install awscli` (v1) or download the official installer (v2 — recommended)
- Configure: `aws configure` — sets access key, secret key, default region, output format
- Credentials stored in `~/.aws/credentials`; config (region, output) in `~/.aws/config`
- Command pattern: `aws <service> <action> [--options]`
- Output formats: `json` (default, scriptable), `text` (tab-separated), `table` (human-readable)
- `--query` accepts JMESPath expressions to filter output; `--output table` for readability
- Named profiles: `aws configure --profile myprofile` then `aws s3 ls --profile myprofile`
- Environment variables override credentials file: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`

**Tricky points:**
- CLI v2 and v1 behave differently for binary inputs and some commands — check which version is installed with `aws --version`
- `--dry-run` is supported only for specific EC2 operations — it is not a universal flag
- Credentials in `~/.aws/credentials` are stored in plaintext — on shared machines, environment variables or IAM roles are safer
- The configured `default` profile is used when no `--profile` is specified — on developer machines with multiple accounts this is a common source of accidental operations in the wrong account
- JMESPath queries are case-sensitive and must match exact field names from the API response

---

## What It Is

Think of the AWS Console as a graphical cockpit — it is intuitive for exploration but slow for repetitive work. Every action in the console (clicking "Create bucket", "Launch instance", "Add policy") translates to an API call behind the scenes. The AWS CLI exposes those same API calls as terminal commands. Instead of navigating five pages in a browser to find all S3 buckets, you type `aws s3 ls` and get the answer in under a second. Instead of clicking through a wizard to launch an EC2 instance, you write a shell script that launches identical instances every time, in any environment.

The deeper value of the CLI is verifiability. When debugging a production issue at midnight, you cannot rely on the console's visual presentation to tell you the exact state of an IAM policy or the precise configuration of a security group. The CLI returns structured data — JSON, text, or table — that you can pipe into `jq`, store in a variable, or diff against a previous state. It makes the implicit explicit. Running `aws sts get-caller-identity` before any significant operation tells you exactly which account and identity your commands will affect — a habit that prevents catastrophic operations in the wrong account.

For Python developers, the CLI and boto3 are complementary tools. The CLI is faster for ad-hoc investigation and script-level automation. boto3 is better for application logic, error handling, and integration with Python code. A practical workflow: use the CLI to experiment and verify the API behaviour, then translate the confirmed operation into a boto3 call in your application. The `--output json` and `--query` flags make the CLI's output directly comparable to what boto3 returns as Python dictionaries.

---

## How It Actually Works

The AWS CLI is built on top of botocore — the same library that boto3 uses. When you run a CLI command, botocore constructs a signed HTTP request using the SigV4 signing algorithm, which creates a cryptographic signature from your credentials and the request content. This signature is included in the request headers, allowing AWS to verify both your identity and that the request has not been tampered with in transit. The CLI then sends the request to the appropriate regional endpoint, parses the response, and formats it according to your `--output` setting.

Credentials are resolved in this order: command-line options (`--profile`) → environment variables (`AWS_ACCESS_KEY_ID` etc.) → the `default` profile in `~/.aws/credentials` → IAM instance profile (when running on EC2/Lambda). This order matters because a misconfigured environment variable silently overrides your credentials file, which can cause operations to run as the wrong identity.

```bash
# Install CLI v2 on Linux/macOS (download from AWS, not pip)
# On Windows: use the MSI installer from AWS

# Check version
aws --version  # Should be 2.x.x for CLI v2

# Initial configuration (interactive)
aws configure

# Configure a named profile
aws configure --profile prod-account

# Show the current resolved configuration
aws configure list

# Verify which identity is active (do this before any significant operation)
aws sts get-caller-identity

# Use a named profile for a single command
aws s3 ls --profile prod-account

# Common operations
aws s3 ls                                          # list all buckets
aws s3 ls s3://my-bucket/                         # list bucket contents
aws ec2 describe-instances --output table         # list EC2 instances
aws lambda list-functions --output json           # list Lambda functions

# Filter output with JMESPath
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,IP:PublicIpAddress}' \
  --output table

# Paginate through large result sets
aws s3api list-objects-v2 \
  --bucket my-bucket \
  --max-items 100 \
  --starting-token <token-from-previous-call>

# Use --dry-run to test EC2 permissions without executing
aws ec2 run-instances \
  --image-id ami-12345678 \
  --instance-type t3.micro \
  --dry-run
```

```python
import subprocess
import json

# Running CLI commands from Python (useful for scripts where boto3 is overkill)
result = subprocess.run(
    ['aws', 'sts', 'get-caller-identity', '--output', 'json'],
    capture_output=True,
    text=True,
    check=True
)
identity = json.loads(result.stdout)
print(f"Running as: {identity['Arn']}")

# More commonly, use boto3 directly — but the CLI verifies the same identity
import boto3
sts = boto3.client('sts')
identity = sts.get_caller_identity()
print(f"Running as: {identity['Arn']}")
```

---

## How It Connects

The CLI and boto3 share the same underlying library (botocore) and the same credential resolution logic. Understanding how the CLI resolves credentials explains how boto3 resolves them in your Python applications.

[[boto3-basics|boto3 Basics]] — the Python SDK that uses the same credential resolution order and underlying botocore library as the CLI.

The CLI is the fastest way to verify IAM permissions before writing application code. Running a CLI command and getting an access denied error tells you exactly what policy change is needed.

[[iam-overview|IAM Overview]] — IAM controls what every CLI command and boto3 call is authorised to do.

Credentials configured via `aws configure` affect all AWS tools on the machine — understanding their storage and priority order is essential for multi-account setups.

[[iam-users-groups|IAM Users and Groups]] — the IAM users whose access keys are stored in `~/.aws/credentials`.

---

## Common Misconceptions

Misconception 1: "The AWS CLI and the AWS Console do different things."
Reality: Both are wrappers around the same AWS API. Every console action maps to an API call, and every API call can be made from the CLI. The console is a graphical interface; the CLI is a programmatic one. Some newer features appear in the console first before the CLI is updated, but the underlying capability is identical.

Misconception 2: "The `--dry-run` flag works for all AWS CLI commands."
Reality: `--dry-run` is an EC2-specific feature for a subset of EC2 operations (like `run-instances`, `stop-instances`). It checks whether you have the required IAM permissions without executing the action. For other services, there is no equivalent — the IAM policy simulator is the correct tool for testing permissions without executing actions.

Misconception 3: "Setting `AWS_DEFAULT_REGION` in my shell overrides the region in `~/.aws/config`."
Reality: This is true and is intentional. Environment variables take precedence over the credentials file. The problem is that if a developer sets this variable in their shell profile and forgets about it, every CLI command in that shell — including commands they intended to run in the configured default region — uses the environment variable's value. Always run `aws configure list` to see the active configuration when debugging unexpected region behaviour.

---

## Why It Matters in Practice

The CLI is the fastest debugging tool available when something goes wrong with AWS. When a Lambda function cannot write to S3, the first step is not reading IAM documentation — it is running `aws s3 cp test.txt s3://my-bucket/test.txt` with the same credentials the Lambda uses. If it fails with `Access Denied`, the problem is confirmed as an IAM issue. If it succeeds, the problem is in the application code. This binary verification loop is faster than any other approach.

The CLI also serves as the ground truth for infrastructure state. The AWS Console has been known to display stale data, especially during updates and in regions under load. The CLI queries the API directly and returns the current state. For operations like verifying a security group rule is active, confirming a deployment succeeded, or checking whether a certificate has been issued, the CLI gives you reliable data in a scriptable format.

---

## What Breaks in Production

**Scenario 1: Wrong profile used in CI/CD, production resources modified accidentally.**

```bash
# Wrong: relying on default profile in CI where multiple profiles exist
aws s3 sync ./dist s3://my-bucket/

# Right: explicitly specify the account/role in CI via environment variables
# In CI pipeline configuration:
# AWS_ACCESS_KEY_ID: ${{ secrets.PROD_AWS_ACCESS_KEY_ID }}
# AWS_SECRET_ACCESS_KEY: ${{ secrets.PROD_AWS_SECRET_ACCESS_KEY }}
# AWS_DEFAULT_REGION: us-east-1

# Or better: use assume-role with a CI role
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/ci-deploy-role \
  --role-session-name ci-deployment
```

**Scenario 2: JMESPath query returns None silently when field name changes between API versions.**

```bash
# Fragile: field name 'PublicIpAddress' is absent for instances without a public IP
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].PublicIpAddress'
# Returns [null] for private-only instances — not an error, silently wrong

# Robust: use conditional and default
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,IP:PublicIpAddress || `none`}' \
  --output table
```

**Scenario 3: Credentials file checked into version control.**

```bash
# Check for accidentally staged credentials before committing
git diff --cached ~/.aws/credentials  # never commit this file

# Add to .gitignore globally
git config --global core.excludesfile ~/.gitignore_global
echo "*.pem" >> ~/.gitignore_global
echo ".aws/credentials" >> ~/.gitignore_global
```

---

## Interview Angle

Common question forms:
- "How do you manage multiple AWS accounts in your CLI setup?"
- "Walk me through how you would debug an IAM permission issue."
- "What is the difference between AWS CLI v1 and v2?"

Answer frame:
For multiple accounts, named profiles plus `AWS_PROFILE` environment variable per project is the standard approach. For IAM debugging, the workflow is: `aws sts get-caller-identity` to confirm identity → run the failing CLI command to get the exact error code → use IAM policy simulator or CloudTrail to identify which policy evaluation denied the action → add the minimum required permission. CLI v2 adds SSO support, better binary handling, and `aws configure import` for bulk profile setup — v1 is still common in older CI environments.

---

## Related Notes

- [[boto3-basics|boto3 Basics]]
- [[iam-overview|IAM Overview]]
- [[iam-users-groups|IAM Users and Groups]]
- [[aws-overview|AWS Overview]]
