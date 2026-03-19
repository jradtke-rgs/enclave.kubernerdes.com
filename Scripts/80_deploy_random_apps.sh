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

##############################################################################
# chell-test — SUSE Security test workload (curl + wget, periodic fastly probe)
##############################################################################

echo "=== Deploying chell-test ==="

kubectl apply -f - <<'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: aperature-sci
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chell-test
  namespace: aperature-sci
  labels:
    app: chell-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: chell-test
  template:
    metadata:
      labels:
        app: chell-test
    spec:
      containers:
        - name: chell-test
          image: nicolaka/netshoot
          command: ["/bin/sh", "-c"]
          args:
            - |
              while true; do
                curl -svo /dev/null https://www.fastly.com 2>&1 | grep subjectAltName
                sleep 5
              done
EOF

echo "chell-test deployed to namespace aperature-sci"
echo "be sure to remove/delete later"
echo "kubectl delete namespace aperature-sci"
