---
title: 15 - S3 Buckets and Objects
description: A bucket is the top-level container in S3 — globally unique, region-bound — and every file you store inside it is an object identified entirely by its key string.
tags: [aws, cloud, layer-11, s3, buckets]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# S3 Buckets and Objects

> Buckets and objects are the two fundamental primitives of S3 — understanding their constraints, naming rules, and metadata model is the prerequisite for every other S3 topic.

---

## Quick Reference

**Core idea:**
- A bucket is a globally unique, region-specific container — its name must be unique across all AWS accounts worldwide
- An object is any file stored in a bucket, identified by its key (a UTF-8 string up to 1024 bytes)
- Object metadata includes: key, size, last-modified, ETag (MD5 hash), storage class, and custom user-defined metadata
- Core operations: PUT (upload), GET (download), DELETE, COPY, HEAD (metadata without body)
- The URL pattern for any object: `https://<bucket>.s3.<region>.amazonaws.com/<key>`

**Tricky points:**
- Bucket names are globally unique — if someone else has `my-bucket`, you cannot create it in your account
- Bucket names cannot contain uppercase letters or underscores — common source of frustration
- Buckets are region-specific but bucket names are globally scoped — creating a bucket in `us-east-1` does not affect `eu-west-1` but the name is reserved globally
- The default `Public Access Block` setting on new buckets blocks all public access — this is correct and must be consciously overridden
- Deleting a bucket requires it to be empty — you cannot delete a non-empty bucket in a single API call

---

## What It Is

Think of an S3 bucket as a named postal address for your data. Just as two businesses cannot occupy the same street address in the same city, no two AWS accounts in the world can own a bucket with the same name. When you create a bucket named `acme-corp-assets`, that name is reserved globally. This is why bucket names tend to include company identifiers, project names, or account IDs to avoid collisions.

Inside the bucket, every stored file is an object. An object has two parts: the data (the raw bytes of your file) and its metadata. The key — the object's name — is just a string. It can be as simple as `logo.png` or as long as `production/logs/2026/05/18/app-server-1/errors.log.gz`. There is no hierarchical storage behind those slashes. The bucket holds all objects in a flat namespace, and the console renders key prefixes as folder icons for human convenience.

Every object also carries an ETag header — a hex-encoded MD5 hash of its content. S3 uses this for integrity verification during transfers and for conditional requests (download only if the content has changed). For multipart-uploaded objects the ETag is computed differently (a hash of the part hashes), which surprises developers who try to validate object integrity by comparing ETags to locally computed MD5s.

---

## How It Actually Works

Creating a bucket ties it to a specific AWS region. All objects stored in that bucket physically reside within that region's storage infrastructure, which matters for compliance (keeping data in a specific geography), latency (put the bucket close to your compute), and egress cost (data transferred out to the internet or to a different region incurs charges). The bucket region cannot be changed after creation — if you need data in a different region, you copy or replicate it.

Object operations are HTTP-based. A PUT request uploads the object; the body is the raw file content. A GET request retrieves it. A HEAD request returns only the metadata headers — useful for checking whether an object exists or reading its size without paying for data transfer. A DELETE on a non-versioned bucket permanently removes the object; on a versioned bucket it places a delete marker instead.

```bash
# Create a bucket in a specific region
aws s3api create-bucket \
    --bucket my-project-assets \
    --region eu-west-1 \
    --create-bucket-configuration LocationConstraint=eu-west-1

# Upload an object
aws s3 cp ./logo.png s3://my-project-assets/static/logo.png

# Check object metadata only (HEAD, no download)
aws s3api head-object --bucket my-project-assets --key static/logo.png

# Delete an object
aws s3 rm s3://my-project-assets/static/logo.png

# List objects with a specific prefix
aws s3 ls s3://my-project-assets/static/ --recursive
```

```python
import boto3

s3 = boto3.client("s3", region_name="eu-west-1")

# Create a bucket (us-east-1 does NOT need LocationConstraint — all others do)
s3.create_bucket(
    Bucket="my-project-assets",
    CreateBucketConfiguration={"LocationConstraint": "eu-west-1"},
)

# Upload bytes directly (put_object) — good for small objects
s3.put_object(
    Bucket="my-project-assets",
    Key="config/settings.json",
    Body=b'{"debug": false}',
    ContentType="application/json",
)

# Head object — check existence and size without downloading
try:
    response = s3.head_object(Bucket="my-project-assets", Key="config/settings.json")
    print("Size:", response["ContentLength"])
    print("ETag:", response["ETag"])
except s3.exceptions.ClientError as e:
    if e.response["Error"]["Code"] == "404":
        print("Object does not exist")
    else:
        raise

# Copy an object within or across buckets
s3.copy_object(
    CopySource={"Bucket": "my-project-assets", "Key": "config/settings.json"},
    Bucket="my-project-backup",
    Key="config/settings.json",
)

# Delete a bucket (must be empty first)
paginator = s3.get_paginator("list_objects_v2")
for page in paginator.paginate(Bucket="my-project-assets"):
    for obj in page.get("Contents", []):
        s3.delete_object(Bucket="my-project-assets", Key=obj["Key"])
s3.delete_bucket(Bucket="my-project-assets")
```

---

## How It Connects

Before you can create a bucket or put any object into it, the IAM identity making the API call must have the corresponding permissions. Bucket policies and IAM policies both influence what is allowed, and the public access block settings act as a global override that can prevent public access regardless of any policy.

[[s3-permissions|S3 Bucket Policies and ACLs]] — the complete model for who can access a bucket and its objects, including the difference between IAM policies and bucket policies.

Once you understand buckets and objects, the Python-specific operations for uploading and downloading large files, streaming content, and handling pagination are the next practical step.

[[s3-python|S3 with Python (boto3)]] — idiomatic boto3 patterns for all common S3 operations including streaming and large-file uploads.

---

## Common Misconceptions

Misconception 1: I can create a bucket in eu-west-1 with the same name as a bucket in us-east-1 because they're different regions.
Reality: Bucket names are globally unique across all regions and all AWS accounts. The name `my-bucket` can only exist once in the entire S3 namespace. Creating a bucket in eu-west-1 permanently reserves that name globally — no one else (including you in us-east-1) can use it while the bucket exists.

Misconception 2: Deleting a bucket deletes all objects inside it automatically.
Reality: S3 will refuse to delete a non-empty bucket with a `BucketNotEmpty` error. You must first delete every object (and every version, if versioning is enabled) before you can delete the bucket itself. For large buckets this requires paginating through all objects and deleting them in batches.

Misconception 3: The ETag of an object is always the MD5 hash of its content.
Reality: For objects uploaded in a single PUT request, the ETag is the MD5 of the content. For multipart uploads, the ETag is computed as the MD5 of the concatenated MD5s of each part, followed by a hyphen and the number of parts (e.g., `d41d8cd98f00b204e9800998ecf8427e-5`). Comparing ETags to local MD5 checksums will fail for multipart-uploaded objects.

---

## Why It Matters in Practice

Bucket and object mechanics are the foundation for every S3 interaction. Getting the naming rules wrong means hitting errors at deployment time (bucket names with underscores or uppercase letters are rejected). Not understanding the flat key namespace leads to application logic that assumes `deletePrefix("images/")` removes a directory, when in reality it does nothing — S3 has no directory delete operation.

The ETag and ContentLength from HEAD requests are valuable for caching and synchronisation logic. Before downloading a large file, you can HEAD it and compare the ETag to a locally cached value to avoid unnecessary transfers. This pattern appears frequently in data pipeline code that syncs S3 data to local machines or other services.

---

## What Breaks in Production

**Creating a bucket in us-east-1 with a LocationConstraint, or creating outside us-east-1 without one.** This is a long-standing AWS quirk that causes `InvalidLocationConstraint` errors.

```python
# Bad — will fail in us-east-1 with InvalidLocationConstraint
s3.create_bucket(
    Bucket="my-bucket",
    CreateBucketConfiguration={"LocationConstraint": "us-east-1"},  # do NOT do this
)

# Correct for us-east-1 — omit CreateBucketConfiguration entirely
s3.create_bucket(Bucket="my-bucket")

# Correct for all other regions
s3.create_bucket(
    Bucket="my-bucket",
    CreateBucketConfiguration={"LocationConstraint": "eu-west-1"},
)
```

**Assuming `list_objects_v2` returns all objects.** The API returns at most 1000 keys per call. Without pagination, code silently processes only the first page.

```python
# Bad — processes only first 1000 objects
response = s3.list_objects_v2(Bucket="large-bucket", Prefix="data/")
for obj in response.get("Contents", []):
    process(obj["Key"])

# Good — paginator handles continuation automatically
paginator = s3.get_paginator("list_objects_v2")
for page in paginator.paginate(Bucket="large-bucket", Prefix="data/"):
    for obj in page.get("Contents", []):
        process(obj["Key"])
```

---

## Interview Angle

Common question forms:
- "Why must S3 bucket names be globally unique?"
- "What is an ETag in S3 and when would you use it?"
- "How do you delete all objects in a bucket programmatically?"

Answer frame:
For global uniqueness: S3 uses bucket names as DNS subdomains (`bucket.s3.region.amazonaws.com`). DNS is a global namespace — two entries with the same name cannot coexist. For ETags: explain content hash for single-part uploads, compound hash for multipart — useful for caching and sync decisions, but not reliable as a raw MD5 for multipart objects. For bulk delete: paginator on `list_objects_v2`, then `delete_objects` in batches of up to 1000.

---

## Related Notes

- [[s3-overview|S3 Overview]]
- [[s3-python|S3 with Python (boto3)]]
- [[s3-permissions|S3 Bucket Policies and ACLs]]
- [[s3-versioning|S3 Versioning]]
