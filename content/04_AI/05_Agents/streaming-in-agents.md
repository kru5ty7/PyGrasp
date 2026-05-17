---
title: 06 - Streaming in Agents
description: "Streaming in LangGraph agents delivers tokens and events progressively — `.stream()` yields state updates per node; `.astream_events()` yields fine-grained events including individual tokens; streaming reduces perceived latency for end users waiting for long agent responses."
tags: [langgraph, streaming, astream-events, token-streaming, agent-ux, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Streaming in Agents

> Streaming in LangGraph agents delivers tokens and events progressively — `.stream()` yields state updates per node; `.astream_events()` yields fine-grained events including individual tokens; streaming reduces perceived latency for end users waiting for long agent responses.

---

## Quick Reference

**Core idea:**
- `app.stream(input)` — yields one dict per node execution: `{"node_name": state_update}`
- `await app.astream_events(input)` — yields fine-grained events: token chunks, tool start/end, node start/end
- Event types: `"on_chat_model_stream"` (individual tokens), `"on_tool_start"`, `"on_tool_end"`, `"on_chain_end"`
- `stream_mode="values"` — yield full state after each node (default: `"updates"` yields only changed keys)
- For FastAPI SSE: use `EventSourceResponse` with an async generator that calls `astream_events`

**Tricky points:**
- `.stream()` yields after each *node* completes — not individual tokens; tool calls block until the tool finishes
- `astream_events` yields per-token events from the LLM but requires filtering by event name — event volume is high
- Streaming tool calls: the LLM streams the tool call JSON as tokens, but the tool itself doesn't execute until the full call is assembled
- `stream_mode="messages"` — yields `(message_chunk, metadata)` tuples; simplest for chat applications
- In async FastAPI, the streaming generator must use `async for` with `app.astream_events()`

---

## What It Is

Without streaming, users stare at a loading indicator while the agent reasons, calls tools, and formulates a response — this can take 10-30 seconds for complex tasks. Streaming delivers partial results as they become available, improving perceived responsiveness.

LangGraph supports two levels of streaming: node-level (state updates after each node) and token-level (individual tokens as the LLM generates them). Most UIs need token-level streaming for the final answer.

---

## How It Actually Works

Node-level streaming:
```python
from langgraph.graph import StateGraph, MessagesState
from langchain_core.messages import HumanMessage

app = graph.compile()

for event in app.stream(
    {"messages": [HumanMessage(content="What is the weather in Paris?")]},
    stream_mode="updates",  # yield only changed state keys per node
):
    for node_name, update in event.items():
        print(f"Node '{node_name}' completed:")
        if "messages" in update:
            print(f"  {update['messages'][-1].content[:100]}")
```

Token-level streaming via `astream_events`:
```python
import asyncio

async def stream_agent_response(user_input: str):
    """Yield individual tokens as the agent generates them."""
    async for event in app.astream_events(
        {"messages": [HumanMessage(content=user_input)]},
        version="v2",
    ):
        kind = event["event"]
        
        # Individual LLM output tokens
        if kind == "on_chat_model_stream":
            chunk = event["data"]["chunk"]
            if chunk.content:
                yield chunk.content
        
        # Tool execution notifications
        elif kind == "on_tool_start":
            tool_name = event["name"]
            yield f"\n[Calling tool: {tool_name}]\n"
        
        elif kind == "on_tool_end":
            yield f"[Tool complete]\n"

# Usage
async def main():
    async for token in stream_agent_response("What is the weather in Paris?"):
        print(token, end="", flush=True)
```

FastAPI Server-Sent Events endpoint:
```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from langchain_core.messages import HumanMessage

app_api = FastAPI()

async def generate_stream(user_input: str):
    async for event in langgraph_app.astream_events(
        {"messages": [HumanMessage(content=user_input)]},
        version="v2",
    ):
        if event["event"] == "on_chat_model_stream":
            chunk = event["data"]["chunk"]
            if chunk.content:
                yield f"data: {chunk.content}\n\n"
    yield "data: [DONE]\n\n"

@app_api.get("/stream")
async def stream_endpoint(query: str):
    return StreamingResponse(
        generate_stream(query),
        media_type="text/event-stream",
    )
```

Simple chat message streaming (`stream_mode="messages"`):
```python
for message_chunk, metadata in app.stream(
    {"messages": [HumanMessage(content="Tell me a joke")]},
    stream_mode="messages",
):
    if message_chunk.content:
        print(message_chunk.content, end="", flush=True)
```

---

## How It Connects

Streaming is delivered over FastAPI as Server-Sent Events — the agent backend connects to the web layer here.
[[fastapi-websockets|FastAPI WebSockets]]

LangGraph agent architecture determines what events are available to stream.
[[langgraph-core|LangGraph Core]]

---

## Common Misconceptions

Misconception 1: "`.stream()` gives token-by-token output."
Reality: `.stream()` yields state updates after each complete node — if the LLM node takes 5 seconds, you wait 5 seconds for its event. Use `.astream_events()` for token-level streaming.

Misconception 2: "Streaming is only about speed."
Reality: Streaming also provides transparency — seeing tool calls happen in real-time tells users what the agent is doing, which builds trust and helps debug incorrect behavior.

---

## Why It Matters in Practice

For production chat interfaces, the streaming hierarchy is:
1. Stream final LLM response tokens (`on_chat_model_stream`) — highest priority for UX
2. Stream tool start/end events — shows progress for long-running tools
3. Stream intermediate reasoning (if visible) — useful for debugging, optional for users

Filter events by node name to avoid streaming internal reasoning nodes:
```python
# Only stream events from the final response node
if event["event"] == "on_chat_model_stream" and event["metadata"].get("langgraph_node") == "final_response":
    yield event["data"]["chunk"].content
```

---

## Interview Angle

Common question forms:
- "How do you stream responses from a LangGraph agent?"
- "What is the difference between `.stream()` and `.astream_events()`?"

Answer frame: Two levels — node-level (`.stream()`, yields after each node completes) and token-level (`.astream_events()`, yields individual tokens). For chat UIs, filter `on_chat_model_stream` events for tokens, `on_tool_start`/`on_tool_end` for progress. Expose via FastAPI `StreamingResponse` with `text/event-stream` content type.

---

## Related Notes

- [[langgraph-core|LangGraph Core]]
- [[agents|Agents]]
- [[fastapi-websockets|FastAPI WebSockets]]
- [[react-pattern|ReAct Pattern]]
