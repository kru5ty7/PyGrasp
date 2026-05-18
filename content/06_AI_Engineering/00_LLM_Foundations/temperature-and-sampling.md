---
title: 05 - Temperature and Sampling
description: "Temperature controls LLM output randomness  -  0.0 is near-deterministic (always the most likely token), 1.0 is normal sampling; `top_p` and `top_k` are alternative sampling parameters; lower temperature for factual/code tasks, higher for creative tasks."
tags: [temperature, sampling, top-p, top-k, greedy-decoding, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Temperature and Sampling

> Temperature controls LLM output randomness  -  0.0 is near-deterministic (always the most likely token), 1.0 is normal sampling; `top_p` and `top_k` are alternative sampling parameters; lower temperature for factual/code tasks, higher for creative tasks.

---

## Quick Reference

**Core idea:**
- `temperature=0.0`  -  greedy decoding; always picks the most probable token; deterministic (mostly)
- `temperature=1.0`  -  sample from the probability distribution as-is; default for most models
- `temperature>1.0`  -  amplify low-probability tokens; more random/creative (rare to use above 1.5)
- `top_p` (nucleus sampling): sample only from tokens that together account for the top P% of probability mass
- `top_k`: limit sampling to the top K most likely tokens

**Tricky points:**
- Temperature 0.0 is NOT perfectly deterministic  -  floating point non-associativity and hardware differences can cause occasional variation at the most likely token boundary; for true reproducibility, use `top_k=1`
- Increasing temperature does NOT improve reasoning accuracy  -  it just makes the model more willing to explore lower-probability completions; for reasoning, use CoT instead
- `top_p` and `temperature` are often used together  -  Anthropic's recommended defaults: temperature=1.0, no top_p modification unless needed
- Temperature affects diversity of outputs, not quality  -  for data extraction/classification, temperature=0 to minimize hallucination; for story generation, temperature=0.8-1.0 for variety
- "Best of N" sampling: generate N outputs at higher temperature, then select the best  -  more expensive but can improve quality for generation tasks

---

## What It Is

At each step, an LLM outputs a probability distribution over its vocabulary  -  the next token could be any of 100k+ tokens, each with some probability. Temperature is a scaling factor applied to these probabilities before sampling. Low temperature makes the distribution sharper (winner takes more); high temperature flattens it (more tokens become plausible).

Think of it as confidence vs. exploration:
- Temperature 0: "I'll always say the most confident thing"
- Temperature 1: "I'll sample proportionally from my beliefs"
- Temperature 2: "I'm willing to say surprising things"

---

## How It Actually Works

How temperature transforms probabilities:
```python
import numpy as np

# Raw logits from the model:
logits = np.array([2.0, 1.0, 0.5, 0.1])

def softmax_with_temperature(logits, temp):
    scaled = logits / temp
    exp = np.exp(scaled - np.max(scaled))  # numerical stability
    return exp / exp.sum()

# Low temperature -> confident
print(softmax_with_temperature(logits, 0.1))
# [0.9997, 0.0002, 0.0001, 0.0000]  <- almost always picks token 0

# Default temperature -> balanced
print(softmax_with_temperature(logits, 1.0))
# [0.6007, 0.2207, 0.1336, 0.0450]  <- samples proportionally

# High temperature -> exploratory
print(softmax_with_temperature(logits, 2.0))
# [0.4149, 0.2449, 0.2000, 0.1401]  <- flatter, more token variety
```

Using in Claude API:
```python
import anthropic

client = anthropic.Anthropic()

# Factual extraction  -  deterministic
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=512,
    temperature=0.0,
    messages=[{"role": "user", "content": "Extract all dates from: " + document}]
)

# Creative writing  -  more variety
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    temperature=0.9,
    messages=[{"role": "user", "content": "Write a short story about a robot."}]
)
```

`top_p` (nucleus sampling):
```python
# Only sample from tokens that together make up 90% of probability mass
response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=512,
    temperature=1.0,
    top_p=0.9,  # ignore the long tail of low-probability tokens
    messages=[...]
)
```

---

## How It Connects

Temperature is one of the key parameters in the Claude API and affects output quality for different tasks.
[[llm-basics|How LLMs Work]]

Prompt engineering and temperature work together  -  a good system prompt with low temperature gives consistent, reliable outputs.
[[prompt-engineering|Prompt Engineering]]

---

## Common Misconceptions

Misconception 1: "Temperature 0 gives the same output every time."
Reality: Temperature 0 approaches determinism but floating-point arithmetic and batch processing may cause rare variations. For truly reproducible outputs, you'd need `top_k=1` and identical hardware/software  -  in practice, temperature 0 is reliable enough for most uses.

Misconception 2: "Higher temperature makes the model smarter or more creative in a meaningful way."
Reality: Temperature just changes which tokens the model is willing to sample. It doesn't add knowledge or improve reasoning  -  it makes the model explore lower-probability completions, which can produce novel outputs or more garbage, depending on the task.

---

## Why It Matters in Practice

Task -> temperature guide:
```
Data extraction, SQL generation, code completion: 0.0 - 0.2
Question answering over documents:                0.0 - 0.3
Summarization:                                    0.3 - 0.5
General conversation:                             0.7 - 1.0
Creative writing, brainstorming:                  0.8 - 1.0
Poetry, highly creative:                          1.0 - 1.2
```

For classification/extraction tasks with structured output: always use low temperature. A "creative" extraction is a hallucinated extraction.

---

## Interview Angle

Common question forms:
- "What does temperature do in an LLM?"
- "When would you use a higher temperature?"

Answer frame: Temperature scales the probability distribution of the next token  -  0 = always pick the most likely (deterministic), 1 = sample proportionally, higher = explore low-probability tokens. Low temperature for factual/code/extraction tasks (minimize hallucination). High temperature for creative/diverse outputs. `top_p`: sample from the top P% of probability mass (alternative to temperature). Use `top_p` or temperature, rarely both.

---

## Related Notes

- [[llm-basics|How LLMs Work]]
- [[prompt-engineering|Prompt Engineering]]
- [[structured-output|Structured Output]]
