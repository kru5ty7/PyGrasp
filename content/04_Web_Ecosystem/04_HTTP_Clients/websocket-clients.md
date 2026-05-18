---
title: 04 - WebSocket Clients
description: "WebSocket clients in Python maintain persistent bidirectional connections to servers, enabling real-time communication  -  the websockets library and aiohttp's built-in client are the primary async options."
tags: [websockets, websocket-client, aiohttp, real-time, layer-4, web-ecosystem]
status: draft
difficulty: intermediate
layer: 4
domain: web-ecosystem
created: 2026-05-18
---

# WebSocket Clients

> A WebSocket client maintains an open, full-duplex connection to a server  -  both sides can send messages at any time without the request/response overhead of HTTP.

---

## Quick Reference

**Core idea:**
- `websockets` library: `async with websockets.connect(uri) as ws: await ws.send('hello'); msg = await ws.recv()`
- aiohttp built-in: `async with session.ws_connect(url) as ws: await ws.send_str('hello'); msg = await ws.receive()`
- Connection lifecycle: connect -> HTTP upgrade handshake -> bidirectional messages -> close (4 states: CONNECTING, OPEN, CLOSING, CLOSED)
- `websockets.exceptions.ConnectionClosedError`: server closed the connection  -  handle explicitly for reconnect logic
- `httpx-ws` adds WebSocket support to httpx, useful for testing FastAPI WebSocket endpoints

**Tricky points:**
- WebSocket connections are long-lived  -  they are not request/response; the client must actively receive messages in a loop or tasks never arrive
- `await ws.recv()` blocks until a message arrives  -  run receiving in a dedicated coroutine when you need to both send and receive concurrently
- Servers can send `ping` frames that the client must respond to with `pong`  -  `websockets` handles this automatically; aiohttp requires explicit handling or `heartbeat` parameter
- Connection drops silently in some network configurations (firewalls, idle timeouts)  -  implement a heartbeat or reconnect loop for production clients
- Binary messages and text messages are different types  -  `ws.send(bytes)` vs `ws.send(str)`; receiving returns the appropriate type

---

## What It Is

HTTP is a request/response protocol: the client sends a request, the server sends a response, and the connection either closes or sits idle until the next request. This model works for fetching pages and calling APIs but is inefficient for real-time applications. A chat application where the client polls every second for new messages wastes bandwidth and introduces latency. A live dashboard that needs to display stock prices updating ten times per second cannot do so efficiently with polling.

WebSockets solve this by upgrading an HTTP connection into a persistent, bidirectional channel. The handshake starts as an HTTP request with an `Upgrade: websocket` header. If the server supports WebSockets, it responds with `101 Switching Protocols` and the connection transitions from HTTP to the WebSocket protocol. From that point, either side can send frames  -  text or binary messages  -  at any time without waiting for the other side to ask. The connection remains open until one side closes it.

A Python WebSocket client connects to a server endpoint and participates in this persistent channel. The `websockets` library is the pure-Python reference implementation for async WebSocket clients and servers. aiohttp's `ws_connect()` is an alternative that integrates naturally when aiohttp is already in use as an HTTP client. For testing FastAPI WebSocket endpoints, `httpx-ws` provides a synchronous and async testing interface that works with FastAPI's `TestClient`.

---

## How It Actually Works

The `websockets` library provides the cleanest async WebSocket client interface. The `async with websockets.connect(uri)` pattern manages the connection lifecycle, including the HTTP upgrade handshake and clean close on exit.

```python
import asyncio
import websockets
import json

async def websocket_client():
    uri = "wss://api.example.com/ws"

    async with websockets.connect(
        uri,
        extra_headers={"Authorization": "Bearer token"},
        ping_interval=20,   # send keepalive ping every 20 seconds
        ping_timeout=10,    # raise error if no pong within 10 seconds
    ) as ws:
        # Send a subscription message
        await ws.send(json.dumps({"action": "subscribe", "channel": "prices"}))

        # Receive loop  -  process messages until connection closes
        async for message in ws:
            data = json.loads(message)
            print(f"Received: {data}")

async def websocket_send_receive():
    """Client that both sends and receives concurrently."""
    async with websockets.connect("wss://echo.websocket.org") as ws:
        async def sender():
            for i in range(5):
                await ws.send(f"message {i}")
                await asyncio.sleep(1)
            await ws.close()

        async def receiver():
            try:
                async for msg in ws:
                    print(f"Echo: {msg}")
            except websockets.exceptions.ConnectionClosedOK:
                pass  # normal close

        await asyncio.gather(sender(), receiver())

asyncio.run(websocket_send_receive())
```

Reconnection logic handles the common case where the server drops the connection.

```python
import asyncio
import websockets
from websockets.exceptions import ConnectionClosedError, ConnectionClosedOK

async def resilient_client(uri: str):
    while True:
        try:
            async with websockets.connect(uri) as ws:
                async for message in ws:
                    await handle_message(message)
        except ConnectionClosedError as exc:
            print(f"Connection closed unexpectedly: {exc}. Reconnecting in 5s...")
            await asyncio.sleep(5)
        except ConnectionClosedOK:
            print("Server closed connection cleanly. Exiting.")
            break
```

aiohttp's WebSocket client integrates with an existing `ClientSession`.

```python
import aiohttp
import asyncio

async def aiohttp_ws_client():
    async with aiohttp.ClientSession() as session:
        async with session.ws_connect(
            "wss://api.example.com/ws",
            heartbeat=30,    # auto-ping every 30 seconds
        ) as ws:
            await ws.send_str(json.dumps({"subscribe": "events"}))

            async for msg in ws:
                if msg.type == aiohttp.WSMsgType.TEXT:
                    print(f"Text: {msg.data}")
                elif msg.type == aiohttp.WSMsgType.BINARY:
                    print(f"Binary: {len(msg.data)} bytes")
                elif msg.type == aiohttp.WSMsgType.ERROR:
                    print(f"Error: {ws.exception()}")
                    break
```

Testing FastAPI WebSocket endpoints uses `httpx-ws` or `starlette.testclient.TestClient`.

```python
from fastapi.testclient import TestClient
from myapp.main import app

def test_websocket_endpoint():
    client = TestClient(app)
    with client.websocket_connect("/ws") as ws:
        ws.send_text("hello")
        response = ws.receive_text()
        assert response == "hello back"
```

---

## How It Connects

aiohttp provides both an HTTP client and a WebSocket client  -  the `ClientSession` used for HTTP also handles WebSocket connections.

[[aiohttp-client|aiohttp Client]]

httpx-ws extends httpx's HTTP client testing capabilities to WebSocket endpoints, making it relevant to FastAPI testing patterns.

[[testing-fastapi|Testing FastAPI]]

---

## Common Misconceptions

Misconception 1: "WebSocket connections automatically reconnect if the server restarts."
Reality: A WebSocket connection is a persistent TCP connection. When the server closes or crashes, the TCP connection terminates. The client receives a `ConnectionClosedError` and must explicitly implement reconnection logic  -  the protocol does not provide automatic reconnection. Production clients always need a reconnect loop.

Misconception 2: "I can use a single WebSocket connection for all clients in my application."
Reality: A WebSocket connection is a 1:1 channel between one client and one server. It cannot be shared across multiple users or application components without explicit message routing. Each client (browser, service) maintains its own WebSocket connection to the server.

---

## Why It Matters in Practice

WebSocket clients appear in integrations with real-time APIs  -  financial data feeds, live collaboration services, notification systems, and browser DevTools protocols. Understanding the connection lifecycle, the distinction between text and binary frames, and the requirement for explicit reconnect logic prevents the most common WebSocket bugs: silent dropped connections and blocking receive loops that prevent concurrent sends.

---

## Interview Angle

Common question forms:
- "How do WebSockets differ from HTTP for real-time communication?"
- "How do you handle connection drops in a WebSocket client?"
- "How do you test a FastAPI WebSocket endpoint?"

Answer frame:
WebSockets: HTTP upgrade to persistent bidirectional channel  -  no request/response overhead, either side can send at any time. Connection drops: wrap the connection in a try/except for `ConnectionClosedError` and reconnect in a loop with a delay. Testing FastAPI WebSockets: `TestClient(app).websocket_connect('/ws')` provides a sync context manager for sending and receiving. `websockets` library for production async clients; `httpx-ws` for test clients.

---

## Related Notes

- [[aiohttp-client|aiohttp Client]]
- [[httpx|httpx]]
- [[http-basics|HTTP Basics]]
- [[async-await|Async/Await]]
- [[websockets|WebSockets (Server-Side)]]
