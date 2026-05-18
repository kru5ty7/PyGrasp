---
title: 13 - EC2 Instance Profiles
description: An instance profile is a container for an IAM role that attaches the role to an EC2 instance, allowing code running on the instance to call AWS APIs without any access keys.
tags: [aws, cloud, layer-11, iam, ec2, instance-profile]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# EC2 Instance Profiles

> An EC2 instance profile is the mechanism that gives an EC2 instance an identity — without one, code running on the instance cannot call AWS APIs; with one, boto3 retrieves credentials automatically from the instance metadata service.

---

## Quick Reference

**Core idea:**
- An instance profile is a container for exactly one IAM role — it is the linkage between an EC2 instance and an IAM role
- Creating a role via the Console for EC2 automatically creates the instance profile with the same name
- Creating a role via the CLI/API requires creating the instance profile separately and adding the role to it
- Credentials served at `http://169.254.169.254/latest/meta-data/iam/security-credentials/<role-name>` (IMDSv1)
- IMDSv2 (preferred, more secure) requires a session token obtained from `PUT http://169.254.169.254/latest/api/token`
- boto3 queries IMDS automatically and refreshes credentials before expiry — application code needs no special handling
- Instance profile can be attached or replaced without stopping the instance; new credentials appear within seconds

**Tricky points:**
- Instance profiles and IAM roles are separate IAM objects — when using the CLI, you must create both and link them explicitly
- IMDSv1 is a Server-Side Request Forgery (SSRF) attack vector — a web app that fetches URLs from user input can be tricked into fetching `http://169.254.169.254/` and returning AWS credentials. IMDSv2 requires a prior PUT request, which most SSRF attacks cannot perform
- Requiring IMDSv2 is a one-line configuration at instance launch but breaks applications that use the IMDS SDK before they support the session-token model
- An instance can only have one instance profile attached at a time
- Modifying the role attached to an instance profile takes effect within ~30 seconds — running processes continue using cached credentials until they refresh

---

## What It Is

Think of an instance profile as the employment record that a factory worker carries when they enter a secure facility. The worker (the EC2 instance) arrives at the gate and presents their employment record (the instance profile). The employment record references their job title and clearance level (the IAM role). The security desk (AWS STS) looks up what that clearance level permits and issues a time-limited access badge (temporary credentials). The worker carries that badge and uses it every time they need to open a secure door (make an AWS API call). When the badge expires, the worker returns to the gate and the desk issues a fresh one automatically — the worker never needs to ask.

The Instance Metadata Service (IMDS) is the gate in this analogy. It is a special HTTP endpoint reachable only from within the EC2 instance at the link-local IP address `169.254.169.254`. Only code running on the instance can reach this endpoint — it is not accessible from the internet, from other instances, or from outside AWS. The endpoint exposes not just credentials but also the instance's own metadata: its instance ID, AMI ID, region, availability zone, hostname, public and private IP addresses, and security groups. boto3 uses this endpoint to retrieve credentials and the instance's region automatically when no other credential source is configured.

IMDSv2 (Instance Metadata Service version 2) was introduced in 2019 as a security hardening measure. The original IMDS (IMDSv1) has a vulnerability: any code on the instance that makes HTTP GET requests to user-controlled URLs could be tricked into fetching `http://169.254.169.254/latest/meta-data/iam/security-credentials/` and returning the result to an attacker. This is an SSRF (Server-Side Request Forgery) attack, and it has been used in real credential theft incidents. IMDSv2 mitigates this by requiring a preliminary PUT request with a TTL to obtain a session token, which is then required in the GET header. Standard SSRF payloads make GET requests and cannot perform the initial PUT — so they cannot obtain the session token needed to read the credentials endpoint.

---

## How It Actually Works

When an EC2 instance is launched with an instance profile, the AWS hypervisor makes the instance's assumed-role credentials available through the IMDS. The credentials at the IMDS endpoint are refreshed automatically before they expire — typically every hour. When boto3 creates a client without explicit credentials, its credential resolution chain eventually reaches the IMDS provider, which queries `http://169.254.169.254/latest/meta-data/iam/security-credentials/<role-name>` (IMDSv1) or the equivalent IMDSv2 flow. The response is a JSON object containing `AccessKeyId`, `SecretAccessKey`, `Token`, and `Expiration`. boto3 caches these credentials and re-queries the endpoint when the expiry approaches.

For IMDSv2, boto3 handles the session token acquisition automatically when the IMDS endpoint requires it. If an instance is configured to require IMDSv2 (the recommended configuration), boto3 sends a PUT request to obtain a session token and includes that token in subsequent IMDS requests. Application code does not need to change to support IMDSv2 — boto3 handles the protocol difference transparently.

```bash
# Launch an EC2 instance with an instance profile
aws ec2 run-instances \
  --image-id ami-12345678 \
  --instance-type t3.micro \
  --iam-instance-profile Name=my-instance-profile \
  --metadata-options HttpEndpoint=enabled,HttpTokens=required \
  # HttpTokens=required enforces IMDSv2

# Create an instance profile (when using CLI — Console does this automatically)
aws iam create-instance-profile \
  --instance-profile-name my-app-profile

# Add the role to the instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name my-app-profile \
  --role-name my-ec2-app-role

# Attach profile to a running instance (no restart required)
aws ec2 associate-iam-instance-profile \
  --instance-id i-1234567890abcdef0 \
  --iam-instance-profile Name=my-app-profile

# Replace the profile on a running instance
aws ec2 replace-iam-instance-profile-association \
  --iam-instance-profile Name=new-app-profile \
  --association-id iip-assoc-1234567890

# Verify the profile attached to a running instance
aws ec2 describe-instances \
  --instance-ids i-1234567890abcdef0 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'

# From inside the EC2 instance — query IMDS directly (IMDSv2)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --silent)
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/iam/security-credentials/" --silent
# Returns the role name, then:
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/iam/security-credentials/my-ec2-app-role" --silent
```

```python
import boto3
import urllib.request
import json

# boto3 queries IMDS automatically — no configuration required
# This works on any EC2 instance with an attached instance profile
s3 = boto3.client('s3')
response = s3.list_buckets()
print([b['Name'] for b in response['Buckets']])

# Verify credentials source (useful for debugging)
session = boto3.Session()
credentials = session.get_credentials()
resolved = credentials.resolve()
print(f"Credential class: {type(resolved).__name__}")
# On EC2 with instance profile: InstanceMetadataFetcher or similar

# Manually query IMDS (IMDSv2) to verify the attached role and credentials
# This is what boto3 does internally — shown here for transparency
def get_instance_metadata_token(ttl_seconds: int = 21600) -> str:
    req = urllib.request.Request(
        'http://169.254.169.254/latest/api/token',
        method='PUT',
        headers={'X-aws-ec2-metadata-token-ttl-seconds': str(ttl_seconds)}
    )
    with urllib.request.urlopen(req, timeout=1) as response:
        return response.read().decode('utf-8')

def get_instance_credentials(role_name: str) -> dict:
    token = get_instance_metadata_token()
    req = urllib.request.Request(
        f'http://169.254.169.254/latest/meta-data/iam/security-credentials/{role_name}',
        headers={'X-aws-ec2-metadata-token': token}
    )
    with urllib.request.urlopen(req, timeout=1) as response:
        return json.loads(response.read().decode('utf-8'))

# Get current region from instance metadata
def get_instance_region() -> str:
    token = get_instance_metadata_token()
    req = urllib.request.Request(
        'http://169.254.169.254/latest/meta-data/placement/region',
        headers={'X-aws-ec2-metadata-token': token}
    )
    with urllib.request.urlopen(req, timeout=1) as response:
        return response.read().decode('utf-8')

# Enforce IMDSv2 at instance launch via boto3
ec2 = boto3.client('ec2', region_name='us-east-1')
ec2.run_instances(
    ImageId='ami-12345678',
    InstanceType='t3.micro',
    MinCount=1,
    MaxCount=1,
    IamInstanceProfile={'Name': 'my-app-profile'},
    MetadataOptions={
        'HttpEndpoint': 'enabled',
        'HttpTokens': 'required',    # IMDSv2 required
        'HttpPutResponseHopLimit': 1  # prevents containers on the instance from accessing IMDS
    }
)
```

---

## How It Connects

Instance profiles are the EC2-specific implementation of the same concept that Lambda execution roles implement for serverless — they give the execution environment an IAM identity without requiring access keys in application code.

[[iam-roles|IAM Roles]] — the IAM role that an instance profile contains; the trust policy on the role must allow `ec2.amazonaws.com` to assume it.

[[iam-role-python|IAM Roles with Python (boto3)]] — how boto3 picks up credentials from the IMDS in the same credential resolution chain that handles Lambda and local credentials.

EC2 overview covers the full lifecycle of instances — instance profiles are one part of the security configuration that should be set at launch.

[[ec2-overview|EC2 Overview]] — the compute service that instance profiles attach to; understanding instance lifecycle helps understand when profile changes take effect.

---

## Common Misconceptions

Misconception 1: "Instance profiles and IAM roles are the same thing."
Reality: An instance profile is a container object that holds exactly one IAM role. They are separate IAM resource types with separate ARNs. When you create a role with the EC2 use case in the AWS Console, AWS creates both the role and the instance profile with matching names — which makes them appear identical. When you create a role via the AWS CLI or CloudFormation, you must explicitly create the instance profile and add the role to it as a separate step, or your `run-instances` command will fail with "Instance profile not found."

Misconception 2: "IMDSv2 breaks my application — I should disable it and use IMDSv1."
Reality: Modern versions of boto3 (1.9.91+), the AWS CLI v2, and the AWS SDKs for other languages all support IMDSv2 automatically. If your application is failing with IMDSv2 required, the fix is to update the SDK/library version, not to downgrade the IMDS security setting. Disabling IMDSv2 (leaving IMDSv1 available) leaves the instance vulnerable to SSRF-based credential theft, which is a known attack vector with real-world incidents behind it.

Misconception 3: "Detaching an instance profile immediately revokes the instance's AWS access."
Reality: When an instance profile is detached, the IMDS endpoint stops serving credentials, but credentials that were already retrieved and cached by running processes remain valid until they expire — typically up to one hour. For immediate revocation, invalidate the credentials by revoking the session through a policy change (add a Deny for all actions to the role, or use an IAM session policy), not just by detaching the profile.

---

## Why It Matters in Production

Instance profiles are the secure foundation for any Python application running on EC2. Without an instance profile, developers default to storing access keys in environment variables or configuration files on the instance — keys that survive snapshots, are visible to any process on the machine, are included in AMI copies, and require manual rotation. Every production EC2 instance that runs code calling AWS services should have an instance profile with a narrowly scoped role; this is not a best practice but a baseline requirement.

The IMDSv2 requirement is increasingly a compliance and security baseline. The AWS Foundational Security Best Practices standard (managed by AWS Security Hub) includes a check for IMDSv2 compliance. CIS AWS Foundations Benchmark includes it. Several real-world data breaches at major companies have involved IMDS credentials obtained via SSRF. Enforcing IMDSv2 at the organisation level (via AWS Organizations SCP preventing instance launches without `HttpTokens=required`) is a one-time configuration that eliminates this entire attack class.

---

## What Breaks in Production

**Scenario 1: EC2 role created via CLI without creating the instance profile — launch fails.**

```bash
# Wrong: creating role only (CLI does not auto-create instance profile)
aws iam create-role \
  --role-name my-ec2-role \
  --assume-role-policy-document file://ec2-trust.json

# Then run-instances fails: "Invalid IAM Instance Profile name"

# Right: also create the instance profile and link them
aws iam create-instance-profile \
  --instance-profile-name my-ec2-profile

aws iam add-role-to-instance-profile \
  --instance-profile-name my-ec2-profile \
  --role-name my-ec2-role

# Wait for propagation (IAM eventual consistency)
aws iam get-instance-profile --instance-profile-name my-ec2-profile

aws ec2 run-instances \
  --iam-instance-profile Name=my-ec2-profile \
  ...
```

**Scenario 2: Code running in a container on EC2 can reach IMDS and use the instance's full role.**

```python
# Container on EC2 shares the instance's network namespace
# and can reach IMDS unless explicitly blocked

# When running containers on EC2, set hop limit to 1 to prevent containers
# from accessing IMDS (requires IMDSv2 with hop limit)
ec2 = boto3.client('ec2')
ec2.run_instances(
    ...,
    MetadataOptions={
        'HttpEndpoint': 'enabled',
        'HttpTokens': 'required',
        'HttpPutResponseHopLimit': 1  # hop limit 1 = instance only, not containers
        # containers need hop limit 2 to reach IMDS
        # set to 2 only if containers legitimately need IMDS access
        # For ECS/EKS, use task roles instead of instance credentials for containers
    }
)
```

**Scenario 3: Instance profile change not reflected because running Python process cached old credentials.**

```python
# boto3 automatically refreshes credentials before expiry,
# but if you extract the raw credential values and store them,
# they become stale after ~1 hour.

# Wrong: extract and store raw credentials
session = boto3.Session()
creds = session.get_credentials().resolve()
access_key = creds.access_key  # cached static value — becomes stale

# Right: use boto3 clients and sessions — they handle refresh internally
s3 = boto3.client('s3')  # boto3 refreshes credentials transparently
# Each API call through this client uses current, valid credentials
```

---

## Interview Angle

Common question forms:
- "How does an EC2 instance get AWS credentials without access keys?"
- "What is IMDSv2 and why does it matter?"
- "What is the difference between an IAM role and an instance profile?"

Answer frame:
An instance profile is a container for an IAM role that can be attached to an EC2 instance. When attached, the instance's metadata service (IMDS) serves temporary credentials for the role, which boto3 retrieves automatically. IMDSv2 adds a required session token obtained via a preliminary PUT request — this defeats most SSRF attacks by requiring a request method that SSRF tools cannot perform. An IAM role and instance profile are separate objects; the Console creates both together, but the CLI requires creating them separately. Always enforce IMDSv2 and set the hop limit appropriately for the use case.

---

## Related Notes

- [[iam-roles|IAM Roles]]
- [[iam-role-python|IAM Roles with Python (boto3)]]
- [[iam-least-privilege|Principle of Least Privilege]]
- [[ec2-overview|EC2 Overview]]
- [[iam-overview|IAM Overview]]
