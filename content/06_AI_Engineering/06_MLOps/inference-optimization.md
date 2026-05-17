---
title: 03 - Inference Optimization
description: "techniques for reducing ML inference cost and latency including request batching, semantic caching, async pipelines, and GPU vs CPU trade-offs for different model sizes and traffic patterns"
tags: [inference, optimization, batching, caching, async, gpu, cpu, mlops, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# Inference Optimization

> Inference optimization is the discipline of doing more with the same hardware — the same model, the same GPU, the same API budget — by restructuring when and how inference calls are made rather than by changing the model itself.

---

## Quick Reference

**Core idea:**
- **Request batching**: accumulate N requests over a time window, process them as one batched model call, return results — GPU utilization improves because matrix ops scale with batch size
- **Exact cache**: store `hash(prompt) → response` in Redis; return cached response for identical prompts without an inference call
- **Semantic cache**: embed the query and search a vector store for a "close enough" previous query; return its cached response — tolerant of paraphrase and minor variation
- **Async pipelines**: use `asyncio.gather()` to fire multiple independent inference calls concurrently rather than awaiting them sequentially
- **GPU vs CPU**: GPU is 10–100× faster for large models but expensive per hour; CPU is sufficient for small models (<500M parameters) or low-throughput serving
- **KV cache**: transformer inference reuses key/value tensors from previous tokens — this is the mechanism that makes autoregressive generation efficient; it is internal to the model runtime, not application-level

**Tricky points:**
- Semantic caching can return stale responses if the cached answer was generated with an older model version or outdated context — cache invalidation must be time-bounded
- Batching adds latency to fast individual requests: a request that would complete in 50ms now waits up to `max_batch_delay_ms` before processing even starts
- `asyncio.gather()` runs tasks concurrently on the same event loop thread — if each task calls a synchronous inference function without `run_in_executor`, the tasks serialize on the GIL
- GPU underutilization is a real cost problem: a GPU instance left idle between requests still incurs the full per-hour cost; auto-scaling to zero requires a cold start when traffic returns
- For OpenAI and Anthropic APIs, "batching" means using the Batch API (`/v1/messages/batches` for Anthropic, `/v1/batches` for OpenAI) which processes requests asynchronously at ~50% cost reduction but with 24-hour turnaround

---

## What It Is

Optimizing ML inference is like managing a delivery truck. A truck that makes one delivery at a time, driving across the city for each individual package, is expensive and slow. The same truck loaded with 50 packages and following an optimized route delivers more value per mile. The truck's capacity (the GPU's parallel compute units) is fixed — the optimization is in how fully you use that capacity per trip. Batching is the act of loading the truck. Caching is the act of not sending the truck at all when you already have the item in the warehouse. Async pipelines are the act of dispatching multiple trucks simultaneously rather than waiting for one to return before sending the next.

GPU inference is fundamentally a batch operation. The mathematical operations at the core of transformer inference — large matrix multiplications — are designed to run on many examples simultaneously. A batch of 32 inputs does not take 32× as long as a single input on a GPU; it might take only 1.5–3× as long because the GPU's parallel compute units can process all 32 inputs nearly simultaneously. A batch of 1 (per-request inference) therefore wastes the majority of the GPU's parallel capacity. At low traffic, this waste is unavoidable unless you implement dynamic batching — accumulating requests over a small time window before processing them together. Dedicated serving frameworks like NVIDIA Triton implement dynamic batching by configuration; a custom implementation requires a request queue with a background worker.

Caching addresses a different kind of waste: repeated computation. In production LLM applications, many queries are functionally identical — the same question rephrased slightly differently, the same system prompt with different user messages, or the same question asked by different users. Exact caching (keyed on a hash of the exact prompt string) eliminates redundant computation for identical prompts but has low hit rates in conversational systems where prompts vary continuously. Semantic caching goes further by storing previous query-response pairs and, for each new query, checking whether a semantically similar query was already answered. If the cosine similarity between the new query embedding and a cached query embedding exceeds a threshold, the cached response is returned without an inference call. Libraries like `GPTCache` and `langchain-community`'s `SemanticSimilarityCache` implement this pattern.

---

## How It Actually Works

Async pipelines optimize the case where multiple independent inference calls must be made as part of processing one user request — for example, classifying the query, retrieving documents, and running a safety check in parallel before the main LLM call. Using `asyncio.gather()` fires all three calls concurrently on the event loop, reducing total latency from the sum of all three to the maximum of all three.

```python
import asyncio
from openai import AsyncOpenAI

client = AsyncOpenAI()

async def classify(text: str) -> str:
    resp = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": f"Classify: {text}"}],
        max_tokens=10,
    )
    return resp.choices[0].message.content

async def summarize(text: str) -> str:
    resp = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": f"Summarize: {text}"}],
        max_tokens=100,
    )
    return resp.choices[0].message.content

async def process(text: str):
    # Both calls fire simultaneously — total time ≈ max(classify_time, summarize_time)
    classification, summary = await asyncio.gather(
        classify(text),
        summarize(text),
    )
    return {"classification": classification, "summary": summary}
```

Semantic caching requires embedding each incoming query, searching a vector store for near-duplicate queries within a similarity threshold, and returning the stored response on a cache hit. The threshold is a tunable parameter: too low (strict) produces few cache hits; too high (permissive) returns cached responses for queries that are genuinely different. A threshold of 0.95 cosine similarity is typical for semantic caches where accuracy is critical.

```python
from langchain.cache import InMemoryCache
from langchain.globals import set_llm_cache
from langchain_openai import OpenAIEmbeddings
from langchain_community.cache import RedisSemanticCache

embeddings = OpenAIEmbeddings()
set_llm_cache(RedisSemanticCache(
    redis_url="redis://localhost:6379",
    embedding=embeddings,
    score_threshold=0.95,
))
# Subsequent LangChain LLM calls check the semantic cache before calling the API
```

The GPU versus CPU decision for serving depends on model size and throughput requirements. Models below 500M parameters (DistilBERT, all-MiniLM, small classifiers) serve efficiently on CPU at low latency, avoiding GPU instance costs entirely. Models in the 1–7B range can run on a single GPU but may serve acceptably on CPU at lower traffic volumes with quantization. Models above 13B parameters require GPU for acceptable latency. The cost comparison is straightforward: a `ml.g4dn.xlarge` on SageMaker costs roughly \$0.74/hour for a T4 GPU; a `ml.c5.2xlarge` CPU instance costs \$0.34/hour. For a model that handles 10 requests/minute, CPU may be more cost-effective even if each request takes 3× longer.

---

## How It Connects

Quantization is the model-level counterpart to inference optimization: it reduces the memory footprint and compute cost of each inference call, making a given GPU more capable of handling concurrent requests without other optimizations.

[[quantization|Quantization]]

Semantic caching stores embedding-response pairs and requires a vector database or in-memory vector store. Understanding how similarity search works at the threshold level is necessary to tune the cache's aggressiveness correctly.

[[vector-search|Vector Search]]

LLM cost optimization extends inference optimization with application-level strategies: routing simple queries to cheaper smaller models, prompt compression, and exact caching for common system prompts.

[[llm-cost-optimization|LLM Cost Optimization]]

---

## Common Misconceptions

Misconception 1: "Async Python makes my model inference faster."
Reality: `async/await` does not make CPU or GPU computation faster — it allows the Python process to handle other I/O work while waiting for an inference call to complete. If the inference is a network call to an external API (OpenAI, Anthropic), async truly enables concurrency. If the inference is a local PyTorch model call in the same process, `async def` alone does nothing — the call blocks the event loop until it completes. You must use `run_in_executor` to offload CPU-bound inference to a thread or process pool.

Misconception 2: "Semantic caching is safe to use for all query types."
Reality: Semantic caching is only safe when similar queries have similar correct answers. For queries where small wording differences produce legitimately different correct responses — "what is today's price of AAPL?" asked at two different times, or "summarize this document" with two different documents — semantic caching will return a stale or wrong answer. Semantic caches should only be applied to query types where semantic similarity is a reliable proxy for answer identity, and always with a time-to-live (TTL) to prevent indefinitely stale responses.

---

## Why It Matters in Practice

Inference costs are the dominant operating expense for production ML applications at scale. A system making 1 million LLM API calls per day at \$0.005 per call spends \$5,000 per day — \$150,000 per month. A semantic cache with a 30% hit rate reduces this to \$3,500 per day. Async pipelines that reduce per-request latency from 3 seconds to 1.5 seconds halve the number of concurrent connections required to serve a given throughput, reducing infrastructure costs. These optimizations compound: semantic caching + async pipelines + batching can reduce costs by 50–80% without changing model quality.

For LLMs specifically, inference optimization is tightly coupled to user experience. An LLM endpoint with a 10-second p99 latency requires long streaming connections or spinner UI states that degrade the user experience. Reducing p99 latency through caching and batching converts expensive model calls into fast cache hits and improves the experience for the majority of users who ask common questions.

---

## Interview Angle

Common question forms:
- "How would you reduce the cost of an LLM application serving 1 million requests per day?"
- "What is semantic caching and when would you use it?"
- "Why doesn't async Python make GPU inference faster?"

Answer frame: Three layers of optimization — request batching (amortize GPU compute), caching (eliminate redundant calls: exact for identical prompts, semantic for near-duplicate queries), async pipelines (parallelize independent API calls). GPU vs CPU cost analysis depends on model size and throughput. Semantic cache limitations: TTL required, only valid when similar queries have similar correct answers. Async does not speed up local CPU inference — it only helps with I/O-bound API calls.

---

## Related Notes

- [[model-serving|Model Serving]]
- [[quantization|Quantization]]
- [[llm-cost-optimization|LLM Cost Optimization]]
- [[vector-search|Vector Search]]
- [[async-await|Async and Await]]
