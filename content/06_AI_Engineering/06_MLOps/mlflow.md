---
title: 07 - MLflow
description: "tracking ML experiments, logging metrics and artifacts, managing model versions in the registry, and serving models  -  the open-source experiment management platform used to bring reproducibility to iterative model development"
tags: [mlflow, experiment-tracking, model-registry, artifacts, mlops, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# MLflow

> MLflow is the record-keeping system for ML experimentation  -  it captures the parameters, metrics, code version, and model artifacts from every training run so that results are reproducible, comparable, and promotable to production.

---

## Quick Reference

**Core idea:**
- **Run**: a single execution of training/evaluation code  -  `mlflow.start_run()` context manager starts a run; everything logged within it is associated with that run
- **Experiment**: a named group of runs  -  `mlflow.set_experiment("rag-evaluation")` groups related runs for comparison
- `mlflow.log_param(key, value)`: log a hyperparameter or config value (scalar, saved once per run)
- `mlflow.log_metric(key, value, step=N)`: log a metric value at a training step  -  called repeatedly to build a curve
- `mlflow.log_artifact(path)`: save a file (plot, config, dataset sample) to the run's artifact store
- `mlflow.sklearn.log_model()` / `mlflow.pytorch.log_model()` / `mlflow.transformers.log_model()`: log a trained model as an artifact with a flavor-specific signature

**Tricky points:**
- MLflow runs do not start automatically  -  if you log metrics without calling `mlflow.start_run()` first (or use autologging), they are logged to the default experiment under an implicit run that may not be named or findable
- `mlflow.log_metric` with `step` argument enables plotting learning curves in the UI  -  without `step`, all metrics appear as single points, not curves
- The model registry is a separate concept from artifact logging  -  logging a model artifact via `mlflow.pytorch.log_model()` does not register it; you must additionally call `mlflow.register_model()`
- Artifact storage location defaults to `./mlruns` locally but must be configured (S3, GCS, Azure Blob) in team environments  -  the tracking URI and artifact URI are set separately
- MLflow's `autolog()` (e.g., `mlflow.sklearn.autolog()`) automatically captures hyperparameters, metrics, and the model for supported frameworks, but the automatic model signature may not match your serving requirements

---

## What It Is

Running ML experiments without tracking is like conducting chemistry experiments without a lab notebook. You mix compounds, observe a reaction, think "that worked better than yesterday's attempt," but by next week you cannot recall which concentrations you used, in what order you added them, or what temperature the lab was at. The next time you try to reproduce the result, you cannot. The lab notebook  -  precise, timestamped, with measurements for every variable  -  is what makes science reproducible and iterative rather than accidental and irreproducible. MLflow is the digital lab notebook for ML experiments.

MLflow is organized around four components. Tracking captures the inputs (parameters, code version, environment) and outputs (metrics, artifacts) of each training run. The experiment tracking server stores these records either locally in a `./mlruns` directory or remotely via a configured tracking URI, and provides a UI to browse, filter, and compare runs. The Model Registry is a versioned catalog of model artifacts promoted from runs  -  each entry in the registry has a name, a version number, and a staging tag (Staging, Production, Archived). Models is a abstraction layer for loading registered models for inference. Projects is a packaging convention for reproducible execution, though in practice it is less commonly used than the other three components.

The practical workflow is centered on the run context. You start a run, log the hyperparameters you chose (learning rate, batch size, model architecture), run the training loop and log metrics at each step (training loss, validation accuracy), and at the end log the trained model as an artifact. The MLflow UI (launched with `mlflow ui` and accessible at `http://localhost:5000`) then shows all runs for the experiment in a table, allows parallel coordinate plots comparing parameters against metrics, and shows metric curves for selected runs. When a run produces a model that meets the quality threshold, you register it to the model registry and tag it as the candidate for production deployment.

---

## How It Actually Works

The standard usage pattern wraps training code in `mlflow.start_run()` as a context manager. All logging calls within the context are associated with that run. After the `with` block exits, the run is finalized and its status is set to FINISHED.

```python
import mlflow
import mlflow.sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

mlflow.set_experiment("customer-churn-prediction")

with mlflow.start_run(run_name="rf-depth-20-lr-0.1"):
    # Log hyperparameters
    mlflow.log_param("n_estimators", 200)
    mlflow.log_param("max_depth", 20)

    # Train
    model = RandomForestClassifier(n_estimators=200, max_depth=20)
    model.fit(X_train, y_train)

    # Log metrics
    train_acc = accuracy_score(y_train, model.predict(X_train))
    val_acc = accuracy_score(y_val, model.predict(X_val))
    mlflow.log_metric("train_accuracy", train_acc)
    mlflow.log_metric("val_accuracy", val_acc)

    # Log model artifact
    mlflow.sklearn.log_model(model, "random-forest-model")
    run_id = mlflow.active_run().info.run_id

# Register the model in the Model Registry
mlflow.register_model(
    model_uri=f"runs:/{run_id}/random-forest-model",
    name="CustomerChurnClassifier",
)
```

For deep learning training loops, the `step` parameter on `log_metric` is critical for building meaningful learning curves. Each call should pass the current training step or epoch as `step`, enabling the MLflow UI to render the metric as a time series.

```python
with mlflow.start_run():
    mlflow.log_params({"lr": 1e-4, "batch_size": 32, "epochs": 10})
    for epoch in range(10):
        train_loss = train_one_epoch(model, train_loader, optimizer)
        val_loss = evaluate(model, val_loader)
        mlflow.log_metric("train_loss", train_loss, step=epoch)
        mlflow.log_metric("val_loss", val_loss, step=epoch)
    mlflow.pytorch.log_model(model, "model")
```

The model registry supports lifecycle management through staging transitions. After registering a model version, you can transition it through stages using the `MlflowClient` API: `client.transition_model_version_stage(name, version, stage="Staging")`. The standard lifecycle is: new run produces a registered model version -> version promoted to Staging for testing -> version promoted to Production for serving -> previous Production version archived. Loading the latest Production model by name is done with `mlflow.pyfunc.load_model("models:/CustomerChurnClassifier/Production")`, allowing the serving code to be model-version agnostic.

MLflow integrates with the Hugging Face `Trainer` through the `MLflowCallback`, which is included automatically when MLflow is installed. Setting the environment variable `MLFLOW_EXPERIMENT_NAME` or calling `mlflow.set_experiment()` before training routes all Trainer-generated metrics (loss, learning rate, evaluation metrics) to MLflow automatically without additional code.

---

## How It Connects

Weights and Biases covers similar functionality to MLflow but with a cloud-first architecture, stronger visualization, and a hyperparameter sweep system. The choice between them often comes down to whether the team prefers open-source self-hosted (MLflow) or managed SaaS (W&B).

[[weights-and-biases|Weights and Biases]]

The model registry is the integration point between training and deployment. The same model version tracked in MLflow is referenced by the deployment pipeline  -  blue/green and canary deployments retrieve specific model versions from the registry by name and stage.

[[model-deployment-patterns|Model Deployment Patterns]]

QLoRA and fine-tuning training runs benefit particularly from MLflow tracking because the large number of hyperparameters (rank, alpha, target modules, learning rate, quantization config) and their interactions make it easy to lose track of what worked.

[[fine-tuning-basics|Fine-Tuning Basics]]

---

## Common Misconceptions

Misconception 1: "Logging a model with `mlflow.pytorch.log_model()` registers it in the Model Registry."
Reality: Logging a model as an artifact associates it with the run, but it does not appear in the Model Registry. The registry is a separate, explicitly managed catalog. You must call `mlflow.register_model(model_uri, name)` to create a registry entry. The model URI from a run is `runs:/<run_id>/<artifact_path>`; the model URI from the registry is `models:/<model_name>/<version_or_stage>`.

Misconception 2: "MLflow tracking is only useful for scikit-learn and PyTorch models."
Reality: MLflow's autologging integrates with over 20 frameworks (sklearn, XGBoost, LightGBM, PyTorch, TensorFlow, Keras, Spark, Hugging Face Transformers), but the core `log_param` / `log_metric` / `log_artifact` API is framework-agnostic. You can track LLM evaluation runs (logging RAGAS scores per experiment configuration), RAG pipeline variants (logging context precision and recall for different chunking strategies), or any Python process that produces measurable outputs  -  MLflow is a general-purpose experiment tracker, not a framework-specific tool.

---

## Why It Matters in Practice

The value of MLflow becomes concrete the first time you need to reproduce a model trained three months ago. Without tracking, the training script may have been modified, the hyperparameters were not recorded, the exact dataset version is unclear, and the saved model checkpoint cannot be matched to any specific run. With MLflow, every run records the git commit hash of the training code, the full parameter configuration, all metrics, and the model artifact  -  reproducing any past result is a matter of loading the run from the UI and rerunning with the logged parameters.

Team-scale MLflow deployments require a shared tracking server  -  the free `mlflow server` command backed by a PostgreSQL database and S3 artifact store is the standard architecture. This means every team member's training runs flow to the same UI, enabling shared visibility into what has been tried, what performed well, and which model is currently in production. This shared state is the foundation for systematic ML development versus individual notebook experiments.

---

## Interview Angle

Common question forms:
- "How would you track experiments across multiple training runs?"
- "What is the MLflow Model Registry and how does it fit into deployment?"
- "How is MLflow different from simply saving model checkpoints?"

Answer frame: MLflow provides structured tracking of parameters, metrics (with steps for curves), artifacts, and environment. The Model Registry adds a named, versioned catalog with lifecycle stages (Staging/Production/Archived)  -  deployment code loads by stage name, making it model-version agnostic. The difference from raw checkpoints: MLflow records what generated the checkpoint (parameters, data, code version) alongside the checkpoint itself, enabling reproducibility and comparison. Autologging minimizes boilerplate for standard frameworks.

---

## Related Notes

- [[weights-and-biases|Weights and Biases]]
- [[fine-tuning-basics|Fine-Tuning Basics]]
- [[qlora|QLoRA Fine-Tuning]]
- [[model-deployment-patterns|Model Deployment Patterns]]
- [[model-serving|Model Serving]]
