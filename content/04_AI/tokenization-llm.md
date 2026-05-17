---
title: Tokenization in LLMs
description: "Tokenization splits text into tokens — subword units (not words or characters) that the model processes; `tiktoken` is OpenAI's tokenizer; token count drives cost and context window usage; a word is typically 1-3 tokens; non-English text often uses more tokens per word."
tags: [tokenization, tokens, tiktoken, BPE, byte-pair-encoding, context-window, layer-4, ai]
status: draft
difficulty: beginner
layer: 4
domain: ai
created: 2026-05-17
---

# Tokenization in LLMs

> Tokenization splits text into tokens — subword units (not words or characters) that the model processes; `tiktoken` is OpenAI's tokenizer; token count drives cost and context window usage; a word is typically 1-3 tokens; non-English text often uses more tokens per word.

---

## Quick Reference

**Core idea:**
- **Token**: the basic unit of LLM input/output — neither a word nor a character; a subword piece
- Common English word ≈ 1 token; uncommon word may be 2-4 tokens; single character may be 1 token
- `tiktoken` — OpenAI's tokenization library; fast BPE tokenizer; works for GPT and Claude models (approximately)
- Token count determines: API cost (pricing per token), context window usage, response length
- Vocabulary size: GPT-4 uses ~100k token vocabulary; Claude similar

**Tricky points:**
- Spaces are often part of tokens — `" hello"` (with space) and `"hello"` (without) may be different tokens
- Code uses more tokens per character than prose — special characters (`{}`, `()`, `->`) often get their own tokens
- Numbers are often tokenized digit-by-digit or in short groups: `"12345"` might be `["123", "45"]`
- Non-ASCII text (Chinese, Arabic, emoji) uses more tokens per character than English
- Token counting must happen before the API call — the API rejects requests that exceed context limit

---

## What It Is

LLMs don't process characters or words — they process tokens. Tokenization is the preprocessing step that converts raw text into a sequence of token IDs from a fixed vocabulary. The model is trained on these token sequences and generates new tokens one at a time.

Byte Pair Encoding (BPE) is the most common tokenization algorithm: it starts with individual bytes, then iteratively merges the most frequent pairs into new tokens, building a vocabulary of common subwords. This balances vocabulary coverage (no out-of-vocabulary words) with efficiency (common words = 1 token, rare words = multiple tokens).

Understanding tokenization matters for: estimating API costs before sending requests, fitting content into context windows, and understanding why some text is harder for the model (heavily tokenized input is harder to reason about).

---

## How It Actually Works

Using `tiktoken`:
```python
import tiktoken

# claude-3 uses a similar but not identical tokenizer; tiktoken is an approximation
enc = tiktoken.encoding_for_model("gpt-4o")

text = "Hello, how are you today?"
tokens = enc.encode(text)
print(tokens)   # [9906, 11, 1268, 527, 499, 3432, 30]
print(len(tokens))  # 7

# Decode back:
enc.decode(tokens)  # "Hello, how are you today?"

# Count tokens for different text types:
code = "def fibonacci(n): return n if n <= 1 else fibonacci(n-1) + fibonacci(n-2)"
print(len(enc.encode(code)))  # ≈ 25 tokens for ~70 characters
```

Practical token estimation:
```python
def estimate_tokens(text: str) -> int:
    """Rough estimate: ~4 characters per token for English."""
    return len(text) // 4

def count_tokens_tiktoken(text: str, model: str = "gpt-4o") -> int:
    enc = tiktoken.encoding_for_model(model)
    return len(enc.encode(text))
```

Token budget for Claude API:
```python
import anthropic

client = anthropic.Anthropic()

# Count tokens before sending (avoids rejected requests):
response = client.messages.count_tokens(
    model="claude-sonnet-4-6",
    messages=[{"role": "user", "content": my_prompt}],
)
print(response.input_tokens)  # exact token count

# Only send if within budget:
if response.input_tokens < 180_000:  # Claude's context window
    message = client.messages.create(...)
```

---

## How It Connects

Token count determines how much text fits in the context window — understanding tokens is required to reason about context limits.
[[context-window|Context Window]]

Chunking strategies for RAG split documents at token boundaries, not word boundaries, to maximize information density per chunk.
[[chunking-strategies|Chunking Strategies]]

---

## Common Misconceptions

Misconception 1: "Tokens are words."
Reality: Tokens are subword units. "tokenization" might be 3 tokens: ["token", "ization"] or ["token", "iz", "ation"]. Common short words are usually 1 token; long or rare words split into 2-5 tokens.

Misconception 2: "Counting characters is a good enough estimate."
Reality: Token counts vary significantly by content type. English prose ≈ 4 chars/token. Code ≈ 3 chars/token (more special characters). Chinese/Japanese ≈ 1-2 chars/token (but each char = 1 token). For cost-sensitive applications, use `tiktoken` or the API's token counting endpoint.

---

## Why It Matters in Practice

Cost estimation:
```
Claude Sonnet: ~$3 per 1M input tokens
1000-word article ≈ 1,300 tokens ≈ $0.004
1M tokens ≈ 750,000 words ≈ 3,000 pages
```

For a RAG pipeline processing 10,000 documents at 500 tokens each:
- 5M tokens × $3/1M = $15 per full indexing run
- Token count determines whether to summarize documents before embedding vs. chunk raw text

---

## Interview Angle

Common question forms:
- "What is a token in the context of LLMs?"
- "How do you estimate the cost of an API call?"

Answer frame: Tokens are subword units from a fixed vocabulary — roughly 1 word = 1 token for common English words; rare words or non-English text use more. BPE is the tokenization algorithm. Cost = input tokens + output tokens × price per token. Use `tiktoken` or the API's count endpoint before sending expensive requests. Token limits determine what fits in the context window.

---

## Related Notes

- [[llm-basics|How LLMs Work]]
- [[context-window|Context Window]]
- [[chunking-strategies|Chunking Strategies]]
- [[prompt-engineering|Prompt Engineering]]
