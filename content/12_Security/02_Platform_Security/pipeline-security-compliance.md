---
title: 01 - Pipeline Security and Compliance
description: "Security-in-pipelines and compliance-aware engineering for regulated environments - SAST/DAST and scanning gates, least-privilege deploy roles, auditability of infrastructure changes, and a working summary of APRA CPS 234 / CPS 230 for banking platform interviews."
tags: [security, pipelines, compliance, apra, cps-234, least-privilege, auditability, interview-prep, layer-8]
status: draft
difficulty: intermediate
layer: 8
domain: security
created: 2026-07-06
---

# Pipeline Security and Compliance

> Interview prep — Platform Engineering. At a regulated bank, "security and risk ingrained in daily activity" is JD language, not decoration: every platform feature must be explainable in terms of least privilege, auditability, change control, separation of duties, and evidence generation. In design answers, add one sentence on "and this is logged/audited/policy-gated" — that instinct is what's being screened for.

---

## Security Embedded in the Pipeline

**Q: Embed security into a CI/CD pipeline — what goes where?**

Answer frame, by stage:
- **Pre-commit / CI**: secret scanning, SAST ([[bandit|Bandit]]), dependency/SCA scanning ([[dependency-scanning|Dependency Vulnerability Scanning]])
- **Build**: minimal base images, image vulnerability scanning, signed artifacts with provenance
- **Deploy**: least-privilege deploy roles per environment ([[iam-least-privilege|Principle of Least Privilege]]) — the pipeline's prod role can deploy and nothing else; DAST against staging
- **Runtime**: secrets injected from a manager, never stored in code or images ([[secrets-in-python|Handling Secrets in Python]], [[secret-management|Secret Management]])

The platform-team framing: these gates are built into the shared pipeline template so every team gets them by default — compliance as a built-in platform capability, not per-team burden. See [[cicd-design-questions|CI/CD Design Question Bank]] for the full pipeline design.

---

## Auditable Infrastructure

**Q: How do you make infrastructure changes auditable?**

Answer frame: all changes as code through reviewed PRs; applies executed by CI under a scoped, non-personal role; plan output preserved as the change record; drift detection so reality can't silently diverge from code; policy-as-code (Sentinel/OPA) rejecting non-compliant changes pre-apply; CloudTrail/audit logs as evidence. If "repeatable, auditable Terraform" is on your resume, expect it to be pulled on — have a concrete example ready ([[terraform-iac-questions|Terraform and IaC Question Bank]]).

**Q: What would you check before letting an ephemeral environment access production-like data?**

Answer frame: default answer is *it doesn't* — synthetic or masked data. If production-like data is genuinely required: data classification check, masking/tokenization of anything sensitive, time-boxed scoped credentials, network isolation from actual prod, access logging, and automatic teardown with data destruction at TTL.

---

## APRA CPS 234 — Working Summary

**APRA CPS 234 (Information Security)** requires Australian regulated entities to maintain information-security capability commensurate with threats:

- Identification and classification of information assets
- Implementation of controls proportional to asset criticality — spanning access control, encryption, monitoring, segmentation, authentication, logging
- Incident management with APRA notification obligations (material incidents within 72 hours)
- **Systematic testing of controls — regularly and after material system changes** (this is why change-triggered validation belongs in the pipeline)
- Internal audit of control effectiveness

Sources: https://cloud.google.com/security/compliance/cps234 ; https://www.levo.ai/resources/blogs/apra-cps-234-compliance-guide-requirements-controls-third-parties---how-to-build-a-resilient-information-security-framework

**CPS 230** (operational risk management / resilience) replaced APRA's outsourcing standard on 1 July 2025. Enforcement has teeth — e.g., a $250M capital charge on Medibank after its breach.

Source: https://www.cliffside.com.au/insights/apra-cps-234-compliance-guide/

**What this means for engineering answers (inference):** control testing "after material changes" maps to pipeline gates; asset classification maps to data-handling rules for environments; incident notification maps to detection and runbooks. A platform that bakes these in makes every team compliant by default.

---

## Related Notes

- [[dependency-scanning|Dependency Vulnerability Scanning]]
- [[bandit|Bandit (Python Security Linter)]]
- [[secrets-in-python|Handling Secrets in Python]]
- [[secret-management|Secret Management]]
- [[iam-least-privilege|Principle of Least Privilege]]
- [[cicd-design-questions|CI/CD Design Question Bank]]
- [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
