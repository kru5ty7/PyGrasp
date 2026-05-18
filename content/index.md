---
title: Home
---

# PyGrasp

A structured Python knowledge vault — 429 notes across 9 layers, from CPython internals to production AI systems.

---

## Learning Paths

Start here. Each path follows dependency order so every concept builds on what came before.

| Path | What it covers | Notes |
|---|---|---|
| [[lp-core\|Core Python]] | CPython internals, bytecode, memory, object system, decorators, generators, typing | 92 |
| [[lp-concurrency\|Concurrency]] | GIL, threads, processes, async/await, asyncio, event loop | 39 |
| [[lp-web\|Web Frameworks]] | HTTP, WSGI/ASGI, Flask, Django, FastAPI, Pydantic | 74 |
| [[lp-web-ecosystem\|Web Ecosystem]] | Databases, task queues, auth, testing, HTTP clients | 42 |
| [[lp-data-engineering\|Data Engineering]] | NumPy, Pandas, Polars, Kafka, Airflow, dbt, Spark | 33 |
| [[lp-ai-engineering\|AI Engineering]] | LLMs, embeddings, RAG, LangChain, LangGraph, agents, MLOps | 53 |
| [[lp-system-design\|System Design]] | Scalability, caching, databases at scale, microservices, case studies | 55 |
| [[lp-security\|Security]] | OWASP Top 10, injection, deserialization, Python security tools | 12 |
| [[lp-tooling\|Tooling and DevOps]] | Poetry, Docker, Kubernetes, GitHub Actions, observability | 29 |

---

## Recommended Starting Points

**New to Python internals** → Start with [[lp-core|Core Python]], beginning at [[what-is-python|What is Python]].

**Building web APIs** → [[lp-web|Web Frameworks]], starting at [[http-basics|HTTP Basics]], then jump straight to [[fastapi|FastAPI]].

**Working with AI / LLMs** → [[lp-ai-engineering|AI Engineering]], starting at [[llm-basics|How LLMs Work]].

**Preparing for system design interviews** → [[lp-system-design|System Design]], starting at [[scalability-basics|Scalability Basics]].

**Deploying Python services** → [[lp-tooling|Tooling and DevOps]], starting at [[docker-basics|Docker Basics]].

---

## Layer Dependencies

```
Layer 0-1  Core Python
    ↓
Layer 2    Concurrency
    ↓
Layer 3    Web Frameworks
    ↓
Layer 4    Web Ecosystem
    ↓
Layer 5    Data Engineering    Layer 7  System Design
    ↓                              ↑
Layer 6    AI Engineering      Layer 8  Security
                                   ↑
                               Layer 9  Tooling and DevOps
```

Layers 7, 8, and 9 can be read in parallel with Layers 4–6 — they depend on Layer 3 but not on each other.
