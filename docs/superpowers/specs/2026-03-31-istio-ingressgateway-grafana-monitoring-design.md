# Istio Ingressgateway Grafana Monitoring Lab Design

## Summary

This design adds a new lab named `istio-ingressgateway-grafana-monitoring` to this repository. The lab will run on local `kind`, but it is explicitly designed to demonstrate patterns that scale toward production usage where many ingress gateways emit large volumes of metrics.

The lab goal is not only to show Grafana charts, but to model a practical monitoring pipeline for Istio ingress gateways with these properties:

- keep both Istio service-level metrics and Envoy proxy-internal metrics
- prioritize ingress traffic, latency, and response health as the main operational view
- retain enough Envoy depth to inspect cluster count, cluster-level connection load, upstream request pressure, and related gateway internals
- reduce storage and scrape overhead by collecting only the metrics that matter
- express a retention strategy of at least 14 days, with clear guidance on local retention versus long-term production storage

## Problem Statement

The repo already contains labs that demonstrate one focused platform scenario per directory, with local verification scripts and `Makefile` entry points. There is currently no lab that shows how to observe Istio ingress gateways through Grafana while balancing metric depth against storage cost.

This gap matters because ingress gateways are often among the busiest components in a cluster. In environments with many gateways, raw Envoy metrics can become expensive quickly. A useful lab therefore needs to demonstrate not only how to scrape metrics, but how to:

- separate high-value metrics from observability noise
- constrain target scope so only intended gateways are scraped
- use metric relabeling and allowlists to reduce ingestion volume
- preserve at least two weeks of usable history without treating Prometheus like an infinite datastore

## Goals

- Add a new lab under `labs/istio-ingressgateway-grafana-monitoring/`.
- Install a monitoring stack with `kube-prometheus-stack`.
- Monitor Istio ingress gateways at two layers:
  - Istio standard metrics for service-level traffic and latency
  - Envoy metrics for deeper cluster and connection behavior
- Provide Grafana dashboards that separate operational overview from deep-dive proxy internals.
- Demonstrate metric filtering techniques that reduce storage cost while preserving useful signal.
- Configure Prometheus retention for a minimum of 14 days.
- Add shell-based preflight and verification scripts that match existing repo conventions.
- Extend the root `Makefile` with a consistent `up`, `down`, `status`, `preflight`, and `verify` workflow for this lab.

## Non-Goals

- This lab will not attempt to reproduce full production traffic scale inside `kind`.
- This lab will not provide long-term distributed metrics storage such as Thanos, Mimir, or VictoriaMetrics as part of the runnable local setup.
- This lab will not monitor every Envoy metric exposed by ingress gateways.
- This lab will not attempt to cover all Istio telemetry customization features.

## User Outcomes

After completing the lab, a user should be able to:

- deploy a local monitoring stack for Istio ingress gateways
- view request volume, response code distribution, and latency for ingress traffic
- inspect selected Envoy internals such as upstream cluster connections and request activity
- understand which metrics were deliberately kept versus dropped
- see how retention and storage settings constrain Prometheus usage
- map the local design to a higher-scale production rollout

## Lab Scope

The new lab will follow the repository pattern used by the existing labs:

- `README.md` explaining the scenario, layout, and end-to-end flow
- `tests/preflight.sh` for prerequisites and environmental checks
- `tests/verify.sh` for end-to-end verification
- manifests and Helm values grouped under the lab directory
- root `Makefile` targets for common operations

The lab will be runnable on `kind`, but its documents will clearly distinguish:

- what is directly implemented in local `kind`
- what is shown as a production extension strategy

## Proposed Directory Layout

The expected structure is:

```text
labs/istio-ingressgateway-grafana-monitoring/
  README.md
  GUIDE.md
  stack/
    values.yaml
  istio/
    ...
  rules/
    ...
  dashboards/
    ...
  tests/
    preflight.sh
    verify.sh
```

Purpose of each area:

- `stack/`: Helm values for `kube-prometheus-stack`, including retention, selectors, and Grafana provisioning hooks
- `istio/`: manifests related to ingressgateway metric discovery and any lab-specific selectors or monitoring objects
- `rules/`: Prometheus recording rules and any focused alert-style rules used for validation
- `dashboards/`: Grafana dashboard JSON or provisioning assets
- `tests/`: shell checks that validate prerequisites and lab behavior

## Architecture

The lab architecture has five functional layers:

1. `Ingressgateway targets`
   Istio ingress gateways expose both standard Istio telemetry and Envoy-level metrics.

2. `Discovery and scrape control`
   Prometheus discovers only the intended ingressgateway targets through explicit selectors. The design avoids broad scraping of unrelated workloads.

3. `Filtering and relabeling`
   Metric collection is reduced at ingestion time by keeping only high-value metric families and by reducing unhelpful label cardinality where possible.

4. `Aggregation`
   Recording rules precompute the most important operational views so Grafana does not rely heavily on expensive raw queries.

5. `Visualization and validation`
   Grafana surfaces the curated views, and shell verification scripts confirm that the expected metrics and filtering behavior are present.

## Metrics Model

The design uses three metric layers.

### Layer A: Istio Service-Level Metrics

This is the primary operational layer and the most important from the user's stated priorities.

Representative metrics include:

- request rate
- response code distribution
- request latency
- bytes sent and received
- TCP connection opens and closes

This layer answers questions such as:

- is ingress traffic healthy
- are latency percentiles rising
- are error codes increasing
- which gateway is seeing the most traffic

### Layer B: Envoy Deep-Dive Metrics

This layer exists for targeted gateway and upstream analysis. It is intentionally narrower than a full raw Envoy scrape.

Representative metric categories include:

- cluster request counters
- cluster active and total connections
- cluster connection failures and resets
- listener and downstream connection metrics
- overflow or pending-resource style indicators where relevant

This layer answers questions such as:

- how many clusters are active from the ingressgateway perspective
- which upstream clusters have the highest active connection count
- whether connection establishment is failing
- whether cluster-level request pressure matches service-level symptoms

### Layer C: Monitoring Cost Metrics

This layer tracks the observability system itself.

Representative metric categories include:

- active series
- ingestion rate
- head series and chunk pressure
- scrape samples before and after metric relabeling
- storage consumption and retention behavior

This layer answers questions such as:

- whether the chosen metric policy is sustainable
- how much ingestion load the gateway monitoring adds
- whether Prometheus is approaching storage pressure

## Filtering Strategy

Because the user expects many heavy ingress gateways in realistic deployments, the lab will emphasize a three-stage filtering model.

### Stage 1: Target Restriction

Prometheus will only scrape ingress gateways selected for this lab. The design will rely on explicit namespace, label, or monitoring-object selectors so that unrelated proxies are not scraped by default.

### Stage 2: Metric Family Restriction

Envoy metrics will be allowlisted by category rather than scraped wholesale. The lab will keep only the metric families necessary for:

- traffic and latency interpretation
- cluster-level connection visibility
- upstream request visibility
- a small set of gateway health indicators

Metrics unrelated to these goals will be dropped during ingestion.

### Stage 3: Label Cardinality Control

The design will reduce overly granular labels where they do not provide durable operational value. The exact rules may vary by metric family, but the policy direction is:

- prefer stable dimensions such as gateway name and namespace
- avoid storing overly dynamic dimensions for long-term analysis
- use aggregated recording rules for routine dashboards

## Retention and Storage Design

The local lab will configure Prometheus with:

- `retention: 14d`
- a `retentionSize` limit to cap on-disk growth

This reflects a practical principle: retention should be constrained by both time and size. The lab will not frame retention as a log-style rotation problem. Instead, the design aligns with Prometheus TSDB behavior:

- older blocks are deleted according to time and size policy
- block compaction reduces storage overhead over time
- long-term retention beyond the local Prometheus budget belongs in remote storage

The lab will demonstrate local retention settings directly, while the documentation will explain that production deployments with many heavy gateways should evaluate remote write or long-term metrics systems rather than extending a single Prometheus PVC indefinitely.

## Grafana Design

Grafana will ship with dashboards grouped into three views.

### 1. Ingress Overview

This dashboard is the main operational surface and will show:

- request rate
- success versus error code breakdown
- P50, P95, and P99 latency
- bytes in and out
- gateway-level traffic distribution

### 2. Envoy Deep Dive

This dashboard will focus on internal gateway behavior and selected upstream dimensions:

- visible upstream cluster count
- top clusters by active connections
- connection creation and failure trends
- cluster request pressure
- selected downstream or listener connection views

### 3. Monitoring Cost

This dashboard will show observability overhead and storage posture:

- active series
- scrape sample counts
- ingestion trends
- Prometheus storage use indicators
- rule-based aggregate visibility compared with raw metrics usage

## Verification Design

The lab will include two shell scripts.

### `tests/preflight.sh`

This script will validate prerequisites such as:

- `kind`, `kubectl`, and `helm` availability
- cluster reachability
- required namespaces or CRDs where appropriate
- storage prerequisites used by the monitoring stack

### `tests/verify.sh`

This script will validate the end-to-end monitoring flow. It will check:

- monitoring stack readiness
- Grafana and Prometheus availability
- ingressgateway scrape targets are up
- selected Istio metrics exist
- selected Envoy metrics exist
- at least part of the filtering policy is visibly active
- retention-related configuration is applied
- recording rules are loaded

The goal is not merely to confirm installation, but to prove that the design intent is working.

## Makefile Integration

The root `Makefile` will gain a consistent set of targets following the repo's current conventions. Expected commands include:

- `make istio-igw-monitoring-preflight`
- `make istio-igw-monitoring-up`
- `make istio-igw-monitoring-status`
- `make istio-igw-monitoring-verify`
- `make istio-igw-monitoring-down`

If needed, a small number of helper targets may also be added for stack installation, dashboard loading, or metric traffic generation, but the public workflow should remain simple.

## Production Mapping

The lab will explicitly document how the local design maps to larger environments.

Recommended production principles:

- restrict scrape targets before tuning anything else
- allowlist Envoy metric families instead of ingesting the full raw export
- use recording rules for common operational views
- keep retention bounded by both time and size
- move to remote storage for larger historical requirements
- treat raw high-cardinality metrics as an exception, not a default dashboard source

This keeps the local lab honest about scale while still making it useful as a design reference.

## Risks and Trade-Offs

### Risk: Envoy metric naming and availability may vary

Istio and Envoy versions can expose slightly different metric names or label shapes. The implementation should choose a tested subset and document the assumptions clearly.

### Risk: Local `kind` cannot simulate production load

The lab will show the right design patterns, but not realistic production traffic volume. This is acceptable because the local goal is design validation, not scale benchmarking.

### Risk: Over-filtering can hide useful signals

An aggressive allowlist reduces cost, but may remove useful debugging dimensions. The design accepts this trade-off and frames the kept metrics as an intentional baseline rather than a universal final set.

## Testing Strategy

Testing for this work is shell-based and infrastructure-oriented, aligned with the rest of the repository.

- run preflight before installation
- run the full lab bring-up target
- verify scrape health and dashboards indirectly through Prometheus and Kubernetes checks
- run the end-to-end verification target after changes

The implementation should avoid fragile checks that depend on large traffic volumes. Where traffic is required, it should use controlled, reproducible sample generation.

## Implementation Boundaries

This design is scoped tightly enough for a single implementation plan because it focuses on one lab with one monitoring scenario. It does not attempt to redesign the whole repository, nor does it include unrelated Istio service mesh topics outside ingressgateway observability.

## Open Design Decisions Resolved

The following decisions are fixed by this spec:

- The monitoring stack is `kube-prometheus-stack`.
- The lab keeps both Istio and Envoy metrics.
- The primary operational priority is traffic and latency, but connection-level and cost metrics are also first-class.
- The design is a dual-purpose artifact: runnable on `kind`, extensible toward production.
- Local retention is set to a minimum of 14 days and constrained by both time and size.

## Expected Deliverables

Implementation from this design should produce:

- a new lab directory with manifests, values, dashboards, and tests
- root `Makefile` entries for the lab workflow
- written usage documentation
- verification scripts proving both functional observability and basic cost controls
