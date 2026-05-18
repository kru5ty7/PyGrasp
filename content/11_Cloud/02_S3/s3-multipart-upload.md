---
title: 22 - S3 Multipart Upload
description: S3 multipart upload splits large objects into parallel parts for faster, resumable uploads — required for objects over 5GB and strongly recommended for anything over 100MB.
tags: [aws, cloud, layer-11, s3, multipart, large-files]
status: draft
difficulty: advanced
layer: 11
domain: cloud
created: 2026-05-18
---

# S3 Multipart Upload

> Multipart upload is S3's mechanism for reliable large-file transfers — understanding it explains why `upload_file` in boto3 is more than just `put_object`, and why incomplete multipart uploads can silently cost money.

---

## Quick Reference

**Core idea:**
- Multipart upload splits an object into parts of 5MB–5GB each, uploads them independently (in parallel), then assembles them server-side
- Required for objects over 5GB; AWS rejects single-PUT requests above this limit
- boto3's `upload_file` uses multipart automatically for files over 8MB (configurable via `TransferConfig`)
- Manual multipart: `create_multipart_upload` → `upload_part` (repeat for each part) → `complete_multipart_upload`
- Incomplete multipart uploads accumulate and are billed for storage — a lifecycle rule to abort them is essential

**Tricky points:**
- Parts must be at least 5MB each, except for the last part — a 4MB part anywhere except the last position will cause `EntityTooSmall` on completion
- The upload ID from `create_multipart_upload` must be tracked; without it you cannot complete or abort the upload
- Each `upload_part` returns an ETag that must be collected and sent in the `complete_multipart_upload` call in the correct part order
- Aborting an incomplete upload does not delete parts immediately — AWS cleans them up asynchronously
- `TransferConfig.multipart_threshold` defaults to 8MB in boto3 — files smaller than this use a single PUT

---

## What It Is

Imagine sending a 50-page document by fax to someone across the world over a slow and unreliable telephone line. The conventional approach — send all 50 pages as a single transmission — means that if the line drops on page 49, you must start over from page 1. A smarter approach is to divide the document into groups of 10 pages, send each group separately, and let the recipient reassemble them. If the line drops during the fourth group, you only need to retransmit those 10 pages, not all 50.

S3 multipart upload is that smarter approach for large object transfers. You divide the object into parts, upload each part independently, and tell S3 to assemble the parts into the final object once all parts have arrived. The minimum part size is 5MB (except for the last part, which can be any size), and the maximum is 5GB. A 100GB file could be split into 1000 parts of 100MB each and uploaded with 10 simultaneous HTTP connections, finishing in roughly 1/10th of the sequential upload time.

The resumability benefit is equally important. If your application or network fails midway through a large upload, you do not need to restart from scratch. Parts that were successfully uploaded are already stored in S3. Your application can track which parts succeeded, resume by uploading only the failed parts, and then complete the assembly. This is particularly valuable for mobile applications uploading large video files over cellular networks, or data pipelines uploading multi-gigabyte dataset archives from on-premise servers.

---

## How It Actually Works

The multipart upload process has three distinct phases. In the first phase, you call `create_multipart_upload` with the bucket and key. S3 returns an upload ID — a unique identifier for this multipart upload session. You must store this ID; everything else in the process references it.

In the second phase, you call `upload_part` for each part, providing the upload ID, the part number (1 to 10,000), and the part body. Each `upload_part` call returns an ETag in the response. You must collect these ETags and their corresponding part numbers — they are required to complete the upload. Parts can be uploaded in parallel (using threads or asyncio) and in any order. The part number determines the assembly order, not the upload order.

In the third phase, you call `complete_multipart_upload` with the upload ID and a list of part numbers paired with their ETags, sorted by part number. S3 assembles the parts server-side and makes the final object available. If any part is missing or the ETags are wrong, the completion call fails. Alternatively, you can call `abort_multipart_upload` to cancel the session — this tells S3 to eventually delete the uploaded parts.

```bash
# AWS CLI handles multipart automatically for files over 8MB
aws s3 cp large_file.bin s3://my-bucket/data/large_file.bin

# Override multipart threshold and concurrency via CLI
aws s3 cp large_file.bin s3://my-bucket/data/large_file.bin \
    --multipart-threshold 64MB \
    --multipart-chunksize 64MB

# List incomplete multipart uploads (you're being billed for these)
aws s3api list-multipart-uploads --bucket my-bucket

# Abort a specific incomplete upload
aws s3api abort-multipart-upload \
    --bucket my-bucket \
    --key data/large_file.bin \
    --upload-id "VXBsb2FkIElEIGZvciA2aWWpbmcncyBteS1tb3ZpZS5tMnRzIHVwbG9hZA"
```

```python
import boto3
import threading
from boto3.s3.transfer import TransferConfig
from botocore.exceptions import ClientError

s3 = boto3.client("s3")

# --- Automatic multipart via upload_file (recommended for most cases) ---
config = TransferConfig(
    multipart_threshold=16 * 1024 * 1024,   # 16MB — use multipart above this
    max_concurrency=10,                       # simultaneous upload threads
    multipart_chunksize=16 * 1024 * 1024,    # 16MB per part
    use_threads=True,
)

def upload_with_progress(local_path: str, bucket: str, key: str):
    uploaded_bytes = [0]
    import os
    total_bytes = os.path.getsize(local_path)

    def progress_callback(bytes_transferred):
        uploaded_bytes[0] += bytes_transferred
        pct = uploaded_bytes[0] / total_bytes * 100
        print(f"\r{pct:.1f}% uploaded", end="", flush=True)

    s3.upload_file(local_path, bucket, key,
                   Config=config, Callback=progress_callback)
    print()

upload_with_progress("model_weights.bin", "my-bucket", "models/v3/weights.bin")

# --- Manual multipart upload (for fine-grained control or resumability) ---

def multipart_upload(bucket: str, key: str, file_path: str,
                     part_size: int = 16 * 1024 * 1024):
    # Phase 1: initiate
    response = s3.create_multipart_upload(Bucket=bucket, Key=key)
    upload_id = response["UploadId"]
    parts = []

    try:
        with open(file_path, "rb") as f:
            part_number = 1
            while True:
                data = f.read(part_size)
                if not data:
                    break
                # Phase 2: upload each part
                resp = s3.upload_part(
                    Bucket=bucket, Key=key,
                    PartNumber=part_number,
                    UploadId=upload_id,
                    Body=data,
                )
                parts.append({"PartNumber": part_number, "ETag": resp["ETag"]})
                print(f"Uploaded part {part_number} ({len(data)} bytes)")
                part_number += 1

        # Phase 3: complete
        s3.complete_multipart_upload(
            Bucket=bucket, Key=key,
            UploadId=upload_id,
            MultipartUpload={"Parts": parts},
        )
        print(f"Upload complete: s3://{bucket}/{key}")

    except Exception as e:
        # Abort on failure to avoid storage charges for orphaned parts
        s3.abort_multipart_upload(Bucket=bucket, Key=key, UploadId=upload_id)
        raise RuntimeError(f"Upload failed and was aborted: {e}") from e

multipart_upload("my-bucket", "data/large_dataset.parquet", "large_dataset.parquet")

# --- Lifecycle rule to abort incomplete multipart uploads (critical!) ---
s3.put_bucket_lifecycle_configuration(
    Bucket="my-bucket",
    LifecycleConfiguration={
        "Rules": [
            {
                "ID": "AbortIncompleteMultipartUploads",
                "Status": "Enabled",
                "Filter": {},
                "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 7},
            }
        ]
    },
)
```

---

## How It Connects

boto3's `upload_file` method abstracts multipart upload through the S3 Transfer Manager, which handles part splitting, concurrent uploads, retries, and cleanup. Understanding when the Transfer Manager activates and how to tune it connects the Python API surface to the underlying S3 protocol.

[[s3-python|S3 with Python (boto3)]] — `upload_file`, `download_file`, and `TransferConfig` are the high-level wrappers over multipart upload; understanding both layers is necessary for debugging upload failures and tuning throughput.

Incomplete multipart uploads generate storage costs. A lifecycle rule targeting `AbortIncompleteMultipartUpload` is the standard mitigation. Understanding lifecycle configuration is therefore a prerequisite for operating a bucket that receives large uploads.

[[s3-storage-classes|S3 Storage Classes]] — lifecycle rules that clean up incomplete multipart uploads use the same `put_bucket_lifecycle_configuration` API as storage class transitions; understanding the lifecycle rule structure applies to both.

---

## Common Misconceptions

Misconception 1: Once `create_multipart_upload` is called, S3 holds storage space for the final assembled object.
Reality: S3 charges storage for the uploaded parts as they arrive — not for the final assembled object. If you upload 10 parts of 100MB each and then abandon the upload without calling `complete_multipart_upload` or `abort_multipart_upload`, you are billed for 1GB of storage indefinitely. This is why a lifecycle rule to abort incomplete uploads after N days is not optional — it is a cost control requirement for any bucket that receives large uploads.

Misconception 2: `abort_multipart_upload` immediately frees the storage used by uploaded parts.
Reality: `abort_multipart_upload` marks the upload session as aborted, but S3 deletes the underlying part data asynchronously. You may continue to see the parts in `list_multipart_uploads` output and continue to be billed for them briefly after the abort call returns. The eventual deletion is guaranteed, but not instantaneous.

---

## Why It Matters in Practice

Any Python application that uploads files larger than a few hundred megabytes to S3 must use multipart upload — directly or indirectly through `upload_file`. Single-PUT requests for large files fail with timeouts or size limit errors. In ML workflows where model checkpoints can be tens of gigabytes and training datasets can be terabytes, multipart upload is not a nice-to-have — it is the only viable upload mechanism.

The incomplete upload cost issue is a real production gotcha. A data pipeline that crashes mid-upload and retries from scratch every hour can accumulate hundreds of gigabytes in orphaned parts within days. The first indication is usually a billing alert. The fix is a lifecycle rule on every bucket that receives large uploads, applied at bucket creation time.

---

## What Breaks in Production

**Creating parts smaller than 5MB in a manual multipart upload.** Any part except the last must be at least 5MB; otherwise `complete_multipart_upload` fails with `EntityTooSmall`.

```python
# Bad — 1MB chunk size means every part except the last is too small
for chunk in read_in_chunks(file, chunk_size=1 * 1024 * 1024):  # 1MB chunks
    s3.upload_part(Bucket=b, Key=k, PartNumber=n, UploadId=uid, Body=chunk)

# Good — minimum 5MB per part (use 8MB or 16MB in practice)
for chunk in read_in_chunks(file, chunk_size=8 * 1024 * 1024):  # 8MB chunks
    s3.upload_part(Bucket=b, Key=k, PartNumber=n, UploadId=uid, Body=chunk)
```

**Not aborting the multipart upload in the exception handler.** A crash or exception during the upload phase leaves orphaned parts that accumulate storage charges.

```python
upload_id = s3.create_multipart_upload(Bucket=bucket, Key=key)["UploadId"]
try:
    # ... upload parts ...
    s3.complete_multipart_upload(...)
except Exception:
    s3.abort_multipart_upload(Bucket=bucket, Key=key, UploadId=upload_id)
    raise  # re-raise after cleanup
```

---

## Interview Angle

Common question forms:
- "How does S3 multipart upload work, and when would you use it?"
- "What happens to incomplete multipart uploads and how do you handle them?"
- "What is the difference between `upload_file` and `put_object` for large files?"

Answer frame:
For multipart: three phases (create, upload parts in parallel, complete), minimum 5MB per part, part numbers determine assembly order. For incomplete uploads: parts accumulate and are billed; lifecycle rule with `AbortIncompleteMultipartUpload` is the standard fix. For `upload_file` vs `put_object`: `upload_file` uses the Transfer Manager which handles multipart automatically above the threshold; `put_object` is a single HTTP PUT that will fail or timeout for large files.

---

## Related Notes

- [[s3-python|S3 with Python (boto3)]]
- [[s3-buckets|S3 Buckets and Objects]]
- [[s3-storage-classes|S3 Storage Classes]]
- [[s3-overview|S3 Overview]]
