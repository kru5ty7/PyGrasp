---
title: Multi-Agent Systems
description: "Multi-agent systems in LangGraph use multiple specialized agents as subgraphs — each agent handles a domain; a supervisor or router delegates tasks; agents communicate through shared state or message passing; subgraphs compile independently and connect as nodes."
tags: [langgraph, multi-agent, subgraph, agent-collaboration, delegation, layer-4, ai]
status: draft
difficulty: advanced
layer: 4
domain: ai
created: 2026-05-17
---

# Multi-Agent Systems

> Multi-agent systems in LangGraph use multiple specialized agents as subgraphs — each agent handles a domain; a supervisor or router delegates tasks; agents communicate through shared state or message passing; subgraphs compile independently and connect as nodes.

---

## Quick Reference

**Core idea:**
- **Subgraph**: a compiled LangGraph graph used as a node in a parent graph
- **Supervisor**: an orchestrator node that routes tasks to specialized worker agents
- Subgraphs communicate with the parent via shared state keys — output state from subgraph merges into parent state
- `graph.add_node("agent_name", subgraph_app)` — add a compiled subgraph as a node
- Worker agents focus on one task; supervisor focuses on routing and aggregation

**Tricky points:**
- Subgraph state schema must be compatible with the parent state — shared keys must have the same type
- Each subgraph invocation is independent unless checkpointing is configured — subgraphs don't share memory by default
- Parallel execution of subgraphs: use `Send` API to fan out to multiple agents simultaneously
- Nested subgraphs add depth to the execution trace — debugging requires checking each level's state
- Supervisor pattern can produce infinite loops if the stopping condition is not robust — always test the "task complete" routing path

---

## What It Is

A single agent with all tools often produces mediocre results — it must reason about too many domains simultaneously. Multi-agent systems break the problem into specialized pieces: one agent searches the web, another writes code, another reviews outputs. A supervisor delegates and aggregates.

In LangGraph, specialization is implemented as subgraphs — compiled graphs that are plugged in as nodes in a parent graph. The supervisor node decides which subgraph to call next.

---

## How It Actually Works

Subgraph as a node:
```python
from langgraph.graph import StateGraph, MessagesState, START, END

# Define a specialized research subgraph
research_graph = StateGraph(MessagesState)
research_graph.add_node("search", search_node)
research_graph.add_node("summarize", summarize_node)
research_graph.add_edge(START, "search")
research_graph.add_edge("search", "summarize")
research_graph.add_edge("summarize", END)
research_agent = research_graph.compile()

# Define a specialized writing subgraph
writing_graph = StateGraph(MessagesState)
writing_graph.add_node("draft", draft_node)
writing_graph.add_node("revise", revise_node)
writing_graph.add_edge(START, "draft")
writing_graph.add_conditional_edges("draft", needs_revision_check)
writing_graph.add_edge("revise", END)
writing_agent = writing_graph.compile()

# Parent graph using subgraphs as nodes
class ParentState(MessagesState):
    current_agent: str

parent_graph = StateGraph(ParentState)
parent_graph.add_node("supervisor", supervisor_node)
parent_graph.add_node("researcher", research_agent)  # subgraph as node
parent_graph.add_node("writer", writing_agent)        # subgraph as node

parent_graph.add_edge(START, "supervisor")
parent_graph.add_conditional_edges(
    "supervisor",
    route_to_agent,
    {"research": "researcher", "write": "writer", "done": END}
)
parent_graph.add_edge("researcher", "supervisor")  # return to supervisor after each agent
parent_graph.add_edge("writer", "supervisor")

app = parent_graph.compile()
```

Fan-out with `Send` (parallel execution):
```python
from langgraph.types import Send

def dispatch_to_agents(state: dict) -> list[Send]:
    """Fan out to multiple agents in parallel."""
    tasks = state["tasks"]
    return [
        Send("research_agent", {"messages": [HumanMessage(content=task)]})
        for task in tasks
    ]

parent_graph.add_conditional_edges(
    "task_planner",
    dispatch_to_agents,  # returns list of Send objects for parallel execution
)
```

---

## How It Connects

The supervisor pattern is the most common multi-agent architecture — a supervisor routes between worker agents.
[[supervisor-pattern|Supervisor Pattern]]

Human-in-the-loop adds approval gates to multi-agent workflows.
[[human-in-the-loop|Human-in-the-Loop]]

---

## Common Misconceptions

Misconception 1: "More agents = better performance."
Reality: More agents add orchestration overhead, latency (each delegation is an LLM call), and debugging complexity. Start with a single agent and add specialization only when there's a clear bottleneck or quality issue.

Misconception 2: "Subgraph state is isolated from the parent."
Reality: When a subgraph is used as a node, its output state merges into the parent state via the same reducer rules. Subgraph keys that exist in the parent state are updated; extra keys are discarded.

---

## Why It Matters in Practice

When to use multi-agent systems:
- Task requires fundamentally different skills (code generation + web search + data analysis)
- Single agent context window fills up quickly (each agent only sees its own context)
- Parallelism is valuable (fan out to multiple research agents simultaneously)
- Different reliability requirements (code execution agent needs sandboxing; others don't)

Rule of thumb: if you need more than 5-6 tools in one agent, consider splitting into specialized subagents.

---

## Interview Angle

Common question forms:
- "How do you implement multi-agent collaboration in LangGraph?"
- "What is the supervisor pattern in LangGraph?"

Answer frame: Multi-agent = multiple compiled LangGraph graphs used as nodes in a parent graph. Supervisor node routes to specialized worker agents. Subgraph output merges into parent state. `Send` API for parallel fan-out. Use when: multiple domains, context overload, parallelism needed. Tradeoff: orchestration overhead vs. specialization quality.

---

## Related Notes

- [[supervisor-pattern|Supervisor Pattern]]
- [[langgraph-core|LangGraph Core]]
- [[conditional-edges|Conditional Edges]]
- [[human-in-the-loop|Human-in-the-Loop]]
