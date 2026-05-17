---
title: Context Window
description: "The context window is the total number of tokens an LLM can process at once — it includes both the input (system prompt + conversation history + documents) and the output; tokens beyond the limit are silently truncated or cause an error; larger context = more expensive per call."
tags: [context-window, context-length, tokens, truncation, long-context, layer-4, ai]
status: draft
difficulty: beginner
layer: 4
domain: ai
created: 2026-05-17
---

# Context Window

> The context window is the total number of tokens an LLM can process at once — it includes both the input (system prompt + conversation history + documents) and the output; tokens beyond the limit are silently truncated or cause an error; larger context = more expensive per call.

---

## Quick Reference

**Core idea:**
- Context window = maximum tokens the model sees per call (input + output combined)
- Claude 3.5 Sonnet / Claude 3 Opus: 200,000 token context; GPT-4o: 128,000 tokens
- `max_tokens` parameter controls the maximum output length — the rest of the context is for input
- Retrieval-Augmented Generation (RAG): instead of stuffing everything in context, retrieve the relevant chunks
- "Lost in the middle" problem: models attend less to information in the middle of very long contexts

**Tricky points:**
- Large context ≠ perfect recall — experiments show models are better at using information at the beginning and end of the context; middle sections are less reliably accessed
- Cost scales with token count — a 200k token request costs ~100x more than a 2k token request
- Context reuse: Claude prompt caching can reduce costs for repeated long prefixes (system prompt + static documents)
- Output tokens are typically 3-5x more expensive per token than input tokens
- Conversation history management: in multi-turn chats, history grows with each turn; must implement sliding window or summarization to stay within limits

---

## What It Is

The context window is the LLM's working memory — everything it can "see" at once. Unlike human memory that is persistent and associative, the context window is flat and finite: each API call starts fresh with whatever you put in the `messages` array.

This is the central constraint in LLM application design. You can't give the model an entire codebase, database, or document library in one call — you must choose what to include. RAG exists to work around this limitation: retrieve the relevant pieces and include only those.

---

## How It Actually Works

Context budget management:
```python
CONTEXT_LIMIT = 200_000  # Claude claude-sonnet-4-6
RESERVED_OUTPUT = 4_000   # reserve for response

def build_messages(system: str, history: list, new_message: str, docs: list[str]) -> list:
    """Fit conversation into context window."""
    used = count_tokens(system) + count_tokens(new_message)
    
    # Add documents until budget runs out
    doc_content = []
    for doc in docs:
        doc_tokens = count_tokens(doc)
        if used + doc_tokens < CONTEXT_LIMIT - RESERVED_OUTPUT:
            doc_content.append(doc)
            used += doc_tokens
    
    # Add recent history (most recent first, until budget)
    included_history = []
    for msg in reversed(history):
        msg_tokens = count_tokens(msg["content"])
        if used + msg_tokens < CONTEXT_LIMIT - RESERVED_OUTPUT:
            included_history.insert(0, msg)
            used += msg_tokens
        else:
            break  # drop older messages
    
    return included_history + [{"role": "user", "content": new_message}]
```

Checking context usage after a call:
```python
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=4096,
    messages=messages,
)
print(f"Input tokens: {response.usage.input_tokens}")
print(f"Output tokens: {response.usage.output_tokens}")
print(f"Context used: {response.usage.input_tokens / 200_000:.1%}")
```

Prompt caching for long repeated prefixes:
```python
messages = [
    {
        "role": "user",
        "content": [
            {
                "type": "text",
                "text": long_system_document,
                "cache_control": {"type": "ephemeral"},  # cache this prefix
            },
            {"type": "text", "text": user_question},
        ]
    }
]
```

---

## How It Connects

RAG retrieves relevant chunks to fit in the context window instead of stuffing all documents.
[[rag|RAG]]

Chunking strategies determine how documents are split to maximize what fits in the context.
[[chunking-strategies|Chunking Strategies]]

---

## Common Misconceptions

Misconception 1: "A larger context window means the model uses all of it effectively."
Reality: "Lost in the middle" is well-documented — models recall information at the start and end of long contexts more reliably than information in the middle. For critical information, place it at the beginning (system prompt) or the end (most recent user message).

Misconception 2: "Using the full context window is always the best approach."
Reality: More context = higher latency and higher cost. A well-designed RAG pipeline that retrieves 5 relevant chunks is often more accurate (and much cheaper) than dumping 200 pages into context. Quality of retrieved information > quantity of information.

---

## Why It Matters in Practice

Conversation history management for a chatbot:
```python
MAX_HISTORY_TOKENS = 50_000

def trim_history(messages: list[dict]) -> list[dict]:
    """Keep most recent messages within token budget."""
    total = 0
    trimmed = []
    for msg in reversed(messages):
        tokens = count_tokens(msg["content"])
        if total + tokens > MAX_HISTORY_TOKENS:
            break
        trimmed.insert(0, msg)
        total += tokens
    return trimmed
```

---

## Interview Angle

Common question forms:
- "What is a context window?"
- "How do you handle conversations that exceed the context limit?"

Answer frame: Context window = max tokens per API call (input + output). Exceeding limit = error or truncation. Management strategies: sliding window (drop oldest messages), summarization (compress history), RAG (retrieve relevant chunks instead of stuffing everything). "Lost in the middle" effect — put critical info at start/end. Cost scales linearly with tokens.

---

## Related Notes

- [[tokenization-llm|Tokenization in LLMs]]
- [[rag|RAG]]
- [[chunking-strategies|Chunking Strategies]]
- [[llm-basics|How LLMs Work]]
