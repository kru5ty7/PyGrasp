---
title: 01 - Terraform Basics
description: "Terraform is declarative infrastructure as code - providers translate HCL resources into cloud API calls, data sources read existing infrastructure, and the init/plan/apply/destroy lifecycle turns desired state into real infrastructure with a reviewable diff in between."
tags: [terraform, iac, providers, resources, data-sources, lifecycle, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-07-07
---

# Terraform Basics

> Terraform's core loop mirrors Kubernetes' reconciliation idea applied to infrastructure: declare desired state in code, let the tool compute the diff against reality, review that diff, then apply it. The reviewable `plan` is the whole point - infrastructure change becomes a code-review artifact.

---

## Quick Reference

**Core idea:**
- **Declarative over imperative**: you write *what should exist* (an EC2 instance, sized thus, tagged thus), not the steps to create it - Terraform computes create/update/delete operations from the diff
- **Providers**: plugins translating resources into API calls - `aws`, `google`, `azurerm`, `kubernetes`, `helm`; pinned in `required_providers`
- **Resource**: infrastructure Terraform *manages* (creates/updates/destroys). **Data source**: existing infrastructure Terraform *reads* (looked up, never touched)
- **Lifecycle**: `terraform init` (download providers/modules, configure backend) → `plan` (diff config vs state vs reality) → `apply` (execute the plan) → `destroy` (delete everything managed)
- **CLI hygiene**: `terraform fmt` (canonical formatting), `terraform validate` (syntax/internal consistency) - both belong in CI before any plan
- **Tiers**: open-source CLI (free, bring your own backend/CI) → HCP Terraform / Terraform Cloud (SaaS: remote runs, state, private registry, teams) → Terraform Enterprise (self-hosted version of the same, for banks/regulated environments)

**Tricky points:**
- `plan` is a *prediction* - reality can change between plan and apply; saved plan files (`-out`) make apply execute exactly what was reviewed
- Data sources are read at plan/refresh time - a data source that finds nothing fails the plan
- Some resource attribute changes force *replacement* (destroy + create), not update - the plan marks these `-/+`; catching them is why plans get read
- `destroy` removes what's *in state* - resources created outside Terraform survive it

---

## What It Is

The declarative-vs-imperative distinction is the foundation. A bash script that creates a VPC does so exactly once - run it twice and it errors or duplicates; delete a subnet manually and the script knows nothing. A Terraform config *describing* the VPC is idempotent by construction: every run converges reality toward the description. Change the config, and Terraform derives the minimal set of API operations. Delete the config, and Terraform knows to delete the infrastructure. The script encodes *actions*; the config encodes *outcomes* - and outcomes can be diffed, reviewed, and audited.

Providers make this cloud-agnostic in mechanism (not in config - AWS resources are AWS-shaped; multi-cloud means parallel configs, not one config running anywhere). Each provider maps resource types (`aws_instance`, `aws_s3_bucket`) to CRUD API calls and is versioned independently - which is why provider version pinning matters: an unpinned provider upgrade can change resource behavior mid-pipeline.

The resource/data-source split is about ownership. `resource "aws_vpc" "main"` says Terraform owns this VPC's lifecycle. `data "aws_vpc" "shared"` says someone else owns it - another team, another Terraform config, manual creation - and this config only needs to reference it (its ID, its CIDR). Mixing these up is a real failure mode: importing shared infrastructure as a resource in two configs means two configs fighting over one object.

The lifecycle turns all of it into workflow. `init` is per-directory setup. `plan` is the crown jewel: a diff between config, recorded state, and (refreshed) reality, listing every create, update-in-place, and destroy-and-replace before anything happens. `apply` executes; `destroy` is `apply` toward emptiness. In any team setting, plan output is the artifact attached to the pull request - the reviewable, auditable statement of "here is exactly what will change."

---

## How It Actually Works

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# Managed: Terraform owns this bucket's lifecycle
resource "aws_s3_bucket" "artifacts" {
  bucket = "team-a-artifacts"
  tags   = { Team = "team-a", ManagedBy = "terraform" }
}

# Read-only: look up a VPC someone else manages
data "aws_vpc" "shared" {
  tags = { Name = "shared-platform-vpc" }
}

resource "aws_security_group" "api" {
  vpc_id = data.aws_vpc.shared.id       # reference, never modify
}
```

```bash
terraform init          # providers, modules, backend
terraform fmt -check    # CI gate: formatting
terraform validate      # CI gate: internal consistency
terraform plan -out=tfplan
terraform apply tfplan  # applies exactly the reviewed plan
terraform destroy       # tears down everything in state
```

Reading a plan: `+` create, `~` update in place, `-` destroy, `-/+` **replace** - the last one is the line that deserves scrutiny (data loss, downtime).

---

## How It Connects

State - how Terraform remembers what it manages - is the next layer and the deepest interview territory.

[[terraform-iac-questions|Terraform and IaC Question Bank]]

Variables, expressions, and workspaces structure real configurations.

[[terraform-configuration|Terraform Configuration Structure]]

Modules package this into reusable units - the platform-team craft.

[[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]

The AWS resources being provisioned are the Cloud layer's subject matter.

[[aws-platform-questions|AWS Platform Engineering Question Bank]], [[ec2-overview|EC2 Overview]]

---

## Common Misconceptions

Misconception 1: "Terraform is multi-cloud, so one config can deploy to AWS or GCP."
Reality: One *tool and workflow* across clouds; configs are provider-specific. The multi-cloud win is shared skills, review process, and pipelines - not portable configs.

Misconception 2: "`terraform apply` does what the plan showed."
Reality: A bare `apply` re-plans at execution time - reality may have moved. `plan -out` + `apply <planfile>` guarantees the reviewed diff is the executed diff; that's the pattern CI pipelines use.

Misconception 3: "Data sources are just slower variables."
Reality: They're live queries against real infrastructure at plan time, creating an ordering dependency on things outside this config - and a failure mode when the referenced object doesn't exist yet.

---

## Interview Angle

Common question forms:
- "Why Terraform over scripts/CloudFormation/clicking the console?"
- "Resource vs data source?"
- "Walk through init/plan/apply - what does each actually do?"

Answer frame:
Declarative + idempotent + diffable: infrastructure change becomes a reviewed artifact, which is also the audit answer a bank wants. Resource = owned lifecycle, data source = read-only reference to someone else's. Lifecycle: init (setup), plan (config vs state vs refreshed reality → operation list), apply (execute, ideally a saved plan). Flag `-/+` replacement as the thing careful reviewers catch.

---

## Related Notes

- [[terraform-configuration|Terraform Configuration Structure]]
- [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]
- [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [[aws-platform-questions|AWS Platform Engineering Question Bank]]
