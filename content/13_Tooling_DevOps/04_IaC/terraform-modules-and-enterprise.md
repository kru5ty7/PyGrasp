---
title: 03 - Terraform Modules and Terraform Enterprise
description: "Modules package resources behind a variables/outputs interface for reuse across teams; Terraform Enterprise adds the bank-grade layer - private module registry, Sentinel policy enforcement inside the apply pipeline, remote execution, and workspace access controls."
tags: [terraform, iac, modules, module-registry, terraform-enterprise, sentinel, policy-as-code, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-07
---

# Terraform Modules and Terraform Enterprise

> A module is Terraform's unit of product: the platform team encodes "how we do an S3 bucket here" - encryption on, public access off, tags mandatory - and a hundred teams consume it without knowing the twenty resources inside. Terraform Enterprise is the machinery that makes this safe at bank scale.

---

## Quick Reference

**Core idea:**
- **Module** = any directory of `.tf` files; called with `module "x" { source = ... }`, parameterized by variables, consumed via outputs
- Standard layout: `main.tf` (resources), `variables.tf` (interface in), `outputs.tf` (interface out), plus `README` and `examples/`
- **Versioning**: modules are tagged (semver) and consumers pin (`version = "~> 2.1"`); breaking changes ship as new majors with migration notes - never mutate a published version
- **Public registry vs internal**: registry modules (e.g. the AWS VPC module) encode community practice; internal modules encode *organizational* policy - naming, tagging, security defaults, compliance
- **Terraform Enterprise (TFE)** - self-hosted; NAB runs this:
  - **Private module registry**: org-wide versioned modules, searchable, with docs - the innersource distribution channel
  - **Sentinel**: policy-as-code evaluated *between plan and apply, inside the pipeline* - hard/soft mandatory levels; non-compliant plans never reach apply
  - **Remote execution**: plans/applies run on TFE workers with centrally-held credentials - no laptop applies, uniform logging
  - **Workspace access controls**: team-based read/plan/write/admin per workspace - separation of duties, in the tool
- OSS vs Cloud vs Enterprise: same language and providers; the tiers add collaboration, governance, and self-hosting

**Tricky points:**
- A module taking 40 variables is a config file wearing a module costume - good modules make decisions, not just forward parameters
- Deep module nesting (modules calling modules calling modules) makes plans unreadable; one or two levels is the practical ceiling
- `source = "git::...?ref=v2.1.0"` pins by tag; an unpinned git source floats with the default branch - a supply-chain and stability hazard
- Sentinel evaluates the *plan* (what will change), so policy can reason about future state - stronger than linting HCL text

---

## What It Is

Modules exist because the same twenty lines of "S3 bucket plus encryption plus public-access block plus lifecycle rules plus tags" appear in every team's config - divergently, then wrongly. A module collapses that into `module "artifacts_bucket"` with three variables, and centralizes the *decisions*: encryption isn't a variable, it's hardcoded on; tags aren't optional, the module merges mandatory ones in. This is golden-path engineering in miniature - the module makes the compliant way the easy way, which is the entire thesis of a platform team. Module *interface* design follows from that: expose what teams legitimately vary (name, size, retention), decide everything else internally, output what downstream configs need.

Versioning is what makes org-wide consumption survivable. Consumers pin (`version = "~> 2.1"`); the platform team ships breaking changes as v3 with migration notes and a deprecation window, exactly like any library - because that's what a module is. The alternative (teams tracking a moving main branch) means one merged PR simultaneously re-plans a hundred teams' infrastructure.

Terraform Enterprise is where NAB specifically lives, and its features answer the governance questions OSS Terraform leaves open. The private module registry is the distribution channel for innersourced modules - versioned, documented, discoverable inside the org's boundary. Remote execution moves plan/apply off laptops onto controlled workers: cloud credentials live in TFE (never with individual engineers), every run is logged and attributable, and workspace access controls decide who can plan vs approve vs apply - separation of duties as configuration.

Sentinel is the piece to be able to explain precisely: policy-as-code evaluated against the *plan* itself, as a mandatory pipeline stage between plan and apply. "Every S3 bucket must have encryption enabled," "no security group open to 0.0.0.0/0," "all resources tagged with cost-center" - written as policy, versioned in git, enforced on every run, with hard-mandatory policies that no one can override and soft-mandatory ones requiring privileged override. The interview framing: **"how do you enforce policy before infra changes go live" is a Terraform Enterprise answer** - the gate is in the platform, not in a wiki page asking teams to behave. Combined with modules whose defaults are compliant, you get the compliant-by-default posture regulators and [[pipeline-security-compliance|CPS 234]] auditing expect.

---

## How It Actually Works

```
modules/s3-bucket/
├── main.tf          # bucket + encryption + public-access block + logging
├── variables.tf     # name, retention_days, extra_tags - the few real choices
├── outputs.tf       # bucket id/arn
├── README.md
└── examples/basic/  # working example doubling as test fixture
```

```hcl
# Consumer side - pinned version from a registry
module "artifacts" {
  source  = "app.terraform.io/nab-internal/s3-bucket/aws"   # private registry path
  version = "~> 2.1"
  name            = "team-a-artifacts"
  retention_days  = 90
}
```

```python
# Sentinel policy (illustrative): every S3 bucket encrypted
import "tfplan/v2" as tfplan

s3_buckets = filter tfplan.resource_changes as _, rc {
    rc.type is "aws_s3_bucket" and rc.change.actions contains "create"
}

main = rule {
    all s3_buckets as _, b {
        b.change.after.server_side_encryption_configuration is not null
    }
}
```

TFE run flow: VCS push → speculative plan on PR → merge → plan on worker → **Sentinel checks** → (approval if required) → apply → state versioned centrally.

---

## How It Connects

Module interface = variables/outputs discipline from configuration structure.

[[terraform-configuration|Terraform Configuration Structure]]

Version pinning and breaking-change rollout mirror pipeline-template product management.

[[semantic-versioning|Semantic Versioning]], [[cicd-design-questions|CI/CD Design Question Bank]]

Sentinel is the IaC instance of compliance-as-platform-capability.

[[pipeline-security-compliance|Pipeline Security and Compliance]], [[nab-nef-context|NAB, NEF and Banking Domain Context]]

The probing questions (module design, registry, policy-as-code) live in the bank.

[[terraform-iac-questions|Terraform and IaC Question Bank]]

---

## Common Misconceptions

Misconception 1: "A good module exposes everything as a variable for flexibility."
Reality: A module that forwards every attribute is abstraction theater - consumers carry full complexity plus a layer of indirection. Good modules *remove* decisions; opinions are the product.

Misconception 2: "Sentinel is a linter for Terraform files."
Reality: Sentinel evaluates the computed plan - the actual changes about to happen, including values known only after plan. It can reject based on future state ("this change opens a port to the internet"), which text linting cannot see.

Misconception 3: "Terraform Enterprise is just Terraform with a UI."
Reality: The substance is governance: central credentials and remote runs, policy gates inside the apply path, RBAC on workspaces, versioned state with audit history. It's the difference between a tool and a controlled change-management system - which is why a bank runs it.

---

## Interview Angle

Common question forms:
- "Design a module other teams will consume."
- "How do you stop teams deploying non-compliant infrastructure?"
- "How does a breaking module change roll out to a hundred consumers?"

Answer frame:
Module: small deliberate interface, compliant defaults baked in, examples + README, semver tags, registry distribution. Enforcement: Sentinel/OPA between plan and apply - hard gates in the platform, not process documents; pair with modules so the easy path passes the gates. Breaking changes: new major, migration guide, deprecation window, telemetry on version adoption - never mutate published versions. Anchor it to NAB's actual stack: Terraform Enterprise, private registry, Sentinel, innersourced modules.

---

## Related Notes

- [[terraform-basics|Terraform Basics]]
- [[terraform-configuration|Terraform Configuration Structure]]
- [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [[pipeline-security-compliance|Pipeline Security and Compliance]]
- [[nab-nef-context|NAB, NEF and Banking Domain Context]]
