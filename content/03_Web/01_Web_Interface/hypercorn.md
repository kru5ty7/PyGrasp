---
title: 08 - Hypercorn
description: "Hypercorn is a pure-Python ASGI server that supports HTTP/1.1, HTTP/2, and HTTP/3, making it the go-to choice when protocol breadth matters more than raw throughput."
tags: [hypercorn, asgi, http2, http3, server, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# Hypercorn

> Hypercorn is a pure-Python ASGI server that uniquely supports HTTP/1.1, HTTP/2, and HTTP/3 in a single package  -  the choice for Python deployments that need cutting-edge protocol support without relying on C extensions.

---

## Quick Reference

**Core idea:**
- Pure-Python ASGI server implementing HTTP/1.1, HTTP/2, and HTTP/3 (via QUIC)
- Works with any ASGI application: FastAPI, Starlette, Django Channels, Quart
- HTTP/3 support requires `pip install hypercorn[trio]` or `pip install hypercorn[asyncio]` plus optional QUIC dependencies
- Graceful shutdown is triggered by SIGTERM; `--graceful-timeout` sets how long to wait for in-flight requests
- Supports Trio as an alternative async backend alongside asyncio
- Configuration via CLI flags or a TOML/Python config file

**Tricky points:**
- HTTP/3 requires a TLS certificate  -  Hypercorn will not serve HTTP/3 over plain HTTP
- Raw throughput benchmarks typically show Hypercorn slower than uvicorn on HTTP/1.1 because uvicorn uses C-based `httptools` and `uvloop`
- `--workers` spawns multiple processes but uses Python's `multiprocessing`  -  each process runs its own asyncio event loop
- Trio and asyncio backends are not interchangeable; ASGI applications that use asyncio primitives directly may behave unexpectedly under Trio
- The `alt-svc` header must be served to inform browsers that HTTP/3 is available; Hypercorn does not automatically inject this for all deployments

---

## What It Is

A server room analogy: uvicorn is a sports car  -  fast on the track, uses a high-performance engine (uvloop, httptools in C), optimized for the most common race conditions. Hypercorn is a well-equipped touring vehicle  -  not the fastest in a straight line, but it handles a wider range of roads. It supports the HTTP/3 highway that most other Python servers cannot yet navigate, and it does so in pure Python without requiring C extensions to compile.

Hypercorn was created by Philip Jones, the same author as Quart (an async-native Flask-compatible framework). It emerged from the recognition that the ASGI ecosystem needed a server that prioritized protocol completeness over raw speed. While uvicorn reached production quality for HTTP/1.1 and partial HTTP/2 support, Hypercorn pushed further: full HTTP/2 compliance, HTTP/3 over QUIC, and support for both asyncio and Trio as event loop backends. This makes it the reference implementation for testing ASGI application behaviour across protocol versions.

The pure-Python constraint is a deliberate trade-off. By avoiding C extensions, Hypercorn is more portable  -  it runs on PyPy, on platforms without a C compiler, and in environments where installing compiled wheels is restricted. The cost is throughput: on HTTP/1.1 with CPU-bound parsing, uvicorn's `httptools` is noticeably faster. For I/O-bound async workloads  -  which most ASGI applications are  -  the gap shrinks considerably, and for workloads where HTTP/3 support is required, Hypercorn is currently the only Python ASGI server option.

---

## How It Actually Works

Starting Hypercorn from the command line mirrors the uvicorn interface:

```bash
hypercorn app:app --bind 0.0.0.0:8000
hypercorn app:app --bind 0.0.0.0:443 --certfile cert.pem --keyfile key.pem
hypercorn app:app --bind 0.0.0.0:443 --quic-bind 0.0.0.0:443 --certfile cert.pem --keyfile key.pem
```

The first form serves HTTP/1.1. The second adds TLS, which enables HTTP/2 negotiation via ALPN. The third adds `--quic-bind` to also bind a UDP port for HTTP/3. When a client connects over TLS, Hypercorn's ALPN negotiation selects the highest protocol version the client supports. Once the protocol is established, Hypercorn constructs the ASGI `scope` dictionary  -  for HTTP/2 and HTTP/3, the scope includes the same keys as HTTP/1.1 (`type`, `method`, `path`, `headers`) because the ASGI spec abstracts over protocol versions. The ASGI application receives the same interface regardless of whether the underlying transport is HTTP/1.1, HTTP/2, or HTTP/3.

Programmatic configuration is handled through a `Config` object:

```python
from hypercorn.config import Config
from hypercorn.asyncio import serve
import asyncio

config = Config()
config.bind = ["0.0.0.0:8000"]
config.workers = 4
config.graceful_timeout = 5.0

asyncio.run(serve(app, config))
```

This approach is useful in application entry-point scripts where the server needs to be started alongside other asyncio resources (such as a database connection pool opened during lifespan). Hypercorn's `serve()` coroutine runs inside the existing event loop, which means the ASGI lifespan events fire within the same loop context as everything else  -  a useful property for integration testing where you want to control the lifecycle precisely.

---

## How It Connects

Hypercorn's primary protocol differentiator is HTTP/3  -  understanding what HTTP/3 solves over HTTP/2 (transport-level head-of-line blocking via QUIC) explains why you would accept Hypercorn's lower HTTP/1.1 throughput in exchange for this capability.

[[http2-and-http3|HTTP/2 and HTTP/3]]

Hypercorn and uvicorn both implement the ASGI server specification  -  understanding ASGI is prerequisite knowledge for understanding what these servers actually do with an application.

[[asgi|ASGI]]

The direct performance and feature comparison between uvicorn and Hypercorn is the main reason to know both; the WSGI-vs-ASGI note provides the broader context for why the choice of ASGI server matters.

[[uvicorn|Uvicorn]]

---

## Common Misconceptions

Misconception 1: "Hypercorn is just a slower uvicorn and there's no reason to use it."
Reality: Hypercorn is the only Python ASGI server with production-ready HTTP/3 support. For deployments that need QUIC-based transport  -  high-latency networks, mobile clients with unreliable connections  -  that capability is not replicable with uvicorn at any performance level.

Misconception 2: "Pure Python means Hypercorn is too slow for production."
Reality: Most ASGI application latency is dominated by I/O  -  database queries, external API calls, and network round-trips  -  not HTTP parsing. In real workloads, Hypercorn's throughput disadvantage over uvicorn is rarely the bottleneck. Benchmarks that show large gaps use synthetic CPU-bound workloads that do not represent typical web application traffic.

Misconception 3: "HTTP/3 in Hypercorn works without a TLS certificate."
Reality: HTTP/3 runs on QUIC, which mandates TLS 1.3. There is no plaintext HTTP/3. For local development, a self-signed certificate (generated with `mkcert` or `openssl`) is required to test HTTP/3, and the browser must trust that certificate.

---

## Why It Matters in Practice

Hypercorn occupies a specific niche in the Python ASGI server landscape: reach for it when HTTP/3 support is a requirement, when deploying to environments where C extensions are unavailable or undesirable, or when building infrastructure that should work with both asyncio and Trio backends. In the Quart ecosystem, it is the natural server choice since both share an author and are designed to work together.

For most FastAPI or Starlette applications deployed behind a CDN, the CDN handles HTTP/3 from clients while Hypercorn or uvicorn handles the origin connection in HTTP/2 or HTTP/1.1. In this configuration, Hypercorn's HTTP/3 support is not needed for the origin. The operational case for Hypercorn becomes clear when you control the full connection from client to server and need the QUIC transport all the way through  -  niche, but increasingly relevant as HTTP/3 adoption grows.

---

## Interview Angle

Common question forms:
- "When would you choose Hypercorn over uvicorn?"
- "What ASGI servers support HTTP/3 in Python?"
- "Why is Hypercorn pure Python and what are the implications?"

Answer frame:
A strong answer to the first question leads with the HTTP/3 use case  -  Hypercorn is currently the only Python ASGI server with HTTP/3 support, so when QUIC transport is required (poor network conditions, mobile-heavy traffic without a CDN as middleman), it is the correct choice. The pure-Python aspect means lower HTTP/1.1 throughput compared to uvicorn's C-backed parsing, but in I/O-bound workloads the practical difference is small. Mentioning Trio support as a secondary differentiator demonstrates breadth of knowledge.

---

## Related Notes

- [[asgi|ASGI]]
- [[uvicorn|Uvicorn]]
- [[wsgi-vs-asgi|WSGI vs ASGI]]
- [[http2-and-http3|HTTP/2 and HTTP/3]]
- [[starlette|Starlette]]
