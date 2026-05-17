---
title: 01 - Graph Theory Basics
description: "Graph theory vocabulary needed for LangGraph — nodes (processing steps), edges (transitions), directed graphs, cycles, DAGs; LangGraph allows cycles (agents loop until done) unlike DAGs; state flows along edges and is updated by nodes."
tags: [graph-theory, nodes, edges, directed-graph, DAG, cycles, layer-4, ai]
status: draft
difficulty: beginner
layer: 4
domain: ai
created: 2026-05-17
---

# Graph Theory Basics

> Graph theory vocabulary needed for LangGraph — nodes (processing steps), edges (transitions), directed graphs, cycles, DAGs; LangGraph allows cycles (agents loop until done) unlike DAGs; state flows along edges and is updated by nodes.

---

## Quick Reference

**Core idea:**
- **Node**: a processing unit — in LangGraph, a Python function that reads and updates state
- **Edge**: a directed connection between two nodes — determines where execution goes next
- **Directed graph**: edges have direction (A → B ≠ B → A)
- **DAG** (Directed Acyclic Graph): no cycles — execution flows in one direction to a terminal node
- **Cycle**: a path that returns to a previously visited node — allows agents to loop

**Tricky points:**
- LangGraph allows cycles — this is intentional; agents loop (reason → act → observe → reason) until a stopping condition
- LCEL chains are DAGs — they flow top to bottom, no loops; LangGraph graphs can cycle
- `START` and `END` are special LangGraph nodes — every graph begins at `START` and terminates at `END`
- Conditional edges create branching — the edge target is determined by a function that inspects state
- A node that adds an edge to itself creates an infinite loop — always have a stopping condition

---

## What It Is

A graph is a set of nodes connected by edges. For LangGraph, the key distinction from LCEL chains is that graphs support cycles — a node can route back to an earlier node based on the current state. This is what makes agent loops possible: the model reasons, calls a tool, observes the result, and decides whether to call another tool or terminate.

LCEL is a DAG: input flows in, output flows out, no revisiting. LangGraph is a general directed graph: execution can revisit nodes until a terminal condition is reached.

---

## How It Actually Works

Graph vocabulary in LangGraph context:
```python
from langgraph.graph import StateGraph, START, END
from typing import TypedDict

class State(TypedDict):
    messages: list
    step_count: int

graph = StateGraph(State)

# Nodes — processing functions
def node_a(state: State) -> dict:
    return {"step_count": state["step_count"] + 1}

def node_b(state: State) -> dict:
    return {"step_count": state["step_count"] + 1}

# Routing function — determines next node based on state
def route(state: State) -> str:
    if state["step_count"] >= 3:
        return "end"
    return "node_a"  # cycle back

graph.add_node("node_a", node_a)
graph.add_node("node_b", node_b)

graph.add_edge(START, "node_a")    # unconditional edge from START
graph.add_edge("node_a", "node_b") # unconditional edge A → B
graph.add_conditional_edges(       # conditional edge with routing function
    "node_b",
    route,
    {"node_a": "node_a", "end": END}
)

app = graph.compile()
```

Visual representation of this graph:
```
START → node_a → node_b ──(step_count < 3)──→ node_a  (cycle)
                         └─(step_count >= 3)─→ END
```

---

## How It Connects

LangGraph's `StateGraph` is built on directed graph principles — nodes update state, edges route execution.
[[state-graph|State Graph]]

Conditional edges are the mechanism for graph branching and cycles.
[[conditional-edges|Conditional Edges]]

---

## Common Misconceptions

Misconception 1: "All computational graphs are DAGs."
Reality: DAGs are a common special case (NumPy computation graphs, LCEL chains, neural network forward passes). LangGraph deliberately allows cycles because agent loops require revisiting the reasoning node.

Misconception 2: "Cycles mean infinite loops."
Reality: Cycles only cause infinite loops if there's no stopping condition. LangGraph agents always have a conditional edge that routes to `END` when the task is complete.

---

## Why It Matters in Practice

Understanding graph structure helps reason about agent behavior:
- The number of cycles = number of tool calls an agent makes
- A stuck agent is usually missing a `→ END` condition
- Checkpointing saves state at each node — you can replay or resume from any node

---

## Interview Angle

Common question forms:
- "Why does LangGraph use a graph instead of a chain?"
- "What is the difference between a DAG and a general directed graph?"

Answer frame: Graph = nodes (processing) + edges (transitions). DAG = no cycles; LCEL chains are DAGs. LangGraph = general directed graph with cycles. Cycles enable agent loops: reason → act → observe → reason until done. `START` and `END` bound execution. Conditional edges route based on state inspection.

---

## Related Notes

- [[state-graph|State Graph]]
- [[nodes-and-edges|Nodes and Edges]]
- [[conditional-edges|Conditional Edges]]
- [[langgraph-core|LangGraph Core]]
