---
title: 08 - HTTP/2 and HTTP/3
description: "HTTP/2 and HTTP/3 overcome the performance limitations of HTTP/1.1 through multiplexing and a new transport protocol."
tags: [http2, http3, quic, multiplexing, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# HTTP/2 and HTTP/3

> HTTP/2 and HTTP/3 are revised versions of the HTTP protocol that eliminate the performance bottlenecks baked into HTTP/1.1  -  every Python developer building APIs or services should know when these improvements actually matter.

---

## Quick Reference

**Core idea:**
- HTTP/2 multiplexes multiple request/response streams over one TCP connection
- HTTP/2 uses HPACK header compression to reduce redundant metadata overhead
- HTTP/2 introduces a binary framing layer, replacing HTTP/1.1's plain-text format
- HTTP/3 replaces TCP with QUIC (UDP-based) to eliminate transport-level head-of-line blocking
- HTTP/3 supports 0-RTT connection resumption for returning clients
- Python's `httpx` supports HTTP/2 natively; `grpcio` requires HTTP/2 to function

**Tricky points:**
- HTTP/2 server push was deprecated in Chrome in 2022  -  it rarely helped in practice
- HTTP/2 still suffers head-of-line blocking at the TCP level; HTTP/3 solves this at the transport layer
- `httpx` requires `pip install httpx[http2]` which pulls in the `h2` library
- QUIC is UDP-based but provides its own reliability, ordering, and congestion control
- gRPC is built on HTTP/2 and will not fall back to HTTP/1.1

---

## What It Is

Think of HTTP/1.1 as a single-lane road where each car must wait for the car ahead to reach its destination before the next one can depart. You can open multiple parallel roads (TCP connections), but each road still has this constraint, and browsers cap how many roads they open per origin. HTTP/2 is the equivalent of converting that single lane into a multi-lane highway with a shared on-ramp: many requests travel over one connection simultaneously, none blocking the others.

HTTP/2 achieves this through a binary framing layer. Where HTTP/1.1 sends requests and responses as raw text that must be parsed line by line, HTTP/2 encodes everything as binary frames. Each frame carries a stream identifier, which allows the receiver to interleave frames from many concurrent exchanges and reassemble them independently. The connection itself remains one TCP connection  -  the multiplexing is a logical construct on top of it. Header compression via HPACK further reduces wire overhead because headers like `Content-Type` and `Authorization` are sent once and referenced by index on subsequent requests.

HTTP/3 addresses a remaining weakness. TCP is a reliable, ordered byte stream: if one packet is lost, the entire TCP connection stalls until that packet is retransmitted, even if other streams have no dependency on it. This is head-of-line blocking at the transport layer, and HTTP/2's multiplexing cannot escape it because all streams share one TCP connection. HTTP/3 moves to QUIC, a protocol built on UDP that implements its own reliability and ordering per stream. A lost packet only stalls the stream it belongs to. QUIC also embeds TLS 1.3 natively, which enables 0-RTT handshakes: a client that has previously connected can send application data in the very first packet without waiting for a full handshake round-trip.

---

## How It Actually Works

When an `httpx.AsyncClient` is created with `http2=True`, it negotiates the protocol using ALPN (Application-Layer Protocol Negotiation) during the TLS handshake. The server advertises `h2` in its supported protocols, the client matches it, and from that point all communication follows HTTP/2 framing. The `h2` state machine library (a dependency of `httpx[http2]`) manages stream IDs, flow control windows, and HPACK encoding. A single TCP socket handles all concurrent requests, and `asyncio` event loop callbacks demultiplex incoming frames back to the awaiting coroutines.

For server-side HTTP/2 in Python, `hypercorn` supports HTTP/2 and HTTP/3 out of the box. `uvicorn` supports HTTP/2 when built with the `uvloop` and `httptools` extras, but HTTP/3 support requires `hypercorn`. gRPC takes a different path: `grpcio` ships its own C-core that manages HTTP/2 framing directly, and `grpc.aio` wraps that in an asyncio-compatible interface. When building a Python microservice that will serve many small, frequent requests from a single client (such as a gRPC streaming call), HTTP/2's multiplexing removes the per-request connection overhead that would dominate latency in HTTP/1.1.

```python
import httpx

async def fetch_multiple():
    async with httpx.AsyncClient(http2=True) as client:
        # All requests share one HTTP/2 connection
        responses = await asyncio.gather(
            client.get("https://example.com/a"),
            client.get("https://example.com/b"),
            client.get("https://example.com/c"),
        )
    return responses
```

---

## How It Connects

HTTP/2 is the transport layer that makes gRPC possible  -  without multiplexing, bidirectional streaming RPCs could not coexist efficiently on a single connection.

[[grpc-basics|gRPC Basics]]

The websockets note covers a different approach to persistent, bidirectional communication that operates over a single upgraded HTTP connection and is unrelated to HTTP/2 streaming.

[[websockets|WebSockets]]

HTTP/2 and HTTP/3 are protocol-level concerns that sit below the application layer described in the request-response cycle note, but they change the timing and framing of that cycle significantly.

[[request-response-cycle|Request-Response Cycle]]

---

## Common Misconceptions

Misconception 1: "HTTP/2 means my site will be faster because requests are parallel."
Reality: HTTP/2 multiplexing helps most when a single client makes many requests to the same origin simultaneously. If your API serves one request per connection at a time, the improvement is minimal. The gain is primarily in browser page loads and high-fanout API patterns.

Misconception 2: "HTTP/3 is unstable or experimental and shouldn't be used in production."
Reality: HTTP/3 over QUIC is standardized in RFC 9114 (published May 2022) and is supported by all major browsers and CDNs. Cloudflare, Google, and Meta have run it at scale for years. The Python ecosystem support is still maturing, but the protocol itself is production-grade.

Misconception 3: "Switching from HTTP/1.1 to HTTP/2 requires changing my Python application code."
Reality: HTTP/2 is transparent to the application layer. A FastAPI or Django application running behind a reverse proxy that negotiates HTTP/2 (nginx, Caddy) will benefit without any code change. The ASGI/WSGI interface is unaffected.

---

## Why It Matters in Practice

For Python backend developers, HTTP/2 becomes directly relevant when working with gRPC, where it is not optional  -  gRPC requires HTTP/2 for all four RPC patterns. It also matters when writing HTTP clients that hit the same API host repeatedly: `httpx` with `http2=True` will reuse a single connection and multiplex requests, reducing latency and avoiding the connection pool exhaustion that can occur with high-concurrency HTTP/1.1 clients.

HTTP/3 is currently most relevant when deploying behind a CDN that supports it (traffic from users to Cloudflare or similar runs HTTP/3; traffic from Cloudflare to your Python origin typically runs HTTP/2). If you are deploying a service that needs to support poor network conditions  -  mobile clients, high-latency links  -  HTTP/3's resilience to packet loss makes a measurable difference, and `hypercorn` is the Python ASGI server to reach for when you need that support today.

---

## Interview Angle

Common question forms:
- "What problem does HTTP/2 solve over HTTP/1.1?"
- "What is head-of-line blocking and how does HTTP/3 address it?"
- "Why does gRPC require HTTP/2?"

Answer frame:
A strong answer explains HTTP/1.1's head-of-line blocking at the request level (one request per connection at a time, or multiple connections with browser limits), then explains HTTP/2's multiplexed streams as the solution. It then distinguishes between HTTP/2's TCP-level head-of-line blocking  -  which HTTP/2 does not solve  -  and HTTP/3's QUIC-based solution that isolates packet loss to individual streams. For gRPC, a strong answer connects the bidirectional streaming capability to HTTP/2's stream model and notes that the binary framing also aligns well with Protocol Buffers' binary encoding.

---

## Related Notes

- [[grpc-basics|gRPC Basics]]
- [[websockets|WebSockets]]
- [[http-basics|HTTP Basics]]
- [[request-response-cycle|Request-Response Cycle]]
- [[asgi|ASGI]]
