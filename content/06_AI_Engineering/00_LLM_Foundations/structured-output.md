---
title: 07 - Structured Output
description: "Structured output extracts machine-readable data from LLM responses  -  achieved via forced tool use, JSON mode, or Pydantic + `instructor` library; more reliable than parsing free-text JSON; enables direct integration of LLM responses into application code."
tags: [structured-output, json-mode, instructor, pydantic, tool-use, extraction, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Structured Output

> Structured output extracts machine-readable data from LLM responses  -  achieved via forced tool use, JSON mode, or Pydantic + `instructor` library; more reliable than parsing free-text JSON; enables direct integration of LLM responses into application code.

---

## Quick Reference

**Core idea:**
- **Forced tool use**: define a tool schema matching your desired output shape; force the model to always call it
- **`instructor` library**: wraps Anthropic/OpenAI APIs; accepts a Pydantic model as `response_model`; handles retries on parse failures
- **JSON mode**: some APIs have a "JSON mode" that guarantees valid JSON output (not Claude's default)
- Always validate the parsed output  -  even structured outputs can have type mismatches or missing fields
- Use `temperature=0` for extraction  -  randomness adds noise to structured data

**Tricky points:**
- Asking the model to "respond in JSON" in the system prompt is unreliable  -  the model may add prose before/after, use single quotes, or omit fields; use forced tool use instead
- `instructor` automatically retries on `ValidationError`  -  the model output is re-fed with the validation error message; works well for recoverable errors
- Complex nested schemas may confuse the model  -  flatten the schema or break extraction into multiple calls
- Don't confuse the tool schema (JSON Schema describing the structure) with the output (the actual values)  -  the schema is in your code, the values come from the model
- For extraction from long documents, chunk the document and aggregate results

---

## What It Is

When application code needs to consume LLM output (route a ticket, update a database, call another API), free-text responses are fragile. A response that says "The invoice total is $1,234.56" requires regex parsing that breaks on format variation. Structured output gives you a Python dict or Pydantic model with typed fields  -  `invoice.total == 1234.56`  -  directly usable by application code.

The most robust approach is forced tool use: the model is required to produce output in a specific JSON schema, same as function calling, but the "function" is your data model rather than an external action.

---

## How It Actually Works

`instructor` library (cleanest approach):
```python
import anthropic
import instructor
from pydantic import BaseModel

client = instructor.from_anthropic(anthropic.Anthropic())

class Invoice(BaseModel):
    invoice_number: str
    date: str
    vendor: str
    line_items: list[dict]
    total: float
    currency: str = "USD"

invoice = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    response_model=Invoice,  # instructor handles tool use + parsing + retries
    messages=[{
        "role": "user",
        "content": f"Extract the invoice data from:\n{raw_invoice_text}"
    }]
)

print(invoice.total)  # 1234.56  -  float, not string
print(invoice.vendor)  # "ACME Corp"
```

Manual forced tool use (no third-party library):
```python
from anthropic import Anthropic
import json
from pydantic import BaseModel

class SentimentResult(BaseModel):
    sentiment: str  # "positive", "negative", "neutral"
    confidence: float  # 0.0 - 1.0
    key_phrases: list[str]

client = Anthropic()

tool = {
    "name": "report_sentiment",
    "description": "Report the sentiment analysis results",
    "input_schema": SentimentResult.model_json_schema()
}

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=512,
    temperature=0,
    tools=[tool],
    tool_choice={"type": "tool", "name": "report_sentiment"},
    messages=[{"role": "user", "content": f"Analyze sentiment: {text}"}]
)

raw = response.content[0].input
result = SentimentResult.model_validate(raw)
print(result.sentiment)  # validated Pydantic model
```

Batch extraction with aggregation:
```python
def extract_from_all(documents: list[str]) -> list[Invoice]:
    results = []
    for doc in documents:
        try:
            invoice = client.messages.create(
                model="claude-sonnet-4-6",
                max_tokens=512,
                response_model=Invoice,
                messages=[{"role": "user", "content": doc}],
            )
            results.append(invoice)
        except Exception as e:
            logger.error(f"Failed to extract: {e}")
    return results
```

---

## How It Connects

Function calling is the underlying mechanism for forced tool use structured output.
[[function-calling|Function Calling]]

Pydantic validates the extracted data  -  the JSON schema for tool use is generated from Pydantic models via `model_json_schema()`.
[[pydantic|Pydantic]]

---

## Common Misconceptions

Misconception 1: "Asking for JSON in the prompt is sufficient."
Reality: Free-text JSON extraction is unreliable  -  the model may include markdown code fences, add explanatory text, use trailing commas, or omit optional fields. Forced tool use constrains the output format at the API level, not just in the prompt.

Misconception 2: "Structured output always gets the right values."
Reality: Structured output guarantees the shape (correct fields, correct types). It doesn't guarantee the values are correct  -  the model still needs good prompting and enough context to extract accurately. A confident hallucinated value looks identical to a correct one.

---

## Why It Matters in Practice

Use cases where structured output is essential:
- **Data extraction**: extract fields from unstructured documents (invoices, contracts, forms)
- **Classification**: categorize text into predefined labels (routing, sentiment, intent)
- **Transformation**: convert one format to another (freetext -> structured record)
- **Evaluation**: LLM-as-judge that returns scores + reasoning in a parseable format

The `instructor` library is the production standard for this  -  automatic retries, Pydantic integration, multi-provider support.

---

## Interview Angle

Common question forms:
- "How do you get structured output from an LLM?"
- "Why is JSON extraction from free text unreliable?"

Answer frame: Free-text JSON prompting is unreliable  -  model may add prose, use wrong format. Forced tool use constrains output to a JSON schema at the API level. `instructor` library wraps the API and accepts a Pydantic `response_model`  -  handles tool use, parsing, and retries. Use `temperature=0` for extraction. Always validate with Pydantic even with structured output.

---

## Related Notes

- [[function-calling|Function Calling]]
- [[pydantic|Pydantic]]
- [[prompt-engineering|Prompt Engineering]]
- [[llm-basics|How LLMs Work]]
