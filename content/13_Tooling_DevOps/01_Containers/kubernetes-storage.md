---
title: 13 - Kubernetes Storage
description: "Volumes outlive containers but not pods; PersistentVolumes outlive pods; PersistentVolumeClaims decouple what an app requests from what the cluster provides; StorageClasses provision volumes dynamically - and StatefulSets tie it together with volumeClaimTemplates."
tags: [kubernetes, k8s, storage, persistent-volumes, pvc, storageclass, statefulsets, tooling, layer-9]
status: draft
difficulty: intermediate
layer: 9
domain: tooling
created: 2026-07-07
---

# Kubernetes Storage

> The storage model is a chain of indirection on purpose: pod → claim → volume → StorageClass → cloud disk. The app asks for "10Gi, fast"; the platform decides what that means - the same consumer/provider split as the rest of Kubernetes.

---

## Quick Reference

**Core idea:**
- **Ephemeral volumes** (`emptyDir`): live and die with the pod - scratch space, sharing files between containers in a pod
- **PersistentVolume (PV)**: a cluster resource representing real storage (EBS volume, NFS export) with capacity, access mode, and reclaim policy
- **PersistentVolumeClaim (PVC)**: a namespaced *request* for storage ("10Gi, ReadWriteOnce, class gp3") - pods mount claims, never PVs directly
- **StorageClass**: template for dynamic provisioning - a PVC naming a class triggers creation of the backing disk on demand; no admin pre-provisioning
- **Access modes**: ReadWriteOnce (one node - block storage like EBS), ReadWriteMany (many nodes - file storage like EFS/NFS), ReadOnlyMany
- **Reclaim policy**: Delete (backing disk removed with the PVC) vs Retain (disk survives for manual recovery)
- **StatefulSet + volumeClaimTemplates**: each replica gets its own stable PVC (`data-db-0`, `data-db-1`) that survives pod rescheduling and even StatefulSet deletion

**Tricky points:**
- ReadWriteOnce is per-*node*, not per-pod - two pods on the same node can both mount it
- A PVC stuck Pending usually means no StorageClass, no matching PV, or (with `WaitForFirstConsumer`) no scheduled pod yet
- EBS volumes are zonal - a pod rescheduled to another AZ cannot attach its old volume; `volumeBindingMode: WaitForFirstConsumer` exists to delay provisioning until the pod's zone is known
- Deleting a StatefulSet does not delete its PVCs - data-loss protection that surprises people expecting cleanup

---

## What It Is

Container filesystems vanish on restart, and pods vanish on rescheduling - so Kubernetes layers storage lifetimes. `emptyDir` outlives container restarts within a pod (good for caches and sidecar file-sharing) but dies with the pod. Anything that must survive the pod needs a PersistentVolume: an object wrapping real storage with a lifecycle independent of any workload.

The PVC indirection is the design worth explaining in interviews. Applications don't reference storage infrastructure; they claim requirements - size, access mode, class - and Kubernetes binds the claim to a satisfying volume. The manifest that runs on a laptop's kind cluster ("10Gi, standard") runs unchanged on EKS where "standard" maps to gp3 EBS. Storage details become a platform concern, exactly like Services abstract pod IPs.

StorageClasses complete it with dynamic provisioning: instead of admins pre-creating PVs, a class carries a provisioner (EBS CSI driver, EFS CSI driver) and parameters (volume type, IOPS, encryption); creating a PVC against the class creates the actual disk. The class also sets reclaim policy - whether deleting the claim deletes the data - and binding mode, where `WaitForFirstConsumer` defers disk creation until the consuming pod is scheduled so the disk lands in the right availability zone.

StatefulSets are where storage meets identity. `volumeClaimTemplates` stamp out one PVC per replica with a stable name tied to the pod's ordinal: `db-0` always reattaches to `data-db-0`, even after rescheduling to another node. This - stable storage plus stable network identity plus ordered startup - is what makes databases and brokers runnable on Kubernetes at all, and it's why Deployments (whose interchangeable replicas would fight over one RWO volume) are the wrong controller for them.

---

## How It Actually Works

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: fast }
provisioner: ebs.csi.aws.com
parameters: { type: gp3, encrypted: "true" }
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: app-data }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast
  resources: { requests: { storage: 10Gi } }
```

```yaml
# StatefulSet: one stable PVC per replica
spec:
  serviceName: db
  replicas: 3
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: fast
        resources: { requests: { storage: 20Gi } }
```

```bash
kubectl get pvc                      # Bound / Pending status
kubectl describe pvc app-data        # events explain Pending (no class, no capacity, waiting for consumer)
kubectl get pv                       # cluster-wide volumes and reclaim policy
```

---

## How It Connects

StatefulSets appear in the workload-type comparison; storage identity is *why* they exist as a separate controller.

[[kubernetes-operations-questions|Kubernetes Operations Question Bank]]

The zonal-volume constraint is an AWS networking/AZ fact surfacing inside Kubernetes.

[[aws-platform-questions|AWS Platform Engineering Question Bank]]

Ephemeral `emptyDir` sharing between app and sidecar builds on the multi-container pod model.

[[kubernetes-pod-lifecycle|Kubernetes Pod Lifecycle]]

---

## Common Misconceptions

Misconception 1: "ReadWriteOnce means only one pod can use the volume."
Reality: One *node*. Multiple pods co-scheduled on that node can mount it simultaneously - a real source of "works in dev, breaks when replicas spread" bugs.

Misconception 2: "Deleting the StatefulSet cleans up its storage."
Reality: PVCs from volumeClaimTemplates deliberately survive. Scale-down and deletion keep the data; cleanup is a separate explicit `kubectl delete pvc`.

Misconception 3: "PVs and PVCs are only for databases."
Reality: Anything needing pod-independent state - uploaded files, ML model caches, message-queue data. Conversely, most stateless services need no persistent storage at all, and adding it needlessly couples them to zones and complicates autoscaling.

---

## Interview Angle

Common question forms:
- "Explain PV vs PVC vs StorageClass."
- "How does a StatefulSet keep data across pod rescheduling?"
- "Why is a PVC stuck in Pending?"

Answer frame:
Present the indirection chain and who owns each link (app owns the claim, platform owns classes/provisioners). StatefulSet: volumeClaimTemplates create per-replica PVCs bound to ordinals, so `db-0` reattaches to its disk wherever it lands (same zone, for block storage). Pending PVC: missing/wrong class, no capacity, or WaitForFirstConsumer with an unscheduled pod - `describe` events say which.

---

## Related Notes

- [[kubernetes-basics|Kubernetes Basics]]
- [[kubernetes-pod-lifecycle|Kubernetes Pod Lifecycle]]
- [[kubernetes-operations-questions|Kubernetes Operations Question Bank]]
- [[aws-platform-questions|AWS Platform Engineering Question Bank]]
