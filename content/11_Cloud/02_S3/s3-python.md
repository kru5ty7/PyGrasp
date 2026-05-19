---
title: 16 - S3 with Python (boto3)
description: The core boto3 patterns every Python developer needs for uploading, downloading, listing, deleting, and streaming S3 objects reliably and efficiently.
tags: [aws, cloud, layer-11, s3, boto3, python]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# S3 with Python (boto3)

> boto3 is the AWS SDK for Python - knowing its S3 methods, their subtle differences, and their failure modes is the prerequisite for building any Python application that reads from or writes to S3.

---

## Quick Reference

**Core idea:**
- `upload_file` and `download_file` use the S3 Transfer Manager - automatic multipart, retry, and concurrency
- `put_object` and `get_object` are raw API calls - no automatic multipart or retry
- `list_objects_v2` returns at most 1000 objects per call - always use a paginator
- `delete_objects` can delete up to 1000 objects per call - use it for bulk deletes
- Stream large objects through `get_object`'s `Body` without loading them fully into memory

**Tricky points:**
- `get_object` returns a streaming `StreamingBody` - call `.read()` only for small objects; use `.iter_chunks()` for large ones
- `upload_file` silently uses multipart for files over 8MB by default - configure `TransferConfig` to tune this
- `list_objects_v2` results are alphabetical, not insertion order - never rely on creation-time ordering
- `ClientError` wraps all S3 API errors - check `e.response["Error"]["Code"]` to distinguish 404 from 403 from throttling
- The `Bucket` and `Key` parameters are positional only in some methods - use keyword arguments to avoid bugs

---

## What It Is

Think of boto3 as a telephone exchange between your Python code and the AWS API. Each method call you make - `upload_file`, `get_object`, `list_objects_v2` - is translated into a signed HTTPS request and sent to the AWS endpoint. The response comes back as a Python dictionary. boto3 handles the cryptographic request signing (SigV4), the serialisation of parameters into query strings or request bodies, and the deserialisation of XML or JSON responses into dictionaries.

The S3 client has two important conceptual layers. The low-level client (`boto3.client("s3")`) maps one-to-one to the S3 REST API - every call corresponds to exactly one HTTP request. The transfer manager (used internally by `upload_file` and `download_file`) sits above the low-level client and adds multipart splitting, concurrent part uploads, automatic retries, and progress callbacks. For files larger than a few megabytes, the transfer manager is always preferable to raw `put_object` calls.

The distinction between `upload_file` and `put_object` is the most commonly confused pair. `put_object` sends the entire object body in a single HTTP request - suitable for strings, small byte strings, or file-like objects you have already loaded into memory. `upload_file` reads from a local file path and automatically splits the file into parts if it exceeds the multipart threshold, uploading parts in parallel and assembling them server-side. For a 2GB ML model checkpoint, `put_object` will likely timeout or fail on a slow connection; `upload_file` will succeed by uploading 8MB chunks in parallel with automatic retry per chunk.

---

## How It Actually Works

boto3 connects to S3 using the credentials found in the default credential chain: environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), the `~/.aws/credentials` file, an EC2 instance profile, or an ECS task role. The client signs every request using those credentials before sending. You never need to handle signing yourself - boto3 manages it transparently.

Error handling deserves explicit attention. All S3 errors surface as `botocore.exceptions.ClientError`. The error code is nested inside the response: `e.response["Error"]["Code"]`. Common codes include `NoSuchKey` (object does not exist), `NoSuchBucket` (bucket does not exist), `AccessDenied` (insufficient permissions), and `404` (returned by `head_object` when an object is missing). Throttling errors (`SlowDown`, `RequestLimitExceeded`) should be retried with exponential backoff - boto3's built-in retry logic handles these by default, but you can tune the retry configuration via `botocore.config.Config`.

```bash
# AWS CLI equivalents for reference
aws s3 cp local.csv s3://my-bucket/data/local.csv
aws s3 cp s3://my-bucket/data/local.csv ./downloaded.csv
aws s3 rm s3://my-bucket/data/local.csv
aws s3 ls s3://my-bucket/data/ --recursive
```

```python
import boto3
import json
from botocore.exceptions import ClientError
from boto3.s3.transfer import TransferConfig

s3 = boto3.client("s3")

# --- Upload ---

# upload_file: path -> S3 (recommended for local files, handles multipart)
s3.upload_file("model_weights.bin", "my-bucket", "models/v2/weights.bin")

# put_object: bytes/string -> S3 (good for small in-memory content)
s3.put_object(
    Bucket="my-bucket",
    Key="config/app.json",
    Body=json.dumps({"version": 2}).encode(),
    ContentType="application/json",
)

# upload_file with custom TransferConfig (tune multipart threshold and concurrency)
config = TransferConfig(
    multipart_threshold=16 * 1024 * 1024,   # 16MB - files larger than this use multipart
    max_concurrency=10,                       # parallel upload threads
    multipart_chunksize=16 * 1024 * 1024,    # 16MB per part
)
s3.upload_file("large_dataset.zip", "my-bucket", "data/dataset.zip", Config=config)

# --- Download ---

# download_file: S3 -> local path (handles multipart, retries)
s3.download_file("my-bucket", "models/v2/weights.bin", "weights.bin")

# get_object: returns StreamingBody - good for in-memory processing
response = s3.get_object(Bucket="my-bucket", Key="config/app.json")
content = response["Body"].read()  # safe for small objects
config_data = json.loads(content)

# Streaming a large file without loading it all into memory
response = s3.get_object(Bucket="my-bucket", Key="data/large.csv")
with open("output.csv", "wb") as f:
    for chunk in response["Body"].iter_chunks(chunk_size=1024 * 1024):  # 1MB chunks
        f.write(chunk)

# --- List ---

# Always use a paginator - list_objects_v2 returns at most 1000 per page
paginator = s3.get_paginator("list_objects_v2")
for page in paginator.paginate(Bucket="my-bucket", Prefix="data/"):
    for obj in page.get("Contents", []):
        print(f"{obj['Key']}  {obj['Size']}  {obj['LastModified']}")

# --- Delete ---

# Single object delete
s3.delete_object(Bucket="my-bucket", Key="data/old_file.csv")

# Batch delete (up to 1000 per call)
keys_to_delete = ["data/file1.csv", "data/file2.csv", "data/file3.csv"]
s3.delete_objects(
    Bucket="my-bucket",
    Delete={
        "Objects": [{"Key": k} for k in keys_to_delete],
        "Quiet": True,  # suppress per-object success responses
    },
)

# --- Error Handling ---

def get_object_safe(bucket: str, key: str) -> bytes | None:
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        return response["Body"].read()
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code in ("NoSuchKey", "404"):
            return None
        raise  # re-raise unexpected errors (AccessDenied, etc.)

# --- Object existence check (HEAD is cheaper than GET) ---
def object_exists(bucket: str, key: str) -> bool:
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "404":
            return False
        raise
```

---

## How It Connects

Before any boto3 call can succeed, the Python process needs AWS credentials with the appropriate IAM permissions. On EC2, this comes from the instance profile; locally, it comes from the credential file or environment variables. Understanding how boto3 discovers credentials prevents "NoCredentialsError" surprises in production.

[[boto3-basics|boto3 Basics]] - how boto3 is installed, configured, and how the credential chain works across different execution environments.

For large files, multipart upload is the underlying mechanism that makes `upload_file` reliable. Understanding when and why multipart kicks in is important for tuning timeouts and understanding costs.

[[s3-multipart-upload|S3 Multipart Upload]] - the mechanics of multipart upload, manual multipart control, and lifecycle rules to clean up incomplete uploads.

---

## Common Misconceptions

Misconception 1: `put_object` and `upload_file` are interchangeable - just pick whichever looks cleaner.
Reality: `put_object` makes a single HTTP request and loads the entire body into memory (or streams it as a single request). For objects larger than a few hundred megabytes this will fail with a timeout or an out-of-memory error. `upload_file` uses the S3 Transfer Manager, which automatically splits large files into parts, uploads them concurrently, and retries failed parts individually. For any file over about 10MB, use `upload_file`.

Misconception 2: `get_object` immediately returns the file content.
Reality: `get_object` returns a response dictionary. The `Body` key contains a `StreamingBody` object - a lazy reference to the HTTP response stream. The data has not been downloaded yet. You must call `.read()` on it (downloads everything into memory) or iterate it with `.iter_chunks()`. If you never read the `Body`, you will leak the underlying HTTP connection.

---

## Why It Matters in Practice

Almost every Python data pipeline, web application, and ML training job running on AWS touches S3. Getting the boto3 patterns right - particularly around pagination, error handling, and the transfer manager - is the difference between code that works in development (small files, empty buckets) and code that works reliably in production (gigabyte files, million-object buckets, transient network errors).

The streaming pattern for `get_object` is especially important for memory-constrained environments like Lambda or small EC2 instances. A Lambda function with 512MB of memory cannot load a 1GB file with `.read()` - it must stream the response body. Knowing when to stream versus when to load fully is a practical production skill.

---

## What Breaks in Production

**Reading a large StreamingBody with `.read()` in a Lambda function.**

```python
# Bad - loads entire 2GB file into Lambda memory (likely causes OOM)
response = s3.get_object(Bucket="ml-data", Key="training/dataset.parquet")
data = response["Body"].read()  # 2GB into memory

# Good - stream to a local /tmp file (Lambda has up to 10GB /tmp)
response = s3.get_object(Bucket="ml-data", Key="training/dataset.parquet")
with open("/tmp/dataset.parquet", "wb") as f:
    for chunk in response["Body"].iter_chunks(chunk_size=8 * 1024 * 1024):
        f.write(chunk)
```

**Not handling `delete_objects` partial failures.** `delete_objects` with `Quiet=False` returns both successful and failed deletions - but many developers only check the HTTP 200 status and miss that individual objects failed.

```python
response = s3.delete_objects(
    Bucket="my-bucket",
    Delete={"Objects": [{"Key": k} for k in keys], "Quiet": False},
)
failed = response.get("Errors", [])
if failed:
    for err in failed:
        print(f"Failed to delete {err['Key']}: {err['Code']} {err['Message']}")
    raise RuntimeError(f"{len(failed)} objects failed to delete")
```

---

## Interview Angle

Common question forms:
- "What is the difference between `upload_file` and `put_object` in boto3?"
- "How do you list all objects in an S3 bucket with Python?"
- "How do you download a large S3 file without running out of memory?"

Answer frame:
For `upload_file` vs `put_object`: explain the Transfer Manager, multipart threshold, and when each is appropriate. For listing: explain the 1000-object limit, the paginator API, and the `Prefix` filter. For large downloads: explain `StreamingBody`, `iter_chunks`, and the `/tmp` pattern in Lambda.

---

## Related Notes

- [[s3-overview|S3 Overview]]
- [[s3-buckets|S3 Buckets and Objects]]
- [[s3-multipart-upload|S3 Multipart Upload]]
- [[boto3-basics|boto3 Basics]]
- [[s3-presigned-urls|S3 Presigned URLs]]
