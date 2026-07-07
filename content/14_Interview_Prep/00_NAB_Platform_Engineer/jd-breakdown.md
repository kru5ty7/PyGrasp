---
title: 01 - NAB JD Breakdown
description: "Requirement-by-requirement breakdown of the NAB Platform Engineer (SDE2, NEF team, Bangalore) job description - cloud, containers, IaC, CI/CD, observability, programming, security/compliance, and ways of working."
tags: [interview-prep, nab, platform-engineering, jd, layer-14]
status: draft
difficulty: intermediate
layer: 14
domain: interview-prep
created: 2026-07-06
---

# NAB JD Breakdown

> Platform Engineer (SDE2), NEF team, Bangalore. Interview July 11, 2026 (F2F rounds; Codility Python/Java round precedes). Compiled July 6, 2026 from the JD + resume; inferences marked.

---

## Cloud infrastructure

- Hands-on with at least one major cloud (AWS or GCP) — core services: EC2, S3, VPC, IAM → [[aws-platform-questions|AWS Platform Engineering Question Bank]]
- Multi-cloud Internal Developer Platform context (a sibling SDE3 posting for the same NEF team names AWS + Azure as the multi-cloud pair — inference from that sibling JD, not this one: https://www.foundit.in/job/platform-engineer-sde3-nab-bengaluru-bangalore-38349158)
- Cloud infrastructure management *as a platform service* — building it for other teams, not just using it

## Containers & orchestration

- Docker containerization (explicitly "strong, practical") → [[docker-basics|Docker Basics]], [[multi-stage-builds|Multi-Stage Docker Builds]]
- Kubernetes: writing manifests, managing workloads — core requirement, not nice-to-have → [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- Good-to-have: service mesh (Istio, Linkerd)

## Infrastructure as Code

- Terraform (explicitly named) — reusable modules, automated provisioning workflows → [[terraform-iac-questions|Terraform and IaC Question Bank]]
- Ansible (explicitly named) — configuration management
- "Repeatable, auditable" IaC — the audit angle matters at a bank → [[pipeline-security-compliance|Pipeline Security and Compliance]]

## CI/CD

- Design/build/maintain pipelines — Harness named first (twice, incl. good-to-have), then Jenkins, GitHub Actions → [[cicd-design-questions|CI/CD Design Question Bank]]
- Secure, high-velocity pipelines; automation of build/test/deploy for varied app types
- Ephemeral/on-demand environments spun up from internal developer portals, with test automation baked into spin-up

## Observability

- Monitoring, logging, alerting — Prometheus, Grafana, ELK named explicitly → [[observability-questions|Observability Question Bank]]

## Programming

- Python, Go, Java, or Shell — clean, maintainable code (Codility round is Python/Java, so Python is accepted) → [[gil|The GIL]], [[decorators|Decorators]]

## Security / risk / compliance

- "Security and risk ingrained in daily activity" — explicit JD language → [[pipeline-security-compliance|Pipeline Security and Compliance]]
- Good-to-have: regulated financial services experience, understanding of compliance requirements
- Secure CI/CD specifically named as a platform focus area

## Soft skills / ways of working

- End-to-end ownership ("from contributing to owning")
- Developer experience empathy: gathering pain points from product teams, building self-service tools
- Code reviews, technical design discussions, engineering standards
- Good-to-have: TypeScript/frontend for developer portals; cloud certifications

---

## Related Notes

- [[gap-analysis|Gap Analysis]]
- [[nab-nef-context|NAB, NEF and Banking Domain Context]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
