---
title: 17 - Kubernetes Operations Question Bank
description: "Platform-engineering interview questions on Kubernetes operations - workload types, the kubectl apply flow, pod troubleshooting (CrashLoopBackOff, OOMKilled, Pending), probes, RBAC, networking, and rollout strategies - with answer frames and links to the underlying concept notes."
tags: [kubernetes, k8s, interview-prep, troubleshooting, rbac, probes, tooling, layer-9]
status: draft
difficulty: advanced
layer: 9
domain: tooling
created: 2026-07-06
---

# Kubernetes Operations Question Bank

> Interview prep — Platform Engineering. Platform teams *run* clusters, so interviews probe operations depth, not just deployment mechanics: what happens under the hood, how things break, and how you debug them. Questions inferred from a Platform Engineer (SDE2) JD plus standard platform-engineering interview patterns.

---

## Workload Types

**Q: Deployment vs StatefulSet vs DaemonSet vs Job/CronJob — when is each the right choice?**

Answer frame: Deployment for stateless replicas with rolling updates ([[kubernetes-deployments|Kubernetes Deployments]]); StatefulSet when pods need stable identity, stable storage, and ordered startup (databases, brokers); DaemonSet for one-pod-per-node agents (log shippers, CNI plugins, node exporters); Job for run-to-completion work and CronJob for scheduled runs. The differentiator to name: what guarantee the controller provides about pod identity and lifecycle.

---

## The `kubectl apply` Flow

**Q: What happens end-to-end when you run `kubectl apply` on a Deployment manifest?**

Answer frame: kubectl sends the manifest to the API server → authentication/authorization/admission → object persisted in etcd → Deployment controller sees the new desired state and creates/updates a ReplicaSet → ReplicaSet controller creates Pods → scheduler assigns unscheduled Pods to nodes → kubelet on each node pulls images and starts containers → kube-proxy/CNI wire up networking. The core insight is the reconciliation model — independent control loops each driving actual state toward desired state ([[kubernetes-basics|Kubernetes Basics]]).

---

## Troubleshooting (expect the deepest probing here)

**Q: A pod is in CrashLoopBackOff / OOMKilled / Pending — debug step by step.**

Answer frame:
- **CrashLoopBackOff**: the container starts and exits repeatedly. `kubectl describe pod` for events and last state, `kubectl logs --previous` for the dying container's output. Usual causes: bad command/config, missing env/secret, failing liveness probe killing a healthy-but-slow app.
- **OOMKilled**: the container exceeded its memory limit and the kernel killed it. Check `describe` (exit code 137, reason OOMKilled), compare actual usage against `resources.limits.memory`, then either fix the leak or raise the limit.
- **Pending**: the pod was accepted but cannot be scheduled. `describe` shows why: insufficient CPU/memory on any node, unsatisfiable nodeSelector/affinity, taints without tolerations, or unbound PVC.

**Q: A service is unreachable in-cluster — where do you look?**

Answer frame: Is the Service selector actually matching pod labels (`kubectl get endpoints`)? Are the pods Ready (readiness probe failing removes them from endpoints)? Does in-cluster DNS resolve the service name (CoreDNS)? Then CNI/network-policy layer ([[kubernetes-services|Kubernetes Services]]).

---

## Probes and Resources

**Q: Liveness vs readiness vs startup probes; requests vs limits; what happens without limits?**

Answer frame: readiness gates traffic (pod removed from Service endpoints when failing), liveness restarts the container, startup gives slow-starting apps time before liveness kicks in. Wrong answer to flag: using a liveness probe where readiness is needed — it turns a slow dependency into a restart loop. Requests are what the scheduler reserves; limits are the enforcement ceiling. Without limits a pod can starve neighbors (CPU) or trigger node-level OOM kills of *other* pods (memory) — on shared platform clusters, limits are a tenancy-isolation tool, not an optimization.

---

## Networking

**Q: Services, Ingress, in-cluster DNS. What is a CNI?**

Answer frame: Service = stable virtual IP + DNS name over an ever-changing pod set; Ingress = L7 HTTP routing into the cluster through an ingress controller; every Service gets a DNS record (`svc.namespace.svc.cluster.local`) served by CoreDNS. CNI (Container Network Interface) is the plugin layer that gives each pod an IP and wires pod-to-pod routing (e.g. the AWS VPC CNI assigns pods real VPC IPs on EKS).

---

## RBAC

**Q: Restrict a team's access to their own namespace.**

Answer frame: Role (namespaced permission set) + RoleBinding (attach to the team's group/service account) inside the team's namespace; ClusterRole/ClusterRoleBinding only for genuinely cluster-wide needs. On EKS, map the team's IAM role to a Kubernetes group. The platform framing interviewers want: namespace-per-team with RBAC + ResourceQuota + NetworkPolicy is the standard multi-tenancy baseline — same least-privilege instinct as [[iam-least-privilege|Principle of Least Privilege]].

---

## Rollouts

**Q: How do rolling updates work? How would you do a canary on Kubernetes?**

Answer frame: Deployment rolling update creates a new ReplicaSet and scales it up while scaling the old one down, bounded by `maxSurge`/`maxUnavailable`; readiness probes gate each step; `kubectl rollout undo` reverts ([[kubernetes-deployments|Kubernetes Deployments]]). Plain Deployments cannot do weighted canaries — for that, run two Deployments behind one Service and shift replica ratios, or use ingress/mesh traffic splitting, or a progressive-delivery controller (Argo Rollouts, Flagger) that automates promotion/rollback on metrics. See [[cicd-design-questions|CI/CD Design Question Bank]] for the deployment-strategy trade-offs.

---

## Gap-Probe

**Q: "Did you operate the EKS cluster yourself, or deploy to one managed by another team?"**

Prepare a truthful answer. If the experience is deploy-onto (Helm charts, Jobs/CronJobs, probes, resource limits — but not cluster networking, upgrades, or RBAC administration), say so plainly and pivot to the operations theory above plus speed of deepening. Claiming operations experience you don't have gets exposed within two follow-up questions.

---

## Related Notes

- [[kubernetes-basics|Kubernetes Basics]]
- [[kubernetes-deployments|Kubernetes Deployments]]
- [[kubernetes-services|Kubernetes Services]]
- [[kubernetes-python|Deploying Python Apps on Kubernetes]]
- [[docker-basics|Docker Basics]]
- [[cicd-design-questions|CI/CD Design Question Bank]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
