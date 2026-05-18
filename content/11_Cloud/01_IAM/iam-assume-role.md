---
title: Assuming IAM Roles (STS)
description: Assuming a role means exchanging your current credentials for temporary credentials scoped to that role's permissions — this is the mechanism for cross-account access, privilege scoping, and third-party delegation in AWS.
tags: [aws, cloud, layer-11, iam, sts, assume-role]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# Assuming IAM Roles (STS)

> Role assumption via STS is the mechanism that powers cross-account access, least-privilege scoping, and secure third-party delegation — it is the most important IAM operation beyond basic policy attachment.

---

## Quick Reference

**Core idea:**
- `sts:AssumeRole` exchanges your current credentials for temporary credentials (AccessKeyId, SecretAccessKey, SessionToken) scoped to the target role's permissions
- The returned credentials are valid for 15 minutes (minimum) to 12 hours (maximum, depends on `MaxSessionDuration` set on the role)
- `RoleSessionName` is a required string that appears in CloudTrail logs — use a meaningful name identifying the calling context
- The `SessionToken` is a third credential component required alongside the key ID and secret; omitting it causes authentication failure
- Cross-account assumption: the role must exist in the target account, and the trust policy must allow the calling account/principal
- External IDs add a shared secret to the trust policy, preventing confused deputy attacks when third parties assume your role

**Tricky points:**
- You cannot assume a role that your current credentials do not have `sts:AssumeRole` permission for — this is often the source of "not authorized to perform sts:AssumeRole" errors
- The calling entity must be listed in the role's trust policy `Principal` field — having `sts:AssumeRole` permission is necessary but not sufficient; the trust policy is an independent gatekeeper
- Session duration cannot exceed the role's `MaxSessionDuration` setting — requesting a duration longer than this silently gets clamped to the maximum, or raises an error (behaviour varies)
- Temporary credentials from an assumed role cannot be used to assume certain roles that explicitly deny assumed-role principals
- For Lambda and EC2, explicit AssumeRole is usually unnecessary — the execution role is assumed automatically by the runtime

---

## What It Is

Think of role assumption as a counter at a government office where you exchange one form of identification for a temporary visitor badge with specific access permissions. You walk in with your employee ID (your current credentials), tell the counter staff which department you need access to (the target role ARN), and they issue you a time-limited badge (temporary credentials) that opens only the doors that department is allowed to open. Your employee ID remains valid — you have not surrendered it. You are now holding two forms of access simultaneously, but you use the temporary badge for work in that department. When the badge expires, you return to the counter if you need more time.

The cross-account application of role assumption is one of AWS's most powerful access patterns. Consider a company with multiple AWS accounts: a centralised security account, a development account, and a production account. The security team operates from the security account. To audit the production account, they do not need permanent credentials in the production account — they need a role in the production account whose trust policy allows the security account to assume it. The security team members call `sts:AssumeRole` with the production account's auditor role ARN, receive temporary production-account credentials, perform their audit, and the credentials expire. No permanent access keys exist in the production account for the security team; the access is temporary, logged in CloudTrail, and scoped to the auditor role's permissions.

The External ID is a lesser-known feature designed for a specific security problem called the confused deputy attack. When a third party (an external monitoring service, a data partner) needs to assume a role in your account, you share the role ARN with them. But what prevents them from using your role ARN to access another customer's account by accident or malice? The External ID is a shared secret — a unique value you define and put in the trust policy's Condition block. The third party must pass this exact value when calling AssumeRole, or the assumption is rejected. It prevents one customer's service configuration from accidentally granting another customer's access.

---

## How It Actually Works

The `sts:AssumeRole` API call requires the role ARN and a session name. AWS evaluates whether the calling entity is listed in the role's trust policy and whether the calling entity has `sts:AssumeRole` permission in their own policies. If both checks pass, STS generates a set of temporary credentials: a new Access Key ID (starting with `ASIA` rather than the permanent user `AKIA`), a Secret Access Key, a Session Token, and an Expiration timestamp. These three credential components plus the expiry are returned in the API response and must all be used together.

The session name appears in CloudTrail events as the assumed-role session identifier. When an action is taken with assumed-role credentials, CloudTrail records it as `arn:aws:sts::ACCOUNT:assumed-role/ROLE-NAME/SESSION-NAME`. Choosing meaningful session names — the function name, the CI build ID, the username of the operator — makes incident investigation dramatically faster, because CloudTrail events tell you not just that the role was used but which specific invocation of which process used it.

```bash
# Assume a role and print the temporary credentials
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/cross-account-reader \
  --role-session-name audit-session-2026-05-18 \
  --duration-seconds 3600

# Assume a role with an External ID (required for third-party roles)
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/third-party-integration \
  --role-session-name monitoring-agent \
  --external-id unique-customer-identifier-abc123

# Use the assumed role credentials for subsequent CLI calls
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/deploy-role \
  --role-session-name ci-deploy \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SessionToken'])")

# Now CLI commands use the assumed role
aws sts get-caller-identity  # should show the assumed role ARN

# Check what roles your current identity can assume (look for sts:AssumeRole in policies)
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/developer \
  --action-names sts:AssumeRole \
  --resource-arns arn:aws:iam::123456789012:role/deploy-role \
  --output table
```

```python
import boto3
from botocore.exceptions import ClientError

def assume_role(role_arn: str, session_name: str, duration_seconds: int = 3600):
    """
    Assume an IAM role and return a boto3 Session using its temporary credentials.
    
    Args:
        role_arn: The ARN of the role to assume
        session_name: Identifier for this session (appears in CloudTrail)
        duration_seconds: How long the credentials should be valid (900-43200)
    
    Returns:
        boto3.Session configured with the assumed role's credentials
    """
    sts = boto3.client('sts')
    
    try:
        response = sts.assume_role(
            RoleArn=role_arn,
            RoleSessionName=session_name,
            DurationSeconds=duration_seconds
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'AccessDenied':
            raise PermissionError(
                f"Current identity cannot assume role {role_arn}. "
                "Check that the role's trust policy allows the caller and "
                "that the caller has sts:AssumeRole permission."
            )
        raise
    
    creds = response['Credentials']
    return boto3.Session(
        aws_access_key_id=creds['AccessKeyId'],
        aws_secret_access_key=creds['SecretAccessKey'],
        aws_session_token=creds['SessionToken'],  # required — do not omit
        region_name='us-east-1'
    )


# Cross-account S3 access example
cross_account_session = assume_role(
    role_arn='arn:aws:iam::987654321098:role/data-reader',
    session_name=f'ingestion-job-2026-05-18',
    duration_seconds=3600
)
s3 = cross_account_session.client('s3', region_name='us-east-1')
response = s3.list_objects_v2(Bucket='partner-data-bucket')
for obj in response.get('Contents', []):
    print(obj['Key'])

# Verify the assumed identity
sts_assumed = cross_account_session.client('sts')
identity = sts_assumed.get_caller_identity()
print(f"Operating as: {identity['Arn']}")
# arn:aws:sts::987654321098:assumed-role/data-reader/ingestion-job-2026-05-18


# Role assumption with External ID (for third-party integrations)
sts = boto3.client('sts')
response = sts.assume_role(
    RoleArn='arn:aws:iam::123456789012:role/monitoring-integration',
    RoleSessionName='datadog-integration',
    ExternalId='customer-specific-external-id-xyz',
    DurationSeconds=3600
)
creds = response['Credentials']
monitoring_client = boto3.client(
    'cloudwatch',
    aws_access_key_id=creds['AccessKeyId'],
    aws_secret_access_key=creds['SecretAccessKey'],
    aws_session_token=creds['SessionToken']
)
```

---

## How It Connects

Role assumption is the mechanism that makes IAM roles useful outside of the automatic execution-environment cases. Understanding the automatic case (Lambda, EC2) and the explicit case (STS AssumeRole) together gives the complete picture.

[[iam-roles|IAM Roles]] — the IAM entity being assumed; the trust policy on the role is what permits assumption, and the permissions policy determines what the assumed session can do.

[[iam-role-python|IAM Roles with Python (boto3)]] — how boto3 uses IAM roles automatically on Lambda and EC2; the complement to this note's explicit assumption scenario.

Least privilege applies to assumed-role sessions too — scoping what each session can do limits the damage if credentials are compromised.

[[iam-least-privilege|Principle of Least Privilege]] — the design principle that determines how narrowly to scope the permissions policy on each role you create for assumption.

---

## Common Misconceptions

Misconception 1: "Assuming a role requires admin permissions."
Reality: Assuming a specific role requires only `sts:AssumeRole` permission scoped to that role's ARN, plus being listed in the role's trust policy. Neither admin permissions nor any AWS managed policy is required. A minimal policy allowing assumption of one specific role looks like: `{"Effect": "Allow", "Action": "sts:AssumeRole", "Resource": "arn:aws:iam::123456789012:role/specific-role"}`. This is a deliberately narrow permission.

Misconception 2: "I can chain role assumptions indefinitely to escalate privileges."
Reality: Role chaining is permitted (you can assume role A, then from that session assume role B), but it has restrictions. The maximum session duration for a chained assumption is 1 hour regardless of the original role's `MaxSessionDuration`. AWS Service Control Policies can restrict role chaining entirely. And the chained sessions must each be explicitly permitted in each role's trust policy — you cannot chain through a role unless that role explicitly trusts the previous assumed-role session.

Misconception 3: "The External ID is a password — keeping it secret is what makes the role secure."
Reality: The External ID is a coordination mechanism, not a secret. Its purpose is to prevent a confused deputy attack — where an attacker tricks a third-party service into using your role ARN against a different account. The External ID is unique per customer relationship. The security comes from its uniqueness per customer, not its secrecy. If the External ID is compromised along with the role ARN, the protection is lost — which is why External IDs are one layer of a defence-in-depth strategy, not the only defence.

---

## Why It Matters in Practice

Cross-account role assumption is the foundation of multi-account AWS architectures, which are increasingly the standard for organisations with more than a handful of engineers. In a well-structured AWS organisation, developers work in a development account, pipelines deploy to a staging account, and only a deployment role can push to production — assumed by the CI/CD system with short-lived credentials. Data pipelines in one account read from another account's S3 buckets by assuming a cross-account reader role. Security and compliance tools in a central account audit all other accounts by assuming auditor roles. None of this requires sharing access keys between accounts.

For Python developers, the practical skill is writing the `assume_role` wrapper correctly — always passing the session token, choosing meaningful session names, handling the AccessDenied case with a clear error message, and building sessions from the returned credentials rather than passing raw credential dictionaries to each client. Getting these details wrong is a source of intermittent authentication failures that are difficult to diagnose because the error messages from boto3 do not always indicate which credential component is missing or wrong.

---

## What Breaks in Production

**Scenario 1: Session token omitted when constructing boto3 client from assumed-role credentials.**

```python
creds = sts.assume_role(
    RoleArn='arn:aws:iam::123456789012:role/my-role',
    RoleSessionName='my-session'
)['Credentials']

# Wrong: omits session token — request fails with InvalidClientTokenId
s3 = boto3.client(
    's3',
    aws_access_key_id=creds['AccessKeyId'],
    aws_secret_access_key=creds['SecretAccessKey']
    # session token missing!
)

# Right: include all three credential components
s3 = boto3.client(
    's3',
    aws_access_key_id=creds['AccessKeyId'],
    aws_secret_access_key=creds['SecretAccessKey'],
    aws_session_token=creds['SessionToken']  # required
)
```

**Scenario 2: Assumed-role credentials cached beyond expiry, causing sporadic failures.**

```python
import boto3
from datetime import datetime, timezone

# Wrong: cache credentials without checking expiry
cached_creds = None

def get_client():
    global cached_creds
    if cached_creds is None:
        response = boto3.client('sts').assume_role(
            RoleArn='arn:aws:iam::123456789012:role/my-role',
            RoleSessionName='cached-session'
        )
        cached_creds = response['Credentials']
    return boto3.client('s3', **{
        'aws_access_key_id': cached_creds['AccessKeyId'],
        'aws_secret_access_key': cached_creds['SecretAccessKey'],
        'aws_session_token': cached_creds['SessionToken']
    })

# Right: check expiry before using cached credentials
from datetime import timedelta

def get_client_with_refresh():
    global cached_creds
    now = datetime.now(timezone.utc)
    expiry = cached_creds['Expiration'] if cached_creds else now
    
    if cached_creds is None or expiry - now < timedelta(minutes=5):
        response = boto3.client('sts').assume_role(
            RoleArn='arn:aws:iam::123456789012:role/my-role',
            RoleSessionName='refreshable-session',
            DurationSeconds=3600
        )
        cached_creds = response['Credentials']
    
    return boto3.client('s3',
        aws_access_key_id=cached_creds['AccessKeyId'],
        aws_secret_access_key=cached_creds['SecretAccessKey'],
        aws_session_token=cached_creds['SessionToken']
    )
```

**Scenario 3: Cross-account role assumption fails because calling account not in trust policy.**

```bash
# Check the trust policy of the target role
aws iam get-role \
  --role-name cross-account-reader \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json
# If the calling account ARN is not in Principal, assumption will be denied

# Update the trust policy to add the calling account
aws iam update-assume-role-policy \
  --role-name cross-account-reader \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/calling-role"
      },
      "Action": "sts:AssumeRole"
    }]
  }'
```

---

## Interview Angle

Common question forms:
- "How does cross-account access work in AWS?"
- "What is the confused deputy problem and how does External ID solve it?"
- "When would you explicitly assume a role versus using an attached execution role?"

Answer frame:
Cross-account access: create a role in the target account, add the source account or specific principal to the trust policy, grant `sts:AssumeRole` in the calling entity's policy. The calling entity then calls `sts:AssumeRole` and uses the temporary credentials for target-account operations. Confused deputy: a third party with your role ARN could accidentally assume a different customer's role with the same ARN structure — External ID makes each customer relationship unique. Explicit AssumeRole is used for cross-account access and privilege scoping; automatic role assumption (no explicit AssumeRole call) is used by Lambda, EC2, ECS runtimes.

---

## Related Notes

- [[iam-roles|IAM Roles]]
- [[iam-role-python|IAM Roles with Python (boto3)]]
- [[iam-overview|IAM Overview]]
- [[iam-least-privilege|Principle of Least Privilege]]
