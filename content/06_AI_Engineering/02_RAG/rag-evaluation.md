---
title: 04 - RAG Evaluation
description: "how to measure RAG pipeline quality using faithfulness, answer relevance, and context precision/recall  -  covering RAGAS, LLM-as-judge, automated vs human eval, and tracing with LangSmith"
tags: [rag, evaluation, ragas, faithfulness, relevance, langsmith, llm-judge, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# RAG Evaluation

> Measuring RAG pipeline quality requires decomposing "did it answer well?" into distinct, independently measurable signals  -  faithfulness, relevance, and retrieval precision  -  because a pipeline can fail at any stage without revealing which stage caused the failure.

---

## Quick Reference

**Core idea:**
- **Faithfulness**: does the answer contain only claims that are supported by the retrieved context? (Measures hallucination)
- **Answer relevance**: is the generated answer actually responsive to the user's question? (Measures relevance of output)
- **Context precision**: of the retrieved chunks, what fraction were actually useful for answering? (Measures retrieval noise)
- **Context recall**: of all the information needed to answer, what fraction was present in the retrieved chunks? (Measures retrieval coverage)
- **RAGAS** (`ragas` library): `evaluate(dataset, metrics=[faithfulness, answer_relevancy, context_precision, context_recall])`  -  uses an LLM to score each metric automatically
- **LangSmith** tracing: wraps chain invocations and records prompt, retrieved docs, response, latency, and token count per step

**Tricky points:**
- A pipeline with high faithfulness but low context recall is answering only based on what it retrieved  -  but retrieval is missing key information, so answers are incomplete
- LLM-as-judge scores are calibrated to a particular judge model  -  changing the evaluator model (e.g., from `gpt-4o` to `gpt-4o-mini`) produces systematically different scores even on the same data
- Human eval and automated eval often disagree on edge cases  -  automated metrics optimize for measurable proxies, not the nuanced judgment a domain expert applies
- RAGAS `context_recall` requires a reference answer in the dataset  -  it measures whether the retrieved context contains the information present in the ground truth, not whether the answer is correct
- Evaluation datasets built from production logs can be biased toward queries the pipeline already handles well  -  adversarial or edge-case queries must be added deliberately

---

## What It Is

Evaluating a RAG pipeline is like auditing a research assistant who both finds sources and writes summaries from them. You need to check two separate things: did they find the right sources, and did they faithfully summarize what those sources actually say? A research assistant who finds excellent sources but invents claims not in the papers has a faithfulness problem. One who accurately summarizes what they found, but found the wrong papers, has a retrieval problem. These failures look identical from the final output  -  an inaccurate answer  -  but require completely different fixes.

RAG evaluation formalizes this intuition into a set of metrics, each targeting a specific stage of the pipeline. The four canonical RAGAS metrics map to the two-stage structure of a RAG system. Context precision and context recall evaluate the retrieval stage: did the retriever find relevant chunks, and did it find all the relevant chunks? Faithfulness and answer relevance evaluate the generation stage: did the LLM stay grounded in what was retrieved, and did it actually address the question? Running all four metrics simultaneously tells you exactly where in the pipeline quality is degrading.

The RAGAS framework (Retrieval Augmented Generation Assessment) implements these metrics as LLM-as-judge calls. For faithfulness, it decomposes the generated answer into individual factual claims and asks a judge LLM whether each claim is supported by the provided context chunks. For answer relevance, it generates reverse questions from the answer and checks whether they match the original question. For context precision and recall, it uses the judge LLM to assess relevance of each retrieved chunk against the question and against a reference answer. The entire evaluation pipeline runs programmatically and produces numerical scores between 0 and 1, making it possible to track quality over time as the pipeline evolves.

---

## How It Actually Works

The `ragas` library evaluates from a `Dataset` object with defined column schemas. The dataset must contain `question`, `answer`, `contexts` (a list of retrieved chunk strings), and optionally `ground_truth` (a reference answer for recall metrics). You build this dataset from a set of test questions by running your actual RAG pipeline on each question and recording the inputs and outputs.

```python
from ragas import evaluate
from ragas.metrics import faithfulness, answer_relevancy, context_precision, context_recall
from datasets import Dataset

# Build evaluation dataset from your pipeline runs
data = {
    "question": ["What is the capital of France?", ...],
    "answer": ["The capital of France is Paris.", ...],
    "contexts": [["France is a country in Europe. Paris is its capital city.", ...], ...],
    "ground_truth": ["Paris is the capital of France.", ...],
}
dataset = Dataset.from_dict(data)

result = evaluate(
    dataset,
    metrics=[faithfulness, answer_relevancy, context_precision, context_recall],
    llm=ChatOpenAI(model="gpt-4o"),         # the judge model
    embeddings=OpenAIEmbeddings(),           # used by answer_relevancy
)
print(result)  # DataFrame with per-question scores
```

LLM-as-judge evaluation is the dominant approach for RAG because ground-truth labeling at scale is expensive. A judge LLM receives the question, the retrieved context, and the generated answer, then scores the interaction according to a rubric specified in the prompt. The reliability of this approach depends heavily on the judge model's capability and on the rubric's precision. Using `gpt-4o` as judge and keeping the judge model constant across evaluation runs is essential for comparing scores meaningfully. Positional bias (where the judge scores the first option higher regardless of quality) is a documented failure mode  -  mitigated by randomizing the order of options in pairwise evaluation and by averaging multiple judge passes.

LangSmith tracing instruments evaluation at the trace level. When you add `@traceable` decorators or run LangChain chains with the LangSmith endpoint configured, every step of the RAG pipeline  -  the retrieval call, the prompt construction, the LLM generation  -  is recorded as a nested span with timing, token counts, and input/output data. You can then attach evaluation feedback (either automated RAGAS scores or human annotations) to specific traces, building a dataset of labeled production interactions that becomes the foundation for regression testing. The `langsmith` SDK exposes `client.create_feedback(run_id, key="faithfulness", score=0.87)` for programmatic score attachment.

---

## How It Connects

The retrieval quality metrics (context precision and recall) evaluate the output of the retrieval stage directly. Understanding what a retriever returns, how similarity search is scored, and why certain chunks rank above others is prerequisite knowledge for interpreting why retrieval metrics are low and how to fix them.

[[retrieval-strategies|Retrieval Strategies]]

LangSmith tracing is the operational complement to RAGAS scoring: RAGAS tells you the aggregate quality of the pipeline on a test set, while LangSmith traces show you what happened on individual production queries. Together they form the monitoring and debugging layer for a deployed RAG system.

[[langsmith|LangSmith]]

Advanced RAG techniques like query rewriting, HyDE, and parent-document retrieval are the interventions you apply when evaluation reveals specific failure modes  -  low context recall typically signals a retrieval problem that these techniques address.

[[advanced-rag|Advanced RAG Patterns]]

---

## Common Misconceptions

Misconception 1: "If the answer looks correct to me, the pipeline is fine."
Reality: Manual spot-checking does not reveal systematic failure modes. A pipeline might score 0.95 faithfulness on common queries and 0.3 on edge cases that never appear in casual testing. Systematic evaluation on a diverse dataset, including adversarial and out-of-distribution queries, is the only way to characterize pipeline reliability. The RAGAS framework exists precisely because human review does not scale to hundreds of test cases.

Misconception 2: "RAGAS scores are objective ground truth."
Reality: RAGAS scores are judge-LLM opinions, not ground truth. Different judge models produce different scores on the same pipeline. Scores can be gamed by making the answer verbose and repeating the context verbatim (which increases faithfulness scores while reducing answer quality for a user). Treat RAGAS scores as relative metrics for comparing pipeline variants  -  a pipeline with faithfulness 0.85 is better than one with 0.60 on the same dataset and judge model  -  not as absolute quality certificates.

Misconception 3: "Evaluation is a one-time task before deployment."
Reality: RAG pipeline quality degrades as the underlying document corpus changes, as the LLM provider updates the model, and as user query distributions shift. Evaluation must be continuous  -  a scheduled job that runs the full evaluation suite against a fixed test set and alerts when any metric drops below a threshold. LangSmith datasets and LangSmith's run comparison features exist to support exactly this continuous evaluation workflow.

---

## Why It Matters in Practice

Without systematic evaluation, RAG pipeline improvements are guesses. A team that rewrites their chunking strategy, changes their embedding model, and adds a reranker simultaneously cannot attribute any quality change to any specific change. Running RAGAS on a fixed test set before and after each individual change produces measurable, attributable deltas  -  turning RAG improvement from an art into a scientific process. The four metrics give different signals: if context recall is low, the problem is in the retriever; if faithfulness is low, the problem is in the generation prompt or the model; if context precision is low, the retrieved documents are noisy and a reranker would help.

In regulated industries  -  healthcare, legal, finance  -  faithfulness is not an optional quality metric but a compliance requirement. An LLM that generates claims not present in the retrieved documents is hallucinating, and those hallucinations can constitute misinformation in patient-facing or legal document contexts. Building faithfulness evaluation into CI/CD pipelines  -  blocking deployment if faithfulness drops below a threshold on a curated test set  -  is the technical mechanism for enforcing this requirement.

---

## Interview Angle

Common question forms:
- "How would you evaluate the quality of a RAG pipeline?"
- "What is the difference between faithfulness and answer relevance?"
- "How do you know if your retriever is the weak point in your RAG system?"

Answer frame: Describe the four RAGAS metrics and which pipeline stage each targets. Faithfulness measures grounding (generation stage), answer relevance measures responsiveness (generation stage), context precision measures retrieval noise (retrieval stage), context recall measures retrieval coverage (retrieval stage). Explain LLM-as-judge limitations: judge model dependency, inability to detect systematic bias. Describe the evaluation-as-CI pattern: fixed test set, RAGAS scores tracked per commit, LangSmith traces for production debugging.

---

## Related Notes

- [[rag|RAG]]
- [[rag-pipeline|RAG Pipeline]]
- [[retrieval-strategies|Retrieval Strategies]]
- [[advanced-rag|Advanced RAG Patterns]]
- [[langsmith|LangSmith]]
- [[reranking|Reranking]]
