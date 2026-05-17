---
title: 08 - Human-in-the-Loop
description: "LangGraph human-in-the-loop pauses graph execution at an interrupt point — `interrupt_before` or `interrupt_after` on the compiled graph stops at a specified node; execution resumes with `app.invoke(None, config)` after state has been inspected or updated."
tags: [langgraph, human-in-the-loop, interrupt, approval, pause-resume, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Human-in-the-Loop

> LangGraph human-in-the-loop pauses graph execution at an interrupt point — `interrupt_before` or `interrupt_after` on the compiled graph stops at a specified node; execution resumes with `app.invoke(None, config)` after state has been inspected or updated.

---

## Quick Reference

**Core idea:**
- `graph.compile(interrupt_before=["node_name"])` — pause execution before the specified node runs
- `graph.compile(interrupt_after=["node_name"])` — pause execution after the node runs (inspect its output)
- Resume: `app.invoke(None, config)` — pass `None` as input to continue from the checkpoint
- `app.update_state(config, updates)` — modify state before resuming (for human corrections)
- Requires checkpointing — interrupts persist state so execution can resume later

**Tricky points:**
- `interrupt_before` is more common for approval workflows — human sees what the agent is *about to do* and can approve or cancel
- Resume passes `None` as the new input — the graph continues from the saved checkpoint, not from a new input
- Without `app.update_state()` before resuming, the graph continues exactly where it left off
- Multiple `interrupt_before` nodes are supported — graph pauses at each one in order
- In async applications, the pause is implemented by stopping the event loop iteration — the web handler returns a "pending" response

---

## What It Is

Human-in-the-loop enables a human to review, approve, or modify agent actions before they execute. This is critical for high-stakes operations (sending emails, deleting records, making purchases) where autonomous execution is unacceptable.

The mechanism: compile the graph with an interrupt point, run until the interrupt, persist state via checkpointing, return control to the caller. The human reviews the pending action, optionally edits state, then resumes execution.

---

## How It Actually Works

Basic approval workflow:
```python
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import StateGraph, MessagesState, START, END

def draft_action(state: MessagesState) -> dict:
    """Draft an action that requires human approval."""
    return {"messages": [AIMessage(content="I will delete the user record for ID 42.")]}

def execute_action(state: MessagesState) -> dict:
    """Actually execute the action."""
    # delete_user(42)
    return {"messages": [AIMessage(content="User 42 deleted.")]}

graph = StateGraph(MessagesState)
graph.add_node("draft", draft_action)
graph.add_node("execute", execute_action)
graph.add_edge(START, "draft")
graph.add_edge("draft", "execute")
graph.add_edge("execute", END)

checkpointer = MemorySaver()

# Interrupt BEFORE execute — human approves before the action runs
app = graph.compile(
    checkpointer=checkpointer,
    interrupt_before=["execute"],
)

config = {"configurable": {"thread_id": "task-001"}}

# Run until the interrupt
result = app.invoke(
    {"messages": [HumanMessage(content="Delete user 42")]},
    config=config,
)
# Execution paused; result contains state up to the interrupt

# Inspect the pending action
state = app.get_state(config)
print(state.values["messages"][-1].content)  # "I will delete the user record for ID 42."
print(state.next)                             # ["execute"] — waiting to run this node

# Human approves — resume without changes
app.invoke(None, config=config)

# OR: Human rejects — update state to cancel
app.update_state(
    config,
    {"messages": [HumanMessage(content="Actually, cancel this operation.")]},
    as_node="draft",  # treat this update as coming from the "draft" node
)
```

Dynamic interrupt using `interrupt()` function:
```python
from langgraph.types import interrupt

def human_review_node(state: dict) -> dict:
    """Pause and ask the human a question."""
    answer = interrupt({
        "question": "Should I proceed with this action?",
        "proposed_action": state["proposed_action"],
    })
    # answer is provided by the human when resuming
    return {"approved": answer["approved"]}
```

Resuming with input after a dynamic interrupt:
```python
from langgraph.types import Command

# Resume and provide human input
app.invoke(
    Command(resume={"approved": True}),
    config=config,
)
```

---

## How It Connects

Checkpointing is a prerequisite — interrupts persist state so execution can resume.
[[checkpointing|Checkpointing]]

Multi-agent systems use human-in-the-loop to require approval before delegating to a subagent.
[[multi-agent-systems|Multi-Agent Systems]]

---

## Common Misconceptions

Misconception 1: "Human-in-the-loop requires a web UI."
Reality: The interrupt mechanism is purely about pausing and resuming graph execution. The "human review" can happen via CLI input, a web form, an email approval link, or any other mechanism — LangGraph only provides the pause/resume primitives.

Misconception 2: "Resuming with `None` replays the entire graph."
Reality: `app.invoke(None, config)` resumes from the checkpoint — only the remaining nodes run. Completed nodes are not re-executed.

---

## Why It Matters in Practice

Common patterns:
- **Approval gates**: interrupt before a destructive action (delete, send, charge) — human must approve
- **Content review**: interrupt after an LLM drafts content — human edits before it's published
- **Error recovery**: interrupt when the agent detects an ambiguous situation — human provides clarification

The approval pattern is the most common: run the planning phase autonomously, pause before execution, human approves or modifies the plan, then execution proceeds.

---

## Interview Angle

Common question forms:
- "How do you add human approval to a LangGraph agent?"
- "What is interrupt_before in LangGraph?"

Answer frame: Compile with `interrupt_before=["node"]` — graph pauses before that node. Requires checkpointing. Resume with `app.invoke(None, config)`. Inspect state with `app.get_state(config)`, modify with `app.update_state(config, values)`. Use cases: approval gates before destructive actions, content review, human clarification.

---

## Related Notes

- [[checkpointing|Checkpointing]]
- [[state-management|State Management]]
- [[langgraph-core|LangGraph Core]]
- [[multi-agent-systems|Multi-Agent Systems]]
