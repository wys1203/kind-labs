#!/bin/sh

set -eu

KIND_VERSION="${KIND_VERSION:-v0.23.0}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"

case "$arch" in
  x86_64|amd64)
    arch="amd64"
    ;;
  aarch64|arm64)
    arch="arm64"
    ;;
  *)
    echo "Unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

case "$os" in
  linux|darwin)
    ;;
  *)
    echo "Unsupported operating system: $os" >&2
    exit 1
    ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT INT TERM

url="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${os}-${arch}"

echo "Downloading ${url}"
curl -fsSL "$url" -o "$tmp_file"
chmod +x "$tmp_file"

if [ -w "$INSTALL_DIR" ]; then
  mv "$tmp_file" "${INSTALL_DIR}/kind"
else
  echo "Installing to ${INSTALL_DIR}/kind with sudo"
  sudo mv "$tmp_file" "${INSTALL_DIR}/kind"
fi

echo "kind installed to ${INSTALL_DIR}/kind"
"${INSTALL_DIR}/kind" --version
