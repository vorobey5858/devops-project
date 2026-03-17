#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SOURCE="${CONFIG_SOURCE:-$REPO_ROOT/bootstrap/k3s/config.yaml}"
CONFIG_TARGET="${CONFIG_TARGET:-/etc/rancher/k3s/config.yaml}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/rancher/k3s/k3s.yaml}"
INSTALL_CHANNEL="${INSTALL_CHANNEL:-stable}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to install k3s." >&2
  exit 1
fi

sudo mkdir -p "$(dirname "$CONFIG_TARGET")"
sudo cp "$CONFIG_SOURCE" "$CONFIG_TARGET"

curl -sfL https://get.k3s.io | sudo env INSTALL_K3S_CHANNEL="$INSTALL_CHANNEL" sh -s - server

sudo chmod 644 "$KUBECONFIG_PATH"

echo "k3s has been installed."
echo "KUBECONFIG=$KUBECONFIG_PATH"
echo "Run: export KUBECONFIG=$KUBECONFIG_PATH"
kubectl --kubeconfig "$KUBECONFIG_PATH" get nodes
