---
title: 04 - NAB, NEF and Banking Domain Context
description: "Sourced background on NAB Engineering Foundations (NEF) - platform-as-product history, tooling heritage, innersource model - plus APRA CPS 234/230 regulatory context and likely 'why NAB / domain' questions, with source URLs preserved."
tags: [interview-prep, nab, nef, banking, compliance, sourced, layer-14]
status: draft
difficulty: intermediate
layer: 14
domain: interview-prep
created: 2026-07-06
---

# NAB, NEF and Banking Domain Context

> Web-sourced with URLs for sanity-checking. The single most useful framing to echo in the interview: **"compliance as a built-in platform capability, not team burden."**

---

## What NEF is

- NEF began in early 2020 as standardised practices and "repeatable quickstarts" to get code into production faster; born because teams were building the same cloud components in slightly different ways, creating complexity. Grew to 100+ squads across the bank.
  Source: iTnews — https://www.itnews.com.au/news/nab-brings-its-software-engineering-into-focus-553299
- NEF is delivered internally **as a software product**; every application gets a workspace with standard non-prod/prod support; compliance is automated into the platform so teams using it are compliant by default. **Echo this framing in the interview: "compliance as a built-in platform capability, not team burden."**
  Source: HashiCorp talk by NAB Distinguished Engineer Andrew Brydon — https://www.hashicorp.com/en/resources/building-nab-engineering-foundations-with-terraform-enterprise
- **Tooling heritage (2020-era; JD shows Harness has since entered — expect evolution):** Terraform Enterprise for standardised infra deployment, Sentinel policy-as-code for compliance, Jenkins Templating Engine for a reusable standard CI/CD pipeline, innersourced Terraform modules in an internal GitHub org, standard bootcamps on Terraform IaC / Java / JavaScript / containers. (Same HashiCorp + iTnews sources.) → concepts in [[terraform-iac-questions|Terraform and IaC Question Bank]] and [[cicd-design-questions|CI/CD Design Question Bank]]
- Stated NEF goal: **all developers must be able to promote code to production on their first day** — the standard platform bakes in compliance-as-code so teams avoid weeks/months of platform enablement.
  Source: NAB tech blog on Medium — https://medium.com/@nabtechblog/building-the-nab-engineering-foundation-e2605db757c
- NEF uses an **innersource model** — any team can contribute updates so the central platform doesn't become a bottleneck. (iTnews source.)
- **Wider org context:** NAB was the first Australian bank with a cloud-first strategy; runs the NAB Cloud Guild (7,000+ engineers trained, 2,700 cloud certifications); microservices via a platform-based approach; also built NAB-X for federated frontend delivery.
  Source: https://goodteams.app/engineering/nab
- NAB technology supports 8.5M+ customers across Australia/NZ; Innovation Centres in India and Vietnam collaborate on resilient, scalable platforms.
  Source: NAB careers — https://www.nab.com.au/about-us/careers/business-areas/technology-digital
- The JD phrase "Australia's best engineering bank" is real internal mission language — use it.

---

## Banking/regulatory expectations relevant to platform engineering

- **APRA CPS 234 (Information Security):** requires regulated entities to maintain security capability commensurate with threats — asset identification/classification, control implementation, incident management, control testing, audit, APRA notification. Controls span access control, encryption, monitoring, segmentation, authentication, logging; testing required regularly **and after material system changes**. Full working summary: [[pipeline-security-compliance|Pipeline Security and Compliance]].
  Sources: https://cloud.google.com/security/compliance/cps234 ; https://www.levo.ai/resources/blogs/apra-cps-234-compliance-guide-requirements-controls-third-parties---how-to-build-a-resilient-information-security-framework
- **CPS 230** replaced APRA's outsourcing standard on 1 July 2025 (operational risk/resilience); enforcement has teeth — e.g., a $250M capital charge on Medibank after its breach.
  Source: https://www.cliffside.com.au/insights/apra-cps-234-compliance-guide/
- **What this means for answers (inference):** every platform feature at a bank must be explainable in terms of least privilege, auditability, change control, separation of duties, and evidence generation. In design questions, add one sentence on "and this is logged/audited/policy-gated" — that instinct is what the JD's "nack for risk and security" is screening for. ([[iam-least-privilege|Principle of Least Privilege]])

---

## Likely "why NAB / domain" questions

*(Inference, supported by the Glassdoor report that candidates are assessed on NAB knowledge — [[real-interview-intelligence|Real Interview Intelligence]].)*

- Why a bank / why NAB after a SaaS product company? (Good answer: scale + NEF's mission is the mature version of the internal platform built at Deltek.)
- What do you know about NAB / what does NEF do? (Use the summary above.)
- How does a regulated environment change day-to-day engineering?
- Difference between DevOps and platform engineering? (Golden paths, platform-as-product, self-service — have a crisp answer.)

---

## Related Notes

- [[real-interview-intelligence|Real Interview Intelligence]]
- [[pipeline-security-compliance|Pipeline Security and Compliance]]
- [[jd-breakdown|NAB JD Breakdown]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
