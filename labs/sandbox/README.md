# Sandbox Lab

This folder is a starting point for lab scenarios on the local kind cluster.

## Structure

- `base/`: namespace-level baseline resources for the sandbox
- `apps/`: sample workloads to deploy into the sandbox
- `configs/`: ConfigMaps, Secrets templates, and app settings
- `ingress/`: ingress or gateway manifests
- `policies/`: RBAC, NetworkPolicy, PodSecurity, or admission-related manifests
- `tests/`: commands, manifests, or notes used to validate the lab

## Quick Start

Apply the baseline:

```sh
make sandbox-apply
```

Remove the sandbox:

```sh
make sandbox-delete
```
