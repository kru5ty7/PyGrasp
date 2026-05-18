---
title: 02 - Tool Calling
description: Tool calling is the mechanism by which LLMs request execution of external functions  -  the model outputs structured JSON describing which tool to call and with what arguments, the application executes the function, and the result is returned to the model.
tags: [tool-calling, function-calling, tools, llm, agents, json-schema, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Tool Calling

> Tool calling is the mechanism by which LLMs request execution of external functions  -  the model outputs structured JSON describing which tool to call and with what arguments, the application executes the function, and the result is returned to the model.

---

## Quick Reference

**Core idea:**
- Tool calling = the LLM outputs a **tool call** (a JSON object with `name` and `arguments`) instead of a text response when it determines a tool is needed
- The **application** receives the tool call, executes the corresponding function, and sends the result back to the LLM as a `ToolMessage`
- Tools are described to the LLM as **JSON Schema** objects  -  the schema tells the model the tool's name, description, and the shape of its arguments
- The LLM can request **multiple tool calls in parallel** in a single response  -  the model outputs a list of tool calls, all of which should be executed before continuing
- In LangGraph, the `ToolNode` from `langgraph.prebuilt` handles tool dispatch automatically  -  it routes tool call requests to the right function and adds `ToolMessage` results to state

**Tricky points:**
- Tool calling is a **sampling process**  -  the model sometimes calls tools unnecessarily, calls the wrong tool, or hallucinates argument values; validate tool inputs before execution
- The model **does not execute tools**  -  it outputs a request; your application decides whether and how to execute it; you can intercept, validate, or reject tool calls
- `tool_choice="required"` forces the model to call a tool (useful for structured extraction); `tool_choice="none"` disables tool calling; the default (`"auto"`) lets the model decide
- A tool's **description string** is the primary signal the model uses to decide when to call it  -  poorly written descriptions lead to wrong or missing tool calls
- **Parallel tool calls** can be disabled per-request with `parallel_tool_calls=False`  -  useful when tools have side effects that must execute sequentially

---

## What It Is

Think of tool calling as a manager (the LLM) who can delegate tasks to specialists (the tools) but cannot do those tasks directly. The manager reads the incoming request, decides which specialists are needed, writes a delegation note specifying the task and the required information, and waits for the results before continuing. The manager does not pick up the phone  -  they write the note and hand it to their assistant (your application). The assistant makes the call, gets the result, and brings it back to the manager, who then synthesizes the information into a final answer. The manager never executes anything directly; they only decide what should be executed and by whom.

Before tool calling existed as a first-class API feature, developers prompted LLMs to output structured JSON that looked like function calls and then parsed that JSON themselves. This was fragile  -  the model might output slightly malformed JSON, use inconsistent argument names, or omit required fields. Tool calling formalizes this pattern: the model is fine-tuned to output properly structured tool call objects (not as part of the text content, but as a separate structured field in the response), and the API guarantees that if the model outputs a tool call, it conforms to the JSON Schema of the registered tool.

The tool calling pattern unlocks a qualitative capability shift. An LLM without tools can only generate text based on its training knowledge. An LLM with tools can retrieve current information (web search, database queries), perform precise computation (calculators, code interpreters), modify external systems (send emails, update records, execute code), and verify its own reasoning (by calling tools that check facts). The combination of the LLM's reasoning capabilities with actual function execution makes the difference between a chatbot and an agent.

---

## How It Actually Works

Tools are registered by providing their JSON Schema descriptions to the LLM API. The OpenAI-compatible format: each tool is a dict with `"type": "function"`, `"function": {"name": ..., "description": ..., "parameters": {...}}` where `parameters` is a JSON Schema object describing the function's arguments. The LLM reads these tool descriptions as part of its context and uses the name and description fields to decide when and which tool to call.

When the LLM decides to call a tool, the API response has `finish_reason: "tool_calls"` (instead of `"stop"`) and a `tool_calls` list on the message object. Each tool call has an `id` (a unique identifier for this specific call), `type: "function"`, and `function: {"name": ..., "arguments": "..."}` where `arguments` is a JSON-encoded string of the call's arguments. The application parses the arguments, looks up the corresponding function, calls it with the parsed arguments, and constructs a `ToolMessage` with `tool_call_id` matching the call's `id` and `content` set to the function's result (as a string or JSON string).

This `ToolMessage` is appended to the conversation history and the full updated history is sent back to the LLM. The LLM sees: the original request, its tool call decision, and the result of the tool call. It can now either generate a final text answer based on the tool result, or decide it needs another tool call and output another `tool_calls` response. This loop continues until the model outputs a text response without tool calls.

LangChain's `@tool` decorator simplifies tool definition. Decorating a function with `@tool` extracts its name, docstring, and type annotations to build the JSON Schema automatically. `bind_tools([my_tool])` on a chat model registers the tools for that model instance. The `ToolNode` in LangGraph receives a state with `messages[-1].tool_calls`, dispatches each call to the correct function in parallel (using a `tools_by_name` dict), and adds `ToolMessage` results to the messages state. The prebuilt ReAct agent wires the LLM node and `ToolNode` together automatically.

---

## How It Connects

Tool calling is the mechanism that gives agents the ability to act. The agent loop in LangGraph alternates between calling the LLM (which may produce tool calls) and executing those tool calls (via `ToolNode` or custom dispatch). Understanding tool calling is understanding the actuator side of the LLM-as-brain, tools-as-hands agent architecture.
[[agents|Agents]]

In LangGraph, the `ToolNode` is the node that handles tool dispatch. Its output (a list of `ToolMessage` objects) is added to the messages state via the `add_messages` reducer. The conditional edge from the LLM node inspects whether the LLM's last message contains tool calls  -  if yes, route to `ToolNode`; if no, route to `END`. This is the standard `tools_condition` pattern from `langgraph.prebuilt`.
[[nodes-and-edges|Nodes and Edges]]

Tool execution is async-capable  -  tool functions can be `async def`, and `ToolNode` awaits them. Multiple tool calls in parallel are dispatched with `asyncio.gather()`. A tool that makes an HTTP request (web search, database query) should be async to avoid blocking the event loop. A tool that performs CPU-bound computation (data processing) should use `asyncio.to_thread()` to avoid blocking the event loop thread.
[[async-await|Async and Await]]

---

## Common Misconceptions

Misconception 1: "Tool arguments generated by the LLM are always valid."
Reality: The model can and does hallucinate argument values  -  it might invent a user ID it wasn't given, truncate a required string, or produce a date in the wrong format. The JSON Schema specifies the expected structure, and the API validates that the output conforms to the schema structurally, but it cannot validate semantic correctness. Always validate tool arguments against your actual business rules before executing, especially for tools with side effects (writes, deletes, sends). Treating LLM tool call arguments as trusted user input is a security risk.

Misconception 2: "Giving the LLM more tools always improves performance."
Reality: More tools increase the LLM's decision surface. With 50 registered tools, the model must reason about which of 50 tools is appropriate  -  and it more frequently selects the wrong one, fails to select any, or selects unnecessary ones. Practical guidance: keep the tool set small and focused (under 10 - 15 tools), write highly descriptive tool names and descriptions, and consider dynamically selecting a relevant subset of tools based on the query rather than registering all tools on every call.

---

## Why It Matters in Practice

Tool descriptions are the highest-leverage text you write in an agentic system. The model's decision about when and whether to call a tool is driven almost entirely by the description string. A good description specifies: what the tool does, when it should be used, what it requires as input, and what it returns. A bad description ("calls the search function") leaves the model guessing. Iterating on tool descriptions  -  testing with representative queries and checking whether the model calls tools at the right times  -  is as important as the tool implementation itself.

Structured output extraction is a special case of tool calling. If you want the LLM to always return a specific JSON structure (not optionally call a tool, but always output a structured object), you can register a single "response" tool that represents your desired output schema and set `tool_choice={"type": "function", "function": {"name": "response"}}`. This forces the model to always fill in the schema, effectively using tool calling as a structured output mechanism. This pattern is more reliable than prompting the model to output JSON and parsing the text response.

---

## Interview Angle

Common question forms:
- "How does tool calling work with an LLM?"
- "What happens when an LLM outputs a tool call?"
- "How do you prevent an agent from misusing a tool?"

Answer frame: Tool calling  -  the LLM outputs a JSON tool call (name + arguments) instead of text when it decides a tool is needed. The application (not the model) executes the function and returns a ToolMessage with the result. The model receives the result and either answers or calls more tools. Tools are described via JSON Schema  -  description quality is the primary signal for when the model calls them. Validation: always validate tool arguments before execution. Parallel tool calls: multiple calls in one response, dispatched with asyncio.gather(). LangGraph ToolNode automates dispatch.

---

## Related Notes

- [[agents|Agents]]
- [[llm-basics|LLM Basics]]
- [[langgraph-core|LangGraph Core]]
- [[nodes-and-edges|Nodes and Edges]]
