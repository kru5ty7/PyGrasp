---
title: 06 - Design an ML Pipeline
description: "A walkthrough of designing a production ML pipeline  -  feature stores, model training workflows, online vs batch serving, and monitoring for data and model drift."
tags: [system-design, case-study, ml-pipeline, feature-store, layer-7]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-05-18
---

# Design an ML Pipeline

> An ML pipeline is what separates a model that works in a notebook from a model that works in production. The notebook captures the algorithm; the pipeline captures data ingestion, feature engineering, training orchestration, serving infrastructure, and the monitoring needed to know when the model has stopped working.

---

## Quick Reference

**Core idea:**
- Training pipeline: raw data -> feature engineering -> model training -> evaluation -> model registry
- Serving pipeline: request -> feature retrieval -> model inference -> response
- Feature store: central repository for features  -  computed once, reused across models; prevents training-serving skew
- Model registry: versioned storage for trained model artifacts, with metadata (metrics, training data version, hyperparameters)
- Data drift: the distribution of input features shifts over time; model drift: model accuracy degrades; both require automated monitoring

**Key design decisions:**
- Online vs batch serving: online serving (REST API, low latency) vs batch serving (precompute predictions for all users, store in DB)
- Training-serving skew: if the feature computation in training differs from production, the model performs worse in production than in evaluation  -  the feature store prevents this by sharing the same feature definitions
- Feature freshness: real-time features (computed per request) vs precomputed features (batch-updated hourly/daily)  -  the right choice depends on how quickly the feature value changes
- Shadow mode deployment: run the new model alongside the old one, compare predictions, before routing real traffic
- Retraining cadence: triggered by time schedule, data volume threshold, or drift detection  -  automated retraining + evaluation is the production standard

---

## What It Is

Think of a recipe that a chef has perfected in a test kitchen. The recipe works because the test kitchen has specific equipment, specific ingredient suppliers, and specific preparation steps. When that recipe moves to a restaurant kitchen with different equipment, different suppliers, and cooks who prepare ingredients differently, the dish no longer tastes the same. The chef carefully documented the recipe, but the production environment differs from the test environment. This is the training-serving skew problem in ML, and it is the most common reason ML models underperform in production compared to their offline evaluation metrics.

An ML pipeline is the system that ensures the training environment and the production serving environment are consistent  -  that the model is trained on the same feature values it will see at inference time, that it is evaluated on held-out data representative of production, that it is deployed with version tracking and rollback capability, and that its behavior in production is monitored for drift. Without this infrastructure, every model deployment is a manually managed, fragile operation. With it, model development becomes a repeatable engineering process.

The problem is not the model itself  -  that is data science. The problem is everything around the model: where does training data come from? How are features computed consistently between training and serving? How is a new model version deployed without downtime? How does the system detect when the model's predictions become unreliable, and trigger a retrain? These are software engineering and system design questions.

---

## How It Actually Works

**The feature store** is the central component that prevents training-serving skew. A feature store stores precomputed feature values and the transformation logic used to compute them. During training, the model consumes features from the feature store's historical data (the offline store  -  typically a data warehouse). During serving, the model retrieves features from the feature store's low-latency serving layer (the online store  -  typically Redis). Because both use the same transformation logic, the feature values are consistent. A team registering a new feature defines the computation once; all models using that feature get consistent values in both training and production.

**The training pipeline** is an orchestrated workflow: data ingestion from the data warehouse, feature computation (or retrieval from the feature store), train/validation/test split, model training, evaluation against metrics, and conditional promotion to the model registry if evaluation metrics meet the threshold. Orchestration tools (Airflow, Prefect, Kubeflow Pipelines) manage the scheduling, dependency tracking, and failure recovery of these steps. The pipeline is version-controlled and rerunnable  -  a critical property for debugging regressions and for regulatory audit trails.

**Model serving** takes two forms depending on use case. Online serving exposes a REST API that accepts a request, retrieves real-time features from the online feature store, runs model inference, and returns a prediction with sub-100ms latency. This is appropriate when the prediction depends on the current state of the request (e.g., fraud detection, personalized ranking of search results). Batch serving precomputes predictions for all users or items on a schedule (hourly, daily), stores the results in a database, and serves them from the database at request time. This is appropriate when freshness requirements are relaxed and request volume is very high (e.g., email recommendation campaigns, pre-personalized home feeds).

```python
from fastapi import FastAPI
from pydantic import BaseModel
import redis
import mlflow
import mlflow.pyfunc
import json
import time

app = FastAPI()
r = redis.Redis(decode_responses=True)

# Load model from MLflow model registry at startup
# Production URI: mlflow://models/fraud_detector/Production
model = mlflow.pyfunc.load_model("models:/fraud_detector/Production")

class PredictionRequest(BaseModel):
    user_id: str
    transaction_id: str
    amount: float
    merchant_id: str
    timestamp: float

class PredictionResponse(BaseModel):
    transaction_id: str
    fraud_probability: float
    decision: str  # "allow" or "review"
    model_version: str
    latency_ms: float

@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest):
    start = time.time()

    # Step 1: Retrieve precomputed user features from online feature store (Redis)
    user_features_raw = r.hgetall(f"features:user:{request.user_id}")
    if not user_features_raw:
        # Fallback: compute features on the fly (slower, but handles cold start)
        user_features_raw = compute_user_features(request.user_id)

    user_features = {k: float(v) for k, v in user_features_raw.items()}

    # Step 2: Combine request-time features with precomputed features
    features = {
        "amount": request.amount,
        "hour_of_day": time.gmtime(request.timestamp).tm_hour,
        "merchant_country_risk": get_merchant_risk(request.merchant_id),
        # Precomputed features from feature store
        "user_avg_transaction_30d": user_features.get("avg_transaction_30d", 0.0),
        "user_transaction_count_24h": user_features.get("transaction_count_24h", 0),
        "user_new_merchant_ratio_7d": user_features.get("new_merchant_ratio_7d", 0.0),
    }

    # Step 3: Run model inference
    import pandas as pd
    feature_df = pd.DataFrame([features])
    fraud_probability = float(model.predict(feature_df)[0])
    decision = "review" if fraud_probability > 0.7 else "allow"

    latency_ms = (time.time() - start) * 1000

    # Step 4: Log prediction for monitoring and future retraining data
    prediction_log = {
        "transaction_id": request.transaction_id,
        "user_id": request.user_id,
        "features": features,
        "fraud_probability": fraud_probability,
        "decision": decision,
        "model_version": model.metadata.run_id,
        "timestamp": request.timestamp,
        "latency_ms": latency_ms
    }
    r.rpush("prediction_logs", json.dumps(prediction_log))

    return PredictionResponse(
        transaction_id=request.transaction_id,
        fraud_probability=fraud_probability,
        decision=decision,
        model_version=model.metadata.run_id,
        latency_ms=latency_ms
    )

# Batch feature computation job (runs hourly via Airflow)
def update_user_features_batch():
    """
    Compute per-user aggregate features from the last 30 days of transactions.
    Write to both the online store (Redis) and offline store (data warehouse).
    """
    users = db.get_active_users_last_24h()

    pipe = r.pipeline()
    for user_id in users:
        features = {
            "avg_transaction_30d": db.compute_avg_transaction(user_id, days=30),
            "transaction_count_24h": db.compute_transaction_count(user_id, hours=24),
            "new_merchant_ratio_7d": db.compute_new_merchant_ratio(user_id, days=7),
            "updated_at": time.time()
        }
        # Write to online store with 25-hour TTL (covers one batch cycle + buffer)
        pipe.hset(f"features:user:{user_id}", mapping=features)
        pipe.expire(f"features:user:{user_id}", 90000)  # 25 hours

    pipe.execute()

# Drift monitoring: compare recent prediction distribution to training baseline
def check_prediction_drift():
    """
    Read recent prediction logs, compute distribution statistics,
    compare to baseline from training period. Alert if KL divergence exceeds threshold.
    """
    recent_logs = [json.loads(x) for x in r.lrange("prediction_logs", -10000, -1)]
    if len(recent_logs) < 1000:
        return  # not enough data

    recent_probs = [log["fraud_probability"] for log in recent_logs]
    recent_mean = sum(recent_probs) / len(recent_probs)

    # Training baseline (stored in model registry metadata)
    baseline_mean = 0.03  # 3% fraud rate in training data

    drift_ratio = abs(recent_mean - baseline_mean) / baseline_mean
    if drift_ratio > 0.5:  # 50% relative drift
        alert_on_call(f"Model drift detected: baseline mean {baseline_mean:.3f}, "
                      f"recent mean {recent_mean:.3f} (drift ratio: {drift_ratio:.2f})")
```

**Shadow mode deployment** is the safest way to deploy a new model version. The new model runs alongside the current production model. Every request is served by the production model (whose result is returned to the user), and also processed by the shadow model (whose result is logged but not returned). Prediction distributions, latency, and error rates are compared between the two. Once the shadow model demonstrates equivalent or better behavior, it is promoted and the old model is retired. Shadow mode catches bugs and performance regressions that offline evaluation misses, because production traffic distribution often differs from the evaluation dataset.

**The three most important design decisions:** (1) Feature store for training-serving consistency  -  the single most effective architectural decision to prevent performance degradation between offline evaluation and production. (2) Model registry with versioning  -  enables rollback when a new model version degrades, reproducibility for debugging, and audit trail for regulated industries. (3) Automated drift monitoring  -  model performance degrades silently over time as data distributions shift; automated monitoring with alerting is the only way to catch this at scale.

---

## Why It Matters in Practice

ML systems have a unique failure mode that most software systems do not: they degrade gradually and silently. A web server either works or returns an error. A model trained on last year's data continues to serve predictions on this year's data without any runtime error  -  the predictions just become progressively less accurate. Designing systems that detect, surface, and respond to this degradation is as important as designing the model training and serving infrastructure. The production ML pipeline exists to turn a one-time model-in-a-notebook into a continuously maintained, monitored, and improved system.

---

## Interview Angle

Common question forms:
- "How would you design the ML infrastructure for a fraud detection system?"
- "What is training-serving skew and how do you prevent it?"
- "How do you detect when a model in production is no longer performing well?"

Answer frame:
Requirements: low-latency online inference, consistent features between training and serving, versioned deployments, drift monitoring. Feature store: offline store for training (data warehouse), online store for serving (Redis)  -  same transformation logic in both. Training pipeline: orchestrated workflow (Airflow/Prefect), model evaluation gate, promotion to registry on pass. Serving: REST API retrieving features from online store, inference, prediction logging. Drift monitoring: compare recent prediction distribution to training baseline, alert on KL divergence or mean shift. Shadow deployment for safe model version upgrades. Retraining trigger: schedule, data volume, or drift alert.

---

## Related Notes

- [[data-warehousing|Data Warehousing]]
- [[redis-data-structures|Redis Data Structures]]
- [[message-queues|Message Queues]]
- [[caching-strategies|Caching Strategies]]
- [[api-design-principles|API Design Principles]]
