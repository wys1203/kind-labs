#!/bin/sh

set -eu

echo "Pods:"
kubectl get pods -n nats-jetstream-keda -o wide
echo

echo "ScaledObject and HPA:"
kubectl get scaledobject,hpa -n nats-jetstream-keda
echo

echo "NATS stream info:"
kubectl logs job/nats-jetstream-bootstrap -n nats-jetstream-keda --tail=50
echo

echo "Worker deployment:"
kubectl get deployment orders-worker -n nats-jetstream-keda -o wide
echo

echo "Recent worker logs:"
kubectl logs -n nats-jetstream-keda deployment/orders-worker --tail=50 || true
echo

echo "Publisher job status:"
kubectl get job nats-orders-publisher -n nats-jetstream-keda || true
