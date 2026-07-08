---
title: 07 - Master Study Checklist
description: "Checkbox study scaffold for the NAB Platform Engineer prep - Kubernetes, Terraform, CI/CD, RBAC, OOP/design patterns, RAG concepts, and system-design practice prompts - with each item wikilinked to the vault note that covers it."
tags: [interview-prep, nab, platform-engineering, checklist, layer-14]
status: draft
difficulty: intermediate
layer: 14
domain: interview-prep
created: 2026-07-07
---

# Master Study Checklist

> Checkbox format for direct use as a study scaffold — tick items off as they're covered. Items link to the vault note that covers them where one exists; unlinked items are gaps to study from outside the vault. Weighting guidance lives in [[prep-plan|Prioritized Prep Plan]].

---

## 1. Kubernetes (RBAC included here, not separate)

### Core Concepts

- [ ] What Kubernetes is / the container-orchestration problem it solves — [[kubernetes-basics|Kubernetes Basics]]
- [ ] Control plane vs. worker nodes: API server, etcd, scheduler, controller manager, kubelet, kube-proxy, container runtime — [[kubernetes-basics|Kubernetes Basics]]
- [ ] The reconciliation loop — desired state (spec) vs. actual state (status), etcd as source of truth — [[kubernetes-basics|Kubernetes Basics]], [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] Pod lifecycle phases — Pending, Running, Succeeded, Failed, Unknown — [[kubernetes-pod-lifecycle|Kubernetes Pod Lifecycle]]
- [ ] Container Runtime Interface (CRI) — containerd, CRI-O, why Kubernetes is runtime-agnostic — [[kubernetes-pod-lifecycle|Kubernetes Pod Lifecycle]]

### Scheduling

- [ ] Taints and Tolerations — how nodes repel pods unless explicitly tolerated — [[kubernetes-scheduling|Kubernetes Scheduling]]
- [ ] Node Affinity / Anti-affinity — controlling which nodes a pod can land on — [[kubernetes-scheduling|Kubernetes Scheduling]]
- [ ] Pod Affinity / Anti-affinity — controlling placement relative to other pods (e.g., spread replicas across nodes) — [[kubernetes-scheduling|Kubernetes Scheduling]]

### Workload Objects

- [ ] Pods (smallest deployable unit; can hold 1+ containers) — [[kubernetes-basics|Kubernetes Basics]]
- [ ] ReplicaSets (ensures N replicas running) — [[kubernetes-deployments|Kubernetes Deployments]]
- [ ] Deployments (manages ReplicaSets; enables rolling updates/rollbacks) — [[kubernetes-deployments|Kubernetes Deployments]]
- [ ] Jobs (run-to-completion tasks) — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] CronJobs (scheduled Jobs) — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] StatefulSets (stable identity/storage for stateful apps) — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] DaemonSets (one pod per node) — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]

### Networking

- [ ] Services — ClusterIP, NodePort, LoadBalancer, Headless — [[kubernetes-services|Kubernetes Services]]
- [ ] Labels & selectors — how Services find Pods, how Deployments manage their own Pods — [[kubernetes-services|Kubernetes Services]]
- [ ] `port` vs. `targetPort` (Service's own port vs. where it forwards to) — [[kubernetes-services|Kubernetes Services]]
- [ ] In-cluster DNS resolution — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] Ingress (external HTTP/S routing) — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] Network policies (restricting pod-to-pod traffic) — concept level — [[kubernetes-platform-extensions|Kubernetes Platform Extensions]]

### Configuration & Secrets

- [ ] ConfigMaps (non-sensitive config) — get hands-on with mounting one as a volume vs. env var, not just conceptual — [[kubernetes-config-and-secrets|Kubernetes ConfigMaps and Secrets]]
- [ ] Secrets (sensitive data — note: base64-encoded, not encrypted by default) — same, hands-on if time allows — [[kubernetes-config-and-secrets|Kubernetes ConfigMaps and Secrets]], [[secret-management|Secret Management]]
- [ ] Env vars vs. mounted config/secret volumes — [[kubernetes-config-and-secrets|Kubernetes ConfigMaps and Secrets]]

### Storage

- [ ] Volumes — ephemeral vs. persistent — [[kubernetes-storage|Kubernetes Storage]]
- [ ] PersistentVolume (PV) and PersistentVolumeClaim (PVC) — [[kubernetes-storage|Kubernetes Storage]]
- [ ] StorageClass (dynamic provisioning) — [[kubernetes-storage|Kubernetes Storage]]
- [ ] StatefulSet + volumeClaimTemplates — [[kubernetes-storage|Kubernetes Storage]]

### RBAC (Kubernetes-specific)

- [ ] Why RBAC exists — least-privilege principle — [[iam-least-privilege|Principle of Least Privilege]]
- [ ] Role (namespace-scoped) vs. ClusterRole (cluster-wide) — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] RoleBinding vs. ClusterRoleBinding — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] Subjects — Users, Groups, ServiceAccounts
- [ ] ServiceAccounts specifically — workload identity, how Pods authenticate to the API server — IRSA angle in [[aws-platform-questions|AWS Platform Engineering Question Bank]]
- [ ] Rules — apiGroups, resources, verbs (get/list/watch/create/update/patch/delete)
- [ ] Bridge note: maps directly to application RBAC's Role→Permission model (see Section 4) — Subject↔User, Role↔Role, Rule↔Permission, Binding↔"assigned to"

### Scaling & Resource Management

- [ ] Resource requests vs. limits (CPU/memory) — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] Horizontal Pod Autoscaler (HPA) — metrics-based scaling, get this hands-on if the train allows a phone-based interactive scenario — [[kubernetes-autoscaling|Kubernetes Autoscaling and Resource Management]]
- [ ] Vertical Pod Autoscaler (VPA) — brief — [[kubernetes-autoscaling|Kubernetes Autoscaling and Resource Management]]
- [ ] Cluster Autoscaler — node-level scaling, concept only — [[kubernetes-autoscaling|Kubernetes Autoscaling and Resource Management]]
- [ ] Multi-container Pods and init containers — why you'd run more than one container per Pod, what an init container is for — [[kubernetes-pod-lifecycle|Kubernetes Pod Lifecycle]]

### Health & Reliability

- [ ] Liveness vs. readiness vs. startup probes — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] Restart policies — [[kubernetes-pod-lifecycle|Kubernetes Pod Lifecycle]]
- [ ] Rolling updates and rollbacks — [[kubernetes-deployments|Kubernetes Deployments]]
- [ ] Canary and blue-green deployment concepts — [[cicd-design-questions|CI/CD Design Question Bank]]

### Troubleshooting & Operations

- [ ] `kubectl logs`, `kubectl describe`, `kubectl get events` — [[kubernetes-basics|Kubernetes Basics]]
- [ ] Common failure modes — CrashLoopBackOff, OOMKilled, ImagePullBackOff, Pending pods — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] Debugging DNS/networking issues — [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [ ] `kubectl exec` into a running container — [[kubernetes-basics|Kubernetes Basics]]

### Tooling

- [ ] `kubectl` CLI fundamentals — [[kubernetes-basics|Kubernetes Basics]]
- [ ] kubeconfig and contexts — managing/switching between multiple clusters — [[kubernetes-tooling|Kubernetes Tooling]]
- [ ] `kubectl port-forward` — accessing a pod's port locally without a Service — [[kubernetes-tooling|Kubernetes Tooling]]
- [ ] minikube / kind for local dev — [[kubernetes-tooling|Kubernetes Tooling]]
- [ ] Helm and Helm charts — templating, `values.yaml`, releases — [[kubernetes-tooling|Kubernetes Tooling]], [[kubernetes-python|Deploying Python Apps on Kubernetes]]
- [ ] YAML manifest structure — apiVersion, kind, metadata, spec — [[kubernetes-basics|Kubernetes Basics]]

### Advanced / Platform-level (concept literacy, likely not your direct ownership)

- [ ] Managed Kubernetes (EKS/GKE/AKS) vs. self-managed — [[kubernetes-platform-extensions|Kubernetes Platform Extensions]]
- [ ] Kubernetes Operators (custom controllers) — [[kubernetes-platform-extensions|Kubernetes Platform Extensions]]
- [ ] Custom Resource Definitions (CRDs) — how the API itself gets extended; the mechanism Operators are built on — [[kubernetes-platform-extensions|Kubernetes Platform Extensions]]
- [ ] Admission Controllers — validating/mutating webhooks, where the API server enforces policy on requests — [[kubernetes-platform-extensions|Kubernetes Platform Extensions]]
- [ ] Multi-cluster / multi-cloud considerations
- [ ] Security best practices — pod security standards, image scanning, network policies — [[kubernetes-platform-extensions|Kubernetes Platform Extensions]], [[pipeline-security-compliance|Pipeline Security and Compliance]]
- [ ] Private container registries — [[ecr|ECR (Elastic Container Registry)]]

### Observability

- [ ] Prometheus Operator + Exporters (metrics) — [[prometheus-python|Prometheus with Python]], [[observability-questions|Observability Question Bank]]
- [ ] Grafana (visualization) — [[observability-questions|Observability Question Bank]]
- [ ] Log aggregation (ELK / Loki) — [[structured-logging|Structured Logging]], [[logging-production|Production Logging]]

---

## 2. Terraform

### Core Concepts

- [ ] Infrastructure as Code — why declarative over imperative scripting — [[terraform-basics|Terraform Basics]]
- [ ] Providers (AWS, GCP, Azure, etc.) — [[terraform-basics|Terraform Basics]]
- [ ] Resources vs. Data Sources — [[terraform-basics|Terraform Basics]]
- [ ] Lifecycle — init, plan, apply, destroy — [[terraform-basics|Terraform Basics]]
- [ ] Open-source Terraform vs. Terraform Cloud vs. Terraform Enterprise — the three tiers and what each adds — [[terraform-basics|Terraform Basics]], [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]

### State Management

- [ ] What the state file is and why it matters — [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [ ] Remote state (S3 backend — standard AWS pattern) — [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [ ] State locking (DynamoDB lock table) — [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [ ] `terraform import` — bringing existing infra under management — [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [ ] Drift detection and reconciliation — [[terraform-iac-questions|Terraform and IaC Question Bank]]

### Configuration Structure

- [ ] Input variables and Outputs — [[terraform-configuration|Terraform Configuration Structure]]
- [ ] Local values (`locals` block) — computed values reused within a config — [[terraform-configuration|Terraform Configuration Structure]]
- [ ] Functions and expressions — `count`, `for_each`, conditional expressions — [[terraform-configuration|Terraform Configuration Structure]]
- [ ] Environment variables vs. `.tfvars` files — [[terraform-configuration|Terraform Configuration Structure]]
- [ ] Provisioners — when to use, when to avoid — [[terraform-configuration|Terraform Configuration Structure]]
- [ ] Workspaces — managing multiple environments — [[terraform-configuration|Terraform Configuration Structure]], [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [ ] Basic CLI hygiene — `terraform validate`, `terraform fmt` — [[terraform-basics|Terraform Basics]]

### Modules

- [ ] Why modules — reusability, encapsulation — [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]
- [ ] Module structure — `variables.tf`, `outputs.tf`, `main.tf` — [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]
- [ ] Versioning modules — [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]], [[semantic-versioning|Semantic Versioning]]
- [ ] Public registry modules vs. custom internal modules — [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]

### Policy & Governance

- [ ] Sentinel / OPA — policy-as-code concept — [[terraform-iac-questions|Terraform and IaC Question Bank]]
- [ ] Why enterprises/banks need compliance gates before `apply` — [[pipeline-security-compliance|Pipeline Security and Compliance]]

### Terraform Enterprise (NAB specifically runs this, not vanilla OSS Terraform)

- [ ] Private module registry — internal, versioned modules shared org-wide — [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]], [[nab-nef-context|NAB, NEF and Banking Domain Context]]
- [ ] Sentinel policy enforcement built into the apply pipeline itself (not bolted on after) — [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]
- [ ] Remote execution — runs happen on Terraform's infrastructure, not your laptop — [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]
- [ ] Team-based access controls on workspaces — [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]
- [ ] Why this matters for the interview: "how do you enforce policy before infra changes go live" is a Terraform Enterprise answer, not a vanilla-Terraform one — [[terraform-modules-and-enterprise|Terraform Modules and Terraform Enterprise]]

### AWS-specific (your strength — deepen, don't relearn)

- [ ] VPC, subnets, route tables, security groups, NACLs — [[aws-platform-questions|AWS Platform Engineering Question Bank]], [[ec2-security-groups|EC2 Security Groups]]
- [ ] EC2, S3, IAM roles/policies — [[iam-roles|IAM Roles]], [[iam-policies|IAM Policies]]
- [ ] ALB/NLB provisioning via Terraform — [[ec2-elb|Elastic Load Balancer]]

---

## 3. CI/CD

### General Concepts

- [ ] Pipeline stages — build, test, deploy, where security scanning fits — [[cicd-design-questions|CI/CD Design Question Bank]], [[ci-testing-pipeline|CI Testing Pipeline]]
- [ ] CI vs. Continuous Delivery vs. Continuous Deployment — the actual distinctions — [[cicd-overview|CI/CD Overview]]
- [ ] Artifact management/versioning — [[cicd-overview|CI/CD Overview]], [[semantic-versioning|Semantic Versioning]]
- [ ] Rollback strategies — [[cicd-design-questions|CI/CD Design Question Bank]]
- [ ] Blue-green vs. canary deployment patterns — [[cicd-design-questions|CI/CD Design Question Bank]]

### GitHub Actions (your strength)

- [ ] Workflow YAML structure — triggers, jobs, steps — [[github-actions-basics|GitHub Actions Basics]]
- [ ] Runners — hosted vs. self-hosted — [[github-actions-basics|GitHub Actions Basics]]
- [ ] Secrets management in Actions — [[github-actions-python|GitHub Actions for Python]]
- [ ] Reusable workflows / composite actions

### Harness (NAB-specific — conceptual literacy)

- [ ] Pipelines and stages — [[harness-concepts|Harness Concepts]]
- [ ] Delegates — what they are, why they exist — [[harness-concepts|Harness Concepts]]
- [ ] OPA policy gates within pipelines — [[harness-concepts|Harness Concepts]]
- [ ] Canary/blue-green verification built into Harness — [[harness-concepts|Harness Concepts]]

### GitOps (general, increasingly standard in platform engineering)

- [ ] The GitOps model — git as the single source of truth, a controller reconciles cluster state to match it — [[gitops|GitOps]]
- [ ] ArgoCD / FluxCD — what problem they solve vs. a push-based pipeline — [[gitops|GitOps]]
- [ ] Pull-based (GitOps) vs. push-based (traditional CI/CD) deployment — the actual tradeoff — [[gitops|GitOps]]

### Broader tool landscape (awareness, not depth)

- [ ] Jenkins, GitLab CI, CircleCI — know what they are and roughly how they differ from GitHub Actions/Harness — [[cicd-overview|CI/CD Overview]]

### Security in the pipeline

- [ ] Vulnerability scanning (images/dependencies) — [[dependency-scanning|Dependency Vulnerability Scanning]]
- [ ] Secrets scanning — [[secrets-in-python|Handling Secrets in Python]]
- [ ] SAST/DAST — concept level — [[bandit|Bandit (Python Security Linter)]], [[pipeline-security-compliance|Pipeline Security and Compliance]]

---

## 4. RBAC — Application-level (general, separate from K8s mechanics above)

- [ ] RBAC vs. ABAC — role-based vs. attribute-based access control — [[rbac-and-sso|RBAC, ABAC and Enterprise SSO]]
- [ ] Core model — Users, Roles, Permissions, Role-assignment — [[rbac-and-sso|RBAC, ABAC and Enterprise SSO]], [[authentication-vs-authorization|Authentication vs Authorization]]
- [ ] JWT-based auth flow — token issuance, claims, verification — [[jwt|JWT]]
- [ ] OAuth2 vs. session-based auth — when each fits — [[oauth2|OAuth2]], [[session-based-auth|Session-Based Auth]]
- [ ] OIDC (OpenID Connect) and SAML — common enterprise SSO protocols, how they relate to OAuth2 — [[rbac-and-sso|RBAC, ABAC and Enterprise SSO]]
- [ ] Principle of least privilege — [[iam-least-privilege|Principle of Least Privilege]]
- [ ] Your real anchors: Orqa (Payroll Admin → view/edit timesheets), DAG Builder project (JWT + RBAC auth)

---

## 5. OOP and Design Patterns

### OOP Fundamentals

- [ ] Encapsulation — [[encapsulation|Encapsulation]]
- [ ] Abstraction — [[abstraction|Abstraction]]
- [ ] Inheritance — [[inheritance-oop|Inheritance]]
- [ ] Polymorphism — [[polymorphism|Polymorphism]]

### SOLID Principles

- [ ] Single Responsibility — [[srp|Single Responsibility Principle]]
- [ ] Open/Closed — [[ocp|Open/Closed Principle]]
- [ ] Liskov Substitution — [[lsp|Liskov Substitution Principle]]
- [ ] Interface Segregation — [[isp|Interface Segregation Principle]]
- [ ] Dependency Inversion — [[dip|Dependency Inversion Principle]] (overview: [[solid-principles|SOLID Principles]])

### Python-specific mechanics

- [ ] Dunder methods (`__init__`, `__repr__`, `__eq__`, `__len__`, etc.) — [[dunder-methods|Dunder Methods]]
- [ ] `classmethod` vs. `staticmethod` vs. instance method — [[classmethod-staticmethod|classmethod and staticmethod]]
- [ ] Properties (`@property`) — [[properties|Properties]]
- [ ] Composition vs. inheritance — when to choose which — [[composition-over-inheritance|Composition over Inheritance]]
- [ ] Abstract base classes (`ABC` module) — [[abstract-base-classes|Abstract Base Classes]]
- [ ] Multiple inheritance and MRO (Method Resolution Order) — [[mro|Method Resolution Order]]

### Design Patterns (relevant to your FastAPI/backend work)

- [ ] Dependency Injection (on your resume — FastAPI's `Depends` system specifically) — [[dependency-injection-pattern|Dependency Injection]]
- [ ] Inversion of Control (IoC) — the broader principle DI is one implementation of — [[dependency-injection-pattern|Dependency Injection]]
- [ ] Singleton — [[singleton|Singleton]]
- [ ] Factory / Factory Method — [[factory-method|Factory Method]], [[abstract-factory|Abstract Factory]]
- [ ] Builder — constructing complex objects step by step — [[builder-pattern|Builder Pattern]]
- [ ] Strategy — [[strategy-pattern|Strategy Pattern]]
- [ ] Observer — [[observer-pattern|Observer Pattern]]
- [ ] Decorator — [[decorator-pattern|Decorator Pattern]] (language mechanics: [[decorators|Decorators]])
- [ ] Adapter — [[adapter-pattern|Adapter Pattern]]
- [ ] Repository pattern — [[repository-pattern|Repository Pattern]]

### Language-adjacent

- [ ] Java Collections Framework — List/Set/Map, ArrayList vs. LinkedList, HashMap conceptually (lower priority, Python is your working language)

---

## 6. RAG Concepts

### Pipeline Stages

- [ ] Ingestion — parsing PDF/Word/code/text — [[rag-pipeline|RAG Pipeline]]
- [ ] Chunking strategies — semantic similarity chunking (text) vs. AST-based chunking (code) — your own resume claim, know this well — [[chunking-strategies|Chunking Strategies]]
- [ ] Chunk size/overlap tuning — the practical tradeoff between context and precision — [[chunking-strategies|Chunking Strategies]]
- [ ] Embeddings — what they are, cosine similarity for search — [[embeddings|Embeddings]], [[similarity-metrics|Similarity Metrics]]
- [ ] Vector databases — ChromaDB, Pinecone — what problem they solve vs. traditional DBs — [[vector-databases|Vector Databases]]
- [ ] Retrieval — top-k similarity search, re-ranking models — [[retrieval-strategies|Retrieval Strategies]], [[reranking|Reranking]]
- [ ] Generation — how retrieved context gets injected into the prompt — [[rag|RAG]]
- [ ] Evaluation — retrieval precision/recall, faithfulness/groundedness metrics (RAGAS-style frameworks), not just "your resume's model-evaluation layer" in the abstract — [[rag-evaluation|RAG Evaluation]]

### LLM Integration Concepts

- [ ] Prompt engineering fundamentals — [[prompt-engineering|Prompt Engineering]]
- [ ] Multi-model routing (your resume: OpenAI/Claude/Gemini/Ollama) — why route to different models — [[llm-routing-and-guardrails|LLM Routing and Guardrails]]
- [ ] AI guardrails — what they check, how they're implemented — [[llm-routing-and-guardrails|LLM Routing and Guardrails]]
- [ ] Context window limits and their effect on chunking/retrieval design — [[context-window|Context Window]]

### Broader GenAI Platform Concepts

- [ ] RAG vs. fine-tuning vs. prompt engineering — when each is the right tool — [[fine-tuning-basics|Fine-Tuning Basics]]
- [ ] Hallucination mitigation strategies — [[llm-routing-and-guardrails|LLM Routing and Guardrails]]
- [ ] Latency/cost tradeoffs across retrieval/generation strategies — [[llm-routing-and-guardrails|LLM Routing and Guardrails]]
- [ ] Agentic RAG / multi-hop retrieval — an emerging pattern where retrieval itself becomes iterative/tool-using rather than single-shot — [[advanced-rag|Advanced RAG]]

---

## 7. Synthesis / System Design Practice (different from the rest — a practice modality, not a reading topic)

Everything above is single-topic. A real technical round is more likely to ask something that forces you to combine K8s + Terraform + CI/CD + observability into one live, coherent design — this is genuinely different muscle from recalling definitions.

**Practice prompts (talk through out loud, don't just read):**

- [ ] Design an on-demand, ephemeral environment system — spins up automatically from a developer portal request, provisions all dependencies, runs test automation as part of the spin-up, tears down after. (This is directly named in the JD — "Implementing Ephemeral Infrastructure.") — answer frame in [[cicd-design-questions|CI/CD Design Question Bank]]
- [ ] Design a self-service internal developer platform for 100+ engineering squads — what's the golden path, what's the guardrail, what's configurable vs. fixed? — [[nab-nef-context|NAB, NEF and Banking Domain Context]]
- [ ] Design the CI/CD pipeline for a new microservice from scratch — what stages, what gates, what rolls back and how? — [[cicd-design-questions|CI/CD Design Question Bank]]
- [ ] Given a service that needs to scale from 10 to 10,000 requests/sec, walk through what changes at each layer — Kubernetes, networking, database, observability — [[scalability-basics|Scalability Basics]], [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]

**Method for each:** clarify requirements → name the components (which K8s objects, which Terraform-provisioned infra, which pipeline stages, what gets monitored) → name the failure modes → name the tradeoffs. Anchor pieces of it in what you've actually built where you can (the DAG Builder's self-service model is a real analogue to the developer-portal prompt above).

---

## Related Notes

- [[prep-plan|Prioritized Prep Plan]]
- [[gap-analysis|Gap Analysis]]
- [[jd-breakdown|NAB JD Breakdown]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
