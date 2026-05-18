---
title: 04 - Nodes and Edges
description: Nodes are the functions that process state in a LangGraph graph; edges are the transitions between them  -  together they define the structure of the workflow, including conditional branching and parallel fan-out with Send.
tags: [nodes, edges, langgraph, conditional-edges, send, routing, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Nodes and Edges

> Nodes are the functions that process state in a LangGraph graph; edges are the transitions between them  -  together they define the structure of the workflow, including conditional branching and parallel fan-out with Send.

---

## Quick Reference

**Core idea:**
- A **node** is any Python callable added with `graph.add_node("name", function)`  -  it receives the full current state and returns a dict of state updates
- An **edge** is a directed transition: `graph.add_edge("a", "b")` means after node `a` completes, node `b` runs next
- **Conditional edges** use a routing function: `graph.add_conditional_edges("a", router, {"yes": "b", "no": END})`  -  `router(state)` returns a string key mapped to the next node
- **`Send`** enables parallel fan-out: returning `[Send("node", state_override), ...]` from a routing function spawns multiple parallel executions of the same node with different inputs
- `END` is the terminal node  -  any edge pointing to `END` ends that execution path; execution completes when all active paths reach `END`

**Tricky points:**
- A node function must **return a dict** (not `None`)  -  returning `None` raises a LangGraph error; return `{}` for no-op nodes
- The **routing function** for conditional edges receives the full state and must return a string  -  the string must be a key in the mapping dict passed to `add_conditional_edges`
- `Send` passes a **custom state dict** to the target node, not the full current state  -  use it for map-reduce patterns where each parallel branch has its own input
- **`__start__`** is the internal name for the entry point  -  `set_entry_point("node")` is equivalent to `add_edge("__start__", "node")`
- Node functions can be **async** (`async def`)  -  LangGraph awaits them and all async I/O within runs on the event loop without blocking

---

## What It Is

Think of a node as a workstation on a factory floor and an edge as the conveyor belt between workstations. A workstation receives a work-in-progress item (the state), performs its specific operation (the node function's logic), places the modified item back on the conveyor (returns the state update), and the conveyor directs it to the next workstation (the edge target). Some conveyor belts go to a fixed next station (unconditional edges). Others have a diverter: a worker inspects the item and sends it left or right depending on its current condition (conditional edges). And some stations spin up multiple copies of an item to be processed in parallel (Send-based fan-out), which converge at a later assembly point.

Nodes are where all the work happens in a LangGraph workflow. The node function is where you call the LLM, execute a tool, format a response, check a condition, query a database, or perform any computation. The graph structure (nodes and edges) is purely about flow control  -  which functions run, in what order, and with what conditions. The node functions themselves can be anything: a simple lambda that increments a counter, a complex async function that calls an LLM and parses its response, a LangChain Runnable chain, or a prebuilt tool executor.

Edges encode the logic of the workflow at the structural level. An unconditional edge says "this step always leads to that step." A conditional edge says "after this step, the next step depends on the current state of the workflow." The separation between what nodes do (computation) and what edges say (routing) is a clean architectural pattern: the routing logic is explicit and visible in the graph structure, rather than buried inside node function bodies with early returns or flag variables.

---

## How It Actually Works

Registering a node: `graph.add_node("llm_call", llm_node_function)`. The function signature can be `def llm_node(state: AgentState) -> dict` or `async def llm_node(state: AgentState) -> dict`. LangGraph detects async functions and awaits them automatically. It also accepts any callable: a lambda, a class with `__call__`, a bound method, or a LangChain Runnable (which LangGraph calls via `.invoke(state)` for sync or `.ainvoke(state)` for async execution).

Registering edges: `graph.add_edge("a", "b")` creates a directed edge from `a` to `b`. Multiple edges from the same node are allowed  -  `graph.add_edge("a", "b"); graph.add_edge("a", "c")` would run both `b` and `c` after `a`, in parallel. For conditional edges: `graph.add_conditional_edges("a", routing_fn, {"continue": "b", "end": END})`. After node `a` completes, `routing_fn` is called with the current state. If it returns `"continue"`, node `b` runs. If it returns `"end"`, execution terminates.

The `Send` API enables dynamic parallelism. A routing function can return a list of `Send` objects instead of a string: `return [Send("process_item", {"item": item}) for item in state["items"]]`. Each `Send` spawns an independent execution of the target node with the specified state override. All spawned executions run concurrently (using `asyncio.gather()` in async mode). Their outputs are collected and merged back into the main graph state using the field reducers  -  the standard pattern being an append reducer on a list field that collects all parallel results.

Node execution order follows the graph structure. LangGraph's execution engine traverses the graph from the entry point, maintaining a queue of nodes ready to run (nodes whose predecessor node has completed). For sequential chains, nodes run one at a time. For parallel paths (multiple outgoing edges or `Send`), multiple nodes run concurrently. After all nodes in a parallel batch complete, execution continues from their common successor.

---

## How It Connects

Nodes and edges populate the StateGraph. The StateGraph defines the state schema and provides the `.add_node()`, `.add_edge()`, `.add_conditional_edges()`, and `.compile()` methods. Understanding the state graph's structure and the role of reducers in merging node outputs is the context in which nodes and edges operate.
[[state-graph|State Graph]]

The tools node is a specific and common node in agent graphs  -  it receives tool call requests from the LLM node, dispatches them to the appropriate tool functions, and returns results to the state. Understanding tool calling is understanding the most important node type in agentic workflows.
[[tool-calling|Tool Calling]]

Nodes that call LLMs are async functions that `await` the LLM response. The `Send` API runs parallel nodes via `asyncio.gather()`. Understanding the event loop's role in concurrent node execution  -  and why blocking the event loop inside an `async def` node function degrades performance  -  is the same concurrency knowledge that applies throughout Python's async stack.
[[event-loop|The Event Loop]]

---

## Common Misconceptions

Misconception 1: "Conditional edges put the routing logic inside the node function."
Reality: Routing logic belongs in the routing function passed to `add_conditional_edges`, not inside the node function. A node function's job is to update state. The routing function's job is to inspect the updated state and decide the next step. Mixing routing logic into node functions (e.g., checking flags and returning different partial states to signal which path to take) obscures the graph's flow control and makes the graph structure harder to reason about. Explicit routing functions keep the graph's branching visible in the graph definition.

Misconception 2: "`Send` creates new threads or processes."
Reality: `Send` creates parallel coroutines on the same event loop  -  it is concurrency, not parallelism in the CPU sense. If the parallel nodes make async I/O calls (LLM API requests, tool calls that are network requests), they can all be in-flight simultaneously on the same event loop thread, which is efficient. If the parallel nodes perform CPU-bound work (parsing, encoding, complex computation), they still run on the same OS thread and contend for the GIL  -  they do not achieve true CPU parallelism. For CPU-bound parallel processing, the node function would need to use `asyncio.to_thread()` internally.

---

## Why It Matters in Practice

The routing function for a conditional edge is a pure function of state  -  it should have no side effects and no LLM calls. Routing decisions based on state inspection (checking whether `state["tool_calls"]` is empty, whether `state["iteration_count"] >= MAX_ITERATIONS`, whether `state["final_answer"]` is set) are fast, deterministic, and debuggable. Routing decisions that themselves call an LLM introduce latency and non-determinism into what should be a structural decision  -  a common anti-pattern in LangGraph design.

The `Send` API is the correct pattern for map-reduce workflows in LangGraph. A common pattern: one node generates a list of items to process (search results, document chunks, subtasks); a `Send` routing function spawns one execution of a processing node per item; all results are collected into a list field via an append reducer; a final aggregation node reads the list and produces a combined output. This pattern enables parallelizing expensive per-item operations (LLM calls per chunk, tool calls per search result) across the full batch, with latency bounded by the slowest item rather than the sum of all items.

---

## Interview Angle

Common question forms:
- "How do you add conditional branching to a LangGraph graph?"
- "What is the Send API and when would you use it?"
- "How do nodes communicate with each other in LangGraph?"

Answer frame: Nodes are functions `(state) -> dict`  -  they read state and return updates. Edges are transitions between nodes. Conditional edges: `add_conditional_edges(source, routing_fn, mapping)`  -  routing function inspects state and returns a key mapped to the next node. Nodes communicate exclusively through shared state (not direct calls). `Send` enables parallel fan-out: routing function returns a list of `Send(node, state_override)` objects, spawning concurrent coroutines on the event loop. Results merge via reducers. Map-reduce pattern: fan out with Send, collect results via append reducer, aggregate in a final node.

---

## Related Notes

- [[langgraph-core|LangGraph Core]]
- [[state-graph|State Graph]]
- [[agents|Agents]]
- [[tool-calling|Tool Calling]]
