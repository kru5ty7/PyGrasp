---
title: 09 - AI Observability
description: "monitoring LLM applications in production by tracing individual calls, logging prompt and response pairs, tracking latency and token costs, and detecting quality degradation  -  using LangSmith and Phoenix as the primary tools"
tags: [observability, tracing, langsmith, phoenix, llm-monitoring, latency, token-cost, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# AI Observability

> AI observability makes the internal state of an LLM application visible in production  -  without it, you know your service is returning 200s and that something is wrong, but you cannot see which prompt, which retrieved document, or which LLM call caused the failure.

---

## Quick Reference

**Core idea:**
- **Trace**: a single end-to-end request through an LLM application  -  contains a tree of nested spans (retrieval, LLM call, tool call, post-processing)
- **Span**: one unit of work within a trace  -  records input, output, start time, end time, model name, token counts, and cost
- **LangSmith**: tracing backend for LangChain/LangGraph applications  -  set `LANGCHAIN_TRACING_V2=true` and `LANGCHAIN_API_KEY` environment variables to auto-instrument all chains
- **Phoenix** (Arize): open-source observability platform with OpenInference tracing standard  -  supports LangChain, LlamaIndex, OpenAI SDK, and custom instrumentation
- **Key metrics**: first-token latency, total latency, input/output token count, cost per call, error rate, and downstream quality score
- **OpenTelemetry**: the underlying standard for spans and traces  -  Phoenix and LangSmith both emit OpenTelemetry-compatible traces; custom instrumentation uses the `opentelemetry` library

**Tricky points:**
- Setting `LANGCHAIN_TRACING_V2=true` sends all chain inputs and outputs  -  including user PII  -  to LangSmith's servers by default; ensure data governance requirements allow this before enabling in production
- Token cost tracking requires knowing the model's per-token price, which changes with model versions  -  both LangSmith and Phoenix maintain price tables but these require manual updates for newly released models
- A trace that shows fast LLM latency but slow overall response time indicates the bottleneck is in retrieval, post-processing, or network  -  the trace tree is the tool for isolating this
- Phoenix's local mode runs an in-memory trace collector  -  suitable for development, but traces are lost on process restart unless you configure a persistent backend
- Sampling is necessary at high traffic volumes  -  tracing 100% of requests at 10,000 requests/minute produces 144 million traces per day; configure a sample rate (1 - 10% for high-traffic endpoints) while keeping 100% trace rate for errors

---

## What It Is

Running an LLM application in production without observability is like flying an aircraft without instruments. The aircraft may be functioning  -  it is moving, it has fuel, passengers are on board  -  but you have no visibility into airspeed, altitude, engine temperature, or heading. A problem developing in the engine is invisible until it becomes a failure. You cannot distinguish "the aircraft is performing optimally" from "the aircraft is about to stall" until it stalls. Observability instruments provide continuous visibility into what the system is actually doing, not just whether it is running.

Traditional software observability  -  measuring request rates, error rates, and latency  -  is necessary but insufficient for LLM applications. An LLM service that returns `200 OK` in 2 seconds is technically healthy but may be producing consistently wrong, harmful, or off-topic answers. The failure mode is semantic rather than structural, and standard infrastructure metrics cannot detect it. AI observability adds a second layer: capturing the actual content of each LLM interaction  -  the prompt sent, the retrieved documents, the model's response  -  and making that content searchable, filterable, and analyzable at scale.

A trace in an LLM application is the complete record of one user request, structured as a tree of spans. For a RAG pipeline, the trace contains at minimum: a retrieval span (input: user query; output: retrieved chunks; duration: time taken by vector search), an LLM span (input: augmented prompt including chunks; output: generated answer; model: which model; tokens: input/output counts; cost: USD amount), and optionally post-processing spans. LangSmith and Phoenix both render this tree visually, allowing you to see for any individual production request exactly what was retrieved, what was sent to the LLM, and what the LLM returned  -  in the format it actually arrived.

---

## How It Actually Works

LangSmith auto-instruments all LangChain and LangGraph runs with two environment variables. Every chain invocation, retriever call, LLM call, and tool call is automatically wrapped in a span and sent to LangSmith's backend. The LangSmith UI shows the trace tree for each run, with timing, token counts, and model information for each span.

```bash
# .env or environment configuration
LANGCHAIN_TRACING_V2=true
LANGCHAIN_API_KEY=ls__...
LANGCHAIN_PROJECT=production-rag
```

For non-LangChain code, LangSmith provides a `@traceable` decorator and a `RunTree` context manager for manual instrumentation. The `@traceable` decorator wraps a function and records its arguments, return value, and execution time as a span.

```python
from langsmith import traceable

@traceable(name="custom-retrieval", run_type="retriever")
def retrieve_documents(query: str, k: int = 5) -> list[str]:
    # Your custom retrieval logic
    results = vectorstore.similarity_search(query, k=k)
    return [doc.page_content for doc in results]
```

Phoenix (Arize) uses the OpenInference tracing standard and integrates with OpenTelemetry. The `openinference-instrumentation-openai` and `openinference-instrumentation-langchain` packages patch the respective SDK clients to automatically emit traces. Phoenix can run as a local server (`px.launch_app()`) for development or as a persistent service.

```python
import phoenix as px
from openinference.instrumentation.openai import OpenAIInstrumentor
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

# Start Phoenix local server
px.launch_app()

# Configure OpenTelemetry to export to Phoenix
provider = TracerProvider()
provider.add_span_processor(
    SimpleSpanProcessor(OTLPSpanExporter(endpoint="http://localhost:6006/v1/traces"))
)
trace.set_tracer_provider(provider)

# Instrument OpenAI SDK  -  all subsequent openai calls are traced
OpenAIInstrumentor().instrument()
```

Cost tracking per span requires knowing the per-token price for the model used. Both LangSmith and Phoenix extract token counts from the API response's `usage` field (which all OpenAI-compatible APIs return) and multiply by the model's known price. The `langchain_community.callbacks.openai_info.OpenAICallbackHandler` context manager provides per-session cost and token tracking for LangChain chains.

```python
from langchain_community.callbacks import get_openai_callback

with get_openai_callback() as cb:
    result = chain.invoke({"question": "What is RAG?"})
    print(f"Tokens used: {cb.total_tokens}")
    print(f"Cost: ${cb.total_cost:.6f}")
```

---

## How It Connects

LangSmith is the production observability layer for LangChain and LangGraph applications. Understanding what LangSmith traces look like, and how to configure datasets and run evaluations from production traces, is a deeper use of the same infrastructure.

[[langsmith|LangSmith]]

AI observability in production extends the evaluation work done in development. RAGAS scores run offline on test sets; production tracing with attached quality feedback creates a continuous stream of labeled examples that can be used to update the evaluation dataset and monitor distribution shift.

[[rag-evaluation|RAG Evaluation]]

LLM cost observability  -  tracking token spend per trace  -  is one input to the cost optimization strategy. Observability reveals which queries are most expensive and which chains are generating the most output tokens, identifying where optimization effort is best directed.

[[llm-cost-optimization|LLM Cost Optimization]]

---

## Common Misconceptions

Misconception 1: "Logging request/response pairs is sufficient for LLM observability."
Reality: Flat request/response logging (like a standard HTTP access log) records the input and output of the full pipeline but does not capture the internal state of each step. A log showing that request X produced a bad response does not tell you whether the bad response came from retrieving the wrong document, from passing a malformed prompt to the LLM, or from the LLM ignoring well-constructed context. Structured tracing  -  with separate spans for each pipeline stage  -  is necessary to identify which step caused the failure.

Misconception 2: "Token counting at the application level is good enough  -  I don't need observability tooling."
Reality: Application-level token counting only captures what you explicitly instrument. Complex pipelines with multiple LLM calls (agent loops, multi-step chains, parallel retrieval) accumulate token usage across many calls that are difficult to aggregate manually. Tracing tools capture token counts at the span level automatically, roll them up to the trace level, and allow cost analysis by project, user, or query type  -  insights that manual logging cannot produce without substantial engineering effort.

---

## Why It Matters in Practice

The first production incident in an LLM application almost always demonstrates the value of observability in retrospect. A chatbot that starts returning incorrect information after a system prompt update, a RAG pipeline that begins hallucinating after a corpus update, an agent that loops indefinitely on certain query types  -  these failures are invisible in standard infrastructure metrics and only diagnosable with trace-level visibility. Teams that invested in observability from the start can pull up the failing traces within minutes, identify the exact prompt, retrieved document, or model response that caused the failure, and fix it with certainty. Teams without observability spend hours or days in uncertainty.

At scale, AI observability is a compliance and debugging infrastructure. Regulations in healthcare (explaining AI medical recommendations), finance (audit trails for AI-assisted decisions), and legal (documentation of AI-generated content) increasingly require evidence of what the AI actually said and why. Traces provide that evidence. Token cost tracking at the trace level enables accurate per-feature or per-user cost attribution, which is necessary for both billing (in B2B SaaS with AI features) and capacity planning (knowing which use cases are disproportionately expensive).

---

## Interview Angle

Common question forms:
- "How would you monitor an LLM application in production?"
- "What is the difference between tracing and logging for LLM apps?"
- "How do you track token costs across a complex agent pipeline?"

Answer frame: Tracing captures the tree of spans within a request  -  each LLM call, retrieval call, and tool call is a span with input, output, timing, and token counts. LangSmith auto-instruments LangChain via environment variables; Phoenix/OpenInference instruments OpenAI and other SDKs. Key metrics: first-token latency, total latency, token counts, cost per trace, error rate. Cost tracking uses the `usage` field from API responses and known per-token prices. Quality monitoring attaches evaluation scores to traces, enabling production quality regression detection.

---

## Related Notes

- [[langsmith|LangSmith]]
- [[llm-cost-optimization|LLM Cost Optimization]]
- [[rag-evaluation|RAG Evaluation]]
- [[model-serving|Model Serving]]
- [[llm-providers|LLM Providers Comparison]]
