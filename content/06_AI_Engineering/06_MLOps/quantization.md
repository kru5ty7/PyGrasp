---
title: 04 - Quantization
description: "reducing model memory and compute cost by representing weights in lower-precision formats  -  covering INT8/INT4, GGUF, bitsandbytes, and the accuracy trade-off at each precision level"
tags: [quantization, int8, int4, gguf, bitsandbytes, model-compression, mlops, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# Quantization

> Quantization compresses a neural network's weights from 32-bit or 16-bit floating point into lower-precision integers  -  shrinking a 7B model from 14 GB of VRAM to under 4 GB, enabling hardware that would otherwise be incapable of running the model at all.

---

## Quick Reference

**Core idea:**
- **FP32**: full precision, 4 bytes per weight  -  rarely used for inference; training standard
- **FP16/BF16**: half precision, 2 bytes per weight  -  standard for production GPU inference; minimal accuracy loss
- **INT8**: 1 byte per weight  -  approximately 2× memory reduction from FP16; small accuracy degradation, model-dependent
- **INT4**: 0.5 bytes per weight  -  approximately 4× from FP16; larger accuracy degradation but often acceptable for LLMs
- **GGUF format**: quantized model format used by Ollama and llama.cpp  -  `Q4_K_M`, `Q5_K_M`, `Q8_0` are common quantization levels for local deployment
- **bitsandbytes**: `BitsAndBytesConfig(load_in_4bit=True)`  -  loads a Hugging Face model in 4-bit, transparently; required for QLoRA fine-tuning

**Tricky points:**
- Quantization reduces memory but does not always reduce latency  -  INT4 matmuls require dequantization before or during compute; on some hardware they are slower than FP16
- `load_in_8bit=True` and `load_in_4bit=True` in bitsandbytes use different internal schemes: 8-bit uses LLM.int8(), 4-bit uses NF4 (Normal Float 4) by default  -  NF4 has better accuracy than standard INT4
- GGUF quantization levels (Q4_K_M, Q5_K_M, etc.) differ in how they handle outlier weights  -  K-quants (`_K_`) use mixed precision (some layers at higher precision), making them more accurate than uniform quantization
- Quantizing the embedding and output projection layers costs more accuracy than quantizing intermediate attention layers  -  most quantization tools skip these layers by default
- Calibration data affects quantization quality: GPTQ-style quantization uses a sample dataset to calibrate quantization parameters; the calibration data should match the intended use domain

---

## What It Is

Imagine a recording studio that captures audio at 32-bit floating-point resolution  -  CD quality is good, but the file sizes are enormous. A mastering engineer can reduce the recording to 16-bit without audible quality loss for most listeners. Further reducing to 8-bit produces a perceptible but acceptable degradation for a podcast played on a commute. Reducing to 4-bit is noticeable but might be acceptable on a small speaker where high fidelity was never expected. Quantization applies the same logic to neural network weights: the weights that define a model's behavior are stored as floating-point numbers, and the question is how many bits are necessary before degradation becomes unacceptable for the intended use.

The practical motivation for quantization is hardware access. A Llama-3 70B model in FP16 requires approximately 140 GB of VRAM  -  the equivalent of two A100 80GB GPUs. That same model quantized to Q4_K_M in GGUF format requires approximately 43 GB  -  runnable on a single A100, or across two consumer GPUs. Quantized to 4-bit with bitsandbytes and loaded on a single A100, it fits in under 40 GB. This is not a marginal improvement: quantization is the difference between a model being runnable on accessible hardware and requiring datacenter-class infrastructure. For developers running models locally, the GGUF format (used by llama.cpp and Ollama) makes running a 7B or 13B model on a gaming GPU with 8 - 12 GB VRAM routine.

Quantization works by mapping the range of floating-point values in each weight tensor to a smaller set of integer levels. In INT8 quantization, 256 possible values represent the full range of weights in a given layer. In INT4, only 16 values are available. The quantization process determines a scale factor and zero point for each tensor (or block of weights within a tensor), allowing the stored integer values to be dequantized back to approximate floating-point values during computation. The approximation error is the source of accuracy degradation. Techniques like block quantization (applying separate scale factors to small blocks of weights rather than the whole tensor), mixed precision (keeping sensitive layers at higher precision), and outlier-aware quantization (handling statistical outliers in the weight distribution specially) all reduce this error.

---

## How It Actually Works

The `bitsandbytes` library integrates directly with the Hugging Face `transformers` library via the `BitsAndBytesConfig` class. Passing this config to `AutoModelForCausalLM.from_pretrained()` loads the model weights in the specified precision, handling quantization transparently. The model weights are stored in quantized form in GPU memory; dequantization occurs on-the-fly during forward passes.

```python
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
import torch

quantization_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_compute_dtype=torch.bfloat16,  # compute in BF16 after dequantization
    bnb_4bit_quant_type="nf4",               # Normal Float 4  -  better than standard INT4
    bnb_4bit_use_double_quant=True,          # quantize the quantization constants too (saves ~0.4 bits/param)
)

model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Meta-Llama-3-8B-Instruct",
    quantization_config=quantization_config,
    device_map="auto",
)
tokenizer = AutoTokenizer.from_pretrained("meta-llama/Meta-Llama-3-8B-Instruct")
```

The GGUF format takes a different approach to local deployment. Instead of bitsandbytes (which requires a CUDA GPU), GGUF quantized models run on CPU (with optional GPU offloading via Metal on Apple Silicon or CUDA on NVIDIA). The model is stored as a single `.gguf` file where weights are quantized at the block level with K-quant schemes that preserve higher precision in the most sensitive layers. Ollama pulls GGUF-formatted models from a registry and serves them via a local OpenAI-compatible API  -  the quantization level is baked into the model tag (`ollama pull llama3.2:8b-instruct-q5_K_M` for the Q5_K_M quantization of Llama 3.2 8B). The quality difference between quantization levels on a single model is measurable on benchmarks: an 8B model at Q8 (8-bit) scores nearly identically to FP16 on most tasks, while Q4_K_M shows a 1 - 3% degradation on reasoning benchmarks, and Q2_K (2-bit) shows significant degradation.

GPTQ is a post-training quantization method that calibrates quantization parameters using a small dataset, minimizing the reconstruction error of each layer's output. This produces higher-quality quantized models than round-to-nearest quantization, particularly at INT4. GPTQ models are available on Hugging Face Hub with `-GPTQ` in the model name and are loaded using the `auto-gptq` library. AWQ (Activation-aware Weight Quantization) is a newer alternative that identifies and preserves the small fraction of weights that have a disproportionate impact on output quality, making it particularly effective at 4-bit precision.

---

## How It Connects

QLoRA fine-tuning combines 4-bit quantization (via bitsandbytes) with LoRA adapters  -  the quantization reduces base model memory so the full model fits on a consumer GPU, while LoRA adapters are trained in FP16. Understanding quantization is a prerequisite for understanding why QLoRA is possible.

[[qlora|QLoRA Fine-Tuning]]

Quantized models served locally via Ollama use the same OpenAI-compatible API shape as cloud providers, enabling the LLM provider comparison and abstraction patterns.

[[llm-providers|LLM Providers Comparison]]

Quantization is one of the primary tools for fitting a model within the memory constraints of production serving infrastructure  -  directly affecting hardware selection and cost.

[[inference-optimization|Inference Optimization]]

---

## Common Misconceptions

Misconception 1: "INT4 quantization always hurts accuracy significantly."
Reality: For large language models specifically (7B parameters and above), 4-bit quantization with modern schemes (NF4, AWQ, Q4_K_M) typically produces output quality that is indistinguishable from FP16 on most practical tasks. The accuracy loss becomes meaningful on adversarial benchmarks, complex mathematical reasoning, or when the model is at the edge of capability for a specific task. A well-quantized 7B model often outperforms a poorly-prompted FP16 model of the same size. Smaller models (under 1B parameters) are more sensitive to quantization because their capacity is already limited.

Misconception 2: "Lower precision means faster inference."
Reality: Inference speed depends on hardware support for the data type. FP16 runs fast on modern GPUs because they have dedicated FP16 tensor cores. INT8 may run faster or at the same speed depending on the GPU generation and the quantization scheme. INT4 with bitsandbytes often runs slower than FP16 on many GPU configurations because the implementation requires dequantization per operation, and INT4 tensor cores are not universally available. The benefit of INT4 is memory, not necessarily speed. On Apple Silicon (via llama.cpp/MLX), 4-bit inference is significantly faster than FP16 because Apple's unified memory architecture is bandwidth-constrained rather than compute-constrained.

---

## Why It Matters in Practice

Quantization determines which hardware can run a given model. This has direct business implications: teams running self-hosted models on consumer hardware (a developer's workstation, a small GPU server) rely on quantization to access models that would otherwise require cloud API calls. A quantized Llama 3 8B model running locally at Q5_K_M quality provides LLM capability without per-token API costs, with full data privacy. For production deployment, the decision between full-precision cloud API and self-hosted quantized model is a function of volume: at low request rates, the cloud API is cheaper (no fixed infrastructure cost); at high request rates, a quantized self-hosted model amortizes the infrastructure cost across enough requests to be cost-competitive.

---

## Interview Angle

Common question forms:
- "What is quantization and why would you use it?"
- "What is the difference between INT8 and INT4 quantization?"
- "How would you run a 70B model on limited GPU memory?"

Answer frame: Quantization reduces the number of bits per weight, shrinking memory footprint. INT8 is 2× smaller than FP16 with small accuracy loss; INT4 is 4× smaller with larger but often acceptable loss. NF4 (bitsandbytes) and K-quants (GGUF) use more sophisticated schemes that reduce accuracy loss at INT4. For a 70B model on limited hardware: Q4_K_M GGUF via Ollama for CPU-offloaded local inference, or bitsandbytes `load_in_4bit=True` with `device_map="auto"` to split layers across available GPUs. GPTQ and AWQ offer higher accuracy at INT4 than naive rounding, at the cost of a calibration step.

---

## Related Notes

- [[qlora|QLoRA Fine-Tuning]]
- [[fine-tuning-basics|Fine-Tuning Basics]]
- [[inference-optimization|Inference Optimization]]
- [[llm-providers|LLM Providers Comparison]]
- [[model-serving|Model Serving]]
