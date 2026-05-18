---
title: 01 - Model Serving
description: "how to serve ML models in production using FastAPI with async inference, batch inference patterns, and an overview of dedicated serving frameworks like Triton and BentoML"
tags: [model-serving, fastapi, inference, batch-inference, triton, bentoml, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# Model Serving

> Model serving is the discipline of exposing a trained ML model as a reliable, low-latency service  -  the gap between a working Jupyter notebook and a production API that handles concurrent requests, manages model state correctly, and degrades gracefully under load.

---

## Quick Reference

**Core idea:**
- Load the model once at startup, store it in application state  -  never reload per request
- FastAPI + `@app.on_event("startup")` or `lifespan` context manager for model loading
- Use `async def` route handlers with `asyncio.run_in_executor()` for CPU-bound inference to avoid blocking the event loop
- **Batch inference**: accumulate requests over a short time window, call the model once with a batched tensor, return responses  -  increases throughput at the cost of added latency
- **Triton Inference Server**: NVIDIA's production serving framework  -  supports ONNX, TensorRT, PyTorch, TF; handles batching, model versioning, and GPU scheduling automatically
- **BentoML**: Python-first model serving framework  -  `@bentoml.service` decorator + `@bentoml.api` turns any Python function into a containerized HTTP endpoint

**Tricky points:**
- Loading a 7B model takes 10 - 30 seconds  -  if this happens per request, the service is non-functional; model state must live in the process, not be reconstructed each time
- FastAPI routes are async but model inference (PyTorch, scikit-learn) is synchronous CPU/GPU work  -  calling it directly in an `async def` handler blocks the event loop for all concurrent requests
- `asyncio.run_in_executor(None, model.predict, input)` runs inference in the default thread pool; for truly CPU-bound work, `ProcessPoolExecutor` avoids the GIL
- A GPU can only run one inference operation at a time per stream; sending 10 concurrent requests without batching means 10 sequential GPU calls, not 10 parallel ones
- Model state (transformers pipelines, sklearn models, torch modules) is not thread-safe during `__call__` in all implementations  -  validate thread safety before using the default `ThreadPoolExecutor`

---

## What It Is

A trained ML model sitting in a file is like a piece of industrial equipment in a warehouse: technically capable but not doing any work. Model serving is the process of installing that equipment in a factory, connecting it to the production line, and running it reliably at scale. The "factory" is a web server that accepts requests from clients; the "equipment" is the model loaded into memory; the "production line" is the inference pipeline that preprocesses inputs, runs the model, and returns structured outputs. The challenge is that the equipment is expensive to install (model loading), has specific throughput characteristics (GPU utilization), and must serve hundreds of concurrent workers on a single piece of hardware.

FastAPI is the most common choice for building an ML model serving API in Python. It handles HTTP request parsing, input validation via Pydantic, async request handling, and OpenAPI documentation generation. The critical pattern is loading the model at application startup and storing it in application state  -  accessible to all route handlers  -  rather than creating a new model instance per request. FastAPI's `lifespan` context manager (the modern replacement for `@app.on_event("startup")`) is the canonical place to do this initialization.

Dedicated serving frameworks like Triton Inference Server and BentoML exist because FastAPI's general-purpose nature leaves several ML-specific concerns unaddressed. Triton, developed by NVIDIA, handles model versioning (multiple versions of a model simultaneously, with traffic routing), dynamic batching (accumulating requests over a configurable time window and processing them as a single batch), and multi-model scheduling on GPU. It accepts models in ONNX, TensorRT, PyTorch TorchScript, and TensorFlow SavedModel formats and exposes both HTTP and gRPC endpoints. BentoML takes the opposite approach: rather than configuring an external server, you decorate Python functions with `@bentoml.service` and `@bentoml.api`, and BentoML handles containerization, horizontal scaling, and deployment to cloud platforms.

---

## How It Actually Works

The FastAPI model serving pattern uses the `lifespan` context manager to load the model into `app.state` before accepting any requests. The model is loaded once, lives in memory for the lifetime of the process, and is accessed from route handlers via `request.app.state.model`.

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
import asyncio
from transformers import pipeline

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: load model into app state
    app.state.model = pipeline("text-classification", model="distilbert-base-uncased-finetuned-sst-2-english")
    yield
    # Shutdown: release resources
    del app.state.model

app = FastAPI(lifespan=lifespan)

@app.post("/predict")
async def predict(request: Request, text: str):
    loop = asyncio.get_event_loop()
    # Run CPU-bound inference in thread pool  -  does not block the event loop
    result = await loop.run_in_executor(None, request.app.state.model, text)
    return {"label": result[0]["label"], "score": result[0]["score"]}
```

Batch inference addresses the fundamental mismatch between the per-request HTTP model and the per-batch GPU model. GPUs achieve maximum throughput when processing many samples in parallel; sending one sample at a time underutilizes the hardware. A batching server accumulates incoming requests in a queue for a short window (e.g., 20ms), then packages all accumulated inputs into a single batch tensor, calls the model once, and routes results back to the waiting clients. This pattern  -  sometimes called dynamic batching  -  can increase throughput by 10 - 50× compared to per-request inference on GPU, at the cost of up to `max_batch_wait_ms` of added latency. Triton's dynamic batcher implements this automatically by configuration. In a custom FastAPI implementation, you can build a similar pattern using `asyncio.Queue` and a background task that drains the queue on a timer.

For LLM serving specifically, the landscape has additional specialized components. vLLM handles LLM-specific batching using PagedAttention  -  a memory management technique that allows the KV cache for multiple concurrent sequences to share GPU memory, dramatically increasing the number of concurrent requests an LLM can serve. Text Generation Inference (TGI) by Hugging Face provides a production-ready LLM server with continuous batching, tensor parallelism, and streaming support. These are the tools of choice for serving open-weight LLMs at production scale.

---

## How It Connects

FastAPI is the HTTP layer for model serving, providing request validation, async route handling, dependency injection, and OpenAPI documentation. Understanding FastAPI's lifespan management and dependency injection system is prerequisite to building any ML serving API.

[[fastapi|FastAPI]]

LLM serving specifically requires understanding async response handling  -  streaming token-by-token generation over SSE, using `StreamingResponse` in FastAPI, and consuming the stream on the client side.

[[async-await|Async and Await]]

Model serving is where deployment decisions intersect with inference optimization. Quantization, batching, and caching strategies affect what hardware the served model requires and what throughput it can sustain.

[[inference-optimization|Inference Optimization]]

---

## Common Misconceptions

Misconception 1: "I can load the model inside the route handler and cache it with a global variable."
Reality: Using a module-level global variable for model state works in a single-threaded development server but is fragile in production. Gunicorn forks multiple worker processes  -  each fork gets a copy of the module-level state at the time of fork, so the model may be loaded N times (once per worker). FastAPI's `lifespan` and `app.state` are the correct patterns because they are process-local and lifecycle-managed.

Misconception 2: "async route handlers run inference in parallel."
Reality: `async def` means the route handler can yield the event loop while waiting for I/O, not that CPU work runs in parallel. Calling a synchronous model inference function inside an `async def` handler blocks the event loop for the entire duration of inference  -  all other concurrent requests wait. You must explicitly offload CPU-bound work with `run_in_executor` or use a separate worker process to achieve true concurrency.

---

## Why It Matters in Practice

The difference between a functional ML service and a production ML service is operationalization: correct startup/shutdown lifecycle, non-blocking inference, health check endpoints, and validated input schemas. A service that loads the model per request will timeout or OOM under any real load. A service that calls synchronous inference from an async handler will serve one request at a time regardless of how many workers are running. These are not edge cases  -  they are the default failure modes when a data scientist's notebook code is wrapped in FastAPI without understanding the serving patterns.

The choice between a custom FastAPI service and a dedicated framework like BentoML or Triton is an engineering resource tradeoff. BentoML handles containerization, horizontal scaling, and health probes automatically  -  at the cost of framework lock-in and additional abstraction. A custom FastAPI service gives full control  -  at the cost of implementing batching, versioning, and operational concerns manually. For teams without dedicated MLOps infrastructure, BentoML's managed serving layer reduces the surface area of operational decisions significantly.

---

## Interview Angle

Common question forms:
- "How would you build an API to serve an ML model?"
- "What happens if you load a model inside a FastAPI route handler?"
- "Why use `run_in_executor` for ML inference in an async endpoint?"

Answer frame: Model loading in `lifespan` context manager, stored in `app.state`. Pydantic for input validation. `run_in_executor` to offload CPU-bound inference without blocking the event loop. Dynamic batching for GPU throughput. Triton for multi-model, multi-version serving with automatic batching; BentoML for Python-first containerized deployment.

---

## Related Notes

- [[fastapi|FastAPI]]
- [[async-await|Async and Await]]
- [[inference-optimization|Inference Optimization]]
- [[model-deployment-patterns|Model Deployment Patterns]]
- [[ai-observability|AI Observability]]
