---
title: 02 - Gap Analysis
description: "Honest strengths/gaps assessment against the NAB Platform Engineer JD - strong Python and self-service platform building, adjacent Terraform/Kubernetes/observability depth, genuinely missing Harness, Ansible, multi-cloud, and service mesh."
tags: [interview-prep, nab, platform-engineering, gap-analysis, layer-14]
status: draft
difficulty: intermediate
layer: 14
domain: interview-prep
created: 2026-07-06
---

# Gap Analysis

> Honest, no inflation. Net read: a strong Python platform-*builder* interviewing for a platform-*infrastructure* role. The self-service-platform narrative and production ownership are the sell; depth risk is Kubernetes operations, Terraform module engineering, and the named observability/CD stack (Prometheus/Grafana, Harness).

---

## Strong — genuine, defensible in depth

- **Python** — the anchor. 4+ years, async, FastAPI, high-throughput APIs. JD's programming bar fully met. ([[gil|The GIL]], [[asyncio|Asyncio]])
- **Building internal self-service platforms** — the conceptual heart of the role, actually done: self-service internal platform for deploying integration workflows; low-code Airflow DAG builder for non-technical users. NEF's whole mission is "self-service tools developers love" — this is the integration-domain version of exactly that. Lead with it.
- **Docker** — multi-stage builds, image-size optimization, Compose for dev/prod parity, images in CI/CD with vulnerability scanning. ([[multi-stage-builds|Multi-Stage Docker Builds]], [[docker-compose|Docker Compose]])
- **GitHub Actions CI/CD** — lint/pytest/security-scan/build pipelines. Real, but see platform-scale caveat below. ([[github-actions-python|GitHub Actions for Python]])
- **Production ownership & reliability** — 2,000+ Airflow workflows, 99.9% uptime, 30+ clients, RCA experience. Maps directly to "ongoing reliability and performance."
- **AWS core services** — EC2, S3, IAM, VPC, SSM, S3 event triggers, ALB/NLB, auto-scaling groups. Matches the JD's named services. ([[aws-platform-questions|AWS Platform Engineering Question Bank]])

---

## Adjacent — real but shallower or differently-shaped than the JD wants

- **Terraform** — resume shows provisioning EC2/S3/IAM/VPC with Terraform modules. Real, but it is *application-team* Terraform. The JD wants someone who *authors reusable modules for other teams to consume*: state management, workspaces, module versioning, drift, policy-as-code. Expect probing on remote state/locking, module design, `terraform import`, drift handling, Sentinel/OPA. If the experience was a handful of self-maintained modules, say so plainly and pivot to speed of deepening. → prep [[terraform-iac-questions|Terraform and IaC Question Bank]]
- **Kubernetes** — EKS, Helm charts, Jobs/CronJobs, probes, resource limits are listed. More than nothing, but the honest question: did you *operate* the cluster (networking, RBAC, upgrades, CrashLoopBackOff/OOMKilled/DNS troubleshooting) or *deploy onto* one someone else ran? A platform team runs clusters. If experience is deploy-onto, cluster operations is the gap — prep that theory hard. → [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- **Observability** — centralized logging and uptime SLAs exist, but JD names Prometheus/Grafana/ELK and the resume names none of them. Concepts (metrics vs logs vs traces, alerting, SLIs/SLOs) transfer; the specific stack is a gap. Do not claim Prometheus without having run it. → [[observability-questions|Observability Question Bank]]
- **CI/CD at platform scale** — pipelines were built *for own apps*; JD wants pipelines *as a product for hundreds of teams* (templating, golden paths, guardrails). The Airflow DAG-generator CLI is the best bridge argument — "pipeline as a templated product." → [[cicd-design-questions|CI/CD Design Question Bank]]

---

## Genuinely missing — don't inflate

- **Harness** — named twice in the JD; zero experience. Skim Harness concepts (pipelines, delegates, OPA policies, canary/blue-green verification) before the interview to speak the vocabulary.
- **Ansible** — not on the resume at all.
- **Multi-cloud / GCP / Azure** — AWS-only background.
- **Service mesh (Istio/Linkerd)** — absent; good-to-have only, low priority.
- **Ephemeral environment tooling / developer portals (Backstage-style)** — no on-demand env spin-up experience. Conceptually adjacent to dynamic DAG generation, but tooling is new. Sibling SDE3 JD names Backstage + TypeScript — worth 30 minutes of reading.
- **Regulated financial-services experience** — good-to-have, not present. Audit-logging, RBAC, SSM secrets-management work is the partial answer. ([[pipeline-security-compliance|Pipeline Security and Compliance]])
- **TypeScript/frontend** — absent; good-to-have only.

---

## Related Notes

- [[jd-breakdown|NAB JD Breakdown]]
- [[prep-plan|Prioritized Prep Plan]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
