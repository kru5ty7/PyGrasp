---
title: 10 - gRPC Basics
description: "gRPC is a high-performance RPC framework that uses Protocol Buffers for serialization and HTTP/2 for transport."
tags: [grpc, protobuf, rpc, streaming, http2, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-18
---

# gRPC Basics

> gRPC is Google's open-source RPC framework that combines Protocol Buffers, HTTP/2, and generated code stubs to deliver strongly typed, high-throughput service-to-service communication  -  essential knowledge for any Python developer working in a polyglot microservices environment.

---

## Quick Reference

**Core idea:**
- `.proto` files define services and messages; `grpcio-tools` generates Python stubs from them
- Four RPC patterns: unary, server streaming, client streaming, and bidirectional streaming
- HTTP/2 is the mandatory transport; all streams run over one multiplexed connection
- Protocol Buffers serialize data as compact binary, not JSON  -  typically 3-10x smaller and faster to parse
- `grpcio` is the sync Python library; `grpc.aio` provides the async interface for asyncio applications
- gRPC uses status codes (OK, NOT_FOUND, UNAVAILABLE) that map differently from HTTP status codes

**Tricky points:**
- `.proto` schema changes must be backward-compatible: add fields (new field numbers), never reuse or remove numbers
- `grpc.aio` and `grpcio` stubs are not interchangeable  -  async stubs must be generated or wrapped explicitly
- gRPC does not natively work in browsers (requires grpc-web proxy) because browsers cannot control HTTP/2 framing
- Deadlines must be set explicitly; gRPC will wait indefinitely by default
- Interceptors are the gRPC equivalent of middleware and are the correct place for auth, logging, and retry logic

---

## What It Is

Imagine two departments in a large company that need to exchange information constantly. They could send memos in plain English (REST with JSON), but the recipient has to read each memo, parse the meaning, and decide what to do. Alternatively, they could agree on a shared form with numbered fields  -  the sender fills in field 3 (user ID) and field 7 (account balance), folds the form tightly, and hands it over. The recipient knows exactly what each field means because they have the same form definition. The overhead of interpretation disappears, and the envelope is much smaller. gRPC with Protocol Buffers is the second approach.

Google developed gRPC (initially called "Stubby") to handle the enormous volume of internal service-to-service calls across its data centres. The framework became open-source in 2015 and is now used extensively by companies running microservice architectures with high call volumes and strict latency requirements. The core insight is that service boundaries should be as efficient as in-process function calls, which requires strong contracts, compact serialization, and a transport protocol that does not waste round-trips.

The programming model feels like calling local functions. You define a service in a `.proto` file with named methods and typed request/response messages. The `protoc` compiler (via `grpcio-tools` in Python) reads that file and generates a client stub class and a server base class. Client code calls stub methods as if they were ordinary functions, and the framework handles serialization, connection management, and HTTP/2 framing transparently. The contract is enforced at compile time across every language with a protobuf plugin, which means a Python service and a Go service can call each other using types that are structurally guaranteed to match.

---

## How It Actually Works

A minimal gRPC Python workflow starts with a `.proto` file, runs `python -m grpc_tools.protoc` to generate `*_pb2.py` (message classes) and `*_pb2_grpc.py` (stubs and servicer base classes), then subclasses the generated servicer to implement business logic.

```python
# After running grpc_tools.protoc on a hello.proto:
import grpc
import hello_pb2
import hello_pb2_grpc

class GreeterServicer(hello_pb2_grpc.GreeterServicer):
    def SayHello(self, request, context):
        return hello_pb2.HelloReply(message=f"Hello, {request.name}")

# Server
server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
hello_pb2_grpc.add_GreeterServicer_to_server(GreeterServicer(), server)
server.add_insecure_port("[::]:50051")
server.start()
```

For async applications, `grpc.aio` replaces `grpc` in the import and servicer methods become `async def`. The four streaming patterns correspond to which side yields multiple messages: unary-unary is a single request and single response; server streaming sends one request and receives a stream of responses (useful for live data feeds); client streaming accumulates many requests before returning one response (useful for bulk uploads); bidirectional streaming allows both sides to send message sequences independently, which is useful for real-time communication between services with back-pressure control.

Interceptors are the extension point for cross-cutting concerns. A server-side interceptor wraps every RPC call, making it the right place to extract JWT tokens from metadata, validate them, and attach the authenticated identity to the context. A client-side interceptor can add retry logic, append authentication headers, or record call durations. The interceptor API differs between `grpc` and `grpc.aio`, and the async variant requires careful attention to how the continuation function is awaited.

---

## How It Connects

gRPC is built on HTTP/2 and cannot function without it  -  understanding HTTP/2 multiplexing and binary framing explains why gRPC can handle many concurrent streaming calls efficiently over a single connection.

[[http2-and-http3|HTTP/2 and HTTP/3]]

The ASGI server choice matters for gRPC in Python: gRPC has its own server (`grpc.server`), but frameworks like Starlette can be combined with gRPC through bridging libraries when you want both HTTP and gRPC on the same service.

[[asgi|ASGI]]

gRPC is often compared to REST  -  both are inter-service communication protocols, but they occupy different trade-off positions around typing strength, ecosystem tooling, and human debuggability.

[[rest|REST]]

---

## Common Misconceptions

Misconception 1: "gRPC is just REST with binary serialization."
Reality: gRPC and REST are fundamentally different in their communication model. REST is resource-oriented and stateless, with HTTP semantics. gRPC is procedure-oriented with a contract-first schema, four distinct streaming patterns, HTTP/2 as a hard dependency, and its own status code system. You can replace JSON with MessagePack in REST and get binary serialization without getting gRPC's streaming model or type safety.

Misconception 2: "gRPC is always faster than REST."
Reality: gRPC has lower serialization overhead and multiplexing benefits, but the actual latency advantage depends heavily on call patterns. For occasional large-payload requests, the difference is negligible. The gains are most pronounced for high-frequency small-message calls (e.g., health checks, telemetry) and streaming scenarios where HTTP/1.1 would require multiple connections.

Misconception 3: "I can call my gRPC service directly from a browser."
Reality: Browsers do not expose the HTTP/2 framing layer that gRPC requires. The grpc-web protocol is a workaround that requires an intermediary proxy (Envoy or a grpc-web-specific reverse proxy) to translate between the browser's restricted HTTP interface and actual gRPC. This is a significant operational addition.

---

## Why It Matters in Practice

gRPC is the dominant inter-service communication protocol in Kubernetes-based microservice systems. If you work in a polyglot environment  -  Python services calling Go or Java services, for example  -  gRPC's cross-language contract enforcement via `.proto` files eliminates entire categories of integration bugs. The generated stubs mean that a schema change in one service immediately surfaces as a compile-time error (or mypy error in Python) in its callers.

For Python specifically, the friction point is the code generation step. Unlike REST where you can write a client with a few lines of `httpx`, gRPC requires running `grpcio-tools` as part of your build process and managing generated files. Teams that solve this  -  either by committing generated files or building them in CI  -  gain significant reliability in service interfaces. `grpc.aio` integrates cleanly with FastAPI's async model when you need to make outbound gRPC calls from an ASGI application.

---

## Interview Angle

Common question forms:
- "When would you choose gRPC over REST for a Python service?"
- "What are the four types of gRPC calls?"
- "How does Protocol Buffers serialization differ from JSON?"

Answer frame:
A strong answer to the first question leads with use cases  -  high-throughput internal microservices, streaming data, polyglot environments  -  rather than just listing technical features. For the four RPC types, describing a concrete use case for each (unary for lookup, server streaming for live feeds, client streaming for bulk ingestion, bidirectional for real-time interaction) demonstrates practical understanding. For the serialization question, contrasting binary compact encoding with self-describing JSON and explaining why this matters for latency and bandwidth at scale is the core of a strong answer.

---

## Related Notes

- [[http2-and-http3|HTTP/2 and HTTP/3]]
- [[rest|REST]]
- [[asgi|ASGI]]
- [[async-await|Async/Await]]
- [[graphql-basics|GraphQL Basics]]
