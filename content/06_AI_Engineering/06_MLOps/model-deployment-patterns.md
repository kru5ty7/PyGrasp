---
title: 02 - Model Deployment Patterns
description: "deployment strategies for ML models in production including blue/green, canary, shadow mode, A/B testing, and rolling deploys — each managing the risk of introducing a new model version to live traffic"
tags: [deployment, blue-green, canary, shadow-mode, ab-testing, mlops, layer-6, ai]
status: draft
difficulty: intermediate
layer: 6
domain: ai
created: 2026-05-18
---

# Model Deployment Patterns

> ML model deployment patterns are risk management strategies — each controls the blast radius of a bad model update by gradually exposing production traffic to the new version while maintaining the ability to instantly revert.

---

## Quick Reference

**Core idea:**
- **Blue/green deployment**: run old (blue) and new (green) model services simultaneously; switch 100% of traffic at once; instant rollback by switching back
- **Canary deployment**: route a small percentage (1–5%) of traffic to the new model; gradually increase if metrics stay healthy; rollback by returning to 0%
- **Shadow mode**: send every request to both models; new model's responses are discarded (not shown to users); used purely for comparison logging
- **A/B testing**: route user cohorts to different model versions and measure business outcome differences (click-through, conversion, task completion)
- **Rolling deploy**: replace serving instances one at a time (or in small batches) rather than all at once — used when the deployment target is a fleet of replicas
- Traffic splitting in Kubernetes: `VirtualService` in Istio with weight annotations; AWS SageMaker: `create_endpoint_config` with `ProductionVariant` and `InitialVariantWeight`

**Tricky points:**
- Shadow mode does not validate latency impact on users — the shadow calls are made in addition to live calls, so the serving infrastructure handles 2× request volume
- A/B testing for ML models requires careful cohort assignment: randomizing per-request means the same user sees different model outputs on successive calls, which degrades user experience
- Canary deployments for stateful models (LLMs with conversation history) can split a user's session across model versions mid-conversation
- Rolling deploys of large models are slow because each replica must load the model weights before accepting traffic — the rolling window must account for startup time
- Evaluating whether a canary deployment is safe requires defining success metrics before deployment — adding metrics after you see the results introduces survivorship bias

---

## What It Is

Deploying a new version of an ML model is like replacing the engine in a commercial aircraft. You cannot simply swap it in mid-flight, but you also cannot take the aircraft out of service for weeks. The solution is a fleet management strategy: you test the new engine on a small number of flights first, compare performance data to the existing fleet, and gradually retire old engines as confidence builds. If any metric indicates a problem, you ground the aircraft with the new engine immediately and investigate. Blue/green, canary, and shadow deployments are the ML equivalent of this fleet management approach, each offering a different tradeoff between speed of rollout, risk exposure, and operational complexity.

Blue/green deployment is the simplest dual-environment strategy. Two identical serving environments exist simultaneously — the blue environment runs the current production model and the green environment runs the new candidate model. A load balancer (or Kubernetes `Service` selector) points all traffic at blue. To deploy, you route 100% of traffic to green in a single atomic switch. If anything goes wrong, you switch back to blue. The model service itself never changes — only the traffic routing configuration changes. This means rollback takes seconds and is always possible as long as the blue environment remains running. The cost is running two full environments in parallel during the transition period.

Canary deployment introduces the new model to production traffic gradually. A small percentage of requests — typically 1–10% — are routed to the new model while the remainder continue to hit the existing model. The team monitors error rates, latency, and downstream business metrics during the canary phase. If all metrics remain within acceptable bounds after a defined observation period, traffic weight shifts to 25%, then 50%, then 100%. If any metric degrades, traffic returns to 0% on the canary. This strategy limits blast radius to the canary percentage at any given moment and provides real production data about the new model's behavior. The tradeoff is that a small fraction of real users experience the potentially-degraded new model during the observation period.

---

## How It Actually Works

Shadow mode is implemented by sending each incoming request to both the current production model and the candidate model, but routing only the current model's response to the user. The candidate model's response is logged alongside the production response for offline comparison. Shadow mode is the safest way to validate a new model's behavior on real production traffic because no user ever sees the candidate output. It does not validate whether users prefer the new model — it only validates that the new model produces coherent, non-crashing output and can handle the production traffic pattern. Shadow mode temporarily doubles infrastructure cost and latency (though the shadow call can be made asynchronously so it does not increase user-facing latency if implemented carefully).

In AWS SageMaker, these patterns are managed through endpoint configurations. A SageMaker endpoint can host multiple `ProductionVariant` configurations, each pointing to a different model artifact, with a specified `InitialVariantWeight`. The weights determine the traffic split: weights of `[90, 10]` implement a 90/10 canary split. SageMaker also supports shadow variants natively — a `ShadowProductionVariants` parameter accepts the shadow model configuration, and shadow traffic is handled internally without affecting the production response.

```python
import boto3

sagemaker_client = boto3.client("sagemaker")

# Canary: 90% production, 10% candidate
sagemaker_client.create_endpoint_config(
    EndpointConfigName="my-model-canary",
    ProductionVariants=[
        {
            "VariantName": "production",
            "ModelName": "my-model-v1",
            "InitialVariantWeight": 0.9,
            "InstanceType": "ml.m5.xlarge",
            "InitialInstanceCount": 2,
        },
        {
            "VariantName": "canary",
            "ModelName": "my-model-v2",
            "InitialVariantWeight": 0.1,
            "InstanceType": "ml.m5.xlarge",
            "InitialInstanceCount": 1,
        },
    ],
)
```

A/B testing for ML models differs from canary deployment in intent and structure. Canary deployment is a safety check — you are looking for regressions in existing metrics and plan to move all traffic to the new model once confidence is established. A/B testing is an experiment — you are comparing two models on a defined business outcome hypothesis and the experiment may conclude that neither version is superior. A/B tests require sticky session assignment (all requests from user X go to model A, all requests from user Y go to model B) to avoid within-user inconsistency. They also require a pre-determined sample size (calculated from statistical power requirements) and a defined evaluation period — stopping an A/B test early because one variant "looks better" inflates the false positive rate.

---

## How It Connects

The model serving infrastructure — the FastAPI or Triton service that hosts the model — is the unit being deployed. Deployment patterns describe how traffic is routed between versions of that serving infrastructure, not how the model itself is structured.

[[model-serving|Model Serving]]

Canary and shadow deployments generate model comparison data that feeds into evaluation pipelines. Deciding when a canary is safe to promote requires the same quality metrics used in development evaluation — faithfulness, accuracy, latency distributions, and error rates.

[[ai-observability|AI Observability]]

MLflow model registry tracks model versions and their staging status (Staging, Production, Archived). The registry is the source of truth for which model artifact corresponds to the blue and green environments in a deployment.

[[mlflow|MLflow]]

---

## Common Misconceptions

Misconception 1: "Shadow mode is free — users are not affected."
Reality: Shadow mode doubles the compute cost of serving because every request is processed twice. The shadow model call can be made asynchronously so the user does not wait for it, but the infrastructure still handles 2× the normal inference load. For LLMs, where inference is expensive, shadow mode can double operating costs during the comparison period.

Misconception 2: "Canary deployment means I can safely roll out a bad model — only 5% of users are affected."
Reality: 5% of your production traffic can still represent a significant number of users and can cause real harm depending on the application domain. A recommendation system exposing harmful content to 5% of users, or a financial model making incorrect calculations for 5% of transactions, is a serious incident regardless of the percentage. Canary deployment limits blast radius but does not eliminate it. The appropriate canary percentage and observation period must be chosen based on the consequences of a failure, not on the convenience of the deployment process.

---

## Why It Matters in Practice

ML model deployment without a controlled rollout strategy means accepting that every model update is either a big-bang release (high risk, instantaneous blast radius) or a test in staging that never truly replicates production distribution (unknown risk, hidden failures). Neither is acceptable for production systems. The deployment patterns described here are the standard engineering response to this problem and are expected knowledge for any ML engineer working on production systems.

The particularly ML-specific complication is that model quality regressions are often not visible in technical metrics (error rates, latency) — they appear in business metrics (user satisfaction, task completion, downstream accuracy). A model that returns `200 OK` responses with syntactically valid outputs but gives confidently wrong answers is technically healthy but productively broken. Shadow mode and A/B testing, anchored to business outcome metrics rather than infrastructure metrics, are the tools that catch this class of regression.

---

## Interview Angle

Common question forms:
- "How would you safely deploy a new version of an ML model?"
- "What is the difference between canary deployment and A/B testing?"
- "How would you implement shadow mode for an LLM API?"

Answer frame: Describe blue/green as instant atomic switch with instant rollback. Canary as gradual traffic ramp with monitoring gate at each step. Shadow mode as double-invoke with discarded response for risk-free comparison on production traffic. A/B testing as a controlled experiment with sticky cohort assignment and pre-determined sample size — the goal is hypothesis testing, not gradual rollout. For LLMs specifically: shadow mode prevents users seeing candidate output while validating generation quality on real queries.

---

## Related Notes

- [[model-serving|Model Serving]]
- [[inference-optimization|Inference Optimization]]
- [[mlflow|MLflow]]
- [[ai-observability|AI Observability]]
- [[weights-and-biases|Weights and Biases]]
