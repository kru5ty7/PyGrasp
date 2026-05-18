---
title: 04 - Memory in LangChain
description: "LangChain memory persists conversation history across chain invocations  -  `ConversationBufferMemory` keeps all messages; `ConversationSummaryMemory` summarizes old messages to save tokens; in LCEL, memory is explicit: load history -> pass to prompt -> append new exchange to history."
tags: [langchain, memory, conversation-history, ConversationBufferMemory, LCEL, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Memory in LangChain

> LangChain memory persists conversation history across chain invocations  -  `ConversationBufferMemory` keeps all messages; `ConversationSummaryMemory` summarizes old messages to save tokens; in LCEL, memory is explicit: load history -> pass to prompt -> append new exchange to history.

---

## Quick Reference

**Core idea:**
- **In-memory**: `ConversationBufferMemory` stores all messages in a Python list (lost on restart)
- **Summary memory**: `ConversationSummaryMemory` uses LLM to compress old messages  -  saves tokens, loses detail
- **LCEL pattern**: manage history explicitly  -  load from store -> inject into prompt -> save new messages after response
- `RunnableWithMessageHistory`  -  LCEL wrapper that handles history load/save automatically
- Per-user memory: `session_id` scopes memory to a specific conversation/user

**Tricky points:**
- LangChain memory is NOT persistent by default  -  `ConversationBufferMemory` is in-memory; restart = lost history; use `RedisChatMessageHistory` or similar for persistence
- Growing history = growing token count  -  without pruning or summarization, long conversations hit the context limit
- `ConversationSummaryMemory` introduces LLM calls for summarization  -  adds latency and cost; only worthwhile for very long conversations
- In LCEL, the `session_id` must be stable across requests for the same user/session  -  use a UUID generated at conversation start
- Thread safety: Python dict for session storage is not thread-safe for concurrent requests; use Redis or a database for production

---

## What It Is

LLMs are stateless  -  each API call starts fresh. Memory is what makes a chatbot feel like a conversation rather than isolated Q&A. LangChain provides memory components that load previous messages before each LLM call and save new messages after.

The LCEL-native approach is explicit: you manage the history store, load it at the start of each chain invocation, and save the new messages after. `RunnableWithMessageHistory` wraps this pattern into a reusable component.

---

## How It Actually Works

LCEL with explicit history management:
```python
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.messages import HumanMessage, AIMessage

llm = ChatAnthropic(model="claude-sonnet-4-6")

prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    MessagesPlaceholder(variable_name="history"),
    ("human", "{question}"),
])

chain = prompt | llm

# In-memory store (per session_id):
history_store: dict[str, list] = {}

def chat(session_id: str, question: str) -> str:
    history = history_store.get(session_id, [])
    
    response = chain.invoke({
        "history": history,
        "question": question,
    })
    
    # Update history
    history_store[session_id] = history + [
        HumanMessage(content=question),
        AIMessage(content=response.content),
    ]
    
    return response.content
```

`RunnableWithMessageHistory` (automatic history management):
```python
from langchain_core.runnables.history import RunnableWithMessageHistory
from langchain_community.chat_message_histories import ChatMessageHistory

session_store: dict[str, ChatMessageHistory] = {}

def get_session_history(session_id: str) -> ChatMessageHistory:
    if session_id not in session_store:
        session_store[session_id] = ChatMessageHistory()
    return session_store[session_id]

chain = prompt | llm

chain_with_history = RunnableWithMessageHistory(
    chain,
    get_session_history,
    input_messages_key="question",
    history_messages_key="history",
)

# Invoke with session ID:
response = chain_with_history.invoke(
    {"question": "What is the capital of France?"},
    config={"configurable": {"session_id": "user-123"}},
)
```

Redis persistence:
```python
from langchain_community.chat_message_histories import RedisChatMessageHistory

def get_session_history(session_id: str) -> RedisChatMessageHistory:
    return RedisChatMessageHistory(session_id, url="redis://localhost:6379")
```

---

## How It Connects

Memory is injected into chains via `MessagesPlaceholder` in the prompt template  -  the chain structure remains the same; memory just adds the history to the input.
[[chains|Chains]]

Long conversations use the context window  -  understanding context limits is required to reason about when memory must be pruned or summarized.
[[context-window|Context Window]]

---

## Common Misconceptions

Misconception 1: "LangChain handles memory persistence automatically."
Reality: Default memory stores are in-process Python objects  -  lost on restart. For persistent memory, explicitly use `RedisChatMessageHistory`, `PostgresChatMessageHistory`, or a custom store backed by a database.

Misconception 2: "Summary memory is always better for long conversations."
Reality: Summary memory loses detail  -  important details from early in the conversation may be compressed out. For many use cases, a sliding window (keep last N messages) is simpler and more predictable than summarization.

---

## Why It Matters in Practice

Token budget management for long conversations:
```python
MAX_HISTORY_MESSAGES = 20

def get_trimmed_history(session_id: str) -> list:
    full_history = history_store.get(session_id, [])
    return full_history[-MAX_HISTORY_MESSAGES:]  # keep last 20 messages
```

For production chatbots: store full history in a database for audit/replay; pass only the last N messages to the LLM for token efficiency.

---

## Interview Angle

Common question forms:
- "How does conversation memory work in LangChain?"
- "How do you persist conversation history?"

Answer frame: LLMs are stateless  -  memory is added explicitly by loading history before each call and saving after. LangChain provides `ConversationBufferMemory` (all messages, in-memory), `ConversationSummaryMemory` (summarized, saves tokens). In LCEL: `MessagesPlaceholder` in the prompt + explicit history management. `RunnableWithMessageHistory` automates load/save. For persistence: `RedisChatMessageHistory` or database-backed store.

---

## Related Notes

- [[chains|Chains]]
- [[langchain-basics|LangChain Basics]]
- [[context-window|Context Window]]
- [[lcel|LangChain Expression Language]]
