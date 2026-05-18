---
title: 19 - S3 Storage Classes
description: S3 storage classes let you trade retrieval speed and availability against storage cost — choosing the wrong class for your access pattern means either paying too much or waiting hours to retrieve critical data.
tags: [aws, cloud, layer-11, s3, storage-classes, cost]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# S3 Storage Classes

> S3 storage classes are a cost-optimisation mechanism — the same bytes stored in different classes can vary by an order of magnitude in price, and the right choice depends entirely on how often and how urgently you need to retrieve the data.

---

## Quick Reference

**Core idea:**
- Standard: highest cost, immediate retrieval, highest availability — use for frequently accessed data
- Standard-IA and One Zone-IA: lower storage cost but a per-GB retrieval fee — use for data accessed less than once a month
- Glacier Instant Retrieval: archive tier with millisecond access — use for quarterly access patterns
- Glacier Flexible Retrieval: minutes to hours retrieval — use for annual backups you rarely need
- Glacier Deep Archive: cheapest tier, 12-hour retrieval — use for compliance archives and cold backups
- Intelligent-Tiering: auto-moves objects between access tiers based on actual access patterns — use when access is unpredictable

**Tricky points:**
- Infrequent Access classes have a 30-day minimum storage duration — objects deleted before 30 days are billed for the full 30 days
- One Zone-IA stores data in a single Availability Zone — an AZ outage can make the data temporarily unavailable (and permanent if the AZ is destroyed)
- Glacier classes have minimum object sizes for billing — objects smaller than 128KB are charged as 128KB
- Retrieval from Glacier Flexible costs per GB plus per-request fees — bulk retrievals are cheaper than expedited
- Intelligent-Tiering has a monthly monitoring and automation fee per object (about $0.0025 per 1,000 objects) — not cost-effective for millions of tiny objects

---

## What It Is

Think of S3 storage classes as different tiers in a physical archive warehouse. The most expensive tier is the climate-controlled front room — your documents are immediately at hand, always available, retrieved in seconds. The middle tier is a secure room further back — still in the building, but a staff member needs to walk to it and it costs more per trip (retrieval fee). The cheapest tier is off-site deep storage in a remote facility — rent is minimal, but retrieving anything requires scheduling a van, and it may take twelve hours for the material to arrive.

S3 Standard is the front room. Every object stored there is replicated across at least three Availability Zones, is available with 99.99% uptime, and can be retrieved in milliseconds. You pay the highest storage rate per GB but no retrieval fee. This is the right choice for data that your application reads regularly — images served to users, configuration files, recently generated reports, ML model outputs that inference code reads on every request.

Standard-Infrequent Access (Standard-IA) is the secure back room. Storage cost drops significantly compared to Standard, but every retrieval incurs a per-GB fee. The minimum billing duration is 30 days — if you store an object and delete it after two days, you still pay for 30 days. The design assumption is that you will store the object for months and retrieve it rarely. Disaster recovery data, database backups kept for 90 days, and compliance documents that are only accessed during audits are good candidates. One Zone-IA is the same tier but using only one Availability Zone — cheaper still, but with the understanding that an AZ-level disaster could make the data temporarily inaccessible.

The Glacier classes are for genuine archival. Glacier Instant Retrieval maintains the same millisecond access speed as Standard-IA but at a lower storage cost, making it suitable for objects accessed roughly once per quarter. Glacier Flexible Retrieval requires you to submit a retrieval job that completes in minutes (expedited), hours (standard), or up to 12 hours (bulk, cheapest per-GB). Glacier Deep Archive is designed for data you almost never need — 12-hour retrieval is the standard tier — and is the cheapest storage option AWS offers.

---

## How It Actually Works

You set the storage class either at upload time (via the `StorageClass` parameter) or via lifecycle policies that transition objects automatically after a number of days. Transitioning objects between classes is a one-time API call per object that AWS charges for, so lifecycle policies are more efficient than re-uploading objects. You cannot transition from a cheaper class to a more expensive class using lifecycle policies — that must be done explicitly with a `COPY` operation.

Intelligent-Tiering is a special class that monitors each object's access frequency. Objects not accessed for 30 consecutive days are moved to an Infrequent Access tier automatically; after 90 days they move to Archive Instant Access. The process is reversed automatically when the object is accessed. Intelligent-Tiering eliminates the guesswork for data with unpredictable access patterns, but the per-object monitoring fee makes it uneconomical for millions of small files where the fee exceeds the storage savings.

```bash
# Upload directly to a storage class
aws s3 cp backup.tar.gz s3://my-bucket/backups/backup.tar.gz \
    --storage-class STANDARD_IA

# Change an existing object's storage class via copy
aws s3 cp s3://my-bucket/backups/backup.tar.gz \
         s3://my-bucket/backups/backup.tar.gz \
    --storage-class GLACIER

# List objects with their storage class
aws s3api list-objects-v2 --bucket my-bucket \
    --query 'Contents[*].[Key,StorageClass,Size]' --output table
```

```python
import boto3

s3 = boto3.client("s3")

# Upload to Standard-IA
s3.put_object(
    Bucket="my-bucket",
    Key="backups/daily-2026-05-18.tar.gz",
    Body=backup_bytes,
    StorageClass="STANDARD_IA",
)

# upload_file with StorageClass in ExtraArgs
s3.upload_file(
    "large_backup.tar.gz",
    "my-bucket",
    "backups/monthly-2026-05.tar.gz",
    ExtraArgs={"StorageClass": "GLACIER_IR"},  # Glacier Instant Retrieval
)

# Apply a lifecycle policy to auto-transition and expire objects
lifecycle_config = {
    "Rules": [
        {
            "ID": "TransitionOldLogsToGlacier",
            "Status": "Enabled",
            "Filter": {"Prefix": "logs/"},
            "Transitions": [
                {"Days": 30, "StorageClass": "STANDARD_IA"},
                {"Days": 90, "StorageClass": "GLACIER"},
                {"Days": 365, "StorageClass": "DEEP_ARCHIVE"},
            ],
            "Expiration": {"Days": 2555},  # delete after 7 years
        }
    ]
}
s3.put_bucket_lifecycle_configuration(
    Bucket="my-bucket",
    LifecycleConfiguration=lifecycle_config,
)

# Initiate a Glacier retrieval (Flexible or Deep Archive)
s3.restore_object(
    Bucket="my-bucket",
    Key="backups/annual-2024.tar.gz",
    RestoreRequest={
        "Days": 3,               # keep the restored copy available for 3 days
        "GlacierJobParameters": {"Tier": "Standard"},  # Expedited | Standard | Bulk
    },
)

# Check whether a Glacier object has been restored
response = s3.head_object(Bucket="my-bucket", Key="backups/annual-2024.tar.gz")
restore_status = response.get("Restore", "")
if "ongoing-request=\"true\"" in restore_status:
    print("Restore in progress")
elif "ongoing-request=\"false\"" in restore_status:
    print("Restore complete — object temporarily available for download")
```

---

## How It Connects

Storage classes are often managed with lifecycle policies, which are bucket-level rules that automate transitions and deletions. Understanding lifecycle policies is the operational complement to knowing the storage class options.

[[s3-versioning|S3 Versioning]] — versioning and lifecycle rules work together; lifecycle rules can expire old object versions to Glacier or delete them after a number of days, preventing storage costs from accumulating.

The pricing difference between classes is significant in data-heavy Python applications like ML pipelines, where training datasets can be terabytes. The cloud pricing model note explains how S3 pricing is structured (per GB per month, per request, per GB transferred).

[[aws-pricing-model|AWS Pricing Model]] — how S3 storage, request, and data transfer fees combine to determine the total cost of storing data in different classes.

---

## Common Misconceptions

Misconception 1: Glacier is a separate storage service from S3 — I need to use different APIs to access it.
Reality: All Glacier storage classes are part of S3. You access them through the same S3 API and the same boto3 `s3` client. The difference is that Glacier Flexible and Deep Archive require you to submit a restore job before you can download the object — there is no separate Glacier API to learn. The old Amazon Glacier service (now called S3 Glacier Flexible Retrieval) is accessed directly through S3.

Misconception 2: Moving data to Standard-IA always reduces costs because the storage fee is lower.
Reality: Standard-IA has a minimum storage duration of 30 days and a per-GB retrieval fee. If you access the data more than once per month, the retrieval fees can exceed the storage savings. A good rule of thumb: Standard-IA is cost-effective when data is accessed less than once per month and stored for more than 30 days. For data accessed multiple times per week, Standard is cheaper overall.

---

## Why It Matters in Practice

In Python data pipelines and ML workflows, storage costs can dominate the AWS bill. A common pattern is: raw data lands in Standard (frequent access for ETL), transformed data moves to Standard-IA after 30 days (accessed occasionally for re-training), and archived model snapshots move to Glacier after 90 days (accessed only for rollback or compliance). Lifecycle policies automate this without any application code changes.

The Glacier retrieval time matters for disaster recovery planning. If your only database backup is in Glacier Deep Archive, recovering from a production incident will take at minimum 12 hours — a fact that must be reflected in your recovery time objective (RTO).

---

## What Breaks in Production

**Storing millions of small log files in Standard-IA.** The 30-day minimum billing and the retrieval fee per GB make Standard-IA expensive for frequently deleted or accessed small files. Log files processed and then deleted within hours get billed for 30 days each.

```python
# Bad — each 1KB log file stored in Standard-IA gets billed for 30 days minimum
for log_entry in log_batch:
    s3.put_object(Bucket="logs", Key=f"raw/{log_entry['id']}.json",
                  StorageClass="STANDARD_IA", Body=json.dumps(log_entry).encode())

# Good — batch into larger objects; use Standard for hot data; IA only for cold archives
# Also consider Intelligent-Tiering for unpredictable patterns, or just Standard + lifecycle
```

**Forgetting to restore a Glacier object before a scheduled job tries to download it.** The download will fail with `InvalidObjectState` until the restore is complete.

```python
from botocore.exceptions import ClientError

def download_with_restore_check(bucket, key, local_path):
    try:
        s3.download_file(bucket, key, local_path)
    except ClientError as e:
        if e.response["Error"]["Code"] == "InvalidObjectState":
            # Object is in Glacier — initiate restore and notify
            s3.restore_object(Bucket=bucket, Key=key,
                RestoreRequest={"Days": 1, "GlacierJobParameters": {"Tier": "Standard"}})
            raise RuntimeError(f"Object in Glacier — restore initiated, retry in ~3-5 hours")
        raise
```

---

## Interview Angle

Common question forms:
- "What S3 storage class would you use for database backups that are kept for 90 days?"
- "What is the difference between Glacier Instant Retrieval and Glacier Flexible Retrieval?"
- "How would you automatically move old objects to cheaper storage?"

Answer frame:
For backup storage: Standard-IA for the first 30-90 days, transition to Glacier Flexible after 90 days via lifecycle policy. For Glacier variants: Instant = milliseconds access, higher storage cost; Flexible = minutes to hours, lowest cost. For automation: lifecycle configuration rules on the bucket with `Transitions` and `Expiration` settings.

---

## Related Notes

- [[s3-overview|S3 Overview]]
- [[s3-versioning|S3 Versioning]]
- [[s3-buckets|S3 Buckets and Objects]]
- [[aws-pricing-model|AWS Pricing Model]]
