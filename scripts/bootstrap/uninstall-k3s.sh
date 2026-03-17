#!/usr/bin/env bash
set -euo pipefail

if [[ ! -x /usr/local/bin/k3s-uninstall.sh ]]; then
  echo "k3s uninstall script was not found at /usr/local/bin/k3s-uninstall.sh" >&2
  exit 1
fi

sudo /usr/local/bin/k3s-uninstall.sh
