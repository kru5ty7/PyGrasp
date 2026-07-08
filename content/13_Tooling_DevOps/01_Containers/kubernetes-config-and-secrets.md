---
title: 12 - Kubernetes ConfigMaps and Secrets
description: "ConfigMaps carry non-sensitive configuration and Secrets carry sensitive data (base64-encoded, not encrypted by default) - both inject into pods as environment variables or mounted volumes, with different update and exposure semantics."
tags: [kubernetes, k8s, configmaps, secrets, configuration, volumes, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-07
---

# Kubernetes ConfigMaps and Secrets

> The most-repeated interview fact in this area: Kubernetes Secrets are base64-*encoded*, not encrypted - base64 is an encoding anyone can reverse, so real secret hygiene needs encryption at rest, RBAC, and usually an external secrets manager.

---

## Quick Reference

**Core idea:**
- **ConfigMap**: key-value config for non-sensitive data (feature flags, URLs, config files) - decouples config from images so one image runs in every environment
- **Secret**: same mechanics for sensitive data; values base64-encoded in etcd, **not encrypted by default** - enable encryption at rest + restrict RBAC on secrets
- Two injection paths: **environment variables** (snapshot at container start, never updates) vs **mounted volume** (files; updates propagate to running pods within ~a minute)
- `envFrom` imports all keys at once; `valueFrom` picks single keys
- Mounted Secrets live on tmpfs (RAM) on the node - never written to node disk
- Production pattern: sync from an external manager (AWS Secrets Manager / Vault) via External Secrets Operator or CSI driver, rather than hand-managed Secret objects

**Tricky points:**
- Env-var injection requires a pod restart to pick up changes; volume mounts update in place (but the app must re-read the file)
- `kubectl get secret -o yaml` shows base64 - decoding is one `| base64 -d` away; RBAC `get` on secrets is effectively plaintext access
- Secrets in env vars leak easily - crash dumps, `kubectl describe`, child processes, logging frameworks that dump the environment
- A pod referencing a missing ConfigMap key with `valueFrom` fails to start (`CreateContainerConfigError`)

---

## What It Is

Both objects solve the same problem - getting configuration out of container images - with the same two delivery mechanisms and one classification difference: is the value sensitive? Config baked into images forces a rebuild per environment and per change; ConfigMaps/Secrets let the same immutable image ship everywhere, with the environment supplying values at runtime. This is the Kubernetes-native version of the twelve-factor "config in the environment" rule.

The delivery choice matters more than it looks. Environment variables are simple and language-agnostic but frozen at container start: rotating a value means restarting pods, and env vars leak through introspection surfaces (process listings, error reporters, debug endpoints). Volume mounts deliver keys as files; the kubelet refreshes them when the object changes, so an app that re-reads files (or watches them) can pick up rotated values without restart - and files on tmpfs don't show up in `describe` output or environment dumps. The common-sense rule: env vars for boring config, mounted files for secrets and anything that rotates.

The Secret caveat everyone gets asked: base64 is not encryption. Out of the box, a Secret in etcd is reversible encoding. Hardening is layered: encryption at rest for etcd, RBAC narrowing who can `get`/`list` secrets, audit logging on secret access, and - in most platform setups - not storing the source of truth in Kubernetes at all, but syncing from AWS Secrets Manager/Vault so rotation, versioning, and audit live in a purpose-built system.

---

## How It Actually Works

```bash
kubectl create configmap app-config --from-literal=LOG_LEVEL=info --from-file=app.yaml
kubectl create secret generic db-creds --from-literal=password='s3cr3t'
```

```yaml
spec:
  containers:
    - name: app
      image: myapp:1.0
      envFrom:
        - configMapRef: { name: app-config }     # all keys as env vars
      env:
        - name: DB_PASSWORD                       # single key from a Secret
          valueFrom:
            secretKeyRef: { name: db-creds, key: password }
      volumeMounts:
        - name: config-vol
          mountPath: /etc/app                    # keys appear as files
          readOnly: true
  volumes:
    - name: config-vol
      configMap: { name: app-config }
```

Env vars snapshot at start; the `/etc/app/app.yaml` file updates in place after `kubectl apply` of a changed ConfigMap. Verify with `kubectl exec my-pod -- cat /etc/app/app.yaml`.

---

## How It Connects

The same secret-hygiene principles as application-level secret handling - out of code, out of images, injected at runtime.

[[secrets-in-python|Handling Secrets in Python]], [[secret-management|Secret Management]]

In the AWS platform picture, the source of truth is SSM/Secrets Manager with IRSA-scoped access; Kubernetes Secrets are the last-mile delivery.

[[aws-platform-questions|AWS Platform Engineering Question Bank]]

Pipeline secret handling (masking, OIDC, scanning) is the CI/CD half of the same story.

[[cicd-design-questions|CI/CD Design Question Bank]]

---

## Common Misconceptions

Misconception 1: "Kubernetes Secrets are encrypted."
Reality: Base64-encoded only, by default. Encryption at rest is an opt-in etcd configuration (or the cloud provider's default on managed clusters - check, don't assume). RBAC is the real gate.

Misconception 2: "Updating a ConfigMap updates my running app."
Reality: Only volume-mounted keys refresh in running pods, and only if the app re-reads the file. Env vars never refresh; Deployments commonly roll pods on config change (checksum annotation) to force a clean pickup.

Misconception 3: "Env vars and mounted files are interchangeable."
Reality: Different update semantics (frozen vs refreshed), different exposure (environment leaks broadly; tmpfs files don't), different failure modes. The choice is a real design decision.

---

## Interview Angle

Common question forms:
- "How do you get config and secrets into a pod - and which method when?"
- "Are Kubernetes Secrets secure by default?"
- "How do you rotate a secret without downtime?"

Answer frame:
Two objects, two injection paths; env vars for static non-sensitive config, mounted volumes for secrets and rotating values. Lead with the base64-not-encryption fact, then the hardening layers (encryption at rest, RBAC, audit) and the platform pattern: external manager as source of truth, synced into the cluster. Rotation: mounted files + app re-read, or rolling restart triggered by config checksum.

---

## Related Notes

- [[kubernetes-basics|Kubernetes Basics]]
- [[secret-management|Secret Management]]
- [[secrets-in-python|Handling Secrets in Python]]
- [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [[pipeline-security-compliance|Pipeline Security and Compliance]]
