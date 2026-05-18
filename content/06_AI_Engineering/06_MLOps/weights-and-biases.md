---
title: 08 - Weights and Biases
description: "experiment tracking, hyperparameter sweeps, artifact versioning, and model comparison using the Weights and Biases platform  -  covering runs, sweeps, and how it differs from MLflow"
tags: [wandb, weights-and-biases, experiment-tracking, sweeps, hyperparameter-search, mlops, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# Weights and Biases

> Weights and Biases is a cloud-native experiment tracking platform that adds hyperparameter sweep automation and richer visualization on top of the same run/metric/artifact pattern as MLflow  -  the key differentiator is the sweep system, which automates hyperparameter search across distributed training jobs.

---

## Quick Reference

**Core idea:**
- `wandb.init(project="my-project", name="run-1", config={...})`: start a tracked run with configuration
- `wandb.log({"train_loss": 0.45, "val_acc": 0.89})`: log metrics  -  called repeatedly; each call is a new step
- `wandb.log({"train_loss": loss}, step=epoch)`: explicit step control
- **Sweep**: a search over hyperparameter space  -  `wandb.sweep(sweep_config)` + `wandb.agent(sweep_id, function=train_fn, count=N)`  -  runs N training jobs with different hyperparameter combinations
- **Artifacts**: versioned data/model blobs  -  `wandb.Artifact(name, type)` + `artifact.add_file(path)` + `run.log_artifact(artifact)`  -  with lineage tracking (which artifact produced which model)
- `wandb.watch(model, log="all", log_freq=100)`: attach a PyTorch model to a run for automatic gradient and weight histogram logging

**Tricky points:**
- `wandb.init()` requires a network connection to the W&B cloud by default  -  use `mode="offline"` for air-gapped environments, then `wandb sync` to upload when connected
- Sweeps use Bayesian optimization, random search, or grid search  -  Bayesian optimization (`method: bayes`) is efficient for continuous hyperparameters but requires a defined `metric.goal` to optimize toward
- `wandb.log()` without a `step` argument auto-increments an internal counter  -  mixing `wandb.log({"loss": loss})` and `wandb.log({"acc": acc}, step=epoch)` in the same run can produce misaligned metric timelines
- W&B charges for storage of large artifacts and for seats on team plans  -  artifact versioning at scale (large model checkpoints logged every epoch) can accumulate significant storage costs
- The `wandb.watch()` gradient logging can significantly slow training because it hooks into the backward pass  -  log at intervals (`log_freq=100`) rather than every step

---

## What It Is

Managing ML experiments without tooling is like managing a series of cooking experiments by taste-testing results and trusting memory. You try a new recipe variation, note mentally that it seemed better, change two more things the next day, and after a week you can no longer explain what you ate on Tuesday that was particularly good or reproduce it reliably. Weights and Biases is the professional kitchen log  -  every ingredient, quantity, temperature, and timing recorded, with photographs of each dish, and a search interface that lets you find "the pasta dish with garlic and lemon that scored 9/10."

Weights and Biases (W&B) and MLflow solve the same core problem  -  experiment reproducibility and comparison  -  but with different architectural philosophies. MLflow is open-source and self-hosted: you run the tracking server on your own infrastructure. W&B is a cloud-hosted SaaS product: experiment data is sent to W&B's servers in real time, and the UI lives at `wandb.ai`. W&B's cloud-first design means the UI is richer and more polished than MLflow's out-of-the-box, team collaboration features work without infrastructure setup, and real-time monitoring of training runs (watching loss curves update live) works seamlessly. The tradeoff is that experiment data leaves your infrastructure by default, which is a compliance concern for some organizations.

The feature that most differentiates W&B from MLflow is the Sweeps system. A sweep is an automated hyperparameter search experiment: you define the hyperparameter space (which parameters to vary, what ranges to explore, what search strategy to use), and W&B's sweep controller distributes training jobs across one or more machines, managing the search algorithmically. Bayesian optimization sweeps use the results of completed runs to predict which hyperparameter configuration is most likely to improve the target metric, focusing subsequent runs on promising regions of the space. Random search sweeps sample uniformly, which is better for large or discontinuous hyperparameter spaces. Grid search exhaustively evaluates all combinations, appropriate only for small discrete spaces.

---

## How It Actually Works

The W&B integration requires the `wandb` package and a login with an API key (`wandb login` or by setting the `WANDB_API_KEY` environment variable). The training loop integration is minimal: initialize a run with a config dict, log metrics each step, and finish the run.

```python
import wandb

# Initialize: project groups all runs; config is logged as hyperparameters
run = wandb.init(
    project="llm-finetuning",
    name="llama3-8b-r16-lr2e4",
    config={
        "model": "meta-llama/Meta-Llama-3-8B-Instruct",
        "lora_rank": 16,
        "lora_alpha": 32,
        "learning_rate": 2e-4,
        "batch_size": 4,
        "epochs": 3,
    },
)

# Log metrics each step
for epoch in range(config.epochs):
    train_loss = train_one_epoch(model, train_loader, optimizer)
    val_loss = evaluate(model, val_loader)
    wandb.log({
        "train/loss": train_loss,
        "eval/loss": val_loss,
        "epoch": epoch,
    }, step=epoch)

wandb.finish()
```

A W&B sweep is configured as a Python dictionary defining the search space and method, then launched via `wandb.sweep()` to get a sweep ID, and executed via `wandb.agent()` which calls the training function repeatedly with sampled configurations.

```python
sweep_config = {
    "method": "bayes",
    "metric": {"name": "eval/loss", "goal": "minimize"},
    "parameters": {
        "learning_rate": {"min": 1e-5, "max": 1e-3, "distribution": "log_uniform_values"},
        "lora_rank": {"values": [8, 16, 32, 64]},
        "lora_alpha": {"values": [16, 32, 64]},
        "batch_size": {"values": [4, 8, 16]},
    },
}

def train():
    with wandb.init() as run:
        config = run.config
        model = build_model(rank=config.lora_rank, alpha=config.lora_alpha)
        optimizer = AdamW(model.parameters(), lr=config.learning_rate)
        for epoch in range(3):
            loss = train_epoch(model, optimizer, config.batch_size)
            wandb.log({"eval/loss": evaluate(model)})

sweep_id = wandb.sweep(sweep_config, project="lora-sweep")
wandb.agent(sweep_id, function=train, count=30)  # run 30 trials
```

The Artifacts system provides versioned storage for datasets, model checkpoints, and evaluation results, with lineage tracking. An artifact created from a run is tagged with the run that produced it; loading that artifact in a subsequent run creates a lineage edge in W&B's artifact graph. This makes it possible to trace any model back through its training run to the dataset version it was trained on.

```python
# Log a model artifact
artifact = wandb.Artifact("finetuned-llama3", type="model")
artifact.add_dir("./fine-tuned-model/")
run.log_artifact(artifact)

# Load a specific artifact version in a downstream run
artifact = run.use_artifact("finetuned-llama3:v3", type="model")
artifact_dir = artifact.download()
```

---

## How It Connects

MLflow is the primary alternative to W&B for experiment tracking. The choice between them is architectural: MLflow for self-hosted open-source, W&B for cloud-managed SaaS. Both integrate with the Hugging Face `Trainer` and both support a model registry  -  the concepts map directly, though the APIs differ.

[[mlflow|MLflow]]

W&B's sweep system is the practical tool for hyperparameter search during fine-tuning. QLoRA training introduces multiple interacting hyperparameters (rank, alpha, learning rate, target modules, quantization config) that benefit from systematic sweep-based exploration rather than manual grid search.

[[qlora|QLoRA Fine-Tuning]]

AI observability in production extends W&B's development-time monitoring to deployed models  -  tracking prompt/response pairs, latency, and cost in production rather than training metrics.

[[ai-observability|AI Observability]]

---

## Common Misconceptions

Misconception 1: "W&B and MLflow do the same thing  -  pick either one."
Reality: While both track experiments, W&B's sweep system is substantially more capable than MLflow's hyperparameter search  -  W&B supports Bayesian optimization, distributed multi-agent sweeps, and early stopping of unpromising runs natively. MLflow's hyperparameter search requires external tools (Optuna, Ray Tune) for similar capability. Conversely, MLflow's model registry, deployment integrations, and self-hosted nature are better fits for enterprise MLOps pipelines with compliance requirements. They are not interchangeable  -  the right choice depends on what part of the ML workflow is the bottleneck.

Misconception 2: "I need to change my training code significantly to use W&B."
Reality: The Hugging Face `Trainer` integrates with W&B automatically when `wandb` is installed and `WANDB_PROJECT` is set as an environment variable  -  zero code changes required for standard training metrics. For custom training loops, `wandb.init()` and `wandb.log()` can be added in under five lines. The barrier to entry is low; the decision to use W&B is primarily about which UI and feature set better fits the team's needs.

---

## Why It Matters in Practice

Hyperparameter search without automation is a significant time sink in applied ML. Manually running dozens of training jobs with different configurations, checking results, forming intuitions, and adjusting the next run takes days of engineer time. W&B sweeps with Bayesian optimization explore the hyperparameter space intelligently, running the most informative trials first  -  a 30-trial Bayesian sweep often finds configurations as good as a 200-trial grid search for continuous hyperparameter spaces. This directly reduces the calendar time from "initial model" to "best achievable model" on a given dataset.

Real-time monitoring of training runs is another practical benefit. A long fine-tuning run (6 - 12 hours on a single GPU) that silently diverges after 2 hours wastes 4 - 10 hours of compute time if not monitored. W&B's alert system sends notifications when metrics cross thresholds  -  a `val/loss` that stops decreasing or a gradient norm that explodes can trigger a notification before significant compute is wasted.

---

## Interview Angle

Common question forms:
- "How would you run a hyperparameter search for a fine-tuning job?"
- "What is the difference between Weights and Biases and MLflow?"
- "How does a W&B sweep work?"

Answer frame: Sweeps define a hyperparameter space, a search method (Bayesian, random, grid), and a metric to optimize. `wandb.sweep()` registers the sweep; `wandb.agent()` runs training function N times with sampled configs. Bayesian optimization focuses trials on promising regions. Compared to MLflow: W&B is cloud-hosted with richer UI and native sweeps; MLflow is self-hosted open-source with stronger model registry and deployment integrations. Both integrate with Hugging Face Trainer automatically.

---

## Related Notes

- [[mlflow|MLflow]]
- [[fine-tuning-basics|Fine-Tuning Basics]]
- [[qlora|QLoRA Fine-Tuning]]
- [[ai-observability|AI Observability]]
- [[model-deployment-patterns|Model Deployment Patterns]]
