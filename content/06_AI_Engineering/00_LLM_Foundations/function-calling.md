---
title: 06 - Function Calling
description: "Function calling (tool use) lets an LLM request execution of a function — the model outputs a structured tool call with arguments; your code executes the function and returns the result; the model uses the result to generate the final response; enables LLMs to access external data and perform actions."
tags: [function-calling, tool-use, tools, anthropic-api, structured-output, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Function Calling

> Function calling (tool use) lets an LLM request execution of a function — the model outputs a structured tool call with arguments; your code executes the function and returns the result; the model uses the result to generate the final response; enables LLMs to access external data and perform actions.

---

## Quick Reference

**Core idea:**
- Define tools as JSON schemas describing function name, description, and parameters
- Model decides when to call a tool and with what arguments
- You execute the function and return the result to the model in the next message
- Model uses the result in its final response
- `tool_choice` — force the model to use a specific tool or let it decide

**Tricky points:**
- The model does NOT call the function — it generates a structured request; your code calls the actual function
- Multiple tool calls in one response: the model can request several tool calls at once; you must execute all of them and return all results before the model continues
- Tool descriptions drive quality: a poorly written description → wrong tool called at wrong time; treat descriptions like docstrings
- `tool_choice={"type": "tool", "name": "specific_tool"}` — forces the model to always call a specific tool; use for extraction tasks
- Error handling: if a tool fails, return the error message as the tool result — the model can handle it gracefully in its response

---

## What It Is

Function calling bridges the gap between LLM reasoning and real-world data and actions. The model knows how to reason but doesn't have access to current stock prices, your database, or the ability to send an email. With tools, the model can request those operations and incorporate the results into its response.

The paradigm shift: instead of a single API call that returns a response, function calling involves a multi-turn conversation: user → model (tool call request) → your code executes → model (final response using result).

---

## How It Actually Works

Claude tool use with Anthropic SDK:
```python
import anthropic
import json

client = anthropic.Anthropic()

tools = [
    {
        "name": "get_weather",
        "description": "Get the current weather for a location. Returns temperature and conditions.",
        "input_schema": {
            "type": "object",
            "properties": {
                "location": {
                    "type": "string",
                    "description": "City name, e.g. 'London, UK'"
                },
                "unit": {
                    "type": "string",
                    "enum": ["celsius", "fahrenheit"],
                    "description": "Temperature unit"
                }
            },
            "required": ["location"]
        }
    }
]

def get_weather(location: str, unit: str = "celsius") -> dict:
    # Real implementation would call a weather API
    return {"temperature": 18, "conditions": "partly cloudy", "unit": unit}

def run_with_tools(user_message: str) -> str:
    messages = [{"role": "user", "content": user_message}]
    
    while True:
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1024,
            tools=tools,
            messages=messages,
        )
        
        if response.stop_reason == "end_turn":
            # Model is done — extract text response
            return response.content[0].text
        
        if response.stop_reason == "tool_use":
            # Model wants to call tools
            messages.append({"role": "assistant", "content": response.content})
            
            # Execute all requested tool calls
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    if block.name == "get_weather":
                        result = get_weather(**block.input)
                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": block.id,
                            "content": json.dumps(result),
                        })
            
            messages.append({"role": "user", "content": tool_results})
            # Loop: model will now use results to formulate response
```

Forced tool use for structured extraction:
```python
extract_tool = {
    "name": "extract_invoice",
    "description": "Extract structured data from an invoice",
    "input_schema": {
        "type": "object",
        "properties": {
            "invoice_number": {"type": "string"},
            "date": {"type": "string", "format": "date"},
            "total_amount": {"type": "number"},
            "vendor": {"type": "string"},
        },
        "required": ["invoice_number", "date", "total_amount", "vendor"]
    }
}

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=512,
    tools=[extract_tool],
    tool_choice={"type": "tool", "name": "extract_invoice"},  # forced
    messages=[{"role": "user", "content": invoice_text}]
)

# Model always calls extract_invoice → get the structured data:
tool_call = response.content[0]
extracted = tool_call.input  # dict with invoice_number, date, etc.
```

---

## How It Connects

Function calling is the mechanism behind LangChain tools and LangGraph agents — agents decide which tools to call based on the task.
[[tool-calling|Tool Calling]]

Structured output via forced tool use is more reliable than asking the model to format JSON in its text response.
[[structured-output|Structured Output]]

---

## Common Misconceptions

Misconception 1: "The model executes the function."
Reality: The model outputs a structured request with the function name and arguments. Your code executes the function. The model never has direct access to your system — it only sees what you pass back as a tool result.

Misconception 2: "Tool calling requires multiple API calls."
Reality: A response with `stop_reason = "end_turn"` means no tools were called — one API call is sufficient. Tool calling adds round trips only when the model decides to use a tool (which depends on the prompt and available tools).

---

## Why It Matters in Practice

Tools turn LLMs from text transformers into action-taking agents:
- Database queries: tool `search_products(query, filters)` → model gets real data
- Calculations: tool `calculate(expression)` → exact math without hallucination
- External APIs: tool `send_email(to, subject, body)` → model triggers real actions
- Multi-step workflows: model decides which tools to call in what order

The key design principle: tools should be atomic and well-described — each tool does one thing, the description explains when to use it, and the schema is precise.

---

## Interview Angle

Common question forms:
- "How does function calling work with LLMs?"
- "How do you get structured output from Claude?"

Answer frame: Define tools as JSON schemas. Model returns `stop_reason="tool_use"` with tool name + arguments. Your code executes the function and returns the result. Model uses result in final response. Forced tool use (`tool_choice={"type":"tool","name":...}`) guarantees structured output — more reliable than JSON in text. Multiple tool calls can be requested in one response.

---

## Related Notes

- [[llm-basics|How LLMs Work]]
- [[structured-output|Structured Output]]
- [[tool-calling|Tool Calling]]
- [[agents|Agents]]
