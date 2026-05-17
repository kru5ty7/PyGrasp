---
title: 03 - Vector Search
description: Vector search finds the most semantically similar items in a large collection by comparing embedding vectors using approximate nearest-neighbor algorithms — it is the retrieval engine that makes RAG systems practical at scale.
tags: [vector-search, similarity-search, ann, hnsw, vector-database, faiss, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Vector Search

> Vector search finds the most semantically similar items in a large collection by comparing embedding vectors using approximate nearest-neighbor algorithms — it is the retrieval engine that makes RAG systems practical at scale.

---

## Quick Reference

**Core idea:**
- Vector search = **nearest-neighbor search in high-dimensional space**: given a query vector, find the K stored vectors closest to it by cosine similarity or dot product
- **Exact nearest-neighbor search** over millions of vectors is too slow — approximate nearest-neighbor (ANN) algorithms like **HNSW** trade a small accuracy loss for orders-of-magnitude speed gains
- **HNSW** (Hierarchical Navigable Small World) is the dominant ANN algorithm: builds a multi-layer graph where each node connects to nearby nodes; search traverses from the top layer down
- Vector databases (Chroma, Pinecone, Weaviate, Qdrant, pgvector) combine ANN indexing with metadata filtering, persistence, and a query API
- **Metadata filtering** pre- or post-filters results by structured fields (user ID, date, category) before or after the ANN search, combining semantic and structured retrieval

**Tricky points:**
- ANN indices are **not dynamically updatable without rebuild** in some implementations — adding new vectors after an HNSW index is built works, but the index degrades without periodic re-indexing
- **Index build time** is significant for large corpora — HNSW construction is O(N log N); for millions of vectors, this takes minutes to hours
- **Recall** (the fraction of true nearest neighbors returned) is a tunable parameter — higher recall requires more graph traversal and higher query latency
- `top_k` returns the K most similar results by vector distance, but the K-th result may still have low absolute similarity — always check similarity scores, not just ranks
- In-memory vector stores (Chroma in ephemeral mode, FAISS) lose all data on restart; production deployments need persistent storage with a WAL or database backend

---

## What It Is

Think of finding the closest gas station to your current location. One approach: check every gas station in the country and calculate the distance to each one. That works, but it is slow. A better approach: use a hierarchical map where you start at the coarsest level (country regions), zoom into the closest region (city), then the closest neighborhood, and only then check individual stations. You find a very good answer much faster by never checking stations that are clearly in the wrong region. HNSW works the same way — it builds a multi-resolution graph of vectors and navigates from coarse to fine to find the nearest neighbors without checking every stored vector.

Vector search is what makes semantic retrieval practical at scale. Computing cosine similarity between a query vector and every document vector is exact but O(N) per query. For 1,000 documents, this is trivial — a NumPy dot product takes microseconds. For 1,000,000 documents with 1536-dimensional vectors, brute-force similarity is 1.5 billion multiplications per query. That is slow enough that ANN algorithms become necessary. ANN algorithms accept a small probability of missing the single closest vector in exchange for queries that run in milliseconds regardless of corpus size.

Vector databases are the software infrastructure that hosts the ANN index, manages persistence, handles concurrent reads and writes, and provides a query interface with metadata filtering. At their core, they are specialized data stores optimized for one query type: "find the K vectors most similar to this query vector." Most also support **hybrid search** — combining vector similarity with metadata filters, which allows queries like "find the 10 most semantically similar documents to this query, restricted to documents from 2024 by this author."

---

## How It Actually Works

HNSW builds a layered graph. At the bottom layer (layer 0), every vector is a node, and each node is connected to its `M` nearest neighbors (typically M=16 or 32). Layer 1 contains a random subset of nodes, also connected to their layer-1 nearest neighbors. Layer 2 contains a further-reduced subset, and so on up to the top layer, which contains very few nodes. Think of it as a hierarchy from a fine-grained local graph at the bottom to a coarse long-range graph at the top.

To search for the nearest neighbors of a query vector, HNSW starts at the top layer, finds the nearest node at that layer via greedy graph traversal, then descends to the next layer and repeats from that node's position, continuing until layer 0. The search at each layer uses the connections to navigate toward the query: from the current node, check all connected neighbors; if any neighbor is closer to the query than the current node, move there. This greedy navigation converges to the approximate nearest neighbors in O(log N) steps.

Inserting a new vector into HNSW assigns it to a random maximum layer (drawn from a logarithmic distribution — most vectors go to layer 0 only) and then inserts it into the graph by finding its nearest neighbors at each layer and connecting them. This incremental insertion is what makes HNSW suitable for online indexing — you do not need to rebuild the entire index to add new documents.

In Python, FAISS (Facebook AI Similarity Search) is the most widely used library for in-process vector search. `faiss.IndexFlatL2` is exact search; `faiss.IndexHNSWFlat` is HNSW. Building an index: `index = faiss.IndexFlatIP(dimension); index.add(numpy_array_of_vectors)`. Searching: `distances, indices = index.search(query_vectors, k)` returns the top-k results with their distances and the indices into the original corpus array. FAISS is CPU and GPU accelerated and handles tens of millions of vectors efficiently.

Vector database clients like Chroma (`chromadb`) provide a higher-level API: `collection.add(documents=texts, embeddings=vecs, ids=ids)` to insert, and `collection.query(query_embeddings=q_vecs, n_results=10)` to retrieve. They handle embedding storage, metadata, and ANN indexing internally, removing the need to manage FAISS indices and corpus arrays directly.

---

## How It Connects

Embeddings are the vectors that vector search operates on. Every text must be embedded (converted to a vector) before it can be stored in a vector index, and the query must be embedded before it can be searched. The quality of retrieval depends entirely on the embedding model's ability to encode semantic similarity into geometric proximity.
[[embeddings|Embeddings]]

RAG systems use vector search as their retrieval step. When a user query arrives, the query is embedded and the vector index is searched for the most relevant document chunks. Those chunks are inserted into the LLM's context window. The quality of the generated answer depends directly on the quality of the retrieval step — poor vector search means poor RAG.
[[rag|RAG]]

---

## Common Misconceptions

Misconception 1: "Vector search replaces keyword search."
Reality: Vector search and keyword search are complementary. Vector search excels at finding semantically related content even with different phrasing. Keyword search excels at exact term matching — finding a specific function name, a product SKU, a quote. Hybrid search combines both: a BM25 or Elasticsearch keyword score is combined with a vector similarity score (via reciprocal rank fusion or a weighted sum) to get the benefits of both. Most production RAG systems use hybrid search rather than pure vector search.

Misconception 2: "More results from the vector search means better RAG quality."
Reality: Retrieving more chunks (`top_k=50`) gives the LLM more material but also more noise — irrelevant chunks that distract from the correct answer. The optimal `top_k` depends on the application: factual Q&A over a compact knowledge base might need only 3–5 highly relevant chunks; open-ended research over a large corpus might benefit from 10–20. Increasing `top_k` beyond the point where relevant content appears dilutes the prompt and can degrade LLM response quality. Re-ranking (using a cross-encoder model to score each retrieved chunk against the query) is a higher-quality but more expensive alternative to simply increasing `top_k`.

---

## Why It Matters in Practice

Choosing the right vector database involves tradeoffs along three axes: latency, scalability, and operational complexity. For prototyping or small-scale applications (under 100,000 vectors), Chroma running locally with a SQLite backend is the simplest choice — zero infrastructure, Python-native. For production at millions of vectors, managed services like Pinecone or Qdrant Cloud remove operational burden. For applications already running PostgreSQL, `pgvector` adds vector search as a PostgreSQL extension — eliminating a separate service at the cost of some ANN performance.

The **dimensionality** of vectors stored in the index has a linear effect on memory and a sub-linear effect on search latency (due to SIMD vectorization). A corpus of 1 million documents with 1536-dimensional vectors requires approximately 6 GB of RAM for the raw vectors alone (1M × 1536 × 4 bytes per float). HNSW connectivity data adds another 2–4× overhead. Truncating embeddings to 512 dimensions (supported by newer Matryoshka models like `text-embedding-3-small`) reduces storage to ~2 GB and speeds up similarity computation — worth measuring for large corpora.

---

## Interview Angle

Common question forms:
- "How does vector search work?"
- "What is HNSW and why is it used?"
- "How would you build a semantic search system?"

Answer frame: Vector search = nearest-neighbor search over high-dimensional embedding vectors. Exact search is O(N) — too slow at scale. ANN algorithms like HNSW build a layered graph that enables sublinear-time approximate search. HNSW builds from coarse to fine layers; search traverses from top to bottom via greedy graph navigation. Vector databases (Chroma, Pinecone, pgvector) provide ANN indexing plus persistence and metadata filtering. Production systems often use hybrid search (vector + keyword) and re-ranking for higher quality.

---

## Related Notes

- [[embeddings|Embeddings]]
- [[rag|RAG]]
- [[llm-basics|LLM Basics]]
