---
title: 02 - Terraform Configuration Structure
description: "Variables and outputs define a config's interface, locals hold computed values, count/for_each stamp out resources from data, tfvars files carry per-environment values, workspaces multiply state files - and provisioners are the escape hatch to avoid."
tags: [terraform, iac, variables, outputs, locals, for-each, workspaces, tfvars, provisioners, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-07
---

# Terraform Configuration Structure

> A Terraform configuration has an interface like a function: variables in, outputs out, locals as private intermediates. Everything about writing *good* Terraform is designing that interface deliberately.

---

## Quick Reference

**Core idea:**
- **Input variables**: typed, validated, documented parameters (`variable "instance_type" { type = string, default = ... }`); set via `-var`, `.tfvars` files, or `TF_VAR_name` env vars
- **Outputs**: values exported after apply - consumed by humans, other configs (via remote state), or modules
- **Locals**: named computed expressions reused within the config - derived names, merged tag maps; not settable from outside
- **`count`**: N copies indexed by number; **`for_each`**: copies keyed by map/set - for_each is almost always right (removing one item doesn't shift others' identities)
- **Conditionals**: `condition ? a : b`; the `count = var.enabled ? 1 : 0` idiom toggles resource existence
- **Value precedence** (later wins): defaults → env vars → `terraform.tfvars` → `-var-file` → `-var`
- **Workspaces**: multiple state files under one config directory (`terraform.workspace`); OK for light variation, wrong for real env separation
- **Provisioners** (`local-exec`/`remote-exec`): run scripts at create/destroy - officially a last resort; use user_data/cloud-init, config management, or bake images instead

**Tricky points:**
- Switching `count` to `for_each` (or reordering a counted list) changes resource *addresses* - Terraform plans destroy/create unless you `moved`/`state mv`
- Marking a variable `sensitive` hides it from CLI output but not from state - state files still need protecting
- Workspaces share the same backend and credentials - prod/dev isolation by workspace means one compromised pipeline touches both
- Provisioner failures taint the resource; their actions live entirely outside Terraform's model (no diff, no drift detection)

---

## What It Is

Variables, outputs, and locals give a config the shape of a function, and the discipline that follows is interface design. Variables should be typed (`string`, `number`, `map(string)`, rich object types), constrained (`validation` blocks - "instance_type must start with m5/m6"), and few - every variable is surface area consumers must understand. Outputs are the return values: the VPC ID, the endpoint URL, the role ARN downstream configs need. Locals absorb the middle: computed naming conventions, merged default-plus-custom tag maps, repeated expressions given one name.

`count` and `for_each` turn configuration from prose into data-driven generation. `count` is positional - fine for "3 identical instances," dangerous for lists of distinct things because deleting element 0 renumbers everything after it, and renumbered addresses mean destroy-and-recreate of resources that didn't change. `for_each` keys instances by meaningful strings (`for_each = var.teams` → `aws_iam_role.team["payments"]`), so adding or removing one entry touches only that entry. The platform-engineering significance: for_each over a map of teams/environments/services is how one module stamps out fleet-wide resources - the mechanical heart of "build it once for a hundred teams."

Per-environment values flow through `.tfvars` files: `dev.tfvars`, `prod.tfvars`, selected with `-var-file`. Environment variables (`TF_VAR_db_password`) suit secrets in CI - values that must never land in a file in the repo. The precedence chain (defaults < env vars < tfvars < `-var`) is a small thing that debugging sessions turn into a big thing.

Workspaces multiply state files under one directory - `terraform workspace select staging` - with `terraform.workspace` available in expressions. They shine for cheap parallel copies: preview environments, a developer's sandbox. They fail as *the* environment strategy because everything except state is shared: same backend, same credentials, same code version applied wherever you point. Real prod/dev separation wants separate root configs (or repos) with separate backends, separate AWS accounts, separate pipeline permissions - so that no single misstep can cross the boundary. This is the canonical "when would you *not* use workspaces" answer.

Provisioners are the documented escape hatch: run a script on the machine (remote-exec) or locally (local-exec) at create/destroy time. HashiCorp's own docs call them a last resort, and the reasons are structural - what a script does is invisible to plan, undetectable as drift, and unrepeatable on already-created resources. Idiomatic replacements: cloud-init/user_data for boot configuration, baked AMIs (Packer) for software, dedicated config management where it's genuinely needed.

---

## How It Actually Works

```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "teams" {
  type = map(object({ cpu = number, memory = number }))
}

locals {
  name_prefix = "platform-${var.environment}"
  common_tags = merge(var.extra_tags, { Environment = var.environment, ManagedBy = "terraform" })
}

# One namespace-quota resource per team; keyed, not numbered
resource "aws_iam_role" "team" {
  for_each = var.teams
  name     = "${local.name_prefix}-${each.key}"
  tags     = local.common_tags
}

# Conditional existence
resource "aws_cloudwatch_dashboard" "ops" {
  count = var.environment == "prod" ? 1 : 0
  # ...
}

output "team_role_arns" {
  value = { for k, r in aws_iam_role.team : k => r.arn }
}
```

```bash
terraform plan -var-file=prod.tfvars
TF_VAR_db_password=$SECRET terraform apply     # secret via env, never in a file
terraform workspace new preview-pr-142         # cheap parallel copy
terraform console                              # REPL for testing expressions
```

---

## How It Connects

Builds directly on the resource/provider/lifecycle foundation.

[[terraform-basics|Terraform Basics]]

Variables and outputs *are* the module interface - module design is this note applied at a boundary.

[[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]

The workspaces-vs-separate-configs judgment and state mechanics live in the question bank.

[[terraform-iac-questions|Terraform and IaC Question Bank]]

Secrets-via-environment follows the same rules as application secret handling.

[[secret-management|Secret Management]]

---

## Common Misconceptions

Misconception 1: "count and for_each are interchangeable."
Reality: They produce differently-*addressed* resources. count is positional and reorder-fragile; for_each is key-stable. Migrating between them replans existing resources as destroy/create unless addresses are moved explicitly.

Misconception 2: "Workspaces are Terraform's environments feature."
Reality: Workspaces are parallel state files, nothing more. They isolate state - not credentials, not code versions, not blast radius. Environment separation that matters (prod) wants separate configs, backends, and accounts.

Misconception 3: "`sensitive = true` protects a secret."
Reality: It redacts CLI/plan output only. The value sits in plaintext in state. Real protection = encrypted, access-controlled state + secrets sourced from a manager at apply time, not committed anywhere.

---

## Interview Angle

Common question forms:
- "How do you handle multiple environments in Terraform?"
- "count vs for_each?"
- "When are provisioners appropriate?"

Answer frame:
Environments: tfvars per env at minimum, separate root configs + backends + accounts for real isolation; workspaces only for lightweight parallel copies - and say *why* (shared credentials/backend). for_each over count for anything non-identical, because identity follows keys, not positions. Provisioners: name the alternatives first (user_data, baked images), concede the rare legitimate cases, mention that plan/drift can't see what provisioners did.

---

## Related Notes

- [[terraform-basics|Terraform Basics]]
- [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]
- [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [[secret-management|Secret Management]]
