---
title: 05 - Hybrid Search
description: "Hybrid search combines dense vector search (semantic similarity) with sparse keyword search (BM25/TF-IDF) — vector search finds semantically related content; keyword search finds exact term matches; combining both with RRF (Reciprocal Rank Fusion) improves retrieval over either alone."
tags: [hybrid-search, BM25, dense-retrieval, sparse-retrieval, RRF, reciprocal-rank-fusion, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Hybrid Search

> Hybrid search combines dense vector search (semantic similarity) with sparse keyword search (BM25/TF-IDF) — vector search finds semantically related content; keyword search finds exact term matches; combining both with RRF (Reciprocal Rank Fusion) improves retrieval over either alone.

---

## Quick Reference

**Core idea:**
- **Dense retrieval** (vector search): semantic similarity; finds related concepts even with different words; misses exact matches on rare terms
- **Sparse retrieval** (BM25): keyword matching; finds documents containing the query terms; fails on semantically similar but lexically different content
- **Hybrid = dense + sparse + merge**: run both, combine ranked lists with RRF
- **RRF (Reciprocal Rank Fusion)**: `score = Σ 1/(k + rank_i)` where k=60; simple, robust, usually better than weighted combination
- Many vector databases support hybrid search natively (pgvector with `tsvector`, Qdrant, Elasticsearch)

**Tricky points:**
- BM25 is sensitive to exact keyword matches — good for product names, error codes, technical terms; poor for paraphrases or synonyms
- Vector search handles paraphrases well but can miss exact matches — "ERROR_CODE_404" and "404 error" are semantically similar but the embedding may prioritize general meaning over exact code
- RRF parameter `k=60` is the standard default — the `+60` in the denominator prevents documents ranked 1st from dominating excessively; rarely needs tuning
- Hybrid search requires running two retrieval systems — higher latency and complexity than single-modality
- `alpha` parameter (if using weighted combination instead of RRF): 0.0 = pure BM25, 1.0 = pure vector; typical starting point: 0.5

---

## What It Is

Neither vector search nor keyword search is universally better — they complement each other. A query like "how to configure TLS in nginx" benefits from both: vector search finds semantically related documentation, keyword search ensures documents containing "TLS" and "nginx" are included even if they use slightly different phrasing.

Hybrid search exploits the complementarity: retrieve the top-N from each method independently, then merge the ranked lists. The merged list leverages both signals — semantically related content and exact keyword matches both surface.

---

## How It Actually Works

RRF implementation:
```python
from collections import defaultdict

def reciprocal_rank_fusion(
    ranked_lists: list[list[str]],  # each list is ordered by relevance
    k: int = 60,
) -> list[str]:
    """Merge multiple ranked lists using RRF."""
    scores = defaultdict(float)
    
    for ranked in ranked_lists:
        for rank, doc_id in enumerate(ranked, start=1):
            scores[doc_id] += 1.0 / (k + rank)
    
    return sorted(scores.keys(), key=lambda x: scores[x], reverse=True)

# In practice:
vector_results = vector_search(embed(query), top_k=20)  # list of doc IDs
bm25_results = bm25_search(query, top_k=20)             # list of doc IDs

merged_ids = reciprocal_rank_fusion([vector_results, bm25_results])
top_5 = merged_ids[:5]
```

PostgreSQL hybrid search with `pgvector` + full-text search:
```sql
WITH vector_results AS (
    SELECT id, 1 - (embedding <=> $1) as score, rank() OVER (ORDER BY embedding <=> $1) as rank
    FROM documents
    ORDER BY embedding <=> $1
    LIMIT 20
),
text_results AS (
    SELECT id, ts_rank(to_tsvector('english', content), query) as score,
           rank() OVER (ORDER BY ts_rank(to_tsvector('english', content), query) DESC) as rank
    FROM documents, plainto_tsquery('english', $2) query
    WHERE to_tsvector('english', content) @@ query
    LIMIT 20
),
rrf AS (
    SELECT COALESCE(v.id, t.id) as id,
           COALESCE(1.0/(60+v.rank), 0) + COALESCE(1.0/(60+t.rank), 0) as rrf_score
    FROM vector_results v FULL OUTER JOIN text_results t ON v.id = t.id
)
SELECT id FROM rrf ORDER BY rrf_score DESC LIMIT 5;
```

Qdrant hybrid search (built-in support):
```python
from qdrant_client import QdrantClient
from qdrant_client.models import SparseVector

client = QdrantClient(url="http://localhost:6333")

results = client.query_points(
    collection_name="docs",
    prefetch=[
        # Dense: semantic similarity
        {"query": dense_embedding, "using": "dense", "limit": 20},
        # Sparse: keyword matching
        {"query": SparseVector(indices=[...], values=[...]), "using": "sparse", "limit": 20},
    ],
    query=None,  # fusion query
    using="...",
    limit=5,
)
```

---

## How It Connects

Hybrid search combines the outputs of vector search and BM25 retrieval — understanding both is prerequisite.
[[vector-search|Vector Search]]

Reranking is often applied after hybrid search to further refine the merged results.
[[reranking|Reranking]]

---

## Common Misconceptions

Misconception 1: "Vector search alone is sufficient for all retrieval tasks."
Reality: Vector search fails on: exact code snippets, product IDs, error codes, proper names spelled unusually, technical jargon not in training data. These require keyword matching. Hybrid search covers both failure modes.

Misconception 2: "Hybrid search always outperforms single-modality retrieval."
Reality: For well-embedded domains where queries match document style, vector search alone may score near-parity with hybrid. Hybrid is most valuable for mixed-vocabulary domains (technical + natural language queries on technical docs).

---

## Why It Matters in Practice

Use cases where hybrid search provides the most benefit:
- Developer documentation (code snippets + prose explanations)
- E-commerce (product names + descriptions)
- Legal/medical (technical terms + explanatory content)
- Customer support (product codes + natural language descriptions)

Evaluation: measure NDCG@5 on a test set with annotated relevant documents — compare vector-only, BM25-only, and hybrid to determine if hybrid is worth the added complexity for your use case.

---

## Interview Angle

Common question forms:
- "What is hybrid search?"
- "When would you use BM25 over vector search?"

Answer frame: **Dense** (vector) = semantic similarity; finds related content; poor on exact terms. **Sparse** (BM25) = keyword match; exact terms; poor on paraphrases. **Hybrid** = run both, merge with RRF (each result's score = Σ 1/(60 + rank)). RRF is robust and parameter-free. Best for mixed-vocabulary domains (code + prose, technical terms + descriptions).

---

## Related Notes

- [[vector-search|Vector Search]]
- [[reranking|Reranking]]
- [[retrieval-strategies|Retrieval Strategies]]
- [[rag-pipeline|RAG Pipeline]]
