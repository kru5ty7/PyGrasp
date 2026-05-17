---
title: Conditional Edges
description: "Conditional edges in LangGraph route execution to different nodes based on state — a routing function inspects the current state and returns the name of the next node; they implement branching and agent loop termination."
tags: [langgraph, conditional-edges, routing, branching, agent-loop, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Conditional Edges

> Conditional edges in LangGraph route execution to different nodes based on state — a routing function inspects the current state and returns the name of the next node; they implement branching and agent loop termination.

---

## Quick Reference

**Core idea:**
- `graph.add_conditional_edges(source_node, routing_fn, path_map)` — adds an edge whose target is determined at runtime
- Routing function: `(state) -> str` — inspects state, returns a key from `path_map`
- `path_map`: `{"key": "node_name"}` — maps routing function output to actual node names
- Routing to `END` terminates the graph
- LangGraph's `tools_condition` — built-in routing function that routes to tools or `END` based on `tool_calls` in last message

**Tricky points:**
- Routing function must return a value that exists as a key in `path_map` — missing keys raise a `KeyError` at runtime
- `path_map` is optional when routing function returns exact node names or `END` directly
- Multiple conditional edges from the same node are not supported — one routing function handles all branches
- `tools_condition` checks `state["messages"][-1].tool_calls` — works with any LLM that produces tool call messages
- `Literal` type hints on the routing function help with static analysis and documentation

---

## What It Is

Conditional edges are the branching mechanism in LangGraph. An unconditional edge always goes to the same next node. A conditional edge inspects the current state at runtime and decides which node to visit next.

This is what enables agent loops: after the LLM generates a response, a routing function checks whether the response contains tool calls — if yes, route to the tool execution node; if no, route to `END`.

---

## How It Actually Works

Basic conditional routing:
```python
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import MessagesState
from typing import Literal

def route_after_llm(state: MessagesState) -> Literal["tools", "end"]:
    """Route to tools if the LLM made tool calls, otherwise end."""
    last_message = state["messages"][-1]
    if last_message.tool_calls:
        return "tools"
    return "end"

graph = StateGraph(MessagesState)
graph.add_node("llm", llm_node)
graph.add_node("tools", tool_node)

graph.add_edge(START, "llm")
graph.add_conditional_edges(
    "llm",           # source node
    route_after_llm, # routing function
    {
        "tools": "tools",  # if routing fn returns "tools" → go to "tools" node
        "end": END,        # if routing fn returns "end" → terminate
    }
)
graph.add_edge("tools", "llm")  # after tools, always go back to LLM
```

Using the built-in `tools_condition`:
```python
from langgraph.prebuilt import tools_condition, ToolNode

tools = [search_tool, calculator_tool]
tool_node = ToolNode(tools)

llm_with_tools = llm.bind_tools(tools)

def llm_node(state: MessagesState) -> dict:
    return {"messages": [llm_with_tools.invoke(state["messages"])]}

graph = StateGraph(MessagesState)
graph.add_node("llm", llm_node)
graph.add_node("tools", tool_node)

graph.add_edge(START, "llm")
graph.add_conditional_edges("llm", tools_condition)  # path_map inferred from tools_condition
graph.add_edge("tools", "llm")
```

Multi-way branching:
```python
from typing import Literal

def classify_intent(state: dict) -> Literal["search", "calculate", "respond"]:
    intent = classify(state["messages"][-1].content)
    return intent  # "search", "calculate", or "respond"

graph.add_conditional_edges(
    "router",
    classify_intent,
    {
        "search": "search_node",
        "calculate": "calc_node",
        "respond": END,
    }
)
```

---

## How It Connects

Conditional edges are how agent loops terminate — they route between the reasoning node, tool node, and `END`.
[[nodes-and-edges|Nodes and Edges]]

In multi-agent systems, conditional edges route to different subgraphs or agents based on task type.
[[multi-agent-systems|Multi-Agent Systems]]

---

## Common Misconceptions

Misconception 1: "Conditional edges require a `path_map`."
Reality: `path_map` is optional. If the routing function returns exact node names (or `END` directly), LangGraph uses them directly without a mapping.

Misconception 2: "You can have multiple conditional edges from one node."
Reality: Only one `add_conditional_edges` call per source node. To handle multiple routing outcomes, encode all cases in one routing function.

---

## Why It Matters in Practice

The ReAct agent loop is entirely driven by conditional edges:
```
START → llm → [has tool_calls?] → yes: tools → llm (loop)
                                 → no:  END
```

Without the conditional edge, the agent either always calls tools (infinite loop) or never calls tools (useless agent). The routing function is the intelligence that decides when the agent is done.

---

## Interview Angle

Common question forms:
- "How do you implement an agent loop in LangGraph?"
- "What are conditional edges?"

Answer frame: Conditional edges route execution based on state inspection. `add_conditional_edges(source, routing_fn, path_map)` — routing function returns a string key; path_map maps keys to node names or `END`. Agent loop: LLM node → `tools_condition` → tools node → back to LLM; terminates when no tool calls. `tools_condition` is the built-in routing function for tool-calling agents.

---

## Related Notes

- [[nodes-and-edges|Nodes and Edges]]
- [[state-graph|State Graph]]
- [[langgraph-core|LangGraph Core]]
- [[multi-agent-systems|Multi-Agent Systems]]
