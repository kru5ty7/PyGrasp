---
title: 06 - QLoRA Fine-Tuning
description: "fine-tuning large language models on consumer hardware by combining 4-bit quantization with LoRA adapters  -  covering rank selection, target modules, bitsandbytes config, and the Hugging Face PEFT library"
tags: [qlora, lora, peft, fine-tuning, quantization, bitsandbytes, huggingface, mlops, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# QLoRA Fine-Tuning

> QLoRA makes fine-tuning a 7B or 13B language model accessible on a single consumer GPU by quantizing the frozen base model to 4-bit precision while training LoRA adapters in full BF16 precision  -  the quantization handles memory, the adapters handle learning.

---

## Quick Reference

**Core idea:**
- **QLoRA** = Quantized base model (4-bit, via bitsandbytes) + **LoRA** adapter training (in BF16/FP16)
- **LoRA rank** (`r`): dimensionality of the low-rank update matrices  -  higher rank = more capacity but more parameters; typical values: 8, 16, 32, 64
- **LoRA alpha** (`lora_alpha`): scaling factor applied to the adapter output  -  conventionally set to `2 * r` or equal to `r`; controls effective learning rate of adapters
- **target_modules**: which linear layers receive LoRA adapters  -  `["q_proj", "v_proj"]` is minimal; `["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]` is full attention+MLP
- **LoRA dropout** (`lora_dropout`): regularization on adapter weights  -  typically 0.05 - 0.1
- After training, adapters can be merged into the base model with `model.merge_and_unload()` for faster inference (no adapter overhead)

**Tricky points:**
- Gradient checkpointing (`gradient_checkpointing=True` in `TrainingArguments`) is required for QLoRA to fit in memory  -  it trades compute for memory by recomputing activations during backward pass instead of storing them
- `model.enable_input_require_grads()` must be called when using gradient checkpointing with quantized models  -  without it, gradients for the adapter layers may not propagate correctly
- `bnb_4bit_compute_dtype=torch.bfloat16` specifies that dequantized weights are operated on in BF16, not FP32  -  omitting this defaults to FP32 compute, which is slower on modern GPUs and uses more memory
- Merged models (adapters merged into base weights via `merge_and_unload()`) lose the 4-bit quantization  -  the merged model is FP16, larger, and requires more VRAM than the quantized+adapter serving setup
- `use_reentrant=False` in `gradient_checkpointing_kwargs` avoids a bug in PyTorch's reentrant gradient checkpointing with some model architectures

---

## What It Is

Imagine trying to modify the wiring of a large industrial machine to make it perform a specialized task. One approach is to rewire the entire machine from scratch  -  expensive, time-consuming, and requires a full duplicate of the machine while you work. A smarter approach is to leave the machine entirely intact and add a small external control module that intercepts the machine's signals and adjusts them for the specialized task. The control module is small, cheap to build, and can be removed or swapped without touching the main machine at all. LoRA adapters are that control module. QLoRA additionally puts the main machine in "storage mode" (4-bit quantization) so it takes up far less space while the control module is being designed.

LoRA (Low-Rank Adaptation) is based on the observation that the weight updates learned during fine-tuning can be approximated by a low-rank matrix. Instead of updating a weight matrix `W` (of shape `d × k`) directly, LoRA decomposes the update `ΔW` into two smaller matrices: `A` (of shape `d × r`) and `B` (of shape `r × k`), where `r` (the rank) is much smaller than `d` or `k`. The adapter adds `BA` to the frozen original weight during the forward pass: `output = Wx + BAx`. Only `A` and `B` are trained; `W` is frozen. For a 7B model, the total number of trainable parameters in a typical LoRA configuration is 20 - 50 million, compared to 7 billion for full fine-tuning.

QLoRA (Quantized LoRA) extends this by quantizing the frozen base model weights to 4-bit NF4 (Normal Float 4) using the `bitsandbytes` library. This reduces the base model's memory footprint from approximately 14 GB (FP16) to approximately 4.5 GB, making it feasible to load the base model on a single 8 GB or 16 GB consumer GPU. The LoRA adapters are initialized in FP16 or BF16 and remain in higher precision throughout training, because gradients flowing through the adapter parameters need full precision for stable optimization. The quantized base model contributes only forward-pass computation  -  its weights are never updated  -  so the precision limitation of 4-bit affects only representational fidelity, not gradient accuracy.

---

## How It Actually Works

The standard QLoRA setup uses three libraries: `bitsandbytes` for quantized model loading, `peft` for LoRA adapter configuration, and `trl` for the SFT training loop. The quantization config and LoRA config are created separately and composed with the model.

```python
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
from peft import LoraConfig, get_peft_model, TaskType
from trl import SFTTrainer, SFTConfig
from datasets import Dataset
import torch

# Step 1: Load base model in 4-bit
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.bfloat16,
    bnb_4bit_use_double_quant=True,
)
model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Meta-Llama-3-8B-Instruct",
    quantization_config=bnb_config,
    device_map="auto",
)
model.enable_input_require_grads()

# Step 2: Attach LoRA adapters
lora_config = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                    "gate_proj", "up_proj", "down_proj"],
    lora_dropout=0.05,
    bias="none",
    task_type=TaskType.CAUSAL_LM,
)
model = get_peft_model(model, lora_config)
model.print_trainable_parameters()
# Output: trainable params: 41,943,040 || all params: 8,072,302,592 || trainable%: 0.52%
```

The choice of `target_modules` is the most consequential hyperparameter after rank. Applying LoRA only to the query and value projection matrices (`q_proj`, `v_proj`) is a minimal configuration that often works for style and format adaptation. Applying adapters to all attention and feed-forward projection matrices (all seven `*_proj` modules listed above) gives the adapter more capacity to change behavior, at the cost of more trainable parameters and slightly more memory. For most fine-tuning tasks, all-projection adapters with rank 16 represent a good starting point.

After training, the adapter weights are saved separately from the base model using `trainer.model.save_pretrained("./adapter-weights")`. Loading for inference requires loading the base model and then loading the adapter: `model = PeftModel.from_pretrained(base_model, "./adapter-weights")`. For production serving, merging the adapter into the base model via `merged_model = model.merge_and_unload()` eliminates the adapter overhead on every forward pass, but produces a full FP16 model that requires quantization again if memory is constrained.

---

## How It Connects

QLoRA builds directly on quantization fundamentals  -  NF4 format, bitsandbytes, and the `BitsAndBytesConfig` class. Understanding why NF4 is more accurate than standard INT4 at 4-bit precision explains why QLoRA preserves quality while drastically reducing the base model's memory footprint.

[[quantization|Quantization]]

Fine-tuning basics cover the decision framework (when to fine-tune vs prompt engineer vs RAG) and the general SFT training loop. QLoRA is the practical implementation path for that training on hardware most developers can access.

[[fine-tuning-basics|Fine-Tuning Basics]]

Tracking QLoRA training runs  -  loss curves, gradient norms, evaluation metrics across different rank configurations  -  is done with MLflow or Weights and Biases. Both integrate with the Hugging Face `Trainer` via callbacks, logging metrics automatically per step.

[[weights-and-biases|Weights and Biases]]

---

## Common Misconceptions

Misconception 1: "QLoRA always produces worse models than full fine-tuning."
Reality: On most narrow tasks and at 7B scale and above, QLoRA with well-configured adapters reaches 90 - 95% of full fine-tuning quality at a fraction of the cost. The original QLoRA paper demonstrated that a 65B model fine-tuned with QLoRA on a single GPU achieved competitive performance with much larger full fine-tuned models on reasoning benchmarks. For practical production fine-tuning use cases  -  format adaptation, domain-specific instruction following, style transfer  -  the quality gap is typically undetectable in human evaluation.

Misconception 2: "A higher LoRA rank always produces a better model."
Reality: Higher rank adds more trainable parameters and more adapter capacity, but it also increases the risk of overfitting on small datasets and increases memory usage. Rank 8 or 16 is sufficient for most narrow task adaptations; rank 64 or higher is typically only beneficial when fine-tuning for broad behavioral changes (closer to full fine-tuning in scope). The right rank depends on the task complexity and dataset size, and must be selected empirically via evaluation on a held-out validation set.

Misconception 3: "I can skip `model.enable_input_require_grads()` if my training loss is decreasing."
Reality: Without `enable_input_require_grads()`, some quantized model configurations silently fail to propagate gradients to the adapter layers during the backward pass  -  the loss decreases because of other training dynamics (e.g., the head layer adapts), but the attention layer adapters do not train at all. The training loss plot looks normal. The adapter weights remain near initialization. Always call `enable_input_require_grads()` on quantized models before attaching adapters.

---

## Why It Matters in Practice

QLoRA democratized fine-tuning by making it feasible on a single consumer GPU. Before QLoRA (published in 2023), fine-tuning a 7B model required multi-GPU setups with 40 - 80 GB of combined VRAM  -  infrastructure unavailable to most individual practitioners. QLoRA reduced this to an 8 GB or 16 GB GPU, making fine-tuning accessible on a gaming PC, a single cloud GPU instance, or Google Colab. This changed the economics of model specialization: instead of paying for a multi-GPU training run or using only hosted fine-tuning APIs, practitioners can run experiments locally, iterate rapidly on data and configuration, and produce specialized adapters for domain-specific tasks.

The practical workflow  -  quantize base model, attach LoRA adapters, train with SFTTrainer, evaluate, save adapter, optionally merge  -  is now a standard pattern that any ML engineer working on LLMs is expected to know. The adapter-based model management also enables efficient multi-task serving: one quantized base model on GPU with multiple small adapter files on disk, loading the appropriate adapter per request or per tenant, is a pattern used in production multi-tenant LLM systems.

---

## Interview Angle

Common question forms:
- "What is QLoRA and how does it enable fine-tuning on limited hardware?"
- "What are LoRA rank and alpha, and how do you choose them?"
- "What is the difference between training with LoRA adapters and full fine-tuning?"

Answer frame: QLoRA = 4-bit quantized base model (bitsandbytes NF4) + LoRA adapters trained in BF16. Quantization reduces base model memory (14 GB -> ~4.5 GB for 7B FP16 -> 4-bit). LoRA decomposes weight updates into two low-rank matrices (A and B), training only those. Rank controls adapter capacity  -  16 is a good default. Alpha scales adapter output  -  typically 2×rank. Target modules determine which layers get adapters  -  all-projections gives more capacity. Gradient checkpointing required for memory efficiency.

---

## Related Notes

- [[quantization|Quantization]]
- [[fine-tuning-basics|Fine-Tuning Basics]]
- [[mlflow|MLflow]]
- [[weights-and-biases|Weights and Biases]]
- [[model-serving|Model Serving]]
