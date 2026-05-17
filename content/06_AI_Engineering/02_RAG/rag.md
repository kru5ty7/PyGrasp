---
title: 01 - RAG
description: Retrieval-Augmented Generation combines a retrieval step (finding relevant documents via vector search) with a generation step (passing retrieved context to an LLM) — it extends what an LLM can answer beyond its training data without fine-tuning.
tags: [rag, retrieval, augmented-generation, llm, vector-search, context, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# RAG

> Retrieval-Augmented Generation combines a retrieval step (finding relevant documents via vector search) with a generation step (passing retrieved context to an LLM) — it extends what an LLM can answer beyond its training data without fine-tuning.

---

## Quick Reference

**Core idea:**
- RAG = **retrieve relevant document chunks** from a vector index → **insert them into the LLM prompt** → **generate an answer grounded in those documents**
- Solves the LLM's core limitation: the model's knowledge is frozen at training time; RAG provides up-to-date, domain-specific, or proprietary information at query time
- The pipeline has two phases: **indexing** (offline: chunk → embed → store) and **querying** (online: embed query → retrieve → augment prompt → generate)
- **Chunking strategy** determines what goes into each vector — the fundamental quality lever in the indexing phase
- The retrieved chunks are inserted into the LLM context as a **"context" section** of the system or user prompt, followed by the question

**Tricky points:**
- The model answers **based on what is in the context**, not what it was trained on — if retrieval misses the relevant chunk, the model will hallucinate or say it does not know
- **Faithfulness** (answer supported by retrieved context) and **relevance** (retrieved context actually matches the question) are distinct quality metrics that can fail independently
- Long retrieved contexts dilute the model's attention — a known phenomenon called **"lost in the middle"**: models attend less to content in the middle of a long context than at the beginning or end
- Re-ranking retrieved chunks before insertion (using a cross-encoder) improves quality but adds latency — the tradeoff depends on use case
- Hybrid RAG systems combine vector search (semantic) with keyword search (BM25) and merge results via reciprocal rank fusion for higher recall

---

## What It Is

Think of RAG as giving an LLM an open-book exam rather than a closed-book one. In a closed-book exam, the model can only use what it memorized during training — it may not know recent events, your company's internal documentation, or specialized domain knowledge from niche fields. In an open-book exam, the model is given relevant pages from a textbook and asked to answer based on them. RAG is the mechanism for selecting and delivering those relevant pages. The model's job shifts from "recall the answer from training" to "read these specific passages and synthesize an answer."

RAG emerged as a practical solution to two converging problems. LLMs are expensive to fine-tune and their weights cannot be updated cheaply with new information. But LLMs are excellent at reading provided text and synthesizing answers from it — this capability generalizes well to new content the model was never trained on. Vector search provides efficient retrieval of relevant passages from large corpora. Combining them produces a system that can answer questions grounded in a specific, updatable document collection, without the cost of fine-tuning.

The architecture divides into two distinct phases. The **indexing phase** is offline: documents are loaded, split into chunks, each chunk is embedded by an embedding model, and the (chunk text, vector) pairs are stored in a vector database. This runs once (and incrementally as documents are added or updated). The **querying phase** is online: the user's question is embedded, the vector database is searched for the most similar chunk vectors, the top-k matching chunks are retrieved as text, and a prompt is constructed that includes those chunks as context along with the original question. The LLM generates a response based on the provided context.

---

## How It Actually Works

The indexing pipeline begins with document loading — reading PDFs, web pages, code files, or database records into raw text. The text is then split into chunks. A naive fixed-size chunker splits every N characters; a more careful recursive text splitter (as used in LangChain) splits on paragraph boundaries first, then sentence boundaries, then word boundaries, trying to keep semantically coherent units together. Chunk size is typically 256–512 tokens with a 50–100 token overlap between adjacent chunks. The overlap ensures that sentences near chunk boundaries are represented in both adjacent chunks, preventing relevant context from being split across chunks.

Each chunk is sent to an embedding model to produce a vector. In batch processing, sending multiple chunks per API call (up to the model's batch limit) reduces latency and cost. The resulting vectors are stored in a vector database alongside the chunk text and metadata (source document, page number, section heading, creation date). Metadata enables filtered retrieval — "find the most relevant chunks from documents modified in the last 30 days."

At query time, the user's question goes through the same embedding model to produce a query vector. The vector database ANN index is searched for the top-k most similar chunk vectors. The `k` is typically 3–10 depending on the context window size and chunk length. The retrieved chunk texts are assembled into a context string and inserted into the prompt. A common format: system message sets the assistant's role and instructs it to answer only from context; the user message includes a `CONTEXT` block with the retrieved passages, then the question. The LLM generates the answer, ideally citing or grounding its claims in the provided passages.

**Re-ranking** is an optional but quality-improving step between retrieval and generation. A cross-encoder model takes each (query, chunk) pair and scores how relevant the chunk is to the query — more accurate than embedding similarity alone, because the cross-encoder can model the relationship between the full query text and the full chunk text. The top-k retrieved chunks are re-ordered by cross-encoder score, and only the top-m (m < k) are passed to the LLM. This reduces noise in the LLM context at the cost of additional model inference time.

---

## How It Connects

Embeddings are the core mechanism for both indexing and query-time retrieval. The quality of the embedding model determines the quality of semantic matching — whether a user's question about "Python thread safety" retrieves chunks about the GIL, `threading.Lock`, and `asyncio.Queue`. Embedding quality is the ceiling on RAG quality; better retrieval is impossible without better semantic representation.
[[embeddings|Embeddings]]

Vector search is the infrastructure that stores and queries the embedding vectors. The ANN index enables sub-millisecond retrieval even over millions of chunks. The choice of vector database affects latency, scalability, and whether hybrid search (vector + keyword) is supported.
[[vector-search|Vector Search]]

The LLM is the generation component — it reads the retrieved context and produces the answer. The LLM's context window size determines how many chunks can be provided; its instruction-following quality determines how faithfully it stays grounded in the provided context rather than hallucinating from training data.
[[llm-basics|LLM Basics]]

RAG pipelines involve multiple async I/O calls — embedding API requests and LLM API requests are both HTTP calls. Building efficient RAG pipelines (especially batch indexing and streaming responses) relies on async HTTP clients and `asyncio.gather()` for concurrent embedding requests.
[[async-await|Async and Await]]

---

## Common Misconceptions

Misconception 1: "RAG eliminates hallucination."
Reality: RAG reduces hallucination for questions answerable from the indexed documents, but it does not eliminate it. If the relevant chunk is not retrieved (retrieval failure), the model may hallucinate. If the model ignores the provided context (faithfulness failure), it may still hallucinate. If the question is outside the indexed corpus entirely, there is no relevant context to retrieve, and the model will answer from training. RAG adds groundable context; it does not enforce grounding. Faithfulness evaluation (checking that the answer is supported by retrieved chunks) is a separate step required for high-reliability systems.

Misconception 2: "A larger context window makes RAG unnecessary."
Reality: Very large context windows (1 million tokens) enable fitting more of a knowledge base into a single prompt, but they do not replace RAG for large or dynamic knowledge bases. A 1M-token context costs significantly more per query than a focused 4,000-token prompt with 3 retrieved chunks. For corpora larger than the context window, retrieval remains necessary. For frequently updated corpora, retrieval from an updated index is cheaper than re-loading the entire corpus on every call. Retrieval also provides attribution — you know which document the answer came from. Large context windows and RAG are complementary: retrieval narrows the corpus, context window size determines how much retrieved content fits.

---

## Why It Matters in Practice

Evaluation is the hardest part of building a RAG system. The two key metrics are **context relevance** (are the retrieved chunks actually relevant to the question?) and **answer faithfulness** (is the generated answer supported by the retrieved context?). A third metric, **answer correctness**, compares the answer to a ground-truth answer. RAGAS is a popular Python library that automates these evaluations using an LLM as the judge. Running RAGAS on a set of question-answer pairs before and after tuning chunking strategy, embedding model, or retrieval parameters is the standard way to measure whether a change improved RAG quality.

The indexing pipeline should be treated as a separate, maintainable service — not a script that runs once. Documents are added, updated, and deleted. The vector index must stay synchronized with the document store. Each document should have a stable ID; updates should delete and re-insert the corresponding chunks. Failure to maintain the index produces stale retrieval — chunks from outdated document versions that produce incorrect or contradictory answers.

---

## Interview Angle

Common question forms:
- "What is RAG and why is it used?"
- "Walk me through the RAG pipeline."
- "How do you evaluate a RAG system?"

Answer frame: RAG combines retrieval (find relevant document chunks via vector search) with generation (pass retrieved chunks as context to an LLM). Solves the problem of LLMs having stale or missing knowledge without fine-tuning. Two phases: offline indexing (chunk → embed → store) and online querying (embed query → ANN search → augment prompt → generate). Key quality levers: chunking strategy, embedding model quality, retrieval top-k, optional re-ranking, prompt design. Evaluation: context relevance + answer faithfulness + answer correctness, automated via LLM-as-judge frameworks like RAGAS.

---

## Related Notes

- [[embeddings|Embeddings]]
- [[vector-search|Vector Search]]
- [[llm-basics|LLM Basics]]
- [[langchain-basics|LangChain Basics]]
