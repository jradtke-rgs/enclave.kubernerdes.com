#!/bin/bash
set -euo pipefail

# install_RKE2_postboot.sh — Run once after RKE2 server starts on SL-Micro
#
# Sets up kubeconfig for root and sles users.
# Run manually after reboot if the automatic run did not complete:
#   sudo bash /var/lib/install_RKE2_postboot.sh

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Must be run as root."
  exit 1
fi

if [[ ! -f /root/.rke2.vars ]]; then
  echo "ERROR: /root/.rke2.vars not found. Was install_RKE2.sh run first?"
  exit 1
fi

source /root/.rke2.vars

echo "==> Waiting for rke2.yaml to appear..."
for i in $(seq 1 30); do
  [[ -f /etc/rancher/rke2/rke2.yaml ]] && break
  echo "  attempt ${i}/30..."
  sleep 10
done

if [[ ! -f /etc/rancher/rke2/rke2.yaml ]]; then
  echo "ERROR: /etc/rancher/rke2/rke2.yaml not found after waiting. Is rke2-server running?"
  exit 1
fi

mkdir -p /root/.kube
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
chmod 600 /root/.kube/config
sed -i "s/127.0.0.1/${MY_RKE2_VIP}/g" /root/.kube/config

mkdir -p ~sles/.kube 2>/dev/null || true
cp /root/.kube/config ~sles/.kube/config 2>/dev/null || true
chown -R sles ~sles/.kube/ 2>/dev/null || true

export PATH=$PATH:/opt/rke2/bin:/var/lib/rancher/rke2/bin
export KUBECONFIG=/root/.kube/config
echo "==> kubeconfig configured. Nodes:"
kubectl get nodes
