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

echo "Checking Kubernetes server version..."
server_minor="$(
  kubectl version -o json 2>/dev/null \
    | tr -d '\n' \
    | sed -n 's/.*"serverVersion":{[^}]*"minor":"\([0-9][0-9]*\)[^"]*".*/\1/p'
)"
if [ -z "$server_minor" ]; then
  echo "Warning: unable to detect Kubernetes server minor version; continuing." >&2
elif [ "$server_minor" -ne 26 ]; then
  echo "Warning: this lab was authored around Kubernetes 1.26.x and KEDA 2.12.0; continuing on server minor $server_minor." >&2
fi

echo "Preflight checks passed."
