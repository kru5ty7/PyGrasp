---
title: Chunking Strategies
description: "Chunking splits documents into smaller pieces before embedding — the chunk size, overlap, and splitting method affect retrieval quality; fixed-size character splits are simplest; sentence/paragraph splitting preserves context; recursive splitting tries larger units first; chunk overlap prevents losing context at boundaries."
tags: [chunking, chunk-size, overlap, text-splitter, recursive-splitting, RAG, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Chunking Strategies

> Chunking splits documents into smaller pieces before embedding — the chunk size, overlap, and splitting method affect retrieval quality; fixed-size character splits are simplest; sentence/paragraph splitting preserves context; recursive splitting tries larger units first; chunk overlap prevents losing context at boundaries.

---

## Quick Reference

**Core idea:**
- **Chunk size**: smaller chunks = more precise retrieval; larger chunks = more context per match; typical range: 256-1024 tokens
- **Overlap**: duplicate content at chunk boundaries (e.g., 50-100 tokens) — prevents losing information when a fact spans a boundary
- **Fixed-size splitting**: split every N characters/tokens — simple but may split mid-sentence
- **Sentence/paragraph splitting**: split at natural boundaries — better context but variable size
- **Recursive splitting**: try paragraph → sentence → word splits in order; ensures no chunk exceeds max size

**Tricky points:**
- The optimal chunk size depends on your content and query type — short factual queries match small chunks better; reasoning tasks benefit from larger chunks
- Metadata matters as much as content — include document title, URL, section heading in chunk metadata for citation
- Small chunks embedded independently lose context — "it" or "they" in a chunk without context embeds poorly
- Embedding dimension ≠ context window — embedding models have their own input limits (usually 512-8192 tokens); chunks should fit the embedding model's limit, not just the LLM's context window
- Parent-child chunking: embed small chunks for precision, retrieve parent (larger) chunk for context — best of both worlds

---

## What It Is

Embedding an entire 100-page document as one vector loses all granularity — a query about Chapter 3 would match on the whole document. Chunking creates multiple embeddings per document, each representing a section, paragraph, or window of text. The retrieval step then finds the specific chunk most relevant to the query.

The chunking strategy is one of the highest-impact parameters in a RAG pipeline. Bad chunking (chunks that cut mid-sentence, too small to contain useful context, or too large to be specific) directly degrades retrieval quality.

---

## How It Actually Works

Fixed-size with overlap (LangChain):
```python
from langchain.text_splitter import RecursiveCharacterTextSplitter

splitter = RecursiveCharacterTextSplitter(
    chunk_size=1000,       # characters, not tokens
    chunk_overlap=200,     # overlap between chunks
    separators=["\n\n", "\n", ". ", " ", ""],  # try these in order
)

chunks = splitter.split_text(document_text)
# Returns: list of strings, each ≤ 1000 chars
```

Token-aware splitting:
```python
import tiktoken
from langchain.text_splitter import TokenTextSplitter

enc = tiktoken.encoding_for_model("gpt-4o")
splitter = TokenTextSplitter(
    encoding_name="cl100k_base",
    chunk_size=512,    # tokens
    chunk_overlap=50,
)

chunks = splitter.split_text(document_text)
```

Semantic chunking (split at topic boundaries):
```python
from langchain_experimental.text_splitter import SemanticChunker
from langchain_openai.embeddings import OpenAIEmbeddings

splitter = SemanticChunker(
    embeddings=OpenAIEmbeddings(),
    breakpoint_threshold_type="percentile",  # split where cosine distance jumps
)
chunks = splitter.split_text(document_text)
```

Parent-child chunking pattern:
```python
def chunk_with_context(document: str, small_size=256, large_size=1024, overlap=50):
    """Embed small chunks, store large chunk as context."""
    small_splitter = RecursiveCharacterTextSplitter(chunk_size=small_size, chunk_overlap=overlap)
    large_splitter = RecursiveCharacterTextSplitter(chunk_size=large_size, chunk_overlap=overlap)
    
    large_chunks = large_splitter.split_text(document)
    result = []
    for i, large_chunk in enumerate(large_chunks):
        small_chunks = small_splitter.split_text(large_chunk)
        for small in small_chunks:
            result.append({
                "embed_text": small,          # embed this for precise matching
                "retrieve_text": large_chunk,  # return this for context
                "parent_id": i,
            })
    return result
```

---

## How It Connects

Chunked text is embedded before storing in a vector database — chunk quality directly affects embedding quality and retrieval precision.
[[embeddings|Embeddings]]

Chunking strategy determines what ends up in the LLM's context window during RAG — good chunking = relevant, self-contained passages.
[[rag|RAG]]

---

## Common Misconceptions

Misconception 1: "Smaller chunks always give better retrieval."
Reality: Very small chunks (50-100 tokens) often lack enough context for the embedding model to produce a meaningful representation. "The patient was given..." without knowing what drug or condition embeds poorly. A balance of 256-512 tokens typically works well for most text types.

Misconception 2: "Overlap wastes storage space and should be minimized."
Reality: Without overlap, a key piece of information at a chunk boundary is half in one chunk (too incomplete) and half in another (also incomplete). A 10-15% overlap adds modest storage cost but significantly improves retrieval for content that spans chunk boundaries.

---

## Why It Matters in Practice

Choosing chunk size by content type:
```
Legal/technical documents (dense, specific):  256-512 tokens, small overlap
Long-form prose (novels, blog posts):         512-1024 tokens, moderate overlap
Code files:                                   Split at function/class boundaries
Q&A pairs (FAQs):                             One Q&A pair per chunk
Structured data (tables, lists):              One row/item per chunk
```

Testing chunk quality:
- Retrieve the top-5 chunks for 10 representative queries
- Manually evaluate: is the retrieved chunk actually relevant?
- Check: does the chunk contain the answer, or just related terms?
- Adjust chunk size and overlap based on findings

---

## Interview Angle

Common question forms:
- "How do you split documents for RAG?"
- "What is chunk overlap and why does it matter?"

Answer frame: Chunking splits documents into pieces that can be independently embedded and retrieved. Fixed-size: simplest; may cut mid-sentence. Recursive: tries paragraph → sentence splits first; more natural boundaries. Overlap (10-15%): duplicates content at chunk boundaries to prevent losing facts that span the split point. Chunk size trade-off: small = precise but lacks context; large = more context but less specific matches. Parent-child: embed small, retrieve large.

---

## Related Notes

- [[embeddings|Embeddings]]
- [[rag|RAG]]
- [[context-window|Context Window]]
- [[vector-databases|Vector Databases]]
