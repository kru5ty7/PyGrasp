---
title: S3 Presigned URLs
description: A presigned URL is a time-limited, credential-embedded URL that grants temporary access to a private S3 object — enabling secure file downloads and direct browser-to-S3 uploads without exposing AWS credentials.
tags: [aws, cloud, layer-11, s3, presigned-urls, security]
status: draft
difficulty: intermediate
layer: 11
domain: cloud
created: 2026-05-18
---

# S3 Presigned URLs

> Presigned URLs let you grant temporary, scoped access to private S3 objects without changing any IAM policy or bucket policy — a pattern every Python web developer needs for user file downloads and direct browser uploads.

---

## Quick Reference

**Core idea:**
- A presigned URL encodes the AWS credentials, bucket, key, expiry time, and intended operation into a signed HTTPS URL
- Anyone with the URL can perform the specified operation (GET or PUT) until the URL expires — no AWS credentials needed
- Maximum expiry: 7 days for standard credentials, 1 hour for credentials obtained via STS (role assumption)
- GET presigned URL: lets anyone download a specific private object
- PUT presigned URL: lets a client upload directly to S3 without your server receiving the bytes

**Tricky points:**
- The URL grants access to everyone who has it — treat it like a capability token, not a session
- If generated with temporary credentials (IAM role, STS), the URL becomes invalid when those credentials expire, even if the URL's own expiry is longer
- The signing operation happens entirely client-side — no network call to AWS is needed to generate the URL
- PUT presigned URLs require the client to include the same `Content-Type` header that was embedded in the URL at generation time, or the upload will fail with `SignatureDoesNotMatch`
- GET presigned URLs bypass bucket policies and IAM — the object does not need to be public, and the requester does not need AWS credentials

---

## What It Is

Imagine a museum that keeps its collection in a locked vault. Normally, only staff with badge access can retrieve items. But occasionally a researcher outside the museum needs to study a specific artefact for a limited time. Rather than issuing the researcher a permanent badge or moving the artefact to a public gallery, the museum gives the researcher a one-time access voucher that is valid only for a specific item and only until Tuesday. The researcher presents the voucher at the door, retrieves the artefact, and when Tuesday arrives the voucher becomes worthless.

A presigned URL is that voucher. Your backend server generates it using AWS credentials (the "staff badge") and embeds the bucket, key, operation (GET or PUT), and expiry into a signed string. The signature is computed using your AWS secret key, so AWS can verify it when the URL is used — without the recipient ever learning your actual AWS credentials. The resulting URL is a normal HTTPS URL that any HTTP client (browser, curl, mobile app) can use directly.

The GET and PUT variants serve fundamentally different use cases. A GET presigned URL enables secure file distribution — you store files privately in S3 and generate a time-limited download link when a user requests it. This is how file-sharing services, invoice download endpoints, and ML model download pages typically work. A PUT presigned URL enables direct browser-to-S3 uploads — the user's browser sends the file bytes directly to S3 without those bytes ever passing through your application server. This eliminates a bottleneck: your server does not need to receive, buffer, and re-upload potentially large files.

---

## How It Actually Works

Presigned URL generation is a local cryptographic operation. boto3 signs the request parameters using your current credentials and returns the URL string — no network request is made to AWS at generation time. The URL itself contains all the information needed: the endpoint, the bucket and key, the HTTP method, the expiry timestamp, and a cryptographic signature. When the URL is used, S3 validates the signature, checks the expiry, and either serves the response or returns an error.

The expiry is expressed as a number of seconds from the moment of generation. Setting `ExpiresIn=3600` means the URL is valid for one hour. If you generate the URL with credentials obtained from an IAM role assumption (via STS), AWS imposes an additional constraint: the URL becomes invalid when the underlying role credentials expire, even if you set `ExpiresIn` to a longer value. Credentials from role assumptions expire in at most 12 hours (or 1 hour for certain IAM configurations), which caps the effective validity of presigned URLs generated in that context.

```bash
# AWS CLI — generate a presigned GET URL (1 hour expiry)
aws s3 presign s3://my-bucket/invoices/invoice-1234.pdf --expires-in 3600

# There is no native CLI command for presigned PUT URLs — use boto3 for that
```

```python
import boto3
from botocore.config import Config

s3 = boto3.client(
    "s3",
    region_name="eu-west-1",
    # Force path-style addressing for URL compatibility in some environments
    config=Config(signature_version="s3v4"),
)

# --- Presigned GET URL (private object download) ---
url = s3.generate_presigned_url(
    ClientMethod="get_object",
    Params={"Bucket": "my-bucket", "Key": "invoices/invoice-1234.pdf"},
    ExpiresIn=3600,  # 1 hour
)
print(url)
# https://my-bucket.s3.eu-west-1.amazonaws.com/invoices/invoice-1234.pdf?X-Amz-...

# In a Flask/Django view:
# return redirect(url)  or  return jsonify({"download_url": url})

# --- Presigned PUT URL (direct browser-to-S3 upload) ---
put_url = s3.generate_presigned_url(
    ClientMethod="put_object",
    Params={
        "Bucket": "my-bucket",
        "Key": f"uploads/user-123/profile.jpg",
        "ContentType": "image/jpeg",  # client MUST send this exact Content-Type header
    },
    ExpiresIn=300,  # 5 minutes — short expiry for upload URLs
)
# Return put_url to the client; client does an HTTP PUT to this URL with the file body

# --- Presigned POST (alternative for browser uploads — supports conditions) ---
response = s3.generate_presigned_post(
    Bucket="my-bucket",
    Key="uploads/user-123/${filename}",   # ${filename} is filled in by the client
    Fields={"Content-Type": "image/jpeg"},
    Conditions=[
        ["content-length-range", 1, 10 * 1024 * 1024],  # 1 byte to 10MB
        {"Content-Type": "image/jpeg"},
    ],
    ExpiresIn=300,
)
# response contains {"url": ..., "fields": {...}} — use as a multipart POST form
import requests
with open("photo.jpg", "rb") as f:
    requests.post(response["url"], data=response["fields"], files={"file": f})
```

---

## How It Connects

Presigned URLs bypass IAM evaluation for the object access itself — the IAM permissions that matter are those of the identity that generates the URL, not those of the recipient. The generating identity must have `s3:GetObject` (for GET presigned URLs) or `s3:PutObject` (for PUT presigned URLs) on the relevant key.

[[s3-permissions|S3 Bucket Policies and ACLs]] — understanding the permission model clarifies why presigned URLs bypass normal access control and what conditions can invalidate them.

In Python web applications, presigned URLs are commonly generated by a backend endpoint and returned to a frontend client. The Flask or FastAPI route generates the URL, the browser uses it directly. The application code that generates URLs typically runs on EC2 or Lambda and obtains its credentials from an instance profile or execution role.

[[iam-role-python|IAM Roles in Python]] — how Python code running on EC2 or Lambda acquires credentials for generating presigned URLs.

---

## Common Misconceptions

Misconception 1: A presigned URL for a private object only works if the object is made public.
Reality: Presigned URLs are specifically designed for private objects. The object's bucket policy does not need to allow public access. The URL itself contains the cryptographic proof of authorisation — S3 validates the signature and serves the object without requiring any public access settings.

Misconception 2: Setting `ExpiresIn=604800` (7 days) on a URL generated by an EC2 instance role always gives a 7-day URL.
Reality: EC2 instance role credentials are temporary — they are rotated roughly every 6 hours. When those credentials expire, any presigned URL generated with them becomes immediately invalid, regardless of the `ExpiresIn` value set at generation time. For long-lived presigned URLs, generate them using long-lived IAM user credentials (not recommended for security) or by calling `sts:AssumeRole` and setting the role session duration to the maximum.

---

## Why It Matters in Practice

Presigned URLs solve two critical design problems in user-facing applications. The first is private file distribution: you want to store user documents (receipts, medical records, tax forms) privately in S3 but let each user download their own files from the browser. A presigned GET URL with a 5-minute expiry is the standard solution — the server validates the user's session, generates the URL, and redirects. The second is upload performance: receiving large file uploads through an application server means the file travels from the browser to your server and then from your server to S3. With a presigned PUT URL, the file travels directly from the browser to S3 — cutting the time in half and removing load from your server.

---

## What Breaks in Production

**Generating presigned URLs on a Lambda function and setting `ExpiresIn` longer than the Lambda execution role's session duration.** The URL appears valid but expires whenever the role credentials rotate.

```python
# Bad — Lambda role credentials expire in 1 hour by default; URL silently becomes invalid sooner
url = s3.generate_presigned_url("get_object",
    Params={"Bucket": "b", "Key": "k"}, ExpiresIn=86400)  # 24 hours won't work

# Better — keep expiry short, or use a dedicated IAM user with generate_presigned_url
# For long-lived URLs, use CloudFront signed URLs or signed cookies with a key pair
```

**Mismatched `Content-Type` on presigned PUT.** The Content-Type header is part of the signed request. If the client sends a different Content-Type (or omits it), S3 returns `403 SignatureDoesNotMatch`.

```python
# Server generates with Content-Type
url = s3.generate_presigned_url("put_object",
    Params={"Bucket": "b", "Key": "k", "ContentType": "image/jpeg"},
    ExpiresIn=300)

# Client must set the exact same Content-Type header:
import requests
requests.put(url, data=file_bytes, headers={"Content-Type": "image/jpeg"})
# Omitting the header or using "image/png" will cause 403
```

---

## Interview Angle

Common question forms:
- "How would you let users download private S3 files from a web app?"
- "What is the difference between a presigned GET URL and a presigned PUT URL?"
- "Why do presigned URLs generated on Lambda sometimes expire earlier than expected?"

Answer frame:
For downloads: presigned GET URL generated server-side, short expiry, returned to the authenticated user. For PUT vs GET: GET serves an existing private object; PUT lets a client upload a new object directly to S3. For Lambda expiry: role credentials are short-lived; the presigned URL shares that lifetime; explain the STS session duration constraint.

---

## Related Notes

- [[s3-permissions|S3 Bucket Policies and ACLs]]
- [[s3-python|S3 with Python (boto3)]]
- [[iam-role-python|IAM Roles in Python]]
- [[iam-roles|IAM Roles]]
