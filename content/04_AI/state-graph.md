---
title: State Graph
description: A state graph is LangGraph's primary data structure — it defines the schema for shared state, the nodes that read and update it, and the edges that control flow between nodes, compiling into a Runnable that executes the workflow.
tags: [state-graph, langgraph, state, reducers, typeddict, workflow, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# State Graph

> A state graph is LangGraph's primary data structure — it defines the schema for shared state, the nodes that read and update it, and the edges that control flow between nodes, compiling into a Runnable that executes the workflow.

---

## Quick Reference

**Core idea:**
- `StateGraph(StateSchema)` creates a graph that maintains a shared state object conforming to `StateSchema` (a TypedDict or Pydantic model)
- **Nodes** are Python functions with signature `(state: StateSchema) -> dict` — the returned dict contains only the keys being updated
- **Reducers** are annotated on state fields to define how updates are merged: `Annotated[list, operator.add]` appends; default (no annotation) replaces
- The entry point (`set_entry_point`) and `END` define where execution starts and stops; `.compile()` validates the graph and returns a Runnable
- `MessagesState` is a prebuilt state schema that provides a `messages` field with an `add_messages` reducer — the standard starting point for chat-based agents

**Tricky points:**
- A node that returns `{}` (empty dict) makes **no state changes** — this is valid and useful for side-effect-only nodes (e.g., logging)
- **Reducers must be pure functions** — they should not have side effects, as LangGraph may call them multiple times during checkpointing or state reconstruction
- The `messages` field with `add_messages` reducer deduplicates messages by ID — updating a message by returning one with the same ID replaces it, not appends
- **Pydantic state schemas** provide field validation at update time — if a node returns an invalid value for a field, LangGraph raises a validation error before merging the update
- Parallel node execution (via `Send`) can write to the same state fields — reducers handle the merge, but non-commutative reducers (like replace) produce non-deterministic results with parallel writes

---

## What It Is

Think of the state graph as a recipe card for a complex dish where the cook (the LLM) reads the current state of the dish (the state object), performs one action (a node), writes down what changed (the partial update), and then decides which step to do next (edge routing). The recipe card is not filled in until the dish is made — it starts blank, and each cook's action adds to it. The state graph is that recipe card plus the rules for who can write what and when. The final state, when the recipe is complete, is the finished dish — the output of the entire workflow.

In LangGraph, all information that must be communicated between nodes passes through the shared state object. Nodes do not call each other directly. Node A does not pass a return value to node B. Instead, node A updates the state, and node B reads from the state. This is an explicit design decision: it makes the information flow visible, auditable, and persistable. At any point during execution, you can inspect the full state and understand exactly what has happened so far. You can serialize it to a database, restore it, and resume execution — which is what checkpointing does.

The state schema is the contract between all nodes in the graph. Every node sees the same keys. A node that only cares about `messages` ignores `tool_results` and `iteration_count`. A node that counts iterations reads `iteration_count`, increments it, and returns `{"iteration_count": current + 1}`. Defining the schema upfront forces the graph designer to be explicit about every piece of information that flows through the workflow, which is a significant advantage for understanding and debugging complex multi-step agents.

---

## How It Actually Works

Defining a state schema with TypedDict: every key in the TypedDict becomes a field in the state. Fields annotated with `Annotated[type, reducer_function]` use the specified reducer when updates arrive; fields without an annotation use the default replace reducer. For example:

```python
class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    iteration_count: int
    final_answer: str | None
```

`messages` appends new messages without duplication. `iteration_count` and `final_answer` are replaced on each update. The state starts with the initial values passed to `.invoke(initial_state)`.

`MessagesState` is the convenience base class: it defines `messages: Annotated[list[AnyMessage], add_messages]` and nothing else. Many agent graphs derive from `MessagesState` or use it directly, adding additional fields as needed via subclassing or a new TypedDict that includes the same `messages` field.

When a node function runs, LangGraph calls it with the current full state dict. The node accesses state keys it needs (`state["messages"]`, `state["iteration_count"]`), performs its work, and returns a dict of updates. LangGraph then applies each update: for each key in the returned dict, it calls the reducer `new_state[key] = reducer(current_state[key], update_value)`. The resulting merged state is stored (in the checkpointer if one is set) and passed to the next node.

The `.compile()` step performs validation: it checks that every node has at least one outgoing edge (or is `END`), that all referenced node names exist, and that the entry point is defined. It returns a `CompiledStateGraph`. Under the hood, `.compile()` builds the execution plan: it creates an `asyncio`-compatible executor that runs nodes in topological order (for nodes with no data dependencies on each other) or sequentially (for nodes connected by edges), calling checkpointer `put()` after each node to persist state.

---

## How It Connects

The state graph is LangGraph's core data structure — understanding it in detail is understanding what LangGraph does. The graph definition (node functions, edge structure, state schema with reducers) is the static structure; the compiled graph's execution against an initial state is the dynamic behavior.
[[langgraph-core|LangGraph Core]]

Nodes and edges are the components that populate the state graph. Nodes define the computation; edges define the flow control. The state graph is the container that holds them and defines the state schema they operate on.
[[nodes-and-edges|Nodes and Edges]]

State graph execution is async at its core — compiled graphs implement `ainvoke()` and `astream()`. Understanding how coroutines and the event loop enable concurrent node execution and async LLM calls within nodes is the mechanical foundation for building efficient LangGraph workflows.
[[coroutines|Coroutines]]

---

## Common Misconceptions

Misconception 1: "State fields without reducers are shared mutable state — nodes can corrupt each other."
Reality: LangGraph state updates are applied atomically by the framework, not by nodes directly. Nodes return a dict of desired updates; LangGraph applies the updates after the node completes. Two nodes running sequentially cannot corrupt each other because only one runs at a time (in the typical sequential execution model). For genuinely parallel execution using `Send`, LangGraph resolves updates using reducers — parallel writes to the same field go through the reducer, not uncontrolled concurrent mutation.

Misconception 2: "The initial state passed to `.invoke()` must contain all state fields."
Reality: Unset fields default to their zero values — `None` for optional types, `[]` for list fields. You only need to provide the fields that should be non-default at the start of execution. For a `MessagesState`-based graph, `graph.invoke({"messages": [HumanMessage("Hello")]})` is sufficient — `messages` is set to the initial human message, and any other fields in the state schema start at their defaults.

---

## Why It Matters in Practice

Schema design is the most impactful architectural decision in a LangGraph workflow. Fields that should accumulate over the workflow's lifetime (tool call results, retrieved documents, intermediate reasoning steps) should use accumulating reducers (append to a list). Fields that represent the current decision or status (which tool to call next, whether the task is complete) should use the replace reducer. Mixing up these semantics produces bugs that are difficult to diagnose — a "current tool" field that inadvertently appends instead of replaces will carry stale tool selections forward into later nodes.

Adding fields to the state schema is cheap — adding a new key to the TypedDict and using it in the nodes that need it requires no changes to the graph structure itself. This makes it straightforward to add tracking information (timestamps, intermediate results, retry counts) without restructuring the workflow. The state schema acts as the workflow's data model, and evolving it is analogous to evolving a database schema — a lightweight migration rather than an architectural rewrite.

---

## Interview Angle

Common question forms:
- "What is the state graph in LangGraph and how does it manage state?"
- "What is a reducer in LangGraph?"
- "How does state persist between nodes?"

Answer frame: StateGraph takes a TypedDict schema that defines the shared state all nodes read from and write to. Nodes return partial updates (only the keys they're changing); LangGraph applies those updates via reducers. Reducers define how updates merge — `operator.add` appends to a list, the default replaces. MessagesState provides the standard messages field with `add_messages` (dedup by ID). Compilation validates the graph and returns a Runnable. Checkpointers persist state after each node — enabling pause, resume, and multi-turn memory.

---

## Related Notes

- [[langgraph-core|LangGraph Core]]
- [[nodes-and-edges|Nodes and Edges]]
- [[agents|Agents]]
