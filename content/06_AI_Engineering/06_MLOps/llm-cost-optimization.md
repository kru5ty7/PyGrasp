---
title: 10 - LLM Cost Optimization
description: "reducing the operational cost of LLM applications through caching, prompt compression, model routing to smaller models, and batching  -  turning token spend from a runaway variable cost into a manageable, predictable line item"
tags: [cost-optimization, caching, prompt-compression, model-routing, batching, llm, mlops, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# LLM Cost Optimization

> LLM cost optimization is the practice of spending token budget deliberately  -  every optimization either eliminates redundant inference calls (caching), reduces tokens per call (compression and smaller models), or amortizes fixed call overhead (batching).

---

## Quick Reference

**Core idea:**
- **Exact cache**: `hash(system_prompt + user_message) -> response` in Redis  -  eliminates cost for repeated identical queries; effective for FAQ-style workloads
- **Semantic cache**: embed query, find similar cached query, return cached response if similarity > threshold  -  effective for paraphrase-heavy workloads
- **Prompt caching**: OpenAI and Anthropic both offer prompt prefix caching  -  repeated system prompts at the top of context are cached at the API level (50% discount on cached input tokens for Anthropic, ~75% for OpenAI)
- **Prompt compression**: use `LLMLingua` or manual summarization to reduce the token count of long retrieved context before sending to the LLM
- **Model routing**: classify query complexity, route simple queries to `gpt-4o-mini` / `claude-haiku` (10 - 20× cheaper), complex queries to frontier models
- **Batch API**: OpenAI `/v1/batches`, Anthropic `/v1/messages/batches`  -  ~50% cost reduction for non-realtime workloads (24-hour turnaround)

**Tricky points:**
- API-level prompt caching (OpenAI/Anthropic) requires the cached prefix to be at the start of the `messages` array and to exceed a minimum length (1,024 tokens for Anthropic, 1,024 tokens for OpenAI)  -  cache misses occur if you prepend any variable content before the system prompt
- Semantic cache threshold tuning is a precision/recall tradeoff: a 0.98 threshold has few false positives but low hit rate; a 0.90 threshold has more hits but risks returning a cached response for a query that needed a different answer
- Model routing accuracy matters  -  routing a complex reasoning query to a cheap model to save money, when the cheap model cannot answer it correctly, wastes both the cheap model's cost and requires a fallback to the expensive model
- Prompt compression with LLMLingua adds one additional model inference step before the main LLM call  -  if the main model call is short (under 1,000 tokens), compression overhead can exceed the savings
- Output token costs are 2 - 4× more expensive than input tokens on most providers  -  generating concise structured outputs instead of verbose prose can significantly reduce cost

---

## What It Is

Managing LLM costs without optimization is like running a delivery business where every driver takes the most direct route regardless of whether a dozen other packages could be loaded on the same truck with a minor detour. The marginal cost of adding a package to an existing route is nearly zero, but each package sent on a separate truck pays the full overhead. LLM cost optimization is the equivalent of fleet management: route planning (semantic caching and model routing), consolidating loads (batching), reducing the weight of each package (prompt compression), and reusing common infrastructure already paid for (API-level prompt caching).

The economics of LLM APIs at scale are driven by three variables: volume (how many requests), input token count (how large are the prompts), and output token count (how verbose are the responses). Output tokens are the most expensive and most controllable variable  -  explicitly instructing the model to be concise, to respond in structured JSON with a defined schema, or to limit responses to a fixed number of tokens can reduce output cost by 30 - 60% with no quality loss for structured tasks. Input tokens are the second variable  -  long system prompts, extensive few-shot examples, and retrieved context chunks all contribute. A 5,000-token system prompt sent with every request at 1 million requests per day costs 5 billion input tokens daily, a figure that makes prompt efficiency directly important.

Caching is the highest-leverage optimization because a cache hit costs zero inference tokens. Exact caching works for workloads where many users ask the same questions  -  support chatbots, FAQ systems, documentation assistants  -  and can achieve 20 - 40% hit rates on common queries. Semantic caching extends the reach to paraphrase-equivalent queries, potentially doubling the hit rate. API-level prompt caching is the newest form: OpenAI's prompt caching (available automatically since November 2024) and Anthropic's cache control API allow the provider to cache the KV attention states for a repeated long prefix, so the model does not recompute attention over the system prompt on every call. This is transparent to the application (no code change required for OpenAI) or requires explicit cache control headers (for Anthropic) and provides a 50 - 75% discount on the cached portion's input token cost.

---

## How It Actually Works

API-level prompt caching for Anthropic requires adding a `cache_control` block to the content that should be cached. The cached prefix must appear at the same position in the messages array on every call and must exceed 1,024 tokens. The system prompt is the canonical caching target  -  it is identical across all calls from a given deployment and is often long (instructions, persona, few-shot examples).

```python
from anthropic import Anthropic

client = Anthropic()

# The system prompt is cached after the first call;
# subsequent calls with the same prefix pay ~50% of normal input token cost
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    system=[
        {
            "type": "text",
            "text": LONG_SYSTEM_PROMPT,  # must be >= 1024 tokens
            "cache_control": {"type": "ephemeral"},
        }
    ],
    messages=[{"role": "user", "content": user_question}],
)
# response.usage.cache_read_input_tokens shows how many tokens were served from cache
```

Model routing classifies incoming queries by complexity and routes them to the appropriate model. A binary classifier (or a fast LLM call) determines whether the query requires complex reasoning  -  if not, it goes to the cheaper model. The routing classification step is itself a small LLM call (using the cheapest model), so the net saving depends on the accuracy of the router and the cost ratio between the routed models.

```python
from openai import OpenAI

client = OpenAI()

def classify_complexity(query: str) -> str:
    """Returns 'simple' or 'complex'."""
    response = client.chat.completions.create(
        model="gpt-4o-mini",  # cheap classifier
        messages=[{
            "role": "user",
            "content": f"Classify as 'simple' (factual, short answer) or 'complex' (reasoning, analysis): {query}"
        }],
        max_tokens=5,
    )
    return response.choices[0].message.content.strip().lower()

def routed_completion(query: str) -> str:
    complexity = classify_complexity(query)
    model = "gpt-4o-mini" if complexity == "simple" else "gpt-4o"
    response = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": query}],
    )
    return response.choices[0].message.content
```

Prompt compression using `LLMLingua` compresses long retrieved context by identifying and removing tokens that contribute least to preserving the semantic content, targeting a specific compression ratio. At 50% compression, a 2,000-token context becomes 1,000 tokens before being sent to the main LLM. The compression step uses a smaller language model internally to score token importance.

```python
from llmlingua import PromptCompressor

compressor = PromptCompressor(model_name="microsoft/llmlingua-2-xlm-roberta-large-meetingbank")
compressed = compressor.compress_prompt(
    context_text,
    rate=0.5,           # target 50% of original token count
    force_tokens=[],    # tokens to always preserve
)
compressed_context = compressed["compressed_prompt"]
```

---

## How It Connects

Semantic caching is built on vector similarity search  -  embedding the query, searching a vector store for near-duplicate queries, and returning cached results on a match. The same infrastructure (embeddings model, vector store) used for RAG serves double duty as the semantic cache backend.

[[vector-search|Vector Search]]

AI observability provides the data needed to guide cost optimization: per-trace token counts and costs identify which query types, which chains, or which pipeline stages are disproportionately expensive and should be targeted first.

[[ai-observability|AI Observability]]

LLM providers expose the caching infrastructure differently  -  Anthropic requires explicit `cache_control` headers while OpenAI caches automatically for eligible prompts. Understanding the per-provider mechanics is necessary to implement caching correctly.

[[llm-providers|LLM Providers Comparison]]

---

## Common Misconceptions

Misconception 1: "Semantic caching is always safe to use."
Reality: Semantic caching can return a cached response for a query that is semantically similar but requires a different answer. "What is today's weather in Paris?" and "What was yesterday's weather in Paris?" have high semantic similarity but require different responses. Any query whose answer depends on time, user identity, dynamic state, or fine-grained details not captured in semantic similarity is unsafe to cache without additional validity checks. Semantic caching is appropriate for information retrieval over stable corpora, not for dynamic or personalized responses.

Misconception 2: "Using a smaller model always saves money."
Reality: Smaller models are cheaper per token but may require more attempts, longer prompts with more few-shot examples, or follow-up clarification calls to produce acceptable output. A query that requires one `gpt-4o` call and produces a correct answer may require two `gpt-4o-mini` calls  -  one that fails and triggers a retry or fallback. If the failure rate is high enough, the cheaper model costs more per successful completion. Model routing is only cost-effective when the router accurately identifies which queries the cheaper model can handle.

Misconception 3: "Prompt compression always preserves answer quality."
Reality: Prompt compression removes tokens that the compression model judges as low-importance. The compression model's judgment may not align with what the main LLM needs  -  it may discard numerical values, specific entity names, or conditional clauses that are critical for accurate generation. Always evaluate the compressed pipeline's quality metrics against the uncompressed baseline. A 30% reduction in context tokens that produces a 5% drop in faithfulness may not be worth the tradeoff depending on the application's quality requirements.

---

## Why It Matters in Practice

At 1 million API calls per day, a 30% reduction in average input tokens from prompt caching reduces the monthly input token bill by roughly 30%. At \$5/M input tokens, 1 million calls with an average 1,000-token prompt costs \$5,000/day  -  \$1,500/day saved from prompt caching alone. At scale, these optimizations are not minor adjustments; they are the difference between a sustainable unit economics model and an unprofitable one.

The practical discipline of LLM cost optimization forces better architectural decisions. Designers who must account for token cost per user interaction naturally produce leaner, more precise prompts. Teams that measure per-trace cost naturally identify which features are disproportionately expensive and must justify the cost relative to the value delivered. Token cost measurement surfaced via observability tooling converts a hidden, variable infrastructure cost into a first-class product metric  -  the same rigor applied to database query performance or CDN bandwidth.

---

## Interview Angle

Common question forms:
- "How would you reduce the cost of an LLM application that's spending \$50,000/month on API calls?"
- "What is the difference between exact caching, semantic caching, and API-level prompt caching?"
- "When would you use model routing?"

Answer frame: Three layers  -  cache (avoid the call entirely), compress (reduce tokens per call), route (use cheaper model for simple queries). Exact cache: hash match, zero token cost, low hit rate on conversational workloads. Semantic cache: embedding similarity, higher hit rate, requires careful threshold tuning and TTL. Prompt caching: API-level, automatic or via cache_control headers, 50 - 75% discount on cached prefix  -  best ROI for long fixed system prompts. Model routing: classify complexity, route simple queries to cheap model  -  only cost-effective with an accurate router. Batch API: 50% discount at expense of real-time response.

---

## Related Notes

- [[ai-observability|AI Observability]]
- [[llm-providers|LLM Providers Comparison]]
- [[inference-optimization|Inference Optimization]]
- [[vector-search|Vector Search]]
- [[prompt-engineering|Prompt Engineering]]
