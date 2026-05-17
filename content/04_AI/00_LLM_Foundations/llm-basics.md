---
title: 01 - LLM Basics
description: Large language models are transformer-based neural networks trained to predict the next token in a sequence — understanding tokens, context windows, temperature, and the completion API is the foundation for everything built on top of them.
tags: [llm, language-model, tokens, transformer, completions, prompt, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# LLM Basics

> Large language models are transformer-based neural networks trained to predict the next token in a sequence — understanding tokens, context windows, temperature, and the completion API is the foundation for everything built on top of them.

---

## Quick Reference

**Core idea:**
- An LLM takes a sequence of **tokens** as input and outputs a probability distribution over the next token — generation is repeated sampling from this distribution
- **Tokens** are subword units, not characters or words: "tokenization" → 3–4 tokens; the exact mapping depends on the tokenizer (BPE is common)
- **Context window** (measured in tokens) is the maximum total input + output the model can process; exceeding it truncates or raises an error
- **Temperature** controls randomness: `0` makes the model deterministic (always picks highest probability token); higher values increase diversity but reduce coherence
- The **completion API** (and chat API) is stateless — the entire conversation history must be resent on every call; the model has no memory between API calls
- **Streaming** returns tokens as they are generated rather than waiting for the full completion — enabled by SSE (Server-Sent Events) over HTTP

**Tricky points:**
- Token count ≠ word count — code, JSON, and non-English text are generally more tokens per character than plain English prose
- **System prompt**, user messages, and assistant responses all consume context window tokens — long conversation histories eat into available output space
- Temperature `0` is not truly deterministic in practice — floating point arithmetic variations across hardware can produce occasional differences
- The model does not "know" what you said before in a previous API call — stateless means stateless; multi-turn conversations require resending the full message history every time
- **Top-p** (nucleus sampling) is an alternative to temperature: sample from the smallest set of tokens whose cumulative probability exceeds p

---

## What It Is

Think of an LLM as an extraordinarily well-read collaborator who has read most of the text on the internet and in books, but who can only speak by completing sentences. You hand them an incomplete sentence — or a conversation, or a document — and they generate the most contextually appropriate continuation. They do not retrieve information from a database; they do not search the web; they pattern-match across their training to produce text that plausibly continues whatever you gave them. The quality of the completion depends on how well the prompt frames the desired continuation.

An LLM is, mechanically, a function that maps a sequence of tokens to a probability distribution over the next token. "Token" is the unit of text the model works with — a token is typically a word fragment, a whole common word, or a punctuation character. The tokenizer (a separate piece of software that preprocesses text before it reaches the model) converts your input string into a list of integer IDs representing tokens. These integers are passed through the model's transformer layers, which apply attention mechanisms to relate each token to all other tokens in the context, and the final layer outputs logits — unnormalized scores for every token in the vocabulary. These logits are converted to probabilities via softmax, and one token is sampled from the distribution. That token is appended to the sequence, and the process repeats until a stop condition is reached.

The context window defines the total number of tokens the model can attend to in a single forward pass. It includes the system prompt, the conversation history, and the generated output so far. A model with a 128,000-token context window can process roughly 100,000 words of combined input and output. Once the context window is full, the model cannot attend to tokens earlier in the sequence — effectively forgetting them. This is the fundamental constraint that retrieval-augmented generation (RAG) is designed to address: rather than fitting everything in the context, retrieve only the relevant pieces.

---

## How It Actually Works

The transformer architecture at the core of every modern LLM uses **self-attention** to compute relationships between all pairs of tokens in the context. For each token position, attention computes a weighted sum of all other tokens' value vectors, where the weights are determined by the similarity of the query vector at this position to the key vectors at all other positions. This is what allows the model to relate "it" to the specific noun it refers to across a long sentence, or to apply the constraint from a system prompt to user content many tokens later.

Training consists of showing the model trillions of tokens of text and optimizing the model's weights to maximize the probability it assigns to the actual next token in each position. This is called **next-token prediction** with a cross-entropy loss. The model learns grammar, facts, reasoning patterns, code syntax, and conversational conventions entirely from this signal — there is no separate mechanism for learning "facts" versus "style." The model has no separate knowledge store; everything it knows is encoded in its billions of floating-point weight parameters.

At inference time, a **chat completions API** call wraps this generation loop. You provide a list of messages — each with a `role` (`system`, `user`, or `assistant`) and `content` — and the API formats them using the model's chat template, tokenizes the result, runs the forward pass, samples tokens until a stop token or max length is reached, and returns the generated text. The `temperature` parameter scales the logits before softmax, amplifying the differences between probabilities at low values (more deterministic) and compressing them at high values (more uniform, more random). Streaming mode returns an SSE stream of token chunks as they are generated, rather than buffering the full completion.

---

## How It Connects

LLM APIs are accessed over HTTP — each completion request is a POST to an API endpoint. Understanding HTTP request structure (headers, request body as JSON, response streaming via SSE) and how to make async HTTP calls is the mechanical foundation for building LLM-powered applications in Python.
[[http-basics|HTTP Basics]]

LLM APIs support streaming responses, which are consumed as Server-Sent Events over a persistent HTTP connection. Processing a streaming response in Python requires async iteration — `async for chunk in response.aiter_text()` — which depends on coroutines and the event loop. Blocking the event loop while awaiting a long LLM completion degrades the responsiveness of the entire application.
[[async-await|Async and Await]]

---

## Common Misconceptions

Misconception 1: "The LLM remembers previous conversations."
Reality: LLM APIs are fully stateless. Each API call is independent. The model has no memory of previous calls. Multi-turn conversations work by resending the entire conversation history — all previous user and assistant messages — as part of every new API call. The "memory" in a multi-turn chatbot is maintained by the application code, not the model. As conversations grow, this history eventually fills the context window and must be summarized, truncated, or managed.

Misconception 2: "Higher temperature means better, more creative output."
Reality: Temperature increases diversity but also increases incoherence, factual errors, and off-topic responses. For tasks requiring factual accuracy or structured output (JSON generation, code, SQL), low temperature (0.0–0.3) is generally better. For creative writing or brainstorming, moderate temperature (0.7–1.0) increases variety. Very high temperatures (above 1.5) typically produce incoherent output. Temperature is a tradeoff, not a dial that uniformly improves quality.

---

## Why It Matters in Practice

Token counting matters for cost and reliability. LLM APIs charge per token (input and output separately). A 10,000-token system prompt on every call, multiplied by 10,000 requests per day, is 100 million input tokens of cost. Measuring token counts before sending requests (using `tiktoken` for OpenAI models, or the model's tokenizer) allows budget control and prevents silent truncation at the context limit. Libraries like LangChain and LlamaIndex include token counting utilities for this reason.

The stateless nature of LLM APIs has a concrete architectural implication: conversation history is application state, not model state. This means it must be stored, managed, and sent on every call, exactly like session data in a web application. Designing where this state lives — in memory for a single-user CLI, in a database for a multi-user web app, in a Redis cache for a serverless API — is an infrastructure decision, not a model decision.

---

## Interview Angle

Common question forms:
- "What is a token and why does it matter?"
- "How does temperature affect LLM output?"
- "How does a multi-turn conversation work with a stateless API?"

Answer frame: Define token as a subword unit — the model's unit of input/output. Context window: maximum total tokens per call, including history and output. Temperature: scales logits before sampling, 0 is near-deterministic, higher values increase diversity. Stateless API: every call sends the full conversation history; memory is application-level state. Streaming: SSE-based token-by-token delivery, consumed via async iteration.

---

## Related Notes

- [[embeddings|Embeddings]]
- [[rag|RAG]]
- [[tool-calling|Tool Calling]]
- [[agents|Agents]]
- [[langchain-basics|LangChain Basics]]
