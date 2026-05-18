---
title: 01 - Embeddings
description: Embeddings are dense vector representations of text (or other data) produced by a neural network  -  they encode semantic meaning as coordinates in high-dimensional space, enabling similarity search, clustering, and retrieval that operates on meaning rather than keywords.
tags: [embeddings, vectors, semantic-search, similarity, neural-network, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Embeddings

> Embeddings are dense vector representations of text (or other data) produced by a neural network  -  they encode semantic meaning as coordinates in high-dimensional space, enabling similarity search, clustering, and retrieval that operates on meaning rather than keywords.

---

## Quick Reference

**Core idea:**
- An embedding is a **fixed-length list of floats** (e.g., 1536 dimensions for `text-embedding-ada-002`) that represents the semantic content of a piece of text
- Texts with **similar meaning** have embedding vectors that are close together in vector space; unrelated texts have vectors that are far apart
- **Cosine similarity** is the standard distance metric: it measures the angle between two vectors, not their magnitude  -  ranges from -1 (opposite) to 1 (identical direction)
- Embeddings are produced by an **embedding model** (separate from the LLM)  -  OpenAI's `text-embedding-3-small`, Sentence-Transformers, Cohere Embed are common choices
- Embeddings enable **semantic search**: query -> embed the query -> find stored vectors closest to the query vector -> return those documents

**Tricky points:**
- Embedding models have a **token limit** (e.g., 8192 tokens for `text-embedding-3-small`)  -  text longer than this must be chunked before embedding
- The **dimensionality** of the embedding vector is a property of the model, not something you control at inference time (some newer models support Matryoshka truncation)
- Embeddings from **different models are not comparable**  -  you cannot compute similarity between a vector from model A and a vector from model B
- **Dot product** and **cosine similarity** give the same ranking if vectors are L2-normalized  -  many vector databases pre-normalize and use dot product internally
- Embedding an entire long document as one vector averages its semantics  -  a document about Python's GIL and database transactions will have a vector that represents neither topic well

---

## What It Is

Think of a vast library where every book is stored not on shelves by title but plotted as a point in a 1536-dimensional coordinate space. Books on similar topics are plotted close together. "Python concurrency" and "GIL threading" are neighbors. "Medieval history" and "CPython bytecode" are far apart. If you arrive with a question  -  "how does Python handle multithreading?"  -  you convert your question into the same kind of coordinate, walk to that location in the library, and find all nearby books are related to your topic. You never needed to know the exact title or use the right keywords. You navigated by meaning.

This is what embeddings do. A neural network  -  the embedding model  -  has been trained to map text into a vector space where semantic similarity corresponds to geometric proximity. The network learns that "car" and "automobile" should produce nearby vectors, that "fast" and "quick" should be close, that a question about Python threading should be near documents that discuss the GIL and `threading.Thread`, even if those exact words do not appear in the question. The vector representation encodes this learned semantic geometry.

Embeddings are produced in isolation from any specific query  -  you embed a document once, store the vector, and it remains valid for any future query. This is the property that makes embeddings practical for retrieval: you pre-compute vectors for your entire document corpus (once, at indexing time) and store them in a vector database. At query time, you embed only the query and then perform a similarity search over the pre-computed document vectors. The expensive step (embedding the corpus) happens once; the cheap step (a single embedding + nearest-neighbor search) happens at query time.

---

## How It Actually Works

An embedding model is typically a transformer encoder (not a generative decoder like an LLM). It processes the input tokens through attention layers and produces a hidden state for each token. The embedding for the entire input is derived by **mean pooling** these token representations (averaging across the sequence) or by taking the representation at a special `[CLS]` token that the model was trained to use as a summary. The result is a single fixed-length vector regardless of input length.

Embedding models are trained with **contrastive learning** objectives. The model is shown pairs of semantically similar texts (a question and its correct answer, two paraphrases of the same sentence, a product description and a user review of that product) and trained to produce vectors that are close together for similar pairs and far apart for dissimilar pairs. The loss function directly optimizes the geometric structure of the vector space. Models like Sentence-BERT (SBERT) and the OpenAI embedding models are trained this way on large corpora of paired text.

Similarity between two vectors is almost always computed as **cosine similarity**: `cos(θ) = (A · B) / (|A| × |B|)`, the dot product of the two vectors divided by the product of their magnitudes. This measures the angle between the vectors, ignoring their absolute scale. A cosine similarity of 1.0 means the vectors point in exactly the same direction (most similar); 0.0 means they are orthogonal (unrelated); -1.0 means opposite directions. In practice, most embedding models produce positive vectors and cosine similarity ranges between 0 and 1 for typical text pairs. Many implementations L2-normalize the vectors before storage, which makes cosine similarity equivalent to dot product and simplifies the computation.

Calling an embedding API in Python is a single request: pass a list of text strings, receive a list of vectors. With the OpenAI SDK: `client.embeddings.create(model="text-embedding-3-small", input=["text one", "text two"])` returns an object whose `.data` list contains the vectors. In batch processing, sending multiple strings in a single call is more efficient than one call per string, because the model can process them in parallel on the GPU. Chunking a large document into passages (typically 256 - 512 tokens each, with some overlap) and embedding each chunk separately is the standard preprocessing step before indexing into a vector database.

---

## How It Connects

Embeddings are the primary mechanism by which RAG systems retrieve relevant context. A query is embedded, and the nearest document chunks (by cosine similarity) are retrieved and inserted into the LLM's context window. Without embeddings, retrieval falls back to keyword search, which cannot match semantically equivalent phrasing.
[[rag|RAG]]

Vector search is the infrastructure that stores and efficiently queries embedding vectors at scale. Storing vectors in a Python list and computing cosine similarity with NumPy works for hundreds of documents but not for millions. Vector databases (Chroma, Pinecone, Weaviate, pgvector) provide efficient approximate nearest-neighbor search over large corpora.
[[vector-search|Vector Search]]

Embedding API calls are I/O-bound HTTP requests. Embedding a large corpus (thousands of documents) efficiently requires async batch requests  -  sending multiple chunks concurrently and awaiting their completion with `asyncio.gather()` rather than embedding chunks sequentially.
[[async-await|Async and Await]]

---

## Common Misconceptions

Misconception 1: "Embeddings understand meaning the way humans do."
Reality: Embeddings encode statistical patterns from training data  -  co-occurrence patterns, paraphrase patterns, translation patterns. They produce geometrically similar vectors for semantically related texts because those texts appeared in similar contexts in training data. They do not have conceptual understanding. An embedding model trained only on English will poorly represent similar texts in Japanese. A model trained primarily on news articles may not capture the semantic relationships specific to medical or legal text. Domain-specific embedding models often significantly outperform general-purpose models for specialized retrieval tasks.

Misconception 2: "A higher-dimensional embedding vector is always better."
Reality: Higher dimensionality means more expressive capacity but also more storage, more computation per similarity comparison, and more training data required to fill the space meaningfully. A 1536-dimensional model trained on a trillion tokens will outperform a 3072-dimensional model trained on a billion. Newer models like `text-embedding-3-small` support **Matryoshka representation learning**, which means you can truncate the vector to fewer dimensions (e.g., 512) with only modest quality loss, trading quality for speed and storage  -  this is often the right choice for high-volume applications.

---

## Why It Matters in Practice

Chunking strategy is the most impactful variable in embedding quality for retrieval. A chunk that is too long averages semantics across multiple topics; a chunk that is too short lacks enough context to be semantically meaningful. The standard starting point is 256 - 512 tokens per chunk with a 10 - 20% overlap between adjacent chunks (so that sentences spanning a boundary are captured in both). The overlap prevents relevant context from being split across chunks and missing the query's semantic target.

Embedding costs are dominated by corpus size, not query volume. For a corpus of 10,000 documents at 500 tokens each, initial embedding costs 5 million tokens  -  a one-time cost at indexing. Each query embeds only the query string (50 - 100 tokens typically). At scale, re-embedding the entire corpus when switching models (which is necessary, because vectors from different models are incomparable) is the largest operational cost in embedding-based systems.

---

## Interview Angle

Common question forms:
- "What is an embedding and what is it used for?"
- "How does semantic search differ from keyword search?"
- "What is cosine similarity and why is it used?"

Answer frame: Define embedding as a fixed-length float vector produced by a neural network that encodes semantic content  -  similar texts produce nearby vectors. Contrast with keyword search: keyword search requires exact term matches; semantic search finds related content even with different phrasing. Cosine similarity: measures vector angle, not magnitude  -  values from -1 to 1, higher means more similar. Chunking: long documents must be split before embedding; chunk size is a tuning parameter. Vector databases store and search these vectors at scale.

---

## Related Notes

- [[llm-basics|LLM Basics]]
- [[vector-search|Vector Search]]
- [[rag|RAG]]
