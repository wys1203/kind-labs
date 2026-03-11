#!/bin/sh

set -eu

echo "Nodes and zones:"
kubectl get nodes -L topology.kubernetes.io/zone
echo

echo "StorageClass block-ssd:"
kubectl get storageclass block-ssd -o yaml | sed -n '1,80p'
echo

echo "Demo pods and assigned nodes:"
kubectl get pods -n kyverno-ha-demo -o wide
echo

echo "Demo PVCs:"
kubectl get pvc -n kyverno-ha-demo -o wide
echo

echo "StatefulSet topologySpreadConstraints:"
kubectl get sts zone-spread-demo -n kyverno-ha-demo -o yaml | sed -n '/topologySpreadConstraints:/,/containers:/p'
