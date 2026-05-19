---
title: 04 - boto3 Basics
description: boto3 is the official AWS SDK for Python - it exposes every AWS service API through two interfaces (client and resource) and handles credential resolution, request signing, and error handling.
tags: [aws, cloud, layer-11, boto3, python]
status: draft
difficulty: beginner
layer: 11
domain: cloud
created: 2026-05-18
---

# boto3 Basics

> boto3 is the Python interface to all of AWS - understanding its two API surfaces, credential resolution order, pagination model, and error handling patterns is the foundation for every AWS interaction your Python code will make.

---

## Quick Reference

**Core idea:**
- Install: `pip install boto3`
- Two interfaces: `client` (low-level, 1:1 mapping to AWS API, returns dicts) and `resource` (high-level, object-oriented, not available for all services)
- `Session` encapsulates credentials and region; `boto3.client()` creates a default Session automatically
- Credential resolution order: env vars → `~/.aws/credentials` → AWS config file → IAM instance/container role
- Paginators handle multi-page API responses automatically - never loop manually with `NextToken`
- Waiters poll until a resource reaches a desired state - replaces manual `time.sleep` + retry loops
- All exceptions are `botocore.exceptions.ClientError` - check `e.response['Error']['Code']` for the specific error

**Tricky points:**
- The `resource` interface is not available for every service (e.g., no resource for Lambda or SQS) and is in maintenance mode - prefer `client` for new code
- boto3 is not thread-safe at the session level - create separate clients per thread, not a single shared client
- Paginator results must be iterated - they do not return all results at once; calling the non-paginated version on large data sets silently truncates results
- `ClientError` is raised for 4xx and 5xx HTTP errors; `EndpointResolutionError` and `NoRegionError` indicate configuration problems, not service errors
- boto3 does not retry by default on throttling for all services - configure a custom retry policy for high-throughput code

---

## What It Is

Think of boto3 as a bilingual interpreter who knows the dialect of every AWS service. AWS services speak HTTP - they accept signed JSON or XML requests and return JSON or XML responses. boto3 translates between Python idioms (function calls, dictionaries, exceptions) and the raw HTTP protocol of each AWS service. Without boto3, you would need to construct authentication headers using the SigV4 signing algorithm, handle retries, parse XML responses, and translate error codes - thousands of lines of boilerplate before writing a single line of application logic. boto3 handles all of this and presents you with a Python API that feels like calling a local library.

The library has two distinct personalities, called interfaces. The `client` interface is literal - it maps exactly to the underlying AWS API. Call `s3.put_object(Bucket='b', Key='k', Body=b'data')` and boto3 sends a `PUT` request to the S3 endpoint. The response is a raw Python dictionary matching the JSON structure AWS returned. The `resource` interface is interpretive - it wraps common operations in an object model. An S3 bucket becomes a Python object with methods like `bucket.put_object()` and attributes like `bucket.name`. Resources are more intuitive but incomplete; not all services have resource interfaces, and the resource interface is no longer receiving new features from AWS. For anything beyond basic S3 and EC2 operations, you will work with clients.

The Session is the foundation beneath both interfaces. It holds the resolved credentials (access key, secret key, session token) and the target region. When you call `boto3.client('s3')` without a Session, boto3 creates a default Session for you using its credential resolution logic. Understanding this resolution order - environment variables first, then credentials file, then IAM role - is what allows the same Python code to run on a developer laptop (using personal credentials) and on a Lambda function (using an attached IAM role) without any code changes.

---

## How It Actually Works

boto3 is built on botocore. When you call any boto3 method, botocore loads a service model (a JSON description of the AWS API for that service), constructs the HTTP request, signs it using SigV4, and dispatches it. The SigV4 algorithm creates a canonical form of the request (method, URL, headers, body hash), derives a signing key from your secret access key and today's date, and produces an HMAC-SHA256 signature. This signature is sent in the `Authorization` header. AWS verifies the signature server-side before processing the request. If credentials have expired (as happens with temporary credentials from IAM roles), the request fails with `ExpiredTokenException` and you need to refresh credentials.

Pagination is the most commonly mishandled aspect of boto3. Most AWS list APIs return at most 1000 (sometimes fewer) items per call and include a `NextToken` or `Marker` in the response indicating more pages exist. Calling the API without pagination silently returns only the first page. boto3 paginators handle this automatically - they are the correct tool for any operation that may return more results than fit in one API response.

```python
import boto3
from botocore.exceptions import ClientError
from botocore.config import Config

# Client interface (recommended for most services)
s3 = boto3.client('s3', region_name='us-east-1')

# Resource interface (object-oriented, not available for all services)
s3_resource = boto3.resource('s3', region_name='us-east-1')
bucket = s3_resource.Bucket('my-bucket')

# Explicit Session (useful for multi-account or multi-region code)
session = boto3.Session(
    region_name='eu-west-1',
    profile_name='my-profile'  # uses named profile from ~/.aws/config
)
s3_eu = session.client('s3')

# Paginator - always use for list operations
paginator = s3.get_paginator('list_objects_v2')
for page in paginator.paginate(Bucket='my-bucket', Prefix='logs/'):
    for obj in page.get('Contents', []):
        print(obj['Key'], obj['Size'])

# Waiter - polls until resource reaches desired state
ec2 = boto3.client('ec2', region_name='us-east-1')
waiter = ec2.get_waiter('instance_running')
waiter.wait(InstanceIds=['i-1234567890abcdef0'])
print("Instance is now running")

# Error handling - always check the specific error code
try:
    s3.get_object(Bucket='my-bucket', Key='missing-file.txt')
except ClientError as e:
    code = e.response['Error']['Code']
    if code == 'NoSuchKey':
        print("File does not exist")
    elif code == 'AccessDenied':
        print("Permission denied - check IAM policy")
    else:
        raise  # re-raise unexpected errors

# Custom retry configuration for high-throughput code
config = Config(
    retries={
        'max_attempts': 10,
        'mode': 'adaptive'  # exponential backoff with jitter
    }
)
s3_with_retries = boto3.client('s3', config=config)

# Check which identity boto3 is using (same as aws sts get-caller-identity)
sts = boto3.client('sts')
identity = sts.get_caller_identity()
print(f"Account: {identity['Account']}, ARN: {identity['Arn']}")
```

---

## How It Connects

boto3 is the Python-facing surface of the entire AWS ecosystem. Every note in the cloud layer that involves Python code goes through boto3. Understanding the credential resolution order here explains why the same code works on Lambda without configuration.

[[iam-role-python|IAM Roles with Python (boto3)]] - how boto3 automatically picks up IAM role credentials when running on Lambda, EC2, or ECS, and why this eliminates the need for access keys in application code.

The AWS CLI and boto3 share botocore - they use identical credential resolution and signing. Understanding one deeply transfers directly to the other.

[[aws-cli|AWS CLI]] - the command-line interface that shares botocore with boto3; CLI commands and boto3 calls are equivalent operations.

---

## Common Misconceptions

Misconception 1: "The resource interface is better than the client interface because it is more Pythonic."
Reality: The resource interface is more convenient for simple cases but is in maintenance mode - AWS is not adding new features to it. It does not cover all services, and for services where it does exist (S3, EC2, DynamoDB), the client is more complete and gives direct access to all API parameters. The resource interface also obscures pagination behaviour. New code should use the client interface.

Misconception 2: "I need to handle pagination manually by checking for NextToken in the response."
Reality: boto3 provides Paginators for this purpose. Manually handling `NextToken` is error-prone and verbose. `paginator = client.get_paginator('operation_name')` followed by `for page in paginator.paginate(**kwargs)` handles all pagination automatically, including rate limiting and retry on throttle.

Misconception 3: "boto3 will raise an exception if my IAM role does not have permission."
Reality: Some operations fail silently or return partial results when permissions are missing. For example, `describe_instances` with a resource-level policy that allows seeing only some instances will return only those instances without any error. Always verify the scope of permissions and test with the minimum expected data set to confirm you are seeing everything you expect.

---

## Why It Matters in Practice

boto3 is unavoidable for any Python application that interacts with AWS. Incorrect usage of boto3 - particularly failing to paginate, failing to handle errors, or using a single shared client across threads - causes production failures that are difficult to reproduce locally because they depend on data volume and concurrency. A developer who calls `list_objects_v2` without a paginator will have code that works correctly on a bucket with 50 objects and silently processes only the first 1000 objects on a bucket with 10,000.

The credential resolution order is equally important for security. A developer who tests locally using personal access keys and deploys to Lambda with an attached IAM role is relying on the credential resolution order to use the right credentials in each environment. If they accidentally set `AWS_ACCESS_KEY_ID` in the Lambda environment variables, those hardcoded keys override the IAM role - creating a security risk and breaking the automatic credential rotation that IAM roles provide.

---

## What Breaks in Production

**Scenario 1: Non-paginated list call silently truncates results.**

```python
# Wrong: returns at most 1000 objects, no error if bucket has more
response = s3.list_objects_v2(Bucket='my-bucket')
objects = response.get('Contents', [])
print(f"Processing {len(objects)} objects")  # May be 1000 even if 50,000 exist

# Right: use paginator
paginator = s3.get_paginator('list_objects_v2')
all_objects = []
for page in paginator.paginate(Bucket='my-bucket'):
    all_objects.extend(page.get('Contents', []))
print(f"Processing {len(all_objects)} objects")  # Gets all of them
```

**Scenario 2: Shared boto3 client across threads causes intermittent failures.**

```python
import boto3
import threading

# Wrong: single shared client is not thread-safe
shared_s3 = boto3.client('s3')

def upload_file(key, data):
    shared_s3.put_object(Bucket='my-bucket', Key=key, Body=data)  # race condition

# Right: create a client per thread (or use thread-local storage)
thread_local = threading.local()

def get_s3_client():
    if not hasattr(thread_local, 's3'):
        thread_local.s3 = boto3.client('s3', region_name='us-east-1')
    return thread_local.s3

def upload_file_safe(key, data):
    get_s3_client().put_object(Bucket='my-bucket', Key=key, Body=data)
```

**Scenario 3: Generic exception handling swallows actionable errors.**

```python
# Wrong: catches everything, loses the error detail
try:
    s3.put_object(Bucket='my-bucket', Key='file.txt', Body=b'data')
except Exception:
    print("Upload failed")  # No actionable information

# Right: structured error handling with specific codes
from botocore.exceptions import ClientError, NoCredentialsError

try:
    s3.put_object(Bucket='my-bucket', Key='file.txt', Body=b'data')
except NoCredentialsError:
    raise RuntimeError("No AWS credentials found - check IAM role or environment variables")
except ClientError as e:
    code = e.response['Error']['Code']
    if code == 'NoSuchBucket':
        raise ValueError(f"Bucket does not exist: my-bucket")
    elif code in ('RequestTimeout', 'SlowDown'):
        # Log and retry
        raise
    else:
        raise RuntimeError(f"Unexpected AWS error [{code}]: {e}")
```

---

## Interview Angle

Common question forms:
- "What is the difference between a boto3 client and a resource?"
- "How does boto3 find AWS credentials?"
- "How do you handle paginated responses in boto3?"

Answer frame:
Client is the low-level, service-complete interface returning raw dicts - preferred for production code. Resource is the high-level object-oriented interface, convenient but incomplete and in maintenance mode. Credential resolution goes: environment variables → credentials file → IAM role (instance/container metadata). For pagination, always use Paginators rather than manual NextToken handling. For error handling, catch `ClientError` and branch on `e.response['Error']['Code']` for specific behaviour.

---

## Related Notes

- [[aws-cli|AWS CLI]]
- [[iam-role-python|IAM Roles with Python (boto3)]]
- [[iam-assume-role|Assuming IAM Roles (STS)]]
- [[s3-python|S3 with Python]]
