# NATS JetStream With KEDA Lab

This lab creates a local scenario where:

- a single-node NATS server runs with JetStream enabled
- application workloads connect with credentials stored in Kubernetes Secrets
- KEDA scales a worker `Deployment` from JetStream consumer lag using the `nats-jetstream` scaler

## Important Constraint

KEDA's `nats-jetstream` scaler does not authenticate to NATS with the same client credentials as your publishers and consumers. It reads JetStream lag from the NATS monitoring endpoint on port `8222`.

In this lab:

- NATS application traffic uses `nats://nats.nats-jetstream-keda.svc.cluster.local:4222`
- the worker and publisher read `NATS_USER` and `NATS_PASSWORD` from a Secret
- KEDA reads `nats.nats-jetstream-keda.svc.cluster.local:8222` through a `TriggerAuthentication`

That split is intentional and matches the current scaler behavior documented by KEDA.

## Kubernetes Compatibility

The repo's `kind-config.yaml` uses Kubernetes `v1.26.15`.

KEDA's current latest releases require newer Kubernetes versions, so this lab pins `make keda-install` to chart version `2.12.0`, which is in the KEDA `v2.12` line that supports Kubernetes `1.26`.

## Layout

- `base/`: namespace, NATS server, app credentials, worker deployment, and KEDA resources
- `jobs/`: one-shot bootstrap and publisher jobs
- `tests/`: preflight and verification scripts

## Flow

Install KEDA, apply the lab, and create the stream plus durable consumer:

```sh
make nats-keda-up
```

Publish a message burst to create backlog:

```sh
make nats-keda-publish
```

Inspect scaling:

```sh
make nats-keda-status
make nats-keda-verify
kubectl logs -n nats-jetstream-keda deployment/orders-worker --tail=50
kubectl logs -n nats-jetstream-keda statefulset/nats --tail=50
```

Watch the worker scale based on lag:

```sh
kubectl get deployment orders-worker -n nats-jetstream-keda -w
kubectl get hpa -n nats-jetstream-keda -w
```

Clean up:

```sh
make nats-keda-down
```

## Scenario Details

- Stream: `ORDERS`
- Subject: `orders.created`
- Durable consumer: `orders-worker`
- Worker replicas: `0..10`
- Worker behavior: consume one message, ack it, then sleep to keep lag visible
- KEDA trigger:
  - `lagThreshold: 5`
  - `activationLagThreshold: 1`
  - `pollingInterval: 5`
  - `cooldownPeriod: 30`

## Security Notes

- The app path uses a Secret-backed username and password. This is a simple lab credential model, not operator/account JWT `.creds` authentication.
- The monitoring endpoint is exposed only as an in-cluster `ClusterIP` Service so KEDA can poll lag.
- If you need actual NATS JWT `.creds` authentication, the server side must also be configured with operator/account/user JWTs. That is a separate setup from the KEDA scaler and is not what this lab automates.
