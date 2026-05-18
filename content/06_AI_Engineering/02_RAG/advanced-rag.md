---
title: 05 - Advanced RAG Patterns
description: "techniques beyond naive RAG including query rewriting, HyDE, parent-document retriever, multi-query retriever, contextual compression, and self-RAG  -  each targeting a specific failure mode of basic similarity search"
tags: [rag, advanced-rag, hyde, query-rewriting, multi-query, contextual-compression, self-rag, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# Advanced RAG Patterns

> Advanced RAG patterns are targeted interventions for specific failure modes of naive similarity search  -  each technique addresses a different reason why the retriever returns the wrong chunks or too many of them.

---

## Quick Reference

**Core idea:**
- **Query rewriting**: transform the raw user question into a more retrieval-friendly form before embedding  -  rewrites for ambiguity, jargon, or conversational context
- **HyDE** (Hypothetical Document Embedding): generate a fake answer to the question, embed that instead of the question  -  narrows the embedding space distance to real answer documents
- **Parent-document retriever**: embed small chunks for precision retrieval, but return the larger parent document as context  -  avoids chunking artifacts that break coherent answers
- **Multi-query retriever**: generate N rephrased versions of the question, retrieve for each, deduplicate  -  improves recall by covering synonymous query formulations
- **Contextual compression**: after retrieval, pass chunks through an LLM extractor that returns only the sentence(s) relevant to the question  -  reduces noise in the context window
- **Self-RAG**: the model decides whether retrieval is needed at all, then critiques and filters its own retrieved results before generating  -  avoids unnecessary retrieval on questions the model can answer directly

**Tricky points:**
- HyDE adds one full LLM call per query (to generate the hypothetical document)  -  latency doubles before any retrieval occurs
- Parent-document retriever requires maintaining two separate data structures: the chunk-level vector store and the parent-document store (typically an `InMemoryStore` or Redis)
- Multi-query retriever multiplies vector search calls by N  -  with 3 sub-queries you pay 3× embedding and search cost per user query
- Contextual compression can discard relevant context if the compressor LLM is too aggressive  -  always validate that compression does not drop signal
- Self-RAG requires a specially fine-tuned model that outputs special tokens (`[Retrieve]`, `[ISREL]`, `[ISSUP]`, `[ISUSE]`)  -  standard LLMs do not natively emit these and cannot implement true self-RAG

---

## What It Is

Naive RAG treats retrieval as a single-shot similarity search: embed the user's question, find the nearest chunks, insert them into the prompt. This works well when the question and the answer document use similar vocabulary and when the question is clear and specific. In practice, neither condition reliably holds. A user might ask "why did my trade fail?" when the relevant document says "Order rejection reasons include insufficient margin and position limits." The question and the answer share almost no vocabulary, so cosine similarity between their embeddings is low, and retrieval fails even though the relevant document is in the corpus.

Advanced RAG patterns are a toolkit of targeted fixes for these failure modes, rather than a single unified architecture. Query rewriting addresses vocabulary mismatch by transforming the question into the vocabulary domain of the corpus. HyDE addresses the asymmetry between question embeddings and answer embeddings by generating an answer-shaped document to use as the query embedding instead. The parent-document retriever addresses chunking artifacts  -  the observation that small chunks retrieve with high precision but often lack enough surrounding context to generate a coherent answer  -  by decoupling the embedding unit from the context unit. Multi-query retrieval addresses the brittleness of single-query retrieval by generating multiple formulations and taking the union of results. Contextual compression addresses context window pollution by stripping irrelevant sentences from otherwise-relevant chunks.

The term "advanced RAG" also encompasses pipeline-level architectural changes. Sequential RAG runs the pipeline once  -  retrieve then generate. Iterative RAG runs multiple retrieve-and-read cycles, where each generation step produces a follow-up query that drives the next retrieval step. Self-RAG extends this further: the model is fine-tuned to emit special reflection tokens that signal when retrieval is needed, whether retrieved documents are relevant, whether the generated claim is supported by them, and whether the overall response is useful. This makes retrieval a dynamic, model-controlled decision rather than a fixed preprocessing step. Self-RAG requires a model fine-tuned for this behavior; it cannot be approximated by prompting a standard LLM.

---

## How It Actually Works

In LangChain, query rewriting is implemented by constructing a chain that passes the original question through an LLM prompt that asks it to rephrase the question for better document retrieval before passing it to the retriever. A `LLMChain` or LCEL pipe with a rephrase prompt plus the retriever accomplishes this. The `MultiQueryRetriever` automates a specific form of this: it calls an LLM to generate N distinct rephrased questions, executes a vector search for each, and returns the deduplicated union of results.

```python
from langchain.retrievers.multi_query import MultiQueryRetriever
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)
retriever = MultiQueryRetriever.from_llm(
    retriever=vectorstore.as_retriever(search_kwargs={"k": 4}),
    llm=llm,
)
# Internally: generate 3 query variants -> retrieve for each -> deduplicate
docs = retriever.invoke("What causes order rejection in trading systems?")
```

HyDE is implemented by chaining: (1) a prompt that asks the LLM to write a short hypothetical document that would answer the question, (2) an embedding call on that generated text, (3) a similarity search using the generated-text embedding rather than the question embedding. The intuition is that a generated answer lies in the same embedding subspace as real answer documents, while a question lies in a different subspace even when it's semantically related. LangChain's `HypotheticalDocumentEmbedder` implements this as a custom `Embeddings` class.

The parent-document retriever requires two stores: a vector store containing embeddings of small child chunks, and a docstore containing the full parent documents. At index time, each document is split into both small child chunks (for embedding) and kept as a whole parent (in the docstore), with the child chunks linked to their parent by a metadata key. At query time, similarity search runs against the child chunk embeddings to identify the most relevant chunks, then the retriever fetches the corresponding parent documents from the docstore.

```python
from langchain.retrievers import ParentDocumentRetriever
from langchain.storage import InMemoryStore
from langchain_text_splitters import RecursiveCharacterTextSplitter

child_splitter = RecursiveCharacterTextSplitter(chunk_size=400)
parent_splitter = RecursiveCharacterTextSplitter(chunk_size=2000)

docstore = InMemoryStore()
retriever = ParentDocumentRetriever(
    vectorstore=vectorstore,
    docstore=docstore,
    child_splitter=child_splitter,
    parent_splitter=parent_splitter,
)
retriever.add_documents(documents)
# Retrieval returns parent (2000-char) chunks even though search matched child (400-char) chunks
```

Contextual compression wraps any retriever with a `ContextualCompressionRetriever` that passes each retrieved document through a compressor. The `LLMChainExtractor` compressor is an LLM call that returns only the portion of the document relevant to the query. The `EmbeddingsFilter` compressor is a cheaper alternative: it re-embeds each retrieved chunk and filters out chunks whose cosine similarity to the query falls below a threshold  -  no LLM call required.

---

## How It Connects

Multi-query and HyDE both consume additional LLM calls per user query, and these calls add latency. Understanding how to pipeline these calls asynchronously  -  running the N sub-queries for multi-query retrieval concurrently rather than sequentially  -  requires familiarity with async patterns in Python and LangChain's async retriever interface (`ainvoke`).

[[async-await|Async and Await]]

The quality improvements from advanced RAG patterns are only visible through measurement. Running RAGAS evaluation before and after adding a technique like parent-document retrieval or contextual compression is the only way to confirm that the added latency and cost produce a real quality improvement. Without evaluation, advanced RAG patterns are latency overhead with unknown benefit.

[[rag-evaluation|RAG Evaluation]]

LangChain's retriever interfaces  -  `BaseRetriever`, `MultiQueryRetriever`, `ParentDocumentRetriever`, `ContextualCompressionRetriever`  -  all implement the same `invoke(query)` interface, making them interchangeable in LCEL chains and LangGraph nodes.

[[langchain-retrievers|Retrievers]]

---

## Common Misconceptions

Misconception 1: "HyDE always improves retrieval quality."
Reality: HyDE improves recall when questions and documents use different vocabulary, but it can hurt precision when the generated hypothetical document contains confidently stated but incorrect details. If the LLM generates a plausible but factually wrong hypothetical answer, the embedding will retrieve documents similar to the wrong answer rather than documents that would correct the question. HyDE should be evaluated empirically against your specific corpus; it is not a universal improvement.

Misconception 2: "I can implement self-RAG by prompting a standard LLM to decide whether to retrieve."
Reality: Prompting a standard LLM to output retrieval decision tokens is an approximation of self-RAG, not self-RAG. True self-RAG requires a model fine-tuned with a specialized vocabulary of reflection tokens (`[Retrieve]`, `[ISREL]`, `[ISSUP]`, `[ISUSE]`) that are incorporated into the model's generation process. What you can implement with a standard LLM is a routing step  -  a separate classification call that decides whether retrieval is needed  -  which is useful but fundamentally different from self-RAG's integrated reflection mechanism.

Misconception 3: "More advanced techniques mean better results."
Reality: Advanced RAG adds complexity, latency, and cost. The right starting point is always evaluation of the naive pipeline to identify which specific metric is failing. If context recall is 0.9 and answer faithfulness is 0.6, the problem is in generation (or the generation prompt)  -  adding multi-query retrieval will not help. Applying advanced retrieval techniques to a generation problem wastes engineering time. Measure first, then apply the targeted intervention.

---

## Why It Matters in Practice

The transition from a demo RAG pipeline to a production RAG system almost always involves adding at least one advanced technique, because the failure modes of naive similarity search become apparent under real query distributions. Users ask questions in natural language that may use different terminology than the indexed documents, ask compound questions that require multiple pieces of context, and ask follow-up questions in multi-turn conversations where the pronoun "it" refers to something mentioned three turns ago. Parent-document retrieval, multi-query, and query rewriting each address a class of these failure patterns.

The engineering cost of these techniques must be weighed against quality gains on measured metrics. Multi-query adds N-1 extra retrieval calls per query  -  this is acceptable if it raises context recall from 0.65 to 0.85, but the same latency spent on a reranker might achieve a larger gain in context precision for a given corpus. Profiling retrieval latency and comparing RAGAS metrics before and after each technique gives the data needed to make these decisions. Advanced RAG is a menu of options, not a checklist to implement in full.

---

## Interview Angle

Common question forms:
- "What would you do if your RAG pipeline had poor retrieval quality?"
- "Explain HyDE and when you would use it."
- "What is the parent-document retriever and what problem does it solve?"

Answer frame: Start by naming the failure mode before the technique  -  vocabulary mismatch -> HyDE or query rewriting; chunking artifact -> parent-document retriever; single-query brittleness -> multi-query; context window noise -> contextual compression. For HyDE: generate a fake answer, embed it instead of the question, retrieve based on the fake answer's embedding. For parent-document retriever: embed small chunks for precision, return large parent chunks for answer quality. Always anchor the discussion in measurement  -  run RAGAS, identify which metric is failing, apply the corresponding technique.

---

## Related Notes

- [[rag|RAG]]
- [[rag-pipeline|RAG Pipeline]]
- [[rag-evaluation|RAG Evaluation]]
- [[retrieval-strategies|Retrieval Strategies]]
- [[langchain-retrievers|Retrievers]]
- [[reranking|Reranking]]
- [[hybrid-search|Hybrid Search]]
