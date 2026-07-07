---
title: 50 - AWS Platform Engineering Question Bank
description: "Platform-engineering interview questions on AWS - VPC networking design, IAM roles vs users, IRSA for pod-level S3 access, secrets management across environments, and cross-account access architecture for internal platform services."
tags: [aws, cloud, layer-11, vpc, iam, irsa, secrets, interview-prep]
status: draft
difficulty: advanced
layer: 11
domain: cloud
created: 2026-07-06
---

# AWS Platform Engineering Question Bank

> Interview prep — Platform Engineering. Cloud questions at platform interviews test *design ownership*: not "have you used S3" but "walk me through the VPC you designed" and "architect cross-account access for 50 teams." Every answer at a bank should end with one sentence on least privilege and auditability.

---

## VPC Networking

**Q: Walk through the networking of a VPC you designed — subnets, route tables, NAT, security groups vs NACLs.**

Answer frame: CIDR sized for growth, split across at least two AZs; public subnets (route to an Internet Gateway) hold only entry points like ALBs ([[ec2-elb|Elastic Load Balancer]]); private subnets hold workloads, with outbound-only internet via NAT Gateway per AZ; isolated subnets for data stores with no internet route at all ([[rds|RDS]]). Security groups are stateful, instance/ENI-level, allow-only — the primary tool ([[ec2-security-groups|EC2 Security Groups]]); NACLs are stateless, subnet-level, ordered allow/deny rules — a coarse second layer. Mention VPC endpoints (S3/DynamoDB gateway endpoints, interface endpoints for other services) to keep traffic off the public internet — both a security and an audit win.

---

## IAM

**Q: IAM roles vs users/policies. How would you grant an EKS pod access to S3 securely?**

Answer frame: users are long-lived credentials for humans (avoid for workloads); roles are assumable identities with temporary credentials ([[iam-roles|IAM Roles]], [[iam-assume-role|Assuming IAM Roles (STS)]]); policies define the permissions attached to either ([[iam-policies|IAM Policies]]). For the EKS pod: **IRSA (IAM Roles for Service Accounts)** — the cluster's OIDC provider is registered with IAM, the pod's Kubernetes service account is annotated with a role ARN, and the pod exchanges its projected service-account token for temporary role credentials via STS. Result: pod-level (not node-level) permissions, no static keys, scoped to exactly the bucket needed ([[iam-least-privilege|Principle of Least Privilege]]). Wrong answers to explicitly reject: access keys in env vars or secrets, and broad node-instance-profile permissions shared by every pod on the node ([[iam-instance-profile|EC2 Instance Profiles]]).

---

## Secrets

**Q: How do you manage secrets across environments?**

Answer frame: a secrets manager as the single source — SSM Parameter Store (SecureString) or Secrets Manager (adds native rotation) — with per-environment paths/keys, IAM-scoped so prod roles can read only prod secrets, KMS encryption at rest, access fully audit-logged via CloudTrail, and injection at deploy/runtime rather than baked into images or repos ([[secret-management|Secret Management]], [[secrets-in-python|Handling Secrets in Python]], [[lambda-environment|Lambda Environment Variables]]). If you have a real SSM story, lead with it.

---

## Cross-Account Design

**Q: An internal service must be reachable by 50 teams across accounts — architect the access.**

Answer frame: two layers. **Network**: AWS PrivateGateway options — VPC peering doesn't scale to 50 (n² meshes); use Transit Gateway (hub-and-spoke) or, cleanest for one service, AWS PrivateLink — publish the service behind an NLB as a VPC endpoint service and each team creates an interface endpoint; no CIDR overlap issues, no transitive routing exposure. **Identity**: cross-account IAM roles that consumer teams assume ([[iam-assume-role|Assuming IAM Roles (STS)]]), or resource policies allowing specific external principals, plus API-level authN/authZ ([[api-gateway-aws|AWS API Gateway]]). Platform touches that score points: self-service onboarding (teams request access through automation, not tickets), quotas per consumer, and every access decision logged.

---

## Gap-Probe

**Q: "Multi-cloud? GCP or Azure?"** — if AWS-only, say so; the transferable layer is the concepts (identity federation, network segmentation, managed Kubernetes) and IaC that abstracts providers ([[terraform-iac-questions|Terraform and IaC Question Bank]]).

---

## Related Notes

- [[iam-roles|IAM Roles]]
- [[iam-assume-role|Assuming IAM Roles (STS)]]
- [[iam-least-privilege|Principle of Least Privilege]]
- [[ec2-security-groups|EC2 Security Groups]]
- [[secret-management|Secret Management]]
- [[ecs|ECS (Elastic Container Service)]]
- [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
