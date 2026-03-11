#!/bin/sh

set -eu

echo "Checking required commands..."
for cmd in kubectl helm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

echo "Checking cluster access..."
kubectl cluster-info >/dev/null

echo "Checking worker zone labels..."
zone_count="$(kubectl get nodes -L topology.kubernetes.io/zone --no-headers | awk '$2 != "<none>" {count++} END {print count+0}')"
if [ "$zone_count" -lt 3 ]; then
  echo "Expected at least 3 nodes labeled with topology.kubernetes.io/zone" >&2
  kubectl get nodes -L topology.kubernetes.io/zone
  exit 1
fi
kubectl get nodes -L topology.kubernetes.io/zone

echo
echo "Checking StorageClass block-ssd..."
kubectl get storageclass block-ssd >/dev/null
binding_mode="$(kubectl get storageclass block-ssd -o jsonpath='{.volumeBindingMode}')"
if [ "$binding_mode" != "WaitForFirstConsumer" ]; then
  echo "StorageClass block-ssd must use WaitForFirstConsumer, found: $binding_mode" >&2
  exit 1
fi
kubectl get storageclass block-ssd

echo
echo "Preflight checks passed."
