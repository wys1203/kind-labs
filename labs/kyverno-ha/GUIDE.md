# Kyverno HA Policy Guide

## Purpose

This guide explains the design behind the policy in `policies/mutate-zone-spread.yaml`.

The goal is to help stateful workloads spread replicas across multiple zones by automatically injecting `topologySpreadConstraints` when the workload is a good fit for that behavior.

This lab assumes:

- Kubernetes nodes are labeled with `topology.kubernetes.io/zone`
- zones are `dc1`, `dc2`, and `dc3`
- the storage class is `block-ssd`
- `block-ssd` uses `WaitForFirstConsumer`
- workloads use `ReadWriteOnce` volumes with one PVC per replica

## Problem Statement

For stateful HA workloads, placing all replicas in one zone creates a failure domain problem. If that zone becomes unavailable, all replicas may become unavailable together.

At the same time, storage-backed workloads cannot be treated like stateless Deployments:

- one `ReadWriteOnce` PVC cannot be safely shared across multiple nodes
- storage topology may constrain where a Pod can run
- some stateful applications already define their own placement logic

So the policy should not mutate every Pod or every workload with a PVC. It must be selective.

## Policy Design

The policy mutates only `StatefulSet` resources that satisfy all of these conditions:

- label `ha-zone-spread=enabled` is present
- `spec.replicas >= 2`
- at least one `volumeClaimTemplate` uses `storageClassName: block-ssd`
- the Pod template does not already define `topologySpreadConstraints`
- the workload is not marked with `ha-zone-spread-exempt=true`

If all conditions match, Kyverno injects:

- `topologyKey: topology.kubernetes.io/zone`
- `maxSkew: 1`
- `whenUnsatisfiable: DoNotSchedule`
- `minDomains: 3`

## Why This Design

### Why `StatefulSet`

`StatefulSet` is the right default for storage-backed HA replicas because each Pod can have its own PVC through `volumeClaimTemplates`.

That fits `ReadWriteOnce` storage. Each replica gets:

- its own identity
- its own PVC
- its own scheduling decision

Using a generic `Deployment` with one shared RWO claim is usually wrong for multi-zone HA.

### Why opt-in with `ha-zone-spread=enabled`

Automatic mutation is powerful, but broad matching creates risk.

Opt-in labeling keeps control with the application owner:

- only intended workloads are changed
- rollout risk is lower
- troubleshooting is easier

This is the safest way to start.

### Why require `block-ssd`

The policy is intentionally tied to one storage class because storage topology matters.

Different storage classes can have very different behavior:

- zonal vs non-zonal
- local vs network attached
- immediate vs delayed volume binding

Restricting the policy to `block-ssd` avoids applying zone spread to storage backends that are not compatible.

### Why require `WaitForFirstConsumer`

This is the key storage behavior for this pattern.

With `WaitForFirstConsumer`:

1. the scheduler chooses a node and zone first
2. the PVC is then provisioned in a compatible topology

Without it, a PV may be created before scheduling and may end up pinned to a zone that conflicts with the spread rule.

### Why skip workloads that already define `topologySpreadConstraints`

If a workload already has explicit spread settings, the policy should not override them.

That avoids:

- unexpected scheduling changes
- conflicts with vendor-provided manifests
- unclear ownership of placement logic

### Why allow `ha-zone-spread-exempt=true`

Some applications need special handling even if they use the right storage class.

Examples:

- vendor-managed databases
- brokers with strict rack-awareness logic
- applications with custom affinity rules

The exemption label creates a simple escape hatch.

### Why `maxSkew: 1`

This keeps the replica distribution reasonably balanced across zones.

Example with 3 replicas:

- good: `1 / 1 / 1`
- acceptable during some transitions: `2 / 1 / 0` is not acceptable when `DoNotSchedule` blocks further imbalance

The intent is to avoid heavy concentration in one zone.

### Why `whenUnsatisfiable: DoNotSchedule`

This is a strict policy by design.

If the cluster cannot satisfy the zone spread, it is better for the Pod to remain `Pending` than to silently schedule in a way that breaks the HA intent.

This makes problems visible early:

- missing zone labels
- storage topology mismatch
- insufficient capacity in one zone
- conflicting affinity rules

### Why `minDomains: 3`

This lab is explicitly designed for three zones: `dc1`, `dc2`, `dc3`.

`minDomains: 3` makes that design intent explicit to the scheduler. It prevents the policy from quietly accepting a reduced zone set as if the HA goal were still satisfied.

## Policy Spec

The current policy behavior is:

- resource kind: `StatefulSet`
- policy type: `ClusterPolicy`
- mutation style: `patchStrategicMerge`
- scope: cluster-wide, but effectively opt-in by label
- label selector: `ha-zone-spread=enabled`
- exemption label: `ha-zone-spread-exempt=true`
- storage filter: `volumeClaimTemplates[*].spec.storageClassName == block-ssd`
- replica filter: `replicas >= 2`
- spread target: `topology.kubernetes.io/zone`
- strictness: `DoNotSchedule`

## How To Use

1. Ensure nodes are labeled with `topology.kubernetes.io/zone`.
2. Ensure `block-ssd` exists and uses `WaitForFirstConsumer`.
3. Install Kyverno and apply the policy.
4. Create a `StatefulSet` with:
   - `ha-zone-spread=enabled`
   - `replicas >= 2`
   - `volumeClaimTemplates`
   - `storageClassName: block-ssd`
5. Verify the mutated `StatefulSet` contains `topologySpreadConstraints`.
6. Verify Pods land across zones and each replica gets its own PVC.

In this repo:

```sh
make kyverno-up
make kyverno-demo-status
make kyverno-verify
```

## Useful Cases

This policy is useful for:

- stateful applications with one volume per replica
- applications that replicate data across replicas
- HA test labs for zone failure simulation
- internal platforms where storage behavior is standardized
- teams that want a safe default without forcing every app team to hand-write spread rules

Examples:

- replicated databases
- brokers with one data volume per broker
- clustered caches with persistent storage
- internal stateful services built on `StatefulSet`

## Cases Where It Should Not Be Used

### Single shared `ReadWriteOnce` PVC

Do not use this when multiple Pods share one RWO claim.

Why:

- only one node can mount the volume read-write
- multi-zone scheduling will conflict with storage attachment

### Single-replica workloads

Do not use this for one replica.

Why:

- there is nothing to spread
- the rule adds scheduling constraints without HA benefit

### Workloads with local storage or fixed-zone storage

Do not use this when storage is tied to one node or one zone.

Why:

- storage locality and zone spread will conflict
- Pods may remain `Pending`

### Workloads with vendor-defined placement logic

Do not use this when the application already defines its own placement model.

Why:

- the application may already implement rack, zone, or quorum-aware scheduling assumptions
- combining multiple scheduling systems makes behavior harder to predict

### Workloads with explicit affinity/spread already defined

Do not use this if the existing placement rules are the intended source of truth.

Why:

- placement constraints are combined, not replaced
- the intersection may be too restrictive

### Stateless applications

Usually do not use this policy for stateless apps.

Why:

- stateless apps are better handled with a separate policy or deployment template
- the storage-specific checks in this design do not apply

## Failure Modes To Expect

Common failure modes:

- Pods stay `Pending` because one zone has no capacity
- Pods stay `Pending` because storage cannot provision in the chosen zone
- mutation does not happen because the workload is missing the opt-in label
- mutation does not happen because the workload uses another StorageClass
- mutation does not happen because the workload already defines spread constraints
- a workload is intentionally skipped because `ha-zone-spread-exempt=true`

These are not necessarily policy bugs. In many cases they are the intended safety behavior.

## Operational Guidance

- Start opt-in only.
- Keep this policy focused on a known-good storage class.
- Use a separate policy for stateless applications.
- Review application-level replication before calling the result "multi-zone HA".
- Add `PodDisruptionBudget`, readiness probes, and anti-affinity where appropriate.
- Document exception owners so exemption labels do not become permanent shortcuts without review.

## Important Limitation

This policy spreads Pods across zones. It does not replicate data.

Multi-zone HA for stateful applications requires both:

- replica placement across zones
- application or storage replication across zones

If the application does not replicate its own data, then spreading Pods alone does not create real multi-zone durability.

## Test Matrix

The table below summarizes the main scenarios this lab should cover.

| ID | Scenario | Workload Shape | Expected Result | Why It Matters |
| --- | --- | --- | --- | --- |
| TC01 | Happy path | `StatefulSet`, `ha-zone-spread=enabled`, `replicas=3`, `volumeClaimTemplates`, `storageClassName=block-ssd` | Policy mutates workload and spreads replicas across zones | Validates the intended design |
| TC02 | Higher replica count | Same as TC01 but `replicas=6` | Policy mutates and balances replicas with `maxSkew: 1` | Confirms scaling behavior |
| TC03 | Minimum valid replica count | Same as TC01 but `replicas=2` | Policy mutates because `replicas >= 2` | Confirms lower admission boundary |
| TC04 | Missing opt-in label | `StatefulSet` without `ha-zone-spread=enabled` | No mutation | Confirms opt-in scope |
| TC05 | Explicit exemption | `StatefulSet` with `ha-zone-spread-exempt=true` | No mutation | Confirms exception path |
| TC06 | Wrong StorageClass | `StatefulSet` uses a StorageClass other than `block-ssd` | No mutation | Confirms storage-class scoping |
| TC07 | No `volumeClaimTemplates` | `StatefulSet` has no PVC template | No mutation | Avoids matching non-stateful storage patterns |
| TC08 | Single replica | `replicas=1`, otherwise valid | No mutation | No HA value for one replica |
| TC09 | Existing spread rules | Workload already defines `topologySpreadConstraints` | No mutation | Avoids overriding app-owned policy |
| TC10 | Wrong workload kind | `Deployment` with opt-in label and PVC usage | No mutation | Confirms `StatefulSet`-only targeting |
| TC11 | Missing node zone labels | Valid `StatefulSet`, nodes not labeled with `topology.kubernetes.io/zone` | Pods may stay `Pending` or spread cannot be satisfied | Confirms cluster prerequisite |
| TC12 | Missing `block-ssd` | Valid `StatefulSet`, but StorageClass absent | PVC binding or scheduling fails | Confirms storage prerequisite |
| TC13 | Wrong `volumeBindingMode` | `block-ssd` exists but is not `WaitForFirstConsumer` | Possible storage-topology conflict, Pods may stay `Pending` | Confirms storage behavior dependency |
| TC14 | Zone capacity shortage | One zone lacks resources or eligible nodes | Some Pods remain `Pending` | Confirms strict `DoNotSchedule` behavior |
| TC15 | Conflicting affinity rules | Valid `StatefulSet` plus restrictive affinity | Scheduling may become unsatisfiable | Confirms combined scheduling semantics |
| TC16 | Local or fixed-zone storage | Storage backend is tied to node or zone | Pods may stay `Pending` | Confirms unsupported storage topology |
| TC17 | Vendor-managed workload | Vendor DB or broker with exemption label | No mutation | Confirms safe bypass for app-specific placement |
| TC18 | Kyverno readiness race | Apply policy immediately after Kyverno install | Policy apply should succeed once `kyverno-ready` completes | Confirms automation robustness |
| TC19 | Helm stuck uninstall state | Kyverno release metadata is stuck in `uninstalling` | `make kyverno-install` should tolerate stale Helm state if resources are healthy | Confirms lab recoverability |

## Suggested Test Coverage

Run these first:

- `TC01`: prove the policy works
- `TC04`: prove opt-in is required
- `TC05`: prove exemption works
- `TC06`: prove StorageClass scoping works
- `TC08`: prove single replica is skipped
- `TC09`: prove existing spread rules are respected
- `TC11`: prove node zone labels are a real prerequisite
- `TC13`: prove `WaitForFirstConsumer` matters
- `TC14`: prove strict scheduling behavior
- `TC15`: prove conflicting affinity can block scheduling

Run these when hardening the platform pattern:

- `TC02`: higher replica scale
- `TC10`: wrong workload kind
- `TC16`: local or fixed-zone storage
- `TC19`: Helm recovery path

## How To Validate Each Test

Core commands:

```sh
make kyverno-demo-status
make kyverno-verify
kubectl get sts -n kyverno-ha-demo -o yaml
kubectl get pods -n kyverno-ha-demo -o wide
kubectl get pvc -n kyverno-ha-demo
kubectl get nodes -L topology.kubernetes.io/zone
kubectl describe pod -n kyverno-ha-demo <pod-name>
```

Main checks:

- mutation happened:
  `kubectl get sts zone-spread-demo -n kyverno-ha-demo -o yaml | sed -n '/topologySpreadConstraints:/,/containers:/p'`
- replicas spread by zone:
  compare Pod node placement with `kubectl get nodes -L topology.kubernetes.io/zone`
- each replica has its own PVC:
  `kubectl get pvc -n kyverno-ha-demo`
- skipped mutation cases:
  verify `topologySpreadConstraints` is absent from the Pod template
- scheduling failures:
  use `kubectl describe pod` and inspect scheduler events

## Replica Count Examples

With 3 zones and `maxSkew: 1`, these distributions are valid:

| Replicas | Expected Balanced Distribution |
| --- | --- |
| 3 | `1 / 1 / 1` |
| 4 | `2 / 1 / 1` |
| 5 | `2 / 2 / 1` |
| 6 | `2 / 2 / 2` |
| 7 | `3 / 2 / 2` |

For a concrete `replicas > 3` test in this repo:

```sh
make kyverno-demo-scale
kubectl get pods -n kyverno-ha-demo -l app=zone-spread-scale-demo -o wide
kubectl get pvc -n kyverno-ha-demo | grep zone-spread-scale-demo
```

Expected result for the 6-replica demo:

- the StatefulSet is mutated by Kyverno
- 6 PVCs are created, one per replica
- Pod placement should converge close to `2 / 2 / 2` across `dc1`, `dc2`, and `dc3`

## Practical Scenario Set

If you want one compact but complete validation pass for this lab, use this order:

1. `TC01` happy path
2. `TC05` exemption path
3. `TC06` wrong StorageClass
4. `TC09` existing spread constraints
5. `TC14` zone shortage or unschedulable zone
6. `TC15` conflicting affinity
7. `TC19` Helm recovery path

That sequence covers:

- policy match
- policy skip
- exception handling
- storage-class filtering
- scheduler strictness
- interaction with other placement rules
- operational recovery of the Kyverno install path
