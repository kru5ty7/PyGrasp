---
title: 04 - Similarity Metrics
description: "Similarity metrics measure how close two vectors are — cosine similarity (angle between vectors, range -1 to 1) is standard for text embeddings; L2 (Euclidean) measures absolute distance; dot product combines magnitude and angle; cosine similarity is preferred because it ignores vector magnitude."
tags: [similarity-metrics, cosine-similarity, L2-distance, dot-product, vector-similarity, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Similarity Metrics

> Similarity metrics measure how close two vectors are — cosine similarity (angle between vectors, range -1 to 1) is standard for text embeddings; L2 (Euclidean) measures absolute distance; dot product combines magnitude and angle; cosine similarity is preferred because it ignores vector magnitude.

---

## Quick Reference

**Core idea:**
- **Cosine similarity**: `cos(θ) = (A·B) / (|A| × |B|)` — measures the angle; 1.0 = identical direction, 0 = orthogonal, -1 = opposite
- **L2 distance** (Euclidean): `||A - B||₂` — absolute distance; 0 = identical; increases with both direction and magnitude differences
- **Dot product**: `A·B = |A||B|cos(θ)` — combines angle and magnitude; used when magnitude carries meaning (e.g., re-ranking by relevance score)
- For most text embedding use cases: **cosine similarity** is the correct choice
- pgvector operators: `<=>` cosine distance (1 - cosine similarity), `<->` L2, `<#>` inner product (negative dot product)

**Tricky points:**
- Cosine distance ≠ cosine similarity: cosine distance = 1 - cosine similarity; smaller distance = more similar; `ORDER BY embedding <=> query ASC` returns most similar first
- Normalized embeddings: if vectors are unit-normalized (length = 1), L2 distance ≈ cosine distance — many embedding models output normalized vectors; check the model docs
- Negative cosine similarity: only possible with non-normalized vectors; means the texts are "opposite" in semantic space (rare in practice)
- Dot product is affected by magnitude — two texts with similar meaning but different lengths may have different magnitudes; cosine similarity removes this effect
- Choice of metric must match the index: pgvector HNSW index created with `vector_cosine_ops` can only do cosine distance; creating a new index changes which metric is optimized

---

## What It Is

After generating embeddings (dense vectors representing text meaning), similarity metrics determine how to compare them. The choice matters: two semantically similar sentences should score high; unrelated sentences should score low.

Cosine similarity dominates text search because text embeddings encode meaning in direction, not magnitude. "cat" and "kitten" should be similar regardless of how the text was encoded into the embedding model — their vectors point in nearly the same direction. L2 distance would penalize differences in magnitude (e.g., if "kitten" got a smaller magnitude for some incidental reason).

---

## How It Actually Works

Computing metrics with NumPy:
```python
import numpy as np

def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))

def l2_distance(a: np.ndarray, b: np.ndarray) -> float:
    return np.linalg.norm(a - b)

def dot_product(a: np.ndarray, b: np.ndarray) -> float:
    return np.dot(a, b)

# Example:
cat = np.array([0.8, 0.6, 0.0])    # simplified embedding
kitten = np.array([0.7, 0.7, 0.0])
dog = np.array([0.6, 0.3, 0.8])
car = np.array([0.0, 0.0, 1.0])

print(cosine_similarity(cat, kitten))  # ≈ 0.99 — very similar
print(cosine_similarity(cat, dog))     # ≈ 0.78 — related (both animals)
print(cosine_similarity(cat, car))     # ≈ 0.00 — unrelated
```

pgvector query with cosine distance:
```sql
-- Find 5 most similar documents to a query embedding
SELECT id, content, 1 - (embedding <=> '[0.1, 0.2, ...]') as similarity
FROM documents
ORDER BY embedding <=> '[0.1, 0.2, ...]'
LIMIT 5;
```

Using `sklearn` for similarity:
```python
from sklearn.metrics.pairwise import cosine_similarity as sk_cosine
import numpy as np

embeddings = np.array([embed1, embed2, embed3])  # shape (n, dim)
query = np.array([query_embed])                   # shape (1, dim)

similarities = sk_cosine(query, embeddings)[0]    # shape (n,)
top_k = np.argsort(similarities)[::-1][:5]       # top 5 indices
```

---

## How It Connects

Similarity metrics are used in vector search to rank retrieved documents — the metric must match what the embedding model was trained with.
[[vector-search|Vector Search]]

Vector databases use specific metrics to build their indexes — `pgvector` requires specifying the metric at index creation.
[[vector-databases|Vector Databases]]

---

## Common Misconceptions

Misconception 1: "Higher L2 distance always means less similar."
Reality: For non-normalized vectors, L2 distance is affected by vector magnitude. Two identical-meaning texts encoded with different magnitudes would have non-zero L2 distance but cosine similarity of 1.0. Use cosine similarity for semantic search.

Misconception 2: "All similarity metrics are interchangeable."
Reality: The metric must match the embedding model's training objective. Sentence transformers trained with cosine similarity loss should be compared with cosine similarity. Using L2 on these embeddings gives suboptimal rankings. Check the model card.

---

## Why It Matters in Practice

Interpreting cosine similarity scores:
```
0.90 - 1.00: Near-duplicate or same content
0.75 - 0.90: Very similar, same topic
0.60 - 0.75: Related, somewhat similar
0.40 - 0.60: Loosely related
0.00 - 0.40: Likely unrelated
```

These thresholds are model-dependent — calibrate by examining actual score distributions from your embedding model on your data.

Setting a similarity threshold for RAG:
```python
results = collection.query(query_texts=[question], n_results=10)
# Only use results above threshold:
relevant = [
    (doc, score) for doc, score in zip(results["documents"][0], results["distances"][0])
    if (1 - score) >= 0.7  # convert distance to similarity
]
```

---

## Interview Angle

Common question forms:
- "What is cosine similarity?"
- "Why do we use cosine similarity for text embeddings?"

Answer frame: Cosine similarity = angle between vectors (1 = identical direction, 0 = orthogonal, -1 = opposite). Preferred for text because it ignores magnitude — only direction (semantic meaning) matters. L2 distance is affected by magnitude (bad for text). Dot product = cosine × magnitudes (useful when magnitude encodes relevance). Cosine distance = 1 - cosine similarity (smaller = more similar — used in distance-based APIs).

---

## Related Notes

- [[embeddings|Embeddings]]
- [[vector-search|Vector Search]]
- [[vector-databases|Vector Databases]]
