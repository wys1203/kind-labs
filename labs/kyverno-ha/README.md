# Kyverno HA Zone Spread Lab

This lab installs Kyverno with Helm chart `3.2.8` and applies a mutate policy that injects `topologySpreadConstraints` into selected StatefulSets so their Pods spread across worker nodes labeled with `topology.kubernetes.io/zone=dc1`, `topology.kubernetes.io/zone=dc2`, and `topology.kubernetes.io/zone=dc3`.

## Layout

- `helm/`: Helm values for the Kyverno installation
- `storageclass/`: lab StorageClass manifest for kind simulation
- `policies/`: Kyverno mutation policies
- `demo/`: sample StatefulSet used to verify zone spreading with `block-ssd`
- `tests/`: verification commands and expected checks

## Prerequisites

- kind cluster created from `kind-config.yaml`
- worker nodes labeled by kubelet with:
  - `topology.kubernetes.io/zone=dc1`
  - `topology.kubernetes.io/zone=dc2`
  - `topology.kubernetes.io/zone=dc3`
- a `StorageClass` named `block-ssd`
- `block-ssd` uses `volumeBindingMode: WaitForFirstConsumer`
- `helm` installed
- `kubectl` configured for the target cluster

For kind simulation in this repo, you can create `block-ssd` as a wrapper around the existing `rancher.io/local-path` provisioner:

```sh
make kyverno-storageclass-apply
```

## Important Points

- The policy matches only StatefulSets labeled `ha-zone-spread=enabled`.
- Add label `ha-zone-spread-exempt=true` to skip mutation for an exception workload.
- The mutation is applied on admission for new resources. Existing StatefulSets are not changed because the policy uses `background: false`.
- The policy injects `topologySpreadConstraints` into the Pod template, so the scheduler spreads replicas by the standard node topology key `topology.kubernetes.io/zone`.
- The policy also requires `replicas >= 2` and at least one `volumeClaimTemplate` using `storageClassName: block-ssd`.
- The policy skips StatefulSets that already define `spec.template.spec.topologySpreadConstraints`.
- Real HA requires more than one replica. For this lab, use `replicas: 3` to align with `dc1`, `dc2`, and `dc3`.
- `whenUnsatisfiable: DoNotSchedule` means a Pod can stay `Pending` if the cluster cannot satisfy the spread rule because of missing zone labels, unavailable nodes, or insufficient resources.
- `minDomains: 3` makes the intent explicit for this lab: the scheduler expects three eligible zones.
- The mutation uses an add anchor for `topologySpreadConstraints`, so it is intended to add the field when absent rather than overwrite an existing spread policy.
- This lab improves zone-aware placement, but it does not replace PodDisruptionBudgets, readiness probes, or application-level replication requirements.

## Real Case: `block-ssd` With `ReadWriteOnce`

- `ReadWriteOnce` means one PVC can be mounted read-write by only one node at a time. If multiple Pods try to share the same PVC across zones, Kubernetes can hit attach or mount conflicts.
- For HA workloads with per-replica storage, prefer a StatefulSet with `volumeClaimTemplates` so each replica gets its own PVC instead of sharing one PVC from a Deployment.
- Zone spreading only works cleanly when the storage backend can provision or attach volumes in each target zone. If the volume is effectively pinned to one zone, a spread rule may force Pods into `Pending`.
- `volumeBindingMode: WaitForFirstConsumer` is the correct StorageClass behavior for this policy. It lets the scheduler pick a zone first, then asks the storage provisioner to create or bind the volume in a compatible topology.
- If `block-ssd` uses immediate binding or pre-provisioned PVs tied to a single zone, the storage topology may conflict with `topologySpreadConstraints`.
- If a workload has only one replica and one RWO PVC, zone spread adds no value. The rule matters when you have multiple replicas, each with separate storage.
- If the Pod already has `nodeSelector`, `nodeAffinity`, `podAffinity`, `podAntiAffinity`, or its own `topologySpreadConstraints`, the final scheduling result is the intersection of all rules. This is the main source of surprise.
- `whenUnsatisfiable: DoNotSchedule` is strict. It protects spread goals, but it also makes storage-topology conflicts visible immediately because Pods will remain unscheduled.

## Recommended Guardrails

- Target only workloads that are designed for multi-replica storage, not every Pod that references a PVC.
- Keep the policy opt-in with `ha-zone-spread=enabled`.
- Match only StatefulSets using `volumeClaimTemplates` on `block-ssd`.
- Exclude workloads that already define their own placement rules.
- Exclude workloads that use a single shared RWO claim.
- Prefer `StatefulSet` over `Deployment` for stateful replicas that need one volume per Pod.
- Validate the StorageClass settings first, especially `volumeBindingMode` and any allowed topology configuration from the CSI driver.
- Add an explicit opt-out label or a separate exception policy if some stateful apps must keep vendor-defined scheduling.

## Suggested Exception Cases

- Stateful apps with vendor-managed affinity or topology rules.
- Workloads using local PVs or zonal disks that cannot move freely.
- Single-replica apps with one RWO PVC.
- Apps that already ship with vendor-managed affinity or spread settings.
- Jobs or CronJobs where zone balance is not useful.

## Flow

Bring up the full lab:

```sh
make kyverno-up
```

Check pod placement:

```sh
make kyverno-demo-status
kubectl get pods -n kyverno-ha-demo -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
kubectl get pvc -n kyverno-ha-demo
kubectl get nodes -L topology.kubernetes.io/zone
make kyverno-verify
```

Deploy an exempt example that should not be mutated:

```sh
make kyverno-demo-exception
kubectl get sts zone-spread-exempt-demo -n kyverno-ha-demo -o yaml | sed -n '/topologySpreadConstraints:/,/containers:/p'
```

Clean up:

```sh
make kyverno-down
```

Rebuild from scratch:

```sh
make kyverno-reset
```
