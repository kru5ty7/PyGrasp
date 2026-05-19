---
title: 04 - Design a Chat System
description: "A walkthrough of designing a real-time chat system  -  WebSocket management, message storage, online presence, and the fanout challenge for group chats."
tags: [system-design, case-study, chat, websockets, layer-7]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Design a Chat System

> A chat system is the canonical real-time system design problem. It surfaces the websocket connection management challenge, the stateful server problem, the message persistence trade-off, and the fanout problem for group chats  -  all in a single, relatable package.

---

## Quick Reference

**Core idea:**
- WebSocket connections are stateful: a client maintains a persistent connection to one chat server
- Message routing: when User A sends a message, the chat server must find which server holds User B's connection
- A message router service (or Redis pub/sub) bridges connections across different chat servers
- Message persistence: store all messages in a database; clients load history on reconnect via REST
- Online presence: a heartbeat mechanism + Redis TTL tracks who is currently connected

**Key design decisions:**
- WebSocket vs long polling vs SSE: WebSocket is bidirectional and efficient; long polling is simpler but wasteful; SSE is server-to-client only
- Message storage: NoSQL (Cassandra, HBase) handles high write throughput and time-ordered retrieval efficiently; use (channel_id, message_id) as the partition + clustering key
- Group chat fanout: a message to a 500-member group requires 500 WebSocket sends  -  this must be done asynchronously
- Message ID: use a Snowflake-style time-ordered ID so messages sort correctly without a separate timestamp index
- Offline delivery: messages sent while a user is offline are stored and delivered on reconnect

---

## What It Is

A chat system is a problem of coordinating real-time bidirectional communication between users who are connected to potentially different servers. Consider a simple two-person chat: Alice is connected to Server 1, Bob is connected to Server 2. When Alice sends Bob a message, Server 1 receives the message but does not hold Bob's connection. It must somehow route the message to Server 2, which then pushes it to Bob over his WebSocket. This routing problem  -  which server is each user connected to?  -  is the central architectural challenge.

The requirements divide clearly. Functional: one-on-one messaging, group messaging (up to a few hundred members), message history (messages persist and load on reconnect), and online presence indicators. Non-functional: low latency (messages should arrive in under 100ms for users in the same region), high availability (chat must work even when some servers fail), and consistency (users should not miss messages or see them out of order).

The scale for a major chat system is extreme. WhatsApp handles over 100 billion messages per day  -  roughly 1.1 million messages per second. Even at smaller scale, a system serving 10 million daily active users each sending 20 messages per day is handling 2,000 messages per second at peak. The write throughput requirements rule out a simple relational database as the message store.

---

## How It Actually Works

**WebSocket connection management** is the first component. Clients establish a WebSocket connection to a chat server on login. The chat server registers this mapping in a presence service: "User A is connected to Server 3." This mapping is stored in Redis as a simple key-value pair (`user:{user_id}:server -> server-3`). When a chat server restarts or crashes, its users' connections are severed, and clients reconnect (to potentially a different server), updating the mapping.

**Message sending** follows a fixed path. The sender's client sends a message over its WebSocket. The chat server receives it, assigns a Snowflake ID, persists it to the message store, and then routes it to all recipients. For the sender's own acknowledgment, the server sends an ACK back over the WebSocket. For delivery to recipients, the server looks up each recipient's presence entry in Redis to find which server holds their connection, then publishes the message to a channel on Redis pub/sub (or calls the target server's internal API). The recipient's chat server receives the routed message and pushes it over the recipient's WebSocket.

**Message storage** uses a NoSQL database designed for high write throughput and time-ordered reads. The schema stores messages partitioned by channel (or conversation) ID, with the message ID (Snowflake, time-ordered) as the clustering key. This layout means "load the last 50 messages in this conversation" is a single partition scan  -  fast and efficient. HBase and Cassandra are the standard choices for this use case.

```python
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from typing import Optional
import redis
import json
import time

app = FastAPI()
r = redis.Redis(decode_responses=True)

# In-memory connection registry for this server instance
active_connections: dict[str, WebSocket] = {}

SERVER_ID = "server-1"  # Unique ID for this chat server instance

@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    await websocket.accept()

    # Register this user's connection on this server
    active_connections[user_id] = websocket
    r.set(f"user:{user_id}:server", SERVER_ID)
    r.set(f"presence:{user_id}", "online", ex=60)  # 60-second TTL, renewed by heartbeat

    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)

            if message["type"] == "message":
                await handle_message(user_id, message)
            elif message["type"] == "heartbeat":
                # Renew presence TTL
                r.set(f"presence:{user_id}", "online", ex=60)
                await websocket.send_text(json.dumps({"type": "heartbeat_ack"}))

    except WebSocketDisconnect:
        del active_connections[user_id]
        r.delete(f"user:{user_id}:server")
        r.delete(f"presence:{user_id}")

async def handle_message(sender_id: str, message: dict):
    channel_id = message["channel_id"]
    text = message["text"]
    message_id = generate_snowflake_id()

    # Persist to message store
    db.insert_message(
        message_id=message_id,
        channel_id=channel_id,
        sender_id=sender_id,
        text=text,
        created_at=time.time()
    )

    payload = json.dumps({
        "type": "message",
        "message_id": str(message_id),
        "channel_id": channel_id,
        "sender_id": sender_id,
        "text": text,
        "created_at": time.time()
    })

    # Send ACK to sender
    if sender_id in active_connections:
        await active_connections[sender_id].send_text(
            json.dumps({"type": "ack", "message_id": str(message_id)})
        )

    # Deliver to all recipients in this channel
    recipient_ids = db.get_channel_members(channel_id)
    for recipient_id in recipient_ids:
        if recipient_id == sender_id:
            continue

        recipient_server = r.get(f"user:{recipient_id}:server")
        if not recipient_server:
            # User is offline  -  message already persisted, will see it on reconnect
            continue

        if recipient_server == SERVER_ID:
            # Recipient is on this server  -  deliver directly
            if recipient_id in active_connections:
                await active_connections[recipient_id].send_text(payload)
        else:
            # Recipient is on a different server  -  publish via Redis pub/sub
            r.publish(f"server:{recipient_server}:messages", json.dumps({
                "recipient_id": recipient_id,
                "payload": payload
            }))

# REST endpoint: load message history (for initial load and reconnect)
@app.get("/channels/{channel_id}/messages")
async def get_message_history(
    channel_id: str,
    before_message_id: Optional[str] = None,
    limit: int = 50
):
    """Cursor-based pagination: load messages before a given message ID."""
    messages = db.get_messages(
        channel_id=channel_id,
        before_id=before_message_id,
        limit=limit
    )
    return {"messages": messages, "has_more": len(messages) == limit}

def generate_snowflake_id() -> int:
    """
    Snowflake-style ID: 41 bits timestamp (ms) + 10 bits machine ID + 12 bits sequence.
    Time-ordered within millisecond, unique across servers, sorts by creation time.
    """
    epoch_ms = int(time.time() * 1000) - 1609459200000  # custom epoch
    machine_id = int(SERVER_ID.split("-")[1])  # extract server number
    # Simplified: in production, include per-millisecond sequence counter
    return (epoch_ms << 22) | (machine_id << 12)
```

**Group chat fanout** is the hardest scaling challenge. For a group of 500 members, one message produces 499 individual WebSocket deliveries (all members except the sender). For large groups, this fanout must be handled by a worker queue rather than the synchronous message path, otherwise the sending server stalls while delivering to hundreds of recipients. The message is persisted first, then a fanout job is enqueued to handle delivery asynchronously. Members of very large groups who are not currently active (offline) need no immediate delivery  -  their messages wait in the persistent store.

**The three most important design decisions:** (1) WebSocket connection registry in Redis  -  allows any chat server to route messages to the correct server without broadcasting. (2) Snowflake IDs for messages  -  time-ordered without a separate timestamp index, unique without a central counter, sortable for pagination. (3) Separate REST path for message history  -  WebSocket handles real-time delivery; REST handles history loading. Mixing them over a single WebSocket connection complicates the client and server unnecessarily.

---

## Why It Matters in Practice

Chat is the template for any real-time collaborative system: multiplayer games, live collaborative documents, real-time analytics dashboards. The WebSocket connection registry problem, the fanout challenge, and the offline/online delivery split appear in all of them. Understanding how chat works at scale provides the mental model for any system where the server needs to push data to a specific connected client.

---

## Interview Angle

Common question forms:
- "Design a chat application like WhatsApp or Slack."
- "How do you route a message to a user connected to a different server?"
- "How does your system handle offline users?"

Answer frame:
Requirements: 1-1 and group chat, message history, online presence. WebSocket for bidirectional real-time communication. Connection registry in Redis: each user's connection server is stored as a key. Message routing: look up recipient's server, route via Redis pub/sub or internal API call. Message storage: Cassandra/HBase with (channel_id, snowflake_id)  -  high write throughput, efficient time-ordered reads. Offline users: messages are persisted; delivered on reconnect via REST history load. Group fanout: async worker for large groups. Presence: heartbeat + TTL in Redis.

---

## Related Notes

- [[redis-architecture|Redis Architecture]]
- [[redis-data-structures|Redis Data Structures]]
- [[message-queues|Message Queues]]
- [[horizontal-vs-vertical-scaling|Horizontal vs Vertical Scaling]]
- [[consistent-hashing|Consistent Hashing]]
