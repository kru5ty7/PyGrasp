---
title: 01 - LangChain Basics
description: LangChain is a Python framework for building LLM-powered applications — it provides abstractions for chains, prompts, retrievers, and memory that compose into pipelines, with LangChain Expression Language (LCEL) as the primary composition mechanism.
tags: [langchain, lcel, chains, prompts, retrievers, memory, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# LangChain Basics

> LangChain is a Python framework for building LLM-powered applications — it provides abstractions for chains, prompts, retrievers, and memory that compose into pipelines, with LangChain Expression Language (LCEL) as the primary composition mechanism.

---

## Quick Reference

**Core idea:**
- LangChain's core abstraction is the **Runnable** — anything that implements `.invoke()`, `.stream()`, and `.batch()` is a Runnable and can be chained
- **LCEL** (LangChain Expression Language) uses the `|` pipe operator to compose Runnables: `prompt | llm | parser` creates a chain where output flows left to right
- **Prompt templates** (`ChatPromptTemplate`, `PromptTemplate`) format user input and variables into the message structure the LLM expects
- **Output parsers** convert the LLM's raw text response into structured Python objects (Pydantic models, dicts, lists)
- **Retrievers** are Runnables that accept a query string and return a list of `Document` objects — they abstract over vector databases, keyword search, and hybrid search

**Tricky points:**
- LCEL chains are **lazy** — calling `prompt | llm` returns a Runnable, not a result; `.invoke(inputs)` executes it
- **Async execution**: every Runnable has `.ainvoke()`, `.astream()`, and `.abatch()` — use these with FastAPI or any async context to avoid blocking the event loop
- LangChain has a large versioning surface — `langchain`, `langchain-core`, `langchain-community`, and `langchain-openai` are separate packages with different release cycles
- `RunnablePassthrough` passes the input through unchanged — useful in chains that need the original input at a later step while also transforming it
- **Callbacks** (via `config=RunnableConfig(callbacks=[...])`) intercept chain events for logging, tracing, and monitoring — they fire on token generation, chain start/end, retriever calls

---

## What It Is

Think of LangChain as a plumbing kit for LLM applications. Water (data) flows through pipes (chains), gets filtered (retrieved), mixed (combined with context), heated (processed by an LLM), and emerges as a finished product (a structured response). The plumbing kit does not define what the building does — it provides standardized pipes, valves, and fittings that you assemble into the specific flow your application needs. Each fitting (Runnable) has the same interface at the connection points, so any two fittings can be connected regardless of what they do internally.

LangChain's value proposition is that the common patterns in LLM application development — format a prompt, call an LLM, parse the output, retrieve documents, insert them into the prompt — involve enough boilerplate that abstracting them pays off across many projects. Rather than manually managing prompt strings, calling `client.chat.completions.create()`, extracting `response.choices[0].message.content`, and parsing JSON from it, LangChain provides components for each step and a composition mechanism (LCEL) that wires them together with a clean data-flow syntax.

LangChain Expression Language (LCEL) was introduced as the primary API in LangChain v0.1. A chain written in LCEL is a Runnable — it inherits `.invoke()`, `.stream()`, `.batch()`, `.ainvoke()`, `.astream()`, and `.abatch()` automatically. This means a chain that you write for synchronous use also works asynchronously without changes — LCEL generates async implementations from the composition. Streaming is built in: a chain ending in a streaming-capable LLM will stream tokens through to the caller when `.stream()` is invoked.

---

## How It Actually Works

Every LCEL component implements the `Runnable` interface from `langchain_core.runnables`. A `Runnable` must implement `invoke(input, config)` — taking an input (typically a dict) and returning an output. The `|` operator is overloaded on `Runnable` to return a `RunnableSequence`: `a | b` returns a `RunnableSequence([a, b])` whose `invoke` calls `a.invoke(input)` and passes the result to `b.invoke()`. Chaining multiple components — `a | b | c | d` — builds a `RunnableSequence` that executes each component in order, passing the output of each as the input to the next.

A `ChatPromptTemplate` is a Runnable that takes a dict of variables and returns a list of `BaseMessage` objects (the formatted prompt). A chat model (`ChatOpenAI`) is a Runnable that takes a list of `BaseMessage` objects and returns an `AIMessage`. An output parser (e.g., `StrOutputParser`) is a Runnable that takes an `AIMessage` and returns its `.content` string. The chain `ChatPromptTemplate.from_messages([...]) | ChatOpenAI() | StrOutputParser()` is therefore a Runnable from dict inputs to string outputs — each step's input and output types match.

Retrieval chains compose a retriever with a prompt and LLM. The canonical RAG chain in LCEL: `{"context": retriever, "question": RunnablePassthrough()} | rag_prompt | llm | StrOutputParser()`. The dict `{"context": retriever, "question": RunnablePassthrough()}` is a `RunnableParallel` — it calls `retriever.invoke(input)` and `RunnablePassthrough().invoke(input)` concurrently and merges their outputs into a dict with keys `context` and `question`. The parallel execution uses `asyncio.gather()` internally when using async invocation, running both the retrieval and passthrough in parallel.

LangChain's chat model integrations (e.g., `langchain_openai.ChatOpenAI`) wrap the underlying client SDK and add Runnable behavior. They handle retry logic, callbacks, token counting, and format conversion between LangChain's `BaseMessage` types and the API's message format. Switching from OpenAI to Anthropic or a local model is a one-line change — replace `ChatOpenAI()` with `ChatAnthropic()` — because both implement the same `Runnable` interface.

---

## How It Connects

LangChain's `.ainvoke()`, `.astream()`, and `.abatch()` are async implementations of the Runnable interface. They `await` the underlying LLM and retriever calls, which are themselves async HTTP requests. Using async LCEL in a FastAPI route handler allows the route to await the full chain without blocking the event loop, enabling many concurrent LLM requests on the same server.
[[async-await|Async and Await]]

LangChain is the framework layer for building RAG pipelines. Its retrievers abstract over vector databases; its prompt templates handle context injection; its chains wire retrieval to generation. Most practical RAG implementations use LangChain or LlamaIndex to avoid managing the pipeline plumbing manually.
[[rag|RAG]]

LangGraph is built on top of LangChain's Runnable abstraction and extends it with stateful, cyclic graph execution. Understanding LangChain's LCEL and Runnable interface is a prerequisite for understanding how LangGraph adds cycles, state, and conditional branching to LangChain's linear chain model.
[[langgraph-core|LangGraph Core]]

---

## Common Misconceptions

Misconception 1: "LangChain is necessary for building LLM applications."
Reality: LangChain is a convenience layer. Every LangChain component can be replaced with direct API calls, manual prompt string construction, and custom Python functions. LangChain's value is in reducing boilerplate for common patterns (RAG, multi-step chains, tool use) and providing consistent observability hooks (callbacks for LangSmith tracing). For simple applications — a single LLM call with a fixed prompt — LangChain adds complexity without benefit. For multi-step pipelines with retrieval, tool use, and memory, LangChain's abstractions pay off quickly.

Misconception 2: "LCEL chains run steps sequentially."
Reality: `RunnableParallel` (created by passing a dict of Runnables) runs its branches concurrently using `asyncio.gather()` in async mode. A retrieval chain that simultaneously retrieves context and passes through the question uses `RunnableParallel` and the two operations run concurrently. Understanding which parts of a chain are parallel is important for latency optimization — retrieval and any preprocessing that does not depend on retrieval results should run in parallel.

---

## Why It Matters in Practice

LangSmith is the observability companion to LangChain — it captures every chain invocation, every LLM call, every retriever result, and every intermediate step as a trace. Setting `LANGCHAIN_TRACING_V2=true` and `LANGCHAIN_API_KEY` in environment variables enables automatic tracing for any LangChain chain. This is the primary debugging tool for LLM pipelines: when an answer is wrong, the LangSmith trace shows exactly what was retrieved, what prompt was sent, and what the model returned. Building without observability makes LLM pipeline debugging nearly impossible.

LangChain's abstraction over LLM providers is its most durable practical value. A chain written against `ChatOpenAI` can be switched to `ChatAnthropic` or a local Ollama model by changing one object. For applications that need to support multiple models, run evaluation comparisons, or fail over between providers, this abstraction significantly reduces the integration surface area.

---

## Interview Angle

Common question forms:
- "What is LangChain and what problem does it solve?"
- "What is LCEL and how does it work?"
- "How would you build a RAG pipeline in LangChain?"

Answer frame: LangChain is a framework for composing LLM applications from standardized components. LCEL's core is the Runnable interface — `.invoke()`, `.stream()`, `.batch()`, plus async variants. The `|` operator composes Runnables into chains. RAG chain pattern: `{context: retriever, question: passthrough} | rag_prompt | llm | parser` — RunnableParallel runs retrieval and passthrough concurrently, then the prompt formats context and question, the LLM generates, the parser extracts text. LangSmith for observability. ChatOpenAI/ChatAnthropic as drop-in swappable LLM integrations.

---

## Related Notes

- [[llm-basics|LLM Basics]]
- [[rag|RAG]]
- [[langgraph-core|LangGraph Core]]
