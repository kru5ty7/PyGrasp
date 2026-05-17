---
title: 02 - Chains
description: "In LangChain, a chain connects components sequentially — LCEL (LangChain Expression Language) uses `|` to pipe components; classic chains like `LLMChain`, `SequentialChain` are legacy; LCEL is the modern approach; a chain takes an input dict and returns an output dict."
tags: [langchain, chains, LCEL, LLMChain, SequentialChain, pipeline, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Chains

> In LangChain, a chain connects components sequentially — LCEL (LangChain Expression Language) uses `|` to pipe components; classic chains like `LLMChain`, `SequentialChain` are legacy; LCEL is the modern approach; a chain takes an input dict and returns an output dict.

---

## Quick Reference

**Core idea:**
- **Chain**: a sequence of processing steps — prompt → LLM → output parser
- **LCEL**: `chain = prompt | llm | parser` — pipe operator; components implement `Runnable` interface
- `chain.invoke({"key": "value"})` — run chain synchronously
- `await chain.ainvoke(...)` — async invocation
- `chain.stream(...)` — streaming output; returns iterator of tokens

**Tricky points:**
- LCEL is the modern API (LangChain 0.3+); `LLMChain`, `SequentialChain` are legacy but still work — prefer LCEL for new code
- LCEL `|` operator requires both sides to implement `Runnable` — LangChain components (prompts, LLMs, parsers) all implement it; custom functions must be wrapped with `RunnableLambda`
- Input/output types: LCEL chains pass the output of each step as input to the next; type compatibility is not checked at definition time — errors surface at runtime
- `RunnablePassthrough()` passes input through unchanged — used to preserve earlier values in a chain
- Parallel execution with `RunnableParallel`: runs multiple branches simultaneously

---

## What It Is

A chain is LangChain's abstraction for combining components into a pipeline. The classic use case: `PromptTemplate | ChatModel | StrOutputParser` — takes a user input, formats it into a prompt, passes to the LLM, and extracts the text response.

LCEL (LangChain Expression Language) is the declarative piping syntax that replaced the older class-based chains. It's cleaner, supports async/streaming natively, and is composable — chains can be nested as components in other chains.

---

## How It Actually Works

Basic LCEL chain:
```python
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser

llm = ChatAnthropic(model="claude-sonnet-4-6")
prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    ("human", "{question}"),
])
parser = StrOutputParser()

chain = prompt | llm | parser

result = chain.invoke({"question": "What is the capital of France?"})
print(result)  # "Paris"

# Async:
result = await chain.ainvoke({"question": "What is the capital of France?"})

# Streaming:
for chunk in chain.stream({"question": "Tell me a joke."}):
    print(chunk, end="", flush=True)
```

Preserving intermediate values with `RunnablePassthrough`:
```python
from langchain_core.runnables import RunnablePassthrough, RunnableParallel

chain = RunnableParallel(
    question=RunnablePassthrough(),  # pass question through unchanged
    answer=prompt | llm | parser,   # also compute the answer
)

result = chain.invoke({"question": "What is 2+2?"})
# {"question": {"question": "What is 2+2?"}, "answer": "4"}
```

Custom function in chain:
```python
from langchain_core.runnables import RunnableLambda

def format_result(text: str) -> dict:
    return {"response": text, "length": len(text)}

chain = prompt | llm | parser | RunnableLambda(format_result)
```

Sequential chain with multiple LLM calls:
```python
translate_chain = (
    ChatPromptTemplate.from_template("Translate to French: {text}") | llm | parser
)

summarize_chain = (
    ChatPromptTemplate.from_template("Summarize: {french_text}") | llm | parser
)

# Combine: translate then summarize
full_chain = (
    translate_chain
    | (lambda french: {"french_text": french})
    | summarize_chain
)
```

---

## How It Connects

LCEL is the syntax for building chains — understanding the LCEL expression language gives the full power of composition.
[[lcel|LangChain Expression Language]]

Memory components are added to chains to provide conversation history.
[[langchain-memory|Memory in LangChain]]

---

## Common Misconceptions

Misconception 1: "LCEL `|` is the same as Python's `|` bitwise OR."
Reality: LangChain overloads `__or__` on `Runnable` objects to create a pipeline — it has nothing to do with bitwise OR. The result is a new `Runnable` that, when invoked, runs the components sequentially.

Misconception 2: "LangChain chains require the LangChain LLM wrappers."
Reality: Any callable that takes the chain's output as input can be part of an LCEL chain via `RunnableLambda`. You can mix LangChain components with custom Python functions seamlessly.

---

## Why It Matters in Practice

RAG chain using LCEL:
```python
from langchain_core.runnables import RunnablePassthrough

rag_chain = (
    {
        "context": retriever | format_docs,
        "question": RunnablePassthrough(),
    }
    | ChatPromptTemplate.from_template(
        "Answer based on context:\n{context}\n\nQuestion: {question}"
    )
    | llm
    | StrOutputParser()
)

answer = rag_chain.invoke("What is FastAPI?")
```

The `|` pipeline cleanly expresses: retrieve context + pass question → format prompt → call LLM → parse output.

---

## Interview Angle

Common question forms:
- "What is an LCEL chain in LangChain?"
- "How do you connect components in LangChain?"

Answer frame: LCEL: `chain = component1 | component2 | component3` using `|` operator on `Runnable` objects. Each component receives the previous output. Invoke with `.invoke()` (sync), `.ainvoke()` (async), `.stream()` (streaming). `RunnablePassthrough()` preserves input through a branch. `RunnableParallel` runs branches in parallel. Modern replacement for legacy `LLMChain`.

---

## Related Notes

- [[langchain-basics|LangChain Basics]]
- [[lcel|LangChain Expression Language]]
- [[langchain-memory|Memory in LangChain]]
- [[langchain-tools|Tools in LangChain]]
