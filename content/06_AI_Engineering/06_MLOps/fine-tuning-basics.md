---
title: 05 - Fine-Tuning Basics
description: "when and how to fine-tune a language model — covering full fine-tuning vs PEFT, supervised fine-tuning data preparation, and the practical decision of when fine-tuning is the right tool vs prompt engineering or RAG"
tags: [fine-tuning, peft, sft, supervised-fine-tuning, lora, mlops, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# Fine-Tuning Basics

> Fine-tuning adapts a pre-trained language model to a specific task or style by continuing training on a curated dataset — but the decision to fine-tune should come after exhausting prompt engineering and RAG, not before.

---

## Quick Reference

**Core idea:**
- **Full fine-tuning**: update all model weights on a task-specific dataset — requires storing a full copy of the model for each fine-tuned version; expensive in compute and storage
- **PEFT** (Parameter-Efficient Fine-Tuning): freeze most weights, train a small set of additional parameters — LoRA is the dominant PEFT method; QLoRA extends it to quantized base models
- **Supervised Fine-Tuning (SFT)**: fine-tune on (input, output) pairs — the standard approach for instruction following, classification, and format adaptation
- **Hugging Face `Trainer`**: `TrainingArguments` + `SFTTrainer` from `trl` — the standard training loop for SFT with Hugging Face models
- **Dataset format**: each example has `{"messages": [{"role": "user", ...}, {"role": "assistant", ...}]}` for chat models — the chat template formats this into the training input
- **When to fine-tune**: when the task requires consistent output format, specific style, or domain vocabulary that prompt engineering cannot reliably produce

**Tricky points:**
- Fine-tuning on too small a dataset (under a few hundred examples for most tasks) typically produces worse results than a well-crafted prompt — the model overfits to the training examples
- Fine-tuning on low-quality data teaches the model to replicate that low quality — "garbage in, garbage out" applies more forcefully to fine-tuning than to prompting
- A fine-tuned model forgets some general capability in proportion to how aggressively it is trained on the task data — catastrophic forgetting is real, especially with full fine-tuning at high learning rates
- Fine-tuning cannot reliably inject factual knowledge — if the training data contains facts not in the pre-training distribution, the model often hallucinates related facts. RAG is the correct tool for knowledge injection.
- Evaluation must compare the fine-tuned model against the best-prompted base model — it is common to find that a well-prompted GPT-4o outperforms a fine-tuned GPT-3.5 on the same task

---

## What It Is

Fine-tuning a pre-trained language model is like hiring a generalist employee from a consulting firm and then putting them through your company's onboarding program. The employee arrives with a broad set of skills — reading, writing, reasoning, coding — built up over years of general education and experience. Your onboarding program does not re-teach them to read or reason; it teaches them your company's specific terminology, processes, preferred communication style, and domain-specific patterns. After onboarding, they are more effective at your specific work, though they may have slightly less bandwidth for work far outside your domain. The onboarding program is fine-tuning; the generalist pre-trained model is the employee before onboarding.

Full fine-tuning updates every weight in the model on the task-specific dataset. Starting from a pre-trained checkpoint, the training procedure runs a supervised learning loop — each training example provides an input and a target output, and the model's weights are adjusted via gradient descent to make the target output more probable given the input. For large models, this is computationally expensive: fine-tuning a 7B parameter model in full requires a GPU with enough memory to hold the model weights (14 GB at FP16) plus gradients (another 14 GB at FP32) plus optimizer states (another 28 GB for AdamW) — approximately 56 GB total, requiring multiple A100s. Each fine-tuned version of the model requires storing a full copy of all 7 billion weights, which becomes expensive in storage as the number of task-specific variants grows.

Parameter-efficient fine-tuning (PEFT) addresses both the compute and storage problems by training only a small number of additional parameters while freezing the base model weights. LoRA (Low-Rank Adaptation) is the dominant PEFT method: instead of updating the full weight matrices, it trains two small low-rank matrices whose product approximates the update to the original matrix. A rank-16 LoRA adapter for a 7B model might have only 20–40 million trainable parameters — less than 1% of the base model's parameters — while achieving quality close to full fine-tuning on many tasks. The LoRA adapter weights can be stored separately from the base model, meaning one base model on disk supports many task-specific adapters, each a fraction of the base model's size.

---

## How It Actually Works

Supervised fine-tuning (SFT) is the most common form of fine-tuning for instruction-following models. The dataset consists of (instruction, response) pairs where each response demonstrates the behavior you want to elicit. For format adaptation tasks — making the model output valid JSON, follow a specific response structure, or use domain-specific terminology — even a few hundred high-quality examples can produce measurable improvement. The `trl` (Transformer Reinforcement Learning) library's `SFTTrainer` is the standard tool for this, wrapping the Hugging Face `Trainer` with SFT-specific defaults.

```python
from trl import SFTTrainer, SFTConfig
from transformers import AutoModelForCausalLM, AutoTokenizer
from datasets import Dataset

model = AutoModelForCausalLM.from_pretrained("meta-llama/Meta-Llama-3-8B-Instruct")
tokenizer = AutoTokenizer.from_pretrained("meta-llama/Meta-Llama-3-8B-Instruct")

# Dataset: list of dicts with "messages" key in chat format
dataset = Dataset.from_list([
    {
        "messages": [
            {"role": "user", "content": "Classify this review as positive or negative: 'Great product!'"},
            {"role": "assistant", "content": "positive"},
        ]
    },
    # ... hundreds more examples
])

training_args = SFTConfig(
    output_dir="./fine-tuned-model",
    num_train_epochs=3,
    per_device_train_batch_size=4,
    learning_rate=2e-4,
    logging_steps=10,
)

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    args=training_args,
)
trainer.train()
trainer.save_model()
```

The decision framework for fine-tuning versus alternatives is critical because fine-tuning has higher upfront cost than the alternatives. Prompt engineering should always be exhausted first: a carefully constructed few-shot prompt with 5–10 examples often matches the quality of a fine-tuned model on format adaptation tasks, at zero training cost. RAG should be used when the goal is knowledge injection — providing the model with information it was not trained on. Fine-tuning is appropriate when the task requires consistent, reliable format adherence that prompt engineering cannot deliver, when the desired style or tone is highly specific and examples alone do not convey it reliably, or when latency requires shorter prompts (a fine-tuned model may need no few-shot examples in the prompt, reducing token count and latency).

---

## How It Connects

QLoRA is the dominant practical approach to fine-tuning: it uses quantization to fit the base model in 4-bit, then trains LoRA adapters in higher precision. Understanding PEFT and LoRA conceptually is prerequisite to understanding what QLoRA adds (quantization of the base model) and why it matters (enables fine-tuning on a single consumer GPU).

[[qlora|QLoRA Fine-Tuning]]

MLflow is the standard tool for tracking fine-tuning experiments: logging training loss curves, evaluation metrics, and model artifacts across multiple training runs enables comparison and selection of the best checkpoint.

[[mlflow|MLflow]]

Fine-tuning is not a substitute for RAG when the goal is providing up-to-date domain knowledge — a model fine-tuned on last year's documentation does not know about this year's changes, and updating it requires another full training run. RAG retrieves current documents at query time.

[[rag|RAG]]

---

## Common Misconceptions

Misconception 1: "Fine-tuning teaches the model new facts."
Reality: Fine-tuning trains the model to produce certain outputs given certain inputs, but it does not reliably inject factual knowledge that was absent from pre-training. If you fine-tune on a dataset of Q&A pairs about your internal product, the model may learn to answer questions in the right format and style, but factual details it did not encounter in pre-training are often hallucinated rather than learned. RAG, which retrieves the actual document at query time and passes it in context, is the correct mechanism for grounding responses in specific facts.

Misconception 2: "More training epochs always produce better fine-tuned models."
Reality: Overfitting to the fine-tuning dataset is a real failure mode. A model trained for too many epochs on a small dataset will memorize the training examples and perform poorly on novel inputs. The standard approach is to monitor evaluation loss on a held-out validation set and stop training when validation loss begins to increase. For small datasets (under 1,000 examples), 1–3 epochs is typically the safe range; larger datasets can support more epochs before overfitting.

Misconception 3: "I need to fine-tune to improve my LLM application."
Reality: The majority of LLM application improvements come from better prompts, better retrieval, and better post-processing — not from fine-tuning. Fine-tuning has a high barrier: it requires curated training data, training compute, evaluation infrastructure, and a deployment process for the new model. These costs are justified only when simpler interventions have been exhausted and the performance gap is measurable and significant.

---

## Why It Matters in Practice

Fine-tuning is the mechanism that closes the gap between a general-purpose foundation model and a specialized model that reliably handles a specific task at production quality. The practical outcome is twofold: a fine-tuned smaller model (7B or 13B) often outperforms a much larger general model (70B) on a narrow task, at substantially lower inference cost. A fine-tuned 7B model for invoice extraction that runs locally on a quantized CPU server is both cheaper and more accurate for that specific task than a GPT-4o API call.

The data quality requirement is the primary practical bottleneck. Curating 500–2,000 high-quality (instruction, response) pairs for a specific task takes significant human effort — often more effort than building the fine-tuned model itself. Automating dataset generation using a larger LLM (a process called "distillation" or "synthetic data generation") reduces this effort but introduces quality risks if the generating model makes systematic errors that get baked into the fine-tuning data.

---

## Interview Angle

Common question forms:
- "When would you fine-tune a model versus using RAG or prompt engineering?"
- "What is the difference between full fine-tuning and PEFT?"
- "Can fine-tuning inject new factual knowledge into a model?"

Answer frame: Fine-tuning is the last resort after prompt engineering and RAG. It is appropriate for style/format adaptation, not knowledge injection. Full fine-tuning updates all weights — expensive compute and storage. PEFT/LoRA trains small adapters, achieving similar quality at a fraction of the cost. SFT requires (instruction, response) dataset; quality of data matters more than quantity. Fine-tuning cannot reliably add facts — use RAG for knowledge grounding.

---

## Related Notes

- [[qlora|QLoRA Fine-Tuning]]
- [[rag|RAG]]
- [[prompt-engineering|Prompt Engineering]]
- [[mlflow|MLflow]]
- [[weights-and-biases|Weights and Biases]]
