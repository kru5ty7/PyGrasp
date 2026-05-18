---
title: 17 - S3 Bucket Policies and ACLs
description: S3 access is controlled by three layered mechanisms — IAM policies, bucket policies, and ACLs — and understanding their interaction and precedence prevents both security gaps and accidental lockouts.
tags: [aws, cloud, layer-11, s3, permissions, bucket-policy]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# S3 Bucket Policies and ACLs

> S3 has its own multi-layered permission system on top of IAM — every Python developer storing sensitive data in S3 must understand how bucket policies, IAM policies, and the public access block interact to avoid both data exposures and access errors.

---

## Quick Reference

**Core idea:**
- IAM policies are identity-based — attached to a user, group, or role; control what that identity can do across all buckets
- Bucket policies are resource-based — attached to the bucket; control who can access this specific bucket
- For an API call to succeed, either the IAM policy or the bucket policy must explicitly allow it (and neither must deny it)
- ACLs are a legacy per-object/bucket access mechanism — AWS recommends disabling them (bucket ownership enforced mode)
- The Public Access Block has four independent toggles that can override both IAM and bucket policies to prevent any public access

**Tricky points:**
- A bucket policy that grants `s3:GetObject` to `*` (everyone) is still blocked if the Public Access Block setting `BlockPublicPolicy` is enabled
- Cross-account access requires both the IAM policy in the source account AND the bucket policy in the destination account to allow the action
- `s3:PutObject` permission does not automatically grant `s3:GetObject` — they are separate permissions
- Denying access in an IAM policy will override any bucket policy that grants it (Deny always wins in AWS)
- An empty bucket policy means IAM is the only control — which is correct for private buckets

---

## What It Is

Imagine S3 as a secure storage facility with two separate sets of locks. The first set of locks belongs to IAM — they determine whether your keycard (IAM role or user) is allowed to enter any storage unit of a given type across the whole facility. The second set belongs to the individual storage unit (the bucket) — the bucket owner can choose to share their unit with specific key cards or, in exceptional cases, leave it completely open to the public. An action only succeeds when both locks permit it.

IAM policies are attached to identities — a specific IAM role, user, or group. They define the set of actions that identity is allowed to perform across AWS. An EC2 instance with an IAM role that includes `s3:GetObject` on `arn:aws:s3:::my-bucket/*` can download objects from that bucket. The same role without that permission cannot, regardless of what the bucket policy says (unless the bucket policy grants cross-account access, which creates a different trust model).

Bucket policies are JSON documents attached directly to the bucket. They are evaluated in terms of who is making the request, not what role is attached to the request's originator. A bucket policy can grant access to a specific IAM role, to an entire AWS account, to everyone (public), or to specific IP address ranges. The typical production use case for a bucket policy is either cross-account access (granting another account's role access to your bucket) or service access (allowing CloudFront to read objects using an Origin Access Control identity). For same-account IAM access, IAM policies alone are usually sufficient.

The four Public Access Block toggles are a safety net introduced after several high-profile S3 data breaches. When enabled (the default for new buckets), they prevent bucket policies or ACLs from granting any public access, regardless of what those policies say. This means you can write a bucket policy with `"Principal": "*"` and it will be silently blocked if the Public Access Block is active. Disabling these settings intentionally, for a static website bucket, requires explicitly understanding and accepting the consequence.

---

## How It Actually Works

AWS evaluates permissions in a strict order. First, it checks for an explicit Deny in any applicable policy (IAM policy, bucket policy, SCP). An explicit Deny anywhere terminates the evaluation — access is denied. Then it checks for an explicit Allow. For same-account access to S3, an explicit Allow in either the IAM policy or the bucket policy is sufficient. For cross-account access, an explicit Allow must appear in both the bucket policy (in the resource account) and the IAM policy (in the calling account) — one without the other is insufficient.

ACLs (Access Control Lists) predate IAM and bucket policies. They attach directly to individual objects or to buckets and express simple grant/deny rules for predefined groups (AllUsers, AuthenticatedUsers). AWS now recommends disabling ACLs entirely using Bucket Ownership Controls set to `BucketOwnerEnforced` mode. In this mode, ACLs are disabled and the bucket owner automatically owns all objects, even those uploaded by other accounts.

```bash
# View current bucket policy
aws s3api get-bucket-policy --bucket my-bucket --query Policy --output text | python -m json.tool

# Apply a bucket policy from a file
aws s3api put-bucket-policy --bucket my-bucket --policy file://bucket-policy.json

# Check Public Access Block settings
aws s3api get-public-access-block --bucket my-bucket

# Disable Public Access Block (required for public static website hosting)
aws s3api put-public-access-block \
    --bucket my-public-website-bucket \
    --public-access-block-configuration \
        BlockPublicAcls=false,IgnorePublicAcls=false,\
        BlockPublicPolicy=false,RestrictPublicBuckets=false
```

```python
import boto3, json

s3 = boto3.client("s3")

# Apply a bucket policy granting a specific IAM role read access
role_arn = "arn:aws:iam::123456789012:role/DataPipelineRole"
policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowDataPipelineRoleRead",
            "Effect": "Allow",
            "Principal": {"AWS": role_arn},
            "Action": ["s3:GetObject", "s3:ListBucket"],
            "Resource": [
                "arn:aws:s3:::my-bucket",
                "arn:aws:s3:::my-bucket/*",
            ],
        }
    ],
}
s3.put_bucket_policy(Bucket="my-bucket", Policy=json.dumps(policy))

# Cross-account bucket policy — allow an entire account to read
cross_account_policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CrossAccountRead",
            "Effect": "Allow",
            "Principal": {"AWS": "arn:aws:iam::987654321098:root"},
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::my-bucket/*",
        }
    ],
}
s3.put_bucket_policy(Bucket="my-bucket", Policy=json.dumps(cross_account_policy))

# Enforce bucket owner ownership (disables ACLs)
s3.put_bucket_ownership_controls(
    Bucket="my-bucket",
    OwnershipControls={"Rules": [{"ObjectOwnership": "BucketOwnerEnforced"}]},
)

# Get the effective bucket policy
response = s3.get_bucket_policy(Bucket="my-bucket")
print(json.loads(response["Policy"]))
```

---

## How It Connects

S3 bucket policies use IAM ARN syntax for principals — you reference IAM roles, users, and accounts by ARN. Understanding the IAM identity model is therefore a prerequisite for writing correct bucket policies.

[[iam-policies|IAM Policies]] — the JSON policy language that governs both IAM policies and bucket policies; the Effect/Action/Resource/Principal/Condition structure is the same in both.

Presigned URLs are a way to grant temporary, scoped access to individual S3 objects without modifying any bucket policy or IAM policy — they are generated programmatically and bypass the normal IAM evaluation for the duration of their validity.

[[s3-presigned-urls|S3 Presigned URLs]] — a mechanism to grant temporary object access without changing permanent permissions, useful for user-facing downloads and direct uploads.

---

## Common Misconceptions

Misconception 1: A bucket policy that allows `s3:GetObject` to `*` makes the bucket publicly accessible.
Reality: This is only true if the Public Access Block is also disabled. If `BlockPublicPolicy` is enabled (the default), AWS will reject the attempt to set such a policy with an error. If `RestrictPublicBuckets` is enabled, the policy will be accepted but its effect will be silently overridden — requests from anonymous users will still receive `403 AccessDenied`. Both toggles must be disabled for a public bucket policy to actually work.

Misconception 2: Granting an IAM role `s3:*` on a bucket means that role can do everything, including making the bucket public.
Reality: `s3:*` on a bucket grants all S3 data actions for that role, but does not grant the ability to modify the bucket's own Public Access Block settings or bucket policy. Those are separate administrative actions (`s3:PutBucketPublicAccessBlock`, `s3:PutBucketPolicy`) that must be explicitly granted, and even then the account-level S3 Public Access Block (separate from the bucket-level one) may still block them.

---

## Why It Matters in Practice

S3 data breaches have exposed millions of records — most were caused by bucket policies or ACLs that granted public access, either intentionally (static website) or accidentally (misconfigured policy copied from a tutorial). AWS now enables the Public Access Block by default on new accounts and buckets, which prevents the most common mistake. But for cross-account access patterns (data teams reading from a shared data lake, CI/CD pipelines writing artifacts to a deployment bucket), bucket policies are the correct mechanism — and getting them wrong means either broken deployments or over-permissioned access.

In production Python applications, the most relevant scenario is granting an EC2 instance role or a Lambda execution role access to a specific bucket or key prefix. Overly broad policies (granting `s3:*` on `*`) expose all buckets in the account. Correct least-privilege policies grant only the needed actions (`s3:GetObject`, `s3:PutObject`) on only the needed bucket and prefix.

---

## What Breaks in Production

**Cross-account upload succeeding but the bucket owner not being able to read the object.** When another account uploads an object to your bucket, the uploading account owns the object by default (not the bucket owner). The bucket owner cannot read it without either a bucket policy or ACL granting them access — or using BucketOwnerEnforced mode.

```bash
# Fix: enforce bucket owner ownership (disables ACLs, bucket owner owns all objects)
aws s3api put-bucket-ownership-controls \
    --bucket my-bucket \
    --ownership-controls '{"Rules":[{"ObjectOwnership":"BucketOwnerEnforced"}]}'
```

**A bucket policy that grants access but the IAM role does not have `s3:ListBucket`, causing 403 instead of 404 for missing objects.** Without `s3:ListBucket`, a `head_object` or `get_object` on a missing key returns `403 AccessDenied` instead of `404 NoSuchKey`, making existence checks ambiguous.

```python
# IAM policy must include both ListBucket (for the bucket ARN) and GetObject (for the key ARN)
{
    "Effect": "Allow",
    "Action": ["s3:ListBucket"],          # needed for 404 vs 403 distinction
    "Resource": "arn:aws:s3:::my-bucket"
},
{
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": "arn:aws:s3:::my-bucket/*"
}
```

---

## Interview Angle

Common question forms:
- "What is the difference between an IAM policy and an S3 bucket policy?"
- "How do you grant cross-account access to an S3 bucket?"
- "Why would a `GetObject` call return 403 even though the object exists?"

Answer frame:
For IAM vs bucket policy: identity-based vs resource-based — both can grant S3 access, but cross-account access requires both. For cross-account: bucket policy in the destination account, IAM policy in the source account. For the 403 on existing object: explain that without `s3:ListBucket` on the bucket ARN, missing keys and permission errors are both returned as 403.

---

## Related Notes

- [[s3-overview|S3 Overview]]
- [[iam-policies|IAM Policies]]
- [[iam-roles|IAM Roles]]
- [[s3-presigned-urls|S3 Presigned URLs]]
- [[iam-least-privilege|IAM Least Privilege]]
