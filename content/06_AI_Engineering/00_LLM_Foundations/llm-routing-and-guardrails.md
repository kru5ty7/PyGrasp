---
title: 09 - LLM Routing and Guardrails
description: "Multi-model routing sends each request to the model that best balances its capability, latency, and cost needs; guardrails validate inputs and outputs around the model call - together with hallucination mitigation, these are the production-hardening layer of an LLM platform."
tags: [llm, routing, guardrails, hallucination, latency, cost, multi-model, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-07-07
---

# LLM Routing and Guardrails

> A single model call is a demo; a production LLM feature is a pipeline with a router in front, guardrails on both sides, and grounding + evaluation around the model. This note covers the platform layer: routing, guardrails, hallucination mitigation, and the latency/cost budget.

---

## Quick Reference

**Core idea:**
- **Multi-model routing**: match request → model on capability/cost/latency - frontier model (Claude, GPT-4-class) for hard reasoning, small/fast model for classification and extraction, local model (Ollama) for data that must not leave the boundary
- Routing axes: task complexity, latency budget, cost per token, data sensitivity/residency, provider availability (fallback on outage/rate-limit)
- **Guardrails - input side**: prompt-injection screening, PII detection/redaction, topic/scope filters, input length caps
- **Guardrails - output side**: schema validation (Pydantic on structured output), content policy checks, PII leak scan, groundedness check against retrieved context, fallback behavior on failure (retry, safer model, refusal)
- **Hallucination mitigation stack**: ground with RAG → constrain the prompt ("answer only from context, else say you don't know") → validate structured claims against sources → evaluate continuously (faithfulness metrics) → design UX for uncertainty (citations, confidence)
- **Latency/cost levers**: model size, streaming (time-to-first-token), caching (exact + semantic), context length discipline, batch where async is tolerable

**Tricky points:**
- Routing on "complexity" needs a cheap classifier in front - which is itself a small model call; keep it fast or it eats the latency it saves
- Guardrail failures need designed fallbacks - blocking output with no fallback is an outage from the user's perspective
- Hallucination cannot be eliminated - the honest engineering framing is *reducing the rate and bounding the blast radius*, never "solved"
- Provider fallback must account for prompt portability - the same prompt performs differently across models; fallback paths need their own evals

---

## What It Is

Routing exists because model choice is a three-way trade-off (capability, latency, cost) and no single model wins all three for a mixed workload. A support assistant classifying ticket intent doesn't need a frontier model at frontier prices and frontier latency; the summarizer behind a legal review does. A router - rules on task type at minimum, a lightweight complexity classifier when justified - assigns each call the cheapest model that clears the quality bar. Two more axes matter in enterprise settings: data sensitivity (some inputs must route to in-boundary models - the Ollama lane) and availability (provider outage or rate-limit triggers fallback to a second provider, with the caveat that prompts aren't automatically portable across models). Routing through one gateway also centralizes the operational plumbing: keys, retries, spend tracking, audit logs per model lane.

Guardrails are the admission-control of the LLM world: validation on both sides of a fundamentally probabilistic component. Input guards run before spending tokens - prompt-injection heuristics, PII redaction (especially before data crosses a provider boundary), scope filters that keep the internal tool on internal topics. Output guards run before the response reaches a user or a downstream system: structured outputs parsed and schema-validated (Pydantic - retry on violation), content policy applied, and for RAG systems a groundedness check that the answer is actually supported by the retrieved context. The design discipline is the fallback chain: on guard failure, retry with corrective instructions → downgrade to a constrained/safer response → refuse gracefully. A guard with no fallback path converts model flakiness into feature downtime.

Hallucination mitigation is layered, not singular. Grounding via RAG narrows the model's job from "recall" to "synthesize from provided context" - the single biggest lever. Prompt constraints make the escape hatch explicit ("if the context doesn't contain the answer, say so"). Output-side checks catch what grounding misses: citation verification, claim-vs-source checking for high-stakes flows. Continuous evaluation (faithfulness/groundedness metrics, RAGAS-style) turns "seems fine" into a tracked number that gates releases like any other quality metric. And UX absorbs the residual: citations users can check, confidence signals, and human-in-the-loop for consequential actions.

The latency/cost budget shapes every choice above. Cost scales with tokens × model tier; latency with model size and output length. The levers, in rough order of leverage: route to smaller models where quality allows; cache (exact-match first, semantic cache with a similarity threshold second - and mind staleness); stream tokens so perceived latency is time-to-first-token; keep contexts tight (retrieval precision beats stuffing - [[context-window|Context Window]]); batch offline workloads. The platform-engineering framing: these are SLO decisions - "p95 under 2s at under $0.01/request" determines the routing table more than any benchmark does.

---

## How It Actually Works

```python
# The shape of a router + guardrails pipeline (illustrative)
async def handle(request: UserRequest) -> Response:
    # --- input guards ---
    if detect_injection(request.text) or not in_scope(request.text):
        return refuse(request)
    clean_text = redact_pii(request.text)

    # --- route ---
    lane = route(request)   # rules first: task type, sensitivity, latency budget
    # {"claude-fable-5": hard reasoning, "claude-haiku-4-5": classify/extract,
    #  "ollama/local": data must stay in-boundary}

    # --- call with fallback ---
    try:
        raw = await lane.model.generate(clean_text, timeout=lane.slo)
    except (RateLimited, ProviderDown):
        raw = await lane.fallback.generate(clean_text, timeout=lane.slo)

    # --- output guards ---
    try:
        result = OutputSchema.model_validate_json(raw)      # Pydantic gate
    except ValidationError:
        raw = await lane.model.generate(clean_text + REPAIR_PROMPT)
        result = OutputSchema.model_validate_json(raw)       # then fallback/refuse

    if request.grounded and not is_grounded(result, request.context):
        return respond_with_uncertainty(result)              # bounded blast radius
    return result
```

Cost/latency instrumentation per lane - tokens, spend, p95, cache hit rate, guard trip rate - is what makes the routing table tunable rather than folklore.

---

## How It Connects

Grounding and evaluation live in the RAG notes - this note is the layer wrapped around them.

[[rag-pipeline|RAG Pipeline]], [[rag-evaluation|RAG Evaluation]], [[retrieval-strategies|Retrieval Strategies]]

Context discipline and provider trade-offs are foundation-layer material.

[[context-window|Context Window]], [[llm-providers|LLM Providers Comparison]], [[structured-output|Structured Output]]

Schema-gated outputs reuse Pydantic validation mechanics.

[[pydantic|Pydantic]]

Guardrails-as-gates is the same pattern as pipeline and admission policy - validation at the boundary of an untrusted component.

[[cicd-design-questions|CI/CD Design Question Bank]]

---

## Common Misconceptions

Misconception 1: "Route everything to the best model - quality first."
Reality: For classification, extraction, and routine summarization, small models match frontier quality at a fraction of latency and cost. "Best model" is per-task, defined by evals against the quality bar - not by leaderboard rank.

Misconception 2: "Guardrails are a content-safety feature."
Reality: Safety is one guard among several. Schema validation, PII boundaries, groundedness checks, and injection screening are reliability and security engineering - the reason a downstream system can consume LLM output at all.

Misconception 3: "RAG fixes hallucination."
Reality: RAG *reduces* it - the model can still contradict or embellish retrieved context, and retrieval itself can fetch the wrong passage. Hence the layered stack: ground, constrain, verify, measure, and design UX for the residual rate.

---

## Interview Angle

Common question forms:
- "Why route across multiple models?" (resume probe - OpenAI/Claude/Gemini/Ollama)
- "How do your guardrails work - what do they check?"
- "How do you deal with hallucination in production?"

Answer frame:
Routing: the capability/latency/cost triangle plus sensitivity and availability lanes - give the concrete split (frontier for reasoning, small for classification, local for in-boundary data) and the fallback caveat about prompt portability. Guardrails: both sides of the call, with the fallback chain as the design point. Hallucination: layered mitigation ending in measurement - never claim elimination. Anchor in the multi-model routing you actually shipped, and quantify with lane-level cost/latency numbers if you have them.

---

## Related Notes

- [[llm-providers|LLM Providers Comparison]]
- [[context-window|Context Window]]
- [[structured-output|Structured Output]]
- [[rag-pipeline|RAG Pipeline]]
- [[rag-evaluation|RAG Evaluation]]
- [[prompt-engineering|Prompt Engineering]]
