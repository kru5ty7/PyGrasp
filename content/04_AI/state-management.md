---
title: State Management in LangGraph
description: "LangGraph state is a typed dict passed between nodes — each node returns a partial update; reducers (like `operator.add`) control how updates merge into the current state; `Annotated[list, operator.add]` appends rather than replaces."
tags: [langgraph, state, TypedDict, reducers, Annotated, operator.add, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# State Management in LangGraph

> LangGraph state is a typed dict passed between nodes — each node returns a partial update; reducers (like `operator.add`) control how updates merge into the current state; `Annotated[list, operator.add]` appends rather than replaces.

---

## Quick Reference

**Core idea:**
- State = `TypedDict` schema — defines what data flows through the graph
- Each node receives the full state and returns a `dict` with only the keys it updates
- **Default merge**: returned keys overwrite current state values
- **Reducer**: `Annotated[list, operator.add]` — instead of replacing, the returned list is appended to the existing list
- `add_messages` reducer from LangGraph — special reducer for chat message lists that handles deduplication

**Tricky points:**
- Returning `{"messages": new_messages}` with default merge **replaces** the entire messages list — use `add_messages` reducer to append
- State is immutable within a node — nodes receive state as input and return updates; they don't mutate in place
- Reducers must be pure functions: `(current_value, update_value) -> new_value`
- Private state fields (prefixed `_`) are not exposed to subgraphs — use for node-local scratch data
- `MessagesState` is a built-in LangGraph state class with `add_messages` already configured

---

## What It Is

State is the shared memory that flows through a LangGraph graph. Every node reads from it and writes partial updates back. The graph merges these updates using reducers — functions that define how new values combine with existing ones.

The default merge is replacement: if a node returns `{"count": 5}`, the state's `count` becomes `5`. But for message lists, replacement would destroy conversation history — so the `add_messages` reducer appends new messages instead.

---

## How It Actually Works

Basic state with reducers:
```python
import operator
from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langchain_core.messages import HumanMessage, AIMessage

# Custom state with mixed merge behaviors
class AgentState(TypedDict):
    # add_messages reducer — appends new messages, handles deduplication
    messages: Annotated[list, add_messages]
    # Default replacement — last writer wins
    current_tool: str
    # operator.add reducer — accumulates a list
    tool_calls_made: Annotated[list, operator.add]
    # Default replacement — simple counter
    step_count: int

def node_a(state: AgentState) -> dict:
    # Return only the keys this node updates
    return {
        "messages": [AIMessage(content="Thinking...")],  # appended via add_messages
        "step_count": state["step_count"] + 1,          # replaced
        "tool_calls_made": ["search"],                  # appended via operator.add
    }
```

Using `MessagesState` (built-in shortcut):
```python
from langgraph.graph import MessagesState

# MessagesState is equivalent to:
# class MessagesState(TypedDict):
#     messages: Annotated[list, add_messages]

graph = StateGraph(MessagesState)
```

Custom reducer function:
```python
def keep_last_n(current: list, update: list, n: int = 10) -> list:
    """Keep only the last N items."""
    combined = current + update
    return combined[-n:]

class WindowedState(TypedDict):
    # Custom reducer via partial
    from functools import partial
    messages: Annotated[list, partial(keep_last_n, n=10)]
```

Inspecting state during execution:
```python
app = graph.compile()

# Stream state updates as the graph runs
for event in app.stream({"messages": [HumanMessage(content="Hello")], "step_count": 0, "tool_calls_made": []}):
    for node_name, state_update in event.items():
        print(f"Node '{node_name}' updated: {state_update}")

# Get final state
final_state = app.invoke({"messages": [HumanMessage(content="Hello")], "step_count": 0, "tool_calls_made": []})
```

---

## How It Connects

State flows through nodes and edges — graph structure determines the order of state updates.
[[state-graph|State Graph]]

Checkpointing persists state between graph invocations — enables resuming interrupted runs.
[[checkpointing|Checkpointing]]

---

## Common Misconceptions

Misconception 1: "Nodes mutate state directly."
Reality: Nodes receive state as a read-only dict and return a dict of updates. LangGraph applies the updates using reducers — the node never mutates the state object.

Misconception 2: "You must return all state keys from every node."
Reality: Nodes return only the keys they update — omitted keys are unchanged. This is partial update semantics.

---

## Why It Matters in Practice

The `add_messages` / replacement distinction is critical:
```python
# WRONG — replaces entire message history with just the new message
def bad_node(state):
    response = llm.invoke(state["messages"])
    return {"messages": [response]}  # overwrites history!

# RIGHT — uses add_messages reducer; new message is appended
def good_node(state):
    response = llm.invoke(state["messages"])
    return {"messages": [response]}  # appended because of Annotated[list, add_messages]
```

Both look identical — the difference is in how `messages` was declared in the state TypedDict.

---

## Interview Angle

Common question forms:
- "How does state work in LangGraph?"
- "What is a reducer in LangGraph?"

Answer frame: State = TypedDict schema; flows through every node. Nodes return partial updates (only modified keys). Reducers define merge behavior: default = replacement; `add_messages` = append with deduplication; `operator.add` = list concatenation. `MessagesState` is the built-in state for chat agents — already has `add_messages` configured.

---

## Related Notes

- [[state-graph|State Graph]]
- [[nodes-and-edges|Nodes and Edges]]
- [[checkpointing|Checkpointing]]
- [[langgraph-core|LangGraph Core]]
