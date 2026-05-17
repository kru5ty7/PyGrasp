---
title: 05 - gRPC Design
description: "Protocol buffers, service definitions, streaming RPCs, and when gRPC's efficiency over REST/JSON makes it the right choice for service-to-service communication."
tags: [grpc, protobuf, rpc, streaming, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# gRPC Design

> gRPC is what you use when the overhead of JSON serialization and HTTP/1.1 connection management matters — and in high-throughput internal service communication, it often does.

---

## Quick Reference

**Core idea:**
- gRPC uses Protocol Buffers (protobuf) for binary serialization — 5-10x smaller and faster than JSON
- Service contracts are defined in `.proto` files; client and server code is generated from them
- HTTP/2 multiplexing: multiple RPC calls share one connection, eliminating connection overhead
- Four communication patterns: unary, server streaming, client streaming, bidirectional streaming
- gRPC is best for internal service-to-service communication; REST/GraphQL for external APIs

**Tricky points:**
- Proto definitions are schemas — changing them requires backward-compatible field numbering
- gRPC requires HTTP/2, which not all load balancers and proxies support natively
- Browser clients cannot call gRPC directly without grpc-web or a translation layer
- Protobuf field numbers are permanent — once a field is used, that number must always represent the same field
- Error handling uses gRPC status codes (not HTTP status codes) — they map differently

---

## What It Is

Imagine two offices in the same building, connected by a pneumatic tube system. Instead of sending full letters with envelopes and stamps (HTTP/1.1 with JSON), they send compact encoded notes using an agreed-upon shorthand notation (protobuf). The tube allows multiple notes to travel simultaneously without waiting for one to arrive before sending the next (HTTP/2 multiplexing). Both offices know exactly what format each type of message takes because they shared a protocol document when the system was built (the `.proto` schema).

gRPC (Google Remote Procedure Call) is a high-performance, open-source RPC framework developed by Google and released in 2016. It builds on Protocol Buffers (protobuf) for message serialization and HTTP/2 for transport, combining three performance advantages: binary serialization (smaller messages), multiplexed connections (no per-request connection overhead), and code generation (strongly typed clients and servers from a schema definition).

Protocol Buffers are Google's language-neutral binary serialization format. Instead of human-readable key-value JSON (`{"user_id": 1234, "name": "Alice"}`), protobuf encodes data as binary with field numbers as keys. The schema defines the encoding: field 1 is user_id (int32), field 2 is name (string). The encoded binary is 2–10x smaller than equivalent JSON and decodes 5–10x faster. The tradeoff is that binary data is not human-readable — debugging requires protobuf decoders.

Service definitions in `.proto` files specify the contract between client and server. A service has RPC methods; each method has a request message type and a response message type. Running the `protoc` compiler generates client stub code and server interface code in any supported language (Python, Go, Java, C++, and more). The generated code handles serialization, deserialization, and transport transparently. The developer writes business logic against the generated interface.

---

## How It Actually Works

The four gRPC communication patterns serve different use cases. Unary RPC is the classic request-response: the client sends one request and waits for one response. This is the direct equivalent of a REST GET or POST. Server streaming RPC: the client sends one request and the server responds with a stream of messages. This is appropriate for long-running operations that produce incremental results (e.g., streaming search results, progress updates). Client streaming: the client sends a stream of messages and the server responds once. Appropriate for bulk uploads or aggregation. Bidirectional streaming: both client and server send streams simultaneously. Appropriate for real-time two-way communication.

HTTP/2 multiplexing is a significant performance advantage over HTTP/1.1. HTTP/1.1 processes one request at a time per connection (or requires multiple connections for concurrency). HTTP/2 allows multiple requests and responses to be interleaved on a single TCP connection, eliminating the latency of opening new connections for concurrent requests. For microservices making many parallel downstream calls, this reduces connection overhead substantially.

```proto
// user_service.proto — service definition
syntax = "proto3";
package user;

service UserService {
  rpc GetUser (GetUserRequest) returns (UserResponse);
  rpc ListUsers (ListUsersRequest) returns (stream UserResponse);  // server streaming
  rpc BatchCreateUsers (stream CreateUserRequest) returns (BatchCreateResponse);  // client streaming
}

message GetUserRequest {
  string user_id = 1;   // field number 1 — permanent identifier
}

message UserResponse {
  string id = 1;
  string name = 2;
  string email = 3;
  int64 created_at = 4;  // unix timestamp
}

message ListUsersRequest {
  int32 limit = 1;
  string cursor = 2;
}

message CreateUserRequest {
  string name = 1;
  string email = 2;
}

message BatchCreateResponse {
  repeated string created_ids = 1;
  int32 success_count = 2;
  int32 failure_count = 3;
}
```

```python
# Python gRPC server implementation (generated code + business logic)
import grpc
from concurrent import futures
import user_pb2          # generated from user_service.proto
import user_pb2_grpc     # generated service stubs

class UserServicer(user_pb2_grpc.UserServiceServicer):
    """Server-side implementation of the UserService."""

    def GetUser(self, request, context):
        user = db.get_user(request.user_id)
        if not user:
            context.set_code(grpc.StatusCode.NOT_FOUND)
            context.set_details(f"User {request.user_id} not found")
            return user_pb2.UserResponse()

        return user_pb2.UserResponse(
            id=user["id"],
            name=user["name"],
            email=user["email"],
            created_at=int(user["created_at"].timestamp())
        )

    def ListUsers(self, request, context):
        """Server streaming: yield one response per user."""
        users = db.list_users(limit=request.limit, cursor=request.cursor)
        for user in users:
            yield user_pb2.UserResponse(
                id=user["id"], name=user["name"], email=user["email"]
            )

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    user_pb2_grpc.add_UserServiceServicer_to_server(UserServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

# Python gRPC client
def get_user_via_grpc(user_id: str) -> dict:
    with grpc.insecure_channel('user-service:50051') as channel:
        stub = user_pb2_grpc.UserServiceStub(channel)
        try:
            response = stub.GetUser(
                user_pb2.GetUserRequest(user_id=user_id),
                timeout=5.0  # 5 second deadline
            )
            return {"id": response.id, "name": response.name, "email": response.email}
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.NOT_FOUND:
                return None
            raise
```

Schema evolution in protobuf requires field number discipline. Once you assign field number 1 to `user_id`, that field number must always mean `user_id`. If you want to rename the field, you can change the name in the `.proto` file (names are not encoded in the binary format — only numbers are), but you must keep the field number the same. To add a new field, use a new field number. To remove a field, mark it as `reserved` to prevent future reuse of that number. Never reuse field numbers for different fields — this creates backward compatibility nightmares.

---

## How It Connects

gRPC is primarily for service-to-service communication. The API gateway handles external client traffic in REST or GraphQL; internally, services may communicate via gRPC.

[[api-gateway|API Gateway]]

gRPC and GraphQL solve different problems. GraphQL is for flexible client-driven queries. gRPC is for efficient, strongly-typed service-to-service calls with streaming support.

[[graphql-design|GraphQL Design]]

gRPC's streaming capabilities overlap with WebSocket use cases for real-time communication, though they serve different architectural positions (internal service calls vs browser connections).

[[websockets|WebSockets]]

---

## Common Misconceptions

Misconception 1: "gRPC is always faster than REST."
Reality: gRPC is faster than REST in specific dimensions: message serialization (binary vs JSON) and connection management (HTTP/2 multiplexing). For simple, infrequent request-response calls, the performance difference may be imperceptible. gRPC's advantages are most apparent for high-throughput internal service communication, large payloads, or streaming data.

Misconception 2: "I can use gRPC for my public API instead of REST."
Reality: Browsers cannot call gRPC directly without grpc-web, which adds a translation layer. Most developer tooling for public APIs (Postman, curl, API explorers) has better REST support than gRPC support. Unless your public API consumers all use gRPC client libraries, REST is more accessible for external-facing APIs.

Misconception 3: "Changing a field name in a .proto file breaks existing clients."
Reality: In protobuf, field names are not encoded in the binary — only field numbers are. Renaming a field in the `.proto` file changes the generated code (so existing code must be recompiled), but it does not change the binary encoding and is backward compatible with already-compiled binaries. Changing a field number, however, is a breaking binary change.

---

## Why It Matters in Practice

gRPC is particularly relevant in Python ML pipelines and microservices. Model serving frameworks like TensorFlow Serving expose gRPC endpoints. Large systems use gRPC for internal service-to-service calls because of the performance advantages and the contract enforcement provided by proto definitions. The schema-first development workflow — define the proto, generate both client and server code — ensures that client and server always agree on the interface.

For Python developers, grpc-io and the grpcio package make implementing gRPC servers and clients straightforward. The generated stubs handle all the serialization and transport complexity. The main investment is in learning protobuf schema design and the schema evolution rules.

---

## Interview Angle

Common question forms:
- "What is gRPC and when would you use it over REST?"
- "What are the advantages of Protocol Buffers over JSON?"
- "Describe the four gRPC communication patterns."

Answer frame:
Define gRPC: binary serialization (protobuf) + HTTP/2 transport + code generation from schema. List advantages: smaller messages, faster serialization, multiplexed connections, strongly typed contracts. Describe the four patterns: unary, server streaming, client streaming, bidirectional. When to use gRPC: internal service-to-service, high-throughput, streaming data, polyglot teams (proto is language-agnostic). When to use REST: external APIs, browser clients, developer tooling needs simplicity.

---

## Related Notes

- [[api-design-principles|API Design Principles]]
- [[graphql-design|GraphQL Design]]
- [[api-gateway|API Gateway]]
- [[grpc-basics|gRPC Basics]]
- [[model-serving|Model Serving]]
