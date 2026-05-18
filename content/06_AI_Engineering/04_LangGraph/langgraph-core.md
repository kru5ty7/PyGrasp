---
title: 02 - LangGraph Core
description: LangGraph is a library for building stateful, multi-step LLM workflows as explicit graphs  -  it extends LangChain's linear chain model with cycles, branching, and persistent state, enabling agentic loops where the LLM decides what to do next.
tags: [langgraph, state-graph, agents, cycles, nodes, edges, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# LangGraph Core

> LangGraph is a library for building stateful, multi-step LLM workflows as explicit graphs  -  it extends LangChain's linear chain model with cycles, branching, and persistent state, enabling agentic loops where the LLM decides what to do next.

---

## Quick Reference

**Core idea:**
- LangGraph models a workflow as a **directed graph** with nodes (functions that process state) and edges (transitions between nodes, including conditional branching)
- The graph operates on a shared **state object**  -  each node receives the current state, returns updates to it, and the graph manages merging those updates
- `StateGraph` is the primary class: add nodes with `.add_node()`, add edges with `.add_edge()`, add conditional edges with `.add_conditional_edges()`
- Compile the graph with `.compile()` to get a Runnable  -  it then works like any LCEL chain (`.invoke()`, `.astream()`, etc.)
- **Cycles** are what distinguish LangGraph from LCEL  -  an LLM can call tools, observe results, and decide to call more tools, looping until a stopping condition is met

**Tricky points:**
- **State merging**: each node returns a dict of state updates, not the full state  -  LangGraph merges the updates into the existing state using annotated reducers (e.g., `Annotated[list, operator.add]` appends to a list)
- `END` is a special node name  -  any edge to `END` terminates graph execution and returns the final state
- The graph **must have a path from every node to `END`** (possibly via conditional edges)  -  unreachable states cause the graph to run indefinitely
- Streaming from a compiled graph yields **state updates after each node execution**, not just final output  -  use `astream_events()` for token-level streaming
- **Checkpointing** (via a `MemorySaver` or database checkpointer) persists graph state between invocations, enabling multi-turn conversations that remember prior steps

---

## What It Is

Think of LangGraph as a flowchart execution engine where the flowchart's decision boxes can be answered by an LLM. A traditional software flowchart has fixed branches  -  `if condition A, go to step 3; else go to step 5`. A LangGraph workflow can have branches where the condition is "ask the LLM whether we need more information or whether we have enough to answer." The LLM's response to that question determines which edge the graph traverses. Because the graph can loop back  -  from "need more information" back to the tool-calling step  -  it can execute an unbounded number of steps guided by LLM decisions, rather than a fixed linear sequence.

LangChain's LCEL handles linear workflows well  -  prompt -> LLM -> parse -> done. But real agentic behavior requires cycles: call a tool, observe the result, decide if another tool call is needed, call the next tool, decide again, and eventually produce an answer. LCEL's sequential `|` composition cannot express cycles. LangGraph introduces an explicit graph structure where edges can point backward to earlier nodes, creating loops. The graph runs until a node transitions to the special `END` node, which terminates execution.

The central design decision in LangGraph is the **shared state object**. Rather than passing data from node to node through return values (as in LCEL), LangGraph maintains a state dict that every node reads from and writes to. Each node function accepts the full current state and returns a partial update  -  only the keys it wants to change. LangGraph merges these updates into the state before passing it to the next node. This design makes the shared state explicit, inspectable, and persistable  -  you can checkpoint the state at any node, resume from any checkpoint, and inspect the full state at any point during graph execution.

---

## How It Actually Works

A `StateGraph` is defined by first specifying a **state schema**  -  a TypedDict subclass or Pydantic model that defines the keys in the state and their types. Annotations on state fields specify **reducers**  -  functions that determine how updates to a field are merged with the existing value. The most common reducer is `operator.add` (append to a list), declared as `Annotated[list[BaseMessage], operator.add]`. Without an annotation, the default reducer is assignment  -  the new value overwrites the old.

Nodes are added with `graph.add_node("node_name", function)`. The function signature is `def node(state: StateType) -> dict`, where the dict contains only the keys the node wants to update. Adding edges: `graph.add_edge("a", "b")` creates an unconditional transition from node `a` to node `b`. Setting the entry point: `graph.set_entry_point("first_node")`. Conditional edges: `graph.add_conditional_edges("a", routing_function, {"option1": "node_x", "option2": END})`  -  after node `a` runs, `routing_function(state)` is called and its return value is used as a key to look up the next node.

Compilation calls `.compile()`, optionally with a `checkpointer`. The compiled graph is a `CompiledStateGraph`, which is a LangChain Runnable. Invoking it: `result = graph.invoke({"messages": [HumanMessage("Hello")]})` passes the initial state and returns the final state after execution reaches `END`. Async invocation uses `await graph.ainvoke(...)`. Streaming state updates after each node: `async for event in graph.astream(initial_state): ...` yields dicts like `{"node_name": {"state_key": updated_value}}` after each node completes.

The **prebuilt agents** in `langgraph.prebuilt`  -  `create_react_agent`  -  provide a complete LangGraph graph for the ReAct (Reasoning + Acting) pattern: the LLM either calls tools or produces a final answer; tool calls are dispatched, results added to messages, and the loop continues until the LLM produces a final answer without tool calls. `create_react_agent(llm, tools)` returns a compiled graph that implements this loop, accepting `{"messages": [...]}` as input.

---

## How It Connects

LangGraph is built on LangChain's Runnable abstraction. A compiled `StateGraph` is a Runnable  -  it implements the same `.invoke()`, `.astream()`, and `.ainvoke()` interface as any LCEL chain. Every node in the graph can itself be a LangChain Runnable (a prompt | llm | parser chain). Understanding LangChain's Runnable interface and LCEL composition is the foundation for understanding what happens inside each LangGraph node.
[[langchain-basics|LangChain Basics]]

LangGraph's stateful graph execution model is the architecture for building agents. An agent in LangGraph is a graph where the LLM decides at each step whether to call a tool or produce a final answer  -  the cycle is the agent loop. The nodes are: call LLM, call tools, and the routing function determines which edge to traverse.
[[agents|Agents]]

LangGraph's state graph, nodes, and edges are the concrete implementation of the state machine concept used for agent orchestration. Understanding the graph structure  -  how state flows, how reducers merge updates, how conditional edges route  -  is essential for building reliable multi-step LLM workflows.
[[state-graph|State Graph]]

LangGraph's async execution uses `asyncio.gather()` internally for parallel node execution where possible. In agentic loops that make multiple tool calls, tool execution can be parallelized  -  LangGraph routes all pending tool calls to their respective tool functions concurrently, awaits all results, and adds them to the messages state.
[[event-loop|The Event Loop]]

---

## Common Misconceptions

Misconception 1: "LangGraph is a more complex version of LangChain for the same use cases."
Reality: LangGraph targets a different class of problems than LCEL. LCEL chains are for deterministic, linear pipelines  -  the same sequence of steps every time. LangGraph is for workflows where the number of steps, the choice of which steps to take, and when to stop are determined dynamically at runtime (often by LLM decisions). If your workflow always runs the same steps in the same order, LCEL is simpler. If your workflow has conditional branches, loops, or LLM-driven decision points, LangGraph is the right tool.

Misconception 2: "LangGraph state is automatically saved between user sessions."
Reality: Graph state is ephemeral by default  -  each `.invoke()` call starts with fresh state. Persistence between calls requires a **checkpointer**: `MemorySaver` stores state in memory (lost on restart, single-process only), `SqliteSaver` persists to a SQLite file, and database checkpointers (PostgreSQL via `langgraph-checkpoint-postgres`) provide production-grade persistence. The checkpointer is passed to `.compile()`. Multi-turn conversations that remember prior exchanges require a checkpointer and a consistent `thread_id` in the config passed to each invocation.

---

## Why It Matters in Practice

Graph visibility is essential for debugging LangGraph workflows. When an agent loop runs 8 tool calls before answering, understanding why requires seeing every intermediate state. `graph.astream_events()` yields low-level events including LLM token chunks and tool call results. LangSmith tracing captures the full graph execution as a tree, showing each node's input state, output state, and any LLM or tool calls made within it. Building without tracing makes it extremely difficult to diagnose why an agent made a particular sequence of decisions.

Termination conditions require explicit design. Unlike a simple RAG query that always terminates in exactly 3 steps (embed -> retrieve -> generate), an agentic loop can theoretically run indefinitely. A LangGraph graph without a reliable path to `END` will run until it hits a token limit or a hard-coded iteration count. Best practice: always set a maximum iteration count using a counter in state; add a conditional edge that routes to `END` if the iteration count is exceeded. This prevents runaway agents from incurring unbounded API costs.

---

## Interview Angle

Common question forms:
- "What is LangGraph and how does it differ from LangChain?"
- "How does state work in LangGraph?"
- "How do you prevent an agent loop from running forever?"

Answer frame: LangGraph is a stateful graph execution framework for LLM workflows that require cycles and branching  -  things LCEL cannot express. A `StateGraph` has nodes (functions that update state) and edges (transitions between nodes, including conditional branching). Shared state is a TypedDict with annotated reducers for merging updates. Compiled graph is a LangChain Runnable. Termination: explicit `END` node; prevent infinite loops with an iteration counter in state. Persistence: checkpointer parameter to `.compile()`, with `thread_id` per conversation. Prebuilt ReAct agent: `create_react_agent(llm, tools)`.

---

## Related Notes

- [[langchain-basics|LangChain Basics]]
- [[state-graph|State Graph]]
- [[nodes-and-edges|Nodes and Edges]]
- [[agents|Agents]]
