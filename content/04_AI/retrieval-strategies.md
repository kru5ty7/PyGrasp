---
title: Retrieval Strategies
description: "Retrieval strategies improve what gets passed to the LLM in RAG — basic vector search can be augmented with query expansion (generate multiple queries), HyDE (generate a hypothetical answer to embed), multi-query retrieval, and parent-document retrieval (embed small, return large)."
tags: [retrieval-strategies, HyDE, query-expansion, multi-query, parent-document, RAG, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Retrieval Strategies

> Retrieval strategies improve what gets passed to the LLM in RAG — basic vector search can be augmented with query expansion (generate multiple queries), HyDE (generate a hypothetical answer to embed), multi-query retrieval, and parent-document retrieval (embed small, return large).

---

## Quick Reference

**Core idea:**
- **Basic retrieval**: embed query → find top-k nearest chunks (sufficient for many use cases)
- **HyDE** (Hypothetical Document Embeddings): ask the LLM to generate a hypothetical answer → embed that → search; the hypothetical answer embeds closer to document space than a bare question
- **Multi-query**: generate 3-5 reformulations of the query → retrieve for each → merge results; covers more of the semantic space
- **Parent-document retrieval**: embed small chunks (precise matching) but return their parent (larger context)
- **Step-back prompting**: ask the model to identify the abstract principle behind the question → search on the principle

**Tricky points:**
- HyDE adds one LLM call before retrieval — adds latency and cost; worthwhile when queries are very different from document style
- Multi-query deduplication: the same chunk may be retrieved by multiple query reformulations — deduplicate before passing to the LLM
- Parent-document retrieval requires storing the parent-child relationship — extra complexity but often worth it for dense technical documents
- Query expansion in BM25 (keyword search) is well-studied; for dense retrieval, the gains are more variable — test on your data
- Long queries embed poorly in some models — truncate to the model's max input length before embedding

---

## What It Is

Basic vector search works well when queries match the style of documents. Problems arise when they don't: user asks "why is the app slow?" but documents describe "latency optimization techniques." The semantic gap between colloquial queries and technical documents causes relevant content to rank lower than it should.

Retrieval strategies address this gap. HyDE bridges it by converting the question to answer-style text (closer to document style). Multi-query covers it by searching multiple angles. Parent-document retrieval ensures the retrieved context is long enough to be useful, even if matched by a small chunk.

---

## How It Actually Works

HyDE (Hypothetical Document Embeddings):
```python
import anthropic

def hyde_retrieve(query: str, top_k: int = 5) -> list[str]:
    client = anthropic.Anthropic()
    
    # Step 1: generate hypothetical answer
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",  # use cheap model for HyDE
        max_tokens=256,
        messages=[{
            "role": "user",
            "content": f"Write a concise technical answer to: {query}\n"
                       "Write as if from a documentation page."
        }]
    )
    hypothetical_answer = response.content[0].text
    
    # Step 2: embed the hypothetical answer instead of the question
    embedding = embed(hypothetical_answer)
    return vector_search(embedding, top_k)
```

Multi-query retrieval:
```python
def multi_query_retrieve(query: str, top_k: int = 5) -> list[str]:
    client = anthropic.Anthropic()
    
    # Generate query variations
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=512,
        system="Generate 4 different ways to search for the same information. One per line.",
        messages=[{"role": "user", "content": query}]
    )
    queries = [query] + response.content[0].text.strip().split("\n")[:4]
    
    # Retrieve for each query, deduplicate
    seen = set()
    results = []
    for q in queries:
        for chunk in vector_search(embed(q), top_k):
            if chunk["id"] not in seen:
                seen.add(chunk["id"])
                results.append(chunk)
    
    return results[:top_k * 2]  # return more for re-ranking
```

Parent-document retrieval:
```python
def parent_retrieve(query: str, top_k: int = 5) -> list[dict]:
    # Small chunks indexed for precision
    small_results = vector_search(embed(query), top_k=top_k)
    
    # Return parent (larger) chunks for context
    parent_chunks = []
    seen_parent_ids = set()
    for result in small_results:
        parent_id = result["metadata"]["parent_id"]
        if parent_id not in seen_parent_ids:
            seen_parent_ids.add(parent_id)
            parent_chunks.append(get_parent_chunk(parent_id))
    
    return parent_chunks
```

---

## How It Connects

Retrieval strategies build on basic RAG retrieval — they improve the quality of what gets passed to the LLM.
[[rag-pipeline|RAG Pipeline]]

Reranking is often applied after retrieval strategies to further sort the candidate chunks.
[[reranking|Reranking]]

---

## Common Misconceptions

Misconception 1: "Complex retrieval strategies always outperform basic vector search."
Reality: On well-chunked documents with queries that match the document style, basic vector search is hard to beat. Complex strategies add latency and cost. Measure the improvement before committing to HyDE or multi-query — the gains are dataset-dependent.

Misconception 2: "More retrieved chunks compensate for poor retrieval quality."
Reality: More chunks add noise. The LLM context window fills with irrelevant content, diluting the signal. Better retrieval of fewer, more relevant chunks outperforms noisy retrieval of many chunks.

---

## Why It Matters in Practice

When to use each strategy:
```
Basic vector search:     Works for most use cases; start here
HyDE:                    Queries very different from document style (e.g., natural language questions vs. technical docs)
Multi-query:             Queries with multiple valid interpretations; ambiguous questions
Parent-document:         Documents with dense, specific content (code, legal, medical)
Step-back prompting:     Questions requiring background knowledge or first principles
```

Always evaluate on a held-out test set (20-50 representative queries with known correct answers) before and after adding retrieval strategies — confirm the improvement is real.

---

## Interview Angle

Common question forms:
- "How do you improve RAG retrieval beyond basic vector search?"
- "What is HyDE?"

Answer frame: Basic vector search embeds the question and finds similar chunks. **HyDE**: generate a hypothetical answer → embed that (closer to document space). **Multi-query**: 3-5 query reformulations → merge results (covers more semantic angles). **Parent-document**: match small chunks, return larger parent for context. All add latency/cost — measure improvement before deploying. Reranking is often applied after retrieval to further filter.

---

## Related Notes

- [[rag-pipeline|RAG Pipeline]]
- [[reranking|Reranking]]
- [[hybrid-search|Hybrid Search]]
- [[rag|RAG]]
