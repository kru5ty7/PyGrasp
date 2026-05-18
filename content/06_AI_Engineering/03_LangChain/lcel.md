---
title: 03 - LangChain Expression Language
description: "LCEL (LangChain Expression Language) is the composable pipeline syntax for LangChain  -  the `|` operator chains `Runnable` objects; every component (prompt, LLM, parser, retriever) implements `Runnable`; chains support sync, async, streaming, and batch invocation uniformly."
tags: [langchain, LCEL, runnable, pipeline, RunnableParallel, RunnablePassthrough, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# LangChain Expression Language

> LCEL (LangChain Expression Language) is the composable pipeline syntax for LangChain  -  the `|` operator chains `Runnable` objects; every component (prompt, LLM, parser, retriever) implements `Runnable`; chains support sync, async, streaming, and batch invocation uniformly.

---

## Quick Reference

**Core idea:**
- `chain = a | b | c`  -  `|` overloads `Runnable.__or__` to produce a new `Runnable`; not Python bitwise OR
- Every LangChain component is `Runnable`: prompts, LLMs, parsers, retrievers, tools
- `chain.invoke(input)`  -  sync; `await chain.ainvoke(input)`  -  async; `chain.stream(input)`  -  token stream; `chain.batch([...])`  -  parallel list
- `RunnablePassthrough()`  -  passes its input unchanged; used to preserve values across branches
- `RunnableParallel(a=..., b=...)`  -  runs branches in parallel, returns `{"a": ..., "b": ...}`
- `RunnableLambda(fn)`  -  wraps any Python callable as a `Runnable`

**Tricky points:**
- LCEL does not validate input/output types at definition time  -  type mismatches surface at runtime
- `chain.stream()` only streams the final component's output; intermediate components run to completion first
- `.bind(stop=["\n"])`  -  bind fixed kwargs to a `Runnable` (e.g., stop sequences for an LLM); does not invoke it
- `.with_config(run_name="MyChain")`  -  adds metadata (name, tags, callbacks) without changing behavior
- `.with_retry(stop_after_attempt=3)`  -  wraps a `Runnable` with automatic retry; useful for flaky API calls
- `RunnableParallel` keys become the output dict keys  -  key names matter; they must match downstream input variable names

---

## What It Is

LCEL replaced the older class-based chains (`LLMChain`, `SequentialChain`) with a declarative piping syntax. The `|` operator is the core idea: it composes two `Runnable` objects into a new one that runs them sequentially  -  the output of the left becomes the input of the right.

The key design principle: every LangChain component implements the same `Runnable` interface, so they all compose identically. A retriever, an LLM, a custom Python function wrapped in `RunnableLambda`  -  all behave the same in a chain.

---

## How It Actually Works

Core invocation methods:
```python
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser

llm = ChatAnthropic(model="claude-sonnet-4-6")
prompt = ChatPromptTemplate.from_template("Translate to French: {text}")
parser = StrOutputParser()

chain = prompt | llm | parser

# Sync
result = chain.invoke({"text": "Hello world"})

# Async
result = await chain.ainvoke({"text": "Hello world"})

# Streaming  -  yields string chunks as they arrive
for chunk in chain.stream({"text": "Hello world"}):
    print(chunk, end="", flush=True)

# Batch  -  parallel execution of multiple inputs
results = chain.batch([{"text": "Hello"}, {"text": "Goodbye"}])
```

`RunnableParallel`  -  parallel branches merged into a dict:
```python
from langchain_core.runnables import RunnableParallel, RunnablePassthrough

# Run two branches in parallel; merge outputs
parallel = RunnableParallel(
    original=RunnablePassthrough(),           # pass input through unchanged
    translated=prompt | llm | parser,        # translate it
)

result = parallel.invoke({"text": "Hello"})
# {"original": {"text": "Hello"}, "translated": "Bonjour"}
```

`RunnableLambda`  -  wrap a custom function:
```python
from langchain_core.runnables import RunnableLambda

def add_metadata(text: str) -> dict:
    return {"response": text, "word_count": len(text.split())}

chain = prompt | llm | parser | RunnableLambda(add_metadata)
result = chain.invoke({"text": "Hello"})
# {"response": "Bonjour", "word_count": 1}
```

`.bind()`  -  fix kwargs on a Runnable:
```python
# Bind stop sequences  -  useful for LLMs that need consistent stop tokens
llm_with_stop = llm.bind(stop=["Human:", "Assistant:"])

chain = prompt | llm_with_stop | parser
```

`.with_retry()`  -  automatic retry on failure:
```python
from langchain_core.runnables import RunnableRetry

resilient_llm = llm.with_retry(
    stop_after_attempt=3,
    wait_exponential_jitter=True,
)

chain = prompt | resilient_llm | parser
```

Composing chains as sub-chains:
```python
# A chain can be a component in another chain
summary_chain = (
    ChatPromptTemplate.from_template("Summarize: {text}") | llm | parser
)

qa_chain = (
    ChatPromptTemplate.from_template("Answer based on this summary:\n{summary}\n\nQuestion: {question}")
    | llm | parser
)

# Compose: summarize first, then answer
full_chain = (
    RunnableParallel(
        summary=summary_chain,
        question=RunnablePassthrough() | RunnableLambda(lambda x: x["question"]),
    )
    | qa_chain
)
```

---

## How It Connects

LCEL is the syntax used to build all LangChain chains  -  understanding it unlocks the full composability of the framework.
[[chains|Chains]]

Memory, retrievers, and tools all slot into LCEL chains as `Runnable` components.
[[langchain-memory|Memory in LangChain]]
[[langchain-retrievers|Retrievers]]

---

## Common Misconceptions

Misconception 1: "`chain = a | b` executes immediately."
Reality: `|` only constructs a new `Runnable`  -  nothing executes until `.invoke()`, `.ainvoke()`, `.stream()`, or `.batch()` is called.

Misconception 2: "`RunnableParallel` requires async."
Reality: `RunnableParallel` uses threads under the hood for the sync `.invoke()` call  -  it runs branches concurrently in a thread pool. For true async parallelism, use `.ainvoke()`.

---

## Why It Matters in Practice

The `RunnableParallel` + `RunnablePassthrough` pattern is the standard way to build RAG chains:
```python
from langchain_core.runnables import RunnablePassthrough

def format_docs(docs):
    return "\n\n".join(doc.page_content for doc in docs)

rag_chain = (
    RunnableParallel(
        context=retriever | RunnableLambda(format_docs),
        question=RunnablePassthrough(),
    )
    | ChatPromptTemplate.from_template(
        "Answer based on context:\n{context}\n\nQuestion: {question}"
    )
    | llm
    | StrOutputParser()
)

answer = rag_chain.invoke("What is RAG?")
```

The parallel step retrieves context while passing the original question through  -  both are available in the prompt template.

---

## Interview Angle

Common question forms:
- "What is LCEL in LangChain?"
- "How do you compose LangChain components?"

Answer frame: LCEL = composable pipeline syntax using `|` operator on `Runnable` objects. Every LangChain component is `Runnable`. Chains support `invoke` (sync), `ainvoke` (async), `stream` (tokens), `batch` (parallel list). `RunnablePassthrough` preserves input; `RunnableParallel` runs branches simultaneously; `RunnableLambda` wraps any Python function. `.bind()` fixes kwargs. Chains are themselves `Runnable`  -  nested composition is natural.

---

## Related Notes

- [[chains|Chains]]
- [[langchain-memory|Memory in LangChain]]
- [[langchain-retrievers|Retrievers]]
- [[langchain-tools|Tools in LangChain]]
