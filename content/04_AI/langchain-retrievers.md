---
title: Retrievers
description: "LangChain retrievers are components that return documents given a query — they implement a standard interface (`get_relevant_documents(query)`) and are used in RAG chains; vector store retrievers, multi-query retrievers, and contextual compression retrievers are common; any retriever can slot into an LCEL chain."
tags: [langchain, retrievers, vector-store-retriever, multi-query-retriever, RAG, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Retrievers

> LangChain retrievers are components that return documents given a query — they implement a standard interface (`get_relevant_documents(query)`) and are used in RAG chains; vector store retrievers, multi-query retrievers, and contextual compression retrievers are common; any retriever can slot into an LCEL chain.

---

## Quick Reference

**Core idea:**
- `vectorstore.as_retriever(search_kwargs={"k": 5})` — convert any LangChain vector store to a retriever
- `retriever.invoke("query")` → `list[Document]` — documents have `.page_content` and `.metadata`
- Retrievers are `Runnable` — they plug directly into LCEL chains with `|`
- `MultiQueryRetriever` — generates query variations, merges results
- `ContextualCompressionRetriever` — wraps another retriever and filters/compresses results

**Tricky points:**
- `as_retriever()` returns all `k` results regardless of relevance — add a score threshold: `search_kwargs={"score_threshold": 0.7}` (only works with similarity score search)
- `Document.metadata` is a dict — always include source/URL/title metadata during indexing; you'll need it for citation
- Chroma's `as_retriever(search_type="mmr")` uses Maximum Marginal Relevance — reduces redundancy in retrieved docs; useful when top results are near-duplicate
- Async retrieval: `await retriever.ainvoke("query")` — necessary for async FastAPI handlers
- `EnsembleRetriever` combines multiple retrievers (e.g., BM25 + vector) — implements hybrid search without manual RRF

---

## What It Is

LangChain's retriever abstraction provides a common interface for all retrieval methods — vector search, keyword search, graph-based, or custom API-backed. Any retriever can be swapped into an LCEL chain without changing the surrounding code, enabling easy experimentation with different retrieval backends.

This is the plug-in point for the retrieval step in a RAG pipeline — the chain doesn't know or care whether the retriever uses pgvector, Chroma, or a custom search API.

---

## How It Actually Works

Vector store retriever (basic):
```python
from langchain_chroma import Chroma
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnablePassthrough
from langchain_huggingface import HuggingFaceEmbeddings

# Setup:
embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
vectorstore = Chroma(persist_directory="./chroma_db", embedding_function=embeddings)
retriever = vectorstore.as_retriever(search_kwargs={"k": 5})

# RAG chain:
llm = ChatAnthropic(model="claude-sonnet-4-6")
prompt = ChatPromptTemplate.from_template(
    "Answer using only the context:\n{context}\n\nQuestion: {question}"
)

def format_docs(docs):
    return "\n\n".join(doc.page_content for doc in docs)

rag_chain = (
    {"context": retriever | format_docs, "question": RunnablePassthrough()}
    | prompt | llm | StrOutputParser()
)

answer = rag_chain.invoke("What is RAG?")
```

`MultiQueryRetriever`:
```python
from langchain.retrievers import MultiQueryRetriever

multi_retriever = MultiQueryRetriever.from_llm(
    retriever=vectorstore.as_retriever(search_kwargs={"k": 3}),
    llm=llm,
    include_original=True,  # include the original query in addition to variations
)

docs = multi_retriever.invoke("How does caching work?")
```

`EnsembleRetriever` for hybrid search:
```python
from langchain.retrievers import BM25Retriever, EnsembleRetriever

bm25_retriever = BM25Retriever.from_documents(documents)
bm25_retriever.k = 5

vector_retriever = vectorstore.as_retriever(search_kwargs={"k": 5})

ensemble = EnsembleRetriever(
    retrievers=[bm25_retriever, vector_retriever],
    weights=[0.5, 0.5],  # equal weight; adjust based on evaluation
)

docs = ensemble.invoke("asyncio event loop")
```

Contextual compression (filter irrelevant passages):
```python
from langchain.retrievers.document_compressors import LLMChainExtractor
from langchain.retrievers import ContextualCompressionRetriever

compressor = LLMChainExtractor.from_llm(llm)
compression_retriever = ContextualCompressionRetriever(
    base_compressor=compressor,
    base_retriever=retriever,
)
docs = compression_retriever.invoke("asyncio tasks")
# Returns only the relevant parts of each document, not the full chunk
```

---

## How It Connects

Retrievers are the retrieval layer in LangChain RAG pipelines — they plug into LCEL chains as the source of context.
[[rag|RAG]]

`EnsembleRetriever` implements hybrid search within LangChain's retriever abstraction.
[[hybrid-search|Hybrid Search]]

---

## Common Misconceptions

Misconception 1: "All retrievers return the same quality of results."
Reality: Retriever quality depends heavily on the underlying search method, the embedding model, and the indexing quality. `MultiQueryRetriever` and `ContextualCompressionRetriever` add significant latency for marginal improvement if the base retriever is already good. Profile first.

Misconception 2: "`as_retriever()` requires configuring `search_type`."
Reality: The default `search_type="similarity"` with `k=4` works well for most cases. Only change it when you have evidence that similarity search is failing — e.g., use `mmr` when retrieved documents are too similar to each other.

---

## Why It Matters in Practice

The retriever interface enables easy A/B testing of retrieval strategies:
```python
# Experiment: compare base retriever vs. multi-query
base_chain = {
    "context": base_retriever | format_docs,
    "question": RunnablePassthrough(),
} | prompt | llm | StrOutputParser()

multi_chain = {
    "context": multi_retriever | format_docs,
    "question": RunnablePassthrough(),
} | prompt | llm | StrOutputParser()

# Same evaluation code works for both — retriever is the only difference
```

---

## Interview Angle

Common question forms:
- "How do you build a RAG chain in LangChain?"
- "What is a retriever in LangChain?"

Answer frame: Retriever = component returning `list[Document]` given a query; implements `.invoke(query)`. `vectorstore.as_retriever()` converts any vector store. Plugs into LCEL chain with `|`. `MultiQueryRetriever`: generates query variations, merges. `EnsembleRetriever`: combines BM25 + vector (hybrid search). `ContextualCompressionRetriever`: filters retrieved chunks. All are interchangeable in the chain — swap retriever to change strategy.

---

## Related Notes

- [[langchain-basics|LangChain Basics]]
- [[rag|RAG]]
- [[hybrid-search|Hybrid Search]]
- [[chains|Chains]]
