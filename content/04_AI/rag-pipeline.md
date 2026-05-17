---
title: RAG Pipeline
description: "A RAG pipeline has two phases: indexing (chunk → embed → store) and retrieval (embed query → search → retrieve → augment prompt → generate); the indexing phase runs once (or on document updates); the retrieval phase runs on every user query."
tags: [rag, rag-pipeline, indexing, retrieval, augmentation, generation, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# RAG Pipeline

> A RAG pipeline has two phases: indexing (chunk → embed → store) and retrieval (embed query → search → retrieve → augment prompt → generate); the indexing phase runs once (or on document updates); the retrieval phase runs on every user query.

---

## Quick Reference

**Core idea:**
- **Indexing phase**: load document → chunk → embed chunks → store in vector DB (offline, run once)
- **Retrieval phase**: embed user query → search vector DB → retrieve top-k chunks → build prompt → call LLM
- **Augmentation**: inject retrieved chunks into the prompt context between system instructions and user query
- **Evaluation metrics**: answer correctness, faithfulness (grounded in retrieved docs), context relevance (retrieved docs are relevant)
- `top_k` — number of chunks to retrieve; typical: 3-10; more chunks = more context for the LLM but also more noise

**Tricky points:**
- Retrieval quality is the bottleneck — a perfect LLM with bad retrieval produces bad answers; optimize retrieval first
- Empty retrieval should be handled explicitly — if no chunks score above the threshold, tell the LLM "no relevant information found" rather than passing an empty context
- Chunk-level vs. document-level attribution — track which chunk each retrieved piece came from for citation
- Stale index: documents added after the last indexing run are not retrieved — implement incremental indexing for live systems
- Query-document mismatch: user queries are short and colloquial; documents are longer and formal — this semantic gap reduces retrieval quality; HyDE or query expansion can help

---

## What It Is

A RAG pipeline operationalizes the idea of giving an LLM access to a knowledge base. The two-phase design is deliberate: indexing is expensive (embed every chunk) and done upfront; retrieval is fast (one embedding + ANN search) and done per query.

The pipeline is a chain of transformations: raw text → retrievable embeddings (offline), and question → relevant context → grounded answer (online). Each step in the chain has its own quality parameters and failure modes.

---

## How It Actually Works

Complete RAG pipeline:
```python
import anthropic
from sentence_transformers import SentenceTransformer
import chromadb

# ===== INDEXING PHASE (offline) =====

def index_documents(documents: list[dict]):
    """documents: [{"content": "...", "source": "url", "title": "..."}]"""
    model = SentenceTransformer("all-MiniLM-L6-v2")
    client = chromadb.PersistentClient(path="./chroma_db")
    collection = client.get_or_create_collection("docs")
    
    for doc in documents:
        chunks = split_into_chunks(doc["content"], chunk_size=512, overlap=50)
        embeddings = model.encode(chunks).tolist()
        
        collection.add(
            ids=[f"{doc['source']}_{i}" for i in range(len(chunks))],
            embeddings=embeddings,
            documents=chunks,
            metadatas=[{"source": doc["source"], "title": doc["title"]}] * len(chunks),
        )

# ===== RETRIEVAL PHASE (online, per query) =====

def retrieve(query: str, top_k: int = 5) -> list[dict]:
    model = SentenceTransformer("all-MiniLM-L6-v2")
    client = chromadb.PersistentClient(path="./chroma_db")
    collection = client.get_collection("docs")
    
    query_embedding = model.encode([query]).tolist()
    results = collection.query(
        query_embeddings=query_embedding,
        n_results=top_k,
    )
    
    return [
        {"content": doc, "source": meta["source"]}
        for doc, meta in zip(results["documents"][0], results["metadatas"][0])
    ]

def generate_answer(query: str, chunks: list[dict]) -> str:
    client = anthropic.Anthropic()
    
    context = "\n\n".join([
        f"Source: {c['source']}\n{c['content']}" 
        for c in chunks
    ])
    
    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        system="""Answer questions based on the provided context.
If the context doesn't contain enough information, say so.
Always cite the source (e.g., 'According to [source]...').""",
        messages=[{
            "role": "user",
            "content": f"Context:\n{context}\n\nQuestion: {query}"
        }]
    )
    return response.content[0].text

def rag_query(question: str) -> str:
    chunks = retrieve(question, top_k=5)
    if not chunks:
        return "No relevant information found."
    return generate_answer(question, chunks)
```

---

## How It Connects

The RAG pipeline's retrieval step is the practical application of vector search — the query embedding finds similar document embeddings.
[[rag|RAG]]

Retrieval strategies beyond basic vector search (re-ranking, hybrid search) improve the quality of what gets passed to the LLM.
[[retrieval-strategies|Retrieval Strategies]]

---

## Common Misconceptions

Misconception 1: "RAG eliminates hallucination."
Reality: RAG reduces hallucination by grounding the LLM in retrieved facts. But the LLM can still hallucinate if: the retrieved chunks don't contain the answer, the LLM ignores the context, or the LLM confabulates beyond the retrieved information. Always evaluate answer faithfulness.

Misconception 2: "More chunks = better answers."
Reality: Retrieving 20 chunks fills the context window with noise — irrelevant chunks confuse the model. 3-5 high-quality relevant chunks typically outperform 20 mixed-quality chunks. Use re-ranking to select the best chunks from a larger candidate set.

---

## Why It Matters in Practice

RAG pipeline evaluation:
```
Metric 1 — Retrieval precision: % of retrieved chunks that are actually relevant
Metric 2 — Answer faithfulness: is the answer grounded in the retrieved context?
Metric 3 — Answer correctness: is the answer factually right?

Diagnose failures:
- Wrong answer + relevant chunks: LLM problem (prompt, model)
- Wrong answer + irrelevant chunks: retrieval problem (embedding, chunking)
- No chunks retrieved: indexing problem (document not indexed, query mismatch)
```

---

## Interview Angle

Common question forms:
- "How does a RAG pipeline work?"
- "What are the two phases of RAG?"

Answer frame: Two phases — **indexing** (offline: chunk → embed → store in vector DB) and **retrieval** (online per query: embed query → ANN search → retrieve top-k chunks → inject into prompt → LLM generates answer). Bottleneck is retrieval quality. Failure modes: bad chunking, embedding model mismatch, stale index, too many/few chunks. Evaluate separately: is retrieval relevant? Is the answer faithful to retrieved context?

---

## Related Notes

- [[rag|RAG]]
- [[retrieval-strategies|Retrieval Strategies]]
- [[chunking-strategies|Chunking Strategies]]
- [[vector-databases|Vector Databases]]
