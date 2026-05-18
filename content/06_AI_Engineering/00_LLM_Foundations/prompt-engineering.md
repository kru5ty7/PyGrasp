---
title: 04 - Prompt Engineering
description: "Prompt engineering is the practice of crafting inputs to guide LLM behavior  -  techniques include clear instructions, examples (few-shot), chain-of-thought, role assignment, and structured output requests; better prompts produce more reliable, accurate, and useful responses."
tags: [prompt-engineering, few-shot, chain-of-thought, system-prompt, prompting, layer-4, ai]
status: draft
difficulty: beginner
layer: 4
domain: ai
created: 2026-05-17
---

# Prompt Engineering

> Prompt engineering is the practice of crafting inputs to guide LLM behavior  -  techniques include clear instructions, examples (few-shot), chain-of-thought, role assignment, and structured output requests; better prompts produce more reliable, accurate, and useful responses.

---

## Quick Reference

**Core idea:**
- **System prompt**: persistent instructions that frame all responses  -  role, format, constraints
- **Few-shot examples**: show the model the input-output pattern instead of explaining it
- **Chain-of-thought (CoT)**: instruct the model to "think step by step"  -  dramatically improves reasoning accuracy
- **Structured output**: request JSON, XML, or specific formats  -  combine with Pydantic parsing
- **Temperature**: lower (0.0-0.3) for factual/deterministic tasks; higher (0.7-1.0) for creative tasks

**Tricky points:**
- Instruction clarity matters more than length  -  a concise clear instruction often beats a long vague one
- Negative instructions ("don't do X") are less reliable than positive ones ("do Y instead")  -  models attend to what they should do
- Few-shot examples must be representative  -  a poor example teaches the wrong pattern and is worse than no example
- CoT reasoning is in the output tokens  -  it costs tokens; for simple tasks it wastes money; for complex reasoning it's worth it
- Prompt injection: user-provided content that contains instructions can override your system prompt  -  sanitize user input and use defensive prompting

---

## What It Is

An LLM's behavior is entirely determined by its training and its input. Prompt engineering shapes the input to steer the output toward the desired behavior. It's empirical  -  there's no single "correct" prompt; you iterate based on observed outputs.

The most important insight: LLMs are pattern-completing systems. They continue patterns from training data. If your prompt looks like the beginning of a high-quality technical explanation, the completion will look like a high-quality technical explanation. Prompts that look like low-effort requests get low-effort completions.

---

## How It Actually Works

System prompt structure:
```
You are a [role] that [core task].

[Context: relevant background the model needs]

[Format: how to structure the output]

[Constraints: what to avoid or require]

[Examples: if few-shot examples help]
```

Few-shot examples:
```python
system = """Extract the sentiment and key entities from customer reviews.

Format: {"sentiment": "positive|negative|neutral", "entities": [...]}

Examples:
Input: "The laptop arrived quickly but the battery dies in 2 hours."
Output: {"sentiment": "negative", "entities": ["laptop", "battery"]}

Input: "Amazing camera quality, worth every penny!"
Output: {"sentiment": "positive", "entities": ["camera"]}"""
```

Chain-of-thought:
```python
# Without CoT  -  unreliable on math
prompt = "Is 17 * 23 prime? Answer yes or no."

# With CoT  -  reliable
prompt = """Is the result of 17 * 23 a prime number?
First calculate the result, then check if it's prime. Show your reasoning."""
```

Structured output with JSON schema:
```python
from anthropic import Anthropic
import json

client = Anthropic()

response = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    system="You extract structured data. Always respond with valid JSON.",
    messages=[{
        "role": "user",
        "content": f"""Extract from this text:
{text}

Respond with JSON matching:
{{"name": string, "date": "YYYY-MM-DD", "amount": number}}"""
    }]
)

data = json.loads(response.content[0].text)
```

---

## How It Connects

Structured outputs pair with Pydantic  -  the model generates JSON that is then validated by a Pydantic model.
[[structured-output|Structured Output]]

Temperature and sampling parameters control the randomness of the output  -  important for balancing creativity vs. consistency.
[[temperature-and-sampling|Temperature and Sampling]]

---

## Common Misconceptions

Misconception 1: "More detailed prompts always produce better results."
Reality: Long prompts with contradictory instructions confuse models. Clarity beats length. Remove instructions that don't add constraints  -  redundant text dilutes signal-to-noise ratio.

Misconception 2: "Chain-of-thought makes the model smarter."
Reality: CoT doesn't give the model new capabilities  -  it encourages the model to use its existing capabilities more deliberately. For tasks the model fundamentally can't do (requires external data, exceeds knowledge cutoff), CoT doesn't help.

---

## Why It Matters in Practice

Iterative prompting workflow:
```
1. Start simple: minimal prompt, test on diverse examples
2. Identify failure modes: what cases does it get wrong?
3. Add targeted instructions: address specific failure modes
4. Test regression: ensure fixes don't break passing cases
5. Evaluate systematically: a small labeled test set is worth more than vibe-checking
```

The highest-impact prompting technique for reliability is **structured output**  -  instead of asking the model to format its response in prose, ask for JSON and parse it. This gives you machine-readable output that fails loudly if malformed rather than silently if the prose format varies.

---

## Interview Angle

Common question forms:
- "What is prompt engineering?"
- "What is chain-of-thought prompting?"

Answer frame: Prompt engineering = crafting inputs to guide LLM outputs. Key techniques: system prompt (role + constraints), few-shot examples (show the pattern), chain-of-thought ("think step by step" for reasoning), structured output (JSON for parseable results). Temperature: low for factual, high for creative. Iterate: identify failure modes -> add targeted instructions -> test regression.

---

## Related Notes

- [[llm-basics|How LLMs Work]]
- [[structured-output|Structured Output]]
- [[temperature-and-sampling|Temperature and Sampling]]
- [[function-calling|Function Calling]]
