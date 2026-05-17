---
title: 03 - ReAct Pattern
description: "ReAct (Reason + Act) is the core agent loop — the LLM alternates between Thought (reasoning about what to do), Action (calling a tool), and Observation (seeing the tool result); this loop repeats until the LLM produces a final answer without a tool call."
tags: [react, reasoning, agent-loop, thought-action-observation, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# ReAct Pattern

> ReAct (Reason + Act) is the core agent loop — the LLM alternates between Thought (reasoning about what to do), Action (calling a tool), and Observation (seeing the tool result); this loop repeats until the LLM produces a final answer without a tool call.

---

## Quick Reference

**Core idea:**
- **ReAct loop**: Thought → Action (tool call) → Observation (tool result) → Thought → ... → Final Answer
- The LLM generates a tool call when it needs external information; the framework executes the tool and feeds results back
- Loop terminates when the LLM generates a response with no tool calls
- `create_react_agent` in LangGraph builds a ReAct agent automatically — wraps the LLM + tools in a standard loop
- In LangChain's `AgentExecutor`, the same pattern is implemented with the legacy `ZERO_SHOT_REACT_DESCRIPTION` format

**Tricky points:**
- "Thought" is implicit in modern LLMs using native tool calling — the LLM doesn't literally output "Thought:" text; its reasoning is internal
- The loop can run indefinitely if the LLM never produces a final answer — set `max_iterations` in `AgentExecutor` or `recursion_limit` in LangGraph
- Observation quality determines next thought quality — poorly formatted tool results confuse the LLM; return clean, structured data from tools
- The LLM might call the same tool multiple times with different arguments — this is normal; the agent is exploring
- Scratchpad = accumulated tool calls and results in the message history; long scratchpads cost tokens

---

## What It Is

ReAct is the original prompting strategy that enables LLMs to use tools effectively. The insight: if you give the LLM space to reason before acting ("Thought: I need to find the current stock price. Action: search_tool(AAPL)"), it makes better tool choices than acting immediately.

Modern LLMs with native tool calling implement this implicitly — the model reasons internally and generates tool call JSON. The framework executes the tool and appends the result as a message, and the loop continues.

---

## How It Actually Works

LangGraph ReAct agent (modern approach):
```python
from langchain_anthropic import ChatAnthropic
from langchain_core.tools import tool
from langgraph.prebuilt import create_react_agent
from langchain_core.messages import HumanMessage

llm = ChatAnthropic(model="claude-sonnet-4-6")

@tool
def get_weather(location: str) -> str:
    """Get current weather for a location."""
    return f"Sunny, 22°C in {location}"

@tool
def search_web(query: str) -> str:
    """Search the web for current information."""
    return f"Search results for: {query}"

tools = [get_weather, search_web]

# create_react_agent builds the full ReAct loop:
# state → llm(tools) → [tool_calls?] → tools → llm → [tool_calls?] → ... → END
agent = create_react_agent(llm, tools)

result = agent.invoke({
    "messages": [HumanMessage(content="What's the weather in Paris?")]
})

# Inspect the full ReAct trace
for message in result["messages"]:
    print(f"{type(message).__name__}: {message.content[:100]}")
```

The ReAct loop step by step:
```python
# The loop implemented manually (for understanding — use create_react_agent in practice)
from langchain_core.messages import AIMessage, ToolMessage

messages = [HumanMessage(content="What's the weather in Paris?")]

while True:
    # Thought step: LLM reasons and optionally calls a tool
    response = llm_with_tools.invoke(messages)
    messages.append(response)
    
    # Check if done
    if not response.tool_calls:
        break  # LLM gave a final answer — loop complete
    
    # Action step: execute tool calls
    for tool_call in response.tool_calls:
        tool_result = tools_by_name[tool_call["name"]].invoke(tool_call["args"])
        # Observation step: append tool result to messages
        messages.append(ToolMessage(
            content=str(tool_result),
            tool_call_id=tool_call["id"],
        ))
    # Loop back — LLM sees the observation and reasons again
```

---

## How It Connects

`create_react_agent` is the LangGraph implementation of the ReAct pattern.
[[agents|Agents]]

Tools are what the ReAct agent calls during the Action step.
[[langchain-tools|Tools in LangChain]]

---

## Common Misconceptions

Misconception 1: "ReAct requires explicit 'Thought:' output in the LLM response."
Reality: The original ReAct paper used text prompting with explicit thought prefixes. Modern LLMs with native tool calling reason implicitly — the "Thought" step is internal, and the output is structured tool call JSON.

Misconception 2: "The ReAct loop always terminates quickly."
Reality: Complex tasks may require 5-10+ tool calls. Each tool call adds latency. Set `recursion_limit` in LangGraph (`graph.compile(recursion_limit=25)`) to prevent runaway agents.

---

## Why It Matters in Practice

Debugging a stuck ReAct agent:
```python
# Stream events to see each step
for event in agent.stream({"messages": [HumanMessage(content="Research X and write a summary")]}):
    for key, value in event.items():
        print(f"--- {key} ---")
        if "messages" in value:
            last = value["messages"][-1]
            if hasattr(last, "tool_calls") and last.tool_calls:
                print(f"Tool call: {last.tool_calls}")
            else:
                print(f"Response: {last.content[:200]}")
```

---

## Interview Angle

Common question forms:
- "How does a ReAct agent work?"
- "What is the ReAct pattern?"

Answer frame: ReAct = Reason + Act. Loop: LLM generates response → if tool calls present, execute tools and append results → LLM sees results and generates next response → repeat until no tool calls → final answer. `create_react_agent` in LangGraph implements this. Key: tool results (Observations) are fed back as messages; LLM sees the full history each iteration.

---

## Related Notes

- [[agents|Agents]]
- [[langchain-tools|Tools in LangChain]]
- [[tool-calling|Tool Calling]]
- [[langgraph-core|LangGraph Core]]
