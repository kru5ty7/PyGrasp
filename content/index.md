---
title: Home
---

# PyGrasp

A structured Python knowledge vault - 694 notes across 13 layers, from CPython internals to AWS cloud deployments.

---

## Learning Paths

Start here. Each path follows dependency order so every concept builds on what came before.

| Path | What it covers | Notes |
|---|---|---|
| [[lp-core\|Core Python]] | CPython internals, bytecode, memory, object system, decorators, generators, typing | 102 |
| [[lp-concurrency\|Concurrency]] | GIL, threads, processes, async/await, asyncio, event loop | 38 |
| [[lp-web\|Web Frameworks]] | HTTP, WSGI/ASGI, Flask, Django, FastAPI, Pydantic | 84 |
| [[lp-web-ecosystem\|Web Ecosystem]] | Databases, task queues, auth, testing, HTTP clients | 53 |
| [[lp-data-engineering\|Data Engineering]] | NumPy, Pandas, Polars, Kafka, Airflow, dbt, Spark | 41 |
| [[lp-ai-engineering\|AI Engineering]] | LLMs, embeddings, RAG, LangChain, LangGraph, agents, MLOps | 57 |
| [[lp-lld\|Low Level Design]] | OOP, SOLID, design patterns, concurrency safety, API design, LLD case studies | 49 |
| [[lp-hld\|High Level Design]] | Scalability, caching, databases at scale, microservices, HLD case studies | 61 |
| [[lp-sql\|SQL]] | Fundamentals, joins, aggregations, indexes, transactions, advanced SQL | 45 |
| [[lp-dsa\|DSA]] | Data structures, sorting, searching, dynamic programming, graph algorithms | 52 |
| [[lp-cloud\|Cloud (AWS)]] | IAM, S3, EC2, Lambda, SQS/SNS, ECS, boto3 | 56 |
| [[lp-security\|Security]] | OWASP Top 10, injection, XSS, CSRF, SSRF, Python security tools | 11 |
| [[lp-tooling\|Tooling and DevOps]] | Poetry, Docker, Kubernetes, GitHub Actions, CD pipelines, observability | 45 |

---

## Recommended Starting Points

**New to Python internals** → Start with [[lp-core|Core Python]], beginning at [[what-is-python|What is Python]].

**Building web APIs** → [[lp-web|Web Frameworks]], starting at [[http-basics|HTTP Basics]], then jump to [[fastapi|FastAPI]].

**Working with AI / LLMs** → [[lp-ai-engineering|AI Engineering]], starting at [[llm-basics|How LLMs Work]].

**System design interviews** → [[lp-lld|LLD]] first (OOP + design patterns), then [[lp-hld|HLD]] starting at [[scalability-basics|Scalability Basics]].

**SQL and database depth** → [[lp-sql|SQL]], starting at [[what-is-sql|What is SQL]], then [[lp-hld|HLD]] databases section.

**Coding interviews** → [[lp-dsa|DSA]], starting at [[big-o-notation|Big O Notation]].

**Deploying Python to AWS** → [[lp-tooling|Tooling]] (containers + CI/CD), then [[lp-cloud|Cloud (AWS)]] starting at [[aws-overview|AWS Overview]].

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
    ↓               ↓
Layer 5    Data     Layer 7   LLD (OOP + Design Patterns)
Engineering             ↓
    ↓           Layer 8   HLD (Distributed Systems)
Layer 6    AI
Engineering

Layer 9   SQL          ← standalone, any time
Layer 10  DSA          ← standalone, any time
Layer 11  Cloud (AWS)  ← after Layer 13 (containers)
Layer 12  Security     ← after Layer 3 + 4
Layer 13  Tooling      ← any time after Layer 1
```
