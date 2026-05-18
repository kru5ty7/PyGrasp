---
title: 07 - WebSockets
description: "WebSockets provide full-duplex, persistent connections over a single TCP connection  -  the client sends an HTTP upgrade request, the server responds with `101 Switching Protocols`, and both sides can send messages at any time; used for real-time features like chat, live updates, and notifications."
tags: [websockets, full-duplex, upgrade, ws, wss, real-time, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# WebSockets

> WebSockets provide full-duplex, persistent connections over a single TCP connection  -  the client sends an HTTP upgrade request, the server responds with `101 Switching Protocols`, and both sides can send messages at any time; used for real-time features like chat, live updates, and notifications.

---

## Quick Reference

**Core idea:**
- WebSocket connection starts as an HTTP/1.1 `GET` with `Upgrade: websocket` header
- Server responds with `101 Switching Protocols`  -  the TCP connection is now a WebSocket connection
- Both client and server can send **frames** at any time (full-duplex, bidirectional)
- `ws://`  -  plain WebSocket; `wss://`  -  WebSocket over TLS (use `wss://` always in production)
- Messages can be text (UTF-8) or binary (bytes); framing is handled by the protocol

**Tricky points:**
- WebSocket connections are stateful and long-lived  -  each connected client is a persistent coroutine in async servers; resource usage scales with connection count, not request rate
- Standard HTTP load balancers often don't support WebSockets without explicit configuration (sticky sessions or WebSocket-aware LB)
- WebSockets bypass HTTP's request-response semantics  -  no built-in authentication per-message; authenticate on connect (validate token in the upgrade request), then trust the connection
- `ping`/`pong` frames keep connections alive through proxies/firewalls that close idle TCP connections
- Reconnection is the client's responsibility  -  the server cannot initiate reconnect after a disconnect

---

## What It Is

HTTP is a request-response protocol: client asks, server answers, connection closes (or waits for next request). WebSockets flip this  -  after the upgrade, either side can send a message at any time without waiting for a request. This is necessary for real-time applications: a chat server needs to push new messages to all connected clients immediately, not wait for each client to poll.

The upgrade handshake reuses the existing HTTP infrastructure (ports 80/443, TLS) but then hands the connection to the WebSocket protocol. The result is a bidirectional message channel with minimal framing overhead compared to HTTP polling.

---

## How It Actually Works

WebSocket upgrade handshake:
```http
-> GET /ws HTTP/1.1
   Host: example.com
   Upgrade: websocket
   Connection: Upgrade
   Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
   Sec-WebSocket-Version: 13

<- HTTP/1.1 101 Switching Protocols
   Upgrade: websocket
   Connection: Upgrade
   Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

After this, the connection is no longer HTTP  -  messages are sent as WebSocket frames.

FastAPI WebSocket endpoint:
```python
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

app = FastAPI()

connected: list[WebSocket] = []

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    connected.append(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            # broadcast to all connected clients
            for conn in connected:
                await conn.send_text(f"Message: {data}")
    except WebSocketDisconnect:
        connected.remove(websocket)
```

Client-side (JavaScript):
```javascript
const ws = new WebSocket("wss://api.example.com/ws");
ws.onmessage = (event) => console.log(event.data);
ws.send("hello");
```

---

## How It Connects

WebSockets start as an HTTP upgrade  -  understanding HTTP request flow explains the handshake.
[[http-basics|HTTP Basics]]

Async servers (FastAPI + Uvicorn) handle WebSockets as long-lived coroutines  -  each connected client runs `await websocket.receive_text()` which yields to the event loop.
[[async-await|Async and Await]]

---

## Common Misconceptions

Misconception 1: "WebSockets are always better than polling."
Reality: For low-frequency updates (checking a job status every 30 seconds), long-polling or Server-Sent Events (SSE) are simpler and lower overhead than WebSockets. WebSockets shine for high-frequency, bidirectional updates (chat, multiplayer games, live collaboration).

Misconception 2: "WebSockets work through all proxies automatically."
Reality: Some proxies and firewalls don't support the `Upgrade` header and will block or corrupt WebSocket connections. Production deployments need WebSocket-aware proxies (Nginx with `proxy_read_timeout`, AWS ALB with WebSocket support enabled, etc.).

---

## Why It Matters in Practice

Use cases:
- **Chat**: server pushes messages to all participants as they arrive
- **Live dashboards**: server pushes updated metrics without client polling
- **Collaborative editing**: bi-directional document changes (Google Docs style)
- **Notifications**: server pushes alerts without repeated HTTP polling

Scaling WebSockets: because connections are long-lived, a single server instance maintains many persistent TCP connections. Horizontal scaling requires a shared pub/sub backend (Redis pub/sub, message queue) so messages can be routed to connections on other server instances.

---

## Interview Angle

Common question forms:
- "How does a WebSocket connection start?"
- "When would you use WebSockets vs HTTP polling?"

Answer frame: WebSocket starts with HTTP GET + `Upgrade: websocket` header -> server responds `101 Switching Protocols` -> TCP connection becomes a WebSocket channel. Full-duplex: both sides send at any time. Use WebSockets for high-frequency bidirectional updates (chat, live collab). Use SSE for server-to-client only streams. Use HTTP polling for low-frequency status checks. Scaling challenge: persistent connections need a pub/sub broker for multi-instance deployments.

---

## Related Notes

- [[http-basics|HTTP Basics]]
- [[fastapi-websockets|WebSockets in FastAPI]]
- [[asgi|ASGI]]
- [[async-await|Async and Await]]
