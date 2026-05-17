---
title: 09 - Deploying Python Apps on Kubernetes
description: "Deploying a Python application on Kubernetes requires a Deployment for pod management, a Service for stable network access, ConfigMaps for environment configuration, resource limits for scheduler information, and liveness/readiness probes for safe rolling updates."
tags: [kubernetes, python, fastapi, deployment, configmap, health-checks, probes, tooling, layer-9]
status: draft
difficulty: beginner
layer: 9
domain: tooling
created: 2026-05-18
---

# Deploying Python Apps on Kubernetes

> Deploying a Python application on Kubernetes means writing a set of YAML manifests — Deployment, Service, ConfigMap — that together declare how the application runs, how it is accessed, how it receives configuration, and how Kubernetes knows it is healthy.

---

## Quick Reference

**Core idea:**
- **Deployment**: manages pod replicas and rolling updates
- **Service** (ClusterIP or LoadBalancer): stable network address for the pods
- **ConfigMap**: non-secret environment variables (database host, feature flags)
- **Secret**: sensitive values (database passwords, API keys) — base64-encoded in etcd
- `livenessProbe`: restarts the container when the application is hung
- `readinessProbe`: gates traffic — pods not ready are removed from Service endpoints

**Tricky points:**
- FastAPI's `/docs` endpoint is not a health check endpoint — add a dedicated `/health` route that returns 200 with minimal work
- Resource `requests` tell the scheduler how much CPU/memory to reserve; `limits` cap usage — set both; a pod without requests is unpredictably scheduled
- Secrets are only base64-encoded by default in Kubernetes, not encrypted — use Sealed Secrets, Vault, or cloud-provider secret stores for real security
- `envFrom: configMapRef` injects all ConfigMap keys as environment variables — simpler than listing each `env` item individually
- The pod must complete its current requests before being killed — `terminationGracePeriodSeconds` plus `preStop` hook give the app time to drain

---

## What It Is

A Kubernetes deployment of a Python application is a set of YAML manifests that together define everything about how the application runs in the cluster. Unlike Docker Compose, where one file covers the full local stack, Kubernetes manifests tend to be separate files organized by resource type: a Deployment manifest, a Service manifest, a ConfigMap manifest. These are often organized in a `k8s/` directory and applied with `kubectl apply -k k8s/` (using Kustomize) or individually.

The mental model for a complete deployment is: the Deployment says "run N copies of this container"; the Service says "route traffic to those containers at this stable address"; the ConfigMap says "inject these environment variables into the container"; the readiness probe says "only route traffic to a container if it responds to this health check." Together they describe a self-healing, observable, configurable application that Kubernetes continuously maintains.

Each configuration concern is separated because each has a different lifecycle. The Deployment changes when the application version changes. The Service almost never changes after initial setup. The ConfigMap changes when runtime configuration changes (without requiring a new image build). This separation means a configuration change can be applied without triggering a rolling update — just update the ConfigMap, and if the application reads its config from environment variables at startup, a pod restart (which a ConfigMap change can trigger via annotation) picks up the new values.

---

## How It Actually Works

A complete set of manifests for a FastAPI application:

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
  namespace: production
data:
  DATABASE_HOST: "postgres-service"
  DATABASE_NAME: "appdb"
  LOG_LEVEL: "info"
  WORKERS: "2"
```

```yaml
# secret.yaml (in practice: use Sealed Secrets or Vault, not plain YAML committed to git)
apiVersion: v1
kind: Secret
metadata:
  name: myapp-secrets
  namespace: production
type: Opaque
data:
  DATABASE_PASSWORD: c2VjcmV0cGFzc3dvcmQ=   # base64("secretpassword")
  SECRET_KEY: bXlzZWNyZXRrZXk=              # base64("mysecretkey")
```

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: app
          image: myregistry/myapp:1.5
          ports:
            - containerPort: 8000
          # Inject ConfigMap as environment variables
          envFrom:
            - configMapRef:
                name: myapp-config
          # Inject individual secrets
          env:
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: myapp-secrets
                  key: DATABASE_PASSWORD
            - name: SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: myapp-secrets
                  key: SECRET_KEY
          # Resource limits: required for scheduler and stability
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          # Readiness: gates traffic; must pass before rolling update continues
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10    # Wait 10s before first check
            periodSeconds: 5           # Check every 5s
            failureThreshold: 3        # Fail 3 times before marking not ready
          # Liveness: restarts hung containers
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30    # Longer delay — wait for full startup
            periodSeconds: 10
            failureThreshold: 3
      terminationGracePeriodSeconds: 30    # Time to complete in-flight requests
```

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: production
spec:
  selector:
    app: myapp
  ports:
    - name: http
      port: 80
      targetPort: 8000
  type: ClusterIP    # Internal only; use Ingress for external access
```

The FastAPI health check endpoint that the probes call:

```python
from fastapi import FastAPI

app = FastAPI()

@app.get("/health")
async def health_check():
    # Minimal check: just prove the process is alive and can handle requests
    return {"status": "healthy"}

# For a more thorough readiness check:
@app.get("/ready")
async def readiness_check(db: Session = Depends(get_db)):
    # Check that downstream dependencies are reachable
    try:
        db.execute("SELECT 1")
        return {"status": "ready"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))
```

---

## How It Connects

The Deployment and Service manifests build directly on the Kubernetes concepts of pod management and stable network addressing.

[[kubernetes-deployments|Kubernetes Deployments]]

[[kubernetes-services|Kubernetes Services]]

The image referenced in the Deployment is built from a Dockerfile — multi-stage builds produce the slim runtime image that Kubernetes pulls from the registry.

[[dockerfile-python|Writing a Dockerfile for Python]]

---

## Common Misconceptions

Misconception 1: "I can use `localhost` to connect to my database from the application container."
Reality: `localhost` inside a pod refers to the pod itself. Other services in the cluster are accessed by their Service name (e.g., `postgres-service:5432`). The database Service name becomes the hostname in the connection string: `postgresql://user:pass@postgres-service:5432/dbname`.

Misconception 2: "Secrets in Kubernetes are encrypted and safe to commit to a git repository."
Reality: Kubernetes Secrets are only base64-encoded, not encrypted. Anyone with read access to the cluster's etcd (or with `kubectl get secret -o yaml`) can decode them. For security, use Sealed Secrets (encrypted at rest, safe to commit), HashiCorp Vault, or cloud-provider-native secret managers (AWS Secrets Manager, GCP Secret Manager). Never commit plain Kubernetes Secret YAML with sensitive values to version control.

Misconception 3: "Setting `limits` for CPU means Kubernetes will kill the pod if it exceeds them."
Reality: CPU limits are throttled, not killed. If a container exceeds its CPU limit, the kernel's CFS scheduler throttles it (reduces CPU time allocation) — the process slows but does not die. Memory limits behave differently: exceeding the memory limit causes the container to be OOMKilled (killed by the kernel's OOM killer) and then restarted. Set memory limits carefully — too low a limit causes repeated OOMKills; too high allows a runaway process to starve other pods on the node.

---

## Why It Matters in Practice

A complete Kubernetes deployment for a Python application includes at minimum: Deployment, Service, ConfigMap. Without ConfigMaps, configuration ends up hardcoded in the image — requiring a new image build for every config change. Without resource limits, pods compete unpredictably for node resources. Without readiness probes, rolling updates push traffic to pods before they are ready to handle it, causing errors during deployments.

The health check endpoint (`/health`) is not an afterthought — it is the mechanism by which Kubernetes makes zero-downtime deployments possible. During a rolling update, new pods must pass the readiness probe before old pods receive a SIGTERM. If the `/health` endpoint is missing or always returns 200 even when the application is broken, Kubernetes has no reliable signal and the safety mechanism fails.

---

## Interview Angle

Common question forms:
- "How would you deploy a FastAPI application on Kubernetes?"
- "What Kubernetes resources do you need for a typical Python web service?"

Answer frame:
Walk through the three-resource set: Deployment (replicas, image, probes, resources), Service (ClusterIP for internal, or LoadBalancer/Ingress for external), ConfigMap (environment config). Explain the readiness/liveness probe distinction. Mention Secrets and the caveat that they are base64 not encrypted. Note `terminationGracePeriodSeconds` for graceful shutdown. This demonstrates end-to-end deployment knowledge, not just "write a Deployment YAML."

---

## Related Notes

- [[kubernetes-basics|Kubernetes Basics]]
- [[kubernetes-deployments|Kubernetes Deployments]]
- [[kubernetes-services|Kubernetes Services]]
- [[dockerfile-python|Writing a Dockerfile for Python]]
- [[multi-stage-builds|Multi-Stage Docker Builds]]
- [[fastapi|FastAPI]]
