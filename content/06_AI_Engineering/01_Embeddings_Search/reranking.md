---
title: 06 - Reranking
description: "Reranking re-orders retrieved chunks by relevance before passing them to the LLM  -  a cross-encoder model scores each (query, chunk) pair more accurately than the bi-encoder used for retrieval; Cohere Rerank and `cross-encoder/ms-marco-MiniLM` are common; improves precision at the cost of extra latency."
tags: [reranking, cross-encoder, bi-encoder, Cohere-Rerank, RAG, precision, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Reranking

> Reranking re-orders retrieved chunks by relevance before passing them to the LLM  -  a cross-encoder model scores each (query, chunk) pair more accurately than the bi-encoder used for retrieval; Cohere Rerank and `cross-encoder/ms-marco-MiniLM` are common; improves precision at the cost of extra latency.

---

## Quick Reference

**Core idea:**
- **Two-stage retrieval**: vector search (fast, approximate) -> reranker (slow, precise)
- Retrieve more candidates (top-20) -> rerank -> keep top-5 for the LLM prompt
- **Bi-encoder** (used in retrieval): encodes query and document separately; fast but less accurate
- **Cross-encoder** (used in reranking): takes `[query, document]` as pair; more accurate but can't be pre-computed
- Cohere Rerank API: managed reranking; `cohere.rerank(query, documents, top_n=5)`

**Tricky points:**
- Cross-encoders are slower than bi-encoders  -  running a cross-encoder on 1000 documents per query is too slow; use it on the top-20-50 retrieved by the bi-encoder
- Reranking improves precision but not recall  -  if a relevant document wasn't retrieved in the first stage, reranking can't recover it
- The reranker's relevance score and the vector similarity score are different scales  -  don't mix them; trust the reranker's ordering
- LLM-as-reranker: ask an LLM to rate relevance for each chunk  -  expensive but potentially more accurate for domain-specific tasks
- Reranking adds ~100-500ms latency  -  evaluate if the quality gain justifies it for your SLA

---

## What It Is

Vector search (bi-encoder) retrieves documents by comparing query and document embeddings independently  -  fast because document embeddings are pre-computed. But this misses subtle relevance signals that require joint reasoning over query and document together.

A cross-encoder takes `[query, document]` as a pair and produces a relevance score. It can reason about how the document specifically answers the query, not just whether their topics are similar. This produces better rankings but requires running inference on every (query, document) pair at query time  -  expensive for large candidate sets.

The two-stage approach solves this: use fast vector search to get 20-50 candidates, then use the slower cross-encoder to re-score and select the best 5.

---

## How It Actually Works

Using `sentence-transformers` cross-encoder:
```python
from sentence_transformers import CrossEncoder

reranker = CrossEncoder("cross-encoder/ms-marco-MiniLM-L-6-v2")

def rerank(query: str, candidates: list[dict], top_k: int = 5) -> list[dict]:
    """
    candidates: list of {"content": "...", "source": "..."}
    Returns top-k reranked candidates.
    """
    pairs = [(query, c["content"]) for c in candidates]
    scores = reranker.predict(pairs)
    
    ranked = sorted(
        zip(candidates, scores),
        key=lambda x: x[1],
        reverse=True,
    )
    return [item for item, _ in ranked[:top_k]]

# In the RAG pipeline:
def rag_with_reranking(query: str) -> str:
    # Stage 1: retrieve 20 candidates
    candidates = vector_search(embed(query), top_k=20)
    
    # Stage 2: rerank and keep top 5
    top_chunks = rerank(query, candidates, top_k=5)
    
    # Generate answer with reranked context
    return generate_answer(query, top_chunks)
```

Cohere Rerank (managed API):
```python
import cohere

co = cohere.Client(api_key="...")

def cohere_rerank(query: str, documents: list[str], top_n: int = 5) -> list[str]:
    response = co.rerank(
        query=query,
        documents=documents,
        top_n=top_n,
        model="rerank-english-v3.0",
    )
    # Results are sorted by relevance score (highest first)
    return [documents[r.index] for r in response.results]
```

---

## How It Connects

Reranking is applied after the initial retrieval step in the RAG pipeline  -  it works on top of vector search results.
[[rag-pipeline|RAG Pipeline]]

Hybrid search (combining vector + BM25) retrieves a richer candidate set; reranking then selects the best from the combined results.
[[hybrid-search|Hybrid Search]]

---

## Common Misconceptions

Misconception 1: "Reranking always improves results."
Reality: Reranking improves results when the bi-encoder retrieval has high recall but imprecise ranking. If the bi-encoder already retrieves the right chunks in the top-5, reranking adds latency without improving quality. Measure NDCG or similar before/after.

Misconception 2: "Cross-encoders are too slow to use in production."
Reality: Cross-encoders on 20-50 candidates take 100-500ms on CPU. With GPU or batching, this drops to 20-100ms. For interactive applications (chat), this is acceptable. For bulk processing, batch your reranking calls.

---

## Why It Matters in Practice

Two-stage retrieval results (typical observed improvement):
```
Without reranking: retrieve top-5 with vector search alone
  -> 60-70% of the top-5 are truly relevant

With two-stage (retrieve top-20, rerank to top-5):
  -> 80-90% of the top-5 are truly relevant
```

The improvement is especially pronounced when:
- Queries use different vocabulary than documents
- Documents have high lexical overlap but different meanings
- The correct document is in the top-20 but ranked 10-15 by vector similarity

---

## Interview Angle

Common question forms:
- "What is reranking in RAG?"
- "What is the difference between a bi-encoder and a cross-encoder?"

Answer frame: **Bi-encoder** (used for retrieval): encodes query and document separately -> fast, pre-computable, approximate. **Cross-encoder** (used for reranking): takes (query, document) as pair -> slower, more accurate. Two-stage RAG: retrieve top-20 with bi-encoder -> rerank with cross-encoder -> keep top-5. Improves precision without hurting recall. Adds 100-500ms latency.

---

## Related Notes

- [[retrieval-strategies|Retrieval Strategies]]
- [[rag-pipeline|RAG Pipeline]]
- [[hybrid-search|Hybrid Search]]
- [[rag|RAG]]
