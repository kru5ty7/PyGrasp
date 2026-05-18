---
title: S3 Overview
description: S3 (Simple Storage Service) is AWS's infinitely scalable object storage — store any file as an object in a bucket, retrieve it by key, and never worry about provisioning disk space.
tags: [aws, cloud, layer-11, s3, object-storage]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# S3 Overview

> S3 is AWS's object storage service — every Python developer deploying to AWS will use it for static files, ML datasets, logs, backups, and media, and understanding its object model (not a filesystem) prevents costly architectural mistakes.

---

## Quick Reference

**Core idea:**
- Store arbitrary files (objects) inside named containers (buckets)
- Objects are identified by a key — a string that looks like a path but is not a directory structure
- 99.999999999% (11 nines) durability — AWS replicates your data across at least three Availability Zones
- Unlimited total storage; individual objects can be up to 5TB
- Access via HTTPS, AWS CLI, or the boto3 SDK — no mounting, no filesystem calls

**Tricky points:**
- S3 is not a filesystem — there are no real directories, no file locking, and no random byte access
- A key like `images/profile/user123.png` is a single flat key, not a nested path — the slashes are part of the key name
- S3 is eventually consistent for object listings in some edge cases involving rapid overwrites
- S3 does not have transactions — two clients writing the same key simultaneously will result in one version winning silently
- You are billed for requests and data transfer out, not just storage — high-frequency tiny-object reads can be surprisingly expensive

---

## What It Is

Think of S3 as an infinitely large filing cabinet that lives outside your servers. Each drawer in the cabinet is a bucket — you name it, you pick which AWS region it lives in, and you decide the access rules. Inside each drawer you can place any number of files. Each file gets a label (the key) that you attach to it, and that label is the only way you retrieve it later. Unlike a physical filing cabinet, S3 never runs out of space, never loses a file due to a disk failure, and is accessible from anywhere on the internet.

The key insight that trips up developers coming from a Linux background is that S3 has no directories. When you see a key like `data/2026/january/report.csv`, you are not looking at a folder called `data` containing a folder called `2026`. You are looking at a single object whose name happens to contain forward slashes. S3 uses those slashes as a visual delimiter in the console and in listing operations, but they carry no structural meaning in the storage layer. There is no concept of creating an empty folder — a "folder" in the S3 console only appears when at least one object with a matching key prefix exists.

S3 was designed for durability and availability, not for low-latency random access. AWS achieves 11 nines of durability by synchronously writing each object to multiple physical devices across multiple Availability Zones before confirming the write. The trade-off is that S3 is optimised for large sequential reads and whole-object writes — operations like appending a byte to the end of an existing file require downloading the object, modifying it in memory, and uploading the entire object again.

---

## How It Actually Works

When you write an object to S3, you make an HTTP PUT request (or the SDK wraps it for you) targeting a URL of the form `https://<bucket>.s3.<region>.amazonaws.com/<key>`. AWS receives the data, replicates it across multiple storage nodes, and returns a 200 OK once durability is confirmed. The object is then available for GET requests from any client with the correct credentials. Every object has metadata: the key, the content length, the ETag (an MD5 hash of the content used for integrity checks), the storage class, the last-modified timestamp, and any custom metadata headers you attach at upload time.

Listing objects uses the `ListObjectsV2` API, which returns results in alphabetical key order, up to 1000 objects per page. For buckets with millions of objects you must paginate using the `ContinuationToken` returned in each response. The AWS CLI handles pagination automatically with `--no-paginate` disabled by default; in boto3 you should use a paginator rather than calling `list_objects_v2` in a loop manually.

```bash
# AWS CLI — list all objects in a bucket (paginated automatically by the CLI)
aws s3 ls s3://my-bucket/ --recursive

# Upload a file
aws s3 cp ./report.csv s3://my-bucket/data/2026/report.csv

# Download a file
aws s3 cp s3://my-bucket/data/2026/report.csv ./report.csv

# Sync a local directory to S3 (only uploads changed files)
aws s3 sync ./dist/ s3://my-bucket/static/
```

```python
import boto3

s3 = boto3.client("s3")

# Upload
s3.upload_file("report.csv", "my-bucket", "data/2026/report.csv")

# Download
s3.download_file("my-bucket", "data/2026/report.csv", "report.csv")

# List with pagination
paginator = s3.get_paginator("list_objects_v2")
for page in paginator.paginate(Bucket="my-bucket", Prefix="data/2026/"):
    for obj in page.get("Contents", []):
        print(obj["Key"], obj["Size"])
```

---

## How It Connects

S3 does not stand alone — almost every AWS service either reads from or writes to it. Understanding how IAM controls access to S3 is essential before you store anything sensitive; every read and write requires either an IAM identity with the correct permissions or a presigned URL.

[[iam-overview|IAM Overview]] — S3 access is controlled by IAM policies and bucket policies; without correct IAM permissions no API call to S3 will succeed.

S3 buckets and objects are the starting point for the rest of the S3 notes. Once you understand the object model, the permission system and advanced features like versioning and event notifications make much more sense.

[[s3-buckets|S3 Buckets and Objects]] — the concrete mechanics of creating buckets, structuring keys, and making API calls against individual objects.

---

## Common Misconceptions

Misconception 1: S3 is just a cloud hard drive — I can use it anywhere I'd use a filesystem.
Reality: S3 is an object store with HTTP semantics. You cannot open a file, seek to byte 1000, read 50 bytes, and close it. Every read downloads the entire object (or a byte-range you specify). You cannot append data without rewriting the whole object. Applications that require filesystem semantics (databases, write-ahead logs, append-only logs) need EBS or EFS, not S3.

Misconception 2: The slashes in S3 keys create real folders.
Reality: S3 has a flat key namespace. `images/cat.jpg` and `images/dog.jpg` are two separate objects with no shared parent container. The S3 console draws them under a virtual "folder" icon for readability, but there is no directory object. Deleting all objects with prefix `images/` does not remove a folder — the folder simply stops appearing once no keys with that prefix exist.

---

## Why It Matters in Practice

S3 is the backbone of most AWS-based Python applications. It stores the training data for ML models, serves static assets for web apps, holds application logs shipped from EC2, archives database backups, and acts as the source for Lambda triggers. Misunderstanding the object model leads to architectural mistakes — trying to use S3 as a queue (polling is expensive), using it as a database (no atomic updates, no queries), or storing millions of tiny objects and being surprised by the request costs.

Knowing S3's durability guarantees also matters for architecture decisions: you do not need to back up S3 to another storage system for durability (AWS handles that). What you do need to consider is versioning and cross-region replication for protection against accidental deletion or regional outages.

---

## What Breaks in Production

**Storing too many tiny objects without thinking about request costs.** A system that writes one S3 object per log line at 10,000 requests per second generates 864 million PUT requests per day. At $0.005 per 1,000 PUT requests, that is $4,320 per day in request costs alone — more than the storage.

```python
# Bad: one PUT per event
for event in events:
    s3.put_object(Bucket="logs", Key=f"events/{event['id']}.json",
                  Body=json.dumps(event))

# Better: batch into larger objects, e.g. one file per minute or per N events
import io, json
buffer = io.BytesIO()
for event in events:
    buffer.write((json.dumps(event) + "\n").encode())
s3.put_object(Bucket="logs", Key=f"events/batch-{timestamp}.ndjson",
              Body=buffer.getvalue())
```

**Forgetting to paginate `list_objects_v2`.** If a bucket has more than 1000 objects and you call `list_objects_v2` without a paginator, you silently get only the first page.

```python
# Bad: silently truncated at 1000 objects
response = s3.list_objects_v2(Bucket="my-bucket")
keys = [o["Key"] for o in response.get("Contents", [])]

# Good: use a paginator
paginator = s3.get_paginator("list_objects_v2")
keys = [
    obj["Key"]
    for page in paginator.paginate(Bucket="my-bucket")
    for obj in page.get("Contents", [])
]
```

---

## Interview Angle

Common question forms:
- "How does S3 achieve 11 nines of durability?"
- "What is the difference between S3 and EBS?"
- "Describe the S3 data model."

Answer frame:
Start with the object model — key, value, metadata, bucket. Explain that durability comes from synchronous multi-AZ replication, not from any single disk. Contrast with EBS (block storage, attached to one EC2 instance, used for databases and OS volumes) and EFS (network filesystem, POSIX-compatible, multi-instance access). Emphasise that S3 is for whole-object access patterns, not random byte access.

---

## Related Notes

- [[s3-buckets|S3 Buckets and Objects]]
- [[s3-python|S3 with Python (boto3)]]
- [[s3-permissions|S3 Bucket Policies and ACLs]]
- [[iam-overview|IAM Overview]]
- [[aws-overview|AWS Overview]]
