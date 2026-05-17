---
title: Agents
description: An LLM agent is a system where an LLM acts as a reasoning engine that decides what actions to take — calling tools, observing results, and iterating until a goal is achieved — rather than generating a single fixed response.
tags: [agents, react, llm, tool-calling, agentic-loop, planning, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Agents

> An LLM agent is a system where an LLM acts as a reasoning engine that decides what actions to take — calling tools, observing results, and iterating until a goal is achieved — rather than generating a single fixed response.

---

## Quick Reference

**Core idea:**
- An agent loop: **perceive** (read state/context) → **reason** (LLM decides next action) → **act** (execute tool or produce final answer) → repeat until done
- The **ReAct pattern** (Reasoning + Acting) interleaves chain-of-thought reasoning with tool calls — the model thinks, calls a tool, observes the result, thinks again, and so on
- Agents are **stateful over multiple LLM calls** — conversation history (messages) accumulates across the loop, giving the LLM full context of what it has tried and observed
- Tool calling is the agent's **actuator** — without tools, the LLM can only generate text; with tools, it can retrieve, compute, write, and interact with external systems
- `create_react_agent(llm, tools)` in LangGraph creates a prebuilt ReAct agent graph — a complete implementation of the LLM node → tools condition → tool node → LLM loop

**Tricky points:**
- Agents can **loop indefinitely** — always set a maximum iteration count; the prebuilt agent uses `recursion_limit` in config; custom graphs need an explicit counter in state
- **Cascading errors**: a wrong tool call produces wrong results; the model reasons from those wrong results and may make further wrong calls — errors compound over long loops
- The LLM's **context window grows** with each tool call and result added to messages — very long agent runs can exhaust the context window; summarization or message trimming may be needed
- **Determinism is not guaranteed** — the same agent on the same input may take different tool call sequences across runs due to LLM sampling; agents are inherently non-deterministic systems
- Agent quality degrades with tool count — too many tools overwhelm the model's selection ability; keep the tool set small and focused

---

## What It Is

Think of an LLM agent as a detective solving a case. A simple chatbot answers questions from its memory — like a detective who only knows what they were told at the briefing. An agent is a detective who can go out and investigate: look up records, interview witnesses, examine evidence, and follow leads. The detective does not know everything upfront — they discover it. After each piece of evidence (tool result), they update their theory of the case (reasoning) and decide what to investigate next. They stop when they have enough to name the culprit (the goal is achieved) or when they run out of leads (the task is impossible).

The key difference between an LLM chatbot and an LLM agent is the presence of a decision loop that can extend an arbitrary number of steps, with external actions (tool calls) at each step. A chatbot processes one user message and returns one response. An agent processes a user request, then may take 2, 5, or 20 steps of tool calling and reasoning before producing a final response — and the number of steps is not fixed at design time, it is determined by the LLM's reasoning at runtime. This is what makes agents powerful and also what makes them harder to control, debug, and reason about than simple LLM calls.

The ReAct (Reasoning + Acting) pattern is the dominant approach for LLM agents. The model is prompted to alternate between `Thought:` (reasoning about the current state and what to do next) and `Action:` (a tool call). After each action, `Observation:` contains the tool result. With modern function-calling models, this pattern is implemented implicitly: the model's tool call represents the "act" step, and the next LLM call (with the full message history including the tool result) represents the "reason" step, without requiring explicit "Thought:" labels in the output.

---

## How It Actually Works

The ReAct agent loop in LangGraph is a graph with three components. The **LLM node** sends the current messages state to the LLM and receives an `AIMessage` response. If the response contains `tool_calls`, the messages are updated with the `AIMessage` and execution routes to the **ToolNode**. The **ToolNode** dispatches each tool call to the corresponding function, collects results as `ToolMessage` objects, and adds them to messages. Execution routes back to the **LLM node**, which sees the full updated history (original request + all prior tool calls and results) and decides the next step. This loop continues until the LLM produces an `AIMessage` with no `tool_calls` and `finish_reason: "stop"`, which routes to `END`.

The `tools_condition` routing function (from `langgraph.prebuilt`) implements this routing: it inspects the last message in the state — if it is an `AIMessage` with `tool_calls`, return `"tools"`; otherwise return `END`. `create_react_agent(llm, tools)` builds the full graph: adds the LLM node (`agent`), adds the `ToolNode` (`tools`), adds the entry edge to `agent`, adds `tools_condition` as the conditional edge from `agent`, and adds an unconditional edge from `tools` back to `agent`. The resulting graph implements the complete ReAct loop.

**Planning agents** extend the basic ReAct pattern by adding an explicit planning step. A planner LLM call produces a structured plan (a list of subtasks) before any tool calls. Each subtask is dispatched to a sub-agent or tool. Results are collected and a final synthesis step produces the answer. This pattern improves performance on complex multi-step tasks that benefit from upfront decomposition, at the cost of higher latency (the planning step adds an LLM call before execution begins).

**Multi-agent systems** use LangGraph's ability to call one compiled graph from within a node of another graph. A supervisor agent receives a task, determines which specialized sub-agent is best suited (research agent, coding agent, data analysis agent), and routes the task to it. Each sub-agent has its own tool set, system prompt, and state. The supervisor collects results and synthesizes the final answer. This architecture enables specialization without requiring a single agent to be competent at everything.

---

## How It Connects

Tool calling is the mechanism that gives agents agency — the ability to do things beyond generating text. Every action step in the agent loop is a tool call. Understanding the tool call format, how tools are described, and how results are returned to the LLM is the mechanical foundation of agent behavior.
[[tool-calling|Tool Calling]]

LangGraph is the framework for implementing agents as stateful graphs. The agent loop — LLM call → conditional routing → tool execution → loop back — is a naturally cyclic graph, which is what LangGraph was designed to express. Without LangGraph (or an equivalent), implementing the agent loop requires manually managing the message history, dispatching tool calls, and handling the iteration logic.
[[langgraph-core|LangGraph Core]]

The LLM is the agent's reasoning engine. Its quality — instruction following, tool selection accuracy, reasoning coherence across long contexts — directly determines agent capability. Context window size limits how many tool call iterations the agent can perform before the history must be trimmed.
[[llm-basics|LLM Basics]]

Agent loops are inherently async — each LLM call and each tool call is an awaitable I/O operation. An agent making 8 tool calls in parallel (via `Send`) across a 5-second LLM round-trip can complete in 5 seconds rather than 40. Building agents without async concurrency, using synchronous LLM and tool calls inside an async web application, blocks the event loop for the duration of each call.
[[async-await|Async and Await]]

---

## Common Misconceptions

Misconception 1: "Agents are always better than fixed pipelines for complex tasks."
Reality: Agents are appropriate when the number and sequence of steps cannot be determined in advance — the LLM must decide dynamically. For tasks where the steps are known in advance (summarize → extract → format → send), a fixed LangChain LCEL pipeline or LangGraph workflow with explicit nodes and edges is more reliable, predictable, and debuggable. Agents introduce non-determinism and failure modes (wrong tool selection, incorrect reasoning) that fixed pipelines do not. The right choice is the simplest architecture that accomplishes the task reliably.

Misconception 2: "Adding more tools to an agent makes it more capable."
Reality: More tools increase the model's decision surface and degrade tool selection accuracy. Research has shown that most models' ability to select the correct tool degrades significantly beyond 10–15 tools. The effective way to build agents that handle many actions is dynamic tool selection: retrieve the most relevant tools for the current query from a tool registry, and register only those with the model. This gives the agent access to a large library of capabilities while keeping the per-call decision surface manageable.

---

## Why It Matters in Practice

Agent reliability requires guardrails at multiple levels. At the LLM level: a well-written system prompt that defines the agent's role, available tools, and when to stop. At the graph level: a maximum iteration count enforced by the graph structure (conditional edge to END if iteration counter >= max). At the tool level: input validation before execution, rate limiting for expensive external calls, and read-only tools wherever possible. At the application level: human-in-the-loop approval for high-stakes actions (sending emails, writing to databases, making purchases). Agents without these guardrails are unreliable in production.

Observability is non-negotiable for agent systems. When an agent produces a wrong answer, diagnosing why requires knowing the full reasoning trace: what the model said at each step, what tools were called with what arguments, what the tools returned. LangSmith provides this automatically for LangGraph agents — every node execution, every LLM call, and every tool call is captured as a trace. Without tracing, debugging a multi-step agent failure is analogous to debugging a production issue with no logs.

---

## Interview Angle

Common question forms:
- "What is an LLM agent?"
- "Explain the ReAct pattern."
- "How do you prevent an agent from running forever?"

Answer frame: An agent is an LLM in a loop with tools — it reasons, acts (calls tools), observes results, reasons again, and iterates until it achieves the goal. ReAct: alternates reasoning (chain of thought) with acting (tool calls). Implemented in LangGraph as: LLM node → tools_condition → ToolNode → back to LLM. Termination: explicit `END` routing when LLM produces no tool calls; hard maximum iteration limit in state to prevent infinite loops. Observability: LangSmith traces every step. Common failure modes: wrong tool selection, cascading errors from bad tool results, context window exhaustion on long runs.

---

## Related Notes

- [[tool-calling|Tool Calling]]
- [[langgraph-core|LangGraph Core]]
- [[state-graph|State Graph]]
- [[nodes-and-edges|Nodes and Edges]]
- [[llm-basics|LLM Basics]]
