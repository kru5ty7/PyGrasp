---
title: 07 - Checkpointing
description: "LangGraph checkpointing persists graph state after each node — a checkpointer (SQLite, Postgres, in-memory) saves state snapshots keyed by `thread_id`; enables resuming interrupted runs, inspecting intermediate state, and conversation memory across invocations."
tags: [langgraph, checkpointing, persistence, thread-id, MemorySaver, SqliteSaver, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Checkpointing

> LangGraph checkpointing persists graph state after each node — a checkpointer (SQLite, Postgres, in-memory) saves state snapshots keyed by `thread_id`; enables resuming interrupted runs, inspecting intermediate state, and conversation memory across invocations.

---

## Quick Reference

**Core idea:**
- Checkpointer = a storage backend that saves state snapshots after each node execution
- `thread_id` in `config={"configurable": {"thread_id": "..."}}` — scopes checkpoints to a conversation
- `MemorySaver` — in-memory checkpointer for development; lost on restart
- `SqliteSaver` — SQLite-backed persistent checkpointer
- Same `thread_id` across invocations = same conversation; the graph resumes from the last checkpoint

**Tricky points:**
- Without a checkpointer, every `app.invoke()` call starts fresh — no memory of prior turns
- `thread_id` must be a string; use UUIDs for production to avoid collisions between users
- Checkpointing adds overhead — each node execution triggers a write; fine for agents, overkill for simple chains
- `app.get_state(config)` — retrieve the current state for a thread without invoking the graph
- `app.update_state(config, values)` — manually update the saved state; used for human-in-the-loop corrections

---

## What It Is

By default, LangGraph graphs are stateless across invocations — each `.invoke()` starts with fresh state. Checkpointing adds persistence: after each node runs, the updated state is saved to a storage backend. When you invoke the graph again with the same `thread_id`, it loads the last saved state and continues from there.

This is what gives LangGraph agents conversation memory — each user message appended to the existing message history from prior turns.

---

## How It Actually Works

In-memory checkpointer (development):
```python
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import StateGraph, MessagesState, START, END
from langchain_core.messages import HumanMessage

graph = StateGraph(MessagesState)
# ... add nodes and edges ...

# Compile with checkpointer
checkpointer = MemorySaver()
app = graph.compile(checkpointer=checkpointer)

# Thread config — same thread_id = same conversation
config = {"configurable": {"thread_id": "conversation-123"}}

# First turn
result1 = app.invoke(
    {"messages": [HumanMessage(content="My name is Alice.")]},
    config=config,
)

# Second turn — graph loads prior state automatically
result2 = app.invoke(
    {"messages": [HumanMessage(content="What is my name?")]},
    config=config,
)
# Agent has access to both messages — responds "Alice"
```

SQLite checkpointer (persistent):
```python
from langgraph.checkpoint.sqlite import SqliteSaver

# File-backed persistence — survives restarts
with SqliteSaver.from_conn_string("checkpoints.db") as checkpointer:
    app = graph.compile(checkpointer=checkpointer)
    
    result = app.invoke(
        {"messages": [HumanMessage(content="Hello")]},
        config={"configurable": {"thread_id": "user-456"}},
    )
```

Inspecting and updating state:
```python
config = {"configurable": {"thread_id": "user-456"}}

# Get current state for a thread
state = app.get_state(config)
print(state.values)           # current state dict
print(state.next)             # which node runs next (if graph is paused)

# Get full history of state snapshots
for snapshot in app.get_state_history(config):
    print(snapshot.values, snapshot.created_at)

# Manually update state (e.g., to correct a mistake)
app.update_state(config, {"messages": [HumanMessage(content="Corrected message")]})
```

---

## How It Connects

Human-in-the-loop workflows rely on checkpointing to pause execution and resume after human input.
[[human-in-the-loop|Human-in-the-Loop]]

State management defines what is persisted — the checkpointer saves whatever the state TypedDict contains.
[[state-management|State Management]]

---

## Common Misconceptions

Misconception 1: "Checkpointing is only for crash recovery."
Reality: The primary use case for checkpointing in LangGraph is conversation memory — enabling multi-turn interactions where the agent remembers prior messages.

Misconception 2: "`MemorySaver` is sufficient for production."
Reality: `MemorySaver` stores state in a Python dict — it's lost when the process restarts. For production, use `SqliteSaver`, `PostgresSaver`, or a custom backend.

---

## Why It Matters in Practice

```python
# Without checkpointing: each call is independent
result = app.invoke({"messages": [HumanMessage("What did I say before?")]})
# Agent: "I don't have context about previous messages."

# With checkpointing + same thread_id: agent has full history
config = {"configurable": {"thread_id": "user-123"}}
result = app.invoke({"messages": [HumanMessage("What did I say before?")]}, config=config)
# Agent: "You previously said X."
```

For multi-user applications: generate a UUID at session start, store it in the user's session, pass it as `thread_id` on every request.

---

## Interview Angle

Common question forms:
- "How does LangGraph maintain conversation history?"
- "What is a checkpointer in LangGraph?"

Answer frame: Checkpointer saves state after each node. `thread_id` in config scopes the checkpoint to a conversation. Same `thread_id` + new invocation = load prior state and continue. `MemorySaver` (dev, in-memory), `SqliteSaver` (persistent file). Enables conversation memory, crash recovery, and human-in-the-loop workflows. `app.get_state()` and `app.update_state()` for inspection and correction.

---

## Related Notes

- [[state-management|State Management]]
- [[human-in-the-loop|Human-in-the-Loop]]
- [[langgraph-core|LangGraph Core]]
- [[state-graph|State Graph]]
