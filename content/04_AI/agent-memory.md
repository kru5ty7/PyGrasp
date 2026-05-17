---
title: Agent Memory
description: "Agent memory has four types — in-context (messages in the prompt), external (vector store / database), episodic (past interaction summaries), and semantic (facts about the world or user); LangGraph checkpointing handles in-context persistence; external memory requires explicit retrieval."
tags: [agent-memory, in-context, external-memory, episodic-memory, semantic-memory, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Agent Memory

> Agent memory has four types — in-context (messages in the prompt), external (vector store / database), episodic (past interaction summaries), and semantic (facts about the world or user); LangGraph checkpointing handles in-context persistence; external memory requires explicit retrieval.

---

## Quick Reference

**Core idea:**
- **In-context memory**: the message history passed to the LLM — limited by context window; lost without checkpointing
- **External memory**: facts stored in a vector store or database; retrieved on demand via a retrieval step
- **Episodic memory**: summaries of past sessions stored externally — agent retrieves relevant past experiences
- **Semantic memory**: persistent facts about the user or domain — "user prefers concise responses", "project deadline is Friday"
- LangGraph checkpointing = in-context persistence across turns; external memory = anything beyond the context window

**Tricky points:**
- In-context memory grows every turn — without pruning, long conversations eventually hit the context limit
- External memory retrieval adds latency — every turn now requires a vector search before the LLM call
- Semantic memory requires explicit update logic — the agent must decide when to write new facts
- Memory retrieval quality determines agent quality — if the agent retrieves irrelevant memories, it's worse than no memory
- Different memory types serve different timescales: in-context (current session), external (across sessions, weeks/months)

---

## What It Is

LLMs are stateless — they don't remember anything between API calls. Memory in agents is entirely constructed by the framework: the current context window is in-context memory; anything that persists beyond it requires external storage.

The four memory types map to what needs to be remembered:
- **In-context**: what was said this session (conversation history)
- **External/Episodic**: what happened in past sessions (retrieved by similarity)
- **Semantic**: persistent facts that should always be available (user profile, project context)

---

## How It Actually Works

In-context memory via checkpointing:
```python
from langgraph.checkpoint.memory import MemorySaver
from langgraph.prebuilt import create_react_agent
from langchain_core.messages import HumanMessage

agent = create_react_agent(llm, tools)
checkpointer = MemorySaver()
agent_with_memory = agent  # create_react_agent doesn't accept checkpointer directly

# Use StateGraph for full control with checkpointing:
graph = StateGraph(MessagesState)
# ... add nodes ...
app = graph.compile(checkpointer=MemorySaver())

config = {"configurable": {"thread_id": "user-123"}}
```

External semantic memory (persistent facts):
```python
from langchain_chroma import Chroma
from langchain_huggingface import HuggingFaceEmbeddings

embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
memory_store = Chroma(persist_directory="./agent_memory", embedding_function=embeddings)

def save_memory(fact: str, user_id: str):
    """Store a fact in external memory."""
    memory_store.add_texts(
        texts=[fact],
        metadatas=[{"user_id": user_id, "timestamp": datetime.now().isoformat()}],
    )

def retrieve_memories(query: str, user_id: str, k: int = 3) -> list[str]:
    """Retrieve relevant memories for the current context."""
    results = memory_store.similarity_search(
        query,
        k=k,
        filter={"user_id": user_id},
    )
    return [doc.page_content for doc in results]

# In the agent node:
def agent_node_with_memory(state: MessagesState) -> dict:
    user_query = state["messages"][-1].content
    
    # Retrieve relevant memories
    memories = retrieve_memories(user_query, user_id="user-123")
    memory_context = "\n".join(f"- {m}" for m in memories)
    
    system_message = SystemMessage(
        content=f"You are a helpful assistant.\n\nRelevant context:\n{memory_context}"
    )
    
    response = llm.invoke([system_message] + state["messages"])
    return {"messages": [response]}
```

In-context window management (sliding window):
```python
MAX_MESSAGES = 20

def trim_messages(state: MessagesState) -> dict:
    """Keep only the most recent messages to manage context length."""
    messages = state["messages"]
    if len(messages) > MAX_MESSAGES:
        # Always keep system message (index 0) + last N messages
        trimmed = [messages[0]] + messages[-MAX_MESSAGES:]
        return {"messages": trimmed}
    return {}
```

---

## How It Connects

Checkpointing implements in-context memory persistence across invocations.
[[checkpointing|Checkpointing]]

Vector databases are the backing store for external memory retrieval.
[[vector-databases|Vector Databases]]

---

## Common Misconceptions

Misconception 1: "Longer context = better memory."
Reality: Very long contexts increase cost, latency, and the lost-in-the-middle problem — the LLM pays less attention to information in the middle of a long context. Summarization or retrieval-based memory often outperforms raw context extension.

Misconception 2: "Checkpointing is the same as memory."
Reality: Checkpointing persists conversation history for a session. Memory in the broader sense includes external knowledge the agent can look up — retrieval from a vector store, database queries, or any external source.

---

## Why It Matters in Practice

Design questions for agent memory:
1. **What needs to persist beyond a session?** → External memory
2. **How much history fits in context?** → Trimming or summarization strategy
3. **Should the agent learn new facts?** → Write memory tool + explicit update logic
4. **Are memories user-specific?** → Metadata filtering on retrieval

---

## Interview Angle

Common question forms:
- "How does an agent remember things?"
- "What are the types of memory in an agent system?"

Answer frame: Four types — in-context (message history), external (vector store retrieval), episodic (past session summaries), semantic (persistent facts). In-context: LangGraph checkpointing across turns. External: vector store + retrieval step before LLM call. Key tradeoff: in-context = fast, limited by window; external = unlimited, requires retrieval latency.

---

## Related Notes

- [[checkpointing|Checkpointing]]
- [[langchain-memory|Memory in LangChain]]
- [[vector-databases|Vector Databases]]
- [[agents|Agents]]
