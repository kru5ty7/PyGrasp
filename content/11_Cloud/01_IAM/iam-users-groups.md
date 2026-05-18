---
title: 07 - IAM Users and Groups
description: IAM users are long-term identities for people or applications, and groups are collections of users that share permissions — both are the human-facing side of IAM access management.
tags: [aws, cloud, layer-11, iam, users, groups]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# IAM Users and Groups

> IAM users and groups manage human access to AWS — but the most important thing to know is when not to use them: application code running on AWS should use IAM roles, not users with access keys.

---

## Quick Reference

**Core idea:**
- An IAM user is a named identity with long-term credentials: a password (console) and/or access keys (programmatic)
- A group is a named collection of users — attach policies to the group, all members inherit them
- Best practice: one IAM user per human, never share users across people
- Access keys come in pairs: `AKIA...` (access key ID) and a secret (shown only once at creation)
- `aws iam list-access-keys --user-name alice` — shows all keys and their status
- MFA (Multi-Factor Authentication) should be required for all users — especially those with admin access
- IAM supports up to 10 groups per user and up to 300 groups per account

**Tricky points:**
- Access keys are long-lived — they remain valid indefinitely until explicitly deactivated or deleted; there is no automatic expiry
- The secret access key is displayed only once at creation; if lost, a new key must be created (the old one cannot be recovered)
- Groups cannot contain other groups — IAM groups are flat
- An IAM user's console password and programmatic access keys are completely separate — disabling one does not affect the other
- "Service accounts" (access keys used by applications) should be replaced with IAM roles wherever possible; if a service account key is necessary (e.g., for on-premises code), rotate it regularly and audit its usage

---

## What It Is

Think of an IAM user as a company ID card. Each card has the employee's name, a photo (the user's ARN), and magnetic stripes or chips that grant access to specific areas (the attached policies). The card has two types of access codes: a PIN for the front-door keypad (the console password) and a swipe credential for automated systems (the programmatic access key). When the employee leaves the company, you deactivate the card, not the doors. An IAM group is like a department — attach a "Finance Team" badge supplement and every member of the Finance department automatically gains access to the finance systems.

The groups model solves the organisational problem of managing permissions at scale. Without groups, granting S3 read access to twenty developers means attaching the same policy twenty times to twenty different users. When the policy needs to change, you update it twenty times. With a group named "Developers," you attach the policy once, add all twenty users to the group, and a single policy update applies to everyone instantly. Groups are collections of users with a shared permission set — they have no credentials of their own and cannot be nested.

Service accounts — IAM users created for applications rather than humans — represent the most commonly misused pattern in AWS. A developer who needs a Python script to access S3 creates an IAM user, generates an access key, pastes it into a `.env` file, and ships the code. This works, but it creates a long-lived credential that must be rotated manually, can be leaked in a repository, and provides no automatic expiry. The correct pattern for any code running on AWS infrastructure is an IAM role, which provides automatically rotating temporary credentials without any key management. Access keys for service accounts should be reserved for code that runs outside AWS (on-premises servers, developer machines during testing) and should be rotated at least every 90 days.

---

## How It Actually Works

IAM users exist in the AWS global namespace within a specific account. Their ARN is `arn:aws:iam::ACCOUNT-ID:user/username`. When a user makes a programmatic API call with access keys, AWS uses the access key ID to look up the account and user, verifies the request signature using the secret access key, and then evaluates all attached policies (directly attached user policies + group policies) to determine whether the action is authorised.

Access key rotation is a critical operational discipline. The IAM Access Advisor shows when each permission was last used, and the Credential Report (a CSV file AWS generates for the account) lists every user, their password last used date, access key creation dates, and last-used dates. Unused keys are a security risk — an attacker who finds an old, forgotten key has access until it is explicitly deactivated.

```bash
# Create a new IAM user
aws iam create-user --user-name developer-alice

# Create a console password (requires --password-reset-required for first login)
aws iam create-login-profile \
  --user-name developer-alice \
  --password 'Temp#Pass1234' \
  --password-reset-required

# Create programmatic access keys (secret shown once — save it immediately)
aws iam create-access-key --user-name developer-alice

# List all access keys for a user and their status
aws iam list-access-keys --user-name developer-alice

# Check when each key was last used
aws iam get-access-key-last-used --access-key-id AKIAIOSFODNN7EXAMPLE

# Deactivate (not delete) a key — preserves it for investigation
aws iam update-access-key \
  --user-name developer-alice \
  --access-key-id AKIAIOSFODNN7EXAMPLE \
  --status Inactive

# Delete a key permanently
aws iam delete-access-key \
  --user-name developer-alice \
  --access-key-id AKIAIOSFODNN7EXAMPLE

# Create a group
aws iam create-group --group-name Developers

# Attach an AWS managed policy to the group
aws iam attach-group-policy \
  --group-name Developers \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess

# Add a user to a group
aws iam add-user-to-group \
  --group-name Developers \
  --user-name developer-alice

# List users in a group
aws iam get-group --group-name Developers

# Generate the account's credential report (CSV — all users, key ages, last used)
aws iam generate-credential-report
aws iam get-credential-report --output text --query 'Content' | base64 --decode
```

```python
import boto3
import csv
import base64
import io
from datetime import datetime, timezone

iam = boto3.client('iam')

# Generate and parse the credential report to find stale access keys
iam.generate_credential_report()

import time
while True:
    response = iam.get_credential_report()
    if response.get('Content'):
        break
    time.sleep(2)

csv_content = response['Content'].decode('utf-8')
reader = csv.DictReader(io.StringIO(csv_content))

now = datetime.now(timezone.utc)
stale_threshold_days = 90

for row in reader:
    user = row['user']
    for key_num in ['1', '2']:
        key_last_used = row.get(f'access_key_{key_num}_last_used_date', 'N/A')
        key_active = row.get(f'access_key_{key_num}_active', 'false')
        
        if key_active == 'true' and key_last_used not in ('N/A', 'no_information'):
            last_used = datetime.fromisoformat(key_last_used.replace('Z', '+00:00'))
            days_since = (now - last_used).days
            if days_since > stale_threshold_days:
                print(f"STALE KEY: {user} access_key_{key_num} last used {days_since} days ago")

# List all users and their attached policies
paginator = iam.get_paginator('list_users')
for page in paginator.paginate():
    for user in page['Users']:
        username = user['UserName']
        policies = iam.list_attached_user_policies(UserName=username)
        group_response = iam.list_groups_for_user(UserName=username)
        groups = [g['GroupName'] for g in group_response['Groups']]
        print(f"{username}: policies={[p['PolicyName'] for p in policies['AttachedPolicies']]}, groups={groups}")
```

---

## How It Connects

IAM users are only one of four IAM entity types. Understanding when to use users versus roles is the key IAM decision for Python developers. The note on roles explains the preferred alternative for application code.

[[iam-roles|IAM Roles]] — the alternative to service-account access keys for any code running on AWS infrastructure; roles provide automatic credential rotation and no key management burden.

Policies define what users (and groups, and roles) can do. User management and policy management are separate concerns in IAM — this separation allows the same policy to be attached to multiple users, groups, or roles.

[[iam-policies|IAM Policies]] — the JSON permission documents attached to users, groups, and roles; understanding policy structure is required to configure users securely.

The IAM overview establishes the full entity model — users and groups are the human-facing part of a larger system.

[[iam-overview|IAM Overview]] — the broader IAM model that users and groups fit into, including roles and policies.

---

## Common Misconceptions

Misconception 1: "I should create one IAM user for my entire development team to share."
Reality: Shared IAM users make audit trails useless. CloudTrail logs record which access key made each API call — if three developers share one key, you cannot determine who deleted the production database. Every human who needs AWS access gets their own IAM user. Shared access keys are also a rotation problem: rotating a shared key requires coordinating updates across every system and person using it simultaneously.

Misconception 2: "Deleting an access key immediately revokes access."
Reality: Deactivating a key (`--status Inactive`) prevents new requests from succeeding but does not invalidate in-flight requests. Some AWS SDKs cache credentials — code running with a deactivated key may continue to work until the SDK refreshes its credential cache. For immediate revocation, deactivating the key is correct, but verify in CloudTrail that no further calls are made with the key ID before deleting it.

Misconception 3: "Groups in IAM work like Unix groups — you can nest them for hierarchical permissions."
Reality: IAM groups are flat. You cannot add a group as a member of another group. If you need hierarchical permission structures, you must either accept some redundancy in policy attachment or use IAM roles with assume-role chaining. For large organisations, AWS Organizations with Service Control Policies provides hierarchical permission management at the account level rather than the user level.

---

## Why It Matters in Practice

Access key hygiene is one of the most critical and most neglected security practices in AWS. GitHub's secret scanning service detected millions of AWS access keys in public repositories in the past few years — most of them committed accidentally. An exposed access key with broad permissions is an immediate compromise: automated bots scan GitHub and other code hosts for AWS keys within minutes of exposure, and they will use those keys to launch cryptocurrency mining instances, create new IAM users for persistent access, or exfiltrate data before the legitimate owner realises what happened.

The group model matters for team maintainability. An organisation that attaches policies directly to individual users has an access management problem as soon as the second developer joins. An organisation that maintains well-named groups (Developers, DevOps, ReadOnly-Auditors, DataScience) can on-board new team members by adding them to the appropriate groups — a single operation that grants the correct permissions without requiring knowledge of every individual policy.

---

## What Breaks in Production

**Scenario 1: Access key committed to a public repository.**

```bash
# Immediate response: deactivate the key before it is used
aws iam update-access-key \
  --user-name alice \
  --access-key-id AKIAIOSFODNN7EXAMPLE \
  --status Inactive

# Check CloudTrail for usage since commit time
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=AKIAIOSFODNN7EXAMPLE \
  --start-time 2026-05-18T00:00:00Z \
  --output table

# Create a new key for legitimate use and update all systems
aws iam create-access-key --user-name alice

# Delete the compromised key after confirming no legitimate usage remains
aws iam delete-access-key \
  --user-name alice \
  --access-key-id AKIAIOSFODNN7EXAMPLE
```

**Scenario 2: Developer leaves company, account not deprovisioned.**

```python
import boto3
from datetime import datetime, timezone

iam = boto3.client('iam')

def deprovision_user(username: str):
    """Remove all access for a departing user."""
    # Deactivate all access keys
    keys = iam.list_access_keys(UserName=username)['AccessKeyMetadata']
    for key in keys:
        iam.update_access-key(
            UserName=username,
            AccessKeyId=key['AccessKeyId'],
            Status='Inactive'
        )
    
    # Remove from all groups
    groups = iam.list_groups_for_user(UserName=username)['Groups']
    for group in groups:
        iam.remove_user_from_group(
            GroupName=group['GroupName'],
            UserName=username
        )
    
    # Detach all directly attached policies
    policies = iam.list_attached_user_policies(UserName=username)['AttachedPolicies']
    for policy in policies:
        iam.detach_user_policy(
            UserName=username,
            PolicyArn=policy['PolicyArn']
        )
    
    # Delete console password
    try:
        iam.delete_login_profile(UserName=username)
    except iam.exceptions.NoSuchEntityException:
        pass
    
    print(f"Deprovisioned user: {username}")
```

**Scenario 3: All developers in Developers group can access production resources.**

```bash
# Wrong: one group for all environments
aws iam attach-group-policy \
  --group-name Developers \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Right: separate groups per environment with scoped permissions
aws iam create-group --group-name Developers-Dev
aws iam create-group --group-name Developers-Staging  
aws iam create-group --group-name Developers-Prod

# Attach restrictive policy to prod group (read-only + deploy-specific actions)
aws iam attach-group-policy \
  --group-name Developers-Prod \
  --policy-arn arn:aws:iam::123456789012:policy/prod-limited-deploy
```

---

## Interview Angle

Common question forms:
- "When would you use an IAM user versus an IAM role?"
- "How do you manage access key rotation at scale?"
- "What is your process for off-boarding a developer from AWS?"

Answer frame:
IAM users for humans, IAM roles for services — that is the fundamental distinction. Access key management at scale requires: automated credential reports to detect stale keys, enforced MFA, defined rotation windows (90 days or less), and ideally eliminating service-account keys entirely in favour of roles. Off-boarding requires deactivating keys immediately, removing group memberships, deleting login profiles, and auditing CloudTrail for any final activity.

---

## Related Notes

- [[iam-overview|IAM Overview]]
- [[iam-roles|IAM Roles]]
- [[iam-policies|IAM Policies]]
- [[iam-least-privilege|Principle of Least Privilege]]
