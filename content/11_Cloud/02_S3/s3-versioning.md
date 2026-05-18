---
title: 20 - S3 Versioning
description: S3 versioning keeps a full history of every object version in a bucket, protecting against accidental deletion and enabling rollback — but it requires understanding how delete markers work to avoid confusing failures.
tags: [aws, cloud, layer-11, s3, versioning]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# S3 Versioning

> S3 versioning is a bucket-level feature that preserves every write to every object as a distinct version — making it the primary mechanism for accidental-deletion protection, but also one that silently accumulates storage costs without lifecycle rules.

---

## Quick Reference

**Core idea:**
- Once versioning is enabled on a bucket, every PUT creates a new version with a unique version ID; the old version is preserved, not overwritten
- Deleting an object without specifying a version ID places a delete marker — the object is hidden but not gone
- Permanently deleting a specific version requires providing the version ID in the delete call
- Versioning state transitions: Unversioned → Enabled → Suspended (cannot go back to Unversioned)
- All versions (including delete markers) count toward storage billing

**Tricky points:**
- Enabling versioning cannot be undone — you can only suspend it, which stops creating new versions but preserves all existing ones
- A suspended bucket still retains all previously created versions — storage costs do not go away on suspension
- `list_objects_v2` only shows current (non-deleted) objects — use `list_object_versions` to see all versions and delete markers
- Accidentally re-enabling versioning on a suspended bucket resumes version creation, which can be surprising
- MFA Delete requires a hardware MFA device to delete versions or change versioning state — protects against malicious or accidental permanent deletion

---

## What It Is

Imagine a word processor with an infinite undo history. Every time you save the document, a new snapshot is preserved without replacing the previous one. If you accidentally delete the document, the undo history still contains every prior version. You can restore yesterday's version, or last week's version, or the version from six months ago. S3 versioning is that infinite undo history for your S3 objects.

Without versioning, each PUT to `s3://my-bucket/config.json` overwrites the previous content — the old bytes are gone permanently. With versioning enabled, each PUT creates a new version. AWS assigns each version a unique, opaque version ID (a 32-character string like `3sL4kqtJlcpXrof3vjVBH40AbpAyWFMm`). The most recent version is the "current" version, and it is what you get when you GET the object without specifying a version. The previous versions remain stored and accessible by their version IDs indefinitely, until you explicitly delete them.

The delete operation in a versioned bucket behaves differently from what most developers expect. When you call `delete_object` on a key without providing a version ID, S3 does not delete anything. It creates a special marker called a delete marker — a zero-byte placeholder that makes the object appear deleted to `list_objects_v2` and `get_object` calls. The original object versions are still there, still billing you for storage. This design prevents accidental permanent deletion, but it means that "deleting" an object in a versioned bucket without specifying a version ID is a reversible operation — you can undo it by deleting the delete marker.

---

## How It Actually Works

The version ID is the fundamental unit of versioning. Every object operation that creates a version (PUT, COPY, server-side encryption re-encrypt) returns the new version ID in the response. Operations that reference a specific version require the version ID — there is no "previous version" shorthand in the API. To restore an object to a previous version you must either delete the current version (exposing the previous one) or copy the specific version to the same key (creating a new version that is identical to the old one).

Lifecycle rules are the complement to versioning. Without them, every version of every object accumulates in the bucket and you pay for all of them. A lifecycle rule like "expire noncurrent versions after 30 days" automatically deletes old versions, leaving only the most recent one. A rule like "delete expired delete markers" cleans up the zero-byte placeholders left by soft deletes. These two rules together allow you to retain versioning's safety net while keeping storage costs predictable.

```bash
# Enable versioning on a bucket
aws s3api put-bucket-versioning \
    --bucket my-bucket \
    --versioning-configuration Status=Enabled

# Check versioning status
aws s3api get-bucket-versioning --bucket my-bucket

# List all versions and delete markers
aws s3api list-object-versions --bucket my-bucket --prefix config/

# Delete an object (creates a delete marker — NOT a permanent delete)
aws s3 rm s3://my-bucket/config/app.json

# Permanently delete a specific version
aws s3api delete-object \
    --bucket my-bucket \
    --key config/app.json \
    --version-id 3sL4kqtJlcpXrof3vjVBH40AbpAyWFMm

# Get a specific version of an object
aws s3api get-object \
    --bucket my-bucket \
    --key config/app.json \
    --version-id 3sL4kqtJlcpXrof3vjVBH40AbpAyWFMm \
    output.json
```

```python
import boto3

s3 = boto3.client("s3")

# Enable versioning
s3.put_bucket_versioning(
    Bucket="my-bucket",
    VersioningConfiguration={"Status": "Enabled"},
)

# Upload — response includes the new VersionId
response = s3.put_object(
    Bucket="my-bucket", Key="config/app.json", Body=b'{"version": 2}')
version_id = response["VersionId"]
print("New version:", version_id)

# Get a specific version
response = s3.get_object(Bucket="my-bucket", Key="config/app.json",
                         VersionId=version_id)
content = response["Body"].read()

# List all versions of a specific key
response = s3.list_object_versions(Bucket="my-bucket", Prefix="config/app.json")
for version in response.get("Versions", []):
    print(version["VersionId"], version["LastModified"], version["IsLatest"])
for marker in response.get("DeleteMarkers", []):
    print("DELETE MARKER:", marker["VersionId"], marker["IsLatest"])

# Soft delete — creates a delete marker
s3.delete_object(Bucket="my-bucket", Key="config/app.json")

# Undo the soft delete by deleting the delete marker
# First find the delete marker's version ID
response = s3.list_object_versions(Bucket="my-bucket", Prefix="config/app.json")
for marker in response.get("DeleteMarkers", []):
    if marker["IsLatest"]:
        s3.delete_object(Bucket="my-bucket", Key="config/app.json",
                         VersionId=marker["VersionId"])
        print("Delete marker removed — object is visible again")

# Add lifecycle rule to expire old versions after 30 days
s3.put_bucket_lifecycle_configuration(
    Bucket="my-bucket",
    LifecycleConfiguration={
        "Rules": [
            {
                "ID": "ExpireNoncurrentVersions",
                "Status": "Enabled",
                "Filter": {},
                "NoncurrentVersionExpiration": {"NoncurrentDays": 30},
                "ExpiredObjectDeleteMarker": True,  # clean up delete markers
            }
        ]
    },
)
```

---

## How It Connects

Versioning and lifecycle policies work together — without lifecycle rules, versioning causes storage costs to grow indefinitely as every version of every object is retained. Understanding how to write lifecycle rules that target noncurrent versions is the operational skill that makes versioning sustainable.

[[s3-storage-classes|S3 Storage Classes]] — lifecycle rules can not only expire noncurrent versions but also transition them to cheaper storage classes before eventually deleting them, reducing the cost of maintaining a version history.

Versioning interacts with S3 event notifications — delete events in versioned buckets include the version ID in the event payload, which is important for processing pipelines that respond to object deletions.

[[s3-event-notifications|S3 Event Notifications]] — when a delete marker is created in a versioned bucket, the resulting event payload includes both the key and the version ID, allowing downstream processors to handle versioned deletions correctly.

---

## Common Misconceptions

Misconception 1: Deleting an object from a versioned bucket removes it permanently.
Reality: Deleting an object by key name (without a version ID) only creates a delete marker. All versions of the object remain in the bucket, consume storage, and incur charges. To permanently remove data, you must delete each version individually by its version ID — or use a lifecycle rule to expire versions automatically.

Misconception 2: Suspending versioning stops billing for existing versions.
Reality: Suspending versioning stops creating new versions for subsequent PUTs (new objects get a version ID of `null`), but all versions created before suspension continue to exist and continue to incur storage charges. The only way to stop paying for old versions is to delete them explicitly or let lifecycle rules expire them.

---

## Why It Matters in Practice

Versioning is the first line of defence against accidental deletion. Without it, a bug that deletes the wrong S3 key, a failed deployment that overwrites a configuration file, or an accidental `aws s3 rm` command is immediately unrecoverable. With versioning, the deletion is a soft delete — you can recover the object within the lifecycle retention window.

For compliance workloads, versioning combined with Object Lock (WORM — Write Once, Read Many) creates an immutable audit trail. Financial records, medical data, and legal documents that must not be altered or deleted can be locked using S3 Object Lock's Compliance mode, making them non-deletable even by the root account.

---

## What Breaks in Production

**Unexpected storage cost growth from versioned buckets without lifecycle rules.** A bucket that processes file uploads with occasional replacements can double or triple its storage consumption silently once versioning is enabled and no lifecycle policy expiring old versions is in place.

```python
# Add lifecycle rule immediately after enabling versioning — do not leave it unconfigured
s3.put_bucket_versioning(Bucket="my-bucket",
    VersioningConfiguration={"Status": "Enabled"})

# Immediately follow with lifecycle rule
s3.put_bucket_lifecycle_configuration(
    Bucket="my-bucket",
    LifecycleConfiguration={"Rules": [{
        "ID": "CleanupOldVersions",
        "Status": "Enabled",
        "Filter": {},
        "NoncurrentVersionExpiration": {"NoncurrentDays": 30},
        "ExpiredObjectDeleteMarker": True,
    }]},
)
```

**Bulk delete on a versioned bucket that only removes the current version.** Scripts written for non-versioned buckets that use `delete_object` by key will leave old versions behind, causing unexpected storage charges and incomplete data removal.

```python
# Bad — creates delete markers, leaves all versions behind
for key in keys_to_fully_remove:
    s3.delete_object(Bucket="my-bucket", Key=key)

# Good — delete every version of every key
paginator = s3.get_paginator("list_object_versions")
for page in paginator.paginate(Bucket="my-bucket"):
    delete_list = [
        {"Key": v["Key"], "VersionId": v["VersionId"]}
        for v in page.get("Versions", []) + page.get("DeleteMarkers", [])
    ]
    if delete_list:
        s3.delete_objects(Bucket="my-bucket",
            Delete={"Objects": delete_list, "Quiet": True})
```

---

## Interview Angle

Common question forms:
- "How does S3 versioning protect against accidental deletion?"
- "What happens when you delete an object from a versioned S3 bucket?"
- "How do you permanently delete all versions of an object in a versioned bucket?"

Answer frame:
For protection: each PUT preserves the previous version; deletes create reversible delete markers. For the delete mechanism: explain delete markers — the object appears gone but all versions remain; specify version ID to permanently remove. For permanent removal: list all versions with `list_object_versions`, delete each by version ID using `delete_objects` in batches.

---

## Related Notes

- [[s3-buckets|S3 Buckets and Objects]]
- [[s3-storage-classes|S3 Storage Classes]]
- [[s3-event-notifications|S3 Event Notifications]]
- [[s3-python|S3 with Python (boto3)]]
