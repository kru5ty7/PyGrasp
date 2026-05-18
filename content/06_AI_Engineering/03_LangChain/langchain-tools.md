---
title: 05 - Tools in LangChain
description: "LangChain tools are callables the LLM can invoke  -  defined with `@tool` decorator or `StructuredTool`; the tool name, description, and argument schema guide when the LLM calls them; used in agents for web search, database queries, and custom operations."
tags: [langchain, tools, tool-decorator, StructuredTool, agent-tools, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Tools in LangChain

> LangChain tools are callables the LLM can invoke  -  defined with `@tool` decorator or `StructuredTool`; the tool name, description, and argument schema guide when the LLM calls them; used in agents for web search, database queries, and custom operations.

---

## Quick Reference

**Core idea:**
- `@tool` decorator on a function -> LangChain tool with name, description (from docstring), and input schema (from type annotations)
- `StructuredTool.from_function(func, ...)`  -  more control over name, description, and schema
- Tool description is critical  -  the LLM decides when to call a tool based on its description; vague descriptions = wrong tool calls
- `tool.invoke({"arg": "value"})`  -  call the tool directly (testing)
- Community tools: `DuckDuckGoSearchRun`, `WikipediaQueryRun`, `PythonREPLTool`  -  pre-built tools from `langchain-community`

**Tricky points:**
- Tool name must be unique within a tool list  -  duplicate names cause the LLM to call the wrong tool or fail
- Tool schema is inferred from type annotations  -  missing type annotations generate an `Any`-typed schema, which is less informative for the LLM
- Error handling: if a tool raises an exception, the exception propagates to the agent  -  use `handle_tool_error=True` or wrap the tool body in try/except to return error messages instead
- Async tools: define the function as `async def`  -  LangChain handles async tools in async agent loops
- The LLM infers which tool to call from the description alone  -  test that the description correctly guides tool selection

---

## What It Is

Tools are the mechanism by which LLM agents interact with the outside world. An agent that can only reason in its context window is limited to its training data. With tools, it can search the web, query a database, run code, or call any API.

The tool abstraction converts any Python function into something the LLM can "call"  -  the LLM generates the function name and arguments, your code executes the function, and the result is fed back to the LLM.

---

## How It Actually Works

`@tool` decorator:
```python
from langchain_core.tools import tool
from typing import Optional

@tool
def get_stock_price(ticker: str) -> dict:
    """Get the current stock price for a given ticker symbol.
    
    Args:
        ticker: Stock ticker symbol (e.g., 'AAPL', 'MSFT')
    """
    # Real implementation would call a financial API
    return {"ticker": ticker, "price": 150.42, "currency": "USD"}

@tool
def search_database(query: str, limit: int = 5) -> list[dict]:
    """Search the product database for items matching the query.
    
    Args:
        query: Natural language search query
        limit: Maximum number of results to return (default: 5)
    """
    return db.search(query, limit=limit)
```

`StructuredTool` with Pydantic schema:
```python
from langchain_core.tools import StructuredTool
from pydantic import BaseModel

class WeatherInput(BaseModel):
    location: str
    unit: str = "celsius"

def get_weather(location: str, unit: str = "celsius") -> dict:
    return {"location": location, "temp": 20, "unit": unit}

weather_tool = StructuredTool.from_function(
    func=get_weather,
    name="get_weather",
    description="Get current weather for a location. Use for weather-related questions.",
    args_schema=WeatherInput,
)
```

Using tools in an agent:
```python
from langchain_anthropic import ChatAnthropic
from langchain.agents import create_tool_calling_agent, AgentExecutor
from langchain_core.prompts import ChatPromptTemplate

llm = ChatAnthropic(model="claude-sonnet-4-6")
tools = [get_stock_price, search_database, weather_tool]

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant with access to tools."),
    ("human", "{input}"),
    ("placeholder", "{agent_scratchpad}"),
])

agent = create_tool_calling_agent(llm, tools, prompt)
executor = AgentExecutor(agent=agent, tools=tools, verbose=True)

result = executor.invoke({"input": "What's the price of Apple stock?"})
```

---

## How It Connects

LangChain tools are used by agents  -  the agent decides when to call which tool and assembles the final response.
[[agents|Agents]]

Tools in LangGraph are similar but more composable  -  LangGraph nodes can directly call tools without the agent executor pattern.
[[tool-calling|Tool Calling]]

---

## Common Misconceptions

Misconception 1: "The tool description doesn't matter  -  the LLM figures it out."
Reality: The tool description is the primary signal the LLM uses to decide whether to call a tool. A vague description like `do_stuff()` causes unpredictable tool selection. Write descriptions as if explaining to a developer when to use the tool: specific, clear, with examples of valid inputs.

Misconception 2: "Tools always execute when the LLM generates a tool call."
Reality: In LangChain, the `AgentExecutor` or LangGraph node is responsible for actually calling `tool.invoke()`. The LLM generates a *request* to call a tool; your code executes it.

---

## Why It Matters in Practice

Tool design principles:
```python
# BAD  -  vague description, hard to type
@tool
def query(q):
    """Query something."""
    ...

# GOOD  -  specific, typed, informative description
@tool
def search_knowledge_base(query: str, category: Optional[str] = None) -> list[str]:
    """Search the internal knowledge base for information.
    
    Use this for questions about company policies, product specs, and internal procedures.
    
    Args:
        query: Natural language search query
        category: Optional filter ('policy', 'product', 'procedure')
    
    Returns: List of relevant text passages
    """
    ...
```

Each tool should do one thing. A `do_everything` tool with many optional parameters is harder for the LLM to use correctly than 3 focused tools.

---

## Interview Angle

Common question forms:
- "How do you create a tool in LangChain?"
- "How does the LLM know when to use a tool?"

Answer frame: `@tool` decorator on a Python function  -  name from function name, description from docstring, schema from type annotations. Tool description tells the LLM when to call it. `StructuredTool.from_function()` for explicit schema. Tools are passed to `AgentExecutor` or LangGraph agent node. The LLM generates tool call requests; your code executes them. Good descriptions are the single biggest factor in tool call quality.

---

## Related Notes

- [[langchain-basics|LangChain Basics]]
- [[agents|Agents]]
- [[tool-calling|Tool Calling]]
- [[function-calling|Function Calling]]
