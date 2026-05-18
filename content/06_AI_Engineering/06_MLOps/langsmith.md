---
title: 11 - LangSmith
description: "tracing LangChain and LangGraph runs in production, building evaluation datasets from traced interactions, and integrating evaluation with deployment  -  LangSmith as the observability and evaluation platform for LangChain applications"
tags: [langsmith, tracing, evaluation, datasets, langchain, langgraph, mlops, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# LangSmith

> LangSmith is the observability and evaluation platform purpose-built for LangChain applications  -  it turns the opaque sequence of LLM calls, retrieval steps, and tool invocations inside a chain into a navigable, debuggable trace tree, and connects that production data back into the evaluation pipeline.

---

## Quick Reference

**Core idea:**
- Auto-instrumentation: set `LANGCHAIN_TRACING_V2=true` and `LANGCHAIN_API_KEY`  -  all LangChain/LangGraph runs emit traces automatically, zero code change required
- `LANGCHAIN_PROJECT`: environment variable that routes traces to a named project  -  use separate projects for development, staging, and production
- **Dataset**: a named collection of (input, output) examples in LangSmith  -  created manually, from traces, or via the SDK; used as the test set for evaluations
- **Evaluation**: `langsmith.evaluate(target_fn, data="dataset-name", evaluators=[...])`  -  runs `target_fn` on each dataset example, scores results with evaluators
- `@traceable` decorator: manually instrument non-LangChain code  -  `from langsmith import traceable; @traceable(run_type="chain")`
- `client.create_feedback(run_id, key, score, comment)`: attach a score or annotation to any trace from code or the UI

**Tricky points:**
- LangSmith traces include the full prompt text sent to the LLM and the full response  -  any PII in user queries is stored on LangSmith servers; review data governance requirements before enabling in production
- `run_type` parameter in `@traceable` controls how the span appears in the trace tree  -  valid values are `"chain"`, `"retriever"`, `"llm"`, `"tool"`, `"embedding"`, `"prompt"`, `"parser"`
- Datasets in LangSmith are versioned but not immutable  -  adding examples to a dataset changes what future evaluations run against; pin to a specific dataset version for regression testing
- The `evaluate()` function runs evaluations synchronously by default and may take several minutes for large datasets  -  use async evaluators for production CI pipelines
- LangSmith's AI-assisted evaluators (LLM-as-judge) consume tokens from the evaluator model on every example  -  a 200-example dataset with a faithfulness evaluator runs 200 additional LLM calls

---

## What It Is

Building a LangChain application and deploying it without LangSmith is like shipping production software without any logging. The application runs, users interact with it, and when something goes wrong  -  a chain produces a nonsensical response, a retriever returns irrelevant documents, an agent loops  -  you have no record of what happened. You know the output was wrong but not which step in the pipeline produced the problem. LangSmith is the logging, tracing, and debugging infrastructure that turns this opacity into visibility.

LangSmith was built by the LangChain team specifically for LangChain and LangGraph applications, and this tight integration is its primary advantage. The tracing is automatic  -  no instrumentation code, no decorator application, no span management. Setting two environment variables before your application starts is sufficient to route all chain execution data to LangSmith. The trace UI renders the nested structure of a LangChain pipeline accurately: a RAG chain shows as a parent span containing a retriever child span, an LLM child span, and a parser child span, each with timing, inputs, and outputs. For LangGraph graphs, the trace shows each node invocation as a separate span within the graph execution, making it possible to see exactly which node received which state and what it returned.

The evaluation system is the second major capability. LangSmith allows you to create a dataset  -  a collection of (input, expected output) pairs  -  and run any function against that dataset with evaluators that score each example. The evaluators can be simple string comparators, LLM-as-judge prompts, or custom Python functions. Running the same evaluation against multiple versions of a chain provides the comparison data needed to make deployment decisions. The integration between tracing and evaluation is the defining feature: production traces can be added to evaluation datasets with one click in the UI, turning real user queries that revealed failures into regression test cases.

---

## How It Actually Works

Auto-instrumentation requires two environment variables and no code changes to existing LangChain code. The `LANGCHAIN_PROJECT` variable routes traces to a named project, allowing separation of development, staging, and production trace streams.

```bash
# Set in .env or shell environment
LANGCHAIN_TRACING_V2=true
LANGCHAIN_API_KEY=ls__...
LANGCHAIN_PROJECT=production-rag-v2
```

With these variables set, any LangChain chain or LangGraph graph call automatically emits a trace. The trace includes every nested call: retriever invocations, prompt templates, LLM calls (with the full formatted prompt and response), output parser calls, and tool invocations.

For custom Python functions that are not LangChain objects, the `@traceable` decorator creates a span in the current trace context. The decorator accepts `run_type` to classify the span and `name` to label it.

```python
from langsmith import traceable
from openai import OpenAI

client = OpenAI()

@traceable(run_type="retriever", name="vector-store-retrieval")
def retrieve(query: str, k: int = 5) -> list[dict]:
    results = vectorstore.similarity_search(query, k=k)
    return [{"page_content": r.page_content, "metadata": r.metadata} for r in results]

@traceable(run_type="llm", name="openai-generation")
def generate(prompt: str) -> str:
    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": prompt}],
    )
    return response.choices[0].message.content

@traceable(run_type="chain", name="rag-pipeline")
def answer_question(question: str) -> str:
    docs = retrieve(question)
    context = "\n\n".join(d["page_content"] for d in docs)
    prompt = f"Answer based on this context:\n{context}\n\nQuestion: {question}"
    return generate(prompt)
```

Creating and running evaluations uses the `langsmith` client and the `evaluate()` function. The target function is the pipeline under evaluation  -  it receives one example from the dataset and returns an output. Evaluators receive the example's inputs, the pipeline's output, and optionally the reference output, and return a score.

```python
from langsmith import Client
from langsmith.evaluation import evaluate, LangChainStringEvaluator

ls_client = Client()

# Create a dataset from manually curated examples
dataset = ls_client.create_dataset("rag-regression-v1")
ls_client.create_examples(
    inputs=[{"question": "What is the return policy?"}, ...],
    outputs=[{"answer": "30 days, no questions asked."}, ...],
    dataset_id=dataset.id,
)

# Run evaluation
results = evaluate(
    lambda example: answer_question(example["question"]),
    data="rag-regression-v1",
    evaluators=[
        LangChainStringEvaluator("cot_qa"),  # chain-of-thought QA correctness
    ],
    experiment_prefix="gpt-4o-rag-v2",
)
print(results.to_pandas())
```

Adding traces to datasets from the UI requires only selecting a production trace that represents an interesting case and clicking "Add to Dataset." This converts a production failure or edge case into a permanent regression test. The `client.create_examples(inputs=[...], source_run_id=run_id)` API does the same programmatically, enabling automated harvesting of production traces based on quality score thresholds.

---

## How It Connects

LangSmith's tracing covers the observability layer of LangChain/LangGraph applications; AI observability more broadly includes non-LangChain applications, using OpenTelemetry-based tools like Phoenix. LangSmith and Phoenix occupy the same space but with different scope  -  LangSmith is LangChain-native, Phoenix is framework-agnostic.

[[ai-observability|AI Observability]]

LangSmith's evaluation system runs the same metrics as RAGAS (faithfulness, answer relevance) but integrated with production trace data. Understanding the RAGAS metric definitions is prerequisite to interpreting LangSmith evaluation results correctly.

[[rag-evaluation|RAG Evaluation]]

LangGraph graphs emit traces to LangSmith with each node as a separate span. Debugging a multi-agent LangGraph system  -  understanding which node made which decision, what state it received, and what it emitted  -  is primarily done through LangSmith traces.

[[langgraph-core|LangGraph Core]]

---

## Common Misconceptions

Misconception 1: "LangSmith is only useful for debugging, not for production monitoring."
Reality: LangSmith is used for three distinct purposes in a production system: debugging (inspect individual failing traces), monitoring (aggregate metrics  -  error rate, latency distribution, cost per project), and evaluation (run quality scores against datasets). The production monitoring use case is the one that delivers the most continuous value  -  a dashboard showing cost trends, latency p95, and quality score changes over time enables proactive detection of regressions before users report them.

Misconception 2: "Setting `LANGCHAIN_TRACING_V2=true` is all I need to do for LangSmith."
Reality: Without `LANGCHAIN_PROJECT` set, all traces go to the default project  -  mixing development, staging, and production traces in one place makes the UI unusable. Without `LANGCHAIN_TRACING_V2` set for workers in async or Celery-based deployments, traces from background tasks may not be captured. In multi-threaded FastAPI deployments, the trace context must be propagated correctly  -  LangChain handles this automatically for LangChain chains but custom code using `@traceable` must be called within an existing trace context to appear as child spans.

---

## Why It Matters in Practice

LangSmith's most practical value is compressing the time from "something is wrong with my AI feature" to "I know exactly what changed and why." Without LangSmith, diagnosing a quality regression in a RAG pipeline after a prompt change involves writing one-off logging code, re-running problematic queries, and manually inspecting outputs. With LangSmith, you pull up the traces from before and after the prompt change, diff the retrieved documents and LLM responses side by side, and identify within minutes whether the regression is in retrieval, in the prompt template, or in the model's behavior.

For teams building on LangChain or LangGraph, LangSmith is effectively required infrastructure rather than optional tooling. The complexity of chained LLM calls  -  where the output of one step becomes the input of the next, and failures cascade silently  -  makes untraced execution genuinely difficult to debug. LangSmith makes the execution transparent at a level that is otherwise impossible to achieve with print statements or standard logging, at the cost only of an API key and two environment variables.

---

## Interview Angle

Common question forms:
- "How do you debug a LangChain application that's giving incorrect responses?"
- "How would you build a continuous evaluation system for a RAG pipeline?"
- "What is LangSmith and how does it relate to production AI systems?"

Answer frame: LangSmith auto-instruments LangChain via environment variables, capturing every span (retriever, LLM, tool) in a nested trace tree. Debugging: pull the failing trace, inspect retrieved documents and formatted prompt. Continuous evaluation: create a LangSmith dataset, run `evaluate()` against it after each code change, alert on score regression. Dataset growth: add production traces that represent edge cases or failures to the evaluation dataset. Three uses: debugging (individual traces), monitoring (aggregate metrics), evaluation (quality scores on datasets).

---

## Related Notes

- [[ai-observability|AI Observability]]
- [[rag-evaluation|RAG Evaluation]]
- [[langchain-basics|LangChain Basics]]
- [[langgraph-core|LangGraph Core]]
- [[llm-cost-optimization|LLM Cost Optimization]]
