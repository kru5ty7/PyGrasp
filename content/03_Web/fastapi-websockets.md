---
title: WebSockets in FastAPI
description: "FastAPI handles WebSocket connections with `@app.websocket('/ws')` and a `WebSocket` parameter — `await websocket.accept()` upgrades the connection; `receive_text()`/`receive_bytes()` block until a message arrives; `WebSocketDisconnect` is raised when the client disconnects."
tags: [fastapi, websocket, WebSocket, WebSocketDisconnect, real-time, layer-3, web]
status: draft
difficulty: intermediate
layer: 3
domain: web
created: 2026-05-17
---

# WebSockets in FastAPI

> FastAPI handles WebSocket connections with `@app.websocket('/ws')` and a `WebSocket` parameter — `await websocket.accept()` upgrades the connection; `receive_text()`/`receive_bytes()` block until a message arrives; `WebSocketDisconnect` is raised when the client disconnects.

---

## Quick Reference

**Core idea:**
- `@app.websocket("/ws")` — WebSocket route decorator
- `websocket: WebSocket` — FastAPI injects the WebSocket connection object
- `await websocket.accept()` — completes the HTTP upgrade to WebSocket
- `await websocket.receive_text()` / `receive_bytes()` / `receive_json()` — wait for a message from client
- `await websocket.send_text(data)` / `send_bytes()` / `send_json(data)` — send to client
- `WebSocketDisconnect` — raised by `receive_*()` when client disconnects

**Tricky points:**
- `receive_text()` blocks until a message arrives OR the connection closes — always catch `WebSocketDisconnect`; not catching it leaves the exception unhandled
- WebSocket endpoints support path and query parameters just like HTTP endpoints — use `Depends()` for authentication in the upgrade request
- A WebSocket connection is stateful — you cannot use `response_model` or `status_code` decorators; send messages manually
- Broadcasting to multiple clients requires a connection manager (list or dict of active WebSocket objects); there's no built-in pub/sub
- `websocket.close(code=1000)` — explicitly close from server side; send a close frame before the connection ends

---

## What It Is

FastAPI WebSocket endpoints extend the familiar route decorator pattern to persistent bidirectional connections. Unlike HTTP endpoints that handle one request and return one response, a WebSocket endpoint runs a loop — it keeps receiving and sending messages until the client disconnects.

The challenge of WebSockets at scale is state management: each connected client is a live coroutine waiting on `receive_text()`. A broadcast (send to all connected clients) requires iterating all active connections, which must be tracked manually.

---

## How It Actually Works

Simple echo endpoint:
```python
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

app = FastAPI()

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            await websocket.send_text(f"Echo: {data}")
    except WebSocketDisconnect:
        pass  # client disconnected cleanly
```

Chat room with connection manager:
```python
class ConnectionManager:
    def __init__(self):
        self.active: list[WebSocket] = []
    
    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.active.append(ws)
    
    def disconnect(self, ws: WebSocket):
        self.active.remove(ws)
    
    async def broadcast(self, message: str):
        for conn in self.active:
            await conn.send_text(message)

manager = ConnectionManager()

@app.websocket("/chat/{room_id}")
async def chat_room(
    room_id: str,
    websocket: WebSocket,
    token: str = Query(...),  # authentication via query param
):
    user = verify_token(token)
    await manager.connect(websocket)
    try:
        while True:
            msg = await websocket.receive_text()
            await manager.broadcast(f"{user.name}: {msg}")
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        await manager.broadcast(f"{user.name} left")
```

JSON messaging:
```python
@app.websocket("/updates")
async def updates(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_json()
            # data is already a dict
            response = process(data)
            await websocket.send_json(response)
    except WebSocketDisconnect:
        pass
```

---

## How It Connects

WebSocket connections start with an HTTP upgrade request — understanding the WebSocket protocol explains the `accept()` step.
[[websockets|WebSockets]]

Authentication in WebSocket endpoints is done at upgrade time (before `accept()`) because there's no request/response model for per-message auth — use `Depends()` or query params.
[[fastapi-dependencies|FastAPI Dependencies]]

---

## Common Misconceptions

Misconception 1: "FastAPI automatically handles `WebSocketDisconnect`."
Reality: `receive_*()` raises `WebSocketDisconnect` when the client disconnects — if uncaught, it propagates as an unhandled exception. Always wrap the receive loop in `try/except WebSocketDisconnect`.

Misconception 2: "WebSocket endpoints scale automatically with multiple server instances."
Reality: Each server instance maintains its own set of active connections. A broadcast in one instance doesn't reach connections on other instances. Horizontal scaling requires a shared pub/sub (Redis, message broker) so all instances can relay messages to their local connections.

---

## Why It Matters in Practice

Live dashboard pushing server metrics:
```python
@app.websocket("/metrics")
async def metrics_stream(websocket: WebSocket, user = Depends(get_current_user)):
    await websocket.accept()
    try:
        while True:
            metrics = await collect_system_metrics()
            await websocket.send_json(metrics)
            await asyncio.sleep(1)
    except WebSocketDisconnect:
        pass
```

The server pushes data every second without the client polling — each `send_json` is one WebSocket frame sent over the persistent TCP connection.

---

## Interview Angle

Common question forms:
- "How do you implement a chat server in FastAPI?"
- "How do you handle disconnections in FastAPI WebSockets?"

Answer frame: `@app.websocket("/path")` + `async def handler(websocket: WebSocket)` — call `await websocket.accept()` then loop `receive_text()` / `send_text()`. Catch `WebSocketDisconnect` to handle disconnects. Broadcasting requires a connection manager (list of active WebSocket objects). Authentication: check token before `accept()` or via `Depends()` on query param. Scaling: Redis pub/sub to share messages across instances.

---

## Related Notes

- [[websockets|WebSockets]]
- [[fastapi|FastAPI]]
- [[fastapi-dependencies|FastAPI Dependencies]]
- [[async-await|Async and Await]]
