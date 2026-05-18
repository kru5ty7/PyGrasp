---
title: 10 - Supervisor Pattern
description: "The supervisor pattern in LangGraph uses an LLM as an orchestrator  -  the supervisor receives the task and conversation history, decides which worker agent to call next, and aggregates results until the task is complete; workers focus on execution, supervisor focuses on routing."
tags: [langgraph, supervisor, orchestrator, multi-agent, routing, worker-agents, layer-4, ai]
status: draft
difficulty: advanced
layer: 4
domain: ai
created: 2026-05-17
---

# Supervisor Pattern

> The supervisor pattern in LangGraph uses an LLM as an orchestrator  -  the supervisor receives the task and conversation history, decides which worker agent to call next, and aggregates results until the task is complete; workers focus on execution, supervisor focuses on routing.

---

## Quick Reference

**Core idea:**
- **Supervisor node**: an LLM that decides which worker to call next (or to finish)
- **Worker nodes**: specialized agents or tools that execute tasks; they don't decide what to do next
- Supervisor is called after every worker completes  -  it sees the accumulated results and decides the next step
- `FINISH` is the supervisor's signal to terminate  -  it routes to `END` when the task is done
- `create_react_agent` from `langgraph.prebuilt` builds worker agents quickly

**Tricky points:**
- Supervisor uses an LLM call every step  -  each routing decision costs tokens and latency
- Worker names in the supervisor's prompt must match actual node names  -  mismatches cause routing failures
- The supervisor can call the same worker multiple times  -  this is intentional for iterative refinement
- Without a clear task-complete criterion in the supervisor's prompt, it may loop indefinitely
- Supervisor chain-of-thought is visible in `verbose=True`  -  useful for debugging routing decisions

---

## What It Is

In the supervisor pattern, one LLM acts as a manager: given the task and what has been done so far, it decides which specialist to call next. The specialists are workers  -  they receive a specific subtask, execute it, and return results. The supervisor sees the results and decides the next step.

This mirrors how human teams work: a manager delegates to specialists, reviews their work, and decides what's needed next until the project is done.

---

## How It Actually Works

Full supervisor pattern:
```python
from langchain_anthropic import ChatAnthropic
from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.graph import StateGraph, MessagesState, START, END
from langgraph.prebuilt import create_react_agent
from typing import Literal

llm = ChatAnthropic(model="claude-sonnet-4-6")

# Define worker agents
search_tools = [web_search_tool]
code_tools = [python_repl_tool]

search_agent = create_react_agent(llm, search_tools)
code_agent = create_react_agent(llm, code_tools)

# Supervisor node
members = ["researcher", "coder"]

def supervisor_node(state: MessagesState) -> dict:
    system_prompt = f"""You are a supervisor managing these workers: {members}.
    Given the task and conversation so far, decide who should act next.
    Respond with ONLY one of: {members + ['FINISH']}.
    Respond FINISH when the task is complete."""
    
    response = llm.invoke(
        [SystemMessage(content=system_prompt)] + state["messages"]
    )
    next_worker = response.content.strip()
    
    # Store routing decision in messages for traceability
    return {
        "messages": [response],
        "next": next_worker,
    }

# State with routing field
from typing import Annotated
from langgraph.graph.message import add_messages

class SupervisorState(MessagesState):
    next: str  # which worker to call next

# Build the graph
graph = StateGraph(SupervisorState)
graph.add_node("supervisor", supervisor_node)
graph.add_node("researcher", search_agent)
graph.add_node("coder", code_agent)

graph.add_edge(START, "supervisor")

# Conditional edge from supervisor based on "next" field
graph.add_conditional_edges(
    "supervisor",
    lambda state: state["next"],
    {"researcher": "researcher", "coder": "coder", "FINISH": END}
)

# Workers always return to supervisor
graph.add_edge("researcher", "supervisor")
graph.add_edge("coder", "supervisor")

app = graph.compile()

result = app.invoke({
    "messages": [HumanMessage(content="Research Python async patterns, then write a code example.")],
    "next": "",
})
```

Structured output for supervisor routing (more reliable than parsing free text):
```python
from pydantic import BaseModel

class RouteDecision(BaseModel):
    next: Literal["researcher", "coder", "FINISH"]
    reasoning: str

structured_llm = llm.with_structured_output(RouteDecision)

def supervisor_node(state: MessagesState) -> dict:
    decision = structured_llm.invoke([system_message] + state["messages"])
    return {"next": decision.next}
```

---

## How It Connects

The supervisor pattern is the primary architecture for multi-agent systems in LangGraph.
[[multi-agent-systems|Multi-Agent Systems]]

`create_react_agent` builds the worker agents that the supervisor orchestrates.
[[agents|Agents]]

---

## Common Misconceptions

Misconception 1: "The supervisor must be a more capable model than the workers."
Reality: Workers often need more reasoning capability than the supervisor  -  the supervisor makes routing decisions (simple classification), while workers execute complex tasks. You can use a cheaper model for the supervisor.

Misconception 2: "The supervisor pattern requires many agents."
Reality: A supervisor with two workers is still the supervisor pattern. The value is the separation between routing logic and execution logic  -  this applies even with just one worker.

---

## Why It Matters in Practice

Debugging supervisor loops:
```python
# Stream events to trace which workers are called and in what order
for event in app.stream({"messages": [...], "next": ""}):
    for node_name, state in event.items():
        print(f"=== {node_name} ===")
        if "messages" in state:
            print(state["messages"][-1].content[:200])
```

Common failure modes:
- **Infinite loop**: supervisor never returns `FINISH`  -  fix the stopping condition in the system prompt
- **Wrong worker selected**: worker names in prompt don't match node names  -  align them exactly
- **Lost context**: workers don't have access to prior worker results  -  verify state merging is working

---

## Interview Angle

Common question forms:
- "How would you design a multi-agent research and writing system?"
- "What is the supervisor pattern?"

Answer frame: Supervisor = LLM that decides which worker runs next. Workers execute; supervisor orchestrates. Pattern: START -> supervisor -> [worker] -> supervisor (loop) -> FINISH -> END. Supervisor sees full message history, including worker results. Use structured output (`with_structured_output`) for reliable routing decisions. Workers return to supervisor after every execution.

---

## Related Notes

- [[multi-agent-systems|Multi-Agent Systems]]
- [[langgraph-core|LangGraph Core]]
- [[agents|Agents]]
- [[conditional-edges|Conditional Edges]]
