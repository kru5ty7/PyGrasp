---
title: 08 - LLM Providers Comparison
description: "comparison of major LLM provider APIs (OpenAI, Anthropic, Google, local models via Ollama/LM Studio) covering API shapes, rate limits, context windows, cost, and abstraction layers"
tags: [llm, openai, anthropic, google, ollama, litellm, langchain, providers, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# LLM Providers Comparison

> Choosing an LLM provider is an infrastructure decision that affects cost, latency, data privacy, and capability  -  understanding the differences between OpenAI, Anthropic, Google, and local models determines which choice survives production.

---

## Quick Reference

**Core idea:**
- **OpenAI** (`openai` SDK): `client.chat.completions.create(model="gpt-4o", messages=[...])`  -  the de facto standard API shape that most others have adopted
- **Anthropic** (`anthropic` SDK): `client.messages.create(model="claude-sonnet-4-6", system="...", messages=[...])`  -  `system` is a top-level field, not a message role
- **Google** (`google-generativeai` or `google-cloud-aiplatform`): `GenerativeModel("gemini-1.5-pro").generate_content(...)`  -  different shape, multimodal-first
- **Ollama** (local): OpenAI-compatible REST API at `http://localhost:11434/v1`  -  use `openai` client with `base_url` override
- **LiteLLM**: `litellm.completion(model="anthropic/claude-sonnet-4-6", messages=[...])`  -  single interface for 100+ providers with automatic format translation
- **LangChain community** providers: `ChatOpenAI`, `ChatAnthropic`, `ChatOllama`  -  wrap provider SDKs into a unified `invoke(messages)` interface

**Tricky points:**
- Anthropic's `system` parameter is not inside the `messages` list  -  passing it as a system-role message raises a validation error
- Rate limits are per-tier and reset per minute AND per day  -  hitting the daily limit is a different error than hitting the per-minute limit
- Context window sizes change with model versions: `gpt-4o` has 128k, `claude-sonnet-4-6` has 200k, `gemini-1.5-pro` has 1M
- Local models via Ollama run on the machine's hardware  -  an 8B model needs ~6 GB VRAM, a 70B model needs ~40+ GB without quantization
- LiteLLM's `cost_per_token` and `completion_cost()` functions track spend per call; without this, cost monitoring requires manual per-provider parsing

---

## What It Is

Think of LLM providers as competing airlines flying the same routes. The destination  -  getting a natural language completion from a large model  -  is the same, but the check-in process, baggage rules, seat configuration, and pricing structure differ enough that booking one airline's ticket does not automatically work on another carrier. A flight itinerary written for United cannot be handed to Delta without adjustment. Abstracting over providers is like using a travel aggregator: you specify the route and the aggregator handles the carrier-specific booking format.

The LLM provider landscape in 2026 breaks into three tiers. Cloud providers  -  OpenAI, Anthropic, and Google  -  run models on their own infrastructure and expose HTTP APIs. You send a request, pay per token, and receive a completion. The pricing is typically split between input tokens and output tokens, with output tokens costing two to four times more. OpenAI's GPT-4o sits at roughly \$2.50/M input and \$10/M output; Anthropic's Claude Sonnet is in a similar range. Google's Gemini pricing depends on whether you use the Gemini API (direct) or Vertex AI (enterprise GCP route), with Vertex adding IAM and networking complexity in exchange for data residency guarantees. The second tier is open-weight models  -  Meta's Llama family, Mistral, Phi, Qwen  -  models whose weights are publicly released and can be run on your own hardware. The third tier is the infrastructure layer around those open-weight models: Ollama and LM Studio make it trivial to run a model locally by downloading a GGUF-formatted quantized weight file and spinning up a local HTTP server; cloud inference providers like Together AI, Fireworks, and Groq host the same open-weight models at lower cost than the frontier model providers.

The API shapes differ in ways that matter when switching providers. OpenAI's Chat Completions API became the industry template: a JSON body with a `model` string and a `messages` array of `{"role": ..., "content": ...}` objects. Anthropic adopted a nearly identical shape but deliberately separated the system prompt into a top-level `system` field rather than a first message with `role: system`. Google's Generative AI SDK evolved from a generation-first multimodal API and has a different method structure. LiteLLM and LangChain both exist specifically to absorb these differences so application code can switch providers by changing a string.

---

## How It Actually Works

The `openai` Python SDK communicates with OpenAI's servers (or any OpenAI-compatible endpoint) via HTTPS POST to `/v1/chat/completions`. The SDK's `OpenAI` client is initialized with an `api_key` and optionally a `base_url`. Setting `base_url="http://localhost:11434/v1"` and `api_key="ollama"` (a placeholder) routes calls to a locally running Ollama instance instead  -  Ollama deliberately implements the OpenAI API shape for this reason. The same technique works for Azure OpenAI (`base_url` set to the Azure endpoint), Groq, Together AI, and Fireworks, which all chose OpenAI compatibility to reduce integration friction for developers. LM Studio exposes the same compatible endpoint on port 1234 by default.

```python
from openai import OpenAI

# OpenAI
client = OpenAI(api_key="sk-...")
response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "What is a transformer?"}],
    temperature=0.2,
    max_tokens=512,
)

# Ollama (local)  -  same client, different base_url
local_client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
response = local_client.chat.completions.create(
    model="llama3.2",
    messages=[{"role": "user", "content": "What is a transformer?"}],
)
```

LiteLLM's `completion()` function accepts any `provider/model` string and translates the OpenAI-shaped input to the target provider's wire format internally. It handles Anthropic's `system` parameter extraction, Google's content part format, and AWS Bedrock's signing automatically. The `litellm.completion_cost(completion_response)` function parses the usage field and multiplies by the provider's published per-token price, returning a cost in USD  -  making it the most practical way to track spend across a mixed-provider application. LangChain wraps provider SDKs into `BaseChatModel` subclasses (`ChatOpenAI`, `ChatAnthropic`, `ChatGoogleGenerativeAI`, `ChatOllama`) with a common `invoke(messages)` / `stream(messages)` interface and are the standard choice when using LCEL chains or LangGraph nodes that need to be provider-agnostic.

```python
import litellm

# Single interface, any provider
response = litellm.completion(
    model="anthropic/claude-sonnet-4-6",
    messages=[{"role": "user", "content": "What is a transformer?"}],
)
cost = litellm.completion_cost(response)
print(f"Cost: ${cost:.6f}")
```

---

## How It Connects

Every provider call is an HTTP request to a remote service, and production applications need async, non-blocking calls. Understanding how `await client.chat.completions.acreate(...)` fits inside FastAPI route handlers and why blocking the event loop with the synchronous SDK stalls all concurrent requests is a prerequisite for deploying any LLM feature at scale.

[[async-await|Async and Await]]

LangChain's abstraction over providers makes the most sense in the context of chains and graphs  -  when a prompt template, retriever, and output parser need to be connected into a pipeline. The `ChatOpenAI` and `ChatAnthropic` classes implement the `Runnable` interface, meaning they participate in LCEL pipelines and LangGraph nodes uniformly regardless of which provider is behind them.

[[lcel|LangChain Expression Language]]

Selecting a provider for a production system often comes down to cost per token at the target quality level. The tradeoffs between frontier model accuracy, open-weight model hosting cost, and local model latency are central to the economics of LLM feature deployment.

[[llm-cost-optimization|LLM Cost Optimization]]

---

## Common Misconceptions

Misconception 1: "I can swap providers by just changing the model string."
Reality: This works if you are using LiteLLM or a LangChain wrapper, but not if you are calling provider SDKs directly. Anthropic's SDK uses a different client class, a different method name (`messages.create` vs `chat.completions.create`), and a different system prompt convention. Google's SDK has its own entirely separate structure. A direct port requires rewriting the calling code for each provider unless you have already hidden it behind an abstraction layer.

Misconception 2: "Local models via Ollama are free to run."
Reality: Local models are free in API costs but not in infrastructure costs. Running a 70B model requires 40 - 48 GB of VRAM across one or more GPUs. An 8B model requires approximately 6 GB VRAM at full precision or 4 - 5 GB with 4-bit quantization. On a developer laptop, local inference is feasible for small models but impractical for large ones. In a cloud environment, GPU instances cost \$0.50 - \$5.00 per GPU-hour, which can exceed cloud API costs for low-traffic workloads.

Misconception 3: "All providers have the same rate limits."
Reality: Rate limits vary dramatically by tier, model, and metric type. OpenAI's Tier 1 (new accounts) may allow only 10,000 requests per day on GPT-4o. Anthropic tracks requests per minute, tokens per minute, and tokens per day separately. Hitting any one of these triggers a 429 error. Building a production system requires implementing exponential backoff with jitter, and designing around rate limits often means batching requests or distributing across multiple API keys.

---

## Why It Matters in Practice

The choice of provider has long-term consequences that go beyond which model scores best on benchmarks. Data residency and privacy requirements often eliminate certain providers entirely  -  HIPAA workloads cannot send patient data to an API without a Business Associate Agreement, and European data regulations may require models deployed in specific geographic regions. This frequently pushes teams toward either Google Vertex AI (which offers data residency guarantees) or self-hosted open-weight models. The cost difference between frontier APIs and self-hosted open models can be an order of magnitude at high volume, but the engineering cost of hosting, monitoring, and updating local models must be factored into the comparison.

Abstraction layers like LiteLLM or LangChain's chat model wrappers pay for themselves when provider changes are likely. A team that starts with OpenAI and later needs to add Anthropic as a fallback, or experiment with a cost-optimized open model for simpler tasks, can do so by changing a model string rather than rewriting integration code. The pattern of routing different task types to different models  -  a cheap fast model for classification and routing, an expensive frontier model for complex reasoning  -  is called model routing or LLM cascading, and it is only practical if the calling code is provider-agnostic.

---

## Interview Angle

Common question forms:
- "How would you design a system that works with multiple LLM providers?"
- "What are the tradeoffs between hosted APIs and self-hosted open models?"
- "How do you handle rate limits from LLM APIs?"

Answer frame: Describe the abstraction layer pattern (LiteLLM or LangChain wrappers) to achieve provider independence. Cover cost, data privacy, and capability tradeoffs between frontier APIs and open-weight local models. For rate limits: 429 handling with exponential backoff and jitter, per-minute versus per-day limit awareness, and architectural solutions like request queuing or multi-key distribution. Mention that Ollama enables OpenAI-compatible local inference, making provider switching in development nearly frictionless.

---

## Related Notes

- [[llm-basics|How LLMs Work]]
- [[context-window|Context Window]]
- [[lcel|LangChain Expression Language]]
- [[llm-cost-optimization|LLM Cost Optimization]]
- [[ai-observability|AI Observability]]
