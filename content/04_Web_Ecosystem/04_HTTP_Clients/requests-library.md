---
title: 01 - requests Library
description: "requests is the standard Python library for synchronous HTTP calls, offering a clean API for GET/POST/PUT/DELETE requests with automatic JSON encoding, session reuse, and response deserialization."
tags: [requests, http-client, http, synchronous, layer-4, web-ecosystem]
status: draft
difficulty: beginner
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# requests Library

> requests is the "HTTP for humans" library  -  it turns the verbose, error-prone standard library `urllib` into a three-line operation and handles the tedious parts of HTTP for you.

---

## Quick Reference

**Core idea:**
- `requests.get(url, params={}, headers={}, timeout=10)`  -  synchronous GET; returns a `Response` object
- `requests.post(url, json={})`  -  POST with JSON body; sets `Content-Type: application/json` automatically
- `response.raise_for_status()`  -  raises `HTTPError` for 4xx/5xx; silent on 2xx
- `requests.Session()`  -  persistent connection pool, shared headers/cookies across requests
- Always set `timeout`  -  omitting it allows a request to hang indefinitely

**Tricky points:**
- `response.json()` raises `JSONDecodeError` if the response body is not valid JSON  -  check `response.ok` first when the server might return an error page
- `response.text` decodes with the encoding from the `Content-Type` header; `response.content` returns raw bytes  -  always use `.content` for binary data (images, files)
- `timeout=(connect_timeout, read_timeout)`  -  first value is the TCP connection timeout; second is the time to wait between bytes; `timeout=5` applies both as a single value
- `requests.Session.mount()` allows custom adapters  -  useful for retry logic via `HTTPAdapter` with `Retry`
- `requests` is thread-safe for concurrent use of the same `Session`, but sessions should not be shared across asyncio event loops

---

## What It Is

Python's built-in `urllib` can make HTTP requests, but it requires verbose boilerplate  -  manually constructing `Request` objects, handling redirects, decoding responses, and encoding query parameters. requests wraps all of this behind an API that matches how developers think about HTTP: you specify a method, a URL, some parameters, and you get a response back. The library handles encoding, redirection, cookies, authentication, and SSL verification without any explicit configuration.

The library became the de facto standard for Python HTTP because it solved a real friction point at the right level of abstraction. A JSON API call that requires ten lines with `urllib` takes three with requests. The `Response` object has intuitive attributes  -  `.status_code`, `.json()`, `.text`, `.headers`  -  that correspond directly to the parts of an HTTP response a developer cares about. The API is so widely adopted that many other libraries (httpx, for instance) explicitly mimic it.

The `Session` object is the production-grade way to use requests. A bare `requests.get()` creates a new TCP connection for every call and does not share headers or cookies between requests. A `Session` maintains a connection pool (reducing connection overhead for multiple requests to the same host), allows setting headers and authentication once that apply to all requests, and tracks cookies automatically. For any code that makes more than one HTTP call to the same service, a `Session` is the correct tool.

---

## How It Actually Works

The basic request/response pattern is straightforward. Every HTTP method has a corresponding function, and the `Response` object provides access to all parts of the response.

```python
import requests

# GET with query parameters
response = requests.get(
    "https://api.example.com/users",
    params={"page": 1, "limit": 50, "active": True},
    headers={"X-API-Key": "my-key"},
    timeout=10,
)
response.raise_for_status()  # raises requests.HTTPError for 4xx/5xx
users = response.json()      # parsed JSON as Python dict/list

# POST with JSON body
payload = {"name": "Alice", "email": "alice@example.com"}
response = requests.post(
    "https://api.example.com/users",
    json=payload,              # automatically sets Content-Type: application/json
    headers={"Authorization": "Bearer token123"},
    timeout=(3, 10),           # (connect_timeout, read_timeout) in seconds
)
response.raise_for_status()
new_user = response.json()

# File upload (multipart form)
with open("photo.jpg", "rb") as f:
    response = requests.post(
        "https://api.example.com/upload",
        files={"file": ("photo.jpg", f, "image/jpeg")},
    )

# Response attributes
print(response.status_code)    # 200
print(response.headers)        # dict-like response headers
print(response.text)           # decoded string body
print(response.content)        # raw bytes body
print(response.url)            # final URL (after redirects)
```

`Session` is preferred for any code that makes multiple requests to the same service.

```python
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

session = requests.Session()
session.headers.update({"Authorization": "Bearer token123", "Accept": "application/json"})

# Add retry logic with exponential backoff
retry_strategy = Retry(
    total=3,
    backoff_factor=1,           # sleep 1, 2, 4 seconds between retries
    status_forcelist=[429, 500, 502, 503, 504],
)
adapter = HTTPAdapter(max_retries=retry_strategy)
session.mount("https://", adapter)

# All requests through the session share headers and use the retry policy
response = session.get("https://api.example.com/data", timeout=10)
response2 = session.get("https://api.example.com/other", timeout=10)

# Use as context manager to ensure connections are closed
with requests.Session() as session:
    session.headers.update({"Authorization": "Bearer token123"})
    response = session.get("https://api.example.com/data")
```

---

## How It Connects

httpx is the async-capable successor that mirrors the requests API  -  switching from requests to httpx in async applications requires minimal code changes.

[[httpx|httpx]]

The `requests` library is synchronous and blocking  -  in async FastAPI applications, it blocks the event loop; httpx's async client is the correct replacement.

[[async-await|Async/Await]]

---

## Common Misconceptions

Misconception 1: "requests is suitable for use in async Python applications."
Reality: `requests` is entirely synchronous  -  every call occupies the calling thread until the response arrives. In an async FastAPI or asyncio application, this blocks the event loop and serializes all HTTP calls. Use `httpx.AsyncClient` or `aiohttp.ClientSession` for async HTTP in Python.

Misconception 2: "Not setting a timeout is fine for internal services that are always fast."
Reality: Network calls can hang indefinitely due to firewall drops, load balancer timeouts, or server bugs that stall the connection without closing it. An omitted timeout means the request thread is permanently occupied, eventually exhausting the thread pool. Always set a timeout, even if it is generous.

---

## Why It Matters in Practice

requests is the most downloaded Python package for a reason  -  virtually every Python developer will encounter it, whether writing scripts, calling third-party APIs, or testing HTTP services. Knowing the Session pattern for connection reuse, the `raise_for_status()` convention for error handling, the difference between `json=` and `data=` in POST requests, and when to switch to httpx for async code covers the practical API surface of the library.

---

## Interview Angle

Common question forms:
- "How do you make an authenticated HTTP request with requests?"
- "What is the difference between requests.get() and using a Session?"
- "Why should you always set a timeout?"

Answer frame:
`requests.get(url, headers={'Authorization': 'Bearer token'}, timeout=10)`. Session: persistent connection pool, shared auth headers/cookies across multiple requests to the same service  -  more efficient than individual calls. Always set timeout because TCP connections can hang indefinitely on network issues  -  a hung thread without a timeout permanently occupies resources. For async code, use `httpx.AsyncClient` instead.

---

## Related Notes

- [[httpx|httpx]]
- [[aiohttp-client|aiohttp Client]]
- [[http-basics|HTTP Basics]]
- [[rest|REST]]
