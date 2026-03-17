#!/bin/bash
#
# Deploy miscellaneous applications to the enclave applications cluster
#

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-~/.kube/enclave-applications.kubeconfig}"
export KUBECONFIG

##############################################################################
# HexGL — futuristic WebGL racing game
##############################################################################

echo "=== Deploying HexGL ==="

HEXGL_TMP="$(mktemp -d)"
trap 'rm -rf "$HEXGL_TMP"' EXIT

echo "Cloning HexGL repo..."
git clone --depth=1 https://github.com/jradtke-rgs/HexGL "$HEXGL_TMP"

bash "$HEXGL_TMP/scripts/deploy.sh" -k "$KUBECONFIG" -o example
